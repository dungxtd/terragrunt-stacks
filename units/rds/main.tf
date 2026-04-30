locals {
  use_managed_password = var.master_password_override == ""
}

module "rds" {
  source  = "terraform-aws-modules/rds/aws"
  version = "~> 7.2"

  identifier = "${var.project}-payments"

  engine               = "postgres"
  engine_version       = "15"
  family               = "postgres15"
  major_engine_version = "15"
  instance_class       = var.instance_class

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage

  db_name  = "payments"
  username = "postgres"
  port     = 5432

  # v7 module dropped the `password` arg — secrets are always managed via
  # Secrets Manager. Override path (ministack) carries the password through
  # aws_secretsmanager_secret.master_override (see secrets_ministack.tf), and
  # vault-config reads from the override-mirror ARN instead of this module's.
  manage_master_user_password = true

  multi_az               = var.multi_az
  db_subnet_group_name   = var.database_subnet_group_name
  vpc_security_group_ids = [aws_security_group.rds.id]

  backup_retention_period = var.backup_retention_period
  deletion_protection     = var.deletion_protection
  skip_final_snapshot     = var.skip_final_snapshot

  performance_insights_enabled = var.performance_insights
  monitoring_interval          = var.monitoring_interval
  create_monitoring_role       = var.create_monitoring_role
  monitoring_role_name         = "${var.project}-rds-monitoring"

  parameters = [
    {
      name  = "log_connections"
      value = "1"
    }
  ]

  tags = var.tags
}

resource "aws_security_group" "rds" {
  name_prefix = "${var.project}-rds-"
  description = "RDS PostgreSQL security group"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr_block]
    description = "PostgreSQL from VPC"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr_block]
    description = "Outbound within VPC only"
  }

  tags = merge(var.tags, { Name = "${var.project}-rds-sg" })
}
