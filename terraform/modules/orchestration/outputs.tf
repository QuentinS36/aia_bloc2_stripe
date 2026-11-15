output "webserver_url" { value = aws_mwaa_environment.main.webserver_url }
output "dags_bucket" { value = aws_s3_bucket.airflow_dags.bucket }
