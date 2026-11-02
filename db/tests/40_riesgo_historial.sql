-- Pruebas de reglas del modulo 40. Datos aislados, ROLLBACK final.
-- Se ejecuta con el superusuario postgres, igual que run_all.sh --tests.
\set ON_ERROR_STOP 1
SET client_min_messages = notice;
SET search_path = casino, public;
BEGIN;

CREATE TEMP TABLE fx40(clave text PRIMARY KEY, id bigint NOT NULL);
CREATE FUNCTION pg_temp.id40(p text) RETURNS bigint LANGUAGE sql AS $$
  SELECT id FROM fx40 WHERE clave = p;
$$;
CREATE FUNCTION pg_temp.actor40(p text) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('app.usuario_id', (SELECT id::text FROM casino.usuarios WHERE usuario = p), true);
$$;
CREATE FUNCTION pg_temp.check40(p_descripcion text, p_condicion boolean) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF coalesce(p_condicion, false) THEN
    RAISE NOTICE '[OK] %', p_descripcion;
  ELSE
    RAISE NOTICE '[FALLO] %', p_descripcion;
  END IF;
END $$;
CREATE FUNCTION pg_temp.error40(p_descripcion text, p_codigo text, p_sql text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE p_sql;
  RAISE NOTICE '[FALLO] %: no se produjo error %', p_descripcion, p_codigo;
EXCEPTION WHEN OTHERS THEN
  IF SQLSTATE = p_codigo THEN
    RAISE NOTICE '[OK] %', p_descripcion;
  ELSE
    RAISE NOTICE '[FALLO] %: se esperaba %, ocurrio % / %', p_descripcion, p_codigo, SQLSTATE, SQLERRM;
  END IF;
END $$;

-- Fixture de apuestas historicas, insertadas bajo superusuario con triggers
-- temporalmente desactivados para no depender de los modulos de Andre.
-- Los movimientos de saldo SI se producen mediante fn_mover_saldo.
CREATE FUNCTION pg_temp.apuesta40(p_jugador bigint, p_monto numeric, p_ganada boolean) RETURNS bigint
LANGUAGE plpgsql AS $$
DECLARE v_id bigint;
BEGIN
  PERFORM set_config('session_replication_role', 'replica', true);
  INSERT INTO casino.apuestas(ronda_id,jugador_id,opcion_id,monto,factor_pago,estado,premio,creada_en,liquidada_en,registrada_por)
  VALUES(pg_temp.id40('ronda'),p_jugador,pg_temp.id40('opcion'),p_monto,1,
         CASE WHEN p_ganada THEN 'ganada' ELSE 'perdida' END,
         CASE WHEN p_ganada THEN p_monto ELSE NULL END,
         now()-interval '5 minutes',now()-interval '4 minutes',pg_temp.id40('crup_usuario'))
  RETURNING id INTO v_id;
  PERFORM set_config('session_replication_role', 'origin', true);
  PERFORM casino.fn_mover_saldo(p_jugador, 'apuesta', p_monto, v_id);
  IF p_ganada THEN
    PERFORM casino.fn_mover_saldo(p_jugador, 'devolucion', p_monto, v_id);
    PERFORM casino.fn_mover_saldo(p_jugador, 'premio', p_monto, v_id);
  END IF;
  RETURN v_id;
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('session_replication_role', 'origin', true);
  RAISE;
END $$;

DO $$
DECLARE
  v_usuario text;
  v_id bigint;
  v_rol text;
  v_emp bigint;
  v_juego bigint;
  v_jornada bigint;
  v_turno bigint;
  v_asignacion bigint;
  v_mesa bigint;
  v_fecha date := (now() AT TIME ZONE 'America/Bogota')::date - 1;
BEGIN
  SELECT id INTO v_juego FROM juegos WHERE nombre='Ruleta';
  IF v_juego IS NULL THEN RAISE EXCEPTION 'La semilla base no tiene Ruleta'; END IF;
  INSERT INTO fx40 VALUES ('opcion',(SELECT id FROM opciones_apuesta WHERE juego_id=v_juego AND nombre='Rojo'));

  FOREACH v_usuario IN ARRAY ARRAY['t40_admin','t40_crup','t40_sup','t40_staff','t40_j1','t40_j2','t40_staffj','t40_earnj','t40_bad'] LOOP
    v_rol := CASE WHEN v_usuario='t40_admin' THEN 'administrador'
                  WHEN v_usuario='t40_sup' THEN 'supervisor'
                  WHEN v_usuario IN ('t40_crup','t40_staff') THEN 'crupier'
                  ELSE 'jugador' END;
    v_id := fn_crear_usuario(v_usuario,'salt','verificador',v_rol);
    INSERT INTO fx40 VALUES ('usr_'||v_usuario,v_id);
  END LOOP;
  INSERT INTO fx40 VALUES ('crup_usuario',pg_temp.id40('usr_t40_crup'));

  FOREACH v_usuario IN ARRAY ARRAY['t40_crup','t40_sup','t40_staff'] LOOP
    INSERT INTO empleados(usuario_id, documento, nombre, cargo, salario_mensual)
    VALUES (pg_temp.id40('usr_'||v_usuario),
       CASE v_usuario WHEN 't40_crup' THEN '43000001' WHEN 't40_sup' THEN '43000002' ELSE '43000003' END,
       v_usuario,CASE WHEN v_usuario='t40_sup' THEN 'supervisor' ELSE 'crupier' END, 1000)
    RETURNING id INTO v_emp;
    INSERT INTO fx40 VALUES('emp_'||v_usuario,v_emp);
    INSERT INTO competencias(empleado_id,juego_id) VALUES(v_emp,v_juego);
  END LOOP;

  INSERT INTO jornadas(fecha) VALUES (v_fecha) RETURNING id INTO v_jornada;
  INSERT INTO turnos(jornada_id,numero,inicio,fin)
    VALUES(v_jornada,NULL,(v_fecha + time '12:00') AT TIME ZONE 'America/Bogota',
                          (v_fecha + time '13:00') AT TIME ZONE 'America/Bogota')
    RETURNING id INTO v_turno;
  INSERT INTO mesas(codigo,juego_id,monto_minimo,monto_maximo)
  VALUES('T40-RUL',v_juego,1,100000) RETURNING id INTO v_mesa;
  INSERT INTO asignaciones(turno_id,jornada_id,mesa_id,crupier_id,supervisor_id)
  VALUES(v_turno,v_jornada,v_mesa,pg_temp.id40('emp_t40_crup'),pg_temp.id40('emp_t40_sup'))
  RETURNING id INTO v_asignacion;
  INSERT INTO rondas(mesa_id,asignacion_id,numero,inicio,cierre,estado)
    VALUES(v_mesa,v_asignacion,1,
      (v_fecha + time '12:10') AT TIME ZONE 'America/Bogota',
      (v_fecha + time '12:20') AT TIME ZONE 'America/Bogota', 'cerrada')
    RETURNING id INTO v_id;
  INSERT INTO fx40 VALUES('ronda',v_id);

  INSERT INTO jugadores(usuario_id,documento,nombre,fecha_nacimiento)
    VALUES(pg_temp.id40('usr_t40_j1'),'44000001','Jugador prueba 1',DATE '1990-01-01')
    RETURNING id INTO v_id;
  INSERT INTO fx40 VALUES('j1',v_id);
  INSERT INTO jugadores(usuario_id,documento,nombre,fecha_nacimiento)
    VALUES(pg_temp.id40('usr_t40_j2'),'44000002','Jugador prueba 2',DATE '1990-01-01')
    RETURNING id INTO v_id;
  INSERT INTO fx40 VALUES('j2',v_id);
  INSERT INTO jugadores(usuario_id,documento,nombre,fecha_nacimiento,empleado_id)
    VALUES(pg_temp.id40('usr_t40_staffj'),'44000003','Empleado jugador deuda',DATE '1990-01-01',pg_temp.id40('emp_t40_staff'))
    RETURNING id INTO v_id;
  INSERT INTO fx40 VALUES('je',v_id);
  -- Segundo empleado para testear investigacion sin mezclar deuda.
  INSERT INTO empleados(usuario_id,documento,nombre,cargo,salario_mensual)
    VALUES(pg_temp.id40('usr_t40_admin'),'43000004','Administrador jugador','administrador',1000)
    RETURNING id INTO v_emp;
  INSERT INTO jugadores(usuario_id,documento,nombre,fecha_nacimiento,empleado_id)
    VALUES(pg_temp.id40('usr_t40_earnj'),'44000004','Empleado jugador ganancias',DATE '1990-01-01',v_emp)
    RETURNING id INTO v_id;
  INSERT INTO fx40 VALUES('jg',v_id);

  PERFORM pg_temp.actor40('t40_admin');
  PERFORM fn_actualizar_umbral(300);
  PERFORM fn_mover_saldo(pg_temp.id40('j1'),'consignacion',100000);
  PERFORM fn_mover_saldo(pg_temp.id40('j2'),'consignacion',100000);
  PERFORM fn_mover_saldo(pg_temp.id40('je'),'consignacion',100000);
  PERFORM fn_mover_saldo(pg_temp.id40('jg'),'consignacion',100000);
END $$;

SELECT pg_temp.error40('Se impide registrar menores (CA304)','CA304',
  format('INSERT INTO casino.jugadores(usuario_id,documento,nombre,fecha_nacimiento) VALUES (%s,%L,%L,CURRENT_DATE)',
    pg_temp.id40('usr_t40_bad'), '44000005', 'Menor'));
SELECT pg_temp.error40('Documento no numerico bloqueado (CA309)','CA309',
  format('INSERT INTO casino.jugadores(usuario_id,documento,nombre,fecha_nacimiento) VALUES (%s,%L,%L,DATE ''1990-01-01'')',
    pg_temp.id40('usr_t40_bad'),'DOC-X','Documento incorrecto'));
SELECT pg_temp.check40('Estado inicial Activo en vista derivada',
  (SELECT estado='Activo' FROM v_estado_jugador WHERE jugador_id=pg_temp.id40('j1')));

-- Perdida diaria superior al umbral: suspension 24 h, idempotencia, vencimiento.
SELECT pg_temp.actor40('t40_admin');
SELECT pg_temp.apuesta40(pg_temp.id40('j1'),310,false);
SELECT fn_evaluar_riesgo(pg_temp.id40('j1'));
SELECT pg_temp.check40('Perdida neta diaria activa suspension de 24 h',
  (SELECT count(*)=1 FROM v_suspensiones WHERE jugador_id=pg_temp.id40('j1') AND motivo='perdida_diaria' AND activa));
SELECT fn_evaluar_riesgo(pg_temp.id40('j1'));
SELECT pg_temp.check40('Evaluacion de riesgo idempotente',
  (SELECT count(*)=1 FROM suspensiones WHERE jugador_id=pg_temp.id40('j1') AND motivo='perdida_diaria'));
SELECT pg_temp.error40('Suspendido no puede apostar (CA302)','CA302',
  format('SELECT casino.fn_puede_apostar(%s)',pg_temp.id40('j1')));
UPDATE suspensiones SET inicio=now()-interval '25 hours',fin=now()-interval '1 hour'
WHERE jugador_id=pg_temp.id40('j1') AND motivo='perdida_diaria';
SELECT fn_puede_apostar(pg_temp.id40('j1'));
SELECT pg_temp.check40('Suspension vencida permite volver a apostar',
  (SELECT estado='Activo' FROM v_estado_jugador WHERE jugador_id=pg_temp.id40('j1')));

-- Pausa de 24 horas por el jugador: no se duplica una pausa activa.
SELECT pg_temp.actor40('t40_j2');
SELECT fn_solicitar_pausa();
SELECT pg_temp.check40('Pausa voluntaria de 24 h',
  (SELECT count(*)=1 FROM v_suspensiones WHERE jugador_id=pg_temp.id40('j2') AND motivo='pausa_voluntaria' AND activa));
SELECT pg_temp.error40('Segunda pausa voluntaria rechazada (CA305)','CA305',
  'SELECT casino.fn_solicitar_pausa()');
SELECT pg_temp.error40('Jugador en pausa no puede apostar (CA302)','CA302',
  format('SELECT casino.fn_puede_apostar(%s)',pg_temp.id40('j2')));

-- Empleado: deuda > 2 sueldos y levantamiento tras abono.
SELECT pg_temp.actor40('t40_admin');
SELECT pg_temp.apuesta40(pg_temp.id40('je'),2101,false);
SELECT fn_evaluar_riesgo(pg_temp.id40('je'));
SELECT pg_temp.check40('Empleado con deuda > 2 salarios queda suspendido',
  (SELECT count(*)=1 FROM v_suspensiones WHERE jugador_id=pg_temp.id40('je') AND motivo='deuda_empleado' AND activa));
SELECT pg_temp.error40('Deuda bloquea apuestas (CA302)','CA302',
  format('SELECT casino.fn_puede_apostar(%s)',pg_temp.id40('je')));
SELECT pg_temp.check40('Abono devuelve deuda restante exactamente 2000',
  fn_registrar_abono(pg_temp.id40('emp_t40_staff'),101)=2000);
SELECT pg_temp.check40('Al bajar deuda a 2 salarios se levanta suspension',
  (SELECT count(*)=1 FROM suspensiones WHERE jugador_id=pg_temp.id40('je') AND motivo='deuda_empleado' AND levantada_en IS NOT NULL));
-- Perdida diaria > umbral sigue aplicando: no se debe afirmar que puede apostar
-- hasta que venza la suspension independiente por perdida diaria.
SELECT pg_temp.error40('Suspension diaria independiente sigue bloqueando (CA302)','CA302',
  format('SELECT casino.fn_puede_apostar(%s)',pg_temp.id40('je')));

-- Ganancias > salario abren investigacion; cierre la desbloquea si no hay otra causa.
-- Si el premio es 1501, neto acumulado 1501, y no hay perdida diaria.
SELECT pg_temp.apuesta40(pg_temp.id40('jg'),1501,true);
SELECT fn_evaluar_riesgo(pg_temp.id40('jg'));
SELECT pg_temp.check40('Ganancia > salario abre investigacion',
  (SELECT count(*)=1 FROM v_investigaciones WHERE jugador_id=pg_temp.id40('jg') AND cerrada_en IS NULL));
SELECT pg_temp.error40('Investigacion bloquea apuestas (CA303)','CA303',
  format('SELECT casino.fn_puede_apostar(%s)',pg_temp.id40('jg')));
SELECT fn_cerrar_investigacion((SELECT id FROM investigaciones WHERE jugador_id=pg_temp.id40('jg') AND cerrada_en IS NULL), 'Caso revisado');
SELECT fn_puede_apostar(pg_temp.id40('jg'));
SELECT pg_temp.check40('Tras cierre, jugador sin otros bloqueos esta activo',
  (SELECT estado='Activo' FROM v_estado_jugador WHERE jugador_id=pg_temp.id40('jg')));
SELECT pg_temp.error40('No se cierra dos veces una investigacion (CA307)','CA307',
  format('SELECT casino.fn_cerrar_investigacion(%s,%L)',
    (SELECT id FROM investigaciones WHERE jugador_id=pg_temp.id40('jg') ORDER BY id DESC LIMIT 1), 'Segundo cierre'));

-- Baja: sincronizacion de usuario y prioridad Inactivo.
SELECT fn_desactivar_jugador(pg_temp.id40('j1'));
SELECT pg_temp.check40('Jugador desactivado tambien inactiva su usuario',
  (SELECT NOT j.activo AND NOT u.activo FROM jugadores j JOIN usuarios u ON u.id=j.usuario_id WHERE j.id=pg_temp.id40('j1')));
SELECT pg_temp.error40('Jugador inactivo no puede apostar (CA301)','CA301',
  format('SELECT casino.fn_puede_apostar(%s)',pg_temp.id40('j1')));
SELECT pg_temp.check40('Vista de historial refleja saldos, apuestas y movimientos',
  (SELECT count(*)=1 FROM v_jugadores WHERE id=pg_temp.id40('je'))
  AND (SELECT count(*)>=1 FROM v_historial_apuestas WHERE jugador_id=pg_temp.id40('je'))
  AND (SELECT count(*)>=1 FROM v_historial_movimientos WHERE jugador_id=pg_temp.id40('je')));

ROLLBACK;
