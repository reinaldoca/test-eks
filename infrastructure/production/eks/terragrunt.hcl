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
}

# Inputs específicos de producción
inputs = {
  # Overrides para producción (si son necesarios)
  # Por ejemplo, aumentar min_size de node groups
}
