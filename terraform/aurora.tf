data "aws_vpc" "default" {
  count   = local.aurora_enabled ? 1 : 0
  default = true
}

data "aws_subnets" "default" {
  count = local.aurora_enabled ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default[0].id]
  }

  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

resource "random_password" "aurora_master" {
  count   = local.aurora_enabled ? 1 : 0
  length  = 24
  special = false
}

resource "aws_secretsmanager_secret" "aurora_master" {
  count = local.aurora_enabled ? 1 : 0

  name = "${local.name_prefix}-aurora-master"

  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "aurora_master" {
  count = local.aurora_enabled ? 1 : 0

  secret_id = aws_secretsmanager_secret.aurora_master[0].id
  secret_string = jsonencode({
    username = var.aurora_master_username
    password = random_password.aurora_master[0].result
  })
}

resource "aws_security_group" "aurora" {
  count = local.aurora_enabled ? 1 : 0

  name        = "${local.name_prefix}-aurora-sg"
  description = "Aurora Serverless security group for Data API access"
  vpc_id      = data.aws_vpc.default[0].id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.common_tags
}

resource "aws_db_subnet_group" "aurora" {
  count = local.aurora_enabled ? 1 : 0

  name       = "${local.name_prefix}-aurora-subnets"
  subnet_ids = data.aws_subnets.default[0].ids

  tags = local.common_tags
}

resource "aws_rds_cluster" "aurora" {
  count = local.aurora_enabled ? 1 : 0

  cluster_identifier = "${local.name_prefix}-aurora"
  engine             = "aurora-postgresql"
  engine_version     = var.aurora_engine_version
  database_name      = var.aurora_database_name
  master_username    = var.aurora_master_username
  master_password    = random_password.aurora_master[0].result

  db_subnet_group_name   = aws_db_subnet_group.aurora[0].name
  vpc_security_group_ids = [aws_security_group.aurora[0].id]

  backup_retention_period         = 1
  deletion_protection             = false
  storage_encrypted               = true
  skip_final_snapshot             = true
  apply_immediately               = true
  enable_http_endpoint            = true
  copy_tags_to_snapshot           = true
  iam_database_authentication_enabled = false

  serverlessv2_scaling_configuration {
    min_capacity = var.aurora_min_capacity
    max_capacity = var.aurora_max_capacity
  }

  tags = local.common_tags
}

resource "aws_rds_cluster_instance" "aurora_writer" {
  count = local.aurora_enabled ? 1 : 0

  identifier         = "${local.name_prefix}-aurora-1"
  cluster_identifier = aws_rds_cluster.aurora[0].id
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.aurora[0].engine
  engine_version     = aws_rds_cluster.aurora[0].engine_version
  publicly_accessible = false
  apply_immediately   = true

  tags = local.common_tags
}