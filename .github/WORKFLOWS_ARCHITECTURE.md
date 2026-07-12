# GitHub Actions Workflows Architecture

## 📋 Resumen de Pipelines

| Workflow | Trigger | Propósito | Duration |
|----------|---------|-----------|----------|
| **Infrastructure Plan** | Pull Request → `main` | Plan + Security Scan | ~3-5 min |
| **Infrastructure Apply** | Push → `main` | Apply con approval | ~10-15 min |
| **Service A CI/CD** | Push → `main` (código service-a) | Build + Push + GitOps | ~8-10 min |
| **ArgoCD Sync** | Manual dispatch | Forzar sync de ArgoCD | ~2-3 min |

---

## 🔄 Flujo Completo de Infraestructura

```
┌─────────────────────────────────────────────────────────────┐
│  Developer: Cambio en infrastructure/**                     │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ├─ git checkout -b feat/add-subnet
                        ├─ vim infrastructure/production/vpc/terragrunt.hcl
                        ├─ git commit -m "feat: add new subnet"
                        └─ git push origin feat/add-subnet
                                │
                                ▼
┌─────────────────────────────────────────────────────────────┐
│  GitHub: Pull Request Created                               │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│  🔷 Infrastructure Plan Workflow                            │
├─────────────────────────────────────────────────────────────┤
│  Trigger: pull_request → main                               │
│  Purpose: Show changes BEFORE merge                         │
│                                                              │
│  Job 1: terragrunt-plan                                     │
│    ├─ Terragrunt Init                                       │
│    ├─ Terragrunt Validate                                   │
│    ├─ Terragrunt Plan                                       │
│    ├─ Upload plan-output.txt (artifact)                     │
│    └─ 💬 Comment plan in PR                                 │
│                                                              │
│  Job 2: security-scan (parallel)                            │
│    ├─ Checkov (IaC security scan)                           │
│    └─ Upload SARIF to Security tab                          │
│                                                              │
│  ✅ Result: PR shows what will change                       │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ├─ 👥 Code Review (2 approvals)
                        ├─ ✅ All checks passed
                        └─ 🔀 Merge to main
                                │
                                ▼
┌─────────────────────────────────────────────────────────────┐
│  🔶 Infrastructure Apply Workflow                           │
├─────────────────────────────────────────────────────────────┤
│  Trigger: push → main                                       │
│  Purpose: Apply approved changes                            │
│                                                              │
│  Job 1: terragrunt-apply                                    │
│    Environment: production ⏸️  ← PAUSA para approval        │
│                                                              │
│    ├─ ⏸️  Wait for manual approval                          │
│    │   └─ Email notification a reviewers                    │
│    │                                                         │
│    ├─ ✅ Approval granted                                   │
│    ├─ Terragrunt Init                                       │
│    ├─ Terragrunt Plan (verification)                        │
│    ├─ Terragrunt Apply (auto-approve)                       │
│    ├─ Extract outputs (VPC, EKS, S3)                        │
│    ├─ Update kubeconfig                                     │
│    └─ Verify cluster access                                 │
│                                                              │
│  Job 2: post-apply-validation                               │
│    ├─ Verify VPC exists                                     │
│    ├─ Verify EKS cluster running                            │
│    ├─ Verify S3 buckets created                             │
│    └─ Verify ECR repositories                               │
│                                                              │
│  ✅ Result: Infrastructure deployed                         │
└─────────────────────────────────────────────────────────────┘
```

---

## 🎯 **Diferencias Clave Entre Plan y Apply**

### **Infrastructure Plan** (en PRs)

**Cuándo se ejecuta:**
- ✅ En Pull Requests hacia `main`
- ✅ Cuando se modifican archivos en `infrastructure/**`

**Qué hace:**
- ✅ Muestra cambios propuestos (plan)
- ✅ Escaneo de seguridad con Checkov
- ✅ Comenta el plan directamente en el PR
- ❌ **NO aplica cambios**
- ❌ **NO requiere approval**

**Propósito:**
- Permitir code review antes de merge
- Detectar problemas de seguridad temprano
- Mostrar impacto de los cambios

---

### **Infrastructure Apply** (después del merge)

**Cuándo se ejecuta:**
- ✅ Después de merge a `main`
- ✅ Manual dispatch (workflow_dispatch)

**Qué hace:**
- ✅ **Pausa y espera approval manual** (GitHub Environment)
- ✅ Verifica el plan una última vez
- ✅ Aplica los cambios con `-auto-approve`
- ✅ Extrae outputs (IDs de recursos)
- ✅ Valida que todo se creó correctamente
- ✅ Crea issue en GitHub si falla

**Propósito:**
- Aplicar cambios solo después de revisión humana
- Evitar deployments accidentales
- Validar que la infraestructura está saludable

---

## 🔒 **GitHub Environment Protection Rules**

Para que el approval funcione, debes configurar el environment en GitHub:

### **Pasos:**

1. **Ir a:** `Settings` → `Environments` → `New environment`
2. **Nombre:** `production`
3. **Protection Rules:**
   ```
   ✅ Required reviewers: 2 personas (platform engineers)
   ✅ Wait timer: 0 minutos (o 5 min para emergencias)
   ✅ Prevent self-review: Habilitado
   ✅ Allow administrators to bypass: Deshabilitado
   ```
4. **Environment secrets** (si se necesitan):
   ```
   AWS_ACCOUNT_ID
   ```

### **Resultado:**

Cuando el workflow llegue a `terragrunt-apply`, verás:

```
Workflow: Infrastructure Apply

Jobs:
  terragrunt-apply
    Status: ⏸️  Waiting for approval
    Message: Review pending deployments
    
    [Review deployment] ← Botón para aprobar
    
  post-apply-validation
    Status: ⏳ Waiting (needs: terragrunt-apply)
```

---

## ⚡ **Optimizaciones Implementadas**

### **1. No Duplicar Plan**

**❌ Antes:**
```yaml
# Infrastructure Apply ejecutaba:
- plan  ← Duplicado del PR
- apply
```

**✅ Ahora:**
```yaml
# Infrastructure Apply ejecuta:
- plan (solo verification)
- apply
```

El plan principal ya se hizo en el PR. En `main` solo hacemos un plan de verificación rápido antes de apply.

---

### **2. Approval Manual Obligatorio**

**❌ Antes:**
- Apply se ejecutaba automáticamente al merge

**✅ Ahora:**
- Apply **pausa** y espera approval
- Notification por email
- Requiere click manual "Approve deployment"

---

### **3. Artifacts para Auditoría**

Todos los planes y applies se guardan como artifacts:

```yaml
Artifacts (retention 30 días):
  ├─ terragrunt-plan-output (from PR)
  ├─ plan-verification (from apply job)
  └─ terragrunt-apply-output (from apply job)
```

---

## 🚨 **Casos de Uso Especiales**

### **1. Emergency Apply (skip plan)**

Si necesitas aplicar cambios urgentes sin el plan de verificación:

```bash
# En GitHub UI:
Actions → Infrastructure Apply → Run workflow
  Environment: production
  Skip plan: true  ← Checkbox
  Run workflow
```

⚠️ **PELIGRO:** Esto salta la verificación y aplica directamente. Usar solo en emergencias.

---

### **2. Apply a Staging/Dev**

```bash
# En GitHub UI:
Actions → Infrastructure Apply → Run workflow
  Environment: staging  ← Seleccionar
  Skip plan: false
  Run workflow
```

---

### **3. Rollback (manual)**

Si un apply falla o causa problemas:

```bash
# 1. Revertir el commit en Git
git revert <commit-sha>
git push origin main

# 2. Esto triggeará Infrastructure Apply de nuevo
# 3. Aprobar el rollback después de revisar el plan

# Alternativa: Terraform state rollback (más complejo)
terraform state pull > backup.tfstate
terraform state push previous.tfstate
```

---

## 📊 **Métricas y Monitoreo**

### **Success Rate Target**
- Infrastructure Plan: **100%** (solo plan, no puede fallar infraestructura)
- Infrastructure Apply: **95%+** (puede fallar por problemas reales de AWS)

### **Duration Target**
- Plan: < 5 minutos
- Apply: < 15 minutos (sin contar tiempo de approval humano)

### **Dashboards**
- GitHub Actions Insights
- Slack notifications
- GitHub Issues (auto-created on failure)

---

## 🔗 **Relación con Otros Workflows**

```
Infrastructure Apply
    ↓ (crea EKS cluster)
Service A CI/CD
    ↓ (push image to ECR)
ArgoCD Sync
    ↓ (deploy to K8s)
Production! ✅
```

---

## 📚 **Referencias**

- [GitHub Environments](https://docs.github.com/en/actions/deployment/targeting-different-environments/using-environments-for-deployment)
- [Terragrunt Best Practices](https://terragrunt.gruntwork.io/docs/getting-started/quick-start/)
- [Terraform CI/CD Patterns](https://www.terraform.io/docs/cloud/guides/recommended-practices/part3.html)

---

**Última actualización:** 2024-07-11
**Mantenido por:** Platform Engineering Team
