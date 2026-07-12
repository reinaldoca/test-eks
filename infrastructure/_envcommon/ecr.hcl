# ECR Module Common Configuration
# Repositorios de Docker para microservicios

terraform {
  source = "tfr://registry.terraform.io/terraform-aws-modules/ecr/aws?version=2.3.0"
}

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
# ECR Repository para ${service}
module "ecr_${replace(service, "-", "_")}" {
  source  = "terraform-aws-modules/ecr/aws"
  version = "~> 2.0"

  repository_name = "${service}"

  # Lifecycle policy
  repository_lifecycle_policy = <<POLICY
${local.lifecycle_policy}
POLICY

  # Image scanning en push
  repository_image_scan_on_push = true

  # Tag immutability (previene sobrescribir tags)
  repository_image_tag_mutability = "MUTABLE"

  # Encryption con KMS
  repository_encryption_type = "KMS"
  repository_kms_key         = aws_kms_key.ecr.arn

  # Force delete (CUIDADO: elimina repo con imágenes)
  repository_force_delete = false

  # Tags (usar 'tags' en lugar de 'repository_tags')
  tags = {
    Name        = "${service}"
    Environment = "${local.environment}"
    Service     = "${service}"
    ManagedBy   = "terragrunt"
  }
}

# Repository policy comentado para primer deployment
# El rol github-actions-ecr aún no existe
# Se configurará después cuando se cree el rol con GitHub OIDC

# Output del repository URL
output "${replace(service, "-", "_")}_repository_url" {
  description = "URL of ECR repository for ${service}"
  value       = module.ecr_${replace(service, "-", "_")}.repository_url
}

output "${replace(service, "-", "_")}_repository_arn" {
  description = "ARN of ECR repository for ${service}"
  value       = module.ecr_${replace(service, "-", "_")}.repository_arn
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
      url = module.ecr_${replace(service, "-", "_")}.repository_url
      arn = module.ecr_${replace(service, "-", "_")}.repository_arn
    }
%{ endfor ~}
  }
}
EOF
}

inputs = {
  environment = local.environment
}
