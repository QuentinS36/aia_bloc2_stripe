-- Tests d'intégrité OLAP : les contraintes de cohérence financière doivent refuser les lignes invalides.
-- À exécuter après olap_schema.sql + seed_olap.sql :  psql -d olap -f test_integrity_olap.sql
DO $$
DECLARE ok BOOLEAN; dk INT := to_char(CURRENT_DATE,'YYYYMMDD')::int;
BEGIN
  ok := FALSE;
  BEGIN
    INSERT INTO fact_transaction (transaction_id,date_key,merchant_key,customer_key,payment_method_key,
                                  currency_key,status_key,amount,fee_amount,net_amount)
    VALUES (gen_random_uuid(),dk,1,1,1,1,2,100,3,100);   -- net devrait valoir 97
  EXCEPTION WHEN check_violation THEN ok := TRUE; END;
  IF NOT ok THEN RAISE EXCEPTION 'ECHEC : net_amount incohérent accepté'; END IF;
  RAISE NOTICE 'OK  net_amount = amount - refunded_amount - fee_amount';

  ok := FALSE;
  BEGIN
    INSERT INTO fact_transaction (transaction_id,date_key,merchant_key,customer_key,payment_method_key,
                                  currency_key,status_key,amount,refunded_amount,net_amount)
    VALUES (gen_random_uuid(),dk,1,1,1,1,2,100,150,-50);
  EXCEPTION WHEN check_violation THEN ok := TRUE; END;
  IF NOT ok THEN RAISE EXCEPTION 'ECHEC : remboursement supérieur au brut accepté'; END IF;
  RAISE NOTICE 'OK  refunded_amount <= amount';

  -- Cohérence vue / faits : la vue de revenu ne compte que les paiements encaissés
  IF (SELECT COALESCE(SUM(transaction_count),0) FROM agg_revenue_daily_merchant)
     <> (SELECT COUNT(*) FROM fact_transaction f JOIN dim_status s ON s.status_key = f.status_key
          WHERE s.label IN ('successful','refunded')) THEN
    RAISE EXCEPTION 'ECHEC : la vue de revenu ne correspond pas aux paiements encaissés (rafraîchir les vues ?)';
  END IF;
  RAISE NOTICE 'OK  la vue de revenu exclut les transactions pending/failed';
END $$;
