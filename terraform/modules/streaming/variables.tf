variable "project_name" { type = string }
variable "environment" { type = string }
variable "broker_instance_type" { type = string }
variable "broker_count" { type = number }
variable "kafka_version" { type = string }
variable "private_subnet_ids" { type = list(string) }
variable "security_group_id" { type = string }
