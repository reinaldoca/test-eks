# Service A - FinTech Microservice

Microservicio Node.js/TypeScript con instrumentación completa de OpenTelemetry, circuit breaker, y comunicación con Service B.

## 🚀 Features

- **OpenTelemetry**: Instrumentación automática con traces, metrics, y logs correlacionados
- **Circuit Breaker**: Protección contra fallos en cascada con fallback automático
- **W3C Trace Context**: Propagación de contexto de tracing entre servicios
- **Health Checks**: Endpoints `/health`, `/ready`, `/live` para Kubernetes probes
- **Structured Logging**: Winston con correlación de trace IDs
- **TypeScript**: Type safety completo
- **Production-ready**: Dockerfile multi-stage con distroless base

## 📦 Installation

```bash
npm install
```

## 🛠️ Development

```bash
# Compilar TypeScript
npm run build

# Modo desarrollo (con watch)
npm run dev:watch

# Lint
npm run lint

# Format
npm run format

# Tests
npm run test
npm run test:coverage
```

## 🐳 Docker

```bash
# Build
docker build -t service-a:latest .

# Run
docker run -p 8080:8080 \
  -e OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4318 \
  -e SERVICE_B_URL=http://service-b:8080 \
  service-a:latest
```

## 🌐 API Endpoints

### Health Checks
- `GET /health` - Health check
- `GET /health/ready` - Readiness probe
- `GET /health/live` - Liveness probe

### Business Logic
- `GET /api/v1/service-a/hello?name=World` - Main endpoint (calls Service B)
- `POST /api/v1/service-a/echo` - Echo endpoint

### Observability
- `GET /metrics` - Prometheus metrics

## 🔍 OpenTelemetry Configuration

El servicio se instrumenta automáticamente via OpenTelemetry SDK:

- **Traces**: Exportados a OTLP collector
- **Metrics**: Exportados cada 60 segundos
- **Resource Attributes**: service.name, service.version, cloud.provider, k8s.*

### Environment Variables

```bash
OTEL_SERVICE_NAME=service-a
OTEL_SERVICE_VERSION=1.0.0
OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector.observability:4318
NODE_ENV=production
PORT=8080
SERVICE_B_URL=http://service-b:8080
LOG_LEVEL=info
```

## 🔄 Circuit Breaker

El cliente de Service B usa un circuit breaker con:

- **Timeout**: 5 segundos
- **Error Threshold**: 50% (abre circuito si 50%+ de requests fallan)
- **Reset Timeout**: 30 segundos (intenta cerrar el circuito)
- **Fallback**: Respuesta degradada automática

Estados del circuito:
- 🟢 **CLOSED**: Funcionamiento normal
- 🟡 **HALF_OPEN**: Probando si el servicio se recuperó
- 🔴 **OPEN**: Circuito abierto, usando fallback

## 📊 Observability Flow

```
Service A Request
  ↓
Create Span (hello-handler)
  ↓
Call Service B (with W3C Trace Context)
  ↓
  ├─→ Success: Add event to span
  └─→ Failure: Record exception, trigger fallback
  ↓
Log with trace correlation
  ↓
Export to OTLP Collector
  ↓
  ├─→ Tempo (traces)
  ├─→ Prometheus (metrics)
  └─→ Loki (logs)
```

## 🧪 Testing Service-to-Service Communication

```bash
# Hacer request a Service A
curl http://localhost:8080/api/v1/service-a/hello?name=Test

# Response incluye traceId para debugging
{
  "message": "Hello Test!",
  "service": "A",
  "timestamp": "2024-...",
  "serviceBResponse": {
    "message": "Hello Test from Service B!",
    "service": "B"
  },
  "traceId": "abc123..."
}
```

## 🛡️ Security

- **Non-root user**: Corre como user `nonroot` (UID 65532)
- **Distroless**: Base image sin shell ni package managers
- **Read-only filesystem**: Compatible (logs a stdout)
- **No secrets in code**: Secrets via environment variables o External Secrets Operator

## 📈 Performance

- **Startup time**: < 5 segundos
- **Memory footprint**: ~128 MB en reposo
- **Response time**: P95 < 50ms (sin llamada a Service B)
- **Throughput**: ~1000 req/s en instancia m5.large

## 🔗 Related Services

- **Service B**: http://service-b:8080
- **OTEL Collector**: http://otel-collector.observability:4318
- **Grafana**: https://grafana.fintech.com

## 📝 License

Proprietary - FinTech Platform Team
