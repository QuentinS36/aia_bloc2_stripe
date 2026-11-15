-- ============================================================
-- Requêtes SQL et NoSQL de démonstration - Stripe
-- Bloc 2 RNCP38777
-- Répond aux cas d'usage métier du cahier des charges :
-- 1. Analyse de revenus par marchand/période (OLAP)
-- 2. Détection d'anomalies/fraude (OLTP + OLAP + NoSQL)
-- 3. Segmentation client (NoSQL -> OLAP)
--
-- Conventions (cf. olap_schema.sql) :
--  * revenu = paiements encaissés (statut 'successful' ou 'refunded') ;
--  * net_amount = montant brut - remboursements - frais ;
--  * les montants sont toujours agrégés PAR DEVISE (pas de conversion).
--  * les identifiants "uuid-xxxx" des requêtes NoSQL sont des exemples fictifs.
-- ============================================================


-- ============================================================
-- A. ANALYSE DE REVENUS (OLAP - fact_transaction / dimensions)
-- ============================================================

-- A.1 Revenu quotidien par marchand et par devise sur les 30 derniers jours
-- (s'appuie sur la vue matérialisée de pré-agrégation, déjà filtrée sur les paiements encaissés)
SELECT
    d.full_date,
    a.merchant_name,
    a.currency_code,
    a.transaction_count,
    a.gross_amount,
    a.total_refunded,
    a.total_fees,
    a.total_net_revenue
FROM agg_revenue_daily_merchant a
JOIN dim_date d ON d.date_key = a.date_key
WHERE d.full_date >= CURRENT_DATE - INTERVAL '30 days'
ORDER BY d.full_date DESC, a.currency_code, a.total_net_revenue DESC;


-- A.2 Top 10 des marchands par revenu net, par devise, sur le dernier trimestre civil complet
-- (agrégation directe sur la table de faits, sans passer par la vue ;
--  ROW_NUMBER() par devise : un classement distinct pour chaque devise)
WITH ranked AS (
    SELECT
        cu.currency_code,
        m.name              AS merchant_name,
        m.segment,
        COUNT(*)            AS transaction_count,
        SUM(f.net_amount)   AS total_net_revenue,
        ROW_NUMBER() OVER (PARTITION BY cu.currency_code
                           ORDER BY SUM(f.net_amount) DESC) AS rank_in_currency
    FROM fact_transaction f
    JOIN dim_merchant m  ON m.merchant_key  = f.merchant_key
    JOIN dim_date d      ON d.date_key      = f.date_key
    JOIN dim_currency cu ON cu.currency_key = f.currency_key
    JOIN dim_status s    ON s.status_key    = f.status_key
    WHERE s.label IN ('successful', 'refunded')
      AND d.full_date >= date_trunc('quarter', CURRENT_DATE) - INTERVAL '3 months'
      AND d.full_date <  date_trunc('quarter', CURRENT_DATE)
    GROUP BY cu.currency_code, m.name, m.segment
)
SELECT currency_code, rank_in_currency, merchant_name, segment, transaction_count, total_net_revenue
FROM ranked
WHERE rank_in_currency <= 10
ORDER BY currency_code, rank_in_currency;


-- A.3 Tendance mensuelle du revenu net par segment de marchand et par devise
-- (utile pour un dashboard direction : évolution dans le temps)
SELECT
    d.year,
    d.month,
    cu.currency_code,
    m.segment,
    SUM(f.net_amount) AS monthly_net_revenue
FROM fact_transaction f
JOIN dim_merchant m  ON m.merchant_key  = f.merchant_key
JOIN dim_date d      ON d.date_key      = f.date_key
JOIN dim_currency cu ON cu.currency_key = f.currency_key
JOIN dim_status s    ON s.status_key    = f.status_key
WHERE s.label IN ('successful', 'refunded')
GROUP BY d.year, d.month, cu.currency_code, m.segment
ORDER BY d.year, d.month, cu.currency_code, m.segment;


-- ============================================================
-- B. DÉTECTION DE FRAUDE (OLTP + OLAP + NoSQL)
-- ============================================================

-- B.1 [OLTP] Transactions à risque élevé sur les dernières 24h
-- (score au-dessus du seuil ; model_version permet de savoir quel modèle a décidé)
SELECT
    t.transaction_id,
    t.amount,
    t.currency_code,
    t.status,
    t.created_at,
    fi.anomaly_score,
    fi.rule_triggered,
    fi.model_version
FROM transaction t
JOIN fraud_indicator fi ON fi.transaction_id = t.transaction_id
WHERE t.created_at >= now() - INTERVAL '24 hours'
  AND fi.anomaly_score >= 0.80
ORDER BY fi.anomaly_score DESC;


-- B.2 [OLAP] Taux de fraude quotidien par pays
-- (vue de pré-agrégation dédiée ; calculée sur toutes les transactions scorées,
--  y compris refusées, puisque la fraude se détecte aussi sur les tentatives échouées)
SELECT
    d.full_date,
    a.country,
    a.transaction_count,
    a.fraud_count,
    a.fraud_rate,
    a.avg_fraud_score
FROM agg_fraud_daily a
JOIN dim_date d ON d.date_key = a.date_key
WHERE d.full_date >= CURRENT_DATE - INTERVAL '14 days'
ORDER BY d.full_date DESC, a.fraud_rate DESC;


-- B.3 [NoSQL - MongoDB] Corrélation : logs d'erreur associés
-- à une transaction flaguée comme frauduleuse (investigation)
-- (l'identifiant est un exemple : à remplacer par un transaction_id issu de B.1)
db.log_events.find({
  transaction_id: "uuid-1234",
  level: { $in: ["error", "warning"] }
}).sort({ timestamp: -1 }).limit(50);


-- B.4 [NoSQL - MongoDB] Nombre d'événements de log par service
-- sur la dernière heure, pour détecter une anomalie technique
-- corrélée à un pic de fraude (ex. panne du service anti-fraude)
db.log_events.aggregate([
  { $match: { timestamp: { $gte: new Date(Date.now() - 60 * 60 * 1000) } } },
  { $group: { _id: "$service", event_count: { $sum: 1 } } },
  { $sort: { event_count: -1 } }
]);


-- ============================================================
-- C. SEGMENTATION CLIENT (NoSQL -> OLAP)
-- ============================================================

-- C.1 [OLAP] Clients actifs et dépense par segment, par mois et par devise
-- (paiements encaissés uniquement ; dépense brute et nette)
SELECT
    d.year,
    d.month,
    c.segment,
    cu.currency_code,
    COUNT(DISTINCT f.customer_key) AS active_customers,
    SUM(f.amount)                  AS total_spend,
    SUM(f.net_amount)              AS total_net,
    ROUND(AVG(f.amount), 2)        AS avg_transaction_amount
FROM fact_transaction f
JOIN dim_date d      ON d.date_key      = f.date_key
JOIN dim_customer c  ON c.customer_key  = f.customer_key
JOIN dim_currency cu ON cu.currency_key = f.currency_key
JOIN dim_status s    ON s.status_key    = f.status_key
WHERE s.label IN ('successful', 'refunded')
GROUP BY d.year, d.month, c.segment, cu.currency_code
ORDER BY d.year, d.month, cu.currency_code, total_spend DESC;


-- C.2 [NoSQL - MongoDB] Intensité d'usage par client
-- (nombre de sessions et moyenne d'événements par session sur 30 jours)
-- -> alimente la segmentation comportementale en amont de l'OLAP
db.user_sessions.aggregate([
  { $match: { session_start: { $gte: new Date(Date.now() - 30 * 24 * 60 * 60 * 1000) } } },
  { $project: {
      customer_id: 1,
      event_count: { $size: "$events" }
  }},
  { $group: {
      _id: "$customer_id",
      session_count: { $sum: 1 },
      avg_events_per_session: { $avg: "$event_count" }
  }},
  { $sort: { session_count: -1 } }
]);


-- C.3 [NoSQL - MongoDB] Dernière version des features ML
-- disponible pour un client donné (utilisé par le service de scoring
-- et par les analyses de personnalisation)
db.ml_features.find({
  entity_type: "customer",
  entity_id: "uuid-5678"
}).sort({ computed_at: -1 }).limit(1);


-- C.4 [Cas d'usage croisé] Clients à forte valeur (OLAP) ayant
-- laissé un retour négatif récent (NoSQL) : liste à transmettre
-- à l'équipe relation client pour action prioritaire.
--
-- Étape 1 - identifier les clients à forte valeur (OLAP), en EUR, paiements encaissés :
SELECT c.customer_id, SUM(f.amount) AS total_spend_eur
FROM fact_transaction f
JOIN dim_customer c  ON c.customer_key  = f.customer_key
JOIN dim_date d      ON d.date_key      = f.date_key
JOIN dim_currency cu ON cu.currency_key = f.currency_key
JOIN dim_status s    ON s.status_key    = f.status_key
WHERE d.full_date >= CURRENT_DATE - INTERVAL '90 days'
  AND cu.currency_code = 'EUR'
  AND s.label IN ('successful', 'refunded')
GROUP BY c.customer_id
HAVING SUM(f.amount) > 5000
ORDER BY total_spend_eur DESC;

-- Étape 2 - croiser avec les retours négatifs récents (NoSQL),
-- à partir de la liste de customer_id obtenue à l'étape 1
-- (identifiants d'exemple ; dans le pipeline, la liste est passée par le DAG) :
db.customer_feedback.find({
  customer_id: { $in: ["uuid-5678", "uuid-9012"] },
  rating: { $lte: 2 },
  submitted_at: { $gte: new Date(Date.now() - 30 * 24 * 60 * 60 * 1000) }
});
