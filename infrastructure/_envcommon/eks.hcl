# EKS Auto Mode Configuration
# Usando recursos nativos de Terraform para EKS Auto Mode

# NO usar módulo - usar recursos nativos para Auto Mode
terraform {
  source = null
}

locals {
  # Cargar variables del entorno
  region_vars = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  environment = local.region_vars.locals.environment
  aws_region  = local.region_vars.locals.aws_region

  # Nombre del cluster
  cluster_name = "fintech-eks-${local.environment}"

  # Versión de Kubernetes
  cluster_version = "1.30"
}

# Dependencias
dependency "vpc" {
  config_path = "../vpc"

  mock_outputs = {
    vpc_id          = "vpc-00000000"
    private_subnets = ["subnet-00000000", "subnet-11111111", "subnet-22222222"]
    public_subnets  = ["subnet-33333333", "subnet-44444444", "subnet-55555555"]
    vpc_cidr_block  = "10.0.0.0/16"
  }
}

# Generar código Terraform nativo para EKS Auto Mode
generate "eks_auto_mode" {
  path      = "eks_auto_mode.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
# EKS Cluster con Auto Mode
resource "aws_eks_cluster" "main" {
  name     = "${local.cluster_name}"
  version  = "${local.cluster_version}"
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_public_access  = true
    endpoint_private_access = true
    public_access_cidrs     = ["0.0.0.0/0"]
  }

  # EKS Auto Mode: Gestión automática de nodos
  compute_config {
    enabled    = true
    node_pools = ["general-purpose", "system"]
  }

  # Storage Class automático (EBS)
  storage_config {
    block_storage {
      enabled = true
    }
  }

  # Kubernetes Network Config
  kubernetes_network_config {
    service_ipv4_cidr = "172.20.0.0/16"
    ip_family         = "ipv4"
  }

  # Encryption config
  encryption_config {
    provider {
      key_arn = aws_kms_key.eks.arn
    }
    resources = ["secrets"]
  }

  # Logging
  enabled_cluster_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]

  # Access config - permitir acceso al creator
  access_config {
    authentication_mode = "API_AND_CONFIG_MAP"
  }

  depends_on = [
    aws_iam_role_policy_attachment.cluster_AmazonEKSClusterPolicy,
    aws_cloudwatch_log_group.cluster
  ]

  tags = {
    Name        = "${local.cluster_name}"
    Environment = "${local.environment}"
    ManagedBy   = "terragrunt"
  }
}

# IAM Role para EKS Cluster
resource "aws_iam_role" "cluster" {
  name = "${local.cluster_name}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Name = "${local.cluster_name}-cluster-role"
  }
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.cluster.name
}

# KMS Key para encryption
resource "aws_kms_key" "eks" {
  description             = "KMS key for EKS secrets encryption in ${local.environment}"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = {
    Name        = "eks-encryption-key-${local.environment}"
    Environment = "${local.environment}"
  }
}

resource "aws_kms_alias" "eks" {
  name          = "alias/eks-${local.environment}"
  target_key_id = aws_kms_key.eks.key_id
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "cluster" {
  name              = "/aws/eks/${local.cluster_name}/cluster"
  retention_in_days = 731

  tags = {
    Name        = "${local.cluster_name}-logs"
    Environment = "${local.environment}"
  }
}

# OIDC Provider para IRSA
data "tls_certificate" "cluster" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "cluster" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.cluster.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer

  tags = {
    Name = "${local.cluster_name}-oidc-provider"
  }
}

# Cluster Security Group Rules
resource "aws_security_group_rule" "cluster_ingress_vpc" {
  description       = "Allow VPC to communicate with cluster API"
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr_block]
  security_group_id = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
}

# Outputs
output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Certificate authority data for the cluster"
  value       = aws_eks_cluster.main.certificate_authority[0].data
}

output "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL for the cluster"
  value       = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC provider"
  value       = aws_iam_openid_connect_provider.cluster.arn
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
}
EOF
}

# Variables para el módulo
generate "variables" {
  path      = "variables.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
variable "subnet_ids" {
  description = "List of subnet IDs for the EKS cluster"
  type        = list(string)
}

variable "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  type        = string
}
EOF
}

inputs = {
  # Estos inputs vienen del child terragrunt.hcl
  subnet_ids     = null
  vpc_cidr_block = null
}
