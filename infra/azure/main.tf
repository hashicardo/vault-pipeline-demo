terraform {
  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
  }
  required_version = ">= 1.11"
}

provider "azuread" {}

data "azuread_client_config" "current" {}

resource "azuread_application" "vault_demo" {
  display_name = "vault-pipeline-demo"
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
