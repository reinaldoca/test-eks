import { Router, Request, Response } from 'express';
import { trace, context, SpanStatusCode } from '@opentelemetry/api';
import { callServiceB } from '../services/serviceBClient';

const router = Router();

// Get tracer
const tracer = trace.getTracer('service-a');

// Counter metric (custom metric)
const meter = trace.getMeterProvider().getMeter('service-a');
const helloCounter = meter.createCounter('hello_requests_total', {
  description: 'Total number of hello requests',
});

// Main endpoint
router.get('/hello', async (req: Request, res: Response) => {
  // Create a span for this operation
  const span = tracer.startSpan('hello-handler', {
    attributes: {
      'http.method': req.method,
      'http.url': req.url,
      'http.target': req.path,
      'user.id': req.headers['x-user-id'] || 'anonymous',
      'user.type': req.headers['x-user-type'] || 'standard',
    },
  });

  // Use context with the span
  return context.with(trace.setSpan(context.active(), span), async () => {
    try {
      // Increment counter
      helloCounter.add(1, {
        'user.type': (req.headers['x-user-type'] as string) || 'standard',
        'http.method': req.method,
      });

      // Get query parameter
      const name = (req.query.name as string) || 'World';

      // Add event to span
      span.addEvent('processing_request', {
        name,
      });

      // Call Service B (demonstrating distributed tracing)
      const serviceBResponse = await callServiceB(name);

      // Add event after Service B call
      span.addEvent('service_b_called', {
        'service_b.response': JSON.stringify(serviceBResponse),
      });

      // Response
      const response = {
        message: `Hello ${name}!`,
        service: 'A',
        version: '1.0.0',
        timestamp: new Date().toISOString(),
        serviceBResponse,
        traceId: span.spanContext().traceId,
        spanId: span.spanContext().spanId,
      };

      res.json(response);

      // Mark span as successful
      span.setStatus({ code: SpanStatusCode.OK });
    } catch (error) {
      // Record exception in span
      span.recordException(error as Error);
      span.setStatus({
        code: SpanStatusCode.ERROR,
        message: error instanceof Error ? error.message : 'Unknown error',
      });

      console.error('❌ Error in hello handler:', error);

      res.status(500).json({
        error: 'Internal server error',
        message: error instanceof Error ? error.message : 'Unknown error',
        traceId: span.spanContext().traceId,
      });
    } finally {
      span.end();
    }
  });
});

// Echo endpoint (for testing)
router.post('/echo', async (req: Request, res: Response) => {
  const span = tracer.startSpan('echo-handler');

  return context.with(trace.setSpan(context.active(), span), async () => {
    try {
      const { message } = req.body;

      span.setAttribute('echo.message', message);

      res.json({
        echo: message,
        service: 'A',
        timestamp: new Date().toISOString(),
        traceId: span.spanContext().traceId,
      });

      span.setStatus({ code: SpanStatusCode.OK });
    } catch (error) {
      span.recordException(error as Error);
      span.setStatus({ code: SpanStatusCode.ERROR });

      res.status(500).json({
        error: 'Internal server error',
      });
    } finally {
      span.end();
    }
  });
});

export { router as helloRouter };
