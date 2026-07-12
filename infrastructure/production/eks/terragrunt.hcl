# Production EKS Configuration
include "root" {
  path = find_in_parent_folders()
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders())}/_envcommon/eks.hcl"
  expose = true
  merge_strategy = "deep"
}

# Dependency: VPC debe existir primero
dependency "vpc" {
  config_path = "../vpc"

  # Mock outputs para que terragrunt init funcione sin que VPC exista
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs = {
    vpc_id              = "vpc-mock-12345678"
    private_subnets     = ["subnet-mock-1", "subnet-mock-2", "subnet-mock-3"]
    vpc_cidr_block      = "10.0.0.0/16"
    private_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  }
}

# Inputs específicos de producción
inputs = {
  # VPC outputs desde dependency (se pasan al módulo Terraform como variables)
  vpc_id         = dependency.vpc.outputs.vpc_id
  subnet_ids     = dependency.vpc.outputs.private_subnets
  vpc_cidr_block = dependency.vpc.outputs.vpc_cidr_block

  # Overrides para producción (si son necesarios)
  # Por ejemplo, aumentar min_size de node groups
}
