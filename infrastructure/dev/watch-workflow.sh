#!/bin/bash
# Script para monitorear el progreso del workflow en tiempo real
# Uso: ./watch-workflow.sh [workflow_run_id]

set -e

# Colores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Obtener ID del último workflow si no se proporciona
WORKFLOW_ID=${1:-$(gh run list --workflow="Infrastructure Apply" --limit 1 --json databaseId --jq '.[0].databaseId')}

if [ -z "$WORKFLOW_ID" ]; then
  echo -e "${RED}❌ No se encontró workflow en ejecución${NC}"
  exit 1
fi

echo -e "${BLUE}╔═══════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Workflow Monitor - Real Time           ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}Workflow ID: ${WORKFLOW_ID}${NC}"
echo ""

# Función para obtener status
get_status() {
  gh run view $WORKFLOW_ID --json status,conclusion,createdAt,updatedAt 2>/dev/null
}

# Función para parsear duración
get_duration() {
  local created=$1
  local now=$(date -u +%s)
  local created_ts=$(date -d "$created" +%s 2>/dev/null || echo $now)
  local diff=$((now - created_ts))
  echo "${diff}s"
}

# Loop de monitoreo
LAST_STATUS=""
ITERATION=0

while true; do
  ITERATION=$((ITERATION + 1))

  # Obtener estado actual
  STATUS_JSON=$(get_status)

  if [ -z "$STATUS_JSON" ]; then
    echo -e "${RED}❌ Error al obtener estado del workflow${NC}"
    exit 1
  fi

  STATUS=$(echo "$STATUS_JSON" | jq -r '.status')
  CONCLUSION=$(echo "$STATUS_JSON" | jq -r '.conclusion // "running"')
  CREATED=$(echo "$STATUS_JSON" | jq -r '.createdAt')
  UPDATED=$(echo "$STATUS_JSON" | jq -r '.updatedAt')

  # Calcular duración
  DURATION=$(gh run list --workflow="Infrastructure Apply" --limit 1 --json databaseId,createdAt | jq -r '.[0] | .createdAt' | xargs -I {} date -d {} +%s 2>/dev/null || echo "0")
  NOW=$(date +%s)
  ELAPSED=$((NOW - DURATION))

  # Limpiar pantalla cada 10 iteraciones
  if [ $((ITERATION % 10)) -eq 0 ]; then
    clear
    echo -e "${BLUE}╔═══════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║   Workflow Monitor - Real Time           ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════╝${NC}"
    echo ""
  fi

  # Mostrar estado
  echo -ne "\r"

  case $STATUS in
    "in_progress")
      echo -ne "${YELLOW}⏳ In Progress${NC} | Duration: ${ELAPSED}s | Updated: ${UPDATED:11:8}    "
      ;;
    "completed")
      echo -e "\r${GREEN}✅ Completed${NC} | Conclusion: ${CONCLUSION} | Duration: ${ELAPSED}s        "
      break
      ;;
    "cancelled")
      echo -e "\r${RED}❌ Cancelled${NC} | Duration: ${ELAPSED}s                                "
      break
      ;;
    *)
      echo -ne "${BLUE}ℹ️  ${STATUS}${NC} | Duration: ${ELAPSED}s                            "
      ;;
  esac

  # Cambio de estado
  if [ "$STATUS" != "$LAST_STATUS" ]; then
    echo ""
    echo -e "${YELLOW}Status changed: ${LAST_STATUS} → ${STATUS}${NC}"
    LAST_STATUS=$STATUS
  fi

  # Esperar 10 segundos
  sleep 10
done

echo ""
echo ""
echo -e "${GREEN}═══════════════════════════════════════════${NC}"
echo -e "${GREEN}Workflow Finished${NC}"
echo -e "${GREEN}═══════════════════════════════════════════${NC}"
echo ""

# Mostrar resumen final
echo -e "${BLUE}Final Status:${NC}"
gh run view $WORKFLOW_ID --json status,conclusion,createdAt,completedAt | jq -r '"Status: \(.status)\nConclusion: \(.conclusion)\nStarted: \(.createdAt)\nCompleted: \(.completedAt)"'

echo ""
echo -e "${BLUE}View full logs:${NC}"
echo "  gh run view $WORKFLOW_ID --log"

echo ""
echo -e "${BLUE}View in browser:${NC}"
echo "  gh run view $WORKFLOW_ID --web"

# Si falló, mostrar últimas líneas de error
if [ "$CONCLUSION" == "failure" ]; then
  echo ""
  echo -e "${RED}═══════════════════════════════════════════${NC}"
  echo -e "${RED}Errors found:${NC}"
  echo -e "${RED}═══════════════════════════════════════════${NC}"
  gh run view $WORKFLOW_ID --log 2>&1 | grep -i "error\|failed" | tail -20
fi

echo ""
