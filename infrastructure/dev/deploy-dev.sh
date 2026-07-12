#!/bin/bash
# Script para desplegar infraestructura en Dev Environment
# Ejecutar desde: infrastructure/dev/

set -e

echo "🚀 Desplegando Infraestructura en Dev Environment..."
echo ""

# Colores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Verificar que estamos en el directorio correcto
if [ ! -f "region.hcl" ]; then
  echo -e "${RED}❌ Error: Debes ejecutar este script desde infrastructure/dev/${NC}"
  exit 1
fi

# Verificar AWS credentials
echo -e "${GREEN}🔐 Verificando credenciales de AWS...${NC}"
aws sts get-caller-identity > /dev/null 2>&1 || {
  echo -e "${RED}❌ Error: No hay credenciales de AWS configuradas${NC}"
  echo "Ejecuta: aws configure"
  exit 1
}

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "   ✅ AWS Account: ${ACCOUNT_ID}"
echo ""

# Step 1: Limpiar cache
echo -e "${GREEN}🧹 Limpiando cache de Terragrunt...${NC}"
rm -rf */.terragrunt-cache
echo "   ✅ Cache limpiado"
echo ""

# Step 2: Init
echo -e "${GREEN}🔧 Inicializando Terragrunt...${NC}"
terragrunt run --all init -- -upgrade

if [ $? -ne 0 ]; then
  echo -e "${RED}❌ Error en terragrunt init${NC}"
  exit 1
fi
echo "   ✅ Init completado"
echo ""

# Step 3: Validate
echo -e "${GREEN}✅ Validando configuración...${NC}"
terragrunt run --all validate

if [ $? -ne 0 ]; then
  echo -e "${RED}❌ Error en terragrunt validate${NC}"
  exit 1
fi
echo "   ✅ Validación exitosa"
echo ""

# Step 4: Plan
echo -e "${GREEN}📋 Ejecutando plan...${NC}"
terragrunt run --all plan -- -out=plan.tfplan

if [ $? -ne 0 ]; then
  echo -e "${RED}❌ Error en terragrunt plan${NC}"
  exit 1
fi
echo "   ✅ Plan generado"
echo ""

# Preguntar si aplicar
echo -e "${YELLOW}⚠️  ¿Deseas aplicar los cambios? (yes/no)${NC}"
read -p "Respuesta: " APPLY_CONFIRM

if [ "$APPLY_CONFIRM" != "yes" ]; then
  echo -e "${GREEN}✅ Plan generado exitosamente. No se aplicaron cambios.${NC}"
  echo ""
  echo "Para aplicar manualmente:"
  echo "  terragrunt run --all apply"
  exit 0
fi

# Step 5: Apply
echo ""
echo -e "${GREEN}🚀 Aplicando cambios...${NC}"
terragrunt run --all apply

if [ $? -ne 0 ]; then
  echo -e "${RED}❌ Error en terragrunt apply${NC}"
  exit 1
fi

echo ""
echo -e "${GREEN}✅ Infraestructura desplegada exitosamente en Dev!${NC}"
echo ""

# Step 6: Mostrar outputs
echo -e "${GREEN}📊 Outputs de la infraestructura:${NC}"
echo ""

cd vpc
echo -e "${YELLOW}VPC:${NC}"
terragrunt output 2>/dev/null || echo "  No outputs disponibles aún"
cd ..

cd eks
echo -e "${YELLOW}EKS:${NC}"
terragrunt output 2>/dev/null || echo "  No outputs disponibles aún"
cd ..

cd s3-loki
echo -e "${YELLOW}S3 Loki:${NC}"
terragrunt output 2>/dev/null || echo "  No outputs disponibles aún"
cd ..

cd ecr
echo -e "${YELLOW}ECR:${NC}"
terragrunt output 2>/dev/null || echo "  No outputs disponibles aún"
cd ..

echo ""
echo -e "${GREEN}🎉 Deployment completo!${NC}"
echo ""
echo "Próximos pasos:"
echo "  1. Conectar a EKS: aws eks update-kubeconfig --name fintech-eks-dev --region us-east-1"
echo "  2. Verificar nodos: kubectl get nodes"
echo "  3. Verificar recursos: kubectl get all --all-namespaces"
