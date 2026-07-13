# Production IAM Roles (IRSA)
include "root" {
  path = find_in_parent_folders()
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders())}/_envcommon/iam.hcl"
  expose = true
}

# NOTA: Ya no necesitamos dependency de EKS porque usamos data sources
# en _envcommon/iam.hcl para obtener el OIDC provider directamente desde AWS

# Inputs específicos de producción
inputs = {
  # Todos los inputs vienen de _envcommon/iam.hcl
}
