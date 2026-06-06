from fastapi import FastAPI
from pydantic_settings import BaseSettings
import redis
import json
import threading
import logging
from datetime import datetime
import os

from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
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

        RedisInstrumentor().instrument()
        _TELEMETRY_INITIALIZED = True
    except Exception as exc:
        logger.warning("OpenTelemetry setup failed (non-fatal): %s", exc)


setup_telemetry("notification-service")


class Settings(BaseSettings):
    redis_url: str
    service_name: str = "notification-service"
    alert_threshold: float = 10000.0

    class Config:
        env_file = ".env"


settings = Settings()
# root_path="/notifications" is required because the nginx ingress strips the /notifications
# prefix before forwarding to this service. Without root_path, FastAPI generates
# incorrect OpenAPI schema URLs and the /docs Swagger UI shows broken references.
# The app still handles routes as /alerts, /health — no change needed.
app = FastAPI(
    title="ClearLedger Notification Service",
    version="1.0.0",
    root_path="/notifications"
)

FastAPIInstrumentor.instrument_app(app, excluded_urls="health,metrics")
install_prometheus(app, settings.service_name)

# In-memory alert log — replace with a database in production
alerts = []


def start_subscriber():
    r = redis.from_url(settings.redis_url, decode_responses=True)
    pubsub = r.pubsub()
    pubsub.subscribe("ledger-events")
    logger.info("Subscribed to ledger-events channel")

    for message in pubsub.listen():
        if message["type"] == "message":
            try:
                event = json.loads(message["data"])
                if event.get("event") == "large_transaction":
                    alert = {
                        "alert_id": f"ALT-{len(alerts)+1:04d}",
                        "type": "LARGE_TRANSACTION",
                        "user_id": event["user_id"],
                        "amount": event["amount"],
                        "direction": event["direction"],
                        "transaction_id": event["transaction_id"],
                        "triggered_at": datetime.utcnow().isoformat(),
                        "message": (
                            f"Transaction of {event['amount']} "
                            f"({event['direction']}) exceeds threshold"
                        ),
                    }
                    alerts.append(alert)
                    logger.warning(
                        f"ALERT: {alert['type']} | user={alert['user_id']} "
                        f"| amount={alert['amount']}"
                    )
            except json.JSONDecodeError:
                logger.error("Failed to decode event")


@app.on_event("startup")
def startup():
    thread = threading.Thread(target=start_subscriber, daemon=True)
    thread.start()


@app.get("/health")
def health():
    return {"status": "ok", "service": settings.service_name}


@app.get("/alerts")
def get_alerts():
    return {"total": len(alerts), "alerts": alerts[-50:]}
