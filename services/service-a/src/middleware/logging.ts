import { Request, Response, NextFunction } from 'express';
import winston from 'winston';
import { trace } from '@opentelemetry/api';

// Configure Winston logger
export const logger = winston.createLogger({
  level: process.env.LOG_LEVEL || 'info',
  format: winston.format.combine(
    winston.format.timestamp({ format: 'YYYY-MM-DD HH:mm:ss' }),
    winston.format.errors({ stack: true }),
    winston.format.json()
  ),
  defaultMeta: {
    service: 'service-a',
    version: '1.0.0',
    environment: process.env.NODE_ENV || 'development',
  },
  transports: [
    new winston.transports.Console({
      format: winston.format.combine(
        winston.format.colorize(),
        winston.format.printf(({ level, message, timestamp, ...metadata }) => {
          let msg = `${timestamp} [${level}]: ${message}`;
          if (Object.keys(metadata).length > 0) {
            msg += ` ${JSON.stringify(metadata)}`;
          }
          return msg;
        })
      ),
    }),
  ],
});

// Logging middleware
export const loggingMiddleware = (req: Request, res: Response, next: NextFunction) => {
  const start = Date.now();

  // Get current span for trace correlation
  const span = trace.getActiveSpan();
  const traceId = span?.spanContext().traceId || 'no-trace';
  const spanId = span?.spanContext().spanId || 'no-span';

  // Log incoming request
  logger.info('Incoming request', {
    method: req.method,
    url: req.url,
    path: req.path,
    query: req.query,
    headers: {
      'user-agent': req.headers['user-agent'],
      'x-request-id': req.headers['x-request-id'],
      'x-forwarded-for': req.headers['x-forwarded-for'],
    },
    traceId,
    spanId,
  });

  // Capture response
  const originalSend = res.send;
  res.send = function (body): Response {
    const duration = Date.now() - start;

    // Log completed request
    logger.info('Request completed', {
      method: req.method,
      url: req.url,
      path: req.path,
      statusCode: res.statusCode,
      duration: `${duration}ms`,
      contentLength: res.get('content-length') || 0,
      traceId,
      spanId,
    });

    return originalSend.call(this, body);
  };

  next();
};
