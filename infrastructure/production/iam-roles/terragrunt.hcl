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

  # Mock outputs para que terragrunt funcione incluso si EKS no está completo
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "apply"]
  mock_outputs_merge_strategy_with_state = "shallow"

  mock_outputs = {
    cluster_name                      = "fintech-eks-production-mock"
    cluster_oidc_issuer_url           = "https://oidc.eks.us-east-1.amazonaws.com/id/MOCK123456"
    oidc_provider_arn                 = "arn:aws:iam::475274912371:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/MOCK123456"
    cluster_endpoint                  = "https://MOCK123.eks.us-east-1.amazonaws.com"
    cluster_certificate_authority_data = "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JPEG="
  }
}

# Inputs específicos de producción
inputs = {
  # Todos los inputs vienen de _envcommon/iam.hcl
}
