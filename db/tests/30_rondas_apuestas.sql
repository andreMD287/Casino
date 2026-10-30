-- tests/30_rondas_apuestas.sql (André) — pruebas de rondas y apuestas.
-- Patrón: cada prueba imprime [OK], [FALLO] o [PENDIENTE]. Todo corre en una transacción
-- que termina en ROLLBACK, así que no deja rastro. Los datos de prueba son propios
-- (mesas T-*, usuarios t_*), y el turno es el vigente (se reutiliza si ya existe uno).
\set ON_ERROR_STOP 1
SET client_min_messages = notice;
SET search_path = casino, public;
BEGIN;

-- ---------------------------------------------------------------------------
-- Utilidades de prueba
-- ---------------------------------------------------------------------------
CREATE TEMP TABLE fx (clave text PRIMARY KEY, id bigint NOT NULL);

CREATE FUNCTION pg_temp.fx(p text) RETURNS bigint LANGUAGE sql AS $$ SELECT id FROM fx WHERE clave = p $$;

CREATE FUNCTION pg_temp.actor(p_usuario text) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('app.usuario_id', (SELECT id::text FROM casino.usuarios WHERE usuario = p_usuario), true);
$$;

CREATE FUNCTION pg_temp.opcion(p_juego text, p_nombre text) RETURNS bigint LANGUAGE sql AS $$
  SELECT o.id FROM casino.opciones_apuesta o JOIN casino.juegos j ON j.id = o.juego_id
  WHERE j.nombre = p_juego AND o.nombre = p_nombre
$$;

CREATE FUNCTION pg_temp.saldo(p_clave text) RETURNS numeric LANGUAGE sql AS $$
  SELECT saldo FROM casino.jugadores WHERE id = pg_temp.fx(p_clave)
$$;

CREATE FUNCTION pg_temp.verifica(p_desc text, p_cond boolean, p_detalle text DEFAULT '') RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  IF p_cond THEN RAISE NOTICE '[OK] %', p_desc;
  ELSE RAISE NOTICE '[FALLO] % %', p_desc, p_detalle; END IF;
END $$;

-- Ejecuta p_sql y espera el SQLSTATE p_codigo.
CREATE FUNCTION pg_temp.espera_error(p_desc text, p_codigo text, p_sql text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE p_sql;
  RAISE NOTICE '[FALLO] % (se esperaba %, no hubo error)', p_desc, p_codigo;
EXCEPTION WHEN OTHERS THEN
  IF SQLSTATE = p_codigo THEN RAISE NOTICE '[OK] %', p_desc;
  ELSE RAISE NOTICE '[FALLO] % (se esperaba %, llegó %: %)', p_desc, p_codigo, SQLSTATE, SQLERRM; END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Datos de prueba
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_jornada bigint;
  v_turno bigint;
  v_fecha date := (now() AT TIME ZONE 'America/Bogota')::date;
  v_sig timestamptz;
  u text;
  v_emp bigint;
BEGIN
  -- Usuarios
  PERFORM fn_crear_usuario('t_admin', '00', '00', 'administrador');
  FOREACH u IN ARRAY ARRAY['t_crup_a', 't_crup_b', 't_crup_c'] LOOP
    PERFORM fn_crear_usuario(u, '00', '00', 'crupier');
  END LOOP;
  PERFORM fn_crear_usuario('t_sup', '00', '00', 'supervisor');
  PERFORM fn_crear_usuario('t_jug1', '00', '00', 'jugador');
  PERFORM fn_crear_usuario('t_jug2', '00', '00', 'jugador');

  -- Empleados con competencia en los tres juegos
  FOREACH u IN ARRAY ARRAY['t_crup_a', 't_crup_b', 't_crup_c', 't_sup'] LOOP
    INSERT INTO empleados (usuario_id, documento, nombre, cargo, salario_mensual)
    SELECT id, 'DOC-' || u, 'Prueba ' || u, CASE WHEN u = 't_sup' THEN 'supervisor' ELSE 'crupier' END, 3000000
    FROM usuarios WHERE usuario = u
    RETURNING id INTO v_emp;
    INSERT INTO competencias (empleado_id, juego_id) SELECT v_emp, id FROM juegos;
    INSERT INTO fx VALUES ('emp_' || u, v_emp);
  END LOOP;

  -- Mesas
  INSERT INTO mesas (codigo, juego_id, monto_minimo, monto_maximo)
  SELECT 'T-RUL', id, 10, 1000 FROM juegos WHERE nombre = 'Ruleta' RETURNING id INTO v_emp;
  INSERT INTO fx VALUES ('mesa_rul', v_emp);
  INSERT INTO mesas (codigo, juego_id, monto_minimo, monto_maximo)
  SELECT 'T-BJ', id, 10, 500 FROM juegos WHERE nombre = 'Blackjack' RETURNING id INTO v_emp;
  INSERT INTO fx VALUES ('mesa_bj', v_emp);
  INSERT INTO mesas (codigo, juego_id, monto_minimo, monto_maximo)
  SELECT 'T-POK', id, 10, 1000 FROM juegos WHERE nombre = 'Póker' RETURNING id INTO v_emp;
  INSERT INTO fx VALUES ('mesa_pok', v_emp);

  -- Jornada de hoy y turno vigente (se reutilizan si existen)
  SELECT id INTO v_jornada FROM jornadas WHERE fecha = v_fecha;
  IF v_jornada IS NULL THEN
    INSERT INTO jornadas (fecha) VALUES (v_fecha) RETURNING id INTO v_jornada;
  END IF;
  SELECT id INTO v_turno FROM turnos WHERE jornada_id = v_jornada AND now() >= inicio AND now() < fin;
  IF v_turno IS NULL THEN
    SELECT min(inicio) INTO v_sig FROM turnos WHERE jornada_id = v_jornada AND inicio > now();
    INSERT INTO turnos (jornada_id, numero, inicio, fin)
    SELECT v_jornada, coalesce(max(numero), 0) + 1, now() - interval '1 minute',
           least(now() + interval '60 minutes', coalesce(v_sig, 'infinity'))
    FROM turnos WHERE jornada_id = v_jornada
    RETURNING id INTO v_turno;
  END IF;

  -- Asignaciones: crup_a → T-RUL, crup_b → T-BJ, crup_c → T-POK
  INSERT INTO asignaciones (turno_id, jornada_id, mesa_id, crupier_id, supervisor_id) VALUES
    (v_turno, v_jornada, pg_temp.fx('mesa_rul'), pg_temp.fx('emp_t_crup_a'), pg_temp.fx('emp_t_sup')),
    (v_turno, v_jornada, pg_temp.fx('mesa_bj'),  pg_temp.fx('emp_t_crup_b'), pg_temp.fx('emp_t_sup')),
    (v_turno, v_jornada, pg_temp.fx('mesa_pok'), pg_temp.fx('emp_t_crup_c'), pg_temp.fx('emp_t_sup'));

  -- Jugadores con saldo inicial (siempre con fn_mover_saldo)
  INSERT INTO jugadores (usuario_id, documento, nombre, fecha_nacimiento)
  SELECT id, 'DOC-t_jug1', 'Jugador Uno', DATE '1990-01-01' FROM usuarios WHERE usuario = 't_jug1' RETURNING id INTO v_emp;
  INSERT INTO fx VALUES ('jug1', v_emp);
  PERFORM fn_mover_saldo(v_emp, 'consignacion', 1000);
  INSERT INTO jugadores (usuario_id, documento, nombre, fecha_nacimiento)
  SELECT id, 'DOC-t_jug2', 'Jugador Dos', DATE '1991-01-01' FROM usuarios WHERE usuario = 't_jug2' RETURNING id INTO v_emp;
  INSERT INTO fx VALUES ('jug2', v_emp);
  PERFORM fn_mover_saldo(v_emp, 'consignacion', 50);
END $$;

-- ---------------------------------------------------------------------------
-- Correlativo por mesa: 1, 2, 3
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  r1 bigint; r2 bigint; r3 bigint;
BEGIN
  PERFORM pg_temp.actor('t_crup_a');
  r1 := fn_abrir_ronda(pg_temp.fx('mesa_rul'));
  PERFORM fn_cerrar_ronda(r1, ARRAY[pg_temp.opcion('Ruleta', 'Rojo')]);
  r2 := fn_abrir_ronda(pg_temp.fx('mesa_rul'));
  PERFORM fn_cerrar_ronda(r2, ARRAY[pg_temp.opcion('Ruleta', 'Negro')]);
  r3 := fn_abrir_ronda(pg_temp.fx('mesa_rul'));
  INSERT INTO fx VALUES ('ronda_cerrada', r1), ('ronda_rul', r3);
  PERFORM pg_temp.verifica('correlativo 1, 2, 3 por mesa',
    (SELECT array_agg(numero ORDER BY id) FROM rondas WHERE id IN (r1, r2, r3)) = ARRAY[1, 2, 3],
    (SELECT array_agg(numero ORDER BY id) FROM rondas WHERE id IN (r1, r2, r3))::text);
END $$;

-- ---------------------------------------------------------------------------
-- Apertura: segunda ronda abierta y crupier no asignado
-- ---------------------------------------------------------------------------
SELECT pg_temp.actor('t_crup_a');
SELECT pg_temp.espera_error('segunda ronda abierta en la misma mesa → CA208', 'CA208',
  format('SELECT casino.fn_abrir_ronda(%s)', pg_temp.fx('mesa_rul')));

SELECT pg_temp.actor('t_crup_b');
SELECT pg_temp.espera_error('crupier no asignado no puede abrir la mesa → CA207', 'CA207',
  format('SELECT casino.fn_abrir_ronda(%s)', pg_temp.fx('mesa_pok')));
SELECT pg_temp.espera_error('crupier no asignado no puede registrar apuestas en la ronda → CA207', 'CA207',
  format('SELECT casino.fn_registrar_apuesta(%s, %s, %s, 20)', pg_temp.fx('ronda_rul'), pg_temp.fx('jug1'), pg_temp.opcion('Ruleta', 'Rojo')));

SELECT pg_temp.actor('t_jug1');
SELECT pg_temp.espera_error('un jugador no puede abrir rondas → CA002', 'CA002',
  format('SELECT casino.fn_abrir_ronda(%s)', pg_temp.fx('mesa_rul')));

-- ---------------------------------------------------------------------------
-- Validaciones de la apuesta
-- ---------------------------------------------------------------------------
SELECT pg_temp.actor('t_crup_a');
SELECT pg_temp.espera_error('monto menor al mínimo → CA205', 'CA205',
  format('SELECT casino.fn_registrar_apuesta(%s, %s, %s, 5)', pg_temp.fx('ronda_rul'), pg_temp.fx('jug1'), pg_temp.opcion('Ruleta', 'Rojo')));
SELECT pg_temp.espera_error('monto mayor al máximo → CA205', 'CA205',
  format('SELECT casino.fn_registrar_apuesta(%s, %s, %s, 1000.01)', pg_temp.fx('ronda_rul'), pg_temp.fx('jug1'), pg_temp.opcion('Ruleta', 'Rojo')));
SELECT pg_temp.espera_error('saldo insuficiente → CA010', 'CA010',
  format('SELECT casino.fn_registrar_apuesta(%s, %s, %s, 100)', pg_temp.fx('ronda_rul'), pg_temp.fx('jug2'), pg_temp.opcion('Ruleta', 'Rojo')));
SELECT pg_temp.espera_error('opción de otro juego → CA204', 'CA204',
  format('SELECT casino.fn_registrar_apuesta(%s, %s, %s, 20)', pg_temp.fx('ronda_rul'), pg_temp.fx('jug1'), pg_temp.opcion('Blackjack', 'Mano ganadora')));
SELECT pg_temp.espera_error('apuesta en ronda cerrada → CA203', 'CA203',
  format('SELECT casino.fn_registrar_apuesta(%s, %s, %s, 20)', pg_temp.fx('ronda_cerrada'), pg_temp.fx('jug1'), pg_temp.opcion('Ruleta', 'Rojo')));
SELECT pg_temp.espera_error('INSERT directo con monto inválido también se rechaza (trigger) → CA205', 'CA205',
  format('INSERT INTO casino.apuestas (ronda_id, jugador_id, opcion_id, monto, factor_pago, registrada_por) VALUES (%s, %s, %s, 1, 1, %s)',
         pg_temp.fx('ronda_rul'), pg_temp.fx('jug1'), pg_temp.opcion('Ruleta', 'Rojo'), current_setting('app.usuario_id')));
SELECT pg_temp.espera_error('INSERT directo con factor distinto al de la opción → CA206', 'CA206',
  format('INSERT INTO casino.apuestas (ronda_id, jugador_id, opcion_id, monto, factor_pago, registrada_por) VALUES (%s, %s, %s, 20, 99, %s)',
         pg_temp.fx('ronda_rul'), pg_temp.fx('jug1'), pg_temp.opcion('Ruleta', 'Rojo'), current_setting('app.usuario_id')));
SELECT pg_temp.verifica('las apuestas rechazadas no movieron saldo', pg_temp.saldo('jug1') = 1000 AND pg_temp.saldo('jug2') = 50);

-- ---------------------------------------------------------------------------
-- Liquidación con saldo final exacto
--   jug1 (1000): Rojo 100 (×1), Pleno 17 50 (×35), Negro 20 (×1) → queda 830
--   resultado {Pleno 17, Rojo, Impar}: gana Rojo (+100 +100) y Pleno 17 (+50 +1750); pierde Negro
--   saldo final = 830 + 200 + 1800 = 2830
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_ronda bigint := pg_temp.fx('ronda_rul');
  s record;
BEGIN
  PERFORM pg_temp.actor('t_crup_a');
  PERFORM fn_registrar_apuesta(v_ronda, pg_temp.fx('jug1'), pg_temp.opcion('Ruleta', 'Rojo'), 100);
  PERFORM fn_registrar_apuesta(v_ronda, pg_temp.fx('jug1'), pg_temp.opcion('Ruleta', 'Pleno 17'), 50);
  PERFORM fn_registrar_apuesta(v_ronda, pg_temp.fx('jug1'), pg_temp.opcion('Ruleta', 'Negro'), 20);
  PERFORM pg_temp.verifica('al apostar se descuenta el monto', pg_temp.saldo('jug1') = 830, pg_temp.saldo('jug1')::text);

  PERFORM pg_temp.espera_error('resultado con opción de otro juego → CA202', 'CA202',
    format('SELECT * FROM casino.fn_cerrar_ronda(%s, ARRAY[%s]::bigint[])', v_ronda, pg_temp.opcion('Póker', 'Mano ganadora')));
  PERFORM pg_temp.espera_error('cierre sin resultado en juego con registro detallado → CA212', 'CA212',
    format('SELECT * FROM casino.fn_cerrar_ronda(%s, ARRAY[]::bigint[])', v_ronda));

  SELECT * INTO s FROM fn_cerrar_ronda(v_ronda, ARRAY[pg_temp.opcion('Ruleta', 'Pleno 17'), pg_temp.opcion('Ruleta', 'Rojo'), pg_temp.opcion('Ruleta', 'Impar')]);
  PERFORM pg_temp.verifica('liquidación: saldo final exacto 2830', pg_temp.saldo('jug1') = 2830, pg_temp.saldo('jug1')::text);
  PERFORM pg_temp.verifica('liquidación: resumen (2 ganadas, 1 perdida, apostado 170, premios 1850, casino -1830)',
    s.ganadas = 2 AND s.perdidas = 1 AND s.total_apostado = 170 AND s.total_premios = 1850 AND s.resultado_casino = -1830, s::text);
  PERFORM pg_temp.verifica('liquidación: premio = monto × factor y estados correctos',
    (SELECT array_agg(estado || ':' || coalesce(premio::text, '-') ORDER BY id) FROM apuestas WHERE ronda_id = v_ronda)
      = ARRAY['ganada:100.00', 'ganada:1750.00', 'perdida:-']);
  PERFORM pg_temp.verifica('liquidación: movimientos devolucion y premio solo para las ganadas',
    (SELECT count(*) FROM movimientos_saldo m JOIN apuestas a ON a.id = m.apuesta_id WHERE a.ronda_id = v_ronda AND m.tipo IN ('devolucion', 'premio')) = 4);
  PERFORM pg_temp.verifica('la ronda queda cerrada con cierre posterior al inicio',
    (SELECT estado = 'cerrada' AND cierre > inicio FROM rondas WHERE id = v_ronda));
  PERFORM pg_temp.verifica('reporte mesa-turno: resultado nominal = perdidas − premios',
    (SELECT resultado_nominal FROM v_reporte_mesa_turno WHERE mesa_codigo = 'T-RUL') = -1830,
    (SELECT resultado_nominal FROM v_reporte_mesa_turno WHERE mesa_codigo = 'T-RUL')::text);
END $$;

SELECT pg_temp.actor('t_crup_a');
SELECT pg_temp.espera_error('doble cierre de la misma ronda → CA203', 'CA203',
  format('SELECT * FROM casino.fn_cerrar_ronda(%s, ARRAY[%s]::bigint[])', pg_temp.fx('ronda_rul'), pg_temp.opcion('Ruleta', 'Rojo')));

-- ---------------------------------------------------------------------------
-- Anulación con devolución
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_ronda bigint;
  v_ap bigint;
BEGIN
  PERFORM pg_temp.actor('t_crup_a');
  v_ronda := fn_abrir_ronda(pg_temp.fx('mesa_rul'));
  v_ap := fn_registrar_apuesta(v_ronda, pg_temp.fx('jug1'), pg_temp.opcion('Ruleta', 'Par'), 100);
  PERFORM fn_anular_apuesta(v_ap);
  PERFORM pg_temp.verifica('anular apuesta devuelve el monto', pg_temp.saldo('jug1') = 2830, pg_temp.saldo('jug1')::text);
  PERFORM pg_temp.verifica('la apuesta queda anulada', (SELECT estado FROM apuestas WHERE id = v_ap) = 'anulada');
  PERFORM pg_temp.espera_error('no se anula dos veces la misma apuesta → CA211', 'CA211', format('SELECT casino.fn_anular_apuesta(%s)', v_ap));

  PERFORM fn_registrar_apuesta(v_ronda, pg_temp.fx('jug1'), pg_temp.opcion('Ruleta', 'Impar'), 30);
  PERFORM fn_registrar_apuesta(v_ronda, pg_temp.fx('jug1'), pg_temp.opcion('Ruleta', 'Pleno 0'), 10);
  PERFORM fn_anular_ronda(v_ronda);
  PERFORM pg_temp.verifica('anular ronda devuelve todas las apuestas pendientes', pg_temp.saldo('jug1') = 2830, pg_temp.saldo('jug1')::text);
  PERFORM pg_temp.verifica('la ronda queda anulada y sus apuestas también',
    (SELECT estado FROM rondas WHERE id = v_ronda) = 'anulada'
    AND NOT EXISTS (SELECT 1 FROM apuestas WHERE ronda_id = v_ronda AND estado <> 'anulada'));
END $$;

-- ---------------------------------------------------------------------------
-- Póker (sin registro detallado)
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_ronda bigint;
  s record;
  v_antes numeric := pg_temp.saldo('jug1');
BEGIN
  PERFORM pg_temp.actor('t_crup_c');
  v_ronda := fn_abrir_ronda(pg_temp.fx('mesa_pok'));
  PERFORM pg_temp.espera_error('póker: apuesta pendiente no permitida → CA209', 'CA209',
    format('SELECT casino.fn_registrar_apuesta(%s, %s, %s, 50)', v_ronda, pg_temp.fx('jug1'), pg_temp.opcion('Póker', 'Mano ganadora')));
  PERFORM fn_registrar_apuesta_resuelta(v_ronda, pg_temp.fx('jug1'), pg_temp.opcion('Póker', 'Mano ganadora'), 100, true);
  PERFORM fn_registrar_apuesta_resuelta(v_ronda, pg_temp.fx('jug1'), pg_temp.opcion('Póker', 'Mano ganadora'), 40, false);
  PERFORM pg_temp.verifica('póker: saldo = antes + 100 − 40', pg_temp.saldo('jug1') = v_antes + 60, pg_temp.saldo('jug1')::text);
  PERFORM pg_temp.verifica('póker: apuestas guardadas ya liquidadas',
    (SELECT bool_and(liquidada_en IS NOT NULL) AND count(*) = 2 FROM apuestas WHERE ronda_id = v_ronda));
  PERFORM pg_temp.espera_error('póker: el cierre no lleva resultado → CA216', 'CA216',
    format('SELECT * FROM casino.fn_cerrar_ronda(%s, ARRAY[%s]::bigint[])', v_ronda, pg_temp.opcion('Póker', 'Mano ganadora')));
  SELECT * INTO s FROM fn_cerrar_ronda(v_ronda, NULL);
  PERFORM pg_temp.verifica('póker: cierre sin resultado con resumen 1 ganada / 1 perdida',
    s.ganadas = 1 AND s.perdidas = 1 AND s.resultado_casino = -60, s::text);
END $$;

SELECT pg_temp.actor('t_crup_b');
DO $$
DECLARE
  v_ronda bigint := fn_abrir_ronda(pg_temp.fx('mesa_bj'));
BEGIN
  PERFORM pg_temp.espera_error('juego con registro detallado no admite apuesta resuelta → CA210', 'CA210',
    format('SELECT casino.fn_registrar_apuesta_resuelta(%s, %s, %s, 50, true)', v_ronda, pg_temp.fx('jug1'), pg_temp.opcion('Blackjack', 'Mano ganadora')));
  INSERT INTO fx VALUES ('ronda_bj', v_ronda);
END $$;

-- ---------------------------------------------------------------------------
-- Opciones de apuesta (CRUD de administrador)
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_op bigint;
BEGIN
  PERFORM pg_temp.actor('t_admin');
  v_op := fn_crear_opcion((SELECT id FROM juegos WHERE nombre = 'Blackjack'), 'Seguro', 2);
  PERFORM pg_temp.verifica('administrador crea una opción', (SELECT factor_pago FROM opciones_apuesta WHERE id = v_op) = 2);
  PERFORM pg_temp.espera_error('opción duplicada en el mismo juego → CA214', 'CA214',
    format('SELECT casino.fn_crear_opcion(%s, %L, 3)', (SELECT id FROM juegos WHERE nombre = 'Blackjack'), 'Seguro'));

  PERFORM pg_temp.actor('t_crup_b');
  PERFORM fn_registrar_apuesta(pg_temp.fx('ronda_bj'), pg_temp.fx('jug1'), v_op, 20);
  PERFORM pg_temp.espera_error('un crupier no puede crear opciones → CA002', 'CA002',
    format('SELECT casino.fn_crear_opcion(%s, %L, 3)', (SELECT id FROM juegos WHERE nombre = 'Blackjack'), 'Otra'));

  PERFORM pg_temp.actor('t_admin');
  PERFORM pg_temp.espera_error('no se cambia el factor con apuestas pendientes → CA213', 'CA213',
    format('SELECT casino.fn_actualizar_opcion(%s, %L, 5)', v_op, 'Seguro'));
  PERFORM fn_actualizar_opcion(v_op, 'Seguro de la casa', 2);
  PERFORM pg_temp.verifica('sí se puede renombrar sin cambiar el factor', (SELECT nombre FROM opciones_apuesta WHERE id = v_op) = 'Seguro de la casa');
  PERFORM fn_desactivar_opcion(v_op);

  PERFORM pg_temp.actor('t_crup_b');
  PERFORM pg_temp.espera_error('opción desactivada no admite apuestas → CA204', 'CA204',
    format('SELECT casino.fn_registrar_apuesta(%s, %s, %s, 20)', pg_temp.fx('ronda_bj'), pg_temp.fx('jug1'), v_op));
END $$;

-- ---------------------------------------------------------------------------
-- Jugador suspendido (depende de fn_puede_apostar real de Andrés)
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_ronda bigint := pg_temp.fx('ronda_bj');
BEGIN
  PERFORM pg_temp.actor('t_crup_b');
  INSERT INTO suspensiones (jugador_id, motivo, inicio, fin)
  VALUES (pg_temp.fx('jug1'), 'pausa_voluntaria', now() - interval '1 minute', now() + interval '24 hours');
  BEGIN
    PERFORM fn_registrar_apuesta(v_ronda, pg_temp.fx('jug1'), pg_temp.opcion('Blackjack', 'Mano ganadora'), 20);
    RAISE NOTICE '[PENDIENTE] jugador suspendido no puede apostar (fn_puede_apostar todavía es un stub)';
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'deshacer apuesta de prueba';
  EXCEPTION
    WHEN SQLSTATE 'CA302' THEN RAISE NOTICE '[OK] jugador suspendido no puede apostar → CA302';
    WHEN SQLSTATE 'P0001' THEN NULL;
    WHEN OTHERS THEN RAISE NOTICE '[FALLO] jugador suspendido: se esperaba CA302, llegó %: %', SQLSTATE, SQLERRM;
  END;
END $$;

ROLLBACK;
