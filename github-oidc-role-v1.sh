#!/bin/bash

# Configuración (Modifica estos valores según tu repositorio)
ROLE_NAME="GitHubActionsWorkflowRole"
GITHUB_ORG="reinaldoca"
GITHUB_REPO="*"
GITHUB_BRANCH="main"

# Obtener AWS Account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)

# 1. Crear OIDC Provider con thumbprint oficial
aws iam create-open-id-connect-provider \
    --url "https://token.actions.githubusercontent.com" \
    --client-id-list "sts.amazonaws.com" \
    --thumbprint-list "6938fd4d98bab03faadb97b34396831e3780aea1"

# 2. Generar trust policy para el repositorio y rama
cat <<EOF > trust-policy.json
{
    "Version": "2012-10-17",
    "Statement": [{
        "Effect": "Allow",
        "Principal": {"Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"},
        "Action": "sts:AssumeRoleWithWebIdentity",
        "Condition": {"StringEquals": {
            "token.actions.githubusercontent.com:sub": "repo:${GITHUB_ORG}/*",
            "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        }}
    }]
}
EOF

# 3. Crear rol y asignar política
aws iam create-role --role-name "$ROLE_NAME" --assume-role-policy-document file://trust-policy.json
aws iam attach-role-policy --role-name "$ROLE_NAME" --policy-arn "arn:aws:iam::aws:policy/AdministratorAccess"

rm trust-policy.json
echo "ARN: arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME}"
