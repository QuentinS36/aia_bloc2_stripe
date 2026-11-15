-- ============================================================
-- MPD (Modèle Physique de Données) - Système OLAP Stripe
-- SGBD cible : PostgreSQL 16+ (schéma en étoile)
-- Projet : Architecture de données Stripe - Bloc 2 RNCP38777
-- ============================================================
-- Définitions des indicateurs financiers (grain : 1 ligne = 1 transaction) :
--   amount           Montant brut payé, dans la devise de la transaction
--   refunded_amount  Somme des remboursements 'completed' de la transaction
--   fee_amount       Frais de traitement prélevés
--   net_amount       amount - refunded_amount - fee_amount
--                    (montant net conservé par le marchand, imposé par un CHECK)
-- Un paiement "encaissé" est une transaction dont le statut est 'successful' ou 'refunded'.
-- Les transactions 'pending' et 'failed' sont exclues de tous les indicateurs de revenu.
-- Aucune conversion de devise : les montants sont agrégés PAR DEVISE (jamais additionnés
-- entre devises différentes).
-- ============================================================

-- ============================================================
-- Dimensions
-- ============================================================

CREATE TABLE dim_date (
    date_key        INTEGER         PRIMARY KEY,        -- format YYYYMMDD
    full_date       DATE            NOT NULL,
    day_of_week     SMALLINT        NOT NULL,
    month           SMALLINT        NOT NULL,
    quarter         SMALLINT        NOT NULL,
    year            SMALLINT        NOT NULL,
    is_weekend      BOOLEAN         NOT NULL
);

CREATE TABLE dim_merchant (
    merchant_key    SERIAL          PRIMARY KEY,
    merchant_id     UUID            NOT NULL UNIQUE,    -- clé naturelle (source OLTP), cible des upserts
    name            VARCHAR(120)    NOT NULL,
    country         CHAR(2)         NOT NULL,
    segment         VARCHAR(50)
);

CREATE TABLE dim_customer (
    customer_key    SERIAL          PRIMARY KEY,
    customer_id     UUID            NOT NULL UNIQUE,    -- identifiant pseudonymisé : aucun email ni nom
    segment         VARCHAR(50),
    country         CHAR(2)
);

CREATE TABLE dim_payment_method (
    payment_method_key SERIAL       PRIMARY KEY,
    type                VARCHAR(20) NOT NULL UNIQUE
);

CREATE TABLE dim_currency (
    currency_key    SERIAL          PRIMARY KEY,
    currency_code   CHAR(3)         NOT NULL UNIQUE
);

CREATE TABLE dim_location (
    location_key    SERIAL          PRIMARY KEY,
    country         CHAR(2),
    region          VARCHAR(50)
);

CREATE TABLE dim_status (
    status_key      SERIAL          PRIMARY KEY,
    label           VARCHAR(20)     NOT NULL UNIQUE
);

-- Valeurs fixes de la dimension statut (alignées sur le CHECK de transaction.status)
INSERT INTO dim_status (label) VALUES ('pending'), ('successful'), ('failed'), ('refunded');

-- ============================================================
-- Table de faits (partitionnée par date pour la performance)
-- ============================================================

CREATE TABLE fact_transaction (
    transaction_id      UUID            NOT NULL,
    date_key            INTEGER         NOT NULL REFERENCES dim_date(date_key),
    merchant_key        INTEGER         NOT NULL REFERENCES dim_merchant(merchant_key),
    customer_key        INTEGER         NOT NULL REFERENCES dim_customer(customer_key),
    payment_method_key  INTEGER         NOT NULL REFERENCES dim_payment_method(payment_method_key),
    currency_key        INTEGER         NOT NULL REFERENCES dim_currency(currency_key),
    location_key        INTEGER         REFERENCES dim_location(location_key),
    status_key          INTEGER         NOT NULL REFERENCES dim_status(status_key),
    amount              NUMERIC(14,2)   NOT NULL,                       -- brut
    fee_amount          NUMERIC(14,2)   NOT NULL DEFAULT 0,             -- frais
    refunded_amount     NUMERIC(14,2)   NOT NULL DEFAULT 0,             -- remboursé (completed)
    net_amount          NUMERIC(14,2)   NOT NULL,                       -- brut - remboursé - frais
    fraud_score         NUMERIC(5,4),
    is_fraud            BOOLEAN         NOT NULL DEFAULT FALSE,
    is_chargeback       BOOLEAN         NOT NULL DEFAULT FALSE,
    PRIMARY KEY (transaction_id, date_key),
    CHECK (refunded_amount BETWEEN 0 AND amount),
    CHECK (net_amount = amount - refunded_amount - fee_amount)
) PARTITION BY RANGE (date_key);

-- Partitions mensuelles de 2026 (le DAG de maintenance crée les suivantes à l'avance)
DO $$
DECLARE m INT;
BEGIN
    FOR m IN 1..12 LOOP
        EXECUTE format(
            'CREATE TABLE fact_transaction_2026_%s PARTITION OF fact_transaction FOR VALUES FROM (%s) TO (%s)',
            lpad(m::text, 2, '0'),
            20260000 + m * 100 + 1,
            CASE WHEN m = 12 THEN 20270101 ELSE 20260000 + (m + 1) * 100 + 1 END);
    END LOOP;
END $$;

-- Partition par défaut : empêche l'échec du chargement si aucune partition
-- mensuelle n'existe encore (à vider/éclater par le DAG de maintenance).
CREATE TABLE fact_transaction_default PARTITION OF fact_transaction DEFAULT;

-- ============================================================
-- Index de performance
-- ============================================================

CREATE INDEX idx_fact_merchant_date ON fact_transaction(merchant_key, date_key);
CREATE INDEX idx_fact_customer_date ON fact_transaction(customer_key, date_key);
CREATE INDEX idx_fact_status ON fact_transaction(status_key);
CREATE INDEX idx_fact_is_fraud ON fact_transaction(is_fraud) WHERE is_fraud = TRUE;

-- ============================================================
-- Vues matérialisées de pré-agrégation
-- ============================================================

-- Revenu quotidien par marchand ET par devise, paiements encaissés uniquement
CREATE MATERIALIZED VIEW agg_revenue_daily_merchant AS
SELECT
    f.date_key,
    f.merchant_key,
    m.name                  AS merchant_name,
    f.currency_key,
    cu.currency_code,
    COUNT(*)                AS transaction_count,
    SUM(f.amount)           AS gross_amount,
    SUM(f.refunded_amount)  AS total_refunded,
    SUM(f.fee_amount)       AS total_fees,
    SUM(f.net_amount)       AS total_net_revenue
FROM fact_transaction f
JOIN dim_merchant m  ON m.merchant_key  = f.merchant_key
JOIN dim_currency cu ON cu.currency_key = f.currency_key
JOIN dim_status s    ON s.status_key    = f.status_key
WHERE s.label IN ('successful', 'refunded')
GROUP BY f.date_key, f.merchant_key, m.name, f.currency_key, cu.currency_code;

CREATE UNIQUE INDEX ON agg_revenue_daily_merchant (date_key, merchant_key, currency_key);

-- Fraude quotidienne par pays : calculée sur toutes les transactions scorées
CREATE MATERIALIZED VIEW agg_fraud_daily AS
SELECT
    f.date_key,
    COALESCE(l.country, '??')                                    AS country,
    COUNT(*)                                                     AS transaction_count,
    COUNT(*) FILTER (WHERE f.is_fraud)                           AS fraud_count,
    ROUND(COUNT(*) FILTER (WHERE f.is_fraud)::numeric / COUNT(*), 4) AS fraud_rate,
    AVG(f.fraud_score)                                           AS avg_fraud_score
FROM fact_transaction f
LEFT JOIN dim_location l ON l.location_key = f.location_key
GROUP BY f.date_key, COALESCE(l.country, '??');

-- Index unique requis par REFRESH ... CONCURRENTLY
CREATE UNIQUE INDEX ON agg_fraud_daily (date_key, country);

-- Dépense mensuelle par segment client et par devise, paiements encaissés uniquement
CREATE MATERIALIZED VIEW agg_customer_segment_monthly AS
SELECT
    d.year,
    d.month,
    COALESCE(c.segment, 'UNKNOWN')   AS segment,
    cu.currency_code,
    COUNT(DISTINCT f.customer_key)   AS active_customers,
    SUM(f.amount)                    AS total_spend,
    SUM(f.net_amount)                AS total_net
FROM fact_transaction f
JOIN dim_date d      ON d.date_key      = f.date_key
JOIN dim_customer c  ON c.customer_key  = f.customer_key
JOIN dim_currency cu ON cu.currency_key = f.currency_key
JOIN dim_status s    ON s.status_key    = f.status_key
WHERE s.label IN ('successful', 'refunded')
GROUP BY d.year, d.month, COALESCE(c.segment, 'UNKNOWN'), cu.currency_code;

-- Index unique requis par REFRESH ... CONCURRENTLY
CREATE UNIQUE INDEX ON agg_customer_segment_monthly (year, month, segment, currency_code);

-- Rafraîchissement (orchestré par le DAG Airflow dag_olap_refresh, horaire)
-- REFRESH MATERIALIZED VIEW CONCURRENTLY agg_revenue_daily_merchant;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY agg_fraud_daily;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY agg_customer_segment_monthly;
