# Orden de Deployment - Dev Environment

Para evitar errores de dependencias, desplegar en este orden:

## Fase 1: Recursos Simples (Sin Dependencias)
```bash
cd infrastructure/dev

# 1. VPC (base de todo)
cd vpc
terragrunt init --upgrade
terragrunt plan
terragrunt apply

# 2. S3 (independiente)
cd ../s3-loki
terragrunt init --upgrade
terragrunt plan
terragrunt apply

# 3. ECR (independiente)
cd ../ecr
terragrunt init --upgrade
terragrunt plan
terragrunt apply
```

## Fase 2: EKS (Depende de VPC)
```bash
cd ../eks
terragrunt init --upgrade
terragrunt plan
terragrunt apply
```

## Fase 3: IAM (Depende de EKS)
```bash
cd ../iam-roles
terragrunt init --upgrade
terragrunt plan
terragrunt apply
```

## Deploy Todo de Una Vez (Cuando Todo Funcione)
```bash
cd infrastructure/dev
terragrunt run --all --non-interactive apply -- -auto-approve
```
