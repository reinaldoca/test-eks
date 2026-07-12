# Production IAM Roles (IRSA)
include "root" {
  path = find_in_parent_folders()
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders())}/_envcommon/iam.hcl"
  expose = true
}

# Dependency: EKS debe existir primero (para OIDC provider)
dependency "eks" {
  config_path = "../eks"
}

# Inputs específicos de producción
inputs = {
  # Todos los inputs vienen de _envcommon/iam.hcl
}
