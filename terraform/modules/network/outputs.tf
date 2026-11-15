output "vpc_id" { value = aws_vpc.main.id }
output "public_subnet_ids" { value = aws_subnet.public[*].id }
output "private_subnet_ids" { value = aws_subnet.private[*].id }
output "database_sg_id" { value = aws_security_group.database.id }
output "nosql_sg_id" { value = aws_security_group.nosql.id }
output "airflow_sg_id" { value = aws_security_group.airflow.id }
output "kafka_sg_id" { value = aws_security_group.kafka.id }
