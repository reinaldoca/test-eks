#!/bin/bash

# ============================================
# Script para gestionar roles de GitHub Actions en AWS
# ============================================

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuración
ROLE_NAME="github-actions-terragrunt"
GITHUB_ORG="reinaldoca"
GITHUB_REPO="*"
GITHUB_BRANCH="main"
POLICY_ARN="arn:aws:iam::aws:policy/AdministratorAccess"

# ============================================
# Funciones de ayuda
# ============================================

function print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

function print_error() {
    echo -e "${RED}✗ $1${NC}"
}

function print_info() {
    echo -e "${YELLOW}ℹ $1${NC}"
}

function print_separator() {
    echo "============================================"
}

# ============================================
# Funciones principales
# ============================================

function check_aws_credentials() {
    print_info "Verificando credenciales AWS..."
    
    if ! aws sts get-caller-identity &>/dev/null; then
        print_error "No se pudieron obtener credenciales AWS. Asegúrate de estar autenticado."
        return 1
    fi
    
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
    print_success "Credenciales AWS verificadas. Account ID: $AWS_ACCOUNT_ID"
    return 0
}

function check_oidc_provider() {
    local provider_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"
    
    print_info "Verificando existencia del OIDC Provider..."
    
    if aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$provider_arn" &>/dev/null; then
        print_success "OIDC Provider ya existe: $provider_arn"
        return 0
    else
        print_info "OIDC Provider no existe. Se creará uno nuevo."
        return 1
    fi
}

function create_oidc_provider() {
    print_info "Creando OIDC Provider..."
    
    if aws iam create-open-id-connect-provider \
        --url "https://token.actions.githubusercontent.com" \
        --client-id-list "sts.amazonaws.com" \
        --thumbprint-list "6938fd4d98bab03faadb97b34396831e3780aea1" &>/dev/null; then
        print_success "OIDC Provider creado exitosamente"
        return 0
    else
        print_error "Error al crear OIDC Provider"
        return 1
    fi
}

function check_role_exists() {
    print_info "Verificando existencia del rol $ROLE_NAME..."
    
    if aws iam get-role --role-name "$ROLE_NAME" &>/dev/null; then
        print_success "El rol $ROLE_NAME ya existe"
        return 0
    else
        print_info "El rol $ROLE_NAME no existe"
        return 1
    fi
}

function create_trust_policy() {
    local policy_file="$1"
    
    # CORREGIDO: Usar StringLike para el sub cuando hay comodines
    cat <<EOF > "$policy_file"
{
    "Version": "2012-10-17",
    "Statement": [{
        "Effect": "Allow",
        "Principal": {
            "Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"
        },
        "Action": "sts:AssumeRoleWithWebIdentity",
        "Condition": {
            "StringEquals": {
                "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
            },
            "StringLike": {
                "token.actions.githubusercontent.com:sub": "repo:${GITHUB_ORG}/*"
            }
        }
    }]
}
EOF
}

function create_role() {
    local trust_policy_file="trust-policy-${RANDOM}.json"
    
    print_info "Creando trust policy..."
    create_trust_policy "$trust_policy_file"
    print_success "Trust policy creada temporalmente en $trust_policy_file"
    
    # Mostrar el contenido del trust policy para debugging
    print_info "Contenido del trust policy:"
    cat "$trust_policy_file"
    echo ""
    
    print_info "Creando rol $ROLE_NAME..."
    if aws iam create-role \
        --role-name "$ROLE_NAME" \
        --assume-role-policy-document "file://$trust_policy_file" 2>&1; then
        print_success "Rol $ROLE_NAME creado exitosamente"
        
        # Asignar política al rol
        print_info "Asignando política $POLICY_ARN al rol..."
        if aws iam attach-role-policy \
            --role-name "$ROLE_NAME" \
            --policy-arn "$POLICY_ARN" &>/dev/null; then
            print_success "Política asignada exitosamente"
        else
            print_error "Error al asignar política al rol"
            rm -f "$trust_policy_file"
            return 1
        fi
        
        rm -f "$trust_policy_file"
        print_success "Archivo temporal eliminado"
        return 0
    else
        print_error "Error al crear el rol"
        rm -f "$trust_policy_file"
        return 1
    fi
}

# ============================================
# Función para verificar la configuración del rol
# ============================================

function verify_role_config() {
    print_info "Verificando configuración del rol..."
    
    if ! aws iam get-role --role-name "$ROLE_NAME" &>/dev/null; then
        print_error "El rol $ROLE_NAME no existe"
        return 1
    fi
    
    # Obtener y mostrar el trust policy actual
    print_info "Trust policy actual:"
    aws iam get-role --role-name "$ROLE_NAME" --query 'Role.AssumeRolePolicyDocument' --output json | jq '.'
    
    echo ""
    print_info "Verificando si el rol puede ser asumido por GitHub Actions..."
    
    # Probar la asunción del rol (simulación)
    echo -e "${YELLOW}Para probar manualmente, ejecuta:${NC}"
    echo "aws sts assume-role-with-web-identity \\"
    echo "  --role-arn arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME} \\"
    echo "  --role-session-name test \\"
    echo "  --web-identity-token <TOKEN> \\"
    echo "  --provider-id token.actions.githubusercontent.com"
    
    return 0
}

# ============================================
# Script principal y menú
# ============================================

function show_menu() {
    clear
    print_separator
    echo -e "${GREEN}GESTIÓN DE ROLES GITHUB ACTIONS EN AWS${NC}"
    print_separator
    echo "1. Crear rol (con validaciones)"
    echo "2. Eliminar rol (con validaciones)"
    echo "3. Mostrar información del rol"
    echo "4. Verificar configuración del rol"
    echo "5. Salir"
    print_separator
    echo -n "Selecciona una opción [1-5]: "
}

function show_role_info() {
    print_info "Obteniendo información del rol $ROLE_NAME..."
    
    if ! aws iam get-role --role-name "$ROLE_NAME" &>/dev/null; then
        print_error "El rol $ROLE_NAME no existe"
        return 1
    fi
    
    echo ""
    echo "📋 INFORMACIÓN DEL ROL:"
    echo "📌 Nombre: $ROLE_NAME"
    echo "📌 ARN: arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME}"
    echo ""
    echo "📌 Trust Policy:"
    aws iam get-role --role-name "$ROLE_NAME" --query 'Role.AssumeRolePolicyDocument' --output json | jq '.'
    echo ""
    echo "📌 Políticas adjuntas:"
    
    local policies=$(aws iam list-attached-role-policies --role-name "$ROLE_NAME" --query 'AttachedPolicies[].PolicyArn' --output text)
    if [ -n "$policies" ]; then
        for policy in $policies; do
            echo "   - $policy"
        done
    else
        echo "   (No hay políticas adjuntas)"
    fi
    
    echo ""
    return 0
}

function create_role_with_validation() {
    print_separator
    echo -e "${GREEN}CREANDO ROL PARA GITHUB ACTIONS${NC}"
    print_separator
    
    # Validaciones iniciales
    if ! check_aws_credentials; then
        return 1
    fi
    
    # Configurar OIDC Provider
    if ! check_oidc_provider; then
        if ! create_oidc_provider; then
            return 1
        fi
    fi
    
    # Verificar si el rol ya existe
    if check_role_exists; then
        print_info "El rol ya existe. ¿Deseas recrearlo? (s/N): "
        read -r recreate
        if [[ ! "$recreate" =~ ^[Ss]$ ]]; then
            print_info "Operación cancelada"
            return 0
        fi
        
        print_info "Eliminando rol existente..."
        if delete_role; then
            print_success "Rol eliminado. Procediendo con la creación..."
        else
            print_error "No se pudo eliminar el rol existente"
            return 1
        fi
    fi
    
    # Crear el rol
    if create_role; then
        print_separator
        print_success "🎉 Rol creado exitosamente!"
        echo -e "${GREEN}ARN: arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME}${NC}"
        echo ""
        echo -e "${YELLOW}⚠️  IMPORTANTE: Configuración para GitHub Actions:${NC}"
        echo "1. Agrega este ARN como secret en GitHub: AWS_ROLE_ARN"
        echo "2. Asegúrate de que el workflow de GitHub use:"
        echo "   - name: Configure AWS credentials"
        echo "     uses: aws-actions/configure-aws-credentials@v4"
        echo "     with:"
        echo "       role-to-assume: arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME}"
        echo "       aws-region: us-east-1"
        echo ""
        print_separator
        return 0
    else
        print_error "❌ Error al crear el rol"
        return 1
    fi
}

function delete_role_with_validation() {
    print_separator
    echo -e "${RED}ELIMINANDO ROL PARA GITHUB ACTIONS${NC}"
    print_separator
    
    # Validaciones iniciales
    if ! check_aws_credentials; then
        return 1
    fi
    
    # Verificar si el rol existe
    if ! check_role_exists; then
        print_error "El rol $ROLE_NAME no existe. No hay nada que eliminar."
        return 1
    fi
    
    # Confirmación
    echo -n "¿Estás seguro de que deseas eliminar el rol $ROLE_NAME? (s/N): "
    read -r confirm
    
    if [[ ! "$confirm" =~ ^[Ss]$ ]]; then
        print_info "Operación cancelada"
        return 0
    fi
    
    # Eliminar el rol
    if delete_role; then
        print_separator
        print_success "✅ Rol eliminado exitosamente!"
        print_separator
        return 0
    else
        print_error "❌ Error al eliminar el rol"
        return 1
    fi
}

function delete_role() {
    print_info "Iniciando eliminación del rol $ROLE_NAME..."
    
    # Verificar si el rol existe
    if ! aws iam get-role --role-name "$ROLE_NAME" &>/dev/null; then
        print_error "El rol $ROLE_NAME no existe"
        return 1
    fi
    
    # Obtener todas las políticas adjuntas
    print_info "Obteniendo políticas adjuntas..."
    local attached_policies=$(aws iam list-attached-role-policies --role-name "$ROLE_NAME" --query 'AttachedPolicies[].PolicyArn' --output text)
    
    if [ -n "$attached_policies" ]; then
        print_info "Desadjuntando políticas..."
        for policy in $attached_policies; do
            if aws iam detach-role-policy --role-name "$ROLE_NAME" --policy-arn "$policy" &>/dev/null; then
                print_success "Política $policy desadjuntada"
            else
                print_error "Error al desadjuntar política $policy"
            fi
        done
    else
        print_info "No hay políticas adjuntas"
    fi
    
    # Eliminar políticas inline si existen
    print_info "Verificando políticas inline..."
    local inline_policies=$(aws iam list-role-policies --role-name "$ROLE_NAME" --query 'PolicyNames[]' --output text)
    
    if [ -n "$inline_policies" ]; then
        print_info "Eliminando políticas inline..."
        for policy in $inline_policies; do
            if aws iam delete-role-policy --role-name "$ROLE_NAME" --policy-name "$policy" &>/dev/null; then
                print_success "Política inline $policy eliminada"
            else
                print_error "Error al eliminar política inline $policy"
            fi
        done
    else
        print_info "No hay políticas inline"
    fi
    
    # Eliminar el rol
    print_info "Eliminando rol $ROLE_NAME..."
    if aws iam delete-role --role-name "$ROLE_NAME" &>/dev/null; then
        print_success "Rol $ROLE_NAME eliminado exitosamente"
        return 0
    else
        print_error "Error al eliminar el rol"
        return 1
    fi
}

# ============================================
# Script principal
# ============================================

main() {
    # Configuración inicial
    print_info "🚀 Iniciando script de gestión de roles para GitHub Actions"
    print_info "📁 Organización: $GITHUB_ORG"
    print_info "📁 Repositorio: $GITHUB_REPO"
    print_info "🌿 Rama: $GITHUB_BRANCH"
    print_info "🔑 Rol: $ROLE_NAME"
    
    # Verificar si jq está instalado
    if ! command -v jq &> /dev/null; then
        print_info "⚠️  jq no está instalado. Instalando..."
        if [[ "$OSTYPE" == "linux-gnu"* ]]; then
            sudo apt-get install -y jq
        elif [[ "$OSTYPE" == "darwin"* ]]; then
            brew install jq
        fi
    fi
    
    # Soporte para argumentos de línea de comandos
    if [ $# -gt 0 ]; then
        case "$1" in
            create)
                create_role_with_validation
                exit $?
                ;;
            delete)
                delete_role_with_validation
                exit $?
                ;;
            info)
                if check_aws_credentials; then
                    show_role_info
                fi
                exit $?
                ;;
            verify)
                if check_aws_credentials; then
                    verify_role_config
                fi
                exit $?
                ;;
            *)
                echo "Uso: $0 {create|delete|info|verify}"
                echo "  create - Crear el rol con validaciones"
                echo "  delete - Eliminar el rol con validaciones"
                echo "  info   - Mostrar información del rol"
                echo "  verify - Verificar configuración del rol"
                exit 1
                ;;
        esac
    fi
    
    # Modo interactivo
    while true; do
        show_menu
        read -r option
        
        case $option in
            1)
                create_role_with_validation
                ;;
            2)
                delete_role_with_validation
                ;;
            3)
                if check_aws_credentials; then
                    show_role_info
                fi
                ;;
            4)
                if check_aws_credentials; then
                    verify_role_config
                fi
                ;;
            5)
                print_info "👋 Saliendo..."
                exit 0
                ;;
            *)
                print_error "Opción inválida. Por favor selecciona 1-5"
                ;;
        esac
        
        echo ""
        echo -n "Presiona Enter para continuar..."
        read -r
    done
}

# Ejecutar función principal con argumentos
main "$@"