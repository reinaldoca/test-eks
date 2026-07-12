# GitHub Actions CI/CD Pipelines

Pipelines completas para desplegar infraestructura y aplicaciones de la plataforma FinTech.

## 🏗️ Arquitectura de Pipelines

```
GitHub Actions
│
├── Infrastructure Pipelines
│   ├── infrastructure-plan.yml      # PR: Plan con Terragrunt
│   └── infrastructure-apply.yml     # Main: Apply con Terragrunt
│
├── Application Pipelines
│   ├── service-a-ci.yml            # Build, test, push, GitOps update
│   └── service-b-ci.yml            # (similar a service-a)
│
├── ArgoCD Pipelines
│   └── argocd-sync.yml             # Manual sync de aplicaciones
│
└── Composite Actions (reutilizables)
    ├── setup-terragrunt/            # Instalar Terraform + Terragrunt
    ├── build-and-push/              # Build Docker + Push ECR
    └── update-image-tag/            # Update GitOps kustomization
```

---

## 🔐 Configuración Previa (REQUERIDA)

### 1. Crear IAM Roles con OIDC en AWS

Ejecutar el script incluido en el repositorio:

```bash
./github-oidc-role-v2.sh
```

Este script creará 3 roles IAM:

#### **A. github-actions-terragrunt**
- **Propósito**: Desplegar infraestructura (VPC, EKS, S3, IAM)
- **Permisos**: 
  - `ec2:*` (VPC, subnets, NAT Gateways)
  - `eks:*` (Cluster, node groups)
  - `s3:*` (Buckets para Loki, Velero, Terraform state)
  - `iam:*` (Roles IRSA)
  - `kms:*` (Encryption keys)
  - `logs:*` (CloudWatch)
- **Trust Policy**: GitHub OIDC provider para repo `fintech-company/test-eks`

#### **B. github-actions-ecr**
- **Propósito**: Build y push de Docker images
- **Permisos**:
  - `ecr:GetAuthorizationToken`
  - `ecr:BatchCheckLayerAvailability`
  - `ecr:PutImage`
  - `ecr:InitiateLayerUpload`
  - `ecr:UploadLayerPart`
  - `ecr:CompleteLayerUpload`
- **Trust Policy**: GitHub OIDC provider

#### **C. github-actions-eks**
- **Propósito**: Acceso a cluster EKS (ArgoCD sync)
- **Permisos**:
  - `eks:DescribeCluster`
  - `eks:ListClusters`
- **Trust Policy**: GitHub OIDC provider

### 2. Configurar GitHub Secrets

En **Settings > Secrets and variables > Actions**, agregar:

| Secret | Descripción | Ejemplo |
|--------|-------------|---------|
| `AWS_ACCOUNT_ID` | ID de cuenta AWS | `123456789012` |
| `CODECOV_TOKEN` | Token para Codecov (opcional) | `abc123...` |
| `SLACK_WEBHOOK_URL` | Webhook para notificaciones Slack | `https://hooks.slack.com/...` |

### 3. Crear ECR Repositories

**Opción A: Automático con Terragrunt (Recomendado)**

Los repositorios ECR se crean automáticamente cuando aplicas la infraestructura:

```bash
cd infrastructure/production/ecr
terragrunt init
terragrunt apply

# O desplegar todo junto:
cd infrastructure/production
terragrunt run --all apply
# → Incluye VPC, EKS, S3, IAM, ECR
```

**Opción B: Manual (solo si es necesario)**

```bash
aws ecr create-repository --repository-name service-a --region us-east-1
aws ecr create-repository --repository-name service-b --region us-east-1
```

**Features incluidas en el módulo Terragrunt:**
- ✅ Lifecycle policy (mantiene últimas 10 imágenes tagged)
- ✅ Image scanning automático en push
- ✅ Encryption con KMS
- ✅ Repository policy (permite pull desde EKS y push desde GitHub Actions)
- ✅ Cross-region replication a us-west-2 (DR)

---

## 📋 Pipelines Detalladas

### **1. Infrastructure Plan** (`infrastructure-plan.yml`)

**Trigger:**
- Pull Requests que modifiquen `infrastructure/**`

**Flujo:**
1. ✅ Checkout code
2. ✅ Configure AWS credentials (OIDC)
3. ✅ Install Terraform + Terragrunt
4. ✅ `terragrunt init`
5. ✅ `terragrunt validate`
6. ✅ `terragrunt plan` → Comenta plan en PR
7. ✅ Checkov security scan → Upload a Security tab

**Output:**
- Comentario en PR con plan de Terragrunt
- Artifact: `terragrunt-plan-output` (7 días retención)
- Security findings en GitHub Security tab

**Ejemplo de uso:**
```bash
# Crear PR con cambios de infraestructura
git checkout -b feat/add-new-vpc-subnet
# Modificar infrastructure/production/vpc/terragrunt.hcl
git add infrastructure/
git commit -m "feat: add new VPC subnet"
git push origin feat/add-new-vpc-subnet
# Crear PR en GitHub
# → Pipeline se ejecutará automáticamente
```

---

### **2. Infrastructure Apply** (`infrastructure-apply.yml`)

**Trigger:**
- Push a `main` que modifique `infrastructure/**`
- Manual dispatch (workflow_dispatch)

**Flujo:**
1. ✅ Checkout code
2. ✅ Configure AWS credentials (OIDC)
3. ✅ Install Terraform + Terragrunt
4. ✅ `terragrunt init`
5. ✅ `terragrunt plan`
6. ✅ `terragrunt apply` → Despliega infraestructura
7. ✅ Extract outputs (VPC ID, EKS cluster name, S3 buckets)
8. ✅ Update kubeconfig
9. ✅ Verify cluster access
10. ✅ Post-apply validation (VPC, EKS, S3)
11. ❌ Create GitHub issue si falla

**Output:**
- Artifact: `terragrunt-apply-output` (30 días retención)
- GitHub Step Summary con outputs
- Kubeconfig actualizado
- GitHub issue si hay error

**Ejemplo de uso:**
```bash
# Merge PR a main
git checkout main
git pull
# → Pipeline se ejecutará automáticamente

# O ejecutar manualmente desde GitHub UI:
# Actions > Infrastructure Apply > Run workflow
```

---

### **3. Service A CI/CD** (`service-a-ci.yml`)

**Trigger:**
- Push a `main`/`develop` que modifique `services/service-a/**`
- Pull Requests que modifiquen `services/service-a/**`

**Flujo:**

#### **Job 1: Test & Lint**
1. ✅ Setup Node.js 20
2. ✅ `npm ci`
3. ✅ `npm run lint`
4. ✅ `npm run typecheck`
5. ✅ `npm run test:coverage`
6. ✅ Upload coverage a Codecov

#### **Job 2: Security Scan**
1. ✅ Trivy filesystem scan
2. ✅ Upload SARIF a GitHub Security

#### **Job 3: Build & Push** (solo en `main`/`develop`)
1. ✅ Configure AWS credentials
2. ✅ Login to ECR
3. ✅ Docker metadata (tags)
4. ✅ Build Docker image con BuildKit caching
5. ✅ Push a ECR
6. ✅ Trivy image scan
7. ✅ Upload SARIF a GitHub Security

#### **Job 4: Update GitOps** (solo en `main`)
1. ✅ Update `kustomization.yaml` con nuevo image tag
2. ✅ Commit y push cambios
3. ✅ ArgoCD detecta cambio automáticamente

#### **Job 5: Notify**
1. ✅ Send Slack notification

**Output:**
- Docker image en ECR: `123456789012.dkr.ecr.us-east-1.amazonaws.com/service-a:main-abc1234`
- GitOps repo actualizado
- Notificación en Slack
- Coverage report en Codecov

**Ejemplo de uso:**
```bash
# Modificar código de Service A
cd services/service-a
vim src/routes/hello.ts
git add .
git commit -m "feat: add new endpoint"
git push origin main
# → Pipeline ejecuta: test → build → push → GitOps update
# → ArgoCD detecta cambio y despliega automáticamente
```

---

### **4. ArgoCD Manual Sync** (`argocd-sync.yml`)

**Trigger:**
- Manual dispatch (workflow_dispatch)

**Inputs:**
- `application`: Aplicación a sincronizar (`all`, `platform-apps`, `service-a`, etc.)
- `prune`: Eliminar recursos huérfanos (boolean)
- `force`: Forzar sync ignorando hooks (boolean)

**Flujo:**
1. ✅ Configure AWS credentials
2. ✅ Update kubeconfig
3. ✅ Install ArgoCD CLI
4. ✅ Get ArgoCD admin password
5. ✅ Port-forward ArgoCD server
6. ✅ Login to ArgoCD
7. ✅ Sync application(s)
8. ✅ Wait for sync completion
9. ✅ Get application status

**Ejemplo de uso:**
```bash
# Desde GitHub UI:
# Actions > ArgoCD Sync > Run workflow
# - Application: service-a
# - Prune: false
# - Force: false
# → Click "Run workflow"
```

---

## 🔄 Flujo Completo de Deployment

### **Escenario: Desplegar cambio en Service A**

```bash
# 1. Desarrollador hace cambio
cd services/service-a
vim src/routes/hello.ts
git add .
git commit -m "feat: add caching to hello endpoint"

# 2. Crear PR para review
git push origin feat/add-caching
# → Crear PR en GitHub

# 3. Pipeline automático en PR
# - service-a-ci.yml ejecuta:
#   ✅ Lint
#   ✅ Tests
#   ✅ Security scan
# - Reviewers aprueban PR

# 4. Merge a main
git checkout main
git merge feat/add-caching
git push origin main

# 5. Pipeline automático post-merge
# - service-a-ci.yml ejecuta:
#   ✅ Test
#   ✅ Build Docker image
#   ✅ Push a ECR: service-a:main-abc1234
#   ✅ Update GitOps: kustomization.yaml → newTag: main-abc1234
#   ✅ Commit y push a gitops repo

# 6. ArgoCD detecta cambio (auto-sync)
# - ArgoCD compara estado deseado (Git) vs actual (cluster)
# - Detecta diferencia en image tag
# - Aplica cambio: kubectl set image deployment/service-a ...
# - Kubernetes hace rolling update (0 downtime)

# 7. Verificación
# - ArgoCD marca aplicación como "Healthy" y "Synced"
# - Pods nuevos pasan health checks
# - Gateway enruta tráfico a nuevos pods
# - OpenTelemetry reporta métricas/traces

# Total: ~5-10 minutos desde commit hasta production ✅
```

---

## 🛡️ Security Features

### **1. OIDC Authentication**
- ✅ **Sin long-lived credentials** en GitHub Secrets
- ✅ **Tokens temporales** generados por AWS STS
- ✅ **Scoped a repositorio específico** (no funcionan en otros repos)

### **2. Security Scanning**
- ✅ **Checkov**: IaC security scan (Terraform)
- ✅ **Trivy**: Filesystem + Docker image vulnerability scan
- ✅ **SARIF upload**: Resultados en GitHub Security tab
- ✅ **Fail on critical**: Pipeline falla si hay vulnerabilidades críticas

### **3. Least Privilege IAM**
- ✅ **Roles separados** por función (terragrunt, ecr, eks)
- ✅ **Permisos mínimos** necesarios
- ✅ **Trust policy estricto** (solo desde GitHub Actions)

### **4. Artifact Management**
- ✅ **Docker images firmadas** (digest)
- ✅ **Retention policies** (7-30 días)
- ✅ **Immutable tags** en ECR (optional)

---

## 📊 Monitoring de Pipelines

### **GitHub Actions Insights**
- **Actions > Insights** → Ver métricas de pipelines
- **Success rate**, **Duration**, **Bottlenecks**

### **Alertas de Fallos**
1. **GitHub issue automático** (infrastructure-apply.yml)
2. **Slack notification** (service-a-ci.yml)
3. **Email** (configurar en GitHub settings)

### **Logs y Debugging**
```bash
# Ver logs de workflow
gh run list --workflow infrastructure-apply.yml
gh run view <run-id> --log

# Re-ejecutar workflow fallido
gh run rerun <run-id>
```

---

## 🚀 Setup Inicial (One-Time)

### **Paso 1: Configurar OIDC en AWS**
```bash
./github-oidc-role-v2.sh
# → Crear 3 roles IAM: terragrunt, ecr, eks
```

### **Paso 2: Agregar Secrets en GitHub**
```bash
gh secret set AWS_ACCOUNT_ID --body "123456789012"
gh secret set CODECOV_TOKEN --body "abc123..."
gh secret set SLACK_WEBHOOK_URL --body "https://hooks.slack.com/..."
```

### **Paso 3: Crear ECR Repositories**
```bash
aws ecr create-repository --repository-name service-a
aws ecr create-repository --repository-name service-b
```

### **Paso 4: Test Pipeline**
```bash
# Push dummy commit para probar
git commit --allow-empty -m "test: trigger pipeline"
git push origin main
# → Verificar que pipeline se ejecuta correctamente
```

---

## 🔧 Troubleshooting

### **Error: "Role not authorized"**
```bash
# Verificar que el role existe y tiene trust policy correcto
aws iam get-role --role-name github-actions-terragrunt
aws iam get-role-policy --role-name github-actions-terragrunt --policy-name GithubActionsPolicy
```

### **Error: "ECR repository not found"**
```bash
# Crear repository
aws ecr create-repository --repository-name service-a
```

### **Error: "Terragrunt lock timeout"**
```bash
# Limpiar locks en DynamoDB
aws dynamodb delete-item \
  --table-name fintech-platform-terraform-locks \
  --key '{"LockID": {"S": "infrastructure/production/vpc/terragrunt.hcl"}}'
```

### **Pipeline lento**
- ✅ Verificar **BuildKit caching** está funcionando
- ✅ Verificar **Terragrunt parallelism** (default: 20)
- ✅ Usar **self-hosted runners** (opcional)

---

## 📚 Referencias

- **GitHub Actions**: https://docs.github.com/en/actions
- **AWS OIDC**: https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services
- **Terragrunt**: https://terragrunt.gruntwork.io/
- **ArgoCD**: https://argo-cd.readthedocs.io/

---

## 🎯 Métricas de Éxito

**Pipeline Infrastructure:**
- ⏱️ **Duration**: < 15 minutos
- ✅ **Success Rate**: > 95%
- 🔄 **Frequency**: Bajo (cambios infrecuentes)

**Pipeline Service A:**
- ⏱️ **Duration**: < 10 minutos
- ✅ **Success Rate**: > 90%
- 🔄 **Frequency**: Alto (múltiples deployments diarios)

**Time-to-Production:**
- 🚀 **Desde commit hasta production**: < 10 minutos ✅

---

**Última actualización**: 2024-07-11  
**Mantenido por**: Platform Engineering Team
