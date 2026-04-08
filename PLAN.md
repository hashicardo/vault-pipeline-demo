# Execution Plan

## Phase 1 — Azure (infra/azure/)
Scaffold first; outputs feed every other module.
- `azuread_application` + `azuread_service_principal`
- `azuread_application_federated_identity_credential` (GitHub OIDC trust)
- Outputs: `azure_tenant_id`, `azure_client_id`

## Phase 2 — AWS (infra/aws/)
- VPC, single public subnet, IGW, route table
- Two `aws_instance` (t3.small, Ubuntu 22.04): `demo-vm`, `runner-vm`
- Two security groups per spec (SG-to-SG reference for PG port)
- `user_data/demo_vm.sh`: Caddy + Docker Compose (postgres:16 + Flask web server)
- `user_data/runner_vm.sh`: GitHub Actions self-hosted runner (systemd)
- Cloudflare provider: A record `demovm.ricardo.engineer` → `demo_vm_public_ip`, `proxied = false`
- Outputs: `demo_vm_public_ip`, `runner_vm_public_ip`, `runner_vm_id`

## Phase 3 — Vault (infra/vault/)
Depends on Azure outputs (tenant/client ID) and DB reachable at demovm.ricardo.engineer:5432.
- `vault_jwt_auth_backend` (path = "jwt", Azure AD OIDC discovery URL)
- `vault_jwt_auth_backend_role` (bound_claims: repo + environment, TTL 300s)
- `vault_database_secret_backend_connection` (postgres plugin, connection URL, allowed_roles)
- `vault_database_secret_backend_role` (CREATE/REVOKE statements, TTL 300/600s)
- `vault_policy` ("demo-db-policy": read database/creds/demo-role + secret/data/demo/*)

## Phase 4 — Web Server (web/)
- `app.py`: Flask, reads `secret_log` via admin PG creds, injects `expires_at` into template
- `templates/index.html`: countdown timer in JS (updates every second, red EXPIRED state)
- `Dockerfile`: python:3.12-slim, flask + psycopg2-binary

## Phase 5 — GitHub Actions (.github/workflows/)
- `demo-pipeline.yml`: jobs `auth` → `fetch-secret` → `use-secret` → `show-expiry`
  - `show-expiry` is a separate manually-triggered workflow; its failure is intentional

## Phase 6 — Validation & Packaging
- `terraform validate && terraform fmt -check` in each module directory
- `README.md` generated using the 5-point demo narrative from CLAUDE.md

---

## Apply Order
```
infra/azure/  →  infra/aws/  →  infra/vault/
```
Destroy in reverse.

## Key Constraints (never violate)
- No hardcoded IPs, passwords, or tokens in `.tf` files
- All shell scripts: `set -euo pipefail`, idempotent
- HCP Vault already exists — only configure via provider, never provision
- `show-expiry` job failure is the demo; do not fix it
- Cloudflare DNS: `proxied = false` (Caddy handles TLS)
- Web server uses admin DB creds (not dynamic); do not replace
