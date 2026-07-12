# Production EKS Configuration
include "root" {
  path = find_in_parent_folders()
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders())}/_envcommon/eks.hcl"
  expose = true
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
  # Overrides para producción (si son necesarios)
  # Por ejemplo, aumentar min_size de node groups
}
