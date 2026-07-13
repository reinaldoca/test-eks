# Troubleshooting Guide - Dev Environment

Soluciones a problemas comunes en el deployment de infraestructura.

---

## 🔒 State Lock Issues

### Síntoma
```
Acquiring state lock. This may take a few moments...
```
El comando se queda colgado indefinidamente.

### Causa
El workflow anterior fue cancelado sin liberar el lock de DynamoDB.

### Solución

#### Opción 1: Script Local (Recomendado)
```bash
cd infrastructure/dev

# Con perfil AWS configurado
export AWS_PROFILE=santi

# Liberar locks
./deploy-dev.sh unlock
```

#### Opción 2: GitHub Actions Workflow
1. Ve a: **Actions** → **Unlock Terraform State**
2. Click **Run workflow**
3. Selecciona environment: `dev`
4. Escribe: `unlock` en confirmación
5. Click **Run workflow**

#### Opción 3: Manual (AWS CLI)
```bash
export AWS_PROFILE=santi

# Listar locks
aws dynamodb scan \
  --table-name "fintech-platform-terraform-locks" \
  --region us-east-1 \
  --output json | jq '.Items[] | .LockID.S'

# Liberar lock específico (reemplaza LOCK_ID)
aws dynamodb delete-item \
  --table-name "fintech-platform-terraform-locks" \
  --key '{"LockID": {"S": "LOCK_ID_AQUI"}}' \
  --region us-east-1
```

---

## ❌ Workflow Failures

### Error: `out of memory`
**Síntoma:** 
```
fatal error: out of memory
runtime stack: runtime.throw
```

**Causa:** Bug en AWS Provider v6.x con EKS Auto Mode.

**Solución:** Ya revertido a managed node groups con provider v5.x. Si persiste:
1. Verificar `infrastructure/_envcommon/eks.hcl` usa módulo `terraform-aws-modules/eks`
2. Verificar `versions_override.tf` genera provider v5.x
3. Limpiar cache: `./deploy-dev.sh init --no-cache-clean`

---

### Error: `taint effect invalid`
**Síntoma:**
```
Error: expected effect to be one of ["NO_SCHEDULE" "NO_EXECUTE" "PREFER_NO_SCHEDULE"], got NoSchedule
```

**Solución:** Ya corregido en commit `d916c79`. Valores válidos:
- `NO_SCHEDULE` (no `NoSchedule`)
- `NO_EXECUTE` (no `NoExecute`)
- `PREFER_NO_SCHEDULE` (no `PreferNoSchedule`)

---

### Error: `role_policy_arns map required`
**Síntoma:**
```
Error: Invalid value for input variable
The given value is not suitable for module.irsa_grafana.var.role_policy_arns
map of string required.
```

**Solución:** Ya corregido en commit `cdeb532`. El módulo IRSA requiere map, no lista:
```hcl
# ❌ Incorrecto
role_policy_arns = ["arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess"]

# ✅ Correcto
role_policy_arns = {
  policy_0 = "arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess"
}
```

---

### Error: Node groups stuck "Creating"
**Síntoma:** En AWS Console, node groups quedan en estado "Creating" indefinidamente.

**Causa:** EKS Auto Mode no soportado, o managed node groups con error.

**Solución:**
1. **Verificar configuración actual:**
   ```bash
   cd infrastructure/dev/eks
   cat .terragrunt-cache/*/eks_auto_mode.tf 2>/dev/null || echo "Usando módulo EKS"
   ```

2. **Si existe `eks_auto_mode.tf`** (recursos nativos):
   - NO SOPORTADO aún por AWS Provider
   - Ejecutar: `git pull origin develop` (ya revertido)

3. **Si usa módulo EKS** (correcto):
   - Verificar logs de EKS en CloudWatch: `/aws/eks/fintech-eks-dev/cluster`
   - Verificar IAM roles: `aws iam get-role --role-name fintech-eks-dev-cluster-role`

---

## 🔄 Dependency Issues

### Error: `dependency has no outputs`
**Síntoma:**
```
Config /path/to/eks/terragrunt.hcl is a dependency of /path/to/iam-roles/terragrunt.hcl that has no outputs
```

**Solución:** Ya configurado `mock_outputs` en dependencies. Si persiste:

1. **Verificar mock outputs en dependent module:**
   ```hcl
   dependency "eks" {
     config_path = "../eks"

     mock_outputs = {
       cluster_name            = "fintech-eks-dev-mock"
       oidc_provider_arn       = "arn:aws:iam::475274912371:oidc-provider/..."
       cluster_oidc_issuer_url = "https://oidc.eks.us-east-1.amazonaws.com/id/MOCK123"
     }
   }
   ```

2. **Ejecutar en orden:**
   ```bash
   ./deploy-dev.sh apply --target=vpc
   ./deploy-dev.sh apply --target=eks
   ./deploy-dev.sh apply --target=iam-roles
   ```

---

## 🐛 Module Errors

### Error: `repository_tags not supported`
**Síntoma:**
```
Error: Unsupported argument: An argument named "repository_tags" is not expected here.
```

**Solución:** Ya corregido. ECR usa `tags`, no `repository_tags`:
```hcl
resource "aws_ecr_repository" "service_a" {
  name = "service-a"
  tags = {
    Name = "service-a"
  }
}
```

---

### Error: S3 replication_configuration null
**Síntoma:**
```
Error: replication_configuration must not be null
```

**Solución:** Ya simplificado en commit. S3 para primer deployment no usa:
- Replication (target bucket no existe aún)
- Logging (logging bucket no existe aún)
- Complex lifecycle (solo: expire after 90 days)

---

## 🔍 Debugging Tips

### Ver logs de Terragrunt en detalle
```bash
export TF_LOG=DEBUG
./deploy-dev.sh plan --target=eks 2>&1 | tee debug.log
```

### Ver estado actual de recursos
```bash
cd infrastructure/dev/eks
terragrunt state list
terragrunt state show aws_eks_cluster.main
```

### Ver outputs de módulo
```bash
cd infrastructure/dev/eks
terragrunt output -json | jq
```

### Validar configuración sin ejecutar plan
```bash
./deploy-dev.sh validate --target=eks
```

### Limpiar cache completamente
```bash
find infrastructure/dev -type d -name ".terragrunt-cache" -exec rm -rf {} + 2>/dev/null
./deploy-dev.sh init
```

---

## 📊 Verificar Estado de Recursos

### VPC
```bash
export AWS_PROFILE=santi
aws ec2 describe-vpcs \
  --filters "Name=tag:Environment,Values=dev" \
  --query 'Vpcs[*].[VpcId,CidrBlock,State]' \
  --output table
```

### EKS Cluster
```bash
aws eks describe-cluster \
  --name fintech-eks-dev \
  --query 'cluster.[name,status,version,endpoint]' \
  --output table
```

### Node Groups
```bash
aws eks list-nodegroups \
  --cluster-name fintech-eks-dev \
  --output json | jq
```

### S3 Buckets
```bash
aws s3 ls | grep "loki-logs-dev"
```

### ECR Repositories
```bash
aws ecr describe-repositories \
  --repository-names service-a service-b \
  --query 'repositories[*].[repositoryName,repositoryUri]' \
  --output table
```

### IAM Roles (IRSA)
```bash
aws iam list-roles \
  --query 'Roles[?contains(RoleName, `fintech-eks-dev`)].RoleName' \
  --output table
```

### DynamoDB Locks
```bash
aws dynamodb scan \
  --table-name "fintech-platform-terraform-locks" \
  --region us-east-1 \
  --query 'Items | length(@)' \
  --output text
```

---

## 🚨 Emergency Procedures

### Destruir todo (reset completo)
⚠️ **PELIGROSO** - Solo usar en dev, nunca en production.

```bash
cd infrastructure/dev

# Liberar locks primero
./deploy-dev.sh unlock

# Destruir en orden inverso
./deploy-dev.sh destroy --target=iam-roles
./deploy-dev.sh destroy --target=eks
./deploy-dev.sh destroy --target=ecr
./deploy-dev.sh destroy --target=s3-loki
./deploy-dev.sh destroy --target=vpc

# Verificar que todo se destruyó
./deploy-dev.sh output
```

### Recuperar de estado inconsistente
```bash
# 1. Liberar locks
./deploy-dev.sh unlock

# 2. Refrescar state
cd eks
terragrunt refresh

# 3. Ver diferencias
terragrunt plan

# 4. Aplicar solo cambios necesarios
terragrunt apply
```

---

## 📞 Contacto y Recursos

- **Logs de GitHub Actions:** https://github.com/reinaldoca/test-eks/actions
- **AWS Console:** https://console.aws.amazon.com/
- **Terragrunt Docs:** https://terragrunt.gruntwork.io/docs/
- **Terraform AWS Provider:** https://registry.terraform.io/providers/hashicorp/aws/latest/docs

---

## 📝 Checklist de Deployment

Antes de ejecutar `apply`:

- [ ] AWS credentials configuradas (`export AWS_PROFILE=santi`)
- [ ] En directorio correcto (`infrastructure/dev/`)
- [ ] No hay locks activos (`./deploy-dev.sh unlock`)
- [ ] Plan revisado (`./deploy-dev.sh plan`)
- [ ] No hay workflows corriendo en GitHub Actions
- [ ] Cambios commiteados en Git

Durante el deployment:

- [ ] Monitorear logs en tiempo real
- [ ] Verificar cada módulo individualmente si falla `run --all`
- [ ] NO cancelar workflow a menos que sea crítico (deja locks)

Después del deployment:

- [ ] Verificar outputs (`./deploy-dev.sh output`)
- [ ] Conectar a EKS: `aws eks update-kubeconfig --name fintech-eks-dev`
- [ ] Verificar nodos: `kubectl get nodes`
- [ ] Verificar addons: `kubectl get daemonset -n kube-system`
