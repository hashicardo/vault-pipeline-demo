terraform {
  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
  required_version = ">= 1.11"
}

provider "azuread" {}

data "azuread_client_config" "current" {}

resource "random_uuid" "vault_auth_scope_id" {}

resource "azuread_application" "vault_demo" {
  display_name = "vault-pipeline-demo"

  api {
    requested_access_token_version = 2

    oauth2_permission_scope {
      admin_consent_description  = "Allows Vault to validate this application's tokens"
      admin_consent_display_name = "Vault Token Validation"
      enabled                    = true
      id                         = random_uuid.vault_auth_scope_id.result
      type                       = "Admin"
      value                      = "vault.auth"
    }
  }
}

resource "azuread_application_identifier_uri" "vault_demo" {
  application_id = azuread_application.vault_demo.id
  identifier_uri = "api://${azuread_application.vault_demo.client_id}"
}

resource "azuread_service_principal" "vault_demo" {
  client_id = azuread_application.vault_demo.client_id
}

resource "azuread_application_federated_identity_credential" "github_actions" {
  application_id = azuread_application.vault_demo.id
  display_name   = "github-actions-pipeline-demo"
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:hashicardo/vault-pipeline-demo:environment:demo"
  audiences      = ["api://AzureADTokenExchange"]
}
