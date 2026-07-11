import express, { Express, Request, Response, NextFunction } from 'express';
import { healthRouter } from './routes/health';
import { helloRouter } from './routes/hello';
import { metricsRouter } from './routes/metrics';
import { errorHandler } from './middleware/errorHandler';
import { loggingMiddleware } from './middleware/logging';

export const startServer = async (port: number): Promise<Express> => {
  const app = express();

  // Trust proxy (behind ALB)
  app.set('trust proxy', true);

  // Middleware
  app.use(express.json({ limit: '10mb' }));
  app.use(express.urlencoded({ extended: true, limit: '10mb' }));

  // Logging middleware
  app.use(loggingMiddleware);

  // CORS headers (if needed)
  app.use((req: Request, res: Response, next: NextFunction) => {
    res.header('X-Service-Name', 'service-a');
    res.header('X-Service-Version', '1.0.0');
    next();
  });

  // Routes
  app.use('/health', healthRouter);
  app.use('/api/v1/service-a', helloRouter);
  app.use('/metrics', metricsRouter);

  // 404 handler
  app.use((req: Request, res: Response) => {
    res.status(404).json({
      error: 'Not Found',
      path: req.path,
      method: req.method,
    });
  });

  // Error handling middleware (must be last)
  app.use(errorHandler);

  // Start server
  return new Promise((resolve, reject) => {
    const server = app.listen(port, () => {
      resolve(app);
    });

    server.on('error', (error: NodeJS.ErrnoException) => {
      if (error.code === 'EADDRINUSE') {
        console.error(`❌ Port ${port} is already in use`);
      } else {
        console.error('❌ Server error:', error);
      }
      reject(error);
    });
  });
};
