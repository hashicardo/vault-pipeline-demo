output "azure_tenant_id" {
  description = "Azure AD tenant ID — pass to infra/vault as var.azure_tenant_id"
  value       = data.azuread_client_config.current.tenant_id
}

output "azure_client_id" {
  description = "App registration client ID — pass to infra/vault as var.azure_client_id"
  value       = azuread_application.vault_demo.client_id
}

output "debug_client_secret" {
  description = "Client secret for manual debugging — use with az login --service-principal"
  value       = azuread_application_password.debug.value
  sensitive   = true
}
