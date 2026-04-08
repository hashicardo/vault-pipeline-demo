# Vault JWT Auth + Dynamic PostgreSQL Secrets — SE Demo

The pipeline authenticates using your existing Azure AD identity — no Vault
token stored anywhere, no secret pre-shared with GitHub. Vault issues a unique
database credential for this pipeline run only. It has never existed before and
will never exist again. Five minutes later — the countdown hits zero. The
credential is gone. Not rotated. Not revoked. Just gone.

---

## Prerequisites

| Tool | Version | Purpose |
|---|---|---|
| Terraform | >= 1.11 | Infrastructure provisioning |
| Azure CLI (`az`) | any | Bootstrap authentication |
| Vault CLI | any | Smoke-testing (optional) |
| `gh` CLI | any | Runner token + setting Actions secrets |

Accounts required: AWS, Azure, HCP (Vault + platform credentials), Cloudflare,
GitHub (`hashicardo/vault-pipeline-demo`).

---

## One-time setup

### 1. Export credentials

All providers authenticate via environment variables — nothing sensitive goes
into `.tf` or `.tfvars` files.

```bash
# AWS (use doormat or long-lived creds)
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_SESSION_TOKEN="..."        # if using doormat / assumed role

# Azure — option A: service principal
export ARM_TENANT_ID="..."
export ARM_CLIENT_ID="..."
export ARM_CLIENT_SECRET="..."
# Azure — option B: CLI login (local dev)
# az login && export ARM_USE_CLI=true

# HCP platform (used by the HCP Terraform provider for VPC peering)
export HCP_CLIENT_ID="..."
export HCP_CLIENT_SECRET="..."

# HCP Vault (used by the Vault Terraform provider)
export VAULT_ADDR="https://<cluster-id>.hashicorp.cloud:8200"
export VAULT_TOKEN="..."              # admin token for the admin namespace

# Cloudflare (used by both the Cloudflare provider and Caddy on the VM)
export CLOUDFLARE_API_TOKEN="..."     # needs Zone:DNS:Edit
```

### 2. Export sensitive Terraform variables

These are marked `sensitive = true` in the modules and must not appear in any
`.tfvars` file. Terraform picks them up automatically from `TF_VAR_*`.

```bash
# PostgreSQL root password — pick something strong, reuse it for all modules
export TF_VAR_postgres_password="$(openssl rand -base64 24)"

# Cloudflare API token (also passed into the demo VM for Caddy's TLS challenge)
export TF_VAR_cloudflare_api_token="$CLOUDFLARE_API_TOKEN"

# GitHub runner registration token — expires in 1 hour, generate fresh before
# applying infra/aws each time
export TF_VAR_gh_runner_token="$(gh api \
  --method POST \
  -H "Accept: application/vnd.github+json" \
  /repos/hashicardo/vault-pipeline-demo/actions/runners/registration-token \
  --jq '.token')"
```

### 3. Populate per-module tfvars

Each module ships with a `terraform.tfvars.example`. Copy and fill in the
non-sensitive values — these files are gitignored and stay local.

```bash
cp infra/aws/terraform.tfvars.example   infra/aws/terraform.tfvars
cp infra/vault/terraform.tfvars.example infra/vault/terraform.tfvars
# infra/azure has no input variables — nothing to copy
```

Key values to fill in `infra/aws/terraform.tfvars`:

| Variable | Where to find it |
|---|---|
| `home_ip` / `office_ip` | Your public IPs as `/32` CIDRs |
| `ssh_public_key` | Contents of `~/.ssh/id_ed25519.pub` |
| `cloudflare_zone_id` | Cloudflare dashboard → your domain → Overview |
| `hcp_org_id` | HCP Portal → Settings → General |
| `hcp_project_id` | HCP Portal → Settings → General |
| `hvn_id` | HCP Portal → Virtual Networks (CIDR is read automatically) |

---

## Apply order

### Step 1 — Azure (Entra ID app + federated credential)

```bash
cd infra/azure
terraform init
terraform apply
```

Capture the outputs for Step 3:

```bash
terraform output azure_tenant_id
terraform output azure_client_id
```

Fill both values into `infra/vault/terraform.tfvars`.

### Step 2 — AWS (VPC, EC2, DNS, HCP peering)

> Ensure `TF_VAR_gh_runner_token` is set — it expires in 1 hour.

```bash
cd infra/aws
terraform init
terraform apply
```

Once applied, populate the private IP into the Vault module's tfvars before
proceeding — Vault connects over the HVN peering, not the public hostname:

```bash
terraform output -raw demo_vm_private_ip
# paste the result into infra/vault/terraform.tfvars as db_hostname
```

Wait ~3 minutes for the demo VM to boot and PostgreSQL to initialise before
proceeding to Step 3.

### Step 3 — Vault (namespace, JWT auth, DB secrets engine, policy)

```bash
cd infra/vault
terraform init
terraform apply
```

`TF_VAR_postgres_password` is the only sensitive variable; everything else is
in `terraform.tfvars`.

---

## Set GitHub Actions secrets

```bash
REPO="hashicardo/vault-pipeline-demo"

gh secret set AZURE_CLIENT_ID       --repo "$REPO" --body "$(cd infra/azure && terraform output -raw azure_client_id)"
gh secret set AZURE_TENANT_ID       --repo "$REPO" --body "$(cd infra/azure && terraform output -raw azure_tenant_id)"
gh secret set AZURE_SUBSCRIPTION_ID --repo "$REPO" --body "$(az account show --query id -o tsv)"
gh secret set VAULT_ADDR            --repo "$REPO" --body "$VAULT_ADDR"
```

Create the **`demo`** environment in repo Settings → Environments. No secrets
need to live in the environment itself — the `bound_claims` in the Vault JWT
role enforce the environment constraint.

---

## Running the demo

### Main pipeline

```
Actions → Vault JWT Auth Demo → Run workflow
```

Jobs run in order: `auth` → `fetch-secret` → `use-secret`

Watch **https://demovm.ricardo.engineer** — the countdown starts as soon as the
credential is issued.

### Expiry proof (run 5+ minutes after the pipeline completes)

```
Actions → Show Secret Expiry → Run workflow
```

Provide the `db_user` and `db_pass` from the previous run's job summary. The
job will fail with:

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
HCP Vault (JWT auth → cicd-demo-ns → demo-db-policy)
  │  VPC peering (HVN ↔ demo VPC)
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
| `infra/aws/` | VPC, EC2 (demo + runner), Cloudflare DNS, HCP peering |
| `infra/vault/` | Namespace, JWT auth, database secrets engine, policy |
| `web/app.py` | Flask UI — reads `secret_log`, serves countdown |
| `.github/workflows/demo-pipeline.yml` | Main 3-job pipeline |
| `.github/workflows/show-expiry.yml` | Manually-triggered expiry proof |
| `docs/customer-brief.md` | Narrative for customer-facing sessions |
