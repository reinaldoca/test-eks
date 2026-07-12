# Production S3 Bucket for Loki Logs
include "root" {
  path = find_in_parent_folders()
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders())}/_envcommon/s3.hcl"
  expose = true
}

# Inputs específicos de producción
inputs = {
  # Habilitar MFA delete en producción (requiere configuración manual de MFA)
  # versioning = {
  #   enabled    = true
  #   mfa_delete = true
  # }
}
