# ============================================================
# Module OLTP : PostgreSQL transactionnel (RDS)
# Réplication activée pour la haute disponibilité (Multi-AZ)
# et pour l'alimentation du pipeline CDC (Debezium)
# ============================================================

resource "aws_db_subnet_group" "oltp" {
  name       = "${var.project_name}-oltp-subnet-group"
  subnet_ids = var.private_subnet_ids
}

# Paramétrage nécessaire à la Change Data Capture (Debezium)
resource "aws_db_parameter_group" "oltp" {
  name   = "${var.project_name}-oltp-pg"
  family = "postgres16"

  parameter {
    name         = "rds.logical_replication"
    value        = "1"
    apply_method = "pending-reboot"
  }

  # Parametres statiques : un redemarrage est necessaire pour les appliquer
  parameter {
    name         = "max_replication_slots"
    value        = "10"
    apply_method = "pending-reboot"
  }

  parameter {
    name         = "max_wal_senders"
    value        = "10"
    apply_method = "pending-reboot"
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

resource "aws_db_instance" "oltp_primary" {
  identifier     = "${var.project_name}-oltp-${var.environment}"
  engine         = "postgres"
  engine_version = "16.3"
  instance_class = var.instance_class

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.allocated_storage * 3
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = "stripe_oltp"
  username = var.master_username
  password = var.master_password

  db_subnet_group_name   = aws_db_subnet_group.oltp.name
  vpc_security_group_ids = [var.security_group_id]
  parameter_group_name   = aws_db_parameter_group.oltp.name

  # Exigence ACID / haute disponibilité : réplication synchrone Multi-AZ
  multi_az = true

  # Export des logs (dont pgAudit) vers CloudWatch Logs
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  backup_retention_period   = 7
  deletion_protection       = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.project_name}-oltp-final-snapshot"

  tags = { Name = "${var.project_name}-oltp-primary", Role = "OLTP" }
}

# Réplica en lecture (délestage des requêtes de reporting ponctuelles,
# et base pour un éventuel scénario de failover manuel)
resource "aws_db_instance" "oltp_replica" {
  identifier          = "${var.project_name}-oltp-replica-${var.environment}"
  replicate_source_db = aws_db_instance.oltp_primary.identifier
  instance_class      = var.instance_class
  storage_encrypted   = true

  # Un replica n'a pas besoin de snapshot final (evite l'echec du destroy)
  skip_final_snapshot = true

  vpc_security_group_ids = [var.security_group_id]

  tags = { Name = "${var.project_name}-oltp-replica", Role = "OLTP-Replica" }
}
