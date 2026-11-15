terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Backend distant recommandé en production (non initialisé ici,
  # ce projet n'étant pas destiné à être déployé - cf. README.md)
  # backend "s3" {
  #   bucket = "stripe-data-platform-tfstate"
  #   key    = "global/terraform.tfstate"
  #   region = "eu-west-1"
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
