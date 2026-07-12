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

  # Lifecycle rules
  lifecycle_rule = [
    # Logs activos (alta performance)
    {
      id      = "active-logs"
      enabled = true

      filter = {
        prefix = "active/"
      }

      transition = [
        {
          days          = 7
          storage_class = "STANDARD_IA"
        },
        {
          days          = 30
          storage_class = "GLACIER"
        }
      ]

      expiration = {
        days = 90
      }

      noncurrent_version_expiration = {
        days = 30
      }
    },

    # Logs de auditoría (retención más larga por compliance)
    {
      id      = "audit-logs"
      enabled = true

      filter = {
        prefix = "audit/"
      }

      transition = [
        {
          days          = 90
          storage_class = "GLACIER"
        },
        {
          days          = 365
          storage_class = "DEEP_ARCHIVE"
        }
      ]

      expiration = {
        days = 730  # 2 años para compliance (SOC2/ISO27001)
      }

      noncurrent_version_expiration = {
        days = 90
      }
    }
  ]

  # CORS para Grafana (si se accede directo)
  cors_rule = [
    {
      allowed_methods = ["GET", "PUT", "POST"]
      allowed_origins = ["https://grafana.fintech.com"]
      allowed_headers = ["*"]
      expose_headers  = ["ETag"]
      max_age_seconds = 3000
    }
  ]

  # Logging del bucket (para auditoría)
  logging = {
    target_bucket = "fintech-access-logs-${local.environment}-${get_aws_account_id()}"
    target_prefix = "loki-bucket-logs/"
  }

  # Replicación cross-region para DR (deshabilitado para dev/staging)
  # Nota: En dev/staging no usamos replication para reducir costos
  # replication_configuration = {} # Comentado para dev, habilitar en production

  # Bucket policy (acceso solo desde VPC y roles específicos)
  attach_policy = true
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Permitir acceso desde VPC (via VPC endpoint)
      {
        Sid    = "AllowVPCAccess"
        Effect = "Allow"
        Principal = "*"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${local.bucket_name}",
          "arn:aws:s3:::${local.bucket_name}/*"
        ]
        Condition = {
          StringEquals = {
            "aws:SourceVpc" = "vpc-id-placeholder"  # Reemplazar con VPC ID real
          }
        }
      },

      # Permitir acceso desde roles específicos
      {
        Sid    = "AllowOTELCollectorAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${get_aws_account_id()}:role/fintech-eks-${local.environment}-otel-collector"
        }
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${local.bucket_name}",
          "arn:aws:s3:::${local.bucket_name}/*"
        ]
      },

      # Permitir acceso desde Grafana (read-only)
      {
        Sid    = "AllowGrafanaAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${get_aws_account_id()}:role/fintech-eks-${local.environment}-grafana"
        }
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${local.bucket_name}",
          "arn:aws:s3:::${local.bucket_name}/*"
        ]
      },

      # Denegar acceso sin SSL
      {
        Sid    = "DenyInsecureTransport"
        Effect = "Deny"
        Principal = "*"
        Action = "s3:*"
        Resource = [
          "arn:aws:s3:::${local.bucket_name}",
          "arn:aws:s3:::${local.bucket_name}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })

  # Tags
  tags = {
    Name        = local.bucket_name
    Environment = local.environment
    Purpose     = "loki-logs-storage"
    Compliance  = "soc2-iso27001"
  }
}
