# ──────────────────────────────────────────────────────────────────────────────
# security_groups.tf — Firewall rules for each VM
#
# sg-gateway   → public-facing nginx (port 80 open to internet)
# sg-engine    → iii engine (ports 3111 + 49134 open to private subnet only)
# sg-inference → inference worker (no inbound needed — outbound only)
# ──────────────────────────────────────────────────────────────────────────────

# ── sg-gateway ────────────────────────────────────────────────────────────────
# Attached to: vm-gateway (public subnet)

resource "aws_security_group" "gateway" {
  name        = "sg-gateway"
  description = "Public-facing nginx reverse proxy"
  vpc_id      = aws_vpc.main.id

  # HTTP from internet
  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS from internet (optional — add TLS cert to nginx to enable)
  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SSH from your IP only — never open SSH to 0.0.0.0/0
  ingress {
    description = "SSH from admin IP only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.your_ip]
  }

  # Allow all outbound (needed to proxy requests to vm-engine)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "sg-gateway" }
}

# ── sg-engine ─────────────────────────────────────────────────────────────────
# Attached to: vm-engine (private subnet)

resource "aws_security_group" "engine" {
  name        = "sg-engine"
  description = "iii engine — HTTP API and WebSocket broker"
  vpc_id      = aws_vpc.main.id

  # HTTP API (:3111) — only from gateway VM
  ingress {
    description     = "iii HTTP API from gateway only"
    from_port       = 3111
    to_port         = 3111
    protocol        = "tcp"
    security_groups = [aws_security_group.gateway.id]
  }

  # WebSocket broker (:49134) — only from within private subnet
  # (inference-worker on vm-inference connects here)
  ingress {
    description = "iii WebSocket broker from private subnet"
    from_port   = 49134
    to_port     = 49134
    protocol    = "tcp"
    cidr_blocks = [var.private_subnet_cidr]
  }

  # SSH — only via gateway (use gateway as jump host)
  ingress {
    description     = "SSH via gateway jump host"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.gateway.id]
  }

  # Allow all outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "sg-engine" }
}

# ── sg-inference ──────────────────────────────────────────────────────────────
# Attached to: vm-inference (private subnet)
# The inference worker connects OUTBOUND to vm-engine:49134.
# No inbound ports needed at all (except SSH for admin).

resource "aws_security_group" "inference" {
  name        = "sg-inference"
  description = "Inference worker — outbound only, no public inbound"
  vpc_id      = aws_vpc.main.id

  # SSH — only via gateway (use gateway as jump host)
  ingress {
    description     = "SSH via gateway jump host"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.gateway.id]
  }

  # Allow all outbound (needs to reach vm-engine:49134 and NAT for docker pull)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "sg-inference" }
}
