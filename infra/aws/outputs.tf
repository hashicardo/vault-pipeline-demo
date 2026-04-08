output "demo_vm_public_ip" {
  description = "Public IP of the demo VM — used for Cloudflare DNS and TLS"
  value       = aws_instance.demo_vm.public_ip
}

output "demo_vm_private_ip" {
  description = "Private IP of the demo VM — used by Vault to reach PostgreSQL over the HVN peering"
  value       = aws_instance.demo_vm.private_ip
}

output "runner_vm_public_ip" {
  description = "Public IP of the GitHub Actions runner VM"
  value       = aws_instance.runner_vm.public_ip
}

output "runner_vm_id" {
  description = "EC2 instance ID of the runner VM"
  value       = aws_instance.runner_vm.id
}
