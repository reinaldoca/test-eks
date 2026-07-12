# Terragrunt 1.x Migration Guide

## 🔄 Cambios de Sintaxis (0.x → 1.x)

### Comandos `run-all` → `run --all`

**❌ Terragrunt 0.x:**
```bash
terragrunt run-all init
terragrunt run-all plan
terragrunt run-all apply
terragrunt run-all destroy
```

**✅ Terragrunt 1.x:**
```bash
terragrunt run --all init
terragrunt run --all plan
terragrunt run --all apply
terragrunt run --all destroy
```

---

### Flags sin prefijo `terragrunt-`

**❌ Terragrunt 0.x:**
```bash
terragrunt plan --terragrunt-non-interactive
terragrunt apply --terragrunt-working-dir /path
terragrunt apply --terragrunt-out-dir /tmp/plans
```

**✅ Terragrunt 1.x:**
```bash
terragrunt plan --non-interactive
terragrunt apply --working-dir /path
terragrunt apply --out-dir /tmp/plans
```

---

## 📋 Tabla de Equivalencias

| Terragrunt 0.x | Terragrunt 1.x |
|----------------|----------------|
| `run-all` | `run --all` |
| `--terragrunt-non-interactive` | `--non-interactive` |
| `--terragrunt-working-dir` | `--working-dir` |
| `--terragrunt-download-dir` | `--download-dir` |
| `--terragrunt-source` | `--source` |
| `--terragrunt-out-dir` | `--out-dir` |
| `--terragrunt-parallelism` | `--parallelism` |
| `--terragrunt-include-external-dependencies` | `--include-external-dependencies` |

---

## 🚀 Comandos Comunes

### Workflow Completo

```bash
cd infrastructure/production

# 1. Inicializar (descargar providers)
terragrunt run --all init

# 1b. Init con upgrade de providers (actualizar a últimas versiones)
terragrunt run --all init -- -upgrade

# 2. Validar sintaxis
terragrunt run --all validate

# 3. Plan (ver cambios)
terragrunt run --all plan

# 4. Apply (aplicar cambios)
terragrunt run --all apply

# 5. Destroy (eliminar recursos) - ¡CUIDADO!
terragrunt run --all destroy
```

### Importante: Separador `--` para flags de Terraform

En Terragrunt 1.x, los flags de Terraform deben ir después de `--`:

```bash
# ❌ Incorrecto
terragrunt run --all init -upgrade
terragrunt run --all plan -out=tfplan

# ✅ Correcto
terragrunt run --all init -- -upgrade
terragrunt run --all plan -- -out=tfplan
```

### Comandos por Módulo Específico

```bash
# En lugar de run --all, omitir el flag
cd infrastructure/production/vpc
terragrunt init
terragrunt plan
terragrunt apply
```

### Comandos con Opciones

```bash
# Plan con output
terragrunt run --all plan -out=tfplan

# Apply sin confirmación (CI/CD)
terragrunt run --all apply --auto-approve

# Apply con paralelismo personalizado
terragrunt run --all apply --parallelism 5

# Plan solo para módulos específicos
terragrunt run --all plan --terragrunt-include-dir vpc --terragrunt-include-dir eks
```

---

## 🔧 Troubleshooting

### Error: "unknown command: run-all"

**Problema:**
```
ERROR  unknown command: "run-all". Terragrunt no longer forwards unknown commands by default.
```

**Solución:**
```bash
# ❌ Antiguo
terragrunt run-all init

# ✅ Nuevo
terragrunt run --all init
```

---

### Error: "flag provided but not defined: -terragrunt-non-interactive"

**Problema:**
```
ERROR  flag provided but not defined: -terragrunt-non-interactive
```

**Solución:**
```bash
# ❌ Antiguo
terragrunt apply --terragrunt-non-interactive

# ✅ Nuevo
terragrunt apply --non-interactive
```

---

## 📖 Documentación Oficial

- **CLI Redesign:** https://docs.terragrunt.com/migrate/cli-redesign/
- **Migration Guide:** https://docs.terragrunt.com/migrate/
- **New Commands:** https://docs.terragrunt.com/commands/

---

## ✅ Checklist de Migración

- [x] Actualizar `run-all` a `run --all`
- [x] Remover prefijo `--terragrunt-` de flags
- [x] Actualizar pipelines de CI/CD
- [x] Actualizar documentación (README, runbooks)
- [x] Probar comandos localmente
- [x] Actualizar version constraints en `terragrunt.hcl`

---

**Versiones usadas en este proyecto:**
- Terraform: `>= 1.15.0`
- Terragrunt: `>= 1.1.0`
