-- 92_semilla_jugadores.sql (Andrés)
-- Jugadores, saldos y escenarios de riesgo compatibles con el trigger real de apuestas.
-- Se prepara historial con INSERT de apuestas pendientes válidas, movimientos por
-- fn_mover_saldo y posterior liquidación. No se desactivan triggers ni se altera el saldo directo.
SET ROLE casino_owner;
SET search_path = casino, public;

DO $$
DECLARE
  v_admin bigint; v_crupier_hist bigint; v_crupier_pasado bigint;
  v_j1 bigint; v_j2 bigint; v_j3 bigint; v_c1_juega bigint; v_s1_juega bigint;
  v_emp_c1 bigint; v_emp_s1 bigint;
  v_mesa_rul bigint; v_asig_hist bigint; v_asig_pasado bigint;
  v_ini_hist timestamptz; v_ini_pasado timestamptz;
  v_ronda_hist bigint; v_ronda_pasado bigint;
  v_opcion bigint; v_factor numeric;
  v_apuesta bigint; v_i int;
BEGIN
  SELECT id INTO STRICT v_admin FROM usuarios WHERE usuario = 'admin';
  PERFORM set_config('app.usuario_id', v_admin::text, true);
  SELECT e.id INTO STRICT v_emp_c1 FROM empleados e JOIN usuarios u ON u.id = e.usuario_id WHERE u.usuario = 'crupier1';
  SELECT e.id INTO STRICT v_emp_s1 FROM empleados e JOIN usuarios u ON u.id = e.usuario_id WHERE u.usuario = 'supervisor1';

  INSERT INTO jugadores(usuario_id, documento, nombre, fecha_nacimiento)
  SELECT id, '10203041', 'Juan García', DATE '1997-04-12' FROM usuarios WHERE usuario = 'jugador1'
  RETURNING id INTO v_j1;
  INSERT INTO jugadores(usuario_id, documento, nombre, fecha_nacimiento)
  SELECT id, '10203042', 'Sofía Martínez', DATE '1995-08-19' FROM usuarios WHERE usuario = 'jugador2'
  RETURNING id INTO v_j2;
  INSERT INTO jugadores(usuario_id, documento, nombre, fecha_nacimiento)
  SELECT id, '10203043', 'Carlos López', DATE '1992-11-09' FROM usuarios WHERE usuario = 'jugador3'
  RETURNING id INTO v_j3;
  INSERT INTO jugadores(usuario_id, documento, nombre, fecha_nacimiento, empleado_id)
  SELECT id, '10203044', 'Camilo Rivera (jugador)', DATE '1993-03-15', v_emp_c1
  FROM usuarios WHERE usuario = 'crupier1.juega'
  RETURNING id INTO v_c1_juega;
  INSERT INTO jugadores(usuario_id, documento, nombre, fecha_nacimiento, empleado_id)
  SELECT id, '10203045', 'María Fernández (jugadora)', DATE '1991-07-03', v_emp_s1
  FROM usuarios WHERE usuario = 'supervisor1.juega'
  RETURNING id INTO v_s1_juega;

  -- TODO el saldo inicial queda registrado como movimiento de consignación.
  PERFORM fn_mover_saldo(v_j1, 'consignacion', 1000000);
  PERFORM fn_mover_saldo(v_j2, 'consignacion', 1000000);
  PERFORM fn_mover_saldo(v_j3, 'consignacion', 700000);
  PERFORM fn_mover_saldo(v_c1_juega, 'consignacion', 4500000);
  PERFORM fn_mover_saldo(v_s1_juega, 'consignacion', 100000);

  SELECT id INTO STRICT v_mesa_rul FROM mesas WHERE codigo = 'RUL-01';
  SELECT o.id, o.factor_pago INTO STRICT v_opcion, v_factor
  FROM opciones_apuesta o JOIN juegos g ON g.id = o.juego_id
  WHERE g.nombre = 'Ruleta' AND o.nombre = 'Pleno 17';

  -- Turno histórico: solo la asignación de RUL-01 de hace 3 días.
  SELECT a.id, t.inicio, e.usuario_id
    INTO STRICT v_asig_hist, v_ini_hist, v_crupier_hist
  FROM asignaciones a JOIN turnos t ON t.id = a.turno_id
  JOIN mesas m ON m.id = a.mesa_id
  JOIN empleados e ON e.id = a.crupier_id
  WHERE m.codigo = 'RUL-01'
    AND (t.inicio AT TIME ZONE 'America/Bogota')::date =
        (now() AT TIME ZONE 'America/Bogota')::date - 3;

  PERFORM set_config('app.usuario_id', v_crupier_hist::text, true);
  INSERT INTO rondas(mesa_id, asignacion_id, inicio)
    VALUES(v_mesa_rul, v_asig_hist, v_ini_hist + interval '5 minutes')
    RETURNING id INTO v_ronda_hist;

  -- Empleado crupier1: pérdidas históricas de 3.500.000;
  -- 2 salarios = 3.600.000, por eso está cerca del límite, sin superarlo.
  FOR v_i IN 1..35 LOOP
    INSERT INTO apuestas(ronda_id, jugador_id, opcion_id, monto, factor_pago,
      estado, creada_en, registrada_por)
    VALUES(v_ronda_hist, v_c1_juega, v_opcion, 100000, v_factor,
      'pendiente', v_ini_hist + interval '6 minutes', v_crupier_hist)
    RETURNING id INTO v_apuesta;
    PERFORM fn_mover_saldo(v_c1_juega, 'apuesta', 100000, v_apuesta);
    UPDATE apuestas SET estado = 'perdida', liquidada_en = v_ini_hist + interval '12 minutes'
    WHERE id = v_apuesta;
    UPDATE movimientos_saldo SET creado_en = v_ini_hist + interval '6 minutes'
    WHERE apuesta_id = v_apuesta;
  END LOOP;

  -- Empleada supervisor1: premio histórico 60.000 * 35 = 2.100.000;
  -- salario = 2.300.000; todavía no entra en investigación.
  INSERT INTO apuestas(ronda_id, jugador_id, opcion_id, monto, factor_pago,
    estado, creada_en, registrada_por)
  VALUES(v_ronda_hist, v_s1_juega, v_opcion, 60000, v_factor,
    'pendiente', v_ini_hist + interval '7 minutes', v_crupier_hist)
  RETURNING id INTO v_apuesta;
  PERFORM fn_mover_saldo(v_s1_juega, 'apuesta', 60000, v_apuesta);
  UPDATE apuestas SET estado = 'ganada', premio = 2100000,
    liquidada_en = v_ini_hist + interval '12 minutes' WHERE id = v_apuesta;
  PERFORM fn_mover_saldo(v_s1_juega, 'devolucion', 60000, v_apuesta);
  PERFORM fn_mover_saldo(v_s1_juega, 'premio', 2100000, v_apuesta);
  UPDATE movimientos_saldo SET creado_en = v_ini_hist + interval '7 minutes'
    WHERE apuesta_id = v_apuesta;
  UPDATE rondas SET estado = 'cerrada', cierre = v_ini_hist + interval '15 minutes'
    WHERE id = v_ronda_hist;

  -- Pasado reciente: jugador2 acumula 225.000 en pérdidas en el último turno
  -- terminado (si ese turno comenzó hoy, queda cerca del umbral de 300.000).
  SELECT a.id, t.inicio, e.usuario_id
    INTO STRICT v_asig_pasado, v_ini_pasado, v_crupier_pasado
  FROM asignaciones a JOIN turnos t ON t.id = a.turno_id
  JOIN mesas m ON m.id = a.mesa_id
  JOIN empleados e ON e.id = a.crupier_id
  WHERE m.codigo = 'RUL-01' AND t.fin <= now()
    AND t.fin > now() - interval '3 hours'
  ORDER BY t.fin DESC LIMIT 1;

  PERFORM set_config('app.usuario_id', v_crupier_pasado::text, true);
  INSERT INTO rondas(mesa_id, asignacion_id, inicio)
    VALUES(v_mesa_rul, v_asig_pasado, v_ini_pasado + interval '5 minutes')
    RETURNING id INTO v_ronda_pasado;
  FOR v_i IN 1..3 LOOP
    INSERT INTO apuestas(ronda_id, jugador_id, opcion_id, monto, factor_pago,
      estado, creada_en, registrada_por)
    VALUES(v_ronda_pasado, v_j2, v_opcion, 75000, v_factor,
      'pendiente', v_ini_pasado + interval '6 minutes', v_crupier_pasado)
    RETURNING id INTO v_apuesta;
    PERFORM fn_mover_saldo(v_j2, 'apuesta', 75000, v_apuesta);
    UPDATE apuestas SET estado = 'perdida', liquidada_en = v_ini_pasado + interval '10 minutes'
      WHERE id = v_apuesta;
    UPDATE movimientos_saldo SET creado_en = v_ini_pasado + interval '6 minutes'
      WHERE apuesta_id = v_apuesta;
  END LOOP;
  UPDATE rondas SET estado = 'cerrada', cierre = v_ini_pasado + interval '15 minutes'
    WHERE id = v_ronda_pasado;

  -- Evaluar el riesgo después de registrar los resultados históricos.
  PERFORM fn_evaluar_riesgo(v_j2);
  PERFORM fn_evaluar_riesgo(v_c1_juega);
  PERFORM fn_evaluar_riesgo(v_s1_juega);
  PERFORM set_config('app.usuario_id', v_admin::text, true);

  IF (SELECT count(*) FROM jugadores) <> 5 THEN
    RAISE EXCEPTION '92: se esperaban cinco jugadores';
  END IF;
  RAISE NOTICE '92: 5 jugadores, consignaciones y escenarios históricos de riesgo preparados';
END $$;
