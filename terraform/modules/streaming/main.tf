# ============================================================
# Module Streaming : cluster Kafka managé (Amazon MSK)
# Topics : transaction_events (CDC), log_events, clickstream_events
# ============================================================

resource "aws_cloudwatch_log_group" "kafka_broker_logs" {
  name              = "/msk/${var.project_name}-${var.environment}"
  retention_in_days = 14
}

resource "aws_msk_configuration" "main" {
  name           = "${var.project_name}-kafka-config"
  kafka_versions = [var.kafka_version]

  server_properties = <<PROPERTIES
auto.create.topics.enable=false
default.replication.factor=3
min.insync.replicas=2
num.partitions=6
log.retention.hours=168
PROPERTIES
}

resource "aws_msk_cluster" "main" {
  cluster_name           = "${var.project_name}-kafka-${var.environment}"
  kafka_version          = var.kafka_version
  number_of_broker_nodes = var.broker_count

  broker_node_group_info {
    instance_type   = var.broker_instance_type
    client_subnets  = var.private_subnet_ids
    security_groups = [var.security_group_id]

    storage_info {
      ebs_storage_info {
        volume_size = 500
      }
    }
  }

  configuration_info {
    arn      = aws_msk_configuration.main.arn
    revision = aws_msk_configuration.main.latest_revision
  }

  encryption_info {
    encryption_in_transit {
      client_broker = "TLS"
      in_cluster    = true
    }
  }

  logging_info {
    broker_logs {
      cloudwatch_logs {
        enabled   = true
        log_group = aws_cloudwatch_log_group.kafka_broker_logs.name
      }
    }
  }

  tags = { Name = "${var.project_name}-kafka" }
}

# Mise a l'echelle automatique du stockage des brokers (scale-out du volume,
# jamais de reduction) : evite la saturation disque en cas de pic de volume.
resource "aws_appautoscaling_target" "kafka_storage" {
  max_capacity       = 2000
  min_capacity       = 1
  resource_id        = aws_msk_cluster.main.arn
  scalable_dimension = "kafka:broker-storage:VolumeSize"
  service_namespace  = "kafka"
}

resource "aws_appautoscaling_policy" "kafka_storage" {
  name               = "${var.project_name}-kafka-storage-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_msk_cluster.main.arn
  scalable_dimension = aws_appautoscaling_target.kafka_storage.scalable_dimension
  service_namespace  = aws_appautoscaling_target.kafka_storage.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "KafkaBrokerStorageUtilization"
    }
    target_value = 70
  }
}

# Remarque : la création des topics (transaction_events, log_events,
# clickstream_events) avec leurs paramètres de rétention et de
# partitionnement dédiés est gérée via le provider Terraform "kafka"
# (Mongey/kafka) ou un script d'initialisation exécuté après la mise
# en service du cluster, et non via le provider AWS lui-même.
# Non instanciée ici, ce projet n'étant pas destiné à être déployé
# (cf. README.md).
