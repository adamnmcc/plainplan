# -------------------------------------------------------------------
# RDS PostgreSQL free-tier instance (db.t4g.micro)
# Public endpoint — Lambda connects over the internet via DATABASE_URL.
# -------------------------------------------------------------------

locals {
  rds_enabled = !var.enable_aurora_serverless
}

data "aws_vpc" "rds_default" {
  count   = local.rds_enabled ? 1 : 0
  default = true
}

data "aws_subnets" "rds_default" {
  count = local.rds_enabled ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.rds_default[0].id]
  }

  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

resource "random_password" "rds_master" {
  count   = local.rds_enabled ? 1 : 0
  length  = 24
  special = false
}

resource "aws_secretsmanager_secret" "rds_master" {
  count = local.rds_enabled ? 1 : 0

  name = "${local.name_prefix}-rds-master"
  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "rds_master" {
  count = local.rds_enabled ? 1 : 0

  secret_id = aws_secretsmanager_secret.rds_master[0].id
  secret_string = jsonencode({
    username = var.rds_master_username
    password = random_password.rds_master[0].result
  })
}

resource "aws_security_group" "rds" {
  count = local.rds_enabled ? 1 : 0

  name        = "${local.name_prefix}-rds-sg"
  description = "RDS PostgreSQL - public access restricted by password + SSL"
  vpc_id      = data.aws_vpc.rds_default[0].id

  ingress {
    description = "PostgreSQL from anywhere (password + SSL required)"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.common_tags
}

resource "aws_db_subnet_group" "rds" {
  count = local.rds_enabled ? 1 : 0

  name       = "${local.name_prefix}-rds-subnets"
  subnet_ids = data.aws_subnets.rds_default[0].ids

  tags = local.common_tags
}

resource "aws_db_instance" "postgres" {
  count = local.rds_enabled ? 1 : 0

  identifier     = "${local.name_prefix}-pg"
  engine         = "postgres"
  engine_version = var.rds_engine_version
  instance_class = "db.t4g.micro"

  allocated_storage     = 20
  max_allocated_storage = 20
  storage_type          = "gp2"
  storage_encrypted     = true

  db_name  = var.rds_database_name
  username = var.rds_master_username
  password = random_password.rds_master[0].result

  db_subnet_group_name   = aws_db_subnet_group.rds[0].name
  vpc_security_group_ids = [aws_security_group.rds[0].id]
  publicly_accessible    = true

  backup_retention_period = 1
  deletion_protection     = false
  skip_final_snapshot     = true
  apply_immediately       = true
  copy_tags_to_snapshot   = true

  tags = local.common_tags
}

locals {
  rds_database_url = local.rds_enabled ? "postgresql://${var.rds_master_username}:${random_password.rds_master[0].result}@${aws_db_instance.postgres[0].endpoint}/${var.rds_database_name}?sslmode=require" : ""
}
