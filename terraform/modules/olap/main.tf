# ============================================================
# Module OLAP : entrepôt de données PostgreSQL (schéma en étoile)
# Instance dimensionnée pour les requêtes analytiques (CPU/RAM,
# stockage plus important que l'OLTP)
# ============================================================

resource "aws_db_subnet_group" "olap" {
  name       = "${var.project_name}-olap-subnet-group"
  subnet_ids = var.private_subnet_ids
}

resource "aws_db_parameter_group" "olap" {
  name   = "${var.project_name}-olap-pg"
  family = "postgres16"

  # Paramètres orientés requêtes analytiques (jointures larges,
  # agrégations sur de gros volumes)
  parameter {
    name  = "work_mem"
    value = "65536" # 64 Mo, ajustable selon la charge réelle
  }

  parameter {
    name  = "max_parallel_workers_per_gather"
    value = "4"
  }

  # Audit (Security and Compliance Plan, section 7) : pgAudit
  parameter {
    name         = "shared_preload_libraries"
    value        = "pg_stat_statements,pgaudit"
    apply_method = "pending-reboot"
  }

  parameter {
    name  = "pgaudit.log"
    value = "ddl,role,write"
  }
}

resource "aws_db_instance" "olap" {
  identifier     = "${var.project_name}-olap-${var.environment}"
  engine         = "postgres"
  engine_version = "16.3"
  instance_class = var.instance_class

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.allocated_storage * 2
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = "stripe_olap"
  username = var.master_username
  password = var.master_password

  db_subnet_group_name   = aws_db_subnet_group.olap.name
  vpc_security_group_ids = [var.security_group_id]
  parameter_group_name   = aws_db_parameter_group.olap.name

  multi_az = true

  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  backup_retention_period         = 14
  deletion_protection             = true
  skip_final_snapshot             = false
  final_snapshot_identifier       = "${var.project_name}-olap-final-snapshot"

  tags = { Name = "${var.project_name}-olap", Role = "OLAP" }
}
