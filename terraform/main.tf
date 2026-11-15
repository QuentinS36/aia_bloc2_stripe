# ============================================================
# Architecture de données Stripe
# Point d'entrée racine : assemble les modules réseau, OLTP,
# OLAP, NoSQL, streaming, orchestration et monitoring.
#
# Ce code est écrit pour spécifier et documenter la
# infrastructure cible.
# ============================================================

module "network" {
  source = "./modules/network"

  project_name       = var.project_name
  environment        = var.environment
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
}

module "oltp" {
  source = "./modules/oltp"

  project_name       = var.project_name
  environment        = var.environment
  instance_class     = var.oltp_instance_class
  allocated_storage  = var.oltp_allocated_storage
  private_subnet_ids = module.network.private_subnet_ids
  security_group_id  = module.network.database_sg_id
  master_username    = var.db_master_username
  master_password    = var.db_master_password
}

module "olap" {
  source = "./modules/olap"

  project_name       = var.project_name
  environment        = var.environment
  instance_class     = var.olap_instance_class
  allocated_storage  = var.olap_allocated_storage
  private_subnet_ids = module.network.private_subnet_ids
  security_group_id  = module.network.database_sg_id
  master_username    = var.db_master_username
  master_password    = var.db_master_password
}

module "nosql" {
  source = "./modules/nosql"

  project_name       = var.project_name
  environment        = var.environment
  instance_class     = var.nosql_instance_class
  instance_count     = var.nosql_instance_count
  private_subnet_ids = module.network.private_subnet_ids
  security_group_id  = module.network.nosql_sg_id
  master_username    = var.db_master_username
  master_password    = var.db_master_password
}

module "streaming" {
  source = "./modules/streaming"

  project_name         = var.project_name
  environment          = var.environment
  broker_instance_type = var.kafka_broker_instance_type
  broker_count         = var.kafka_broker_count
  kafka_version        = var.kafka_version
  private_subnet_ids   = module.network.private_subnet_ids
  security_group_id    = module.network.kafka_sg_id
}

module "orchestration" {
  source = "./modules/orchestration"

  project_name       = var.project_name
  environment        = var.environment
  environment_class  = var.airflow_environment_class
  min_workers        = var.airflow_min_workers
  max_workers        = var.airflow_max_workers
  private_subnet_ids = module.network.private_subnet_ids
  security_group_id  = module.network.airflow_sg_id
}

module "monitoring" {
  source = "./modules/monitoring"

  project_name       = var.project_name
  environment        = var.environment
  alert_email        = var.alert_email
  oltp_instance_id   = module.oltp.identifier
  olap_instance_id   = module.olap.identifier
  kafka_cluster_name = module.streaming.cluster_name
  kafka_broker_count = var.kafka_broker_count
}
