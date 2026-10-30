-- 50_permisos_auditoria.sql (André) — dueño de los objetos, permisos mínimos y auditoría.
-- Se ejecuta después de todos los archivos de esquema y funciones (00–40).
SET ROLE casino_owner;
SET search_path = casino, public;

-- ===========================================================================
-- 1. Dueño de los objetos: casino_owner (cambiar de dueño exige superusuario).
-- ===========================================================================
RESET ROLE;
DO $$
DECLARE
  o record;
BEGIN
  FOR o IN
    SELECT c.relname AS nombre,
           CASE c.relkind WHEN 'r' THEN 'TABLE' WHEN 'p' THEN 'TABLE' WHEN 'v' THEN 'VIEW'
                          WHEN 'm' THEN 'MATERIALIZED VIEW' WHEN 'S' THEN 'SEQUENCE' END AS tipo
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'casino' AND c.relkind IN ('r', 'p', 'v', 'm', 'S')
      AND pg_get_userbyid(c.relowner) <> 'casino_owner'
      AND NOT (c.relkind = 'S' AND EXISTS (SELECT 1 FROM pg_depend d WHERE d.objid = c.oid AND d.deptype = 'i'))
  LOOP
    EXECUTE format('ALTER %s casino.%I OWNER TO casino_owner', o.tipo, o.nombre);
  END LOOP;

  FOR o IN
    SELECT p.oid::regprocedure AS firma
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'casino' AND pg_get_userbyid(p.proowner) <> 'casino_owner'
  LOOP
    EXECUTE format('ALTER ROUTINE %s OWNER TO casino_owner', o.firma);
  END LOOP;
END
$$;
SET ROLE casino_owner;

-- ===========================================================================
-- 2. Permisos de casino_app (el rol con el que conecta Next.js)
-- ===========================================================================
REVOKE ALL ON ALL TABLES IN SCHEMA casino FROM PUBLIC, casino_app, casino_lectura;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA casino FROM PUBLIC, casino_app, casino_lectura;
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA casino FROM PUBLIC;

GRANT USAGE ON SCHEMA casino TO casino_app, casino_lectura;

-- EXECUTE solo sobre las funciones públicas que usa la app (lista explícita).
-- Se otorga a todas las sobrecargas del nombre; si una función aún no existe, se avisa y se sigue.
-- Las internas (fn_crear_usuario, fn_mover_saldo, fn_crupier_asignado, fn_puede_apostar,
-- fn_evaluar_riesgo, fn_preparar_apuesta, fn_ronda_para_operar, ...) NO van aquí.
DO $$
DECLARE
  v_nombre text;
  v_firma regprocedure;
  v_encontrada boolean;
  v_publicas text[] := ARRAY[
    -- Apoyo de vistas (las vistas llaman funciones con los permisos de quien consulta)
    'fn_actor', 'fn_motivo_no_apuesta',
    -- Autenticación (André)
    'fn_srp_datos_login', 'fn_guardar_desafio', 'fn_consumir_desafio', 'fn_marcar_desafio',
    'fn_crear_sesion', 'fn_obtener_sesion', 'fn_cerrar_sesion', 'fn_registrar_jugador',
    -- Rondas y apuestas (André)
    'fn_abrir_ronda', 'fn_cerrar_ronda', 'fn_anular_ronda',
    'fn_registrar_apuesta', 'fn_registrar_apuesta_resuelta', 'fn_anular_apuesta',
    'fn_crear_opcion', 'fn_actualizar_opcion', 'fn_desactivar_opcion'
    -- Personal, mesas, riesgo e historial (Andrés): se agregan aquí a pedido suyo.
  ];
BEGIN
  FOREACH v_nombre IN ARRAY v_publicas LOOP
    v_encontrada := false;
    FOR v_firma IN
      SELECT p.oid::regprocedure FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'casino' AND p.proname = v_nombre
    LOOP
      EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO casino_app', v_firma);
      v_encontrada := true;
    END LOOP;
    IF NOT v_encontrada THEN
      RAISE NOTICE 'Aviso: la función pública % todavía no existe; no se otorgó EXECUTE', v_nombre;
    END IF;
  END LOOP;
END
$$;

-- SELECT en todas las vistas v_*.
DO $$
DECLARE
  v record;
BEGIN
  FOR v IN SELECT viewname FROM pg_views WHERE schemaname = 'casino' AND viewname LIKE 'v\_%' LOOP
    EXECUTE format('GRANT SELECT ON casino.%I TO casino_app', v.viewname);
  END LOOP;
END
$$;

-- ===========================================================================
-- 3. Permisos de casino_lectura (reportes)
-- ===========================================================================
DO $$
DECLARE
  v_vista text;
BEGIN
  FOREACH v_vista IN ARRAY ARRAY['v_reporte_mesa_turno', 'v_rondas', 'v_apuestas', 'v_opciones'] LOOP
    IF to_regclass('casino.' || v_vista) IS NOT NULL THEN
      EXECUTE format('GRANT SELECT ON casino.%I TO casino_lectura', v_vista);
    END IF;
  END LOOP;
END
$$;

-- ===========================================================================
-- 4. Auditoría: trigger genérico que escribe en auditoria.
-- ===========================================================================
CREATE OR REPLACE FUNCTION tg_auditar() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = casino, pg_temp AS $$
DECLARE
  v_fila jsonb := CASE WHEN TG_OP = 'DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END;
BEGIN
  INSERT INTO auditoria (tabla, operacion, registro_id, usuario_id, datos)
  VALUES (
    TG_TABLE_NAME,
    TG_OP,
    (v_fila ->> 'id')::bigint,
    nullif(current_setting('app.usuario_id', true), '')::bigint,   -- tolera que no haya actor (semillas)
    CASE TG_OP
      WHEN 'INSERT' THEN to_jsonb(NEW)
      WHEN 'DELETE' THEN to_jsonb(OLD)
      ELSE jsonb_build_object('antes', to_jsonb(OLD), 'despues', to_jsonb(NEW))
    END
  );
  RETURN NULL;   -- AFTER trigger
END
$$;
REVOKE EXECUTE ON FUNCTION tg_auditar() FROM PUBLIC;

DO $$
DECLARE
  v_tabla text;
BEGIN
  FOREACH v_tabla IN ARRAY ARRAY['empleados', 'mesas', 'asignaciones', 'conceptos', 'jugadores', 'suspensiones',
                                 'investigaciones', 'abonos_empleado', 'opciones_apuesta', 'rondas'] LOOP
    EXECUTE format('CREATE OR REPLACE TRIGGER tr_auditoria AFTER INSERT OR UPDATE OR DELETE ON casino.%I '
                   'FOR EACH ROW EXECUTE FUNCTION casino.tg_auditar()', v_tabla);
  END LOOP;
END
$$;
