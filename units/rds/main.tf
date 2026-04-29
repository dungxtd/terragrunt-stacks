module "rds" {
  source  = "terraform-aws-modules/rds/aws"
  version = "~> 6.0"

  identifier = "${var.project}-payments"

  engine               = "postgres"
  engine_version       = "15"
  family               = "postgres15"
  major_engine_version = "15"
  instance_class       = var.instance_class

  allocated_storage     = 20
  max_allocated_storage = 100

  db_name  = "payments"
  username = "postgres"
  port     = 5432

  manage_master_user_password = true

  multi_az               = var.multi_az
  db_subnet_group_name   = var.database_subnet_group_name
  vpc_security_group_ids = [aws_security_group.rds.id]

  backup_retention_period = 7
  deletion_protection     = var.deletion_protection
  skip_final_snapshot     = true

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
