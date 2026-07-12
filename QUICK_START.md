# 🚀 Quick Start - Deploy Dev Environment

Esta guía te lleva paso a paso para desplegar tu primer environment (dev) usando GitHub Actions.

---

## ✅ **Pre-requisitos**

Antes de comenzar, verifica:

- [x] Branch `develop` existe en GitHub
- [x] Cambios pusheados a `develop`
- [x] AWS OIDC configurado (ejecutaste `./github-oidc-role-v2.sh`)
- [ ] GitHub Environments configurados
- [ ] GitHub Secrets configurados

---

## 📋 **PASO 1: Configurar GitHub Environment**

### **1.1. Crear Environment "dev"**

1. Ve a tu repo en GitHub:
   ```
   https://github.com/reinaldoca/test-eks
   ```

2. Click en **Settings** (arriba derecha)

3. En el sidebar izquierdo, click en **Environments**

4. Click en **New environment** (verde)

5. **Name:** `dev`

6. Click **Configure environment**

### **1.2. Configurar Protection Rules para Dev**

En la página de configuración del environment `dev`:

**Required reviewers:**
- Dejar en **0** (sin approval para dev)
- Esto permite deployment automático

**Wait timer:**
- Dejar en **0** minutes

**Deployment branches:**
- Select: **Selected branches**
- Add pattern: `develop`

Click **Save protection rules**

### **1.3. Agregar Secrets al Environment**

En la misma página del environment `dev`, scroll down a **Environment secrets**:

1. Click **Add secret**
   - **Name:** `AWS_ACCOUNT_ID`
   - **Value:** Tu AWS Account ID (ejemplo: `475274912371`)
   - Click **Add secret**

---

## 📋 **PASO 2: Ejecutar Manual Deployment**

### **2.1. Ir a GitHub Actions**

1. En tu repo, click en **Actions** (arriba)

2. En el sidebar izquierdo, busca:
   ```
   Infrastructure Apply (Manual)
   ```

3. Click en ese workflow

### **2.2. Ejecutar el Workflow**

1. Click en **Run workflow** (botón azul a la derecha)

2. Se abre un dropdown con opciones:

   **Use workflow from:** `develop`

   **Environment to deploy:** Seleccionar `dev`

   **Action to perform:** Seleccionar `apply`

   **Auto-approve apply:** ✅ Marcar (para dev está OK)

3. Click **Run workflow** (verde)

### **2.3. Monitorear la Ejecución**

1. La página se recargará y verás el workflow corriendo

2. Click en el nombre del run (ej: "feat: add manual deployment...")

3. Click en el job **Terragrunt apply - dev**

4. Verás el output en tiempo real:

```
🔧 Initializing Terragrunt for dev...
✅ Validating configurations...
📋 Running plan for dev...
🚀 Applying changes to dev...

[VPC] Creating vpc...
[VPC] Creating subnet 1/9...
[EKS] Creating cluster...
...
```

**⏰ Tiempo estimado:** 15-20 minutos

---

## 📋 **PASO 3: Verificar Deployment**

### **3.1. Verificar en AWS Console**

Una vez que el workflow termine con éxito (✅):

**VPC:**
```
AWS Console → VPC → Your VPCs
Buscar: fintech-vpc-dev
```

**EKS:**
```
AWS Console → EKS → Clusters
Buscar: fintech-eks-dev
Status: Active
```

**S3:**
```
AWS Console → S3
Buscar: loki-logs-dev-*
```

**ECR:**
```
AWS Console → ECR → Private repositories
Buscar: service-a, service-b
```

### **3.2. Verificar desde Terminal (Local)**

```bash
# 1. Conectar a EKS
aws eks update-kubeconfig --name fintech-eks-dev --region us-east-1

# 2. Verificar nodos
kubectl get nodes
# Expected output:
# NAME                         STATUS   ROLES    AGE   VERSION
# ip-10-0-1-123.ec2.internal   Ready    <none>   5m    v1.30.x
# ip-10-0-2-456.ec2.internal   Ready    <none>   5m    v1.30.x

# 3. Verificar namespaces
kubectl get namespaces

# 4. Verificar system pods
kubectl get pods -n kube-system

# 5. Verificar recursos AWS
aws ec2 describe-vpcs --filters "Name=tag:Environment,Values=dev"
aws s3 ls | grep dev
aws ecr describe-repositories

# 6. Verificar costos (últimos 7 días)
aws ce get-cost-and-usage \
  --time-period Start=$(date -d "7 days ago" +%Y-%m-%d),End=$(date +%Y-%m-%d) \
  --granularity DAILY \
  --metrics "BlendedCost" \
  --filter file://cost-filter-dev.json

# Crear cost-filter-dev.json:
{
  "Tags": {
    "Key": "Environment",
    "Values": ["dev"]
  }
}
```

---

## 📊 **PASO 4: Validar Outputs del Deployment**

En el workflow de GitHub Actions, al final verás un **Summary**:

```
✅ Terragrunt apply - dev

Action: apply
Environment: dev
AWS Region: us-east-1
Triggered by: @tu-usuario

VPC ID: vpc-0abc123def456789
EKS Cluster: fintech-eks-dev
```

**Guarda estos valores**, los necesitarás para los siguientes pasos.

---

## 🎯 **Próximos Pasos**

### **Opción 1: Desplegar Staging (Recomendado)**

Una vez que dev esté estable:

1. Crear `infrastructure/staging/`
2. Crear branch `staging` en GitHub
3. Configurar GitHub Environment `staging`
4. Ejecutar workflow manual para staging

Ver: [Deployment Guide - Fase 2](docs/DEPLOYMENT_GUIDE.md#fase-2-staging-environment-1-día)

### **Opción 2: Desplegar Observability en Dev**

Con dev funcionando, desplegar el stack de observabilidad:

1. ArgoCD
2. OpenTelemetry Operator
3. Prometheus + Grafana
4. Loki + Tempo

Ver: `docs/OBSERVABILITY_DEPLOYMENT.md` (próximamente)

### **Opción 3: Desplegar Microservicios en Dev**

Con infraestructura lista, desplegar services:

1. Build imágenes Docker
2. Push a ECR
3. Deploy con ArgoCD

Ver: `docs/SERVICES_DEPLOYMENT.md` (próximamente)

---

## 🚨 **Troubleshooting**

### **Error: "Environment not found"**

**Causa:** El GitHub Environment `dev` no está creado.

**Solución:**
```
Settings → Environments → New environment → "dev"
```

### **Error: "Unable to assume role"**

**Causa:** AWS OIDC no configurado o secrets incorrectos.

**Solución:**
```bash
# 1. Verificar que el role existe
aws iam get-role --role-name github-actions-terragrunt

# 2. Si no existe, ejecutar:
./github-oidc-role-v2.sh

# 3. Agregar AWS_ACCOUNT_ID al environment secret en GitHub
```

### **Error: "S3 bucket does not exist"**

**Causa:** Backend de Terraform no creado.

**Solución:**
```bash
cd infrastructure/bootstrap
./create-state-backend.sh create
```

### **Error: "Unsupported argument: repository_tags"**

**Causa:** Cache de Terragrunt con código viejo.

**Solución:** Ya está corregido en el código. Si persiste:
```bash
cd infrastructure/dev
rm -rf */.terragrunt-cache
```

### **Workflow falla en "Apply"**

**Causa:** Puede ser un límite de AWS, permisos, o recurso ya existe.

**Solución:**
1. Ver logs completos del workflow
2. Identificar el recurso que falla
3. Verificar en AWS Console si existe
4. Si es necesario, destroy y reintentar:

```bash
# Desde GitHub Actions:
Run workflow → Environment: dev → Action: destroy
```

---

## 💰 **Monitoreo de Costos**

**Dev Environment - Costos Esperados:**

| Servicio | Costo Mensual | Notas |
|----------|---------------|-------|
| EKS Control Plane | $73 | Flat fee |
| EC2 (2x t3.medium) | ~$60 | On-demand |
| NAT Gateway (1x) | ~$32 | + data transfer |
| S3 (Loki logs) | ~$5-10 | Con lifecycle |
| ECR | ~$1 | Por GB storage |
| EBS Volumes | ~$20 | Para nodos |
| **TOTAL** | **~$200-250/mes** | Estimado |

**Para reducir costos en dev:**

```hcl
# infrastructure/dev/eks/terragrunt.hcl
inputs = {
  # Solo 1 NAT Gateway (no HA)
  enable_nat_gateway = true
  single_nat_gateway = true

  # Nodes más pequeños
  instance_types = ["t3.small"]  # En lugar de t3.medium
  min_size = 1
  max_size = 3
  desired_size = 1
}
```

---

## 📚 **Recursos**

- [Deployment Guide Completa](docs/DEPLOYMENT_GUIDE.md)
- [Workflows Architecture](WORKFLOWS_ARCHITECTURE.md)
- [Terragrunt v1 Migration](infrastructure/TERRAGRUNT_V1_MIGRATION.md)
- [AWS EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)

---

## ✅ **Checklist Final**

Antes de marcar dev como "completo":

- [ ] VPC creada con 9 subnets
- [ ] EKS cluster en estado "Active"
- [ ] 2-3 nodos running en EKS
- [ ] S3 bucket para Loki creado
- [ ] ECR repositories creados (service-a, service-b)
- [ ] IAM roles IRSA funcionando
- [ ] `kubectl get nodes` funciona
- [ ] `kubectl get pods -n kube-system` muestra pods healthy
- [ ] Costos monitoreados en AWS Cost Explorer
- [ ] Terraform state guardado en S3 con versioning

---

🎉 **¡Felicidades! Tu Dev Environment está desplegado.**

**Siguiente:** [Desplegar Staging](docs/DEPLOYMENT_GUIDE.md#fase-2-staging-environment-1-día)
