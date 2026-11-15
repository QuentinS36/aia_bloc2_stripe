-- ============================================================
-- MPD (Modèle Physique de Données) - Système OLTP Stripe
-- SGBD cible : PostgreSQL 16+
-- Projet : Architecture de données Stripe - Bloc 2 RNCP38777
-- ============================================================
-- Règles de gestion portées par le schéma :
--  R1. Le moyen de paiement d'une transaction appartient au client de la transaction
--      (clé étrangère composite).
--  R2. Une transaction peut avoir plusieurs remboursements (partiels ou successifs) ;
--      la somme des remboursements non échoués ne peut pas dépasser le montant payé.
--  R3. Une transaction a au plus un chargeback (un litige par paiement).
--  R4. Aucune suppression en cascade sur l'historique financier (ON DELETE RESTRICT) :
--      le droit à l'effacement passe par l'anonymisation des données personnelles
--      (voir doc Security and Compliance Plan), pas par la suppression de lignes.
--  R5. transaction.status = 'refunded' uniquement quand les remboursements 'completed'
--      couvrent la totalité du montant ; un remboursement partiel laisse 'successful'.
-- ============================================================

-- Extension pour la génération d'UUID
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================
-- Tables de référence
-- ============================================================

CREATE TABLE currency (
    currency_code   CHAR(3)         PRIMARY KEY,        -- ISO 4217 (EUR, USD...)
    name            VARCHAR(50)     NOT NULL
);

CREATE TABLE device (
    device_id       UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    device_type     VARCHAR(30)     NOT NULL             -- mobile, desktop, tablet
);

CREATE TABLE location (
    location_id     UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    ip_address      INET            NOT NULL,
    country         CHAR(2)                              -- ISO 3166-1 alpha-2
);

-- ============================================================
-- Entités principales
-- ============================================================

CREATE TABLE merchant (
    merchant_id     UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    name            VARCHAR(120)    NOT NULL,
    country         CHAR(2)         NOT NULL,
    business_type   VARCHAR(50),
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT now()
);

CREATE TABLE customer (
    customer_id     UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    email           VARCHAR(255)    NOT NULL UNIQUE,
    country         CHAR(2),
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),
    anonymized_at   TIMESTAMPTZ                          -- renseigné par le DAG d'effacement RGPD
);

CREATE TABLE payment_method (
    payment_method_id  UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id        UUID         NOT NULL REFERENCES customer(customer_id) ON DELETE RESTRICT,
    type               VARCHAR(20)  NOT NULL,            -- card, bank_transfer, wallet
    last4              CHAR(4),
    created_at         TIMESTAMPTZ  NOT NULL DEFAULT now(),
    -- cible de la clé étrangère composite de transaction (règle R1)
    UNIQUE (payment_method_id, customer_id)
);

-- ============================================================
-- Table centrale : transaction
-- ============================================================

CREATE TABLE transaction (
    transaction_id      UUID           PRIMARY KEY DEFAULT gen_random_uuid(),
    merchant_id         UUID           NOT NULL REFERENCES merchant(merchant_id),
    customer_id         UUID           NOT NULL REFERENCES customer(customer_id),
    payment_method_id   UUID           NOT NULL,
    currency_code       CHAR(3)        NOT NULL REFERENCES currency(currency_code),
    device_id           UUID           REFERENCES device(device_id),
    location_id         UUID           REFERENCES location(location_id),
    amount              NUMERIC(14,2)  NOT NULL CHECK (amount > 0),            -- montant brut payé
    fee_amount          NUMERIC(14,2)  NOT NULL DEFAULT 0 CHECK (fee_amount >= 0), -- frais de traitement
    status              VARCHAR(20)    NOT NULL DEFAULT 'pending'
                            CHECK (status IN ('pending','successful','failed','refunded')),
    created_at          TIMESTAMPTZ    NOT NULL DEFAULT now(),
    CHECK (fee_amount <= amount),
    -- R1 : le moyen de paiement doit appartenir au client de la transaction
    FOREIGN KEY (payment_method_id, customer_id)
        REFERENCES payment_method (payment_method_id, customer_id)
);

-- ============================================================
-- Entités dépendantes de transaction
-- ============================================================

CREATE TABLE fraud_indicator (
    fraud_id          UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    transaction_id    UUID            NOT NULL REFERENCES transaction(transaction_id) ON DELETE RESTRICT,
    anomaly_score     NUMERIC(5,4)    NOT NULL CHECK (anomaly_score BETWEEN 0 AND 1),
    rule_triggered    VARCHAR(100),
    model_version     VARCHAR(50),                       -- version du modèle ML (NULL = règle métier seule)
    created_at        TIMESTAMPTZ     NOT NULL DEFAULT now()
);

CREATE TABLE refund (
    refund_id         UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    transaction_id    UUID            NOT NULL REFERENCES transaction(transaction_id) ON DELETE RESTRICT,
    amount            NUMERIC(14,2)   NOT NULL CHECK (amount > 0),
    status            VARCHAR(20)     NOT NULL DEFAULT 'pending'
                          CHECK (status IN ('pending','completed','failed')),
    created_at        TIMESTAMPTZ     NOT NULL DEFAULT now()
);

CREATE TABLE chargeback (
    chargeback_id     UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    transaction_id    UUID            NOT NULL UNIQUE REFERENCES transaction(transaction_id) ON DELETE RESTRICT,
    reason            VARCHAR(100),
    status            VARCHAR(20)     NOT NULL DEFAULT 'open'
                          CHECK (status IN ('open','won','lost')),
    created_at        TIMESTAMPTZ     NOT NULL DEFAULT now()
);

-- R2 : la somme des remboursements (hors échecs) ne dépasse pas le montant payé
CREATE FUNCTION check_refund_total() RETURNS trigger AS $$
DECLARE
    paid  NUMERIC(14,2);
    total NUMERIC(14,2);
BEGIN
    -- verrou sur la transaction : sérialise deux remboursements concurrents
    SELECT amount INTO paid FROM transaction WHERE transaction_id = NEW.transaction_id FOR UPDATE;
    SELECT COALESCE(SUM(amount), 0) INTO total
      FROM refund
     WHERE transaction_id = NEW.transaction_id
       AND status <> 'failed'
       AND refund_id <> NEW.refund_id;
    IF NEW.status <> 'failed' AND total + NEW.amount > paid THEN
        RAISE EXCEPTION 'Remboursements (%) supérieurs au montant payé (%) pour la transaction %',
            total + NEW.amount, paid, NEW.transaction_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_refund_total
    BEFORE INSERT OR UPDATE OF amount, status ON refund
    FOR EACH ROW EXECUTE FUNCTION check_refund_total();

-- ============================================================
-- Abonnements
-- ============================================================

CREATE TABLE subscription_plan (
    plan_id           UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    merchant_id       UUID            NOT NULL REFERENCES merchant(merchant_id),
    name              VARCHAR(120)    NOT NULL,
    amount            NUMERIC(14,2)   NOT NULL CHECK (amount > 0),
    currency_code     CHAR(3)         NOT NULL REFERENCES currency(currency_code),
    billing_interval  VARCHAR(20)     NOT NULL CHECK (billing_interval IN ('monthly','yearly'))
);

CREATE TABLE subscription (
    subscription_id   UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id       UUID            NOT NULL REFERENCES customer(customer_id),
    plan_id           UUID            NOT NULL REFERENCES subscription_plan(plan_id),
    status            VARCHAR(20)     NOT NULL DEFAULT 'active'
                          CHECK (status IN ('active','cancelled','past_due')),
    start_date        TIMESTAMPTZ     NOT NULL DEFAULT now()
);

-- ============================================================
-- Index de performance
-- (jointures fréquentes + requêtes analytiques/temporelles)
-- ============================================================

CREATE INDEX idx_transaction_merchant ON transaction(merchant_id);
CREATE INDEX idx_transaction_customer ON transaction(customer_id);
CREATE INDEX idx_transaction_payment_method ON transaction(payment_method_id, customer_id);
CREATE INDEX idx_transaction_created_at ON transaction(created_at);
CREATE INDEX idx_transaction_status ON transaction(status);
CREATE INDEX idx_payment_method_customer ON payment_method(customer_id);
CREATE INDEX idx_fraud_indicator_transaction ON fraud_indicator(transaction_id);
CREATE INDEX idx_refund_transaction ON refund(transaction_id);
CREATE INDEX idx_subscription_customer ON subscription(customer_id);
