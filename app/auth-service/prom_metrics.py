from prometheus_client import CONTENT_TYPE_LATEST, Counter, generate_latest
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response

HTTP_REQUESTS = Counter(
    "http_requests_total",
    "Total HTTP requests",
    ["app", "method", "status"],
)


class PrometheusMiddleware(BaseHTTPMiddleware):
    def __init__(self, app, service_name: str):
        super().__init__(app)
        self.service_name = service_name

    async def dispatch(self, request: Request, call_next):
        if request.url.path == "/metrics":
            return await call_next(request)
        response = await call_next(request)
        HTTP_REQUESTS.labels(
            app=self.service_name,
            method=request.method,
            status=str(response.status_code),
        ).inc()
        return response


def install_prometheus(app, service_name: str) -> None:
    app.add_middleware(PrometheusMiddleware, service_name=service_name)

    @app.get("/metrics", include_in_schema=False)
    def metrics():
        return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)
