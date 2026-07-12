# 🚀 Próximos Pasos - Deployment de Infraestructura

## ✅ **Lo que Acabamos de Hacer**

### **1. Creamos Environment Dev** ✅
```bash
✅ infrastructure/dev/ creado (copia optimizada de production)
✅ region.hcl configurado con environment = "dev"
✅ eks/terragrunt.hcl ajustado para dev
✅ Script deploy-dev.sh creado para deployment local
```

### **2. Corregimos Problemas de Terragrunt** ✅
```bash
✅ ECR: Cambiado repository_tags → tags
✅ ECR: Eliminado data.aws_caller_identity duplicado
✅ EKS: Cambiado dependency.vpc.outputs.* → var.* en _envcommon
✅ EKS: Agregado mock_outputs en dependency
```

### **3. Actualizamos Pipeline Multi-Environment** ✅
```bash
✅ infrastructure-plan.yml detecta environment automáticamente:
   - PR → develop  = plan en dev/
   - PR → staging  = plan en staging/
   - PR → main     = plan en production/
```

### **4. Documentación Completa** ✅
```bash
✅ docs/DEPLOYMENT_GUIDE.md con guía paso a paso
✅ Estrategia de branches explicada
✅ Troubleshooting incluido
```

### **5. Commit en Branch Develop** ✅
```bash
✅ Branch 'develop' creado
✅ Todos los cambios commiteados
✅ Listo para push
```

---

## 🎯 **Tu Siguiente Acción (AHORA)**

### **Opción A: Deployment Local (Recomendado para Primera Vez)**

```bash
# 1. Configurar AWS credentials
aws configure
# O si ya tienes profile:
export AWS_PROFILE=tu-perfil

# 2. Ejecutar script de deployment
cd infrastructure/dev
./deploy-dev.sh

# Esto hará:
# - Init + Validate + Plan + Apply (con confirmación)
# - Mostrará todos los outputs
# - Tiempo estimado: 15-20 minutos
```

**✅ Ventajas:**
- Más rápido para iterar
- Ves los errores en tiempo real
- Puedes debuggear fácilmente
- No consume GitHub Actions minutes

---

### **Opción B: Deployment vía Pipeline (Producción)**

```bash
# 1. Push branch develop
git push -u origin develop

# 2. Crear PR en GitHub UI
# Ir a: https://github.com/tu-usuario/test-eks/compare/main...develop
# Título: "feat: Add dev environment infrastructure"
# Descripción: Ver abajo

# 3. Esperar a que pipeline ejecute plan
# Workflow: Infrastructure Plan
# - Detecta environment = dev
# - Ejecuta terragrunt plan
# - Comenta el plan en el PR

# 4. Revisar plan en PR comment

# 5. Merge PR → develop
# Esto NO triggerea apply automático aún
# (Necesitas configurar GitHub Actions workflow para apply)

# 6. Para aplicar, ejecutar workflow manualmente:
# Actions → Infrastructure Apply → Run workflow
#   Environment: dev
#   Branch: develop
```

---

## 📝 **Descripción Recomendada para el PR**

```markdown
## 🚀 Add Dev Environment Infrastructure

### Changes
- ✅ Created `infrastructure/dev/` with cost-optimized configuration
- ✅ Fixed ECR module configuration (tags parameter)
- ✅ Fixed EKS dependency chain (VPC outputs as variables)
- ✅ Updated pipeline to support multi-environment (dev/staging/production)
- ✅ Added comprehensive deployment guide

### Environment Details
- **Name:** dev
- **Region:** us-east-1
- **Expected Cost:** ~$500-800/month
- **Purpose:** Rapid development and testing

### Testing Plan
- [x] Terragrunt validate passes
- [x] Terragrunt plan generates ~50-70 resources
- [ ] Terragrunt apply creates all resources
- [ ] EKS cluster accessible via kubectl
- [ ] ECR repositories created

### Deployment Strategy
This is the **first environment** in our progressive rollout:
1. **Dev** (this PR) → Rapid iteration, cost-optimized
2. **Staging** (next) → Pre-production testing
3. **Production** (final) → Customer-facing

### Rollback Plan
If apply fails:
- Terragrunt will not partially create resources (atomic operations)
- Can destroy with: `terragrunt run --all destroy`
- S3 backend has versioning enabled for state recovery

### Review Checklist
- [ ] Plan shows expected resources (~50-70)
- [ ] No unexpected deletions
- [ ] Security scan (Checkov) passes
- [ ] Cost estimation within budget ($500-800/month)

cc @platform-team
```

---

## 🔍 **Verificación Post-Deployment**

Una vez que el deployment termine (local o pipeline), ejecuta:

```bash
# 1. Verificar AWS credentials
aws sts get-caller-identity

# 2. Verificar S3 backend
aws s3 ls | grep fintech-platform-terraform-state

# 3. Verificar VPC
aws ec2 describe-vpcs \
  --filters "Name=tag:Environment,Values=dev" \
  --query 'Vpcs[*].[VpcId,CidrBlock,Tags[?Key==`Name`].Value|[0]]' \
  --output table

# 4. Verificar EKS cluster
aws eks describe-cluster \
  --name fintech-eks-dev \
  --query 'cluster.[name,status,version,endpoint]' \
  --output table

# 5. Conectar a EKS
aws eks update-kubeconfig --name fintech-eks-dev --region us-east-1

# 6. Verificar nodos
kubectl get nodes
# Expected: 2-3 nodos en estado Ready

# 7. Verificar S3 buckets
aws s3 ls | grep loki-logs-dev

# 8. Verificar ECR repositories
aws ecr describe-repositories \
  --repository-names service-a service-b \
  --query 'repositories[*].[repositoryName,repositoryUri]' \
  --output table

# 9. Verificar costos actuales
aws ce get-cost-and-usage \
  --time-period Start=$(date -d "7 days ago" +%Y-%m-%d),End=$(date +%Y-%m-%d) \
  --granularity DAILY \
  --metrics "BlendedCost" \
  --filter file://- << EOF
{
  "Tags": {
    "Key": "Environment",
    "Values": ["dev"]
  }
}
EOF
```

---

## 🚨 **Troubleshooting Común**

### **Error: "S3 bucket does not exist"**
```bash
cd infrastructure/bootstrap
./create-state-backend.sh create
```

### **Error: "Unsupported attribute vpc_cidr_block"**
```bash
# Ya corregido en este commit
# Si persiste, verifica:
cat infrastructure/_envcommon/eks.hcl | grep "vpc_cidr_block"
# Debe ser: cidr_blocks = [var.vpc_cidr_block]
# NO: cidr_blocks = [dependency.vpc.outputs.vpc_cidr_block]
```

### **Error: "Duplicate data aws_caller_identity"**
```bash
# Ya corregido en este commit
# Si persiste, limpiar cache:
cd infrastructure/dev
rm -rf */.terragrunt-cache
terragrunt run --all init -- -upgrade
```

### **Error: "NoCredentials"**
```bash
# Configurar AWS credentials
aws configure

# O usar SSO
aws sso login --profile tu-perfil
export AWS_PROFILE=tu-perfil
```

---

## 📊 **Métricas de Éxito**

### **Infraestructura Creada**
- [ ] 1 VPC con 9 subredes (3 AZs × 3 tipos)
- [ ] 1 EKS cluster con 2-3 nodos
- [ ] 1 S3 bucket para Loki logs
- [ ] 2 ECR repositories (service-a, service-b)
- [ ] 6 IAM roles IRSA
- [ ] Total: ~50-70 recursos

### **Performance**
- [ ] Deployment time: < 25 minutos
- [ ] EKS API endpoint responsive
- [ ] Kubectl access functional

### **Cost**
- [ ] Daily cost: ~$16-26/día
- [ ] Monthly estimate: ~$500-800/mes
- [ ] Within dev budget: ✅

---

## 🎯 **Siguientes Fases**

### **FASE 2: GitOps con ArgoCD** (Después de dev estable)
```bash
# 1. Desplegar ArgoCD en cluster dev
# 2. Configurar App of Apps pattern
# 3. Desplegar observability stack (Prometheus, Grafana, Loki)
# Ver: docs/ARGOCD_DEPLOYMENT.md (próximo documento)
```

### **FASE 3: Staging Environment**
```bash
# 1. Copiar dev → staging
# 2. Ajustar sizing (70% de production)
# 3. Create branch staging
# 4. Deploy y validar
```

### **FASE 4: Production Environment**
```bash
# 1. Ya existe en infrastructure/production/
# 2. Crear PR: staging → main
# 3. Review exhaustivo (2+ approvals)
# 4. Apply con approval manual obligatorio
```

---

## 📚 **Recursos**

- **Deployment Guide:** [docs/DEPLOYMENT_GUIDE.md](docs/DEPLOYMENT_GUIDE.md)
- **Workflow Architecture:** [.github/WORKFLOWS_ARCHITECTURE.md](.github/WORKFLOWS_ARCHITECTURE.md)
- **Terragrunt v1 Migration:** [infrastructure/TERRAGRUNT_V1_MIGRATION.md](infrastructure/TERRAGRUNT_V1_MIGRATION.md)

---

## ✅ **Checklist Pre-Deployment**

Antes de ejecutar `./deploy-dev.sh` o merge el PR:

- [ ] AWS credentials configuradas (`aws sts get-caller-identity`)
- [ ] S3 backend creado (`./create-state-backend.sh status`)
- [ ] Terraform v1.15.0 instalado (`terraform version`)
- [ ] Terragrunt v1.1.0 instalado (`terragrunt --version`)
- [ ] Budget configurado en AWS ($1000/mes para dev)
- [ ] Alertas de costo configuradas (opcional pero recomendado)

---

**🎉 ¡Todo listo para deployment!**

**Comando recomendado:**
```bash
cd infrastructure/dev
./deploy-dev.sh
```

**O push para pipeline:**
```bash
git push -u origin develop
# Luego crear PR en GitHub UI
```
