#!/bin/bash
# Script para verificar el estado de la destrucción de recursos
# Uso: ./check-destroy-status.sh

export AWS_PROFILE=santi

echo "╔═══════════════════════════════════════════╗"
echo "║   AWS Resources Destruction Status       ║"
echo "╚═══════════════════════════════════════════╝"
echo ""

check_eks() {
  echo "🔍 Checking EKS Cluster..."
  STATUS=$(aws eks describe-cluster --name fintech-eks-dev --query 'cluster.status' --output text 2>&1 || echo "NOT_FOUND")

  if [ "$STATUS" = "NOT_FOUND" ]; then
    echo "   ✅ EKS Cluster: DELETED"
    return 0
  elif [ "$STATUS" = "DELETING" ]; then
    echo "   ⏳ EKS Cluster: DELETING (this takes 10-15 minutes)"
    return 1
  else
    echo "   ❌ EKS Cluster: $STATUS"
    return 1
  fi
}

check_vpc() {
  echo ""
  echo "🔍 Checking VPC..."
  VPC=$(aws ec2 describe-vpcs --vpc-ids vpc-0bb2a1f695ae86a9e --query 'Vpcs[0].VpcId' --output text 2>&1 || echo "NOT_FOUND")

  if [ "$VPC" = "NOT_FOUND" ] || [ -z "$VPC" ]; then
    echo "   ✅ VPC: DELETED"
    return 0
  else
    echo "   ⏳ VPC: Still exists (vpc-0bb2a1f695ae86a9e)"

    # Check dependencies
    echo "   📋 VPC Dependencies:"

    # ENIs
    ENI_COUNT=$(aws ec2 describe-network-interfaces --filters "Name=vpc-id,Values=$VPC" --query 'NetworkInterfaces | length(@)' --output text 2>&1 || echo "0")
    echo "      - Network Interfaces (ENIs): $ENI_COUNT"

    # Subnets
    SUBNET_COUNT=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC" --query 'Subnets | length(@)' --output text 2>&1 || echo "0")
    echo "      - Subnets: $SUBNET_COUNT"

    # Security Groups
    SG_COUNT=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC" --query 'SecurityGroups | length(@)' --output text 2>&1 || echo "0")
    echo "      - Security Groups: $SG_COUNT"

    # Route Tables
    RT_COUNT=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC" --query 'RouteTables | length(@)' --output text 2>&1 || echo "0")
    echo "      - Route Tables: $RT_COUNT"

    # NAT Gateways
    NAT_COUNT=$(aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$VPC" --query 'NatGateways[?State!=`deleted`] | length(@)' --output text 2>&1 || echo "0")
    echo "      - NAT Gateways: $NAT_COUNT"

    return 1
  fi
}

check_other_resources() {
  echo ""
  echo "🔍 Checking Other Resources..."

  # S3
  S3=$(aws s3 ls | grep "loki-logs-dev" || echo "")
  if [ -z "$S3" ]; then
    echo "   ✅ S3 Bucket: DELETED"
  else
    echo "   ❌ S3 Bucket: Still exists"
  fi

  # ECR
  ECR=$(aws ecr describe-repositories --repository-names service-a service-b 2>&1 | grep "repositoryName" || echo "")
  if [ -z "$ECR" ]; then
    echo "   ✅ ECR Repositories: DELETED"
  else
    echo "   ❌ ECR Repositories: Still exist"
  fi

  # IAM Roles
  IAM_COUNT=$(aws iam list-roles --query 'Roles[?contains(RoleName, `fintech-eks-dev`)] | length(@)' --output text 2>&1 || echo "0")
  if [ "$IAM_COUNT" = "0" ] || [ "$IAM_COUNT" = "1" ]; then
    echo "   ✅ IAM Roles: DELETED (or only cluster role left)"
  else
    echo "   ⏳ IAM Roles: $IAM_COUNT roles still exist"
  fi
}

# Run checks
check_eks
EKS_STATUS=$?

check_vpc
VPC_STATUS=$?

check_other_resources

echo ""
echo "═══════════════════════════════════════════"
echo ""

if [ $EKS_STATUS -eq 0 ] && [ $VPC_STATUS -eq 0 ]; then
  echo "✅ ALL RESOURCES DELETED"
  echo ""
  echo "Next steps:"
  echo "  1. cd infrastructure/dev"
  echo "  2. ./clean-state.sh"
  echo "  3. terragrunt run --all init --reconfigure (if redeploying)"
  exit 0
else
  echo "⏳ RESOURCES STILL DELETING"
  echo ""
  echo "Wait 2-3 minutes and run this script again:"
  echo "  ./check-destroy-status.sh"
  echo ""
  echo "Or monitor in AWS Console:"
  echo "  - EKS: https://console.aws.amazon.com/eks/home?region=us-east-1#/clusters"
  echo "  - VPC: https://console.aws.amazon.com/vpc/home?region=us-east-1#vpcs:"
  exit 1
fi
