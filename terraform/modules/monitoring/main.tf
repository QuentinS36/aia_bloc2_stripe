# ============================================================
# Module Monitoring : alerting CloudWatch + notification SNS
# ============================================================

resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-${var.environment}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# --- Alarmes OLTP ---
resource "aws_cloudwatch_metric_alarm" "oltp_cpu" {
  alarm_name          = "${var.project_name}-oltp-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "CPU OLTP > 80% pendant 15 minutes"
  dimensions          = { DBInstanceIdentifier = var.oltp_instance_id }
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "oltp_storage" {
  alarm_name          = "${var.project_name}-oltp-storage-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 10737418240 # 10 Go
  alarm_description   = "Espace disque OLTP restant < 10 Go"
  dimensions          = { DBInstanceIdentifier = var.oltp_instance_id }
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

# --- Alarmes OLAP ---
resource "aws_cloudwatch_metric_alarm" "olap_cpu" {
  alarm_name          = "${var.project_name}-olap-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 85
  alarm_description   = "CPU OLAP > 85% pendant 15 minutes (requêtes analytiques lourdes)"
  dimensions          = { DBInstanceIdentifier = var.olap_instance_id }
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

# --- Alarme Kafka (MSK) ---
resource "aws_cloudwatch_metric_alarm" "kafka_disk_usage" {
  # Une alarme par broker : la metrique KafkaDataLogsDiskUsed est publiee par broker
  count               = var.kafka_broker_count
  alarm_name          = "${var.project_name}-kafka-disk-high-broker-${count.index + 1}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "KafkaDataLogsDiskUsed"
  namespace           = "AWS/Kafka"
  period              = 300
  statistic           = "Maximum"
  threshold           = 80
  alarm_description   = "Utilisation disque des brokers Kafka > 80%"
  dimensions = {
    "Cluster Name" = var.kafka_cluster_name
    "Broker ID"    = tostring(count.index + 1)
  }
  alarm_actions = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project_name}-${var.environment}-overview"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title   = "OLTP - CPU Utilization"
          metrics = [["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", var.oltp_instance_id]]
          period  = 300
          stat    = "Average"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title   = "OLAP - CPU Utilization"
          metrics = [["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", var.olap_instance_id]]
          period  = 300
          stat    = "Average"
        }
      }
    ]
  })
}
