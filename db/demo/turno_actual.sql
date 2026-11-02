-- demo/turno_actual.sql (Andrés)
-- Asegura que exista un turno vigente y asignaciones completas para 3 mesas.
-- Ejecutar con psql como superusuario, DESPUÉS de la semilla 91/92/93.
-- No elimina rondas ni evade rotación/competencias. Si estas restricciones
-- impiden crear otro turno en la jornada, indica recrear la demo con run_all.sh.
\set ON_ERROR_STOP on
SET ROLE casino_owner;
SET search_path = casino, public;

DO $$
DECLARE
  v_admin bigint;
  v_turno bigint;
  v_jornada bigint;
  v_inicio timestamptz := now() - interval '1 minute';
  v_fin timestamptz := now() + interval '45 minutes';
  v_proximo timestamptz;
  v_mesa record;
  v_crupier bigint;
  v_supervisor bigint;
  v_existentes int;
  v_cantidad int;
BEGIN
  SELECT id INTO STRICT v_admin FROM usuarios WHERE usuario = 'admin';
  PERFORM set_config('app.usuario_id', v_admin::text, true);

  SELECT id INTO v_turno FROM turnos
  WHERE now() >= inicio AND now() < fin ORDER BY inicio DESC LIMIT 1;
  IF v_turno IS NULL THEN
    -- Nunca pisar otro turno: ajustar el cierre al próximo turno del día.
    SELECT min(inicio) INTO v_proximo FROM turnos WHERE inicio > now();
    IF v_proximo IS NOT NULL THEN
      v_fin := least(v_fin, v_proximo - interval '1 second');
    END IF;
    IF v_fin <= now() + interval '2 minutes' THEN
      RAISE EXCEPTION 'No hay ventana suficiente para otro turno: espere al siguiente turno programado o recree la demo con run_all.sh';
    END IF;
    v_jornada := fn_crear_jornada((v_inicio AT TIME ZONE 'America/Bogota')::date);
    v_turno := fn_crear_turno(v_jornada, v_inicio, v_fin);
  END IF;

  SELECT jornada_id INTO STRICT v_jornada FROM turnos WHERE id = v_turno;
  SELECT count(*) INTO v_existentes FROM asignaciones WHERE turno_id = v_turno;

  -- Póker primero: menos crupieres tienen competencia. Después Blackjack y Ruleta.
  FOR v_mesa IN
    SELECT m.id, m.codigo, m.juego_id FROM mesas m
    JOIN juegos g ON g.id = m.juego_id
    WHERE m.activa AND m.codigo IN ('RUL-01','BJ-01','POK-01')
    ORDER BY CASE m.codigo WHEN 'POK-01' THEN 1 WHEN 'BJ-01' THEN 2 ELSE 3 END
  LOOP
    IF EXISTS (SELECT 1 FROM asignaciones WHERE turno_id = v_turno AND mesa_id = v_mesa.id) THEN
      CONTINUE;
    END IF;

    SELECT e.id INTO v_crupier FROM empleados e
    JOIN competencias c ON c.empleado_id = e.id AND c.juego_id = v_mesa.juego_id
    JOIN usuarios u ON u.id = e.usuario_id AND u.activo
    WHERE e.activo AND e.cargo = 'crupier'
      AND NOT EXISTS (SELECT 1 FROM asignaciones a WHERE a.turno_id = v_turno AND a.crupier_id = e.id)
      AND NOT EXISTS (SELECT 1 FROM asignaciones a WHERE a.jornada_id = v_jornada
                      AND a.mesa_id = v_mesa.id AND a.crupier_id = e.id)
    ORDER BY (SELECT count(*) FROM competencias c2 WHERE c2.empleado_id = e.id), e.id
    LIMIT 1;

    SELECT e.id INTO v_supervisor FROM empleados e
    JOIN competencias c ON c.empleado_id = e.id AND c.juego_id = v_mesa.juego_id
    JOIN usuarios u ON u.id = e.usuario_id AND u.activo
    WHERE e.activo AND e.cargo = 'supervisor'
    ORDER BY e.id LIMIT 1;

    IF v_crupier IS NULL OR v_supervisor IS NULL THEN
      RAISE EXCEPTION 'No hay personal elegible para la mesa % sin violar competencias o rotación. Vuelva a inicializar el casino cerca de la demo.', v_mesa.codigo;
    END IF;
    PERFORM fn_crear_asignacion(v_turno, v_mesa.id, v_crupier, v_supervisor);
  END LOOP;

  SELECT count(*) INTO v_cantidad FROM asignaciones a
  JOIN mesas m ON m.id = a.mesa_id
  WHERE a.turno_id = v_turno AND m.codigo IN ('RUL-01','BJ-01','POK-01');
  IF v_cantidad <> 3 THEN
    RAISE EXCEPTION 'El turno actual requiere tres asignaciones; encontradas %', v_cantidad;
  END IF;
  RAISE NOTICE '[OK] Turno vigente % con las tres mesas de demo asignadas (antes: % asignaciones)', v_turno, v_existentes;
END $$;
