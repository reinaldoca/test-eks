# EKS Module Common Configuration
# Módulo reutilizable para EKS Auto Mode en todos los entornos

terraform {
  source = "terraform-aws-modules/eks/aws//."
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

  # Node pools configuration (Karpenter-based)
  node_pools = {
    # Critical workloads (always-on, on-demand)
    critical = {
      instance_types = ["m5.large", "m5.xlarge", "m5a.large"]
      capacity_type  = "ON_DEMAND"
      min_size       = 3   # 1 por AZ
      max_size       = 30
      desired_size   = 3

      taints = [{
        key    = "critical"
        value  = "true"
        effect = "NoSchedule"
      }]

      labels = {
        workload-type = "critical"
        cost-center   = "platform"
      }
    }

    # Standard workloads (on-demand)
    standard = {
      instance_types = ["m5.large", "m5.xlarge", "m6i.large", "m6i.xlarge"]
      capacity_type  = "ON_DEMAND"
      min_size       = 6   # 2 por AZ
      max_size       = 50
      desired_size   = 6

      labels = {
        workload-type = "standard"
      }
    }

    # Batch/Data processing (spot, 40% discount)
    batch = {
      instance_types = ["m5.large", "m5.xlarge", "c5.large", "c5.xlarge"]
      capacity_type  = "SPOT"
      min_size       = 0
      max_size       = 20
      desired_size   = 2

      taints = [{
        key    = "spot"
        value  = "true"
        effect = "NoSchedule"
      }]

      labels = {
        workload-type  = "batch"
        cost-optimized = "true"
      }
    }
  }
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

  # VPC y subredes
  vpc_id     = dependency.vpc.outputs.vpc_id
  subnet_ids = dependency.vpc.outputs.private_subnets

  # Control plane
  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  # Habilitar EKS Auto Mode
  # NOTA: EKS Auto Mode es una feature preview, se habilita via console o CLI
  # Por ahora usamos managed node groups con Karpenter
  enable_cluster_creator_admin_permissions = true

  # Cluster addons (managed by AWS)
  cluster_addons = {
    # VPC CNI para networking
    vpc-cni = {
      most_recent = true
      configuration_values = jsonencode({
        env = {
          # Habilitar prefix delegation para más IPs por nodo
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
        }
      })
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
      service_account_role_arn = "arn:aws:iam::${get_aws_account_id()}:role/${local.cluster_name}-ebs-csi-driver"
    }
  }

  # Managed Node Groups (por cada pool)
  eks_managed_node_groups = local.node_pools

  # IAM roles for service accounts (IRSA)
  enable_irsa = true

  # Cluster security group rules
  cluster_security_group_additional_rules = {
    # Permitir tráfico desde VPC
    ingress_vpc_https = {
      description = "HTTPS from VPC"
      protocol    = "tcp"
      from_port   = 443
      to_port     = 443
      type        = "ingress"
      cidr_blocks = [dependency.vpc.outputs.vpc_cidr_block]
    }
  }

  # Node security group rules
  node_security_group_additional_rules = {
    # Permitir comunicación entre nodos
    ingress_self_all = {
      description = "Node to node all traffic"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }

    # Permitir tráfico desde control plane
    ingress_cluster_all = {
      description                   = "Cluster to node all traffic"
      protocol                      = "-1"
      from_port                     = 0
      to_port                       = 0
      type                          = "ingress"
      source_cluster_security_group = true
    }

    # Egress a internet (via NAT Gateway)
    egress_all = {
      description = "Node all egress"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "egress"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  # Cluster encryption (KMS)
  cluster_encryption_config = {
    resources        = ["secrets"]
    provider_key_arn = "arn:aws:kms:${local.aws_region}:${get_aws_account_id()}:key/alias/eks-${local.environment}"
  }

  # CloudWatch logging
  cluster_enabled_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]

  # Retention de logs (compliance: 2 años)
  cloudwatch_log_group_retention_in_days = 730

  # Tags
  tags = {
    Name        = local.cluster_name
    Environment = local.environment
    ManagedBy   = "terragrunt"
  }
}
