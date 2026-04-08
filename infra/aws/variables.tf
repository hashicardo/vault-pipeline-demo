variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-2"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "instance_type" {
  description = "EC2 instance type for both VMs"
  type        = string
  default     = "t4g.medium"
}

variable "home_ip" {
  description = "Home IP CIDR (e.g. 1.2.3.4/32) for SSH and HTTPS access"
  type        = string
}

variable "office_ip" {
  description = "Office IP CIDR (e.g. 5.6.7.8/32) for SSH and HTTPS access"
  type        = string
}

variable "ssh_public_key" {
  description = "SSH public key material to install on both VMs"
  type        = string
}

variable "postgres_password" {
  description = "PostgreSQL root password (postgres user)"
  type        = string
  sensitive   = true
}

variable "gh_runner_token" {
  description = "GitHub Actions runner registration token (1h TTL — generate fresh before apply)"
  type        = string
  sensitive   = true
}

variable "demo_vm_hostname" {
  description = "Fully-qualified hostname for the demo VM"
  type        = string
  default     = "demovm.ricardo.engineer"
}

variable "gh_repo" {
  description = "GitHub repository (owner/repo) for runner registration and code clone"
  type        = string
  default     = "hashicardo/vault-pipeline-demo"
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID for ricardo.engineer"
  type        = string
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token with DNS edit permissions (used by Caddy for TLS challenge)"
  type        = string
  sensitive   = true
}
