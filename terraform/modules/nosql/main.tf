# ============================================================
# Module NoSQL : DocumentDB (compatible API MongoDB)
# Stocke les logs, le clickstream, les retours clients et
# le feature store ML (cf. NoSQL Data Model)
# ============================================================

resource "aws_docdb_subnet_group" "nosql" {
  name       = "${var.project_name}-nosql-subnet-group"
  subnet_ids = var.private_subnet_ids
}

resource "aws_docdb_cluster_parameter_group" "nosql" {
  name   = "${var.project_name}-nosql-pg"
  family = "docdb5.0"

  # Active le TTL Monitor, nécessaire à la purge automatique
  # de la collection log_events (index TTL défini côté schéma)
  parameter {
    name  = "ttl_monitor"
    value = "enabled"
  }

  # Journal d'audit (connexions, DDL) pour la tracabilite
  parameter {
    name  = "audit_logs"
    value = "enabled"
  }
}

resource "aws_docdb_cluster" "nosql" {
  cluster_identifier              = "${var.project_name}-nosql-${var.environment}"
  engine                          = "docdb"
  engine_version                  = "5.0.0" # aligne sur la famille docdb5.0
  enabled_cloudwatch_logs_exports = ["audit"]
  master_username                 = var.master_username
  master_password                 = var.master_password
  db_subnet_group_name            = aws_docdb_subnet_group.nosql.name
  db_cluster_parameter_group_name = aws_docdb_cluster_parameter_group.nosql.name
  vpc_security_group_ids          = [var.security_group_id]

  storage_encrypted         = true
  backup_retention_period   = 7
  preferred_backup_window   = "03:00-05:00"
  deletion_protection       = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.project_name}-nosql-final-snapshot"

  tags = { Name = "${var.project_name}-nosql-cluster" }
}

resource "aws_docdb_cluster_instance" "nosql" {
  count              = var.instance_count
  identifier         = "${var.project_name}-nosql-${count.index}"
  cluster_identifier = aws_docdb_cluster.nosql.id
  instance_class     = var.instance_class

  tags = { Name = "${var.project_name}-nosql-instance-${count.index}" }
}
