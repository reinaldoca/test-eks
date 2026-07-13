# Guía de Uso: deploy-dev.sh

Script mejorado para gestionar infraestructura de Dev con Terragrunt.

## 📋 Comandos Disponibles

### `init` - Inicializar Terragrunt
Limpia cache y ejecuta `terragrunt init` en todos los módulos.

```bash
./deploy-dev.sh init
```

### `plan` - Ver cambios sin aplicar
Ejecuta `terragrunt plan` y guarda output en `plan-output.txt`.

```bash
./deploy-dev.sh plan
```

**Útil para:** Revisar cambios antes de aplicar, validar configuración.

### `apply` - Aplicar cambios
Ejecuta plan primero, luego aplica cambios (con confirmación).

```bash
./deploy-dev.sh apply

# Sin confirmación
./deploy-dev.sh apply --auto-approve
```

### `destroy` - Destruir infraestructura
**⚠️ PELIGROSO** - Destruye toda la infraestructura.

```bash
./deploy-dev.sh destroy

# Sin confirmación (requiere escribir "destroy-all")
./deploy-dev.sh destroy --auto-approve
```

### `validate` - Validar configuración
Valida sintaxis de Terraform sin ejecutar plan.

```bash
./deploy-dev.sh validate
```

### `output` - Ver outputs
Muestra outputs de todos los módulos.

```bash
./deploy-dev.sh output
```

### `all` - Pipeline completo
Ejecuta: init → validate → plan → apply (con confirmación interactiva).

```bash
./deploy-dev.sh all
```

**Recomendado para:** Primer deployment o cambios mayores.

---

## 🎯 Opciones

### `--target=MODULE`
Ejecuta comando solo en un módulo específico.

**Módulos disponibles:**
- `vpc` - Virtual Private Cloud
- `eks` - EKS Cluster (con Auto Mode)
- `s3-loki` - Bucket S3 para logs de Loki
- `ecr` - Elastic Container Registry
- `iam-roles` - Roles IAM (IRSA)

**Ejemplos:**
```bash
# Solo actualizar VPC
./deploy-dev.sh plan --target=vpc

# Destruir solo EKS
./deploy-dev.sh destroy --target=eks

# Aplicar cambios solo en IAM
./deploy-dev.sh apply --target=iam-roles
```

### `--auto-approve`
Aplica cambios sin pedir confirmación (solo para `apply` y `destroy`).

```bash
./deploy-dev.sh apply --auto-approve
./deploy-dev.sh destroy --target=s3-loki --auto-approve
```

**⚠️ CUIDADO:** Úsalo solo en pipelines CI/CD o cuando estés 100% seguro.

### `--no-cache-clean`
No limpia cache de Terragrunt antes de ejecutar.

```bash
./deploy-dev.sh init --no-cache-clean
```

**Útil para:** Depuración, cuando no quieres re-descargar módulos.

---

## 📚 Ejemplos de Uso

### Primer deployment (todo desde cero)
```bash
# 1. Inicializar
./deploy-dev.sh init

# 2. Ver plan completo
./deploy-dev.sh plan

# 3. Aplicar (con confirmación)
./deploy-dev.sh apply

# 4. Ver outputs
./deploy-dev.sh output
```

**O simplemente:**
```bash
./deploy-dev.sh all
```

---

### Actualizar solo un módulo
```bash
# Cambios en EKS
./deploy-dev.sh plan --target=eks
./deploy-dev.sh apply --target=eks
```

---

### Pipeline CI/CD (sin interacción)
```bash
./deploy-dev.sh init
./deploy-dev.sh plan
./deploy-dev.sh apply --auto-approve
```

---

### Destruir todo (con seguridad)
```bash
# Primero ver qué se destruirá
./deploy-dev.sh plan

# Destruir (requiere escribir "destroy-all")
./deploy-dev.sh destroy
```

---

### Debug de un módulo específico
```bash
# No limpiar cache, ver plan de VPC
./deploy-dev.sh plan --target=vpc --no-cache-clean

# Ver logs detallados
TF_LOG=DEBUG ./deploy-dev.sh plan --target=vpc
```

---

## 🔍 Verificaciones Automáticas

El script verifica automáticamente:
- ✅ Directorio correcto (`infrastructure/dev/`)
- ✅ AWS credentials configuradas
- ✅ Terragrunt y Terraform instalados
- ✅ Región de AWS

---

## 📁 Archivos Generados

| Archivo | Descripción |
|---------|-------------|
| `plan-output.txt` | Output del último `terragrunt plan` |
| `apply-output.txt` | Output del último `terragrunt apply` |
| `destroy-output.txt` | Output del último `terragrunt destroy` |
| `.terragrunt-cache/` | Cache de Terragrunt (limpiado por defecto) |

---

## 🚨 Troubleshooting

### Error: "Debes ejecutar este script desde infrastructure/dev/"
**Solución:** Navega al directorio correcto:
```bash
cd infrastructure/dev
./deploy-dev.sh <comando>
```

### Error: "No hay credenciales de AWS configuradas"
**Solución:** Configura AWS CLI:
```bash
aws configure
# O usa AWS SSO:
aws sso login --profile <profile>
export AWS_PROFILE=<profile>
```

### Error: "terragrunt no está instalado"
**Solución:** Instala Terragrunt:
```bash
# macOS
brew install terragrunt

# Linux/Windows
# Ver: https://terragrunt.gruntwork.io/docs/getting-started/install/
```

### Plan tarda mucho / timeouts
**Solución:** Ejecuta por módulo individual:
```bash
./deploy-dev.sh plan --target=vpc
./deploy-dev.sh plan --target=eks
# ... etc
```

### Cache corrupto
**Solución:** Limpia cache manualmente:
```bash
find . -type d -name ".terragrunt-cache" -exec rm -rf {} +
./deploy-dev.sh init
```

---

## 🎓 Best Practices

1. **Siempre ejecuta `plan` antes de `apply`**
   ```bash
   ./deploy-dev.sh plan
   # Revisar cambios
   ./deploy-dev.sh apply
   ```

2. **Usa `--target` para cambios pequeños**
   - Más rápido
   - Menos riesgo
   - Más fácil de debuggear

3. **Usa `--auto-approve` solo en CI/CD**
   - Nunca lo uses manualmente sin revisar plan primero

4. **Guarda outputs importantes**
   ```bash
   ./deploy-dev.sh output > infrastructure-outputs.txt
   ```

5. **Destruye en orden inverso**
   ```bash
   ./deploy-dev.sh destroy --target=iam-roles
   ./deploy-dev.sh destroy --target=eks
   ./deploy-dev.sh destroy --target=ecr
   ./deploy-dev.sh destroy --target=s3-loki
   ./deploy-dev.sh destroy --target=vpc
   ```

---

## 🔗 Referencias

- [Terragrunt Docs](https://terragrunt.gruntwork.io/)
- [Terraform Docs](https://www.terraform.io/docs)
- [AWS EKS Auto Mode](https://docs.aws.amazon.com/eks/latest/userguide/automode.html)
- [DEPLOY_ORDER.md](./DEPLOY_ORDER.md) - Orden de deployment
- [QUICK_START.md](./QUICK_START.md) - Guía rápida

---

## 💡 Tips

**Ver logs en tiempo real:**
```bash
./deploy-dev.sh apply 2>&1 | tee live-output.txt
```

**Ver solo cambios específicos:**
```bash
./deploy-dev.sh plan | grep -A 10 "Resource actions"
```

**Verificar estado actual:**
```bash
cd vpc && terragrunt state list
cd ../eks && terragrunt state list
```

**Ver outputs de un módulo:**
```bash
cd eks && terragrunt output -json | jq
```
