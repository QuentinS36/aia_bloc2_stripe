output "oltp_primary_endpoint" {
  description = "Endpoint de connexion à l'OLTP (lecture/écriture)"
  value       = module.oltp.primary_endpoint
}

output "oltp_replica_endpoint" {
  description = "Endpoint de connexion au réplica OLTP (lecture seule)"
  value       = module.oltp.replica_endpoint
}

output "olap_endpoint" {
  description = "Endpoint de connexion à l'entrepôt OLAP"
  value       = module.olap.endpoint
}

output "nosql_cluster_endpoint" {
  description = "Endpoint du cluster DocumentDB (NoSQL)"
  value       = module.nosql.cluster_endpoint
}

output "kafka_bootstrap_brokers" {
  description = "Adresses des brokers Kafka (TLS)"
  value       = module.streaming.bootstrap_brokers_tls
}

output "airflow_webserver_url" {
  description = "URL de l'interface web Airflow (MWAA)"
  value       = module.orchestration.webserver_url
}
