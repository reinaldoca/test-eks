import axios, { AxiosError } from 'axios';
import { trace, context, propagation, SpanStatusCode } from '@opentelemetry/api';
import CircuitBreaker from 'opossum';

const tracer = trace.getTracer('service-a');

// Service B URL from environment variable
const SERVICE_B_URL = process.env.SERVICE_B_URL || 'http://service-b:8080';

// Circuit breaker function
const serviceBCall = async (name: string): Promise<any> => {
  const span = tracer.startSpan('call-service-b', {
    attributes: {
      'peer.service': 'service-b',
      'network.protocol.name': 'http',
      'http.url': `${SERVICE_B_URL}/api/v1/service-b/hello`,
    },
  });

  return context.with(trace.setSpan(context.active(), span), async () => {
    try {
      // Inject W3C Trace Context into headers
      const headers: Record<string, string> = {};
      propagation.inject(context.active(), headers);

      // Add custom headers
      headers['X-Request-Id'] = span.spanContext().traceId;
      headers['Content-Type'] = 'application/json';
      headers['X-Source-Service'] = 'service-a';

      // Log outgoing request
      console.log(`📤 Calling Service B: ${SERVICE_B_URL}/api/v1/service-b/hello?name=${name}`);
      console.log(`📋 Trace Context:`, headers);

      // Make HTTP request
      const response = await axios.get(`${SERVICE_B_URL}/api/v1/service-b/hello`, {
        params: { name },
        headers,
        timeout: 5000,
      });

      // Add response details to span
      span.setAttribute('http.status_code', response.status);
      span.setAttribute('http.response_content_length', JSON.stringify(response.data).length);

      span.setStatus({ code: SpanStatusCode.OK });

      return response.data;
    } catch (error) {
      // Record exception
      span.recordException(error as Error);
      span.setStatus({
        code: SpanStatusCode.ERROR,
        message: error instanceof Error ? error.message : 'Unknown error',
      });

      // Add error details
      if (axios.isAxiosError(error)) {
        const axiosError = error as AxiosError;
        span.setAttribute('http.status_code', axiosError.response?.status || 0);
        span.setAttribute('error.type', axiosError.code || 'unknown');
      }

      throw error;
    } finally {
      span.end();
    }
  });
};

// Circuit breaker configuration
const breaker = new CircuitBreaker(serviceBCall, {
  timeout: 5000, // 5 seconds timeout
  errorThresholdPercentage: 50, // Open circuit if 50% of requests fail
  resetTimeout: 30000, // Try to close circuit after 30 seconds
  rollingCountTimeout: 10000, // Window for error calculation
  rollingCountBuckets: 10,
  name: 'service-b',
  // Only consider network errors and 5xx as failures
  errorFilter: (error: Error) => {
    if (axios.isAxiosError(error)) {
      const status = error.response?.status || 0;
      // Only count 5xx errors and network errors as failures
      return status >= 500 || status === 0;
    }
    return true;
  },
});

// Circuit breaker event listeners
breaker.on('open', () => {
  console.warn('🔴 Circuit Breaker OPENED for Service B');
});

breaker.on('halfOpen', () => {
  console.info('🟡 Circuit Breaker HALF-OPEN for Service B');
});

breaker.on('close', () => {
  console.info('🟢 Circuit Breaker CLOSED for Service B');
});

breaker.on('fallback', () => {
  console.warn('⚠️  Circuit Breaker FALLBACK triggered for Service B');
});

// Fallback function
breaker.fallback((name: string) => {
  console.warn('🔄 Using fallback response for Service B');

  // Create a span for fallback
  const span = tracer.startSpan('service-b-fallback');
  span.setAttribute('fallback.used', true);
  span.setAttribute('fallback.reason', 'circuit_breaker_open');
  span.setStatus({ code: SpanStatusCode.OK });
  span.end();

  return {
    message: 'Service B is currently unavailable (using fallback)',
    status: 'degraded',
    service: 'B',
    fallback: true,
    timestamp: new Date().toISOString(),
  };
});

// Export the circuit breaker fire function
export const callServiceB = async (name: string): Promise<any> => {
  try {
    return await breaker.fire(name);
  } catch (error) {
    console.error('❌ Circuit breaker failed to call Service B:', error);
    // Fallback will be triggered automatically
    throw error;
  }
};

// Export circuit breaker stats for monitoring
export const getCircuitBreakerStats = () => ({
  name: breaker.name,
  state: breaker.opened ? 'OPEN' : breaker.halfOpen ? 'HALF_OPEN' : 'CLOSED',
  stats: breaker.stats,
});
