import { Router, Request, Response } from 'express';

const router = Router();

// Health check endpoint (no tracing to avoid noise)
router.get('/', (req: Request, res: Response) => {
  res.status(200).json({
    status: 'healthy',
    service: 'service-a',
    version: '1.0.0',
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
  });
});

// Readiness check
router.get('/ready', (req: Request, res: Response) => {
  // Check dependencies (e.g., database, external services)
  // For now, always return ready
  res.status(200).json({
    status: 'ready',
    service: 'service-a',
    timestamp: new Date().toISOString(),
  });
});

// Liveness check
router.get('/live', (req: Request, res: Response) => {
  // Simple liveness check
  res.status(200).json({
    status: 'alive',
    service: 'service-a',
    timestamp: new Date().toISOString(),
  });
});

export { router as healthRouter };
