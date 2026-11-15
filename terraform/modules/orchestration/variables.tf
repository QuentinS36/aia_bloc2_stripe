variable "project_name" { type = string }
variable "environment" { type = string }
variable "environment_class" { type = string }
variable "private_subnet_ids" { type = list(string) }
variable "security_group_id" { type = string }
variable "min_workers" { type = number }
variable "max_workers" { type = number }
