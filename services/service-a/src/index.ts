// IMPORTANT: tracing must be imported FIRST before any other code
import './tracing';
import { startServer } from './app';

const PORT = process.env.PORT || 8080;

startServer(Number(PORT))
  .then(() => {
    console.log('');
    console.log('='.repeat(60));
    console.log(`🚀 Service A running on port ${PORT}`);
    console.log(`📊 Health: http://localhost:${PORT}/health`);
    console.log(`📈 Metrics: http://localhost:${PORT}/metrics`);
    console.log(`🔍 OpenTelemetry: ${process.env.OTEL_EXPORTER_OTLP_ENDPOINT || 'http://otel-collector.observability:4318'}`);
    console.log(`🌍 Environment: ${process.env.NODE_ENV || 'development'}`);
    console.log('='.repeat(60));
    console.log('');
  })
  .catch((error) => {
    console.error('❌ Failed to start server:', error);
    process.exit(1);
  });

// Handle uncaught exceptions
process.on('uncaughtException', (error) => {
  console.error('❌ Uncaught Exception:', error);
  process.exit(1);
});

// Handle unhandled promise rejections
process.on('unhandledRejection', (reason, promise) => {
  console.error('❌ Unhandled Rejection at:', promise, 'reason:', reason);
  process.exit(1);
});
