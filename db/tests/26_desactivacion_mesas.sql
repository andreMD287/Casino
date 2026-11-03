-- Regresion de desactivacion con asignaciones futuras/vigentes y preservacion historica.
-- Se prueba sobre la instalacion de las semillas; todo se revierte.
\set ON_ERROR_STOP 1
SET client_min_messages = notice;
SET search_path = casino, public;
BEGIN;

CREATE FUNCTION pg_temp.ok26(p_nombre text, p_cond boolean) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  IF NOT coalesce(p_cond, false) THEN RAISE EXCEPTION 'FALLO prueba: %', p_nombre; END IF;
  RAISE NOTICE '[OK] %', p_nombre;
END $$;

CREATE FUNCTION pg_temp.error26(p_nombre text, p_codigo text, p_sql text) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE v_estado text;
BEGIN
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_estado = RETURNED_SQLSTATE;
    IF v_estado = p_codigo THEN
      RAISE NOTICE '[OK] %', p_nombre;
      RETURN;
    END IF;
    RAISE EXCEPTION 'FALLO prueba: %; esperado %, recibido %', p_nombre, p_codigo, v_estado;
  END;
  RAISE EXCEPTION 'FALLO prueba: %; no hubo error %', p_nombre, p_codigo;
END $$;

DO $$
DECLARE
  v_ruleta bigint;
  v_admin bigint;
  v_mesa bigint;
  v_jornada_futura bigint;
  v_turno_futuro bigint;
  v_asignacion_futura bigint;
  v_jornada_pasada bigint;
  v_turno_pasado bigint;
  v_asignacion_pasada bigint;
  v_crupier bigint;
  v_supervisor bigint;
BEGIN
  SELECT id INTO STRICT v_admin FROM usuarios WHERE usuario = 'admin';
  PERFORM set_config('app.usuario_id', v_admin::text, true);
  SELECT id INTO STRICT v_ruleta FROM juegos WHERE nombre = 'Ruleta';
  SELECT e.id INTO STRICT v_crupier FROM empleados e
    JOIN usuarios u ON u.id = e.usuario_id WHERE u.usuario = 'crupier1';
  SELECT e.id INTO STRICT v_supervisor FROM empleados e
    JOIN usuarios u ON u.id = e.usuario_id WHERE u.usuario = 'supervisor2';

  v_mesa := fn_crear_mesa('QA26-DESACTIVACION', v_ruleta, 1000, 50000);
  v_jornada_futura := fn_crear_jornada(DATE '2099-08-14');
  v_turno_futuro := fn_crear_turno(v_jornada_futura,
    '2099-08-14 08:00:00-05'::timestamptz,
    '2099-08-14 09:00:00-05'::timestamptz);
  v_asignacion_futura := fn_crear_asignacion(v_turno_futuro, v_mesa, v_crupier, v_supervisor);
  PERFORM pg_temp.ok26('Mesa activa con asignacion futura valida',
    EXISTS (SELECT 1 FROM mesas WHERE id=v_mesa AND activa) AND
    EXISTS (SELECT 1 FROM asignaciones WHERE id=v_asignacion_futura));

  PERFORM pg_temp.error26('Desactivar con asignacion futura bloqueado (CA125)', 'CA125',
    format('SELECT casino.fn_desactivar_mesa(%s)', v_mesa));
  PERFORM pg_temp.ok26('Rechazo conserva mesa activa y asignacion futura',
    EXISTS (SELECT 1 FROM mesas WHERE id=v_mesa AND activa) AND
    EXISTS (SELECT 1 FROM asignaciones WHERE id=v_asignacion_futura));
  PERFORM pg_temp.error26('UPDATE directo de activa bloqueado (CA125)', 'CA125',
    format('UPDATE casino.mesas SET activa=false WHERE id=%s', v_mesa));

  PERFORM fn_eliminar_asignacion(v_asignacion_futura);
  PERFORM pg_temp.ok26('La asignacion futura se puede eliminar sin rondas',
    NOT EXISTS (SELECT 1 FROM asignaciones WHERE id=v_asignacion_futura));

  v_jornada_pasada := fn_crear_jornada(DATE '2025-01-16');
  v_turno_pasado := fn_crear_turno(v_jornada_pasada,
    '2025-01-16 08:00:00-05'::timestamptz,
    '2025-01-16 09:00:00-05'::timestamptz);
  v_asignacion_pasada := fn_crear_asignacion(v_turno_pasado, v_mesa, v_crupier, v_supervisor);
  PERFORM fn_desactivar_mesa(v_mesa);
  PERFORM pg_temp.ok26('Asignacion historica permite desactivar la mesa',
    EXISTS (SELECT 1 FROM mesas WHERE id=v_mesa AND NOT activa));
  PERFORM pg_temp.ok26('Asignacion historica se conserva tras desactivar',
    EXISTS (SELECT 1 FROM asignaciones WHERE id=v_asignacion_pasada AND mesa_id=v_mesa));
  PERFORM pg_temp.error26('Mesa inactiva rechaza nuevas asignaciones (CA112)', 'CA112',
    format('SELECT casino.fn_crear_asignacion(%s,%s,%s,%s)',
      v_turno_futuro, v_mesa, v_crupier, v_supervisor));
END $$;

ROLLBACK;
