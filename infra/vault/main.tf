terraform {
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.11"
}

# Provider connects to the parent namespace (admin) where the Vault token lives.
# The demo namespace is created as a child and all resources live inside it.
provider "vault" {
  address   = var.vault_addr
  namespace = "admin"
  # Authenticates via VAULT_TOKEN environment variable
}

# ── Namespace ──────────────────────────────────────────────────────────────────

resource "vault_namespace" "demo" {
  path = var.vault_namespace
}

# ── Database secrets engine ────────────────────────────────────────────────────

resource "vault_mount" "database" {
  namespace = vault_namespace.demo.path_fq
  path      = "database"
  type      = "database"
}

resource "vault_database_secret_backend_connection" "postgres" {
  namespace     = vault_namespace.demo.path_fq
  backend       = vault_mount.database.path
  name          = "postgres"
  plugin_name   = "postgresql-database-plugin"
  allowed_roles = ["demo-role"]

  postgresql {
    connection_url = "postgresql://{{username}}:{{password}}@${var.db_hostname}:${var.db_port}/${var.db_name}"
    username       = var.postgres_username
    password       = var.postgres_password
  }
}

resource "vault_database_secret_backend_role" "demo_role" {
  namespace = vault_namespace.demo.path_fq
  backend   = vault_mount.database.path
  name      = "demo-role"
  db_name   = vault_database_secret_backend_connection.postgres.name

  default_ttl = 300
  max_ttl     = 600

  creation_statements = [
    "CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}';",
    "GRANT SELECT, INSERT ON secret_log TO \"{{name}}\";"
  ]

  revocation_statements = [
    "REVOKE ALL ON secret_log FROM \"{{name}}\";",
    "DROP ROLE IF EXISTS \"{{name}}\";"
  ]
}

# ── JWT auth backend (Azure AD as OIDC provider) ───────────────────────────────

resource "vault_jwt_auth_backend" "azure_ad" {
  namespace          = vault_namespace.demo.path_fq
  path               = "jwt"
  oidc_discovery_url = "https://login.microsoftonline.com/${var.azure_tenant_id}/v2.0"
  bound_issuer       = "https://login.microsoftonline.com/${var.azure_tenant_id}/v2.0"
}

resource "vault_jwt_auth_backend_role" "github_actions" {
  namespace = vault_namespace.demo.path_fq
  backend   = vault_jwt_auth_backend.azure_ad.path
  role_name = "github-actions-demo"
  role_type = "jwt"

  bound_audiences = ["api://${var.azure_client_id}"]

  bound_claims = {
    repository  = "hashicardo/vault-pipeline-demo"
    environment = "demo"
  }

  user_claim     = "sub"
  token_policies = ["demo-db-policy"]
  token_ttl      = 300
}

# ── Policy ─────────────────────────────────────────────────────────────────────

resource "vault_policy" "demo_db" {
  namespace = vault_namespace.demo.path_fq
  name      = "demo-db-policy"

  policy = <<-EOT
    path "database/creds/demo-role" {
      capabilities = ["read"]
    }

    path "secret/data/demo/*" {
      capabilities = ["read"]
    }
  EOT
}
