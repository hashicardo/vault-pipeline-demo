output "azure_tenant_id" {
  description = "Azure AD tenant ID — pass to infra/vault as var.azure_tenant_id"
  value       = data.azuread_client_config.current.tenant_id
}

output "azure_client_id" {
  description = "App registration client ID — pass to infra/vault as var.azure_client_id"
  value       = azuread_application.vault_demo.client_id
}
