#!/bin/bash
# Script para liberar state locks de Terragrunt/Terraform
# Ejecutar cuando un workflow se cancela y deja locks huérfanos

set -e

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}🔓 Script para liberar state locks${NC}"
echo ""

# Verificar directorio correcto
if [ ! -f "region.hcl" ]; then
  echo -e "${RED}❌ Error: Debes ejecutar este script desde infrastructure/dev/${NC}"
  exit 1
fi

# Verificar AWS credentials
if ! aws sts get-caller-identity > /dev/null 2>&1; then
  echo -e "${RED}❌ Error: No hay credenciales de AWS configuradas${NC}"
  exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
DYNAMODB_TABLE="fintech-platform-terraform-locks"

echo -e "${GREEN}AWS Account: ${ACCOUNT_ID}${NC}"
echo -e "${GREEN}DynamoDB Table: ${DYNAMODB_TABLE}${NC}"
echo ""

# Listar locks actuales
echo -e "${YELLOW}📋 Listando locks actuales en DynamoDB...${NC}"
echo ""

LOCKS=$(aws dynamodb scan \
  --table-name "${DYNAMODB_TABLE}" \
  --region us-east-1 \
  --output json 2>/dev/null || echo '{"Items":[]}')

LOCK_COUNT=$(echo "$LOCKS" | jq '.Items | length')

if [ "$LOCK_COUNT" -eq 0 ]; then
  echo -e "${GREEN}✅ No hay locks activos${NC}"
  exit 0
fi

echo -e "${YELLOW}⚠️  Se encontraron ${LOCK_COUNT} locks:${NC}"
echo ""

# Mostrar locks
echo "$LOCKS" | jq -r '.Items[] | "  - " + .LockID.S + " (Info: " + (.Info.S // "N/A") + ")"'

echo ""
echo -e "${RED}⚠️  ATENCIÓN: Liberar locks puede causar inconsistencias si hay otro apply corriendo${NC}"
echo ""
echo -e "${YELLOW}¿Deseas liberar TODOS los locks? (yes/no)${NC}"
read -p "Respuesta: " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
  echo -e "${GREEN}Operación cancelada${NC}"
  exit 0
fi

# Liberar locks
echo ""
echo -e "${YELLOW}🔓 Liberando locks...${NC}"

echo "$LOCKS" | jq -r '.Items[].LockID.S' | while read -r lock_id; do
  echo "  Liberando: ${lock_id}"

  aws dynamodb delete-item \
    --table-name "${DYNAMODB_TABLE}" \
    --key "{\"LockID\": {\"S\": \"${lock_id}\"}}" \
    --region us-east-1 2>/dev/null || echo "    ⚠️  Error al liberar lock"
done

echo ""
echo -e "${GREEN}✅ Locks liberados exitosamente${NC}"
echo ""
echo "Verifica que no haya locks restantes:"
echo "  ./unlock-state.sh"
echo ""
echo "Ahora puedes ejecutar:"
echo "  ./deploy-dev.sh apply"
