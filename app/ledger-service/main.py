from fastapi import FastAPI, HTTPException, Depends, status, Header
from pydantic import BaseModel
from pydantic_settings import BaseSettings
from sqlalchemy import create_engine, Column, String, Float, DateTime, Text
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker, Session
from datetime import datetime
from typing import Optional
import uuid
import os
import httpx
import redis
import json
import logging

from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.instrumentation.sqlalchemy import SQLAlchemyInstrumentor
from opentelemetry.instrumentation.httpx import HTTPXClientInstrumentor
from opentelemetry.instrumentation.redis import RedisInstrumentor
from opentelemetry.sdk.resources import Resource

from prom_metrics import install_prometheus

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

_TELEMETRY_INITIALIZED = False


def setup_telemetry(service_name: str):
    """
    Configure OpenTelemetry tracing. Reads OTEL_EXPORTER_OTLP_ENDPOINT
    from environment — defaults to the OTel Collector in-cluster address.
    Falls back silently if the collector is unreachable (dev/local mode).

    The Resource sets the service.name attribute so traces are labelled
    correctly in Grafana Tempo dashboards.
    """
    global _TELEMETRY_INITIALIZED
    if _TELEMETRY_INITIALIZED:
        return
    try:
        resource = Resource.create({
            "service.name": service_name,
            "service.version": "1.0.0",
            "deployment.environment": os.environ.get("ENV", "production"),
        })

        endpoint = os.environ.get(
            "OTEL_EXPORTER_OTLP_ENDPOINT",
            "http://otel-collector.monitoring.svc.cluster.local:4317",
        )

        provider = TracerProvider(resource=resource)
        exporter = OTLPSpanExporter(endpoint=endpoint, insecure=True)
        provider.add_span_processor(BatchSpanProcessor(exporter))
        trace.set_tracer_provider(provider)

        SQLAlchemyInstrumentor().instrument()
        HTTPXClientInstrumentor().instrument()
        RedisInstrumentor().instrument()
        _TELEMETRY_INITIALIZED = True
    except Exception as exc:
        logger.warning("OpenTelemetry setup failed (non-fatal): %s", exc)


setup_telemetry("ledger-service")


# ── Settings ──────────────────────────────────────────────────────────────────
class Settings(BaseSettings):
    auth_service_url: str
    redis_url: str
    notification_threshold: float = 10000.0
    service_name: str = "ledger-service"

    @property
    def database_url(self) -> str:
        file_path = os.environ.get("DATABASE_URL_FILE", "")
        if file_path and os.path.exists(file_path):
            return open(file_path).read().strip()
        vault_file = "/vault/secrets/database_url"
        if os.path.exists(vault_file):
            return open(vault_file).read().strip()
        return os.environ.get("DATABASE_URL", "")

    class Config:
        env_file = ".env"


settings = Settings()

# ── Database ──────────────────────────────────────────────────────────────────
engine = create_engine(settings.database_url)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()


class Transaction(Base):
    __tablename__ = "transactions"
    id = Column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id = Column(String, nullable=False, index=True)
    amount = Column(Float, nullable=False)
    direction = Column(String, nullable=False)  # credit / debit
    description = Column(Text, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)


Base.metadata.create_all(bind=engine)


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


# ── Redis ─────────────────────────────────────────────────────────────────────
redis_client = redis.from_url(settings.redis_url, decode_responses=True)


# ── Auth dependency ───────────────────────────────────────────────────────────
def get_current_user(authorization: str = Header(...)):
    try:
        resp = httpx.get(
            f"{settings.auth_service_url}/verify",
            headers={"Authorization": authorization},
            timeout=5.0,
        )
        if resp.status_code != 200:
            raise HTTPException(status_code=401, detail="Unauthorized")
        return resp.json()
    except httpx.RequestError:
        raise HTTPException(status_code=503, detail="Auth service unavailable")


# ── Schemas ───────────────────────────────────────────────────────────────────
class TransactionRequest(BaseModel):
    amount: float
    direction: str  # credit / debit
    description: Optional[str] = None


class TransactionResponse(BaseModel):
    id: str
    user_id: str
    amount: float
    direction: str
    description: Optional[str]
    created_at: datetime


class BalanceResponse(BaseModel):
    user_id: str
    balance: float


# ── App ───────────────────────────────────────────────────────────────────────
# root_path="/ledger" is required because the nginx ingress strips the /ledger
# prefix before forwarding to this service. Without root_path, FastAPI generates
# incorrect OpenAPI schema URLs and the /docs Swagger UI shows broken references.
# The app still handles routes as /transactions, /balance, /health — no change needed.
app = FastAPI(
    title="ClearLedger Ledger Service",
    version="1.0.0",
    root_path="/ledger"
)

FastAPIInstrumentor.instrument_app(app, excluded_urls="health,metrics")
install_prometheus(app, settings.service_name)

# With OTel instrumentation, POST /transactions generates a trace spanning
# ledger-service → auth-service /verify → postgres INSERT → redis PUBLISH.
# Visible in Grafana → Explore → Tempo (search: service.name = "ledger-service").


@app.get("/health")
def health():
    return {"status": "ok", "service": settings.service_name}


@app.post(
    "/transactions",
    response_model=TransactionResponse,
    status_code=status.HTTP_201_CREATED,
)
def create_transaction(
    req: TransactionRequest,
    db: Session = Depends(get_db),
    user: dict = Depends(get_current_user),
):
    if req.amount <= 0:
        raise HTTPException(
            status_code=422,
            detail="amount must be positive",
        )
    if req.direction not in ("credit", "debit"):
        raise HTTPException(
            status_code=400, detail="direction must be credit or debit"
        )

    tx = Transaction(
        user_id=user["user_id"],
        amount=req.amount,
        direction=req.direction,
        description=req.description,
    )
    db.add(tx)
    db.commit()
    db.refresh(tx)

    if req.amount >= settings.notification_threshold:
        event = {
            "event": "large_transaction",
            "user_id": user["user_id"],
            "amount": req.amount,
            "direction": req.direction,
            "transaction_id": tx.id,
            "timestamp": tx.created_at.isoformat(),
        }
        redis_client.publish("ledger-events", json.dumps(event))
        logger.info(f"Published large_transaction event for tx {tx.id}")

    logger.info(
        f"Transaction created: {tx.id} | {user['user_id']} | {req.direction} {req.amount}"
    )
    return tx


@app.get("/balance", response_model=BalanceResponse)
def get_balance(
    db: Session = Depends(get_db),
    user: dict = Depends(get_current_user),
):
    txs = db.query(Transaction).filter(Transaction.user_id == user["user_id"]).all()
    balance = sum(
        tx.amount if tx.direction == "credit" else -tx.amount for tx in txs
    )
    return BalanceResponse(user_id=user["user_id"], balance=round(balance, 2))


@app.get("/transactions", response_model=list[TransactionResponse])
def list_transactions(
    db: Session = Depends(get_db),
    user: dict = Depends(get_current_user),
):
    return (
        db.query(Transaction)
        .filter(Transaction.user_id == user["user_id"])
        .order_by(Transaction.created_at.desc())
        .limit(100)
        .all()
    )


@app.get("/transactions/{transaction_id}", response_model=TransactionResponse)
def get_transaction(
    transaction_id: str,
    db: Session = Depends(get_db),
    user: dict = Depends(get_current_user),
):
    """Return a single transaction only if it belongs to the authenticated user (BOLA control)."""
    tx = db.query(Transaction).filter(Transaction.id == transaction_id).first()
    if tx is None:
        raise HTTPException(status_code=404, detail="Transaction not found")
    if tx.user_id != user["user_id"]:
        raise HTTPException(
            status_code=403,
            detail="Forbidden — cannot access another user's transaction",
        )
    return tx
