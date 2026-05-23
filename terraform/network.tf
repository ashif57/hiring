# ──────────────────────────────────────────────────────────────────────────────
# network.tf — VPC, Subnets, Internet Gateway, NAT Gateway, Route Tables
#
# Layout:
#   Public subnet  (10.0.1.0/24) → Internet Gateway  → internet
#   Private subnet (10.0.2.0/24) → NAT Gateway        → internet (outbound only)
#
# The private subnet has NO inbound route from the internet.
# VMs in the private subnet can pull packages/images outbound via NAT.
# ──────────────────────────────────────────────────────────────────────────────

# ── VPC ───────────────────────────────────────────────────────────────────────

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "iii-vpc" }
}

# ── Subnets ───────────────────────────────────────────────────────────────────

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true # gateway VM gets a public IP automatically

  tags = { Name = "iii-public-subnet" }
}

resource "aws_subnet" "private" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.private_subnet_cidr
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = false # private VMs never get public IPs

  tags = { Name = "iii-private-subnet" }
}

# ── Internet Gateway (public subnet → internet) ───────────────────────────────

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "iii-igw" }
}

# ── Elastic IP for NAT Gateway ────────────────────────────────────────────────

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = { Name = "iii-nat-eip" }
}

# ── NAT Gateway (private subnet → internet, outbound only) ───────────────────
# Sits in the PUBLIC subnet, uses the Elastic IP above.
# Private VMs route outbound traffic here to reach the internet
# (for docker pull, pip install, apt-get, etc.)

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id # NAT Gateway must live in public subnet

  tags = { Name = "iii-nat-gateway" }

  depends_on = [aws_internet_gateway.igw]
}

# ── Route Table: Public Subnet ────────────────────────────────────────────────
# 0.0.0.0/0 → Internet Gateway (full inbound + outbound internet access)

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = { Name = "iii-public-rt" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# ── Route Table: Private Subnet ───────────────────────────────────────────────
# 0.0.0.0/0 → NAT Gateway (outbound only — no inbound from internet)

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = { Name = "iii-private-rt" }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}
