FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORTAI_HOST=0.0.0.0 \
    PORTAI_PORT=8000

WORKDIR /app
LABEL org.opencontainers.image.title="PortAI DT Mobile RL backend" \
      org.opencontainers.image.description="Headless port-traffic policy training and held-out replay service" \
      org.opencontainers.image.licenses="MIT"
COPY requirements.txt ./
RUN python -m pip install --no-cache-dir --requirement requirements.txt
COPY portai_rl ./portai_rl
COPY config ./config
COPY data ./data
RUN mkdir -p /app/artifacts && useradd --create-home --uid 10001 portai && chown -R portai:portai /app/artifacts
USER portai
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=3)"]
CMD ["python", "-m", "portai_rl.api"]
