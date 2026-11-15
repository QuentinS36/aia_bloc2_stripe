variable "project_name" {
  description = "Nom du projet, utilisé comme préfixe pour les ressources"
  type        = string
  default     = "stripe-data-platform"
}

variable "environment" {
  description = "Environnement cible (ex. staging, production)"
  type        = string
  default     = "staging"
}

variable "aws_region" {
  description = "Région AWS de déploiement"
  type        = string
  default     = "eu-west-1"
}

variable "vpc_cidr" {
  description = "Bloc CIDR du VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Zones de disponibilité utilisées (haute disponibilité multi-AZ)"
  type        = list(string)
  default     = ["eu-west-1a", "eu-west-1b"]
}

# --- OLTP ---
variable "oltp_instance_class" {
  description = "Classe d'instance RDS pour le système transactionnel"
  type        = string
  default     = "db.r6g.large"
}

variable "oltp_allocated_storage" {
  description = "Stockage alloué (Go) pour l'OLTP"
  type        = number
  default     = 100
}

# --- OLAP ---
variable "olap_instance_class" {
  description = "Classe d'instance RDS pour le système analytique"
  type        = string
  default     = "db.r6g.xlarge"
}

variable "olap_allocated_storage" {
  description = "Stockage alloué (Go) pour l'OLAP"
  type        = number
  default     = 500
}

# --- NoSQL ---
variable "nosql_instance_class" {
  description = "Classe d'instance DocumentDB (compatible MongoDB)"
  type        = string
  default     = "db.r6g.large"
}

variable "nosql_instance_count" {
  description = "Nombre d'instances dans le cluster DocumentDB"
  type        = number
  default     = 2
}

# --- Streaming ---
variable "kafka_broker_instance_type" {
  description = "Type d'instance des brokers Kafka (MSK)"
  type        = string
  default     = "kafka.m5.large"
}

variable "kafka_broker_count" {
  description = "Nombre de brokers Kafka (multiple de 3 recommandé)"
  type        = number
  default     = 3
}

variable "kafka_version" {
  description = "Version Kafka gérée par MSK"
  type        = string
  default     = "3.6.0"
}

# --- Orchestration ---
variable "airflow_environment_class" {
  description = "Classe d'environnement MWAA (Managed Airflow)"
  type        = string
  default     = "mw1.medium"
}

variable "airflow_min_workers" {
  description = "Nombre minimal de workers MWAA"
  type        = number
  default     = 1
}

variable "airflow_max_workers" {
  description = "Nombre maximal de workers MWAA (mise a l'echelle automatique en fonction de la file de taches)"
  type        = number
  default     = 5
}

# --- Sécurité / credentials ---
variable "db_master_username" {
  description = "Identifiant administrateur des bases de données"
  type        = string
  default     = "stripe_admin"
  sensitive   = true
}

variable "db_master_password" {
  description = "Mot de passe administrateur (à fournir via une variable d'environnement TF_VAR_ ou un coffre-fort de secrets, jamais en dur)"
  type        = string
  sensitive   = true
}

# --- Monitoring ---
variable "alert_email" {
  description = "Adresse e-mail de notification des alertes CloudWatch"
  type        = string
  default     = "data-oncall@stripe-fictif.example.com"
}
