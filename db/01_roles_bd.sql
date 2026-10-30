-- 01_roles_bd.sql (André) — roles del clúster y schema. Idempotente: los roles son globales.
-- Uso: psql -v app_password=... -f 01_roles_bd.sql   (lo hace run_all.sh)

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'casino_owner') THEN
    CREATE ROLE casino_owner NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'casino_lectura') THEN
    CREATE ROLE casino_lectura NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'casino_app') THEN
    CREATE ROLE casino_app LOGIN;
  END IF;
END
$$;

-- La clave llega como variable de psql. Las variables no se expanden dentro de $$,
-- así que se pasa por un parámetro de sesión y se aplica con format(%L).
SELECT set_config('casino.app_password', :'app_password', false) AS _ignorar \gset
DO $$
BEGIN
  EXECUTE format('ALTER ROLE casino_app WITH LOGIN PASSWORD %L', current_setting('casino.app_password'));
END
$$;
RESET casino.app_password;

CREATE SCHEMA casino AUTHORIZATION casino_owner;
REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE CREATE ON SCHEMA casino FROM PUBLIC;
REVOKE ALL ON DATABASE casino FROM PUBLIC;
GRANT CONNECT ON DATABASE casino TO casino_app, casino_lectura;
ALTER DATABASE casino SET timezone = 'America/Bogota';
