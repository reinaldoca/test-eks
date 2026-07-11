# FinTech Cloud-Native Platform on AWS EKS

Plataforma de próxima generación para FinTech con operaciones en 12 países, diseñada para processar 50,000+ transacciones por minuto con SLA 99.99%.

## 🎯 Objetivos Estratégicos

- **Time-to-Market**: < 10 minutos para desplegar nuevos microservicios
- **Escalabilidad**: Manejar 10x el tráfico actual durante picos
- **Observabilidad**: Troubleshooting completo en < 5 minutos con correlación automática
- **Compliance**: SOC2 Type II, ISO 27001, GDPR, PCI-DSS
- **SLA**: 99.99% uptime (52 minutos downtime anual)
- **RTO/RPO**: 30 min / 5 min
- **Costo**: < $18,000 USD/mes

## 📊 Estado del Proyecto: **50% Completado**

### ✅ Fases Completadas

#### **Fase 1: Infraestructura Base** - ✅ 100%
- ✅ Terragrunt (11 archivos): VPC multi-AZ, EKS Auto Mode, S3 Loki, IAM IRSA

#### **Fase 2: GitOps con ArgoCD** - ✅ 100%
- ✅ ArgoCD (9 archivos): Bootstrap, RBAC 3 niveles, 3 Projects, App of Apps

#### **Fase 3: Networking** - ⚠️ 50%
- ✅ Gateway API Controller, Gateway resource (2 archivos)
- ⏳ Network Policies, HTTPRoutes completos

#### **Fase 5: Microservicios** - ⚠️ 50%
- ✅ Service A completo (16 archivos): OpenTelemetry, Circuit Breaker, Dockerfile
- ⏳ Service B, Manifiestos Kubernetes

#### **Fase 6: CI/CD con GitHub Actions** - ✅ 100%
- ✅ Pipelines (7 archivos): Infrastructure Plan/Apply, Service CI/CD, ArgoCD Sync
- ✅ Composite Actions (3 archivos): setup-terragrunt, build-and-push, update-image-tag
- ✅ OIDC Authentication (sin long-lived credentials)
- ✅ Security scanning (Checkov, Trivy)

### ⏳ Fases Pendientes
- **Fase 4**: Observabilidad (OTEL Collector, Grafana, Loki, Tempo)
- **Fase 7**: Security (External Secrets, Falco, Gatekeeper)

## 🏗️ Arquitectura Implementada

```
AWS Account
│
├── VPC (10.0.0.0/16)
│   ├── 3x Public Subnets (Load Balancers)
│   ├── 3x Private Subnets (Kubernetes Pods)
│   ├── 3x Database Subnets (RDS, futuro)
│   └── 3x NAT Gateways (HA para SLA 99.99%)
│
├── EKS Cluster (v1.30)
│   ├── Node Pool: Critical (m5.large, on-demand, 3-30)
│   ├── Node Pool: Standard (m5/m6i, on-demand, 6-50)
│   └── Node Pool: Batch (spot, 40% descuento, 0-20)
│
├── S3 Buckets
│   ├── loki-logs (Intelligent-Tiering, lifecycle 2 años)
│   └── velero-backups (DR cross-region)
│
└── IAM IRSA Roles
    ├── otel-collector (CloudWatch, X-Ray, S3)
    ├── grafana (CloudWatch read, Athena, S3)
    ├── external-secrets (Secrets Manager, KMS)
    ├── service-a/b (X-Ray)
    └── velero (S3, EC2 snapshots)

Kubernetes Cluster
│
├── ArgoCD (namespace: argocd)
│   ├── RBAC: platform-engineer/sre/developer
│   ├── OIDC: AWS Cognito
│   └── App of Apps: platform applications
│
├── Gateway API (namespace: production)
│   ├── Gateway (ALB)
│   ├── HTTPRoute (HTTP→HTTPS redirect)
│   └── ReferenceGrant (cross-namespace)
│
├── Observability (namespace: observability)
│   ├── OpenTelemetry Operator
│   └── [Pendiente: OTEL Collector, Tempo, Loki]
│
├── Monitoring (namespace: monitoring)
│   └── Kube-Prometheus-Stack (Prometheus HA, Alertmanager)
│
└── Services (namespace: production)
    ├── Service A (✅ código completo)
    │   ├── OpenTelemetry SDK
    │   ├── Circuit Breaker (opossum)
    │   ├── W3C Trace Context
    │   └── Winston logging
    └── Service B (⏳ pendiente)
```

## 🚀 Quick Start

### Opción A: Despliegue Automatizado con GitHub Actions (Recomendado)

#### 1. Configurar OIDC en AWS
```bash
./github-oidc-role-v2.sh
# Crear roles: github-actions-terragrunt, github-actions-ecr, github-actions-eks
```

#### 2. Agregar GitHub Secrets
```bash
gh secret set AWS_ACCOUNT_ID --body "123456789012"
gh secret set CODECOV_TOKEN --body "your-token"
gh secret set SLACK_WEBHOOK_URL --body "https://hooks.slack.com/..."
```

#### 3. Crear ECR Repositories (opcional, incluido en infraestructura)
```bash
cd infrastructure/production/ecr
terragrunt init
terragrunt apply
# → Crea repositories para service-a, service-b con lifecycle policies
```

#### 4. Push código a GitHub
```bash
git add .
git commit -m "feat: initial platform setup"
git push origin main
# → Las pipelines se ejecutarán automáticamente
# → Infrastructure Apply → Service A Build → ArgoCD Sync
```

#### 5. Monitorear despliegue
- **GitHub Actions**: https://github.com/fintech-company/test-eks/actions
- **ArgoCD UI**: https://argocd.fintech.com
- **Grafana**: https://grafana.fintech.com

### Opción B: Despliegue Manual Local

#### 1. Desplegar Infraestructura
```bash
cd infrastructure/production
terragrunt run-all init
terragrunt run-all apply
```

#### 2. Bootstrap ArgoCD
```bash
kubectl apply -f gitops/bootstrap/argocd-install.yaml
kubectl apply -f gitops/bootstrap/argocd-cm.yaml
kubectl apply -f gitops/bootstrap/argocd-rbac.yaml
kubectl apply -f gitops/applications/platform/app-of-apps.yaml
```

#### 3. Desarrollar Servicios Localmente
```bash
cd services/service-a
npm install
npm run dev:watch
```

### 📋 Ver documentación completa de pipelines
```bash
cat .github/PIPELINES.md
```

## 📂 Estructura del Repositorio

```
test-eks/
├── infrastructure/          # ✅ Terragrunt (11 archivos)
├── gitops/                  # ✅ ArgoCD (11 archivos)
├── services/
│   ├── service-a/          # ✅ Completo (16 archivos)
│   └── service-b/          # ⏳ Pendiente
├── .github/
│   ├── workflows/          # ✅ Pipelines (4 archivos)
│   ├── actions/            # ✅ Composite actions (3 archivos)
│   └── PIPELINES.md        # ✅ Documentación CI/CD
├── docs/                    # ⏳ Pendiente
├── context.md               # 📋 Requisitos completos
└── README.md                # 📄 Este archivo
```

**Total de archivos creados:** 48  
**Progreso estimado:** 52% del proyecto completo

## 🎯 Próximos Pasos

1. **Completar Service B** (similar a Service A)
2. **Manifiestos Kubernetes** (Deployment, Service, HTTPRoute, HPA, PDB, ServiceMonitor)
3. **OpenTelemetry Collector** (ConfigMap con processors/exporters)
4. **Grafana** (OAuth, datasources, dashboards)
5. **CI/CD pipelines** (GitHub Actions)

## 📚 Documentación

- **Plan Completo**: `.claude/plans/act-a-como-un-arquitecto-stateless-pond.md`
- **Requisitos**: `context.md`
- **Service A**: `services/service-a/README.md`

## 💰 Costos Estimados: $12,000/mes
(Dentro del budget de $18,000)

---

## 🔄 CI/CD Flow

```
Developer Commit
    ↓
GitHub Actions
    ├─→ Infrastructure Pipeline (Terragrunt)
    │   ├─→ Plan (en PR)
    │   └─→ Apply (en main)
    │
    └─→ Application Pipeline (Service A)
        ├─→ Test & Lint
        ├─→ Security Scan (Trivy, Checkov)
        ├─→ Build Docker Image
        ├─→ Push to ECR
        └─→ Update GitOps Repo
            ↓
        ArgoCD (auto-sync)
            ├─→ Detect Git change
            └─→ Apply to Kubernetes
                ↓
            Rolling Update (0 downtime)
                ↓
            Health Checks Pass
                ↓
            🎉 Production!
```

**Time-to-Production:** < 10 minutos ✅

---

**Última actualización**: 2024-07-11  
**Estado**: 🚧 En desarrollo (50% completado)  
**Siguiente milestone**: Observabilidad completa (Grafana, Loki, Tempo)
