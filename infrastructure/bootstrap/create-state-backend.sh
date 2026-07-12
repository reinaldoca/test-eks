#!/bin/bash
# Script para gestionar el backend de Terraform (S3 + DynamoDB)
# Uso:
#   ./create-state-backend.sh create   - Crear backend
#   ./create-state-backend.sh destroy  - Eliminar backend (¡PELIGRO!)
#   ./create-state-backend.sh status   - Ver estado del backend

set -e

# Variables
PROJECT_NAME="fintech-platform"
AWS_REGION="${AWS_REGION:-us-east-1}"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

BUCKET_NAME="${PROJECT_NAME}-terraform-state-${AWS_ACCOUNT_ID}"
DYNAMODB_TABLE="${PROJECT_NAME}-terraform-locks"

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Función de ayuda
show_help() {
  cat << EOF
${BLUE}Terraform State Backend Manager${NC}

${GREEN}Uso:${NC}
  $0 <comando>

${GREEN}Comandos:${NC}
  create    Crear backend de Terraform (S3 + DynamoDB)
  destroy   Eliminar backend (${RED}¡PELIGRO! Borra todos los estados${NC})
  status    Verificar estado del backend
  help      Mostrar esta ayuda

${GREEN}Variables de entorno:${NC}
  AWS_REGION     Región de AWS (default: us-east-1)
  AWS_PROFILE    Perfil de AWS CLI a usar

${GREEN}Ejemplos:${NC}
  $0 create
  AWS_REGION=us-west-2 $0 create
  $0 status
  $0 destroy

${YELLOW}Nota:${NC} El comando 'destroy' requiere confirmación interactiva.
EOF
}

# Función para crear el backend
create_backend() {
  echo -e "${BLUE}🚀 Creando backend de Terraform State...${NC}"
  echo "   Bucket: ${BUCKET_NAME}"
  echo "   DynamoDB: ${DYNAMODB_TABLE}"
  echo "   Region: ${AWS_REGION}"
  echo ""

  # Crear S3 bucket
  echo -e "${GREEN}📦 Creando S3 bucket...${NC}"
  if [ "${AWS_REGION}" = "us-east-1" ]; then
    # us-east-1 no permite LocationConstraint
    aws s3api create-bucket \
      --bucket "${BUCKET_NAME}" \
      --region "${AWS_REGION}" \
      2>/dev/null || echo -e "  ${YELLOW}⚠️  Bucket ya existe${NC}"
  else
    # Otras regiones requieren LocationConstraint
    aws s3api create-bucket \
      --bucket "${BUCKET_NAME}" \
      --region "${AWS_REGION}" \
      --create-bucket-configuration LocationConstraint="${AWS_REGION}" \
      2>/dev/null || echo -e "  ${YELLOW}⚠️  Bucket ya existe${NC}"
  fi

  # Habilitar versionamiento
  echo -e "${GREEN}🔄 Habilitando versionamiento...${NC}"
  aws s3api put-bucket-versioning \
    --bucket "${BUCKET_NAME}" \
    --versioning-configuration Status=Enabled

  # Habilitar encriptación
  echo -e "${GREEN}🔐 Habilitando encriptación...${NC}"
  aws s3api put-bucket-encryption \
    --bucket "${BUCKET_NAME}" \
    --server-side-encryption-configuration '{
      "Rules": [{
        "ApplyServerSideEncryptionByDefault": {
          "SSEAlgorithm": "AES256"
        },
        "BucketKeyEnabled": true
      }]
    }'

  # Bloquear acceso público
  echo -e "${GREEN}🛡️  Bloqueando acceso público...${NC}"
  aws s3api put-public-access-block \
    --bucket "${BUCKET_NAME}" \
    --public-access-block-configuration \
      "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

  # Habilitar lifecycle policy para versiones antiguas
  echo -e "${GREEN}♻️  Configurando lifecycle policy...${NC}"
  aws s3api put-bucket-lifecycle-configuration \
    --bucket "${BUCKET_NAME}" \
    --lifecycle-configuration '{
      "Rules": [{
        "ID": "DeleteOldVersions",
        "Status": "Enabled",
        "Filter": {},
        "NoncurrentVersionExpiration": {
          "NoncurrentDays": 90
        }
      }]
    }'

  # Crear DynamoDB table para locking
  echo -e "${GREEN}🔒 Creando DynamoDB table para state locking...${NC}"
  aws dynamodb create-table \
    --table-name "${DYNAMODB_TABLE}" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "${AWS_REGION}" \
    --tags "Key=Name,Value=${DYNAMODB_TABLE}" \
          "Key=Project,Value=${PROJECT_NAME}" \
          "Key=ManagedBy,Value=terraform" \
    2>/dev/null || echo -e "  ${YELLOW}⚠️  DynamoDB table ya existe${NC}"

  # Esperar a que la tabla esté activa
  echo -e "${GREEN}⏳ Esperando a que DynamoDB table esté activa...${NC}"
  aws dynamodb wait table-exists \
    --table-name "${DYNAMODB_TABLE}" \
    --region "${AWS_REGION}"

  echo ""
  echo -e "${GREEN}✅ Backend de Terraform creado exitosamente!${NC}"
  echo ""
  echo -e "${BLUE}📋 Información del backend:${NC}"
  echo "   Bucket ARN: arn:aws:s3:::${BUCKET_NAME}"
  echo "   DynamoDB ARN: arn:aws:dynamodb:${AWS_REGION}:${AWS_ACCOUNT_ID}:table/${DYNAMODB_TABLE}"
  echo ""
  echo -e "${GREEN}🚀 Ahora puedes ejecutar:${NC}"
  echo "   cd infrastructure/production"
  echo "   terragrunt run --all init -- -upgrade"
}

# Función para eliminar el backend
destroy_backend() {
  echo -e "${RED}⚠️  ¡PELIGRO! Estás a punto de eliminar el backend de Terraform${NC}"
  echo ""
  echo "Esto eliminará:"
  echo "  - S3 Bucket: ${BUCKET_NAME} (y todos los archivos de estado)"
  echo "  - DynamoDB Table: ${DYNAMODB_TABLE}"
  echo ""
  echo -e "${YELLOW}Esta acción es IRREVERSIBLE y borrará todo el historial de estados.${NC}"
  echo ""

  # Solicitar confirmación
  read -p "¿Estás seguro? Escribe 'yes' para continuar: " confirmation

  if [ "$confirmation" != "yes" ]; then
    echo -e "${GREEN}✅ Operación cancelada. Backend no eliminado.${NC}"
    exit 0
  fi

  # Segunda confirmación
  echo ""
  echo -e "${RED}⚠️  ÚLTIMA ADVERTENCIA${NC}"
  read -p "Escribe el nombre del bucket para confirmar (${BUCKET_NAME}): " bucket_confirmation

  if [ "$bucket_confirmation" != "$BUCKET_NAME" ]; then
    echo -e "${GREEN}✅ Operación cancelada. Backend no eliminado.${NC}"
    exit 0
  fi

  echo ""
  echo -e "${RED}🗑️  Eliminando backend...${NC}"

  # Eliminar todas las versiones de objetos en S3
  echo -e "${YELLOW}📦 Vaciando bucket S3...${NC}"
  aws s3api list-object-versions \
    --bucket "${BUCKET_NAME}" \
    --query 'Versions[].{Key:Key,VersionId:VersionId}' \
    --output json \
    | jq -r '.[] | "--key \"\(.Key)\" --version-id \"\(.VersionId)\""' \
    | xargs -I {} sh -c "aws s3api delete-object --bucket ${BUCKET_NAME} {}" 2>/dev/null || true

  # Eliminar delete markers
  aws s3api list-object-versions \
    --bucket "${BUCKET_NAME}" \
    --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' \
    --output json \
    | jq -r '.[] | "--key \"\(.Key)\" --version-id \"\(.VersionId)\""' \
    | xargs -I {} sh -c "aws s3api delete-object --bucket ${BUCKET_NAME} {}" 2>/dev/null || true

  # Eliminar bucket
  echo -e "${YELLOW}🗑️  Eliminando bucket S3...${NC}"
  aws s3 rb "s3://${BUCKET_NAME}" --force 2>/dev/null || true

  # Eliminar DynamoDB table
  echo -e "${YELLOW}🗑️  Eliminando DynamoDB table...${NC}"
  aws dynamodb delete-table \
    --table-name "${DYNAMODB_TABLE}" \
    --region "${AWS_REGION}" \
    2>/dev/null || true

  echo ""
  echo -e "${GREEN}✅ Backend eliminado exitosamente.${NC}"
}

# Función para verificar estado del backend
check_status() {
  echo -e "${BLUE}🔍 Verificando estado del backend...${NC}"
  echo ""

  # Verificar S3 bucket
  echo -e "${GREEN}📦 S3 Bucket: ${BUCKET_NAME}${NC}"
  if aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
    echo -e "   ${GREEN}✅ Existe${NC}"

    # Obtener número de objetos
    OBJECT_COUNT=$(aws s3 ls "s3://${BUCKET_NAME}" --recursive | wc -l)
    echo "   📊 Archivos de estado: ${OBJECT_COUNT}"

    # Verificar versionamiento
    VERSIONING=$(aws s3api get-bucket-versioning --bucket "${BUCKET_NAME}" --query 'Status' --output text)
    echo "   🔄 Versionamiento: ${VERSIONING}"

    # Verificar encriptación
    ENCRYPTION=$(aws s3api get-bucket-encryption --bucket "${BUCKET_NAME}" --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm' --output text 2>/dev/null || echo "None")
    echo "   🔐 Encriptación: ${ENCRYPTION}"
  else
    echo -e "   ${RED}❌ No existe${NC}"
  fi

  echo ""

  # Verificar DynamoDB table
  echo -e "${GREEN}🔒 DynamoDB Table: ${DYNAMODB_TABLE}${NC}"
  if aws dynamodb describe-table --table-name "${DYNAMODB_TABLE}" --region "${AWS_REGION}" &>/dev/null; then
    echo -e "   ${GREEN}✅ Existe${NC}"

    STATUS=$(aws dynamodb describe-table --table-name "${DYNAMODB_TABLE}" --region "${AWS_REGION}" --query 'Table.TableStatus' --output text)
    echo "   📊 Estado: ${STATUS}"

    ITEM_COUNT=$(aws dynamodb describe-table --table-name "${DYNAMODB_TABLE}" --region "${AWS_REGION}" --query 'Table.ItemCount' --output text)
    echo "   🔒 Locks activos: ${ITEM_COUNT}"
  else
    echo -e "   ${RED}❌ No existe${NC}"
  fi

  echo ""
}

# Main
case "${1:-}" in
  create)
    create_backend
    ;;
  destroy)
    destroy_backend
    ;;
  status)
    check_status
    ;;
  help|--help|-h)
    show_help
    ;;
  *)
    echo -e "${RED}Error: Comando no válido${NC}"
    echo ""
    show_help
    exit 1
    ;;
esac
