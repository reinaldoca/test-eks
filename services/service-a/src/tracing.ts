import { NodeSDK } from '@opentelemetry/sdk-node';
import { getNodeAutoInstrumentations } from '@opentelemetry/auto-instrumentations-node';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-proto';
import { OTLPMetricExporter } from '@opentelemetry/exporter-metrics-otlp-proto';
import { Resource } from '@opentelemetry/resources';
import { SemanticResourceAttributes } from '@opentelemetry/semantic-conventions';
import { BatchSpanProcessor } from '@opentelemetry/sdk-trace-base';
import { PeriodicExportingMetricReader } from '@opentelemetry/sdk-metrics';
import { diag, DiagConsoleLogger, DiagLogLevel } from '@opentelemetry/api';

// Enable debug logging in development
if (process.env.NODE_ENV === 'development') {
  diag.setLogger(new DiagConsoleLogger(), DiagLogLevel.DEBUG);
}

// Resource attributes (service identity)
const resource = new Resource({
  [SemanticResourceAttributes.SERVICE_NAME]: process.env.OTEL_SERVICE_NAME || 'service-a',
  [SemanticResourceAttributes.SERVICE_VERSION]: process.env.OTEL_SERVICE_VERSION || '1.0.0',
  [SemanticResourceAttributes.DEPLOYMENT_ENVIRONMENT]: process.env.NODE_ENV || 'development',
  'service.instance.id': process.env.HOSTNAME || 'unknown',
  'cloud.provider': 'aws',
  'cloud.platform': 'aws_eks',
  'cloud.region': process.env.AWS_REGION || 'us-east-1',
  'k8s.namespace.name': process.env.K8S_NAMESPACE || 'production',
  'k8s.pod.name': process.env.K8S_POD_NAME || 'unknown',
  'k8s.container.name': process.env.K8S_CONTAINER_NAME || 'service-a',
});

// OTLP endpoint
const otlpEndpoint = process.env.OTEL_EXPORTER_OTLP_ENDPOINT || 'http://otel-collector.observability:4318';

// Trace exporter
const traceExporter = new OTLPTraceExporter({
  url: `${otlpEndpoint}/v1/traces`,
  headers: {
    'X-Scope-OrgID': 'production',
  },
  timeoutMillis: 10000,
});

// Metric exporter
const metricExporter = new OTLPMetricExporter({
  url: `${otlpEndpoint}/v1/metrics`,
  headers: {
    'X-Scope-OrgID': 'production',
  },
  timeoutMillis: 10000,
});

// Configure SDK
const sdk = new NodeSDK({
  resource,
  traceExporter,
  metricReader: new PeriodicExportingMetricReader({
    exporter: metricExporter,
    exportIntervalMillis: 60000, // Export every 60 seconds
  }),
  spanProcessor: new BatchSpanProcessor(traceExporter, {
    maxQueueSize: 2048,
    scheduledDelayMillis: 5000,
    exportTimeoutMillis: 30000,
  }),
  instrumentations: [
    getNodeAutoInstrumentations({
      '@opentelemetry/instrumentation-express': {
        enabled: true,
        requestHook: (span, request) => {
          // Add custom attributes
          span.setAttribute('http.user_agent', request.headers['user-agent'] || 'unknown');
          span.setAttribute('http.x_forwarded_for', request.headers['x-forwarded-for'] || 'unknown');
        },
      },
      '@opentelemetry/instrumentation-http': {
        enabled: true,
        ignoreIncomingPaths: ['/health', '/metrics'],
        requestHook: (span, request) => {
          span.setAttribute('http.flavor', '1.1');
        },
      },
      '@opentelemetry/instrumentation-aws-sdk': {
        enabled: true,
        suppressInternalInstrumentation: true,
      },
    }),
  ],
});

// Start SDK
sdk.start();

console.log('🔍 OpenTelemetry instrumentation initialized');
console.log(`📊 Service: ${resource.attributes[SemanticResourceAttributes.SERVICE_NAME]}`);
console.log(`📈 OTLP Endpoint: ${otlpEndpoint}`);

// Handle graceful shutdown
process.on('SIGTERM', async () => {
  console.log('🛑 SIGTERM received, shutting down OpenTelemetry SDK...');
  try {
    await sdk.shutdown();
    console.log('✅ OpenTelemetry SDK shutdown complete');
  } catch (error) {
    console.error('❌ Error shutting down OpenTelemetry SDK:', error);
  } finally {
    process.exit(0);
  }
});

process.on('SIGINT', async () => {
  console.log('🛑 SIGINT received, shutting down OpenTelemetry SDK...');
  try {
    await sdk.shutdown();
    console.log('✅ OpenTelemetry SDK shutdown complete');
  } catch (error) {
    console.error('❌ Error shutting down OpenTelemetry SDK:', error);
  } finally {
    process.exit(0);
  }
});

export { sdk };
