# Production ECR Repositories Configuration

include "root" {
  path = find_in_parent_folders()
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders())}/_envcommon/ecr.hcl"
  expose = true
}

# Dependencies: ninguna (ECR es independiente)
# Nota: Los repos ECR deben existir antes de que GitHub Actions intente push

# Inputs específicos de producción
inputs = {
  # Agregar servicios adicionales si es necesario
  # additional_services = ["service-c", "service-d"]

  # Image tag immutability en producción
  # image_tag_mutability = "IMMUTABLE"
}
