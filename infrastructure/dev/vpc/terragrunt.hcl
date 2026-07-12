# Production VPC Configuration
include "root" {
  path = find_in_parent_folders()
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders())}/_envcommon/vpc.hcl"
  expose = true
}

# Inputs específicos de producción (si se necesitan overrides)
inputs = {
  # Todos los inputs vienen de _envcommon/vpc.hcl
  # Aquí solo se agregan overrides si son necesarios
}
