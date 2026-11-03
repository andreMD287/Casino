-- Pruebas autónomas: se ejecutan en una transacción y terminan en ROLLBACK.
\set ON_ERROR_STOP 1
SET search_path = casino, public;
BEGIN;

CREATE FUNCTION pg_temp.ok(p_nombre text, p_cond boolean) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  IF p_cond THEN RAISE NOTICE '[OK] %', p_nombre;
  ELSE RAISE NOTICE '[FALLO] %', p_nombre; END IF;
END $$;

CREATE FUNCTION pg_temp.error_esperado(p_nombre text, p_codigo text, p_sql text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE p_sql;
  RAISE NOTICE '[FALLO] %: no hubo error', p_nombre;
EXCEPTION WHEN OTHERS THEN
  IF SQLSTATE = p_codigo THEN RAISE NOTICE '[OK] %', p_nombre;
  ELSE RAISE NOTICE '[FALLO] %: esperado %, obtenido % (%)', p_nombre, p_codigo, SQLSTATE, SQLERRM;
  END IF;
END $$;

CREATE TEMP TABLE caso_ids (clave text PRIMARY KEY, id bigint NOT NULL);
CREATE FUNCTION pg_temp.id(p text) RETURNS bigint LANGUAGE sql AS $$
  SELECT id FROM caso_ids WHERE clave = p
$$;
CREATE FUNCTION pg_temp.actor(p text) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('app.usuario_id', (SELECT id::text FROM casino.usuarios WHERE usuario = p), true)
$$;

DO $$
DECLARE
  v_usuario bigint;
  v_empleado bigint;
  v_jornada bigint;
  v_fecha date := DATE '2035-01-15';
  v_turno bigint;
  v_juego bigint;
  v_mesa bigint;
  v_nombre text;
  v_cargo text;
  v_doc text;
BEGIN
  -- La semilla del proyecto crea los juegos; estas cuentas y empleados son solo de prueba.
  PERFORM fn_crear_usuario('qa_admin20','00','00','administrador');
  PERFORM fn_crear_usuario('qa_crup20a','00','00','crupier');
  PERFORM fn_crear_usuario('qa_crup20b','00','00','crupier');
  PERFORM fn_crear_usuario('qa_sup20a','00','00','supervisor');
  PERFORM fn_crear_usuario('qa_sup20b','00','00','supervisor');
  FOREACH v_nombre IN ARRAY ARRAY['qa_crup20a','qa_crup20b','qa_sup20a','qa_sup20b'] LOOP
    SELECT id, rol INTO v_usuario, v_cargo FROM usuarios WHERE usuario = v_nombre;
    v_doc := CASE v_nombre WHEN 'qa_crup20a' THEN '820000001' WHEN 'qa_crup20b' THEN '820000002'
                         WHEN 'qa_sup20a' THEN '820000003' ELSE '820000004' END;
    INSERT INTO empleados(usuario_id, documento, nombre, cargo, salario_mensual)
    VALUES (v_usuario, v_doc, 'QA ' || v_nombre, v_cargo, 2500000) RETURNING id INTO v_empleado;
    INSERT INTO caso_ids VALUES (v_nombre, v_empleado);
  END LOOP;
  SELECT id INTO v_juego FROM juegos WHERE nombre = 'Ruleta';
  INSERT INTO competencias(empleado_id, juego_id)
  SELECT id, v_juego FROM empleados WHERE usuario_id IN
    (SELECT id FROM usuarios WHERE usuario IN ('qa_crup20a','qa_crup20b','qa_sup20a'));
  INSERT INTO mesas(codigo, juego_id, monto_minimo, monto_maximo)
  VALUES ('QA20-RUL', v_juego, 1000, 90000) RETURNING id INTO v_mesa;
  INSERT INTO caso_ids VALUES ('mesa_ruleta', v_mesa);
  SELECT id INTO v_juego FROM juegos WHERE nombre = 'Blackjack';
  INSERT INTO competencias(empleado_id, juego_id)
  VALUES (pg_temp.id('qa_crup20b'), v_juego), (pg_temp.id('qa_sup20b'), v_juego);
  INSERT INTO mesas(codigo, juego_id, monto_minimo, monto_maximo)
  VALUES ('QA20-BJ', v_juego, 5000, 200000) RETURNING id INTO v_mesa;
  INSERT INTO caso_ids VALUES ('mesa_blackjack', v_mesa);
  INSERT INTO jornadas(fecha) VALUES (v_fecha) RETURNING id INTO v_jornada;
  INSERT INTO caso_ids VALUES ('jornada', v_jornada);
  INSERT INTO turnos(jornada_id, inicio, fin)
  VALUES (v_jornada, '2035-01-15 08:00-05'::timestamptz, '2035-01-15 09:00-05'::timestamptz)
  RETURNING id INTO v_turno;
  INSERT INTO caso_ids VALUES ('turno1', v_turno);
  INSERT INTO turnos(jornada_id, inicio, fin)
  VALUES (v_jornada, '2035-01-15 09:00-05'::timestamptz, '2035-01-15 10:00-05'::timestamptz)
  RETURNING id INTO v_turno;
  INSERT INTO caso_ids VALUES ('turno2', v_turno);
END $$;

SELECT pg_temp.actor('qa_admin20');
SELECT pg_temp.ok('Número correlativo automático por jornada',
  (SELECT array_agg(numero ORDER BY inicio) FROM turnos WHERE jornada_id = pg_temp.id('jornada')) = ARRAY[1,2]);
SELECT pg_temp.error_esperado('Mesa: mínimo mayor al máximo', 'CA103',
  format('SELECT casino.fn_crear_mesa(%L, (SELECT id FROM casino.juegos WHERE nombre=%L), 500, 100)', 'QA20-MAL', 'Ruleta'));
SELECT pg_temp.error_esperado('Turno mayor a dos horas', 'CA109',
  format('SELECT casino.fn_crear_turno(%s, %L::timestamptz, %L::timestamptz)',
    pg_temp.id('jornada'), '2035-01-15 10:00-05', '2035-01-15 12:01-05'));
SELECT pg_temp.error_esperado('Turno en fecha distinta de jornada', 'CA110',
  format('SELECT casino.fn_crear_turno(%s, %L::timestamptz, %L::timestamptz)',
    pg_temp.id('jornada'), '2035-01-16 10:00-05', '2035-01-16 11:00-05'));
SELECT pg_temp.error_esperado('Turnos solapados', 'CA111',
  format('SELECT casino.fn_crear_turno(%s, %L::timestamptz, %L::timestamptz)',
    pg_temp.id('jornada'), '2035-01-15 08:30-05', '2035-01-15 09:30-05'));
SELECT pg_temp.error_esperado('Crupier sin competencia para Blackjack', 'CA115',
  format('SELECT casino.fn_crear_asignacion(%s,%s,%s,%s)', pg_temp.id('turno1'), pg_temp.id('mesa_blackjack'),
     pg_temp.id('qa_crup20a'), pg_temp.id('qa_sup20b')));
SELECT pg_temp.error_esperado('Supervisor con cargo equivocado', 'CA114',
  format('SELECT casino.fn_crear_asignacion(%s,%s,%s,%s)', pg_temp.id('turno1'), pg_temp.id('mesa_ruleta'),
     pg_temp.id('qa_crup20a'), pg_temp.id('qa_crup20b')));
SELECT pg_temp.error_esperado('Supervisor sin competencia para Ruleta', 'CA115',
  format('SELECT casino.fn_crear_asignacion(%s,%s,%s,%s)', pg_temp.id('turno1'), pg_temp.id('mesa_ruleta'),
     pg_temp.id('qa_crup20a'), pg_temp.id('qa_sup20b')));
SELECT casino.fn_crear_asignacion(pg_temp.id('turno1'),pg_temp.id('mesa_ruleta'),
  pg_temp.id('qa_crup20a'),pg_temp.id('qa_sup20a')) AS _asignacion_creada \gset
INSERT INTO caso_ids VALUES ('asignacion1', :_asignacion_creada);
SELECT pg_temp.error_esperado('Mesa duplicada en el mismo turno', 'CA116',
  format('SELECT casino.fn_crear_asignacion(%s,%s,%s,%s)', pg_temp.id('turno1'), pg_temp.id('mesa_ruleta'),
     pg_temp.id('qa_crup20b'), pg_temp.id('qa_sup20a')));
SELECT casino.fn_asignar_competencia(pg_temp.id('qa_crup20a'), (SELECT id FROM juegos WHERE nombre = 'Blackjack'));
SELECT pg_temp.error_esperado('Crupier en dos mesas del mismo turno', 'CA117',
  format('SELECT casino.fn_crear_asignacion(%s,%s,%s,%s)', pg_temp.id('turno1'), pg_temp.id('mesa_blackjack'),
     pg_temp.id('qa_crup20a'), pg_temp.id('qa_sup20b')));
SELECT pg_temp.error_esperado('Crupier repite mesa en la jornada', 'CA118',
  format('SELECT casino.fn_crear_asignacion(%s,%s,%s,%s)', pg_temp.id('turno2'), pg_temp.id('mesa_ruleta'),
     pg_temp.id('qa_crup20a'), pg_temp.id('qa_sup20a')));
SELECT pg_temp.error_esperado('Desactivar empleado con turno futuro', 'CA122',
  format('SELECT casino.fn_desactivar_empleado(%s)', pg_temp.id('qa_crup20a')));
SELECT pg_temp.error_esperado('Quitar competencia utilizada en turno futuro', 'CA123',
  format('SELECT casino.fn_quitar_competencia(%s,%s)', pg_temp.id('qa_crup20a'),
     (SELECT id FROM juegos WHERE nombre = 'Ruleta')));
SELECT pg_temp.actor('qa_sup20a');
SELECT pg_temp.error_esperado('Concepto antes de terminar el turno', 'CA120',
  format('SELECT casino.fn_emitir_concepto(%s, %L, NULL)', pg_temp.id('asignacion1'), 'Comportamiento neutro'));
SELECT pg_temp.actor('qa_sup20b');
SELECT pg_temp.error_esperado('Concepto por supervisor distinto', 'CA119',
  format('SELECT casino.fn_emitir_concepto(%s, %L, NULL)', pg_temp.id('asignacion1'), 'Comportamiento neutro'));

-- Concepto correcto para una asignación histórica de prueba.
SELECT pg_temp.actor('qa_admin20');
SELECT casino.fn_crear_jornada(DATE '2025-01-15') AS _jornada_pasada \gset
SELECT casino.fn_crear_turno(:_jornada_pasada, '2025-01-15 08:00-05'::timestamptz,
  '2025-01-15 09:00-05'::timestamptz) AS _turno_pasado \gset
SELECT casino.fn_crear_asignacion(:_turno_pasado,pg_temp.id('mesa_ruleta'),
  pg_temp.id('qa_crup20b'),pg_temp.id('qa_sup20a')) AS _asig_pasada \gset
SELECT pg_temp.actor('qa_sup20a');
SELECT casino.fn_emitir_concepto(:_asig_pasada, 'Comportamiento neutro', 'Verificado') AS _concepto \gset
SELECT pg_temp.ok('Concepto único registrado por supervisor correcto',
  (SELECT concepto FROM conceptos WHERE id = :_concepto) = 'Comportamiento neutro');
SELECT pg_temp.error_esperado('Segundo concepto de la misma asignación', 'CA121',
  format('SELECT casino.fn_emitir_concepto(%s, %L, NULL)', :_asig_pasada, 'Genera ganancias'));
ROLLBACK;
