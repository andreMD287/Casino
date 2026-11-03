-- Regresion de integridad: conceptos emitidos bloquean eliminacion de asignacion/turno.
-- Se ejecuta aislada en la misma BD de la bateria y revierte todo con ROLLBACK.
\set ON_ERROR_STOP 1
SET client_min_messages = notice;
SET search_path = casino, public;
BEGIN;

CREATE FUNCTION pg_temp.ok27(p_nombre text, p_cond boolean) RETURNS void
LANGUAGE plpgsql AS $$ BEGIN
 IF NOT coalesce(p_cond,false) THEN RAISE EXCEPTION 'FALLO prueba: %',p_nombre; END IF;
 RAISE NOTICE '[OK] %',p_nombre;
END $$;

CREATE FUNCTION pg_temp.error27(p_nombre text,p_codigo text,p_sql text) RETURNS void
LANGUAGE plpgsql AS $$ DECLARE v_codigo text; BEGIN
 BEGIN
  EXECUTE p_sql;
 EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS v_codigo = RETURNED_SQLSTATE;
  IF v_codigo = p_codigo THEN RAISE NOTICE '[OK] %',p_nombre; RETURN; END IF;
  RAISE EXCEPTION 'FALLO prueba %: esperado %, recibido %',p_nombre,p_codigo,v_codigo;
 END;
 RAISE EXCEPTION 'FALLO prueba %: no se produjo error %',p_nombre,p_codigo;
END $$;

DO $$
DECLARE
 v_admin bigint; v_sup_usuario bigint; v_jugador bigint;
 v_juego bigint; v_mesa bigint; v_crupier bigint; v_supervisor bigint;
 v_jornada bigint; v_turno bigint; v_asig bigint;
 v_turno_a bigint; v_asig_a bigint; v_turno_b bigint; v_asig_b bigint;
 v_turno_c bigint; v_asig_c bigint; v_turno_d bigint; v_asig_d bigint;
 v_fecha date;
 v_i int;
BEGIN
 SELECT id INTO STRICT v_admin FROM usuarios WHERE usuario='admin';
 SELECT id INTO STRICT v_jugador FROM usuarios WHERE usuario='jugador1';
 SELECT id INTO STRICT v_sup_usuario FROM usuarios WHERE usuario='supervisor2';
 SELECT id INTO STRICT v_juego FROM juegos WHERE nombre='Ruleta';
 SELECT id INTO STRICT v_crupier FROM empleados WHERE usuario_id=(SELECT id FROM usuarios WHERE usuario='crupier1');
 SELECT id INTO STRICT v_supervisor FROM empleados WHERE usuario_id=v_sup_usuario;
 PERFORM set_config('app.usuario_id',v_admin::text,true);
 v_mesa := fn_crear_mesa('QA27-CONCEPTOS',v_juego,1000,90000);
 FOR v_i IN 1..4 LOOP
  v_fecha := DATE '2021-05-10' + v_i;
  v_jornada := fn_crear_jornada(v_fecha);
  v_turno := fn_crear_turno(v_jornada,
    (v_fecha::text||' 08:00:00-05')::timestamptz,
    (v_fecha::text||' 09:00:00-05')::timestamptz);
  v_asig := fn_crear_asignacion(v_turno,v_mesa,v_crupier,v_supervisor);
  CASE v_i
   WHEN 1 THEN v_turno_a:=v_turno; v_asig_a:=v_asig;
   WHEN 2 THEN v_turno_b:=v_turno; v_asig_b:=v_asig;
   WHEN 3 THEN v_turno_c:=v_turno; v_asig_c:=v_asig;
   WHEN 4 THEN v_turno_d:=v_turno; v_asig_d:=v_asig;
  END CASE;
  IF v_i <= 2 THEN
   PERFORM set_config('app.usuario_id',v_sup_usuario::text,true);
   PERFORM fn_emitir_concepto(v_asig,'Comportamiento neutro','QA historico 27');
   PERFORM set_config('app.usuario_id',v_admin::text,true);
  END IF;
 END LOOP;
 PERFORM pg_temp.ok27('Concepto historico registrado en asignacion A',
   EXISTS(SELECT 1 FROM conceptos WHERE asignacion_id=v_asig_a));
 PERFORM pg_temp.error27('Eliminar asignacion con concepto bloqueado (CA126)','CA126',
   format('SELECT casino.fn_eliminar_asignacion(%s)',v_asig_a));
 PERFORM pg_temp.ok27('Rechazo conserva asignacion A y concepto',
   EXISTS(SELECT 1 FROM asignaciones WHERE id=v_asig_a) AND
   EXISTS(SELECT 1 FROM conceptos WHERE asignacion_id=v_asig_a));
 PERFORM pg_temp.ok27('Concepto historico registrado en turno B',
   EXISTS(SELECT 1 FROM conceptos WHERE asignacion_id=v_asig_b));
 PERFORM pg_temp.error27('Eliminar turno con concepto bloqueado (CA126)','CA126',
   format('SELECT casino.fn_eliminar_turno(%s)',v_turno_b));
 PERFORM pg_temp.ok27('Rechazo conserva turno B, asignacion y concepto',
   EXISTS(SELECT 1 FROM turnos WHERE id=v_turno_b) AND
   EXISTS(SELECT 1 FROM asignaciones WHERE id=v_asig_b) AND
   EXISTS(SELECT 1 FROM conceptos WHERE asignacion_id=v_asig_b));
 PERFORM fn_eliminar_asignacion(v_asig_c);
 PERFORM pg_temp.ok27('Asignacion sin ronda ni concepto se elimina',
   NOT EXISTS(SELECT 1 FROM asignaciones WHERE id=v_asig_c));
 PERFORM fn_eliminar_turno(v_turno_c);
 PERFORM pg_temp.ok27('Turno vacio se elimina',
   NOT EXISTS(SELECT 1 FROM turnos WHERE id=v_turno_c));
 PERFORM fn_eliminar_turno(v_turno_d);
 PERFORM pg_temp.ok27('Turno y asignacion sin historial se eliminan',
   NOT EXISTS(SELECT 1 FROM turnos WHERE id=v_turno_d) AND
   NOT EXISTS(SELECT 1 FROM asignaciones WHERE id=v_asig_d));
 PERFORM pg_temp.error27('Asignacion inexistente da CA106','CA106',
   'SELECT casino.fn_eliminar_asignacion(-987654321)');
 PERFORM pg_temp.error27('Turno inexistente da CA105','CA105',
   'SELECT casino.fn_eliminar_turno(-987654321)');
 PERFORM set_config('app.usuario_id',v_jugador::text,true);
 PERFORM pg_temp.error27('Jugador no puede eliminar asignacion (CA002)','CA002',
   format('SELECT casino.fn_eliminar_asignacion(%s)',v_asig_a));
END $$;
ROLLBACK;
