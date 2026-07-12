Actúa como un Arquitecto de Cloud & DevOps de nivel Senior Staff con amplia experiencia en AWS, Terragrunt, Kubernetes (EKS Auto Mode), GitOps (ArgoCD) y Observabilidad (OpenTelemetry, Prometheus, Grafana, Loki).

Quiero diseñar e implementar una infraestructura completa, automatizada y escalable en AWS usando las mejores prácticas de la industria. Proporcióname la estructura de archivos, el código completo de Terragrunt, los manifiestos de Kubernetes/ArgoCD, el workflow de GitHub Actions y el código de las aplicaciones según los siguientes requerimientos específicos:

### 1. Infraestructura con Terragrunt (AWS)
Utiliza Terragrunt con una estructura DRY (Don't Repeat Yourself) para desplegar los siguientes recursos puros de infraestructura:
- Una VPC con subredes públicas y privadas, NAT Gateways e Internet Gateway etiquetada correctamente para Kubernetes.
- Un clúster de EKS utilizando la funcionalidad nativa de "EKS Auto Mode" (para automatizar la gestión de nodos, almacenamiento y balanceadores sin gestionar Node Groups tradicionales).
- Roles de IAM necesarios mediante IRSA (IAM Roles for Service Accounts) o EKS Pod Identity para los componentes que interactúen con AWS.
- Un bucket S3 que servirá como almacenamiento directo para Loki (Nota: Justifica si es mejor usar S3 directamente en lugar de MinIO dentro del clúster para entornos AWS).

### 2. GitOps con ArgoCD
- Código o estrategia de bootstrapping para instalar ArgoCD dentro del clúster (mediante Helm provider en Terragrunt o un script inicial).
- Estructura declarativa usando el patrón "App of Apps" o "ApplicationSet" para gestionar la configuración del clúster (plataforma) y los microservicios de forma independiente.

### 3. Networking y Exposición (Gateway API)
- Configuración del AWS Gateway API Controller aprovechando las capacidades nativas de EKS Auto Mode.
- Creación de un recurso "Gateway" de Kubernetes que exponga un LoadBalancer de AWS por defecto (sin usar nombres de dominio/Route53 por el momento, apuntando directamente al endpoint público del LoadBalancer).
- Configura las HTTPRoutes para enrutar el tráfico hacia los microservicios Node.js basándote en prefijos de ruta (ej. /service-a, /service-b).

### 4. Stack de Observabilidad y Telemetría
Implementa el stack de monitoreo delegando su despliegue a ArgoCD:
- OpenTelemetry Operator para Kubernetes con configuración de un recurso 'Instrumentation' para la inyección automática del agente (Auto-instrumentation) si aplica, o mediante el Collector.
- OpenTelemetry Collector configurado con pipelines para recibir métricas, logs y trazas, y exportarlas eficientemente.
- Configuración de Prometheus (vía Prometheus Operator / Kube-Prometheus-Stack) para scraping de métricas.
- Configuración de Grafana Loki para recolectar logs (conectado al backend S3/MinIO).
- Instancia de Grafana configurada con data sources listos para correlacionar trazas, logs y métricas.

### 5. Microservicios (Node.js) con OpenTelemetry Integrado
Crea dos microservicios "Hello World" en Node.js (Servicio A y Servicio B):
- Dame el código completo en Node.js ('index.js', 'package.json') e incluye la inicialización explícita del SDK de OpenTelemetry en un archivo separado ('tracing.js') utilizando los exportadores de OTLP (gRPC o HTTP/JSON) para enviar datos al colector de OpenTelemetry.
- Haz que el Servicio A realice una llamada HTTP interna hacia el Servicio B para demostrar la propagación de contexto (W3C Trace Context) en el backend.
- Dockerfile optimizado (multi-stage o distroless/alpine).
- Manifiestos de Kubernetes para cada aplicación: Deployment, Service, HTTPRoute y un Horizontal Pod Autoscaler (HPA) configurado para escalar basado en uso de CPU y memoria.

### 6. Automatización (GitHub Actions)
Genera dos workflows separados en formato YAML:
- **Pipeline de Infraestructura:** Que ejecute `terragrunt run-all plan/apply` ante cambios en la carpeta de infraestructura.
- **Pipeline de Aplicaciones:** Que construya las imágenes Docker de los microservicios, las suba a AWS ECR y actualice automáticamente las etiquetas de imagen en el repositorio GitOps para activar la sincronización de ArgoCD.

### 7. Entregables y Recomendaciones
1. **Árbol de directorios** recomendado para separar la infraestructura (Terragrunt), la plataforma/apps (ArgoCD) y el código de las aplicaciones.
2. **Código de Terragrunt** clave para la VPC, EKS Auto y S3.
3. **Código de Node.js** con la lógica de OpenTelemetry explicada línea por línea.
4. **Manifiestos YAML** esenciales de Kubernetes organizados para ArgoCD.
5. **Guía de pruebas:** Instrucciones paso a paso para realizar una prueba de carga rápida (usando herramientas como K6, Locust o ApacheBench) para forzar el autoscalado (HPA) y verificar la llegada de trazas correlacionadas a Grafana.

Justifica brevemente tus decisiones de arquitectura, especialmente definiendo la frontera exacta entre lo que se debe desplegar con Terragrunt y lo que se debe delegar a ArgoCD.
