#!/bin/bash
# Script para limpiar el Terraform state después de destrucción manual
# Uso: ./clean-state.sh

set -e

export AWS_PROFILE=santi

echo "╔═══════════════════════════════════════════╗"
echo "║   Terraform State Cleanup Script         ║"
echo "╚═══════════════════════════════════════════╝"
echo ""

echo "⚠️  Este script limpia el Terraform state DESPUÉS de haber"
echo "   destruido los recursos manualmente desde AWS."
echo ""
echo "📋 Módulos a limpiar:"
echo "   - vpc"
echo "   - eks"
echo "   - s3-loki"
echo "   - ecr"
echo "   - iam-roles"
echo ""

read -p "¿Continuar con la limpieza del state? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
  echo "Operación cancelada"
  exit 0
fi

echo ""
echo "🧹 Limpiando states..."

# Function to remove all resources from a module's state
clean_module_state() {
  local module=$1
  echo ""
  echo "Limpiando: $module"

  cd $module

  # Listar recursos en state
  RESOURCES=$(terragrunt state list 2>/dev/null || echo "")

  if [ -z "$RESOURCES" ]; then
    echo "  ✓ State vacío o no inicializado"
    cd ..
    return
  fi

  # Contar recursos
  COUNT=$(echo "$RESOURCES" | wc -l)
  echo "  Encontrados $COUNT recursos en state"

  # Remover cada recurso
  while IFS= read -r resource; do
    if [ ! -z "$resource" ]; then
      echo "    Removiendo: $resource"
      terragrunt state rm "$resource" 2>&1 | grep -v "Successfully removed" || true
    fi
  done <<< "$RESOURCES"

  echo "  ✓ State limpiado"
  cd ..
}

# Limpiar cada módulo
clean_module_state "iam-roles"
clean_module_state "eks"
clean_module_state "s3-loki"
clean_module_state "ecr"
clean_module_state "vpc"

echo ""
echo "✅ Limpieza de states completa"
echo ""
echo "📊 Verificación final:"
echo ""

# Verificar que no queden recursos
for module in vpc eks s3-loki ecr iam-roles; do
  cd $module
  COUNT=$(terragrunt state list 2>/dev/null | wc -l || echo "0")
  echo "  $module: $COUNT recursos"
  cd ..
done

echo ""
echo "💡 Próximos pasos:"
echo "   1. Verificar en AWS Console que todos los recursos fueron eliminados"
echo "   2. Si quedaron recursos, eliminarlos manualmente"
echo "   3. Ejecutar: terragrunt run --all init --reconfigure"
echo ""
