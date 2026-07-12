# ECR Configuration
# NO usar módulo externo, generar código Terraform puro inline

locals {
  # Cargar variables del entorno
  region_vars = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  environment = local.region_vars.locals.environment

  # Lista de microservicios que necesitan ECR repository
  services = [
    "service-a",
    "service-b",
  ]

  # Lifecycle policy común para todos los repos
  lifecycle_policy = jsonencode({
    rules = [
      # Mantener últimas 10 imágenes taggeadas
      {
        rulePriority = 1
        description  = "Keep last 10 tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["main-", "develop-", "v"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = {
          type = "expire"
        }
      },
      # Eliminar imágenes sin tag después de 7 días
      {
        rulePriority = 2
        description  = "Delete untagged images after 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# Generar un módulo inline para crear múltiples repos
generate "ecr_repositories" {
  path      = "ecr_repositories.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
%{ for service in local.services ~}
# ECR Repository para ${service} (recurso nativo de Terraform)
resource "aws_ecr_repository" "${replace(service, "-", "_")}" {
  name                 = "${service}"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.ecr.arn
  }

  force_delete = false

  tags = {
    Name        = "${service}"
    Environment = "${local.environment}"
    Service     = "${service}"
    ManagedBy   = "terragrunt"
  }
}

# Lifecycle policy
resource "aws_ecr_lifecycle_policy" "${replace(service, "-", "_")}_lifecycle" {
  repository = aws_ecr_repository.${replace(service, "-", "_")}.name

  policy = <<POLICY
${local.lifecycle_policy}
POLICY
}

# Repository policy comentado para primer deployment
# El rol github-actions-ecr aún no existe
# Se configurará después cuando se cree el rol con GitHub OIDC

# Output del repository URL
output "${replace(service, "-", "_")}_repository_url" {
  description = "URL of ECR repository for ${service}"
  value       = aws_ecr_repository.${replace(service, "-", "_")}.repository_url
}

output "${replace(service, "-", "_")}_repository_arn" {
  description = "ARN of ECR repository for ${service}"
  value       = aws_ecr_repository.${replace(service, "-", "_")}.arn
}
%{ endfor ~}

# Data sources (eliminado, el módulo ECR ya lo incluye)

# KMS key para ECR encryption
resource "aws_kms_key" "ecr" {
  description             = "KMS key for ECR encryption in ${local.environment}"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = {
    Name        = "ecr-encryption-key-${local.environment}"
    Environment = "${local.environment}"
  }
}

resource "aws_kms_alias" "ecr" {
  name          = "alias/ecr-${local.environment}"
  target_key_id = aws_kms_key.ecr.key_id
}

# Output de KMS key
output "ecr_kms_key_arn" {
  description = "ARN of KMS key for ECR encryption"
  value       = aws_kms_key.ecr.arn
}

# Output consolidado de todos los repos
output "ecr_repositories" {
  description = "Map of all ECR repositories"
  value = {
%{ for service in local.services ~}
    ${service} = {
      url = aws_ecr_repository.${replace(service, "-", "_")}.repository_url
      arn = aws_ecr_repository.${replace(service, "-", "_")}.arn
    }
%{ endfor ~}
  }
}
EOF
}

inputs = {
  environment = local.environment
}
