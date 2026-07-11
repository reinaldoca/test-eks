import { Router, Request, Response } from 'express';

const router = Router();

// Prometheus metrics endpoint
// NOTE: This is a placeholder. In production, use @opentelemetry/exporter-prometheus
// or integrate with Prometheus scraping via ServiceMonitor
router.get('/', (req: Request, res: Response) => {
  const metrics = `
# HELP nodejs_heap_size_total_bytes Total heap size
# TYPE nodejs_heap_size_total_bytes gauge
nodejs_heap_size_total_bytes{service="service-a"} ${process.memoryUsage().heapTotal}

# HELP nodejs_heap_size_used_bytes Used heap size
# TYPE nodejs_heap_size_used_bytes gauge
nodejs_heap_size_used_bytes{service="service-a"} ${process.memoryUsage().heapUsed}

# HELP nodejs_external_memory_bytes External memory
# TYPE nodejs_external_memory_bytes gauge
nodejs_external_memory_bytes{service="service-a"} ${process.memoryUsage().external}

# HELP nodejs_process_uptime_seconds Process uptime
# TYPE nodejs_process_uptime_seconds gauge
nodejs_process_uptime_seconds{service="service-a"} ${process.uptime()}

# HELP nodejs_process_cpu_user_seconds_total User CPU time
# TYPE nodejs_process_cpu_user_seconds_total counter
nodejs_process_cpu_user_seconds_total{service="service-a"} ${process.cpuUsage().user / 1000000}

# HELP nodejs_process_cpu_system_seconds_total System CPU time
# TYPE nodejs_process_cpu_system_seconds_total counter
nodejs_process_cpu_system_seconds_total{service="service-a"} ${process.cpuUsage().system / 1000000}
`;

  res.set('Content-Type', 'text/plain; version=0.0.4');
  res.send(metrics.trim());
});

export { router as metricsRouter };
