# Observability Platform - Terraform Starter Template
# This is a simplified example showing the main infrastructure components
# For production, split into modules and use remote state

terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  
  # Recommended: Use S3 backend for state
  # backend "s3" {
  #   bucket         = "my-terraform-state"
  #   key            = "observability/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "terraform-locks"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Project     = "ObservabilityPlatform"
      ManagedBy   = "Terraform"
      Environment = var.environment
    }
  }
}

# =============================================================================
# VARIABLES
# =============================================================================

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "grafana_admin_password" {
  description = "Grafana admin password (store in AWS Secrets Manager)"
  type        = string
  sensitive   = true
}

# =============================================================================
# NETWORKING
# =============================================================================

resource "aws_vpc" "observability" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "observability-vpc"
  }
}

# Public Subnets (for ALB)
resource "aws_subnet" "public" {
  count             = 2
  vpc_id            = aws_vpc.observability.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  map_public_ip_on_launch = true

  tags = {
    Name = "observability-public-${count.index + 1}"
    Tier = "Public"
  }
}

# Private Subnets (for observability components)
resource "aws_subnet" "private_observability" {
  count             = 2
  vpc_id            = aws_vpc.observability.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "observability-private-${count.index + 1}"
    Tier = "Private"
  }
}

# Private Subnets (for monitored hosts)
resource "aws_subnet" "private_monitoring" {
  count             = 2
  vpc_id            = aws_vpc.observability.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 20)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "monitoring-private-${count.index + 1}"
    Tier = "Private"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.observability.id

  tags = {
    Name = "observability-igw"
  }
}

# NAT Gateway (for private subnet internet access)
resource "aws_eip" "nat" {
  count  = 2
  domain = "vpc"

  tags = {
    Name = "observability-nat-eip-${count.index + 1}"
  }
}

resource "aws_nat_gateway" "main" {
  count         = 2
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = {
    Name = "observability-nat-${count.index + 1}"
  }
}

# Route Tables
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.observability.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "observability-public-rt"
  }
}

resource "aws_route_table" "private" {
  count  = 2
  vpc_id = aws_vpc.observability.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }

  tags = {
    Name = "observability-private-rt-${count.index + 1}"
  }
}

# Route Table Associations
resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private_observability" {
  count          = 2
  subnet_id      = aws_subnet.private_observability[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

resource "aws_route_table_association" "private_monitoring" {
  count          = 2
  subnet_id      = aws_subnet.private_monitoring[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# S3 VPC Endpoint (save NAT Gateway costs)
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.observability.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = concat(
    [aws_route_table.public.id],
    aws_route_table.private[*].id
  )

  tags = {
    Name = "observability-s3-endpoint"
  }
}

# =============================================================================
# SECURITY GROUPS
# =============================================================================

# Grafana Security Group
resource "aws_security_group" "grafana" {
  name        = "observability-grafana"
  description = "Security group for Grafana instances"
  vpc_id      = aws_vpc.observability.id

  ingress {
    description     = "HTTP from ALB"
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "observability-grafana-sg"
  }
}

# Prometheus Security Group
resource "aws_security_group" "prometheus" {
  name        = "observability-prometheus"
  description = "Security group for Prometheus instances"
  vpc_id      = aws_vpc.observability.id

  ingress {
    description     = "Prometheus HTTP from Grafana"
    from_port       = 9090
    to_port         = 9090
    protocol        = "tcp"
    security_groups = [aws_security_group.grafana.id]
  }

  ingress {
    description     = "Thanos gRPC from Thanos Query"
    from_port       = 10901
    to_port         = 10901
    protocol        = "tcp"
    security_groups = [aws_security_group.thanos_query.id]
  }

  ingress {
    description = "Remote Write from monitored hosts"
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = aws_subnet.private_monitoring[*].cidr_block
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "observability-prometheus-sg"
  }
}

# Thanos Query Security Group
resource "aws_security_group" "thanos_query" {
  name        = "observability-thanos-query"
  description = "Security group for Thanos Query"
  vpc_id      = aws_vpc.observability.id

  ingress {
    description     = "Thanos Query from Grafana"
    from_port       = 10902
    to_port         = 10902
    protocol        = "tcp"
    security_groups = [aws_security_group.grafana.id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "observability-thanos-query-sg"
  }
}

# Loki Security Group
resource "aws_security_group" "loki" {
  name        = "observability-loki"
  description = "Security group for Loki instances"
  vpc_id      = aws_vpc.observability.id

  ingress {
    description     = "Loki HTTP from Grafana"
    from_port       = 3100
    to_port         = 3100
    protocol        = "tcp"
    security_groups = [aws_security_group.grafana.id]
  }

  ingress {
    description = "Loki HTTP from Promtail (monitored hosts)"
    from_port   = 3100
    to_port     = 3100
    protocol    = "tcp"
    cidr_blocks = aws_subnet.private_monitoring[*].cidr_block
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "observability-loki-sg"
  }
}

# Tempo Security Group
resource "aws_security_group" "tempo" {
  name        = "observability-tempo"
  description = "Security group for Tempo instances"
  vpc_id      = aws_vpc.observability.id

  ingress {
    description     = "Tempo HTTP from Grafana"
    from_port       = 3200
    to_port         = 3200
    protocol        = "tcp"
    security_groups = [aws_security_group.grafana.id]
  }

  ingress {
    description = "OTLP gRPC from monitored hosts"
    from_port   = 4317
    to_port     = 4317
    protocol    = "tcp"
    cidr_blocks = aws_subnet.private_monitoring[*].cidr_block
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "observability-tempo-sg"
  }
}

# ALB Security Group
resource "aws_security_group" "alb" {
  name        = "observability-alb"
  description = "Security group for Application Load Balancer"
  vpc_id      = aws_vpc.observability.id

  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP from internet (redirect to HTTPS)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "observability-alb-sg"
  }
}

# =============================================================================
# S3 BUCKETS
# =============================================================================

# Thanos Metrics Bucket
resource "aws_s3_bucket" "thanos_metrics" {
  bucket = "${var.environment}-observability-thanos-metrics"

  tags = {
    Name      = "Thanos Metrics Storage"
    Component = "Prometheus"
  }
}

resource "aws_s3_bucket_versioning" "thanos_metrics" {
  bucket = aws_s3_bucket.thanos_metrics.id

  versioning_configuration {
    status = "Disabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "thanos_metrics" {
  bucket = aws_s3_bucket.thanos_metrics.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "thanos_metrics" {
  bucket = aws_s3_bucket.thanos_metrics.id

  rule {
    id     = "intelligent-tiering-transition"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "INTELLIGENT_TIERING"
    }
  }

  rule {
    id     = "delete-old-data"
    status = "Enabled"

    expiration {
      days = 730 # 2 years
    }
  }
}

# Loki Logs Bucket
resource "aws_s3_bucket" "loki_logs" {
  bucket = "${var.environment}-observability-loki-logs"

  tags = {
    Name      = "Loki Logs Storage"
    Component = "Loki"
  }
}

resource "aws_s3_bucket_versioning" "loki_logs" {
  bucket = aws_s3_bucket.loki_logs.id

  versioning_configuration {
    status = "Disabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "loki_logs" {
  bucket = aws_s3_bucket.loki_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "loki_logs" {
  bucket = aws_s3_bucket.loki_logs.id

  rule {
    id     = "glacier-transition"
    status = "Enabled"

    transition {
      days          = 90
      storage_class = "GLACIER_IR"
    }
  }

  rule {
    id     = "delete-old-logs"
    status = "Enabled"

    expiration {
      days = 180 # 6 months
    }
  }
}

# Tempo Traces Bucket
resource "aws_s3_bucket" "tempo_traces" {
  bucket = "${var.environment}-observability-tempo-traces"

  tags = {
    Name      = "Tempo Traces Storage"
    Component = "Tempo"
  }
}

resource "aws_s3_bucket_versioning" "tempo_traces" {
  bucket = aws_s3_bucket.tempo_traces.id

  versioning_configuration {
    status = "Disabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tempo_traces" {
  bucket = aws_s3_bucket.tempo_traces.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "tempo_traces" {
  bucket = aws_s3_bucket.tempo_traces.id

  rule {
    id     = "delete-old-traces"
    status = "Enabled"

    expiration {
      days = 30
    }
  }
}

# =============================================================================
# IAM ROLES
# =============================================================================

# IAM Role for Observability Components
resource "aws_iam_role" "observability_instance" {
  name = "${var.environment}-observability-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "observability-instance-role"
  }
}

# IAM Policy for S3 Access
resource "aws_iam_role_policy" "observability_s3" {
  name = "observability-s3-access"
  role = aws_iam_role.observability_instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.thanos_metrics.arn,
          "${aws_s3_bucket.thanos_metrics.arn}/*",
          aws_s3_bucket.loki_logs.arn,
          "${aws_s3_bucket.loki_logs.arn}/*",
          aws_s3_bucket.tempo_traces.arn,
          "${aws_s3_bucket.tempo_traces.arn}/*"
        ]
      }
    ]
  })
}

# IAM Instance Profile
resource "aws_iam_instance_profile" "observability" {
  name = "${var.environment}-observability-instance-profile"
  role = aws_iam_role.observability_instance.name
}

# =============================================================================
# RDS (Grafana Backend Database)
# =============================================================================

resource "aws_db_subnet_group" "grafana" {
  name       = "${var.environment}-grafana-db-subnet"
  subnet_ids = aws_subnet.private_observability[*].id

  tags = {
    Name = "grafana-db-subnet-group"
  }
}

resource "aws_security_group" "rds" {
  name        = "observability-rds"
  description = "Security group for RDS PostgreSQL"
  vpc_id      = aws_vpc.observability.id

  ingress {
    description     = "PostgreSQL from Grafana"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.grafana.id]
  }

  tags = {
    Name = "observability-rds-sg"
  }
}

resource "aws_db_instance" "grafana" {
  identifier             = "${var.environment}-grafana-db"
  engine                 = "postgres"
  engine_version         = "15.5"
  instance_class         = "db.t3.small"
  allocated_storage      = 20
  storage_type           = "gp3"
  storage_encrypted      = true
  
  db_name  = "grafana"
  username = "grafana"
  password = var.grafana_admin_password # In production, use AWS Secrets Manager
  
  multi_az               = true
  db_subnet_group_name   = aws_db_subnet_group.grafana.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  
  backup_retention_period = 7
  backup_window          = "03:00-04:00"
  maintenance_window     = "mon:04:00-mon:05:00"
  
  skip_final_snapshot = false
  final_snapshot_identifier = "${var.environment}-grafana-db-final-snapshot"
  
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  tags = {
    Name = "grafana-database"
  }
}

# =============================================================================
# APPLICATION LOAD BALANCER (Grafana)
# =============================================================================

resource "aws_lb" "grafana" {
  name               = "${var.environment}-grafana-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  enable_deletion_protection = false # Set to true in production

  tags = {
    Name = "grafana-alb"
  }
}

resource "aws_lb_target_group" "grafana" {
  name     = "${var.environment}-grafana-tg"
  port     = 3000
  protocol = "HTTP"
  vpc_id   = aws_vpc.observability.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    path                = "/api/health"
    matcher             = "200"
  }

  stickiness {
    type            = "lb_cookie"
    cookie_duration = 86400 # 24 hours
    enabled         = true
  }

  tags = {
    Name = "grafana-target-group"
  }
}

# HTTP listener (redirect to HTTPS)
resource "aws_lb_listener" "grafana_http" {
  load_balancer_arn = aws_lb.grafana.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# HTTPS listener (requires ACM certificate)
# Uncomment and configure when you have a certificate
# resource "aws_lb_listener" "grafana_https" {
#   load_balancer_arn = aws_lb.grafana.arn
#   port              = "443"
#   protocol          = "HTTPS"
#   ssl_policy        = "ELBSecurityPolicy-TLS-1-2-2017-01"
#   certificate_arn   = aws_acm_certificate.grafana.arn
#
#   default_action {
#     type             = "forward"
#     target_group_arn = aws_lb_target_group.grafana.arn
#   }
# }

# =============================================================================
# DATA SOURCES
# =============================================================================

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# =============================================================================
# OUTPUTS
# =============================================================================

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.observability.id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = aws_subnet.public[*].id
}

output "private_observability_subnet_ids" {
  description = "Private observability subnet IDs"
  value       = aws_subnet.private_observability[*].id
}

output "private_monitoring_subnet_ids" {
  description = "Private monitoring subnet IDs"
  value       = aws_subnet.private_monitoring[*].id
}

output "s3_thanos_bucket" {
  description = "Thanos S3 bucket name"
  value       = aws_s3_bucket.thanos_metrics.id
}

output "s3_loki_bucket" {
  description = "Loki S3 bucket name"
  value       = aws_s3_bucket.loki_logs.id
}

output "s3_tempo_bucket" {
  description = "Tempo S3 bucket name"
  value       = aws_s3_bucket.tempo_traces.id
}

output "grafana_alb_dns" {
  description = "Grafana ALB DNS name"
  value       = aws_lb.grafana.dns_name
}

output "grafana_db_endpoint" {
  description = "Grafana RDS endpoint"
  value       = aws_db_instance.grafana.endpoint
}

output "iam_instance_profile" {
  description = "IAM instance profile for EC2 instances"
  value       = aws_iam_instance_profile.observability.name
}

# =============================================================================
# NOTES
# =============================================================================

# This Terraform configuration provides:
# 1. VPC with public and private subnets across 2 AZs
# 2. S3 buckets with lifecycle policies for metrics, logs, traces
# 3. Security groups for all components
# 4. RDS PostgreSQL for Grafana
# 5. Application Load Balancer for Grafana UI
# 6. IAM roles for EC2 instances to access S3
#
# Next steps:
# 1. Create EC2 launch templates for each component (Prometheus, Loki, etc.)
# 2. Create Auto Scaling Groups for high availability
# 3. Configure ACM certificate for HTTPS
# 4. Create Route 53 records
# 5. Deploy application configuration via user_data or Configuration Management
#
# Example: Deploy Grafana EC2 instance
# resource "aws_instance" "grafana" {
#   count                  = 2
#   ami                    = data.aws_ami.amazon_linux_2023.id
#   instance_type          = "t3.medium"
#   subnet_id              = aws_subnet.private_observability[count.index].id
#   vpc_security_group_ids = [aws_security_group.grafana.id]
#   iam_instance_profile   = aws_iam_instance_profile.observability.name
#   
#   user_data = templatefile("${path.module}/user_data/grafana.sh", {
#     db_endpoint = aws_db_instance.grafana.endpoint
#     db_name     = aws_db_instance.grafana.db_name
#     db_user     = aws_db_instance.grafana.username
#   })
#   
#   tags = {
#     Name = "grafana-${count.index + 1}"
#   }
# }
