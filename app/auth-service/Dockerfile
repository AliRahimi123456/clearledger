# syntax=docker/dockerfile:1
FROM python:3.13-slim

RUN groupadd -r appuser && useradd -r -g appuser appuser

WORKDIR /app

COPY requirements.txt .
RUN --mount=type=cache,target=/root/.cache/pip,id=clearledger-pip,sharing=locked \
    pip install --timeout 120 --retries 10 --no-cache-dir -r requirements.txt

COPY prom_metrics.py main.py ./

USER appuser

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD python -c "import httpx; httpx.get('http://localhost:8000/health')"

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
