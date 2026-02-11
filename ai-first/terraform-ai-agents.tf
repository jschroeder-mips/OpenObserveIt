# AI Agent Infrastructure - Terraform
## Complete AWS Infrastructure for AI Observability Platform

/**
 * Terraform configuration for deploying AI Agents on AWS
 * 
 * Components:
 * - ECS Fargate tasks for each agent
 * - PostgreSQL RDS for incident storage
 * - ElastiCache Redis for caching
 * - Secrets Manager for API keys
 * - EventBridge for agent orchestration
 * - SQS queues for agent communication
 * 
 * Prerequisites:
 * - Existing LGTM stack (from main terraform-example.tf)
 * - AWS CLI configured
 * - Terraform 1.6+
 */

terraform {
  required_version = ">= 1.6"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  
  backend "s3" {
    bucket = "your-terraform-state-bucket"
    key    = "ai-agents/terraform.tfstate"
    region = "us-east-1"
  }
}

provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Project     = "AI-First-Observability"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

# ============================================================================
# VARIABLES
# ============================================================================

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

variable "vpc_id" {
  description = "VPC ID where LGTM stack is deployed"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for ECS tasks"
  type        = list(string)
}

variable "claude_api_key" {
  description = "Claude API key (sensitive)"
  type        = string
  sensitive   = true
}

variable "slack_webhook_url" {
  description = "Slack webhook URL for notifications"
  type        = string
  sensitive   = true
}

variable "pagerduty_api_key" {
  description = "PagerDuty API key"
  type        = string
  sensitive   = true
}

variable "prometheus_url" {
  description = "Prometheus/Mimir endpoint"
  type        = string
  default     = "http://prometheus.internal:9090"
}

variable "loki_url" {
  description = "Loki endpoint"
  type        = string
  default     = "http://loki.internal:3100"
}

variable "tempo_url" {
  description = "Tempo endpoint"
  type        = string
  default     = "http://tempo.internal:3200"
}

variable "grafana_url" {
  description = "Grafana endpoint"
  type        = string
  default     = "http://grafana.internal:3000"
}

# ============================================================================
# DATA SOURCES
# ============================================================================

data "aws_caller_identity" "current" {}
data "aws_availability_zones" "available" {}

# ============================================================================
# SECRETS MANAGEMENT
# ============================================================================

resource "aws_secretsmanager_secret" "claude_api_key" {
  name        = "${var.environment}-claude-api-key"
  description = "Claude API key for AI agents"
}

resource "aws_secretsmanager_secret_version" "claude_api_key" {
  secret_id     = aws_secretsmanager_secret.claude_api_key.id
  secret_string = var.claude_api_key
}

resource "aws_secretsmanager_secret" "slack_webhook" {
  name        = "${var.environment}-slack-webhook"
  description = "Slack webhook URL"
}

resource "aws_secretsmanager_secret_version" "slack_webhook" {
  secret_id     = aws_secretsmanager_secret.slack_webhook.id
  secret_string = var.slack_webhook_url
}

resource "aws_secretsmanager_secret" "pagerduty_api_key" {
  name        = "${var.environment}-pagerduty-api-key"
  description = "PagerDuty API key"
}

resource "aws_secretsmanager_secret_version" "pagerduty_api_key" {
  secret_id     = aws_secretsmanager_secret.pagerduty_api_key.id
  secret_string = var.pagerduty_api_key
}

resource "aws_secretsmanager_secret" "database_url" {
  name        = "${var.environment}-agent-database-url"
  description = "PostgreSQL connection string for incident storage"
}

resource "aws_secretsmanager_secret_version" "database_url" {
  secret_id = aws_secretsmanager_secret.database_url.id
  secret_string = "postgresql://${aws_db_instance.incidents.username}:${random_password.db_password.result}@${aws_db_instance.incidents.endpoint}/${aws_db_instance.incidents.db_name}"
}

# ============================================================================
# DATABASE (Incident Storage & Memory Layer)
# ============================================================================

resource "random_password" "db_password" {
  length  = 32
  special = true
}

resource "aws_db_subnet_group" "incidents" {
  name       = "${var.environment}-agent-incidents-subnet"
  subnet_ids = var.private_subnet_ids

  tags = {
    Name = "AI Agent Incidents DB Subnet Group"
  }
}

resource "aws_security_group" "rds" {
  name        = "${var.environment}-agent-rds-sg"
  description = "Security group for AI Agent RDS"
  vpc_id      = var.vpc_id

  ingress {
    description     = "PostgreSQL from ECS agents"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.agent_tasks.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "AI Agent RDS Security Group"
  }
}

resource "aws_db_instance" "incidents" {
  identifier     = "${var.environment}-agent-incidents"
  engine         = "postgres"
  engine_version = "15.4"
  
  # Cost-optimized for 50 hosts (can scale later)
  instance_class = "db.t3.medium"  # 2 vCPU, 4 GB RAM
  
  allocated_storage     = 50   # GB
  max_allocated_storage = 200  # Auto-scaling limit
  storage_type          = "gp3"
  storage_encrypted     = true
  
  db_name  = "incidents"
  username = "agent_admin"
  password = random_password.db_password.result
  
  vpc_security_group_ids = [aws_security_group.rds.id]
  db_subnet_group_name   = aws_db_subnet_group.incidents.name
  
  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"
  
  skip_final_snapshot = var.environment != "prod"
  final_snapshot_identifier = var.environment == "prod" ? "${var.environment}-agent-incidents-final-${formatdate("YYYY-MM-DD-hhmm", timestamp())}" : null
  
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  
  tags = {
    Name = "AI Agent Incidents Database"
  }
}

# Database schema initialization (run once)
resource "null_resource" "db_schema" {
  depends_on = [aws_db_instance.incidents]
  
  provisioner "local-exec" {
    command = <<-EOT
      # Wait for DB to be ready
      sleep 30
      
      # Apply schema
      PGPASSWORD="${random_password.db_password.result}" psql -h ${aws_db_instance.incidents.endpoint} -U agent_admin -d incidents -f ../schema/incidents.sql || true
    EOT
  }
}

# ============================================================================
# REDIS (Caching & Rate Limiting)
# ============================================================================

resource "aws_elasticache_subnet_group" "redis" {
  name       = "${var.environment}-agent-redis-subnet"
  subnet_ids = var.private_subnet_ids
}

resource "aws_security_group" "redis" {
  name        = "${var.environment}-agent-redis-sg"
  description = "Security group for AI Agent Redis"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Redis from ECS agents"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.agent_tasks.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "AI Agent Redis Security Group"
  }
}

resource "aws_elasticache_replication_group" "redis" {
  replication_group_id       = "${var.environment}-agent-cache"
  replication_group_description = "Redis cache for AI agents"
  
  engine         = "redis"
  engine_version = "7.0"
  node_type      = "cache.t3.micro"  # 0.5 GB, sufficient for caching
  
  num_cache_clusters = 1  # Single node for cost savings (can add replicas later)
  
  subnet_group_name  = aws_elasticache_subnet_group.redis.name
  security_group_ids = [aws_security_group.redis.id]
  
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  
  snapshot_retention_limit = 5
  snapshot_window          = "03:00-05:00"
  
  tags = {
    Name = "AI Agent Redis Cache"
  }
}

# ============================================================================
# SQS QUEUES (Agent Communication)
# ============================================================================

# Sentinel → Triage queue
resource "aws_sqs_queue" "sentinel_to_triage" {
  name                       = "${var.environment}-sentinel-to-triage"
  visibility_timeout_seconds = 300
  message_retention_seconds  = 86400  # 1 day
  
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.sentinel_to_triage_dlq.arn
    maxReceiveCount     = 3
  })
}

resource "aws_sqs_queue" "sentinel_to_triage_dlq" {
  name = "${var.environment}-sentinel-to-triage-dlq"
}

# Triage → First Responder queue
resource "aws_sqs_queue" "triage_to_responder" {
  name                       = "${var.environment}-triage-to-responder"
  visibility_timeout_seconds = 600  # Longer timeout for remediation
  message_retention_seconds  = 86400
  
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.triage_to_responder_dlq.arn
    maxReceiveCount     = 2  # Fewer retries for safety
  })
}

resource "aws_sqs_queue" "triage_to_responder_dlq" {
  name = "${var.environment}-triage-to-responder-dlq"
}

# Triage → Investigator queue
resource "aws_sqs_queue" "triage_to_investigator" {
  name                       = "${var.environment}-triage-to-investigator"
  visibility_timeout_seconds = 900  # 15 minutes for RCA
  message_retention_seconds  = 604800  # 7 days (not urgent)
  
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.triage_to_investigator_dlq.arn
    maxReceiveCount     = 3
  })
}

resource "aws_sqs_queue" "triage_to_investigator_dlq" {
  name = "${var.environment}-triage-to-investigator-dlq"
}

# ============================================================================
# ECR (Container Registry)
# ============================================================================

resource "aws_ecr_repository" "agents" {
  name                 = "${var.environment}-ai-agents"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

resource "aws_ecr_lifecycle_policy" "agents" {
  repository = aws_ecr_repository.agents.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus     = "any"
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# ============================================================================
# ECS CLUSTER
# ============================================================================

resource "aws_ecs_cluster" "agents" {
  name = "${var.environment}-ai-agents"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_ecs_cluster_capacity_providers" "agents" {
  cluster_name = aws_ecs_cluster.agents.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE_SPOT"
    weight            = 1
  }
}

# Security group for all agent tasks
resource "aws_security_group" "agent_tasks" {
  name        = "${var.environment}-agent-tasks-sg"
  description = "Security group for AI Agent ECS tasks"
  vpc_id      = var.vpc_id

  # Allow outbound to LGTM stack, databases, Redis
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "AI Agent Tasks Security Group"
  }
}

# IAM role for ECS execution (pulling images, logging)
resource "aws_iam_role" "ecs_execution_role" {
  name = "${var.environment}-agent-ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution_role_policy" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Allow reading secrets
resource "aws_iam_role_policy" "ecs_secrets_access" {
  name = "secrets-access"
  role = aws_iam_role.ecs_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          aws_secretsmanager_secret.claude_api_key.arn,
          aws_secretsmanager_secret.slack_webhook.arn,
          aws_secretsmanager_secret.pagerduty_api_key.arn,
          aws_secretsmanager_secret.database_url.arn,
        ]
      }
    ]
  })
}

# ============================================================================
# SENTINEL AGENT
# ============================================================================

# IAM role for Sentinel Agent task
resource "aws_iam_role" "sentinel_task_role" {
  name = "${var.environment}-sentinel-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

# Allow Sentinel to invoke Bedrock (optional, if using Bedrock)
resource "aws_iam_role_policy" "sentinel_bedrock_access" {
  name = "bedrock-access"
  role = aws_iam_role.sentinel_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ]
        Resource = "arn:aws:bedrock:${var.aws_region}::foundation-model/anthropic.claude-*"
      }
    ]
  })
}

# Allow Sentinel to write to SQS
resource "aws_iam_role_policy" "sentinel_sqs_access" {
  name = "sqs-access"
  role = aws_iam_role.sentinel_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:GetQueueUrl"
        ]
        Resource = aws_sqs_queue.sentinel_to_triage.arn
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "sentinel" {
  name              = "/ecs/${var.environment}/sentinel-agent"
  retention_in_days = 30
}

resource "aws_ecs_task_definition" "sentinel" {
  family                   = "${var.environment}-sentinel-agent"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512"   # 0.5 vCPU
  memory                   = "1024"  # 1 GB
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.sentinel_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "sentinel-agent"
      image     = "${aws_ecr_repository.agents.repository_url}:sentinel-latest"
      essential = true
      
      environment = [
        { name = "AWS_REGION", value = var.aws_region },
        { name = "PROMETHEUS_URL", value = var.prometheus_url },
        { name = "LOKI_URL", value = var.loki_url },
        { name = "TEMPO_URL", value = var.tempo_url },
        { name = "GRAFANA_URL", value = var.grafana_url },
        { name = "REDIS_URL", value = "redis://${aws_elasticache_replication_group.redis.primary_endpoint_address}:6379" },
        { name = "SQS_QUEUE_URL", value = aws_sqs_queue.sentinel_to_triage.url },
        { name = "AGENT_NAME", value = "sentinel" },
      ]
      
      secrets = [
        {
          name      = "CLAUDE_API_KEY"
          valueFrom = aws_secretsmanager_secret.claude_api_key.arn
        },
        {
          name      = "DATABASE_URL"
          valueFrom = aws_secretsmanager_secret.database_url.arn
        },
      ]
      
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.sentinel.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
      
      healthCheck = {
        command = ["CMD-SHELL", "python -c 'import requests; requests.get(\"http://localhost:8080/health\")'"]
        interval = 30
        timeout = 5
        retries = 3
      }
    }
  ])
}

resource "aws_ecs_service" "sentinel" {
  name            = "${var.environment}-sentinel-agent"
  cluster         = aws_ecs_cluster.agents.id
  task_definition = aws_ecs_task_definition.sentinel.arn
  desired_count   = 1  # Only need 1 instance
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.agent_tasks.id]
    assign_public_ip = false
  }
  
  # Auto-restart on failure
  deployment_configuration {
    minimum_healthy_percent = 0
    maximum_percent         = 100
  }
}

# CloudWatch alarm for Sentinel health
resource "aws_cloudwatch_metric_alarm" "sentinel_failure" {
  alarm_name          = "${var.environment}-sentinel-agent-failure"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "DesiredTaskCount"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = 0
  alarm_description   = "Sentinel Agent is not running"
  alarm_actions       = []  # TODO: Add SNS topic for alerting
  
  dimensions = {
    ServiceName = aws_ecs_service.sentinel.name
    ClusterName = aws_ecs_cluster.agents.name
  }
}

# ============================================================================
# TRIAGE AGENT
# ============================================================================

# Similar structure for Triage Agent (abbreviated for space)
resource "aws_iam_role" "triage_task_role" {
  name = "${var.environment}-triage-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "triage_sqs_access" {
  name = "sqs-access"
  role = aws_iam_role.triage_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = aws_sqs_queue.sentinel_to_triage.arn
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:GetQueueUrl"
        ]
        Resource = [
          aws_sqs_queue.triage_to_responder.arn,
          aws_sqs_queue.triage_to_investigator.arn
        ]
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "triage" {
  name              = "/ecs/${var.environment}/triage-agent"
  retention_in_days = 30
}

resource "aws_ecs_task_definition" "triage" {
  family                   = "${var.environment}-triage-agent"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.triage_task_role.arn

  container_definitions = jsonencode([{
    name  = "triage-agent"
    image = "${aws_ecr_repository.agents.repository_url}:triage-latest"
    essential = true
    environment = [
      { name = "AWS_REGION", value = var.aws_region },
      { name = "SQS_INPUT_QUEUE_URL", value = aws_sqs_queue.sentinel_to_triage.url },
      { name = "SQS_RESPONDER_QUEUE_URL", value = aws_sqs_queue.triage_to_responder.url },
      { name = "SQS_INVESTIGATOR_QUEUE_URL", value = aws_sqs_queue.triage_to_investigator.url },
      { name = "AGENT_NAME", value = "triage" },
    ]
    secrets = [
      { name = "CLAUDE_API_KEY", valueFrom = aws_secretsmanager_secret.claude_api_key.arn },
      { name = "DATABASE_URL", valueFrom = aws_secretsmanager_secret.database_url.arn },
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group" = aws_cloudwatch_log_group.triage.name
        "awslogs-region" = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}

resource "aws_ecs_service" "triage" {
  name            = "${var.environment}-triage-agent"
  cluster         = aws_ecs_cluster.agents.id
  task_definition = aws_ecs_task_definition.triage.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.agent_tasks.id]
    assign_public_ip = false
  }
}

# ============================================================================
# OUTPUTS
# ============================================================================

output "database_endpoint" {
  description = "RDS endpoint for incident storage"
  value       = aws_db_instance.incidents.endpoint
}

output "redis_endpoint" {
  description = "Redis endpoint for caching"
  value       = aws_elasticache_replication_group.redis.primary_endpoint_address
}

output "ecr_repository_url" {
  description = "ECR repository URL for agent images"
  value       = aws_ecr_repository.agents.repository_url
}

output "sentinel_service_name" {
  description = "ECS service name for Sentinel Agent"
  value       = aws_ecs_service.sentinel.name
}

output "triage_service_name" {
  description = "ECS service name for Triage Agent"
  value       = aws_ecs_service.triage.name
}

output "deployment_commands" {
  description = "Commands to build and deploy agents"
  value = <<-EOT
    # Build and push Sentinel Agent
    docker build -t sentinel-agent -f agents/Dockerfile.sentinel .
    docker tag sentinel-agent:latest ${aws_ecr_repository.agents.repository_url}:sentinel-latest
    aws ecr get-login-password --region ${var.aws_region} | docker login --username AWS --password-stdin ${aws_ecr_repository.agents.repository_url}
    docker push ${aws_ecr_repository.agents.repository_url}:sentinel-latest
    
    # Force new deployment
    aws ecs update-service --cluster ${aws_ecs_cluster.agents.name} --service ${aws_ecs_service.sentinel.name} --force-new-deployment
    
    # View logs
    aws logs tail /ecs/${var.environment}/sentinel-agent --follow
  EOT
}

# ============================================================================
# COST ESTIMATE
# ============================================================================

# Monthly cost breakdown:
# - ECS Fargate (6 agents × 0.5 vCPU × $0.04048/hr × 730 hrs) = $177.31
# - RDS t3.medium (730 hrs × $0.068/hr) = $49.64
# - RDS storage (50 GB × $0.115/GB) = $5.75
# - ElastiCache t3.micro (730 hrs × $0.017/hr) = $12.41
# - SQS (minimal) = $1.00
# - Secrets Manager (5 secrets × $0.40) = $2.00
# - CloudWatch Logs (~10 GB × $0.50) = $5.00
# TOTAL AWS INFRASTRUCTURE: ~$253/month
# 
# Add LLM costs (~$500-1000/month) for total: $750-1250/month for AI layer
