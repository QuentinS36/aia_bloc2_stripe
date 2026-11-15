# ============================================================
# Module Orchestration : Apache Airflow managé (Amazon MWAA)
# Exécute les DAGs batch (dag_olap_refresh, dag_ml_feature_refresh)
# ============================================================

resource "aws_s3_bucket" "airflow_dags" {
  bucket = "${var.project_name}-${var.environment}-airflow-dags"

  tags = { Name = "${var.project_name}-airflow-dags" }
}

resource "aws_s3_bucket_versioning" "airflow_dags" {
  bucket = aws_s3_bucket.airflow_dags.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "airflow_dags" {
  bucket                  = aws_s3_bucket.airflow_dags.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  env_name = "${var.project_name}-airflow-${var.environment}"
}

resource "aws_iam_role" "mwaa_execution" {
  name = "${var.project_name}-mwaa-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = [
          "airflow.amazonaws.com",
          "airflow-env.amazonaws.com"
        ]
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "mwaa_execution" {
  name = "${var.project_name}-mwaa-execution-policy"
  role = aws_iam_role.mwaa_execution.id

  # Politique de moindre privilège : accès limité au bucket DAGs,
  # aux logs CloudWatch et aux secrets nécessaires à la connexion
  # aux bases OLTP/OLAP/NoSQL (cf. module monitoring et Secrets Manager)
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["s3:GetObject*", "s3:ListBucket"]
        Resource = [
          aws_s3_bucket.airflow_dags.arn,
          "${aws_s3_bucket.airflow_dags.arn}/*"
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:GetLogEvents"]
        Resource = "arn:aws:logs:*:*:log-group:airflow-${var.project_name}-*"
      },
      {
        Effect   = "Allow"
        Action   = ["airflow:PublishMetrics"]
        Resource = "arn:aws:airflow:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:environment/${local.env_name}"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetAccountPublicAccessBlock"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:DescribeLogGroups"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["cloudwatch:PutMetricData"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:ChangeMessageVisibility", "sqs:DeleteMessage", "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl", "sqs:ReceiveMessage", "sqs:SendMessage"
        ]
        Resource = "arn:aws:sqs:${data.aws_region.current.name}:*:airflow-celery-*"
      },
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = "arn:aws:secretsmanager:*:*:secret:${var.project_name}/*"
      }
    ]
  })
}

resource "aws_mwaa_environment" "main" {
  name               = local.env_name
  airflow_version    = "2.9.2"
  environment_class  = var.environment_class
  min_workers        = var.min_workers
  max_workers        = var.max_workers
  execution_role_arn = aws_iam_role.mwaa_execution.arn

  source_bucket_arn = aws_s3_bucket.airflow_dags.arn
  dag_s3_path       = "dags/"

  network_configuration {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [var.security_group_id]
  }

  logging_configuration {
    dag_processing_logs {
      enabled   = true
      log_level = "INFO"
    }
    scheduler_logs {
      enabled   = true
      log_level = "INFO"
    }
    task_logs {
      enabled   = true
      log_level = "INFO"
    }
    webserver_logs {
      enabled   = true
      log_level = "INFO"
    }
    worker_logs {
      enabled   = true
      log_level = "INFO"
    }
  }

  tags = { Name = "${var.project_name}-airflow" }
}
