# Terragrunt Root Configuration
# Configuración global para todos los entornos (dev, staging, production)

locals {
  # Cargar variables de entorno desde archivo region.hcl
  region_vars = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  # Cargar variables de cuenta AWS
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl", "account.hcl"), {})

  # Extraer valores comunes
  aws_region     = local.region_vars.locals.aws_region
  aws_account_id = try(local.account_vars.locals.aws_account_id, get_aws_account_id())
  environment    = local.region_vars.locals.environment

  # Nombre del proyecto
  project_name = "fintech-platform"

  # Tags comunes para todos los recursos
  common_tags = {
    Project     = local.project_name
    Environment = local.environment
    ManagedBy   = "terragrunt"
    Owner       = "platform-engineering"
    CostCenter  = "infrastructure"
    Compliance  = "soc2-iso27001-gdpr-pci"
  }
}

# Configuración del remote state en S3
remote_state {
  backend = "s3"

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }

  config = {
    bucket         = "${local.project_name}-terraform-state-${local.aws_account_id}"
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = local.aws_region
    encrypt        = true
    dynamodb_table = "${local.project_name}-terraform-locks"

    # S3 bucket versioning para recuperación de estados
    s3_bucket_tags = merge(
      local.common_tags,
      {
        Name = "${local.project_name}-terraform-state"
        Purpose = "terraform-state-backend"
      }
    )

    dynamodb_table_tags = merge(
      local.common_tags,
      {
        Name = "${local.project_name}-terraform-locks"
        Purpose = "terraform-state-locking"
      }
    )
  }
}

# Generar provider AWS para todos los módulos
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.31"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.24"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
  }
}

provider "aws" {
  region = "${local.aws_region}"

  default_tags {
    tags = ${jsonencode(local.common_tags)}
  }

  # Configuración de retries para APIs de AWS
  retry_mode = "adaptive"
  max_retries = 3
}
EOF
}

# Inputs comunes que se pasarán a todos los módulos hijos
inputs = {
  aws_region     = local.aws_region
  aws_account_id = local.aws_account_id
  environment    = local.environment
  project_name   = local.project_name
  common_tags    = local.common_tags
}

# Configuración de Terraform
terraform {
  # Argumentos extra para terraform init
  extra_arguments "init_args" {
    commands = [
      "init",
      "plan",
      "apply",
      "destroy",
      "refresh",
      "import"
    ]

    env_vars = {
      AWS_SDK_LOAD_CONFIG = "1"
    }
  }

  # Configuración de retry para comandos de Terraform
  extra_arguments "retry_lock" {
    commands  = get_terraform_commands_that_need_locking()
    arguments = ["-lock-timeout=10m"]
  }

  # Paralelismo para mejorar performance
  extra_arguments "parallelism" {
    commands  = get_terraform_commands_that_need_parallelism()
    arguments = ["-parallelism=20"]
  }
}

# Hooks before/after para auditoría
terraform_version_constraint  = ">= 1.6.0"
terragrunt_version_constraint = ">= 0.54.0"

# Hook para ejecutar antes de cada comando
# Útil para validaciones y preparación del entorno
before_hook "before_hook" {
  commands     = ["apply", "plan"]
  execute      = ["echo", "🚀 Ejecutando Terragrunt en ${local.environment}..."]
  run_on_error = true
}

# Hook después de cada apply exitoso
after_hook "after_hook" {
  commands     = ["apply"]
  execute      = ["echo", "✅ Infraestructura aplicada exitosamente en ${local.environment}"]
  run_on_error = false
}
