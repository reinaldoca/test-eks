# EKS Module Common Configuration
# Usando módulo terraform-aws-modules/eks con managed node groups
# NOTA: EKS Auto Mode aún no está soportado establemente en AWS Provider

terraform {
  # Usar última versión estable de la serie 20.x (compatible con provider AWS v5+)
  source = "tfr://registry.terraform.io/terraform-aws-modules/eks/aws?version=20.30.0"
}

# Override provider version solo para EKS (el módulo EKS 20.30.0 requiere AWS provider v5.x)
generate "versions_override" {
  path      = "versions_override.tf"
  if_exists = "overwrite"
  contents  = <<EOF
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.46.0, < 6.0.0"  # Force v5.x for EKS compatibility
    }
  }
}
EOF
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
  }
}

inputs = {
  # Nombre del cluster
  cluster_name    = local.cluster_name
  cluster_version = local.cluster_version

  # VPC y subredes (estas variables vienen de inputs en el child terragrunt.hcl)
  # Los valores se pasarán al módulo Terraform como variables de entrada
  vpc_id     = null  # Se sobreescribirá con inputs
  subnet_ids = null  # Se sobreescribirá con inputs

  # Control plane
  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  # Control plane admin permissions
  enable_cluster_creator_admin_permissions = true

  # Cluster addons (managed by AWS)
  cluster_addons = {
    # VPC CNI para networking
    vpc-cni = {
      most_recent = true
    }

    # CoreDNS
    coredns = {
      most_recent = true
    }

    # kube-proxy
    kube-proxy = {
      most_recent = true
    }

    # EBS CSI Driver para persistent volumes
    aws-ebs-csi-driver = {
      most_recent = true
    }
  }

  # Managed node group simple - 1 pool funcional
  # TEMPORAL: Hasta que EKS Auto Mode esté estable en AWS Provider
  eks_managed_node_groups = {
    default = {
      name            = "default"
      instance_types  = ["t3.medium"]
      capacity_type   = "ON_DEMAND"

      min_size     = 2
      max_size     = 10
      desired_size = 2

      labels = {
        role = "worker"
        env  = local.environment
      }

      tags = {
        Name = "${local.cluster_name}-default-node"
      }
    }
  }

  # IAM roles for service accounts (IRSA)
  enable_irsa = true

  # CloudWatch logging
  cluster_enabled_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]

  # Retention de logs (compliance: 2 años)
  cloudwatch_log_group_retention_in_days = 731

  # Bootstrap addons (required variable en EKS module)
  bootstrap_self_managed_addons = false

  # Tags
  tags = {
    Name        = local.cluster_name
    Environment = local.environment
    ManagedBy   = "terragrunt"
  }
}
