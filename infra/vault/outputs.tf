output "jwt_auth_path" {
  description = "Vault JWT auth mount path"
  value       = vault_jwt_auth_backend.azure_ad.path
}

output "db_role_name" {
  description = "Vault database role name"
  value       = vault_database_secret_backend_role.demo_role.name
}

output "policy_name" {
  description = "Vault policy name attached to the JWT role"
  value       = vault_policy.demo_db.name
}
