variable "project_name" { type = string }
variable "environment" { type = string }
variable "instance_class" { type = string }
variable "instance_count" { type = number }
variable "private_subnet_ids" { type = list(string) }
variable "security_group_id" { type = string }

variable "master_username" {
  type      = string
  sensitive = true
}

variable "master_password" {
  type      = string
  sensitive = true
}
