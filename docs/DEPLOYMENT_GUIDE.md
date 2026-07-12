# 🚀 Guía de Deployment - Plataforma FinTech

Esta guía describe el flujo completo para desplegar la infraestructura desde cero siguiendo las mejores prácticas de GitOps.

---

## 📋 Pre-requisitos

Antes de comenzar, verifica que tienes:

- [ ] Acceso AWS con permisos de administrador
- [ ] GitHub Repository configurado
- [ ] AWS OIDC configurado para GitHub Actions (ejecuta `./github-oidc-role-v2.sh`)
- [ ] Secrets configurados en GitHub:
  - `AWS_ACCOUNT_ID`: Tu AWS Account ID
- [ ] Branches protegidos configurados en GitHub:
  - `develop`, `staging`, `main` con required reviews

---

## 🌳 Branch Strategy

```
feature/* ─► develop ─► staging ─► main
              ↓          ↓          ↓
             dev      staging   production
          (auto)     (approval)  (approval+)
```

### **Protección de Branches**

```yaml
develop:
  - Require PR antes de merge
  - Require 1 approval
  - Require status checks: Infrastructure Plan, Security Scan
  
staging:
  - Require PR antes de merge
  - Require 2 approvals (platform engineers)
  - Require status checks to pass
  
main (production):
  - Require PR antes de merge
  - Require 2 approvals (platform engineers + SRE)
  - Require status checks to pass
  - Require linear history
  - Prohibit force pushes
```

---

## 🎬 Deployment Flow - Primera Vez

### **FASE 1: Development Environment (1-2 días)**

#### **1.1. Crear branch de trabajo**

```bash
git checkout -b feature/initial-infrastructure
```

#### **1.2. Crear estructura de directorios dev**

```bash
# Copiar estructura de production a dev
cp -r infrastructure/production infrastructure/dev

# Editar region.hcl
vim infrastructure/dev/region.hcl
```

```hcl
# infrastructure/dev/region.hcl
locals {
  aws_region  = "us-east-1"
  environment = "dev"
}
```

#### **1.3. Ajustar configuración para dev (reducir costos)**

```bash
vim infrastructure/dev/eks/terragrunt.hcl
```

```hcl
inputs = {
  vpc_id         = dependency.vpc.outputs.vpc_id
  subnet_ids     = dependency.vpc.outputs.private_subnets
  vpc_cidr_block = dependency.vpc.outputs.vpc_cidr_block

  # Dev: reducir tamaño de nodos
  eks_managed_node_groups = {
    critical = {
      min_size     = 1  # vs 3 en prod
      max_size     = 5  # vs 30 en prod
      desired_size = 2  # vs 3 en prod
      instance_types = ["t3.medium"]  # vs m5.large en prod
    }
  }
}
```

#### **1.4. Crear backend de Terraform para dev**

```bash
cd infrastructure/bootstrap

# Crear backend para dev
AWS_REGION=us-east-1 ./create-state-backend.sh create

# Verificar
./create-state-backend.sh status
```

#### **1.5. Push y crear PR hacia develop**

```bash
git add infrastructure/dev
git commit -m "feat: add dev environment infrastructure"
git push origin feature/initial-infrastructure

# Crear PR en GitHub UI: feature/initial-infrastructure → develop
```

**✅ Validación:**
- [ ] Pipeline "Infrastructure Plan" se ejecuta automáticamente
- [ ] Plan muestra recursos a crear (VPC, EKS, S3, IAM, ECR)
- [ ] Security scan pasa (Checkov)
- [ ] Plan comentado en el PR

#### **1.6. Revisar y aprobar PR**

```bash
# Revisar el plan en el PR comment
# Verificar:
- Número de recursos: ~50-70 recursos
- No hay deletions (primera vez)
- Costos estimados: ~$500-800/mes para dev
```

#### **1.7. Merge PR → Trigger Apply en dev**

```bash
# Merge el PR en GitHub UI
# Esto trigger "Infrastructure Apply" workflow
```

**⏳ Tiempo de apply:** 15-20 minutos

**✅ Validación:**
- [ ] VPC creada con 3 AZs
- [ ] EKS cluster running
- [ ] S3 bucket para Loki creado
- [ ] ECR repositories creados (service-a, service-b)
- [ ] IAM roles creados

```bash
# Conectar a EKS dev
aws eks update-kubeconfig --name fintech-eks-dev --region us-east-1

# Verificar nodos
kubectl get nodes
# Expected: 2 nodos ready

# Verificar namespaces
kubectl get namespaces
# Expected: default, kube-system, etc.
```

#### **1.8. Iterar en dev hasta estabilizar**

Si hay errores:

```bash
# Crear branch de fix
git checkout -b fix/adjust-dev-config

# Hacer cambios
vim infrastructure/dev/vpc/terragrunt.hcl

# Push y crear PR hacia develop
git commit -am "fix: adjust VPC CIDR for dev"
git push origin fix/adjust-dev-config

# Repetir ciclo: Plan → Review → Merge → Apply
```

**🎯 Objetivo:** Dev environment completamente funcional y estable.

---

### **FASE 2: Staging Environment (1 día)**

#### **2.1. Crear staging environment**

```bash
git checkout develop
git pull

# Crear branch
git checkout -b feature/add-staging-environment

# Copiar de dev y ajustar
cp -r infrastructure/dev infrastructure/staging

# Editar region.hcl
vim infrastructure/staging/region.hcl
```

```hcl
locals {
  aws_region  = "us-east-1"
  environment = "staging"
}
```

#### **2.2. Ajustar configuración (staging = 70% de prod)**

```hcl
# infrastructure/staging/eks/terragrunt.hcl
inputs = {
  eks_managed_node_groups = {
    critical = {
      min_size     = 2   # 70% de prod
      max_size     = 20
      desired_size = 2
      instance_types = ["m5.large"]
    }
  }
}
```

#### **2.3. Crear backend para staging**

```bash
cd infrastructure/bootstrap
AWS_REGION=us-east-1 ./create-state-backend.sh create
```

#### **2.4. Crear branch staging en GitHub**

```bash
# En GitHub UI: Settings → Branches → New branch
# Name: staging
# Source: develop
```

#### **2.5. Push y crear PR: develop → staging**

```bash
git add infrastructure/staging
git commit -m "feat: add staging environment"
git push origin feature/add-staging-environment

# Crear PR: feature/add-staging-environment → staging
```

#### **2.6. Merge y apply**

```bash
# Merge PR
# Pipeline aplica cambios en staging
```

**✅ Validación:**
- [ ] Staging EKS cluster running
- [ ] Smoke tests pasan
- [ ] Load test: 1000 RPS durante 5 min
- [ ] Costos: ~$1,200-1,500/mes

---

### **FASE 3: Production Environment (1 día)**

#### **3.1. Crear PR: staging → main**

```bash
git checkout staging
git pull

git checkout -b release/v1.0.0-infrastructure

# Ya tienes infrastructure/production/ del repo inicial
# Solo verifica configuración

git push origin release/v1.0.0-infrastructure

# Crear PR: release/v1.0.0-infrastructure → main
```

#### **3.2. Review exhaustivo**

**Checklist de revisión:**

- [ ] **Code Review**: 2 platform engineers aprueban
- [ ] **Security Review**: Security engineer aprueba
- [ ] **Cost Review**: Costos estimados ≤ $18,000/mes
- [ ] **Plan Review**: Verificar recursos críticos
  - [ ] 3 NAT Gateways (HA)
  - [ ] 3 nodos mínimos en EKS
  - [ ] Encryption habilitado en S3, EBS
  - [ ] IAM roles con least privilege
- [ ] **Compliance Review**: SOC2/ISO27001/GDPR checklist
- [ ] **Runbooks**: Documentados para incidentes comunes
- [ ] **Rollback Plan**: Documentado

#### **3.3. Crear backend de producción**

```bash
cd infrastructure/bootstrap
AWS_REGION=us-east-1 ./create-state-backend.sh create

# Verificar
./create-state-backend.sh status
```

#### **3.4. Merge PR → Manual Approval requerido**

```bash
# Merge PR en GitHub UI
# Pipeline pausa y espera approval manual
```

**En GitHub Actions UI:**

```
Workflow: Infrastructure Apply
Environment: production

⏸️  Waiting for approval

Required reviewers:
  - platform-engineer-1
  - platform-engineer-2

[Review deployment] ← Click aquí
```

#### **3.5. Approval y deployment**

```bash
# En GitHub Actions:
# 1. Revisar plan una última vez
# 2. Click "Approve deployment"
# 3. Pipeline ejecuta apply

# ⏳ Tiempo: 20-30 minutos
```

**✅ Validación:**
- [ ] VPC creada con 9 subredes (3 AZs × 3 tipos)
- [ ] EKS cluster running con 3+ nodos
- [ ] S3 buckets creados:
  - [ ] loki-logs-production-*
  - [ ] terraform-state-*
- [ ] ECR repositories listos
- [ ] IAM roles IRSA configurados

```bash
# Conectar a production
aws eks update-kubeconfig --name fintech-eks-production --region us-east-1

# Verificar cluster
kubectl cluster-info
kubectl get nodes
kubectl get pods --all-namespaces

# Verificar outputs
cd infrastructure/production
terragrunt run --all output
```

---

## 🔄 Deployment Flow - Cambios Posteriores

### **Cambio en Infraestructura**

```bash
# 1. Crear feature branch
git checkout develop
git pull
git checkout -b feature/add-new-subnet

# 2. Hacer cambios en dev primero
vim infrastructure/dev/vpc/terragrunt.hcl

# 3. PR → develop (plan automático)
git commit -am "feat: add new subnet for databases"
git push

# 4. Merge → Apply en dev (automático)

# 5. Validar en dev
# ... tests ...

# 6. PR → staging
git checkout staging
git merge develop
git push

# 7. PR → main (production)
git checkout main
git merge staging
git push
```

### **Cambio Urgente (Hotfix)**

```bash
# Crear branch desde main
git checkout main
git pull
git checkout -b hotfix/fix-security-group

# Hacer cambios directamente en production/
vim infrastructure/production/eks/terragrunt.hcl

# PR directo a main (requiere 2 approvals + justificación)
git commit -am "hotfix: close exposed security group"
git push

# Fast-track approval
# Apply con monitoring en tiempo real
```

---

## 🎛️ Configuración de GitHub Environments

### **1. Crear Environments en GitHub**

```
Settings → Environments → New environment

Environments a crear:
- dev
- staging  
- production
```

### **2. Configurar Protection Rules**

#### **Dev Environment**

```yaml
Protection rules:
  Required reviewers: 0  # Auto-deploy
  Wait timer: 0 minutes
  Deployment branches: develop only
```

#### **Staging Environment**

```yaml
Protection rules:
  Required reviewers: 1 (platform engineer)
  Wait timer: 0 minutes
  Deployment branches: staging only
  Prevent self-review: Yes
```

#### **Production Environment**

```yaml
Protection rules:
  Required reviewers: 2 (platform engineer + SRE)
  Wait timer: 5 minutes  # Cooling period
  Deployment branches: main only
  Prevent self-review: Yes
  Allow administrators to bypass: No
```

### **3. Configurar Environment Secrets**

```yaml
# Para cada environment (dev, staging, production):

Secrets:
  AWS_ACCOUNT_ID: <your-aws-account-id>

Variables:
  AWS_REGION: us-east-1
  ENVIRONMENT_NAME: dev|staging|production
```

---

## 📊 Monitoreo del Deployment

### **Métricas Clave**

```bash
# Costo mensual por environment
aws ce get-cost-and-usage \
  --time-period Start=2024-01-01,End=2024-01-31 \
  --granularity MONTHLY \
  --metrics "BlendedCost" \
  --filter file://filter.json

# Expected:
# Dev: $500-800/mes
# Staging: $1,200-1,500/mes
# Production: $16,000-18,000/mes
```

### **Health Checks Post-Deployment**

```bash
# 1. EKS Cluster
kubectl get nodes
kubectl top nodes

# 2. S3 Buckets
aws s3 ls | grep fintech

# 3. ECR Repositories
aws ecr describe-repositories

# 4. IAM Roles
aws iam list-roles | grep fintech-eks

# 5. VPC
aws ec2 describe-vpcs --filters "Name=tag:Project,Values=fintech-platform"

# 6. Costos actuales
aws ce get-cost-and-usage --time-period Start=$(date -d "7 days ago" +%Y-%m-%d),End=$(date +%Y-%m-%d) --granularity DAILY --metrics "BlendedCost"
```

---

## 🚨 Troubleshooting

### **Error: S3 bucket does not exist**

```bash
# Crear backend manualmente
cd infrastructure/bootstrap
./create-state-backend.sh create
```

### **Error: Duplicate data aws_caller_identity**

```bash
# Limpiar cache de Terragrunt
cd infrastructure/<env>
rm -rf */.terragrunt-cache

# Reintentar
terragrunt run --all init -- -upgrade
```

### **Error: VPC CIDR conflict**

```bash
# Verificar CIDRs existentes
aws ec2 describe-vpcs --query "Vpcs[*].[VpcId,CidrBlock]"

# Ajustar CIDR en inputs
vim infrastructure/<env>/vpc/terragrunt.hcl
```

### **Rollback de Infraestructura**

```bash
# Opción 1: Revert del commit
git revert <commit-sha>
git push

# Opción 2: Terraform state rollback (peligroso)
cd infrastructure/<env>
terraform state pull > backup.tfstate
aws s3 cp s3://fintech-platform-terraform-state-*/previous.tfstate ./
terraform state push previous.tfstate

# Opción 3: Destroy y recrear
terragrunt run --all destroy  # ⚠️ PELIGRO
```

---

## 📚 Referencias

- [Terragrunt Best Practices](https://terragrunt.gruntwork.io/docs/)
- [EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [GitHub Actions Environments](https://docs.github.com/en/actions/deployment/targeting-different-environments)
- [Terraform State Management](https://www.terraform.io/docs/language/state/index.html)

---

## ✅ Checklist Final

Antes de considerar el deployment completo:

### **Infrastructure**
- [ ] 3 Environments desplegados (dev, staging, production)
- [ ] EKS clusters running en cada environment
- [ ] S3 backends configurados y con backups
- [ ] IAM roles IRSA funcionando
- [ ] ECR repositories creados

### **CI/CD**
- [ ] Pipelines funcionando en develop, staging, main
- [ ] Approval manual configurado para production
- [ ] Security scans pasando (Checkov)
- [ ] Artifacts guardados (planes, outputs)

### **Security**
- [ ] Encryption at rest habilitado
- [ ] Encryption in transit (TLS) habilitado
- [ ] IAM roles con least privilege
- [ ] Network policies configuradas
- [ ] Audit logs habilitados (CloudWatch, CloudTrail)

### **Observability**
- [ ] CloudWatch logs configurados
- [ ] Métricas de costos monitoreadas
- [ ] Alertas configuradas (PagerDuty/Slack)

### **Documentation**
- [ ] Runbooks escritos
- [ ] Architecture diagrams actualizados
- [ ] Compliance checklist completo
- [ ] Disaster Recovery plan documentado

---

**🎉 ¡Felicidades! Tu plataforma FinTech está desplegada.**

**Próximos pasos:**
1. Desplegar GitOps (ArgoCD) → Ver `docs/ARGOCD_DEPLOYMENT.md`
2. Desplegar Observability Stack → Ver `docs/OBSERVABILITY_DEPLOYMENT.md`
3. Desplegar Microservicios → Ver `docs/SERVICES_DEPLOYMENT.md`
