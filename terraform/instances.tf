# ──────────────────────────────────────────────────────────────────────────────
# instances.tf — EC2 instances for each VM
#
# vm-gateway   → public subnet,  nginx reverse proxy
# vm-engine    → private subnet, iii engine + caller-worker
# vm-inference → private subnet, inference-worker (Python + model)
#
# All VMs use the same Ubuntu 22.04 base AMI.
# user_data scripts install Docker and pull the correct container on first boot.
# ──────────────────────────────────────────────────────────────────────────────

locals {
  # Shared Docker + AWS CLI install script — runs on every VM at first boot
  docker_install = <<-EOF
    #!/bin/bash
    set -e
    apt-get update -y
    apt-get install -y ca-certificates curl gnupg awscli

    # Install Docker
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
      gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
      https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io
    systemctl enable docker
    systemctl start docker
  EOF
}

# ── vm-gateway ────────────────────────────────────────────────────────────────

resource "aws_instance" "gateway" {
  ami                         = var.ami_id
  instance_type               = var.gateway_instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.gateway.id]
  key_name                    = var.key_pair_name
  associate_public_ip_address = true

  root_block_device {
    volume_size = 10 # GB — nginx needs very little disk
    volume_type = "gp3"
  }

  user_data = base64encode(local.docker_install)

  tags = { Name = "vm-gateway" }
}

# Elastic IP — gives vm-gateway a stable public IP that doesn't change on reboot
resource "aws_eip" "gateway" {
  instance = aws_instance.gateway.id
  domain   = "vpc"

  tags = { Name = "iii-gateway-eip" }
}

# ── vm-engine ─────────────────────────────────────────────────────────────────

resource "aws_instance" "engine" {
  ami                         = var.ami_id
  instance_type               = var.engine_instance_type
  subnet_id                   = aws_subnet.private.id
  vpc_security_group_ids      = [aws_security_group.engine.id]
  key_name                    = var.key_pair_name
  associate_public_ip_address = false # private subnet — no public IP

  root_block_device {
    volume_size = 20 # GB — enough for Docker images + state store
    volume_type = "gp3"
  }

  # IAM instance profile needed to pull images from ECR
  iam_instance_profile = aws_iam_instance_profile.ecr_pull.name

  user_data = base64encode(local.docker_install)

  tags = { Name = "vm-engine" }
}

# ── vm-inference ──────────────────────────────────────────────────────────────

resource "aws_instance" "inference" {
  ami                         = var.ami_id
  instance_type               = var.inference_instance_type
  subnet_id                   = aws_subnet.private.id
  vpc_security_group_ids      = [aws_security_group.inference.id]
  key_name                    = var.key_pair_name
  associate_public_ip_address = false # private subnet — no public IP

  root_block_device {
    volume_size = 30 # GB — inference image is ~1.5GB (model baked in)
    volume_type = "gp3"
  }

  # IAM instance profile needed to pull images from ECR
  iam_instance_profile = aws_iam_instance_profile.ecr_pull.name

  user_data = base64encode(local.docker_install)

  tags = { Name = "vm-inference" }
}
