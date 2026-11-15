-- Tests d'intégrité OLTP : chaque règle doit REFUSER l'opération invalide.
-- À exécuter après oltp_schema.sql + seed_oltp.sql :  psql -d oltp -f test_integrity_oltp.sql
DO $$
DECLARE ok BOOLEAN;
BEGIN
  -- R1 : moyen de paiement d'un autre client
  ok := FALSE;
  BEGIN
    INSERT INTO transaction (merchant_id, customer_id, payment_method_id, currency_code, amount)
    VALUES ('a0000000-0000-0000-0000-000000000001','c0000000-0000-0000-0000-000000000001',
            'b0000000-0000-0000-0000-000000000002','EUR',10);
  EXCEPTION WHEN foreign_key_violation THEN ok := TRUE; END;
  IF NOT ok THEN RAISE EXCEPTION 'ECHEC R1 : moyen de paiement d''un autre client accepté'; END IF;
  RAISE NOTICE 'OK  R1 : le moyen de paiement doit appartenir au client';

  -- R2 : surremboursement (100 payés, 50 déjà remboursés dans le seed)
  ok := FALSE;
  BEGIN
    INSERT INTO refund (transaction_id, amount, status)
    VALUES ('f0000000-0000-0000-0000-000000000001', 60, 'completed');
  EXCEPTION WHEN raise_exception THEN ok := TRUE; END;
  IF NOT ok THEN RAISE EXCEPTION 'ECHEC R2 : surremboursement accepté'; END IF;
  RAISE NOTICE 'OK  R2 : remboursements cumulés <= montant payé';

  -- R3 : second chargeback sur la même transaction
  ok := FALSE;
  BEGIN
    INSERT INTO chargeback (transaction_id) VALUES ('f0000000-0000-0000-0000-000000000002');
  EXCEPTION WHEN unique_violation THEN ok := TRUE; END;
  IF NOT ok THEN RAISE EXCEPTION 'ECHEC R3 : second chargeback accepté'; END IF;
  RAISE NOTICE 'OK  R3 : un seul chargeback par transaction';

  -- R4 : suppression d'une transaction qui a un historique de fraude
  ok := FALSE;
  BEGIN
    DELETE FROM transaction WHERE transaction_id = 'f0000000-0000-0000-0000-000000000003';
  EXCEPTION WHEN foreign_key_violation THEN ok := TRUE; END;
  IF NOT ok THEN RAISE EXCEPTION 'ECHEC R4 : suppression en cascade possible'; END IF;
  RAISE NOTICE 'OK  R4 : pas de suppression en cascade de l''historique financier';
END $$;
