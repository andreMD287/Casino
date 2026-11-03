-- Regresion: el juego de una mesa no cambia cuando existen rondas o asignaciones.
-- Fixture propio y transaccion revertida; no altera datos al finalizar.
\set ON_ERROR_STOP 1
SET client_min_messages = notice;
SET search_path = casino, public;
BEGIN;

CREATE FUNCTION pg_temp.verificar25(p_descripcion text, p_valido boolean) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  IF NOT coalesce(p_valido, false) THEN
    RAISE EXCEPTION 'FALLO prueba: %', p_descripcion;
  END IF;
  RAISE NOTICE '[OK] %', p_descripcion;
END $$;

CREATE FUNCTION pg_temp.error25(p_descripcion text, p_codigo text, p_sql text) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE v_codigo text;
BEGIN
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_codigo = RETURNED_SQLSTATE;
    IF v_codigo = p_codigo THEN
      RAISE NOTICE '[OK] %', p_descripcion;
      RETURN;
    END IF;
    RAISE EXCEPTION 'FALLO prueba: %; esperado %, recibido %', p_descripcion, p_codigo, v_codigo;
  END;
  RAISE EXCEPTION 'FALLO prueba: %; no se produjo %', p_descripcion, p_codigo;
END $$;

DO $$
DECLARE
  v_ruleta bigint;
  v_blackjack bigint;
  v_admin bigint;
  v_crupier bigint;
  v_supervisor bigint;
  v_mesa bigint;
  v_jornada bigint;
  v_turno bigint;
  v_asignacion bigint;
BEGIN
  SELECT id INTO STRICT v_admin FROM usuarios WHERE usuario = 'admin';
  PERFORM set_config('app.usuario_id', v_admin::text, true);
  SELECT id INTO STRICT v_ruleta FROM juegos WHERE nombre = 'Ruleta';
  SELECT id INTO STRICT v_blackjack FROM juegos WHERE nombre = 'Blackjack';
  SELECT e.id INTO STRICT v_crupier
    FROM empleados e JOIN usuarios u ON u.id = e.usuario_id
   WHERE u.usuario = 'crupier1';
  SELECT e.id INTO STRICT v_supervisor
    FROM empleados e JOIN usuarios u ON u.id = e.usuario_id
   WHERE u.usuario = 'supervisor2';

  v_mesa := fn_crear_mesa('QA25-INTEGRIDAD-MESA', v_ruleta, 1000, 90000);
  PERFORM pg_temp.verificar25('Crear mesa persiste juego, limites y estado activo',
    EXISTS (SELECT 1 FROM mesas WHERE id = v_mesa AND juego_id = v_ruleta
      AND monto_minimo = 1000 AND monto_maximo = 90000 AND activa));

  PERFORM pg_temp.error25('Codigo de mesa duplicado se rechaza (CA103)', 'CA103',
    format('SELECT casino.fn_crear_mesa(%L, %s, 1000, 90000)', 'QA25-INTEGRIDAD-MESA', v_ruleta));
  PERFORM pg_temp.error25('Mesa con minimo cero se rechaza (CA103)', 'CA103',
    format('SELECT casino.fn_crear_mesa(%L, %s, 0, 90000)', 'QA25-MIN-INVALIDO', v_ruleta));

  PERFORM fn_actualizar_mesa(v_mesa, 'QA25-INTEGRIDAD-MESA', v_blackjack, 2000, 80000);
  PERFORM pg_temp.verificar25('Se puede cambiar el juego si no hay rondas ni asignaciones',
    EXISTS (SELECT 1 FROM mesas WHERE id = v_mesa AND juego_id = v_blackjack
      AND monto_minimo = 2000 AND monto_maximo = 80000));
  PERFORM fn_actualizar_mesa(v_mesa, 'QA25-INTEGRIDAD-MESA', v_ruleta, 1000, 90000);

  v_jornada := fn_crear_jornada(DATE '2099-08-13');
  v_turno := fn_crear_turno(v_jornada,
    '2099-08-13 08:00:00-05'::timestamptz,
    '2099-08-13 09:00:00-05'::timestamptz);
  v_asignacion := fn_crear_asignacion(v_turno, v_mesa, v_crupier, v_supervisor);
  PERFORM pg_temp.verificar25('La mesa admite asignacion con competencias correctas',
    EXISTS (SELECT 1 FROM asignaciones WHERE id = v_asignacion
      AND mesa_id = v_mesa AND crupier_id = v_crupier AND supervisor_id = v_supervisor));

  PERFORM pg_temp.error25('Cambio de juego con asignacion sin rondas bloqueado (CA124)', 'CA124',
    format('SELECT casino.fn_actualizar_mesa(%s, %L, %s, 1000, 90000)',
      v_mesa, 'QA25-INTEGRIDAD-MESA', v_blackjack));
  PERFORM pg_temp.verificar25('Rechazo conserva el juego original y la asignacion',
    EXISTS (SELECT 1 FROM mesas WHERE id = v_mesa AND juego_id = v_ruleta)
    AND EXISTS (SELECT 1 FROM asignaciones WHERE id = v_asignacion));

  PERFORM pg_temp.error25('UPDATE directo de juego tambien bloqueado por trigger (CA124)', 'CA124',
    format('UPDATE casino.mesas SET juego_id = %s WHERE id = %s', v_blackjack, v_mesa));

  PERFORM fn_actualizar_mesa(v_mesa, 'QA25-MESA-ACTUALIZADA', v_ruleta, 1500, 70000);
  PERFORM pg_temp.verificar25('Actualizar codigo y limites sin cambiar juego sigue permitido',
    EXISTS (SELECT 1 FROM mesas WHERE id = v_mesa AND juego_id = v_ruleta
      AND codigo = 'QA25-MESA-ACTUALIZADA' AND monto_minimo = 1500
      AND monto_maximo = 70000));

  PERFORM pg_temp.error25('Actualizacion de mesa inexistente (CA104)', 'CA104',
    format('SELECT casino.fn_actualizar_mesa(%s, %L, %s, 1000, 90000)',
      -987654321, 'QA25-NO-EXISTE', v_ruleta));
  PERFORM pg_temp.error25('Actualizacion con maximo menor al minimo (CA103)', 'CA103',
    format('SELECT casino.fn_actualizar_mesa(%s, %L, %s, 90000, 1000)',
      v_mesa, 'QA25-MESA-ACTUALIZADA', v_ruleta));

  PERFORM fn_eliminar_asignacion(v_asignacion);
  PERFORM fn_actualizar_mesa(v_mesa, 'QA25-MESA-ACTUALIZADA', v_blackjack, 1500, 70000);
  PERFORM pg_temp.verificar25('Tras eliminar la asignacion sin rondas, se permite cambiar juego',
    EXISTS (SELECT 1 FROM mesas WHERE id = v_mesa AND juego_id = v_blackjack));

  PERFORM fn_desactivar_mesa(v_mesa);
  PERFORM pg_temp.verificar25('Desactivar mesa la conserva y marca inactiva',
    EXISTS (SELECT 1 FROM mesas WHERE id = v_mesa AND NOT activa));
  PERFORM pg_temp.error25('Desactivar mesa inexistente (CA104)', 'CA104',
    'SELECT casino.fn_desactivar_mesa(-987654321)');
END $$;

ROLLBACK;
