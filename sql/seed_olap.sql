-- Jeu de données synthétique minimal - OLAP (à charger après olap_schema.sql)
-- Dimensions de base
INSERT INTO dim_date
SELECT to_char(d,'YYYYMMDD')::int, d, EXTRACT(isodow FROM d), EXTRACT(month FROM d),
       EXTRACT(quarter FROM d), EXTRACT(year FROM d), EXTRACT(isodow FROM d) >= 6
FROM generate_series(CURRENT_DATE - 200, CURRENT_DATE, interval '1 day') AS g(d);

INSERT INTO dim_currency (currency_code) VALUES ('EUR'), ('USD');
INSERT INTO dim_payment_method (type) VALUES ('card'), ('bank_transfer');
INSERT INTO dim_location (country, region) VALUES ('FR','EU'), ('US','NA');
INSERT INTO dim_merchant (merchant_id, name, country, segment) VALUES
  ('a0000000-0000-0000-0000-000000000001','Boulangerie Dupont','FR','retail'),
  ('a0000000-0000-0000-0000-000000000002','CloudSoft Inc','US','saas');
INSERT INTO dim_customer (customer_id, segment, country) VALUES
  ('c0000000-0000-0000-0000-000000000001','premium','FR'),
  ('c0000000-0000-0000-0000-000000000002','standard','US');

-- Faits : net_amount = amount - refunded_amount - fee_amount (contrainte CHECK)
INSERT INTO fact_transaction
  (transaction_id, date_key, merchant_key, customer_key, payment_method_key, currency_key,
   location_key, status_key, amount, fee_amount, refunded_amount, net_amount, fraud_score, is_fraud, is_chargeback)
SELECT t.id, to_char(CURRENT_DATE - t.ago,'YYYYMMDD')::int, t.mk, t.ck, 1, t.cu, t.lk,
       (SELECT status_key FROM dim_status WHERE label = t.st),
       t.amt, t.fee, t.ref, t.amt - t.ref - t.fee, t.fs, t.fr, t.cb
FROM (VALUES
  ('f0000000-0000-0000-0000-000000000001'::uuid, 5, 1, 1, 1, 1, 'refunded',   100.00, 3.20, 50.00, 0.0300::numeric, false, false),
  ('f0000000-0000-0000-0000-000000000002'::uuid, 5, 2, 2, 2, 2, 'successful', 250.00, 7.55,  0.00, 0.1200::numeric, false, true),
  ('f0000000-0000-0000-0000-000000000003'::uuid, 4, 1, 1, 1, 1, 'failed',      40.00, 0.00,  0.00, 0.9120::numeric, true,  false),
  ('f0000000-0000-0000-0000-000000000004'::uuid, 3, 1, 1, 1, 1, 'successful', 6000.00, 90.00, 0.00, 0.0500::numeric, false, false),
  ('f0000000-0000-0000-0000-000000000005'::uuid, 120, 1, 1, 1, 1, 'successful', 80.00, 2.00, 0.00, 0.0100::numeric, false, false)
) AS t(id, ago, mk, ck, cu, lk, st, amt, fee, ref, fs, fr, cb);
