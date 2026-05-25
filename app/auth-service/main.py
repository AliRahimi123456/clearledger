from fastapi import FastAPI, HTTPException, Depends, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from pydantic import BaseModel, EmailStr
from pydantic_settings import BaseSettings
from sqlalchemy import create_engine, Column, String, DateTime, Boolean
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker, Session
from passlib.context import CryptContext
from jose import JWTError, jwt
from datetime import datetime, timedelta
import uuid
import os
import logging

from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.instrumentation.sqlalchemy import SQLAlchemyInstrumentor
from opentelemetry.instrumentation.httpx import HTTPXClientInstrumentor
from opentelemetry.sdk.resources import Resource

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

        # Auto-instrument SQLAlchemy — every DB query becomes a child span
        SQLAlchemyInstrumentor().instrument()
        # Auto-instrument HTTPX — outbound calls to other services become spans
        HTTPXClientInstrumentor().instrument()
        _TELEMETRY_INITIALIZED = True
    except Exception as exc:
        logger.warning("OpenTelemetry setup failed (non-fatal): %s", exc)


setup_telemetry("auth-service")


# ── Settings ──────────────────────────────────────────────────────────────────
# Vault-aware settings: reads from file if present, falls back to env var.
# This means the same codebase works in:
#   Stage 0-4: reads DATABASE_URL env var directly (K8s Secret)
#   Stage 5+:  reads /vault/secrets/database_url file (Vault injection)
# No code change required between stages — only manifest changes.

def _read_secret(file_env: str, fallback_env: str) -> str:
    """
    Read a secret from a Vault-injected file path (stored in file_env env var),
    falling back to a direct env var (fallback_env) for local/pre-Vault stages.
    """
    file_path = os.environ.get(file_env, "")
    if file_path and os.path.exists(file_path):
        value = open(file_path).read().strip()
        if value:
            return value
    return os.environ.get(fallback_env, "")


class Settings(BaseSettings):
    service_name: str = "auth-service"
    jwt_algorithm: str = "HS256"
    jwt_expire_minutes: int = 60

    # These properties are not declared as BaseSettings fields because
    # their values come from files (Vault) rather than direct env vars.
    # Declaring them as fields would break pydantic-settings validation
    # when the env var doesn't exist.

    @property
    def database_url(self) -> str:
        return _read_secret("DATABASE_URL_FILE", "DATABASE_URL")

    @property
    def jwt_secret(self) -> str:
        return _read_secret("JWT_SECRET_FILE", "JWT_SECRET")

    class Config:
        env_file = ".env"


settings = Settings()


def _load_jwt_secrets() -> list[str]:
    """
    Support safe JWT secret rotation with overlap.

    The Vault-injected jwt_secret file may contain multiple secrets separated by newlines.
    - The first secret is used for signing new tokens.
    - Any secret is accepted for verification.
    """
    raw = settings.jwt_secret
    return [s.strip() for s in raw.splitlines() if s.strip()]


# Database engine can be rotated without pod restart by reloading the Vault-injected file.
_ENGINE_URL: str | None = None
_ENGINE = None
_SessionLocal = None


def _ensure_engine() -> None:
    global _ENGINE_URL, _ENGINE, _SessionLocal
    url = settings.database_url
    if not url:
        raise RuntimeError("DATABASE_URL is not set")
    if _ENGINE is None or _ENGINE_URL != url:
        if _ENGINE is not None:
            _ENGINE.dispose()
        _ENGINE_URL = url
        _ENGINE = create_engine(url)
        _SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=_ENGINE)

# ── Database ──────────────────────────────────────────────────────────────────
_ensure_engine()
Base = declarative_base()


class User(Base):
    __tablename__ = "users"
    id = Column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    email = Column(String, unique=True, index=True, nullable=False)
    hashed_password = Column(String, nullable=False)
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime, default=datetime.utcnow)


Base.metadata.create_all(bind=_ENGINE)


def get_db():
    _ensure_engine()
    db = _SessionLocal()
    try:
        yield db
    finally:
        db.close()


# ── Auth utilities ─────────────────────────────────────────────────────────────
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
security = HTTPBearer()


def hash_password(password: str) -> str:
    return pwd_context.hash(password)


def verify_password(plain: str, hashed: str) -> bool:
    return pwd_context.verify(plain, hashed)


def create_token(user_id: str, email: str) -> str:
    expires = datetime.utcnow() + timedelta(minutes=settings.jwt_expire_minutes)
    payload = {
        "sub": user_id,
        "email": email,
        "exp": expires,
        "iat": datetime.utcnow(),
        "iss": settings.service_name
    }
    secrets = _load_jwt_secrets()
    if not secrets:
        raise RuntimeError("JWT secret is not set")
    return jwt.encode(payload, secrets[0], algorithm=settings.jwt_algorithm)


def decode_token(token: str) -> dict:
    try:
        secrets = _load_jwt_secrets()
        if not secrets:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="JWT secret not configured",
            )
        last_err: Exception | None = None
        for secret in secrets:
            try:
                return jwt.decode(
                    token,
                    secret,
                    algorithms=[settings.jwt_algorithm],
                )
            except JWTError as ex:
                last_err = ex
                continue
        raise last_err or JWTError()
    except JWTError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired token"
        )


# ── Schemas ───────────────────────────────────────────────────────────────────
class RegisterRequest(BaseModel):
    email: EmailStr
    password: str


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user_id: str


class VerifyResponse(BaseModel):
    user_id: str
    email: str
    valid: bool


# ── App ───────────────────────────────────────────────────────────────────────
# root_path="/auth" is required because the nginx ingress strips the /auth prefix
# before forwarding to this service. Without root_path, FastAPI generates
# incorrect OpenAPI schema URLs and the /docs page breaks.
# The app itself still handles routes as /register, /login, /verify, /health.
app = FastAPI(
    title="ClearLedger Auth Service",
    version="1.0.0",
    root_path="/auth"
)

# Auto-instrument FastAPI — every HTTP request generates a root span.
# /health is excluded so liveness/readiness probes stay lightweight.
FastAPIInstrumentor.instrument_app(app, excluded_urls="health")

# With OTel instrumentation, every request to /login generates a trace:
# POST /login (auth-service)
#   └── SELECT * FROM users WHERE email=? (postgres, ~2ms)
# This trace is visible in Grafana → Explore → Tempo data source.
# Correlation ID is propagated via W3C TraceContext headers so a
# ledger-service request that calls auth-service shows as one trace.


@app.get("/health")
def health():
    return {"status": "ok", "service": settings.service_name}


@app.post("/register", status_code=status.HTTP_201_CREATED)
def register(req: RegisterRequest, db: Session = Depends(get_db)):
    existing = db.query(User).filter(User.email == req.email).first()
    if existing:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Email already registered"
        )
    user = User(email=req.email, hashed_password=hash_password(req.password))
    db.add(user)
    db.commit()
    db.refresh(user)
    logger.info(f"New user registered: {user.id}")
    return {"user_id": user.id, "email": user.email}


@app.post("/login", response_model=TokenResponse)
def login(req: LoginRequest, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.email == req.email).first()
    if not user or not verify_password(req.password, user.hashed_password):
        logger.warning(f"Failed login attempt for {req.email}")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid credentials"
        )
    token = create_token(user.id, user.email)
    logger.info(f"User logged in: {user.id}")
    return TokenResponse(access_token=token, user_id=user.id)


@app.get("/verify", response_model=VerifyResponse)
def verify(credentials: HTTPAuthorizationCredentials = Depends(security)):
    payload = decode_token(credentials.credentials)
    return VerifyResponse(
        user_id=payload["sub"],
        email=payload["email"],
        valid=True
    )
