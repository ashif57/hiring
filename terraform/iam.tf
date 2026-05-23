# ──────────────────────────────────────────────────────────────────────────────
# iam.tf — IAM role and instance profile for EC2 → ECR access
#
# vm-engine and vm-inference need to pull Docker images from ECR.
# This role grants them read-only ECR access without hardcoding credentials.
# ──────────────────────────────────────────────────────────────────────────────

# IAM role that EC2 instances can assume
resource "aws_iam_role" "ecr_pull" {
  name = "iii-ecr-pull-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "iii-ecr-pull-role" }
}

# Attach AWS managed policy for read-only ECR access
resource "aws_iam_role_policy_attachment" "ecr_pull" {
  role       = aws_iam_role.ecr_pull.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# Instance profile — wraps the role so EC2 can use it
resource "aws_iam_instance_profile" "ecr_pull" {
  name = "iii-ecr-pull-profile"
  role = aws_iam_role.ecr_pull.name
}
