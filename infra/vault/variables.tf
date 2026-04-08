variable "vault_addr" {
  description = "HCP Vault Dedicated address (e.g. https://vault-cluster.hashicorp.cloud:8200)"
  type        = string
}

variable "vault_namespace" {
  description = "Child namespace to create under admin and deploy all demo resources into"
  type        = string
  default     = "cicd-demo-ns"
}

variable "azure_tenant_id" {
  description = "Azure AD tenant ID — output from infra/azure/"
  type        = string
}

variable "azure_client_id" {
  description = "Azure app registration client ID — output from infra/azure/"
  type        = string
}

variable "postgres_username" {
  description = "PostgreSQL admin username"
  type        = string
  default     = "postgres"
}

variable "postgres_password" {
  description = "PostgreSQL admin password — must match infra/aws var"
  type        = string
  sensitive   = true
}

variable "db_hostname" {
  description = "Hostname Vault uses to reach PostgreSQL"
  type        = string
  default     = "demovm.ricardo.engineer"
}

variable "db_port" {
  description = "PostgreSQL port"
  type        = number
  default     = 5432
}

variable "db_name" {
  description = "PostgreSQL database name"
  type        = string
  default     = "demo_app"
}
