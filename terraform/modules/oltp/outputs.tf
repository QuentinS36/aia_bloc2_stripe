output "primary_endpoint" { value = aws_db_instance.oltp_primary.endpoint }
output "replica_endpoint" { value = aws_db_instance.oltp_replica.endpoint }
output "identifier" { value = aws_db_instance.oltp_primary.identifier }
output "db_name" { value = aws_db_instance.oltp_primary.db_name }
