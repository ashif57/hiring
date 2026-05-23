# ──────────────────────────────────────────────────────────────────────────────
# variables.tf — All input variables in one place
# Edit these before running terraform apply
# ──────────────────────────────────────────────────────────────────────────────

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "ap-south-1"
}

variable "key_pair_name" {
  description = "Name of the EC2 key pair to use for SSH access (must already exist in AWS)"
  type        = string
  # No default — you must pass this in:
  # terraform apply -var="key_pair_name=my-key"
}

variable "your_ip" {
  description = "Your public IP in CIDR notation for SSH access to the gateway (e.g. 203.0.113.5/32)"
  type        = string
  # Find your IP: curl ifconfig.me
}

# ── Network ───────────────────────────────────────────────────────────────────

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet (gateway VM lives here)"
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR block for the private subnet (engine + inference VMs live here)"
  type        = string
  default     = "10.0.2.0/24"
}

# ── EC2 ───────────────────────────────────────────────────────────────────────

variable "ami_id" {
  description = "Ubuntu 22.04 LTS AMI ID — find the correct one for your region at https://cloud-images.ubuntu.com/locator/ec2/"
  type        = string
  default     = "ami-0f58b397bc5c1f2e8" # Ubuntu 22.04 LTS — ap-south-1
}

variable "gateway_instance_type" {
  description = "Instance type for vm-gateway (nginx reverse proxy)"
  type        = string
  default     = "t2.micro" # free tier eligible
}

variable "engine_instance_type" {
  description = "Instance type for vm-engine (iii engine + caller-worker)"
  type        = string
  default     = "t2.micro" # free tier eligible
}

variable "inference_instance_type" {
  description = "Instance type for vm-inference (Python worker + 270M model needs ~2GB RAM)"
  type        = string
  default     = "t2.medium" # 4GB RAM — model requires ~2GB
}
