CREATE OR REPLACE FUNCTION fail() 
RETURNS VOID AS 
$$
BEGIN 
RAISE EXCEPTION 'FAIL'; 
END; 
$$ language plpgsql;

CREATE OR REPLACE FUNCTION pass() 
RETURNS VOID AS 
$$
BEGIN 
NULL; 
END; 
$$ language plpgsql;
