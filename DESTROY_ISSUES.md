# 🔥 Problemas con Destroy - Resumen y Solución

**Fecha:** 2026-07-13  
**Issue:** `./deploy-dev.sh destroy --auto-approve` no destruyó los recursos correctamente

---

## 🔍 Análisis del Problema

### Problemas Encontrados

1. **Sintaxis incorrecta de Terragrunt v1.1.0**
   - ❌ Usaba: `terragrunt run-all destroy --terragrunt-non-interactive`
   - ✅ Debe ser: `terragrunt --non-interactive run --all destroy -- -auto-approve`

2. **Dependency de EKS bloqueando destroy**
   - El módulo `iam-roles` tenía una dependency de EKS
   - Durante destroy, Terragrunt intentaba resolver outputs de EKS
   - Fix aplicado: Eliminada dependency, ahora usa data sources

3. **State inconsistente con AWS**
   - Algunos recursos ya fueron destruidos manualmente en AWS
   - Terraform state todavía los tiene registrados
   - Causa errores al intentar destroy completo

4. **Out of Memory en IAM module**
   - El módulo IAM se quedó sin memoria durante destroy
   - Posiblemente por el data source queriendo consultar EKS que ya no existe

### Estado Actual de Recursos

**✅ Recursos que EXISTEN en AWS:**
- VPC: `vpc-0bb2a1f695ae86a9e` (9 subnets, 3 NAT GW, 1 IGW)
- EKS Cluster: `fintech-eks-dev` (ACTIVE, version 1.30)
- EKS Cluster IAM Role: `fintech-eks-dev-cluster-...`
- Security Groups, Route Tables, etc. (asociados a VPC)

**❌ Recursos que NO EXISTEN en AWS:**
- S3 Bucket: `loki-logs-dev-475274912371`
- ECR Repositories: `service-a`, `service-b`
- IAM IRSA Roles (6): otel-collector, grafana, external-secrets, service-a, service-b, velero
- KMS Keys (2): secrets-encryption-key-dev, loki-encryption-key-dev

---

## ✅ Soluciones

### Opción 1: Destroy Manual por Módulos (RECOMENDADO)

Destruir los módulos uno por uno en orden inverso de dependencias:

```bash
export AWS_PROFILE=santi
cd infrastructure/dev

# 1. Destruir IAM roles (ya no existen en AWS, solo limpiar state)
cd iam-roles
terragrunt destroy -auto-approve
cd ..

# 2. Destruir EKS cluster
cd eks
terragrunt destroy -auto-approve
cd ..

# 3. Destruir VPC
cd vpc
terragrunt destroy -auto-approve
cd ..

# 4. Destruir S3 (ya destruido, solo limpiar state)
cd s3-loki
terragrunt destroy -auto-approve
cd ..

# 5. Destruir ECR (ya destruido, solo limpiar state)
cd ecr
terragrunt destroy -auto-approve
cd ..
```

### Opción 2: Limpiar State de Recursos No Existentes

Si los recursos ya no existen en AWS, puedes removerlos del state:

```bash
export AWS_PROFILE=santi
cd infrastructure/dev

# Listar recursos en state
cd iam-roles && terragrunt state list
cd ../s3-loki && terragrunt state list
cd ../ecr && terragrunt state list

# Remover recursos específicos del state
cd iam-roles
terragrunt state rm 'aws_iam_role.xxx'
# ... repetir para cada recurso
```

### Opción 3: Destroy con Target Específico

```bash
export AWS_PROFILE=santi
cd infrastructure/dev

# Destruir solo EKS (el recurso más importante)
./deploy-dev.sh destroy --target=eks --auto-approve

# Destruir solo VPC
./deploy-dev.sh destroy --target=vpc --auto-approve
```

### Opción 4: Forzar Refresh y Destroy

```bash
export AWS_PROFILE=santi
cd infrastructure/dev

# Refrescar state para sincronizar con AWS
terragrunt run --all refresh

# Luego destruir
./deploy-dev.sh destroy --auto-approve
```

---

## 🛠️ Fixes Aplicados al Script

### 1. Corrección de Sintaxis Terragrunt v1.1.0

**Archivo:** `infrastructure/dev/deploy-dev.sh`

**Cambios:**
```bash
# ANTES (incorrecto):
terragrunt run-all destroy --terragrunt-non-interactive -auto-approve

# DESPUÉS (correcto):
terragrunt --non-interactive run --all destroy -- -auto-approve
```

**Razón:**
- En Terragrunt v1.1.0, el comando cambió de `run-all` a `run --all`
- El flag cambió de `--terragrunt-non-interactive` a `--non-interactive`
- El flag `--non-interactive` debe ir **ANTES** de `run`
- Los flags de Terraform deben ir **DESPUÉS** de `--`

### 2. Eliminación de Dependency de EKS

**Archivo:** `infrastructure/dev/iam-roles/terragrunt.hcl`

**Cambios:**
```hcl
# ELIMINADO (ya no necesario):
dependency "eks" {
  config_path = "../eks"
  mock_outputs = { ... }
}

# REEMPLAZADO POR: data sources en _envcommon/iam.hcl
data "aws_eks_cluster" "this" {
  name = var.cluster_name
}

data "aws_iam_openid_connect_provider" "this" {
  url = data.aws_eks_cluster.this.identity[0].oidc[0].issuer
}
```

**Razón:**
- La dependency causaba que destroy fallara al intentar resolver outputs de EKS
- Los data sources consultan directamente a AWS sin depender de Terraform state
- Permite destroy de IAM roles incluso si EKS no está en state

---

## 📋 Comandos Útiles

### Verificar Estado Actual

```bash
export AWS_PROFILE=santi

# Ver qué hay en Terraform state
cd infrastructure/dev/vpc && terragrunt state list
cd infrastructure/dev/eks && terragrunt state list
cd infrastructure/dev/iam-roles && terragrunt state list

# Ver qué hay en AWS
aws ec2 describe-vpcs --filters "Name=tag:Environment,Values=dev"
aws eks describe-cluster --name fintech-eks-dev
aws iam list-roles --query 'Roles[?contains(RoleName, `fintech-eks-dev`)].RoleName'
```

### Limpiar Locks de DynamoDB

Si el destroy se cancela o falla, puede dejar locks huérfanos:

```bash
cd infrastructure/dev
./deploy-dev.sh unlock
```

---

## 🎯 Recomendación Final

**Para evitar estos problemas en el futuro:**

1. **Siempre usar `./deploy-dev.sh destroy --auto-approve`** (ahora corregido)
2. **No destruir recursos manualmente** en AWS Console sin actualizar Terraform state
3. **Hacer destroy completo** con Terragrunt run-all en lugar de módulo por módulo
4. **Usar `dependencies` block** en lugar de `dependency` cuando no necesites outputs

**Para este caso específico:**

1. Usa **Opción 1** (destroy manual por módulos) para limpiar todo
2. O simplemente destruye EKS y VPC manualmente desde AWS Console
3. Luego ejecuta `terragrunt run --all refresh` para sincronizar state

---

**Commits relacionados:**
- `8431287` - fix(deploy): use terragrunt v1.1.0 syntax for destroy command
- `22306c3` - fix(iam): remove EKS dependency from iam-roles module
- `8c404e3` - fix(iam): use data sources to get OIDC provider from existing cluster
