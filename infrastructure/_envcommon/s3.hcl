# S3 Module Common Configuration
# Bucket para Loki logs con lifecycle policies y seguridad

terraform {
  source = "tfr://registry.terraform.io/terraform-aws-modules/s3-bucket/aws?version=4.2.2"
}

locals {
  # Cargar variables del entorno
  region_vars = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  environment = local.region_vars.locals.environment
  aws_region  = local.region_vars.locals.aws_region

  # Nombre del bucket (debe ser globalmente único)
  bucket_name = "loki-logs-${local.environment}-${get_aws_account_id()}"
}

inputs = {
  # Nombre del bucket
  bucket = local.bucket_name

  # Forzar uso de ACLs deshabilitados (usar bucket policies)
  acl = null

  # Control de ownership
  control_object_ownership = true
  object_ownership         = "BucketOwnerEnforced"

  # Versionamiento (para recuperación)
  versioning = {
    enabled    = true
    mfa_delete = false  # Cambiar a true en producción con MFA configurado
  }

  # Encriptación en reposo (KMS)
  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm     = "aws:kms"
        kms_master_key_id = "arn:aws:kms:${local.aws_region}:${get_aws_account_id()}:alias/loki-encryption-key"
      }
      bucket_key_enabled = true
    }
  }

  # Bloquear acceso público
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  # Intelligent-Tiering para optimización automática de costos
  intelligent_tiering = {
    general = {
      status = "Enabled"
      tiering = {
        ARCHIVE_ACCESS = {
          days = 90
        }
        DEEP_ARCHIVE_ACCESS = {
          days = 180
        }
      }
    }
  }

  # Lifecycle rules (simplificado para dev)
  lifecycle_rule = [
    {
      id      = "expire-old-logs"
      enabled = true

      expiration = {
        days = 90  # Eliminar logs después de 90 días
      }

      noncurrent_version_expiration = {
        days = 30
      }
    }
  ]

  # CORS y Logging deshabilitados para simplificar primer deployment
  # Se pueden habilitar después

  # Replicación cross-region para DR (deshabilitado para dev/staging)
  # Nota: En dev/staging no usamos replication para reducir costos
  # replication_configuration = {} # Comentado para dev, habilitar en production

  # Bucket policy deshabilitado para primer deployment
  # Se configurará después cuando existan los roles IAM
  attach_policy = false

  # Tags
  tags = {
    Name        = local.bucket_name
    Environment = local.environment
    Purpose     = "loki-logs-storage"
    Compliance  = "soc2-iso27001"
  }
}
