#!/bin/bash
# Script mejorado para gestionar infraestructura en Dev Environment
# Ejecutar desde: infrastructure/dev/
# Uso: ./deploy-dev.sh [comando] [opciones]
#
# Comandos:
#   init      Inicializar Terragrunt y limpiar cache
#   plan      Ejecutar plan sin aplicar cambios
#   apply     Aplicar cambios (ejecuta plan automáticamente)
#   destroy   Destruir toda la infraestructura
#   validate  Validar configuración sin ejecutar plan
#   output    Mostrar outputs de la infraestructura
#   unlock    Liberar state locks de DynamoDB (si el workflow se cancela)
#   all       Ejecutar init + validate + plan + apply (interactivo)
#
# Opciones:
#   --auto-approve    Aplicar sin confirmación (solo para apply/destroy)
#   --target=MODULE   Ejecutar solo en un módulo específico (vpc, eks, s3-loki, ecr, iam-roles)
#   --no-cache-clean  No limpiar cache de Terragrunt
#
# Ejemplos:
#   ./deploy-dev.sh init
#   ./deploy-dev.sh plan
#   ./deploy-dev.sh apply --auto-approve
#   ./deploy-dev.sh destroy --target=eks
#   ./deploy-dev.sh all

set -e
set -o pipefail

# Colores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Variables por defecto
COMMAND=""
AUTO_APPROVE=false
TARGET_MODULE=""
CLEAN_CACHE=true

# Funciones de ayuda
print_usage() {
  echo ""
  echo "Uso: $0 [comando] [opciones]"
  echo ""
  echo "Comandos:"
  echo "  init      Inicializar Terragrunt y limpiar cache"
  echo "  plan      Ejecutar plan sin aplicar cambios"
  echo "  apply     Aplicar cambios (ejecuta plan automáticamente)"
  echo "  destroy   Destruir toda la infraestructura"
  echo "  validate  Validar configuración sin ejecutar plan"
  echo "  output    Mostrar outputs de la infraestructura"
  echo "  unlock    Liberar state locks de DynamoDB (si el workflow se cancela)"
  echo "  all       Ejecutar init + validate + plan + apply (interactivo)"
  echo ""
  echo "Opciones:"
  echo "  --auto-approve    Aplicar sin confirmación (solo para apply/destroy)"
  echo "  --target=MODULE   Ejecutar solo en un módulo específico (vpc, eks, s3-loki, ecr, iam-roles)"
  echo "  --no-cache-clean  No limpiar cache de Terragrunt"
  echo ""
  echo "Ejemplos:"
  echo "  $0 init"
  echo "  $0 plan"
  echo "  $0 apply --auto-approve"
  echo "  $0 destroy --target=eks"
  echo "  $0 all"
  echo ""
}

log_info() {
  echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
  echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
  echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
  echo -e "${RED}❌ $1${NC}"
}

log_step() {
  echo ""
  echo -e "${GREEN}$1${NC}"
}

# Verificaciones iniciales
check_prerequisites() {
  log_step "🔍 Verificando pre-requisitos..."

  # Verificar directorio correcto
  if [ ! -f "region.hcl" ]; then
    log_error "Debes ejecutar este script desde infrastructure/dev/"
    exit 1
  fi

  # Verificar AWS credentials
  if ! aws sts get-caller-identity > /dev/null 2>&1; then
    log_error "No hay credenciales de AWS configuradas"
    echo "Ejecuta: aws configure"
    exit 1
  fi

  ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
  AWS_REGION=$(aws configure get region || echo "us-east-1")

  log_success "AWS Account: ${ACCOUNT_ID}"
  log_success "AWS Region: ${AWS_REGION}"

  # Verificar herramientas
  command -v terragrunt >/dev/null 2>&1 || { log_error "terragrunt no está instalado"; exit 1; }
  command -v terraform >/dev/null 2>&1 || { log_error "terraform no está instalado"; exit 1; }

  TERRAGRUNT_VERSION=$(terragrunt --version | head -n1)
  TERRAFORM_VERSION=$(terraform --version | head -n1)

  log_success "Terragrunt: ${TERRAGRUNT_VERSION}"
  log_success "Terraform: ${TERRAFORM_VERSION}"
}

# Limpiar cache
clean_cache() {
  if [ "$CLEAN_CACHE" = true ]; then
    log_step "🧹 Limpiando cache de Terragrunt..."
    find . -type d -name ".terragrunt-cache" -exec rm -rf {} + 2>/dev/null || true
    log_success "Cache limpiado"
  fi
}

# Construir comando de Terragrunt
build_terragrunt_command() {
  local action=$1
  local cmd=""

  if [ -n "$TARGET_MODULE" ]; then
    # Ejecutar solo en módulo específico
    if [ ! -d "$TARGET_MODULE" ]; then
      log_error "Módulo no encontrado: ${TARGET_MODULE}"
      exit 1
    fi
    cmd="cd ${TARGET_MODULE} && terragrunt ${action}"
  else
    # Ejecutar en todos los módulos
    cmd="terragrunt run --all ${action}"
  fi

  echo "$cmd"
}

# Comando: init
cmd_init() {
  log_step "🔧 Inicializando Terragrunt..."
  clean_cache

  local cmd=$(build_terragrunt_command "init -- -upgrade")

  eval $cmd

  if [ $? -eq 0 ]; then
    log_success "Init completado exitosamente"
  else
    log_error "Error en terragrunt init"
    exit 1
  fi
}

# Comando: validate
cmd_validate() {
  log_step "✅ Validando configuración..."

  local cmd=$(build_terragrunt_command "validate")

  eval $cmd

  if [ $? -eq 0 ]; then
    log_success "Validación exitosa"
  else
    log_error "Error en terragrunt validate"
    exit 1
  fi
}

# Comando: plan
cmd_plan() {
  log_step "📋 Ejecutando plan..."

  local cmd=$(build_terragrunt_command "plan -- -no-color")

  eval $cmd | tee plan-output.txt

  if [ ${PIPESTATUS[0]} -eq 0 ]; then
    log_success "Plan generado exitosamente"
    echo ""
    log_info "Plan guardado en: plan-output.txt"
  else
    log_error "Error en terragrunt plan"
    exit 1
  fi
}

# Comando: apply
cmd_apply() {
  log_step "🚀 Aplicando cambios..."

  # Ejecutar plan primero (si no es auto-approve)
  if [ "$AUTO_APPROVE" = false ]; then
    cmd_plan
    echo ""
    log_warning "¿Deseas aplicar estos cambios? (yes/no)"
    read -p "Respuesta: " APPLY_CONFIRM

    if [ "$APPLY_CONFIRM" != "yes" ]; then
      log_info "Operación cancelada por el usuario"
      exit 0
    fi
  fi

  echo ""
  local apply_flags=""
  if [ "$AUTO_APPROVE" = true ]; then
    apply_flags="-- -auto-approve -no-color"
  else
    apply_flags="-- -no-color"
  fi

  local cmd=$(build_terragrunt_command "apply ${apply_flags}")

  eval $cmd | tee apply-output.txt

  if [ ${PIPESTATUS[0]} -eq 0 ]; then
    log_success "Infraestructura aplicada exitosamente"
    echo ""
    log_info "Logs guardados en: apply-output.txt"
  else
    log_error "Error en terragrunt apply"
    exit 1
  fi
}

# Comando: destroy
cmd_destroy() {
  log_step "💥 Destruyendo infraestructura..."

  if [ "$AUTO_APPROVE" = false ]; then
    echo ""
    log_warning "⚠️  ATENCIÓN: Esto destruirá TODA la infraestructura en Dev ⚠️"
    echo ""
    if [ -n "$TARGET_MODULE" ]; then
      log_warning "Módulo objetivo: ${TARGET_MODULE}"
    else
      log_warning "Módulos afectados: TODOS (vpc, eks, s3-loki, ecr, iam-roles)"
    fi
    echo ""
    log_warning "Esta acción es IRREVERSIBLE"
    echo ""
    log_warning "Escribe 'destroy-all' para confirmar:"
    read -p "Confirmación: " DESTROY_CONFIRM

    if [ "$DESTROY_CONFIRM" != "destroy-all" ]; then
      log_info "Operación cancelada por el usuario"
      exit 0
    fi
  fi

  echo ""
  local tf_flags=""
  if [ "$AUTO_APPROVE" = true ]; then
    tf_flags="-auto-approve -no-color"
  else
    tf_flags="-no-color"
  fi

  # Para destroy con auto-approve, necesitamos el flag --non-interactive ANTES de run
  local cmd=""
  if [ -n "$TARGET_MODULE" ]; then
    cmd="cd ${TARGET_MODULE} && terragrunt destroy -- ${tf_flags}"
  else
    if [ "$AUTO_APPROVE" = true ]; then
      cmd="terragrunt --non-interactive run --all destroy -- ${tf_flags}"
    else
      cmd="terragrunt run --all destroy -- ${tf_flags}"
    fi
  fi

  eval $cmd | tee destroy-output.txt

  if [ ${PIPESTATUS[0]} -eq 0 ]; then
    log_success "Infraestructura destruida exitosamente"
    echo ""
    log_info "Logs guardados en: destroy-output.txt"
  else
    log_error "Error en terragrunt destroy"
    exit 1
  fi
}

# Comando: output
cmd_output() {
  log_step "📊 Outputs de la infraestructura:"
  echo ""

  local modules=("vpc" "eks" "s3-loki" "ecr" "iam-roles")

  for module in "${modules[@]}"; do
    if [ -d "$module" ]; then
      echo -e "${YELLOW}${module}:${NC}"
      cd "$module"
      terragrunt output 2>/dev/null || echo "  No outputs disponibles aún"
      cd ..
      echo ""
    fi
  done
}

# Comando: unlock (liberar state locks)
cmd_unlock() {
  log_step "🔓 Liberando state locks de DynamoDB..."
  echo ""

  DYNAMODB_TABLE="fintech-platform-terraform-locks"

  log_info "DynamoDB Table: ${DYNAMODB_TABLE}"
  echo ""

  # Listar locks actuales
  log_info "Listando locks actuales..."
  LOCKS=$(aws dynamodb scan \
    --table-name "${DYNAMODB_TABLE}" \
    --region us-east-1 \
    --output json 2>/dev/null || echo '{"Items":[]}')

  LOCK_COUNT=$(echo "$LOCKS" | jq '.Items | length')

  if [ "$LOCK_COUNT" -eq 0 ]; then
    log_success "No hay locks activos"
    return 0
  fi

  log_warning "Se encontraron ${LOCK_COUNT} locks:"
  echo ""
  echo "$LOCKS" | jq -r '.Items[] | "  - " + .LockID.S'

  echo ""
  log_warning "⚠️  ATENCIÓN: Liberar locks puede causar inconsistencias si hay otro apply corriendo"
  echo ""
  log_warning "¿Deseas liberar TODOS los locks? (yes/no)"
  read -p "Respuesta: " CONFIRM

  if [ "$CONFIRM" != "yes" ]; then
    log_info "Operación cancelada"
    return 0
  fi

  # Liberar locks
  echo ""
  log_info "Liberando locks..."

  echo "$LOCKS" | jq -r '.Items[].LockID.S' | while read -r lock_id; do
    echo "  Liberando: ${lock_id}"

    aws dynamodb delete-item \
      --table-name "${DYNAMODB_TABLE}" \
      --key "{\"LockID\": {\"S\": \"${lock_id}\"}}" \
      --region us-east-1 2>/dev/null && echo "    ✓ Liberado" || echo "    ✗ Error"
  done

  echo ""
  log_success "Locks liberados exitosamente"
  echo ""
  log_info "Ahora puedes ejecutar: ./deploy-dev.sh apply"
}

# Comando: all (pipeline completo)
cmd_all() {
  log_step "🚀 Ejecutando pipeline completo: init → validate → plan → apply"
  echo ""

  cmd_init
  cmd_validate
  cmd_plan

  echo ""
  log_warning "Pipeline completado hasta plan. ¿Deseas aplicar los cambios? (yes/no)"
  read -p "Respuesta: " APPLY_CONFIRM

  if [ "$APPLY_CONFIRM" == "yes" ]; then
    AUTO_APPROVE=true  # Ya confirmamos, no preguntar de nuevo
    cmd_apply
    cmd_output

    echo ""
    log_success "🎉 Deployment completo!"
    echo ""
    echo "Próximos pasos:"
    echo "  1. Conectar a EKS: aws eks update-kubeconfig --name fintech-eks-dev --region us-east-1"
    echo "  2. Verificar nodos: kubectl get nodes"
    echo "  3. Verificar recursos: kubectl get all --all-namespaces"
  else
    log_info "Apply cancelado. Pipeline completado hasta plan."
  fi
}

# Parsear argumentos
if [ $# -eq 0 ]; then
  log_error "No se especificó ningún comando"
  print_usage
  exit 1
fi

COMMAND=$1
shift

while [ $# -gt 0 ]; do
  case $1 in
    --auto-approve)
      AUTO_APPROVE=true
      shift
      ;;
    --target=*)
      TARGET_MODULE="${1#*=}"
      shift
      ;;
    --no-cache-clean)
      CLEAN_CACHE=false
      shift
      ;;
    --help|-h)
      print_usage
      exit 0
      ;;
    *)
      log_error "Opción desconocida: $1"
      print_usage
      exit 1
      ;;
  esac
done

# Ejecutar comando
echo ""
echo -e "${BLUE}╔═══════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Terragrunt Dev Environment Manager     ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════╝${NC}"

check_prerequisites

case $COMMAND in
  init)
    cmd_init
    ;;
  validate)
    cmd_validate
    ;;
  plan)
    cmd_plan
    ;;
  apply)
    cmd_apply
    cmd_output
    ;;
  destroy)
    cmd_destroy
    ;;
  output)
    cmd_output
    ;;
  unlock)
    cmd_unlock
    ;;
  all)
    cmd_all
    ;;
  *)
    log_error "Comando desconocido: $COMMAND"
    print_usage
    exit 1
    ;;
esac

echo ""
log_success "Operación completada exitosamente"
