# Stripe Data Platform — Infrastructure as Code (Terraform)

## Contexte

Ce dépôt contient le code Terraform décrivant l'infrastructure cible de l'architecture de données Stripe.


## Architecture décrite

Le code provisionne, sur AWS (à titre d'exemple de cloud public — la même logique modulaire est transposable à un déploiement on-premise virtualisé) :

| Module | Ressources principales | Rôle |
|---|---|---|
| `network` | VPC, sous-réseaux publics/privés multi-AZ, security groups | Isolation réseau et segmentation des accès |
| `oltp` | RDS PostgreSQL (Multi-AZ + réplica), réplication logique activée | Système transactionnel, source du CDC |
| `olap` | RDS PostgreSQL dimensionné pour l'analytique | Entrepôt de données en schéma étoile |
| `nosql` | Cluster DocumentDB (API MongoDB), 2 instances | Logs, clickstream, feedback, feature store ML |
| `streaming` | Cluster Kafka managé (Amazon MSK), 3 brokers | Bus d'événements (CDC, logs, clickstream) |
| `orchestration` | Airflow managé (Amazon MWAA), bucket S3 des DAGs | Orchestration des traitements batch |
| `monitoring` | Alarmes CloudWatch, topic SNS, dashboard | Supervision de l'infrastructure |

## Structure du dépôt

```
.
├── README.md
├── providers.tf         # Déclaration du provider AWS
├── variables.tf         # Variables globales (dimensionnement, credentials...)
├── main.tf              # Assemblage des modules
├── outputs.tf           # Endpoints exposés
└── modules/
    ├── network/
    ├── oltp/
    ├── olap/
    ├── nosql/
    ├── streaming/
    ├── orchestration/
    └── monitoring/
```

## Choix de conception

- **Modularité** : chaque brique de l'architecture (réseau, OLTP, OLAP, NoSQL, streaming, orchestration, monitoring) est un module Terraform indépendant, réutilisable et testable isolément.
- **Sécurité par défaut** : chiffrement du stockage activé partout (`storage_encrypted = true`), bases de données en sous-réseaux privés, accès restreint au CIDR du VPC, secrets jamais en dur (variables `sensitive`).
- **Haute disponibilité** : OLTP et OLAP en Multi-AZ, réplica en lecture sur l'OLTP, cluster DocumentDB à plusieurs instances, Kafka répliqué sur 3 brokers.
- **Alignement avec le pipeline documenté** : la réplication logique PostgreSQL (`rds.logical_replication`) est explicitement activée sur l'OLTP pour permettre la capture de changements (CDC) via Debezium, telle que décrite dans le document *Data Pipeline Architecture*.
