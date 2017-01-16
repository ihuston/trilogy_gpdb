CREATE OR REPLACE FUNCTION VALIDATE_BALANCE(
  V_CLIENT_ID INT) RETURNS BOOL AS $$
DECLARE
  IS_VALID BOOLEAN;
BEGIN
  SELECT CASE C.BALANCE - COALESCE(SUM(T.VALUE), '0') WHEN '0' THEN TRUE ELSE FALSE END INTO IS_VALID
    FROM CLIENTS C LEFT JOIN TRANSACTIONS T ON T.ID_CLIENT=C.ID WHERE C.ID=V_CLIENT_ID GROUP BY C.ID, C.BALANCE;
  RETURN IS_VALID;
END;
$$ LANGUAGE plpgsql;
