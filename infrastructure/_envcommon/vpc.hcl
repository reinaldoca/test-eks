# VPC Module Common Configuration
# Módulo reutilizable para VPC en todos los entornos

terraform {
  source = "terraform-aws-modules/vpc/aws//."
}

locals {
  # Cargar variables del entorno
  region_vars = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  environment = local.region_vars.locals.environment
  aws_region  = local.region_vars.locals.aws_region

  # Nombre del cluster EKS (para tags)
  cluster_name = "fintech-eks-${local.environment}"

  # Availability Zones (3 para HA)
  azs = ["${local.aws_region}a", "${local.aws_region}b", "${local.aws_region}c"]

  # CIDR base
  vpc_cidr = "10.0.0.0/16"

  # Cálculo de subredes
  # Públicas: 10.0.0.0/20, 10.0.16.0/20, 10.0.32.0/20 (4096 IPs cada una)
  public_subnets = [
    cidrsubnet(local.vpc_cidr, 4, 0),  # 10.0.0.0/20
    cidrsubnet(local.vpc_cidr, 4, 1),  # 10.0.16.0/20
    cidrsubnet(local.vpc_cidr, 4, 2),  # 10.0.32.0/20
  ]

  # Privadas: 10.0.64.0/20, 10.0.80.0/20, 10.0.96.0/20
  private_subnets = [
    cidrsubnet(local.vpc_cidr, 4, 4),  # 10.0.64.0/20
    cidrsubnet(local.vpc_cidr, 4, 5),  # 10.0.80.0/20
    cidrsubnet(local.vpc_cidr, 4, 6),  # 10.0.96.0/20
  ]

  # Restringidas (bases de datos): 10.0.128.0/20, 10.0.144.0/20, 10.0.160.0/20
  database_subnets = [
    cidrsubnet(local.vpc_cidr, 4, 8),   # 10.0.128.0/20
    cidrsubnet(local.vpc_cidr, 4, 9),   # 10.0.144.0/20
    cidrsubnet(local.vpc_cidr, 4, 10),  # 10.0.160.0/20
  ]
}

inputs = {
  # Nombre de la VPC
  name = "fintech-vpc-${local.environment}"

  # CIDR
  cidr = local.vpc_cidr

  # Availability Zones
  azs = local.azs

  # Subredes
  public_subnets   = local.public_subnets
  private_subnets  = local.private_subnets
  database_subnets = local.database_subnets

  # HA: 3 NAT Gateways (uno por AZ)
  # Costo extra pero crítico para SLA 99.99%
  enable_nat_gateway   = true
  single_nat_gateway   = false  # 3 NAT Gateways para HA
  one_nat_gateway_per_az = true

  # Internet Gateway
  enable_dns_hostnames = true
  enable_dns_support   = true

  # VPC Flow Logs para auditoría y troubleshooting
  enable_flow_log                      = true
  create_flow_log_cloudwatch_iam_role  = true
  create_flow_log_cloudwatch_log_group = true
  flow_log_retention_in_days           = 7  # 7 días para reducir costos

  # Tags para integración con EKS
  # kubernetes.io/cluster/<cluster-name> = shared/owned
  public_subnet_tags = {
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    Tier                                        = "public"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    Tier                                        = "private"
    # Karpenter subnet discovery
    "karpenter.sh/discovery" = local.cluster_name
  }

  database_subnet_tags = {
    Tier = "database"
  }

  # Tags adicionales para la VPC
  tags = {
    Name        = "fintech-vpc-${local.environment}"
    Environment = local.environment
  }

  # VPC Endpoints para reducir costos de NAT Gateway
  # y mejorar seguridad (tráfico no sale a internet)
  enable_s3_endpoint       = true
  enable_dynamodb_endpoint = true

  # Crear subnet groups para RDS (futuro)
  create_database_subnet_group           = true
  create_database_subnet_route_table     = true
  create_database_internet_gateway_route = false

  # Segregación de tráfico
  create_database_nat_gateway_route = false
}

# Dependencias: ninguna (VPC es el primer recurso)
dependencies {
  paths = []
}
