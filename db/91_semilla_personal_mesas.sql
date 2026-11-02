-- 91_semilla_personal_mesas.sql (Andrés)
-- Se ejecuta después de 90_semilla_base y antes de 92/93.
-- No altera claves SRP: enlaza los usuarios ya creados por André.
SET ROLE casino_owner;
SET search_path = casino, public;

DO $$
DECLARE
  v_admin bigint;
  v_rul bigint; v_bj bigint; v_pok bigint;
  v_c1 bigint; v_c2 bigint; v_c3 bigint; v_c4 bigint;
  v_s1 bigint; v_s2 bigint;
  v_m_rul bigint; v_m_bj bigint; v_m_pok bigint;
  v_jornada bigint;
  v_turno_anterior bigint; v_turno_actual bigint; v_turno_siguiente bigint;
  v_turno_historico bigint;
  v_actual_ini timestamptz := now() - interval '10 minutes';
  v_actual_fin timestamptz := now() + interval '45 minutes';
  v_anterior_ini timestamptz; v_anterior_fin timestamptz;
  v_siguiente_ini timestamptz; v_siguiente_fin timestamptz;
  v_hoy date := (now() AT TIME ZONE 'America/Bogota')::date;
  v_historico_ini timestamptz;
BEGIN
  SELECT id INTO STRICT v_admin FROM usuarios WHERE usuario = 'admin';
  PERFORM set_config('app.usuario_id', v_admin::text, true);

  INSERT INTO empleados (usuario_id, documento, nombre, cargo, salario_mensual)
  SELECT u.id, x.documento, x.nombre, x.cargo, x.salario
  FROM (VALUES
    ('admin',       '90100101', 'Administrador General', 'administrador', 5000000::numeric),
    ('crupier1',    '90100102', 'Camilo Rivera',          'crupier',       1800000::numeric),
    ('crupier2',    '90100103', 'Daniel Rojas',           'crupier',       1900000::numeric),
    ('crupier3',    '90100104', 'Laura Torres',           'crupier',       2000000::numeric),
    ('crupier4',    '90100105', 'Sebastián Mora',         'crupier',       2100000::numeric),
    ('supervisor1', '90100106', 'María Fernández',       'supervisor',     2300000::numeric),
    ('supervisor2', '90100107', 'Felipe Gómez',          'supervisor',     2400000::numeric)
  ) AS x(usuario, documento, nombre, cargo, salario)
  JOIN usuarios u ON u.usuario = x.usuario;
  IF (SELECT count(*) FROM empleados) <> 7 THEN
    RAISE EXCEPTION 'Semilla 91: se esperaban siete empleados';
  END IF;

  SELECT id INTO STRICT v_rul FROM juegos WHERE nombre = 'Ruleta';
  SELECT id INTO STRICT v_bj FROM juegos WHERE nombre = 'Blackjack';
  SELECT id INTO STRICT v_pok FROM juegos WHERE nombre = 'Póker';
  SELECT e.id INTO STRICT v_c1 FROM empleados e JOIN usuarios u ON u.id = e.usuario_id WHERE u.usuario = 'crupier1';
  SELECT e.id INTO STRICT v_c2 FROM empleados e JOIN usuarios u ON u.id = e.usuario_id WHERE u.usuario = 'crupier2';
  SELECT e.id INTO STRICT v_c3 FROM empleados e JOIN usuarios u ON u.id = e.usuario_id WHERE u.usuario = 'crupier3';
  SELECT e.id INTO STRICT v_c4 FROM empleados e JOIN usuarios u ON u.id = e.usuario_id WHERE u.usuario = 'crupier4';
  SELECT e.id INTO STRICT v_s1 FROM empleados e JOIN usuarios u ON u.id = e.usuario_id WHERE u.usuario = 'supervisor1';
  SELECT e.id INTO STRICT v_s2 FROM empleados e JOIN usuarios u ON u.id = e.usuario_id WHERE u.usuario = 'supervisor2';

  -- Competencias variadas: crupier2 no puede operar Póker;
  -- supervisor2 no puede supervisar Blackjack.
  INSERT INTO competencias(empleado_id, juego_id) VALUES
    (v_c1,v_rul),(v_c1,v_pok),
    (v_c2,v_rul),(v_c2,v_bj),
    (v_c3,v_rul),(v_c3,v_bj),(v_c3,v_pok),
    (v_c4,v_bj),(v_c4,v_pok),
    (v_s1,v_rul),(v_s1,v_bj),(v_s1,v_pok),
    (v_s2,v_rul),(v_s2,v_pok);

  v_m_rul := fn_crear_mesa('RUL-01',v_rul,1000,100000);
  v_m_bj := fn_crear_mesa('BJ-01',v_bj,5000,200000);
  v_m_pok := fn_crear_mesa('POK-01',v_pok,10000,500000);

  v_anterior_fin := v_actual_ini - interval '5 minutes';
  v_anterior_ini := v_anterior_fin - interval '45 minutes';
  v_siguiente_ini := v_actual_fin + interval '5 minutes';
  v_siguiente_fin := v_siguiente_ini + interval '45 minutes';

  -- Cada turno se ubica en la jornada de su fecha local de inicio.
  -- Cerca de medianoche, el anterior o el siguiente pueden pertenecer a otra jornada.
  v_jornada := fn_crear_jornada((v_anterior_ini AT TIME ZONE 'America/Bogota')::date);
  v_turno_anterior := fn_crear_turno(v_jornada, v_anterior_ini, v_anterior_fin);
  v_jornada := fn_crear_jornada((v_actual_ini AT TIME ZONE 'America/Bogota')::date);
  v_turno_actual := fn_crear_turno(v_jornada, v_actual_ini, v_actual_fin);
  v_jornada := fn_crear_jornada((v_siguiente_ini AT TIME ZONE 'America/Bogota')::date);
  v_turno_siguiente := fn_crear_turno(v_jornada, v_siguiente_ini, v_siguiente_fin);

  -- Rotación: ningún crupier repite mesa en una misma jornada.
  PERFORM fn_crear_asignacion(v_turno_anterior, v_m_rul, v_c1, v_s1);
  PERFORM fn_crear_asignacion(v_turno_anterior, v_m_bj,  v_c2, v_s1);
  PERFORM fn_crear_asignacion(v_turno_anterior, v_m_pok, v_c3, v_s2);
  PERFORM fn_crear_asignacion(v_turno_actual,   v_m_rul, v_c2, v_s2);
  PERFORM fn_crear_asignacion(v_turno_actual,   v_m_bj,  v_c3, v_s1);
  PERFORM fn_crear_asignacion(v_turno_actual,   v_m_pok, v_c4, v_s2);
  PERFORM fn_crear_asignacion(v_turno_siguiente,v_m_rul, v_c3, v_s1);
  PERFORM fn_crear_asignacion(v_turno_siguiente,v_m_bj,  v_c4, v_s1);
  PERFORM fn_crear_asignacion(v_turno_siguiente,v_m_pok, v_c1, v_s2);

  -- Un turno histórico de 3 días antes permite preparar escenarios de deuda
  -- y ganancias acumuladas sin suspender artificialmente por pérdida diaria HOY.
  v_historico_ini := ((v_hoy - 3)::timestamp + interval '12 hours') AT TIME ZONE 'America/Bogota';
  v_jornada := fn_crear_jornada((v_historico_ini AT TIME ZONE 'America/Bogota')::date);
  v_turno_historico := fn_crear_turno(v_jornada, v_historico_ini, v_historico_ini + interval '50 minutes');
  PERFORM fn_crear_asignacion(v_turno_historico, v_m_rul, v_c2, v_s2);

  PERFORM fn_actualizar_umbral(300000);
  RAISE NOTICE '91: 7 empleados, 3 mesas, 4 turnos (1 histórico y 3 de demo), 10 asignaciones y umbral 300000';
END $$;
