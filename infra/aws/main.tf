terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
    hcp = {
      source  = "hashicorp/hcp"
      version = "~> 0.111"
    }
  }
  required_version = ">= 1.11"
}

provider "aws" {
  region = var.aws_region
}

provider "cloudflare" {
  # Authenticates via CLOUDFLARE_API_TOKEN environment variable
}

provider "hcp" {
  project_id = var.hcp_project_id
  # Authenticates via HCP_CLIENT_ID and HCP_CLIENT_SECRET environment variables
}

# ── Account identity (used for HCP peering) ───────────────────────────────────

data "aws_caller_identity" "current" {}

# ── AMI ────────────────────────────────────────────────────────────────────────
# (approved by security)
data "aws_ami" "hc_base_ubuntu_2404" {
  for_each = toset(["amd64", "arm64"])

  filter {
    name   = "name"
    values = [format("hc-base-ubuntu-2404-%s-*", each.value)]
  }
  most_recent = true
  owners      = ["888995627335"] # hc1-ami_prod
}

# Security-maintained managed IAM Policy necessary for doormat session
data "aws_iam_policy" "security_compute_access" {
  name = "SecurityComputeAccess"
}

# ── VPC ────────────────────────────────────────────────────────────────────────

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Name = "vault-demo-vpc" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "vault-demo-igw" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.subnet_cidr
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = { Name = "vault-demo-public-subnet" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "vault-demo-public-rt" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# ── Security Groups ────────────────────────────────────────────────────────────
# Rules are managed via aws_vpc_security_group_ingress_rule /
# aws_vpc_security_group_egress_rule — do not add inline ingress/egress blocks.

# runner-vm-sg is declared first — demo-vm-sg references it for PG ingress
resource "aws_security_group" "runner_vm" {
  name        = "runner-vm-sg"
  description = "GitHub Actions self-hosted runner"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "runner-vm-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "runner_vm_ssh_home" {
  security_group_id = aws_security_group.runner_vm.id
  description       = "SSH from home"
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = var.home_ip
}

resource "aws_vpc_security_group_ingress_rule" "runner_vm_ssh_office" {
  security_group_id = aws_security_group.runner_vm.id
  description       = "SSH from office"
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = var.office_ip
}

resource "aws_vpc_security_group_egress_rule" "runner_vm_all" {
  security_group_id = aws_security_group.runner_vm.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_security_group" "demo_vm" {
  name        = "demo-vm-sg"
  description = "Demo VM web UI PostgreSQL SSH"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "demo-vm-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "demo_vm_https_home" {
  security_group_id = aws_security_group.demo_vm.id
  description       = "HTTPS web UI from home"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = var.home_ip
}

resource "aws_vpc_security_group_ingress_rule" "demo_vm_https_office" {
  security_group_id = aws_security_group.demo_vm.id
  description       = "HTTPS web UI from office"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = var.office_ip
}

resource "aws_vpc_security_group_ingress_rule" "demo_vm_postgres_runner" {
  security_group_id            = aws_security_group.demo_vm.id
  description                  = "PostgreSQL from runner VM only"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.runner_vm.id
}

resource "aws_vpc_security_group_ingress_rule" "demo_vm_ssh_home" {
  security_group_id = aws_security_group.demo_vm.id
  description       = "SSH from home"
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = var.home_ip
}

resource "aws_vpc_security_group_ingress_rule" "demo_vm_ssh_office" {
  security_group_id = aws_security_group.demo_vm.id
  description       = "SSH from office"
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = var.office_ip
}

resource "aws_vpc_security_group_egress_rule" "demo_vm_all" {
  security_group_id = aws_security_group.demo_vm.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# ── SSH Key ────────────────────────────────────────────────────────────────────

resource "aws_key_pair" "demo" {
  key_name   = "vault-demo-key"
  public_key = var.ssh_public_key
}

# ── EC2 Instances ──────────────────────────────────────────────────────────────

resource "aws_instance" "demo_vm" {
  ami                    = data.aws_ami.hc_base_ubuntu_2404["arm64"].id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.demo_vm.id]
  key_name               = aws_key_pair.demo.key_name

  user_data = templatefile("${path.module}/user_data/demo_vm.sh", {
    postgres_password    = var.postgres_password
    domain_name          = var.demo_vm_hostname
    cloudflare_api_token = var.cloudflare_api_token
    gh_repo              = var.gh_repo
  })

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = { Name = "vault-demo-vm" }
}

resource "aws_instance" "runner_vm" {
  ami                    = data.aws_ami.hc_base_ubuntu_2404["arm64"].id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.runner_vm.id]
  key_name               = aws_key_pair.demo.key_name

  user_data = templatefile("${path.module}/user_data/runner_vm.sh", {
    gh_runner_token = var.gh_runner_token
    gh_repo         = var.gh_repo
  })

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = { Name = "vault-runner-vm" }
}

# ── Cloudflare DNS ─────────────────────────────────────────────────────────────

resource "cloudflare_dns_record" "demo_vm" {
  zone_id = var.cloudflare_zone_id
  name    = "demovm"
  content = aws_instance.demo_vm.public_ip
  type    = "A"
  ttl     = 1     # 1 = automatic (Cloudflare-managed TTL)
  proxied = false # TLS is handled by Caddy on the VM
}

# ── HCP Vault → VPC peering ────────────────────────────────────────────────────
# Allows HCP Vault Dedicated (running in an HVN) to reach PostgreSQL on demo-vm.

data "hcp_hvn" "main" {
  hvn_id = var.hvn_id
}

resource "hcp_aws_network_peering" "vault_to_demo" {
  hvn_id          = data.hcp_hvn.main.hvn_id
  peering_id      = "vault-demo-peering"
  peer_vpc_id     = aws_vpc.main.id
  peer_account_id = data.aws_caller_identity.current.account_id
  peer_vpc_region = var.aws_region
}

# Route inside the HVN: traffic to the demo VPC CIDR goes via the peering
resource "hcp_hvn_route" "vault_to_demo" {
  hvn_link         = data.hcp_hvn.main.self_link
  hvn_route_id     = "vault-to-demo-vpc"
  destination_cidr = var.vpc_cidr
  target_link      = hcp_aws_network_peering.vault_to_demo.self_link
}

# Accept the peering request on the AWS side
resource "aws_vpc_peering_connection_accepter" "vault_to_demo" {
  vpc_peering_connection_id = hcp_aws_network_peering.vault_to_demo.provider_peering_id
  auto_accept               = true

  tags = { Name = "vault-hvn-to-demo-vpc" }
}

# Route in the VPC: traffic to the HVN CIDR goes via the peering connection
resource "aws_route" "hvn_to_demo_vpc" {
  route_table_id            = aws_route_table.public.id
  destination_cidr_block    = data.hcp_hvn.main.cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection_accepter.vault_to_demo.id
}

# Allow Vault (HVN) to reach PostgreSQL on the demo VM
resource "aws_vpc_security_group_ingress_rule" "demo_vm_postgres_hvn" {
  security_group_id = aws_security_group.demo_vm.id
  description       = "PostgreSQL from HCP Vault HVN"
  ip_protocol       = "tcp"
  from_port         = 5432
  to_port           = 5432
  cidr_ipv4         = data.hcp_hvn.main.cidr_block
}
