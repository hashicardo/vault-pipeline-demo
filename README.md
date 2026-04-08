# Vault JWT Auth + Dynamic PostgreSQL Secrets — SE Demo

The pipeline authenticates using your existing Azure AD identity — no Vault
token stored anywhere, no secret pre-shared with GitHub. Vault issues a unique
database credential for this pipeline run only. It has never existed before and
will never exist again. Five minutes later — the countdown hits zero. The
credential is gone. Not rotated. Not revoked. Just gone.

---

## Prerequisites

| Tool | Purpose |
|---|---|
| Terraform >= 1.5 | Infrastructure provisioning |
| Azure CLI (`az`) | Bootstrap authentication |
| Vault CLI | Smoke-testing (optional) |
| `gh` CLI | Setting Actions secrets |

Accounts required: AWS, Azure, HCP Vault (already running), Cloudflare,
GitHub (`hashicardo/vault-pipeline-demo`).

---

## One-time setup

### 1. Export credentials

```bash
# AWS
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...

# Azure (or use az login --use-device-code)
export ARM_TENANT_ID=...
export ARM_CLIENT_ID=...
export ARM_CLIENT_SECRET=...

# HCP Vault
export VAULT_TOKEN=...          # root or admin token

# Cloudflare
export CLOUDFLARE_API_TOKEN=... # needs Zone:DNS:Edit
```

### 2. Sensitive variables

Create a file **outside** the repo (never commit this):

```bash
cat > ~/vault-demo.tfvars <<'EOF'
home_ip              = "YOUR_HOME_IP/32"
office_ip            = "YOUR_OFFICE_IP/32"
ssh_public_key       = "ssh-ed25519 AAAA..."
cloudflare_zone_id   = "YOUR_ZONE_ID"
EOF
```

Export secrets as environment variables (Terraform reads `TF_VAR_*`):

```bash
export TF_VAR_postgres_password="$(openssl rand -base64 24)"
export TF_VAR_cloudflare_api_token="$CLOUDFLARE_API_TOKEN"
```

---

## Apply order

### Step 1 — Azure (Entra ID app + federated credential)

```bash
cd infra/azure
terraform init
terraform apply -var-file=~/vault-demo.tfvars
```

Note the outputs — you need them for Step 3:

```
azure_tenant_id = "..."
azure_client_id = "..."
```

### Step 2 — AWS (EC2, VPC, DNS)

Generate a fresh GitHub runner token first (it expires in 1 hour):

```bash
gh api \
  --method POST \
  -H "Accept: application/vnd.github+json" \
  /repos/hashicardo/vault-pipeline-demo/actions/runners/registration-token \
  --jq '.token'
```

Then apply:

```bash
cd infra/aws
terraform init
terraform apply \
  -var-file=~/vault-demo.tfvars \
  -var="gh_runner_token=TOKEN_FROM_ABOVE"
```

Wait ~3 minutes for the demo VM to boot and PostgreSQL to start before
proceeding.

### Step 3 — Vault (JWT auth, DB secrets engine, policy)

```bash
cd infra/vault
terraform init
terraform apply \
  -var="vault_addr=https://YOUR-HCP-VAULT-URL:8200" \
  -var="azure_tenant_id=TENANT_ID_FROM_STEP_1" \
  -var="azure_client_id=CLIENT_ID_FROM_STEP_1"
```

(Postgres password is read from `TF_VAR_postgres_password`.)

---

## Set GitHub Actions secrets

```bash
REPO="hashicardo/vault-pipeline-demo"

gh secret set AZURE_CLIENT_ID       --repo "$REPO" --body "..."
gh secret set AZURE_TENANT_ID       --repo "$REPO" --body "..."
gh secret set AZURE_SUBSCRIPTION_ID --repo "$REPO" --body "..."
gh secret set VAULT_ADDR            --repo "$REPO" --body "https://YOUR-HCP-VAULT-URL:8200"
```

Create the **`demo`** environment in the repo settings (Actions → Environments).
No secrets need to live in the environment itself — the `bound_claims` in Vault
enforce the environment constraint.

---

## Running the demo

### Main pipeline (triggers automatically on push, or run manually)

```
Actions → Vault JWT Auth Demo → Run workflow
```

Jobs run in order: `auth` → `fetch-secret` → `use-secret`

Watch the web UI at **https://demovm.ricardo.engineer** — the countdown starts
as soon as the credential is issued.

### Expiry proof (run 5+ minutes after the pipeline completes)

```
Actions → Show Secret Expiry → Run workflow
```

Provide the `db_user` and `db_pass` values from the previous run's job
summary. The job will fail with:

```
FATAL: role "v-token-xxxx" does not exist
```

That failure is the demo.

---

## Teardown

```bash
cd infra/vault && terraform destroy
cd infra/aws   && terraform destroy
cd infra/azure && terraform destroy
```

---

## Architecture

```
GitHub Actions (demo env)
  │
  │  GitHub OIDC token
  ▼
Azure Entra ID ──── federated credential ──── no stored secret
  │
  │  Azure access token  (audience: api://<CLIENT_ID>)
  ▼
HCP Vault (JWT auth backend → demo-db-policy)
  │
  │  dynamic credential  (TTL: 300s)
  ▼
PostgreSQL on demo-vm  ──── secret_log table
  │
  ▼
Flask web UI (https://demovm.ricardo.engineer)
  │  countdown timer, auto-refresh every 10s
  ▼
EXPIRED — role dropped by Vault at TTL
```

---

## Key files

| Path | What it does |
|---|---|
| `infra/azure/` | Entra ID app + GitHub OIDC federated credential |
| `infra/aws/` | VPC, EC2 (demo + runner), Cloudflare DNS |
| `infra/vault/` | JWT auth, database secrets engine, policy |
| `web/app.py` | Flask UI — reads `secret_log`, serves countdown |
| `.github/workflows/demo-pipeline.yml` | Main 3-job pipeline |
| `.github/workflows/show-expiry.yml` | Manually-triggered expiry proof |
| `docs/customer-brief.md` | Narrative for customer-facing sessions |
