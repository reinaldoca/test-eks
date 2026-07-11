# IAM Module Common Configuration
# IRSA (IAM Roles for Service Accounts) para workloads en EKS

locals {
  # Cargar variables del entorno
  region_vars = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  environment = local.region_vars.locals.environment
  aws_region  = local.region_vars.locals.aws_region

  # Nombre del cluster
  cluster_name = "fintech-eks-${local.environment}"

  # Namespace para observabilidad
  observability_namespace = "observability"

  # Namespace para servicios
  services_namespace = "production"

  # Service Accounts y sus políticas
  service_accounts = {
    # OpenTelemetry Collector
    otel-collector = {
      namespace = local.observability_namespace
      policies = [
        "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy",
        "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
      ]
      inline_policies = {
        s3_loki_access = jsonencode({
          Version = "2012-10-17"
          Statement = [
            {
              Effect = "Allow"
              Action = [
                "s3:PutObject",
                "s3:GetObject",
                "s3:DeleteObject",
                "s3:ListBucket"
              ]
              Resource = [
                "arn:aws:s3:::loki-logs-${local.environment}-*",
                "arn:aws:s3:::loki-logs-${local.environment}-*/*"
              ]
            }
          ]
        })
      }
    }

    # Grafana
    grafana = {
      namespace = local.observability_namespace
      policies = [
        "arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess"
      ]
      inline_policies = {
        s3_loki_read = jsonencode({
          Version = "2012-10-17"
          Statement = [
            {
              Effect = "Allow"
              Action = [
                "s3:GetObject",
                "s3:ListBucket"
              ]
              Resource = [
                "arn:aws:s3:::loki-logs-${local.environment}-*",
                "arn:aws:s3:::loki-logs-${local.environment}-*/*"
              ]
            },
            {
              Effect = "Allow"
              Action = [
                "athena:StartQueryExecution",
                "athena:GetQueryExecution",
                "athena:GetQueryResults"
              ]
              Resource = "*"
            }
          ]
        })
      }
    }

    # External Secrets Operator
    external-secrets = {
      namespace = "kube-system"
      policies  = []
      inline_policies = {
        secrets_manager = jsonencode({
          Version = "2012-10-17"
          Statement = [
            {
              Effect = "Allow"
              Action = [
                "secretsmanager:GetSecretValue",
                "secretsmanager:DescribeSecret",
                "secretsmanager:ListSecrets"
              ]
              Resource = "arn:aws:secretsmanager:${local.aws_region}:${get_aws_account_id()}:secret:${local.environment}/*"
            },
            {
              Effect = "Allow"
              Action = [
                "kms:Decrypt",
                "kms:DescribeKey"
              ]
              Resource = "arn:aws:kms:${local.aws_region}:${get_aws_account_id()}:key/*"
              Condition = {
                StringEquals = {
                  "kms:ViaService" = "secretsmanager.${local.aws_region}.amazonaws.com"
                }
              }
            }
          ]
        })
      }
    }

    # Service A
    service-a = {
      namespace = local.services_namespace
      policies = [
        "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
      ]
      inline_policies = {}
    }

    # Service B
    service-b = {
      namespace = local.services_namespace
      policies = [
        "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
      ]
      inline_policies = {}
    }

    # Velero (backup)
    velero = {
      namespace = "velero"
      policies  = []
      inline_policies = {
        velero_backup = jsonencode({
          Version = "2012-10-17"
          Statement = [
            {
              Effect = "Allow"
              Action = [
                "s3:PutObject",
                "s3:GetObject",
                "s3:DeleteObject",
                "s3:ListBucket",
                "s3:GetBucketLocation",
                "s3:ListBucketMultipartUploads",
                "s3:ListMultipartUploadParts"
              ]
              Resource = [
                "arn:aws:s3:::velero-backups-${local.environment}",
                "arn:aws:s3:::velero-backups-${local.environment}/*"
              ]
            },
            {
              Effect = "Allow"
              Action = [
                "ec2:DescribeVolumes",
                "ec2:DescribeSnapshots",
                "ec2:CreateTags",
                "ec2:CreateVolume",
                "ec2:CreateSnapshot",
                "ec2:DeleteSnapshot"
              ]
              Resource = "*"
            }
          ]
        })
      }
    }
  }
}

# Dependencias
dependency "eks" {
  config_path = "../eks"

  mock_outputs = {
    cluster_name                         = "fintech-eks-development"
    cluster_oidc_issuer_url              = "https://oidc.eks.us-east-1.amazonaws.com/id/EXAMPLED539D4633E53DE1B716D3041E"
    oidc_provider_arn                    = "arn:aws:iam::111122223333:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/EXAMPLED539D4633E53DE1B716D3041E"
  }
}

# Generar un módulo Terraform inline para crear múltiples roles IRSA
generate "irsa_roles" {
  path      = "irsa_roles.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
# OIDC Provider ya creado por el módulo EKS
# Solo necesitamos crear los roles IAM y las políticas

%{ for sa_name, sa_config in local.service_accounts ~}
# IAM Role para ${sa_name}
module "irsa_${replace(sa_name, "-", "_")}" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.30"

  role_name = "${local.cluster_name}-${sa_name}"

  oidc_providers = {
    main = {
      provider_arn               = "${dependency.eks.outputs.oidc_provider_arn}"
      namespace_service_accounts = ["${sa_config.namespace}:${sa_name}"]
    }
  }

  %{ if length(sa_config.policies) > 0 ~}
  role_policy_arns = ${jsonencode(sa_config.policies)}
  %{ endif ~}

  tags = {
    Name        = "${local.cluster_name}-${sa_name}"
    Environment = "${local.environment}"
    ServiceAccount = "${sa_name}"
  }
}

%{ if length(sa_config.inline_policies) > 0 ~}
# Inline policies para ${sa_name}
%{ for policy_name, policy_doc in sa_config.inline_policies ~}
resource "aws_iam_role_policy" "${replace(sa_name, "-", "_")}_${policy_name}" {
  name   = "${policy_name}"
  role   = module.irsa_${replace(sa_name, "-", "_")}.iam_role_name
  policy = <<POLICY
${policy_doc}
POLICY
}
%{ endfor ~}
%{ endif ~}

# Output del role ARN
output "${replace(sa_name, "-", "_")}_role_arn" {
  description = "ARN of IAM role for ${sa_name}"
  value       = module.irsa_${replace(sa_name, "-", "_")}.iam_role_arn
}
%{ endfor ~}

# KMS Key para encriptación de secrets
resource "aws_kms_key" "secrets" {
  description             = "KMS key for secrets encryption in ${local.environment}"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = {
    Name        = "secrets-encryption-key-${local.environment}"
    Environment = "${local.environment}"
  }
}

resource "aws_kms_alias" "secrets" {
  name          = "alias/secrets-manager-key-${local.environment}"
  target_key_id = aws_kms_key.secrets.key_id
}

# KMS Key para Loki encryption
resource "aws_kms_key" "loki" {
  description             = "KMS key for Loki logs encryption in ${local.environment}"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = {
    Name        = "loki-encryption-key-${local.environment}"
    Environment = "${local.environment}"
  }
}

resource "aws_kms_alias" "loki" {
  name          = "alias/loki-encryption-key"
  target_key_id = aws_kms_key.loki.key_id
}

# Output de KMS keys
output "secrets_kms_key_arn" {
  description = "ARN of KMS key for secrets encryption"
  value       = aws_kms_key.secrets.arn
}

output "loki_kms_key_arn" {
  description = "ARN of KMS key for Loki logs encryption"
  value       = aws_kms_key.loki.arn
}
EOF
}

inputs = {
  cluster_name = local.cluster_name
  environment  = local.environment
}
