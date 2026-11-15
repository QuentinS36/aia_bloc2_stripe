-- Jeu de données synthétique minimal - OLTP (à charger après oltp_schema.sql)
INSERT INTO currency VALUES ('EUR','Euro'), ('USD','Dollar américain');
INSERT INTO device (device_id, device_type) VALUES
  ('d0000000-0000-0000-0000-000000000001','mobile'),
  ('d0000000-0000-0000-0000-000000000002','desktop');
INSERT INTO location (location_id, ip_address, country) VALUES
  ('10000000-0000-0000-0000-000000000001','203.0.113.10','FR'),
  ('10000000-0000-0000-0000-000000000002','198.51.100.7','US');
INSERT INTO merchant (merchant_id, name, country, business_type) VALUES
  ('a0000000-0000-0000-0000-000000000001','Boulangerie Dupont','FR','retail'),
  ('a0000000-0000-0000-0000-000000000002','CloudSoft Inc','US','saas');
INSERT INTO customer (customer_id, email, country) VALUES
  ('c0000000-0000-0000-0000-000000000001','alice@example.org','FR'),
  ('c0000000-0000-0000-0000-000000000002','bob@example.org','US');
INSERT INTO payment_method (payment_method_id, customer_id, type, last4) VALUES
  ('b0000000-0000-0000-0000-000000000001','c0000000-0000-0000-0000-000000000001','card','4242'),
  ('b0000000-0000-0000-0000-000000000002','c0000000-0000-0000-0000-000000000002','card','1881');
INSERT INTO transaction (transaction_id, merchant_id, customer_id, payment_method_id, currency_code, device_id, location_id, amount, fee_amount, status) VALUES
  ('f0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','c0000000-0000-0000-0000-000000000001','b0000000-0000-0000-0000-000000000001','EUR','d0000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001',100.00,3.20,'successful'),
  ('f0000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000002','c0000000-0000-0000-0000-000000000002','b0000000-0000-0000-0000-000000000002','USD','d0000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000002',250.00,7.55,'successful'),
  ('f0000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000001','c0000000-0000-0000-0000-000000000001','b0000000-0000-0000-0000-000000000001','EUR',NULL,NULL,40.00,0,'failed');
INSERT INTO fraud_indicator (transaction_id, anomaly_score, rule_triggered, model_version) VALUES
  ('f0000000-0000-0000-0000-000000000003',0.9120,'velocity_check','fraud-gbm-v3'),
  ('f0000000-0000-0000-0000-000000000001',0.0300,NULL,'fraud-gbm-v3');
-- Deux remboursements partiels successifs sur la même transaction (règle R2)
INSERT INTO refund (transaction_id, amount, status) VALUES
  ('f0000000-0000-0000-0000-000000000001',30.00,'completed'),
  ('f0000000-0000-0000-0000-000000000001',20.00,'completed');
INSERT INTO chargeback (transaction_id, reason, status) VALUES
  ('f0000000-0000-0000-0000-000000000002','fraudulent','open');
