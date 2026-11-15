# Architecture de données Stripe : OLTP · OLAP · NoSQL

Projet fictif de certification **AIA – Bloc 2 (RNCP38777, niveau 7)** : *Concevoir et déployer des architectures de données (pour l'IA)*.

Conception d'une architecture de données polyglotte pour une fintech de type Stripe : un système transactionnel (OLTP), un entrepôt analytique (OLAP) et une base documentaire (NoSQL), reliés par un pipeline batch et streaming, avec sécurité, conformité et intégration du machine learning.


## Contenu du dépôt

```
.
├── docs/
│   ├── 1_cahier_des_charges.docx        Enjeux, exigences, choix de périmètre, règles de gestion financières
│   ├── 2_modelisation_OLTP.docx         MCD → MLD → MPD, ERD, règles d'intégrité
│   ├── 3_modelisation_OLAP.docx         Schéma en étoile, définition des indicateurs, vues matérialisées
│   ├── 4_modelisation_nosql.docx        Collections MongoDB, embedding / référencement, index
│   ├── 5_architecture_du_pipeline.docx  Kafka, Debezium, Airflow, cohérence, performance, supervision
│   ├── 6_securite.docx                  Security and Compliance Plan (RGPD, PCI-DSS, CCPA)
│   ├── 7_strategie_ml.docx              Feature store, scoring temps réel, gouvernance des modèles
│   └── 8_requetes_sql.docx              Requêtes SQL et NoSQL de démonstration
├── sql/
│   ├── oltp_schema.sql                  Schéma physique OLTP (12 tables, règles R1 à R5)
│   ├── olap_schema.sql                  Schéma en étoile, partitions, vues matérialisées
│   ├── seed_oltp.sql / seed_olap.sql    Jeux de données synthétiques minimaux
│   ├── test_integrity_oltp.sql          Tests : chaque règle d'intégrité doit refuser l'opération invalide
│   ├── test_integrity_olap.sql          Tests : cohérence financière et vues de revenu
│   └── demo_queries.sql                 Requêtes métier (revenu, fraude, segmentation)
└── terraform/                           Infrastructure as Code (AWS), non déployée
```

## Architecture

```
Application Stripe ──► OLTP (PostgreSQL) ──► CDC (Debezium) ──► Kafka ──► consommateurs ──► NoSQL (MongoDB)
        │                                                          │
        └── logs / clickstream ───────────────────────────────────┘
                                                                   └──► Airflow (batch) ──► OLAP (PostgreSQL, étoile)
                                                                                      └──► features ML ──► NoSQL (feature store)
Supervision : CloudWatch + SNS sur l'ensemble des briques
```

| Système | Techno | Modèle | Points clés |
|---|---|---|---|
| OLTP | PostgreSQL, Multi-AZ + réplica | 12 entités normalisées (Merise complet) | ACID, contraintes CHECK, clé étrangère composite, contrôle des remboursements, réplication logique pour le CDC |
| OLAP | PostgreSQL | Étoile : 1 fait, 7 dimensions | Partitionnement mensuel par date, 3 vues matérialisées par devise |
| NoSQL | MongoDB (DocumentDB sur AWS) | 4 collections : logs, sessions, feedback, features ML | Modèle par pattern d'accès, index TTL sur les logs, feature store versionné |
| Streaming | Kafka (MSK) | Topics `transaction_events`, `log_events`, `clickstream_events` | Réplication ×3, `min.insync.replicas=2`, rétention 7 jours (rejeu) |
| Orchestration | Airflow (MWAA) | DAGs de rafraîchissement OLAP, features ML, effacement RGPD | Idempotents (upsert), contrôle de cohérence après chargement |

**Fraîcheur des données** : la capture CDC est continue, mais l'intégration dans l'OLAP et le rafraîchissement des vues sont horaires (fraîcheur d'environ 1 heure). Le temps réel passe par le streaming et le scoring.

## Règles de gestion et définitions

| Règle | Application |
|---|---|
| R1 | Le moyen de paiement d'une transaction appartient au client de la transaction (clé étrangère composite) |
| R2 | La somme des remboursements non échoués ne dépasse jamais le montant payé (déclencheur) |
| R3 | Un chargeback au plus par transaction |
| R4 | Aucune suppression en cascade de l'historique financier (`ON DELETE RESTRICT`) |
| R5 | `refunded` signifie remboursement total ; un remboursement partiel laisse la transaction à `successful` |

Indicateurs OLAP : `net_amount = amount - refunded_amount - fee_amount` (contrainte CHECK). Le **revenu** ne compte que les paiements **encaissés** (`successful` ou `refunded`) et est toujours calculé **par devise**, sans conversion.

## Sécurité et conformité
Défense en profondeur en 5 couches (réseau, chiffrement, accès, audit, supervision) ; RBAC à 7 rôles (`app_service`, `data_engineer`, `analyst`, `ml_engineer`, `fraud_analyst`, `auditor`, `dba`) ; classification des données sensibles par champ ; **anonymisation irréversible** des données personnelles (RGPD / CCPA) avec conservation des montants dissociés de toute identité ; reporting de conformité automatisé.

## Machine learning
Feature store partagé entre entraînement (offline) et scoring (online) pour éviter le *training-serving skew* ; latence cible de scoring < 100 ms ; déploiement progressif staging → shadow → canary ; ré-entraînement déclenché par la dérive (PSI) ; chaque score est lié à une version de modèle (`fraud_indicator.model_version`) ; aucune donnée personnelle directe utilisée comme feature.

## Tester les schémas SQL

```bash
docker run --rm -d --name pg -e POSTGRES_PASSWORD=demo -p 5432:5432 postgres:16
docker exec -i pg psql -U postgres -c "CREATE DATABASE oltp" -c "CREATE DATABASE olap"

# OLTP : schéma, données, tests d'intégrité
docker exec -i pg psql -U postgres -d oltp -v ON_ERROR_STOP=1 < sql/oltp_schema.sql
docker exec -i pg psql -U postgres -d oltp -v ON_ERROR_STOP=1 < sql/seed_oltp.sql
docker exec -i pg psql -U postgres -d oltp < sql/test_integrity_oltp.sql

# OLAP : schéma, données, rafraîchissement des vues, tests
docker exec -i pg psql -U postgres -d olap -v ON_ERROR_STOP=1 < sql/olap_schema.sql
docker exec -i pg psql -U postgres -d olap -v ON_ERROR_STOP=1 < sql/seed_olap.sql
for v in agg_revenue_daily_merchant agg_fraud_daily agg_customer_segment_monthly; do
  docker exec -i pg psql -U postgres -d olap -c "REFRESH MATERIALIZED VIEW $v"
done
docker exec -i pg psql -U postgres -d olap < sql/test_integrity_olap.sql
```

Les tests affichent `OK` pour chaque règle vérifiée (opération invalide refusée) et lèvent une erreur dans le cas contraire. Les requêtes SQL de `sql/demo_queries.sql` s'exécutent sur ces jeux de données ; les requêtes MongoDB y figurent à titre de démonstration (identifiants d'exemple).

## Infrastructure as Code (Terraform)
Sept modules : `network`, `oltp`, `olap`, `nosql`, `streaming`, `orchestration`, `monitoring`. Voir `terraform/README.md`.

```bash
cd terraform
export TF_VAR_db_master_password='...'   # jamais en dur
terraform init && terraform validate && terraform plan
```

## Choix de conception assumés
- **Schéma en étoile plutôt que flocon** : performance de lecture, requêtes plus simples pour les analystes.
- **PostgreSQL pour l'OLAP** : mêmes compétences et mêmes outils que l'OLTP, adapté au volume du projet. À l'échelle réelle de Stripe, un entrepôt colonnaire serait préférable.
- **Kafka entre l'OLTP et les consommateurs** : découplage producteurs / consommateurs et rejeu en cas d'incident.
- **Feature store dans le NoSQL** : lecture à faible latence pour le scoring, schéma flexible.
- **Anonymisation plutôt que suppression** : concilie droit à l'effacement et obligations comptables.


## Limites connues
- Infrastructure non déployée ; Debezium (Kafka Connect), les consommateurs Kafka et le service de scoring ne sont pas provisionnés par le Terraform.
- A grande échelle, entrepôt colonnaire.
