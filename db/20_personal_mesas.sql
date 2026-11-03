-- Gestión de empleados, competencias, mesas, jornadas, turnos y asignaciones.
-- Depende de 02_esquema.sql y 05_contrato.sql. Debe ejecutarse ANTES de 30_rondas_apuestas.sql.
SET ROLE casino_owner;
SET search_path = casino, public;

-- Consistencia entre empleados y sus cuentas de usuario.
CREATE OR REPLACE FUNCTION tg_empleado_rol() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = casino, pg_temp AS $$
DECLARE
  v_rol text;
BEGIN
  SELECT rol INTO v_rol FROM usuarios WHERE id = NEW.usuario_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'El usuario del empleado no existe' USING ERRCODE = 'CA101';
  END IF;
  IF TG_OP = 'INSERT' THEN
    IF v_rol <> NEW.cargo THEN
      RAISE EXCEPTION 'El cargo del empleado no coincide con el rol del usuario' USING ERRCODE = 'CA101';
    END IF;
  ELSE
    IF NEW.usuario_id <> OLD.usuario_id THEN
      RAISE EXCEPTION 'No se puede cambiar la cuenta vinculada al empleado' USING ERRCODE = 'CA101';
    END IF;
    IF NEW.cargo IS DISTINCT FROM OLD.cargo THEN
      IF EXISTS (SELECT 1 FROM asignaciones a JOIN turnos t ON t.id = a.turno_id
                 WHERE (a.crupier_id = NEW.id OR a.supervisor_id = NEW.id) AND t.fin > now()) THEN
        RAISE EXCEPTION 'No se puede cambiar el cargo con asignaciones vigentes o futuras' USING ERRCODE = 'CA122';
      END IF;
      UPDATE usuarios SET rol = NEW.cargo WHERE id = NEW.usuario_id;
    END IF;
    IF NEW.activo IS DISTINCT FROM OLD.activo THEN
      UPDATE usuarios SET activo = NEW.activo WHERE id = NEW.usuario_id;
    END IF;
  END IF;
  RETURN NEW;
END
$$;
CREATE TRIGGER tr_empleado_rol BEFORE INSERT OR UPDATE ON empleados
FOR EACH ROW EXECUTE FUNCTION tg_empleado_rol();

-- Número de turno y validación de fecha, duración y solapamientos.
-- Se bloquea la jornada para serializar inserciones concurrentes de turnos.
CREATE OR REPLACE FUNCTION tg_validar_turno() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = casino, pg_temp AS $$
DECLARE v_fecha date;
BEGIN
  SELECT fecha INTO v_fecha FROM jornadas WHERE id = NEW.jornada_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'La jornada no existe' USING ERRCODE = 'CA109';
  END IF;
  IF NEW.inicio IS NULL OR NEW.fin IS NULL OR NEW.fin <= NEW.inicio
     OR NEW.fin - NEW.inicio > interval '2 hours' THEN
    RAISE EXCEPTION 'Un turno debe durar más de 0 y máximo 2 horas' USING ERRCODE = 'CA109';
  END IF;
  IF (NEW.inicio AT TIME ZONE 'America/Bogota')::date <> v_fecha THEN
    RAISE EXCEPTION 'El inicio del turno no corresponde al día de su jornada' USING ERRCODE = 'CA110';
  END IF;
  IF EXISTS (
    SELECT 1 FROM turnos t
    WHERE t.jornada_id = NEW.jornada_id AND t.id IS DISTINCT FROM NEW.id
      AND t.inicio < NEW.fin AND NEW.inicio < t.fin
  ) THEN
    RAISE EXCEPTION 'El turno se solapa con otro turno de la jornada' USING ERRCODE = 'CA111';
  END IF;
  IF TG_OP = 'INSERT' AND NEW.numero IS NULL THEN
    SELECT coalesce(max(t.numero), 0) + 1 INTO NEW.numero
    FROM turnos t WHERE t.jornada_id = NEW.jornada_id;
  END IF;
  RETURN NEW;
END
$$;
CREATE TRIGGER tr_validar_turno BEFORE INSERT OR UPDATE ON turnos
FOR EACH ROW EXECUTE FUNCTION tg_validar_turno();

-- Asignaciones: juego, cargo, actividad, competencia y jornada.
CREATE OR REPLACE FUNCTION tg_validar_asignacion() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = casino, pg_temp AS $$
DECLARE
  v_jornada bigint;
  v_juego bigint;
  v_mesa_activa boolean;
  v_cargo text;
  v_activo boolean;
BEGIN
  SELECT jornada_id INTO v_jornada FROM turnos WHERE id = NEW.turno_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'El turno no existe' USING ERRCODE = 'CA112';
  END IF;
  NEW.jornada_id := v_jornada;
  SELECT juego_id, activa INTO v_juego, v_mesa_activa FROM mesas WHERE id = NEW.mesa_id FOR SHARE;
  IF NOT FOUND OR NOT v_mesa_activa THEN
    RAISE EXCEPTION 'La mesa no existe o está inactiva' USING ERRCODE = 'CA112';
  END IF;
  SELECT e.cargo, (e.activo AND u.activo) INTO v_cargo, v_activo
  FROM empleados e JOIN usuarios u ON u.id = e.usuario_id WHERE e.id = NEW.crupier_id;
  IF NOT FOUND OR v_cargo <> 'crupier' OR NOT v_activo THEN
    RAISE EXCEPTION 'Se requiere un crupier activo' USING ERRCODE = 'CA113';
  END IF;
  SELECT e.cargo, (e.activo AND u.activo) INTO v_cargo, v_activo
  FROM empleados e JOIN usuarios u ON u.id = e.usuario_id WHERE e.id = NEW.supervisor_id;
  IF NOT FOUND OR v_cargo <> 'supervisor' OR NOT v_activo THEN
    RAISE EXCEPTION 'Se requiere un supervisor activo' USING ERRCODE = 'CA114';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM competencias WHERE empleado_id = NEW.crupier_id AND juego_id = v_juego)
     OR NOT EXISTS (SELECT 1 FROM competencias WHERE empleado_id = NEW.supervisor_id AND juego_id = v_juego) THEN
    RAISE EXCEPTION 'El crupier y el supervisor deben conocer el juego de la mesa' USING ERRCODE = 'CA115';
  END IF;
  RETURN NEW;
END
$$;
CREATE TRIGGER tr_validar_asignacion BEFORE INSERT OR UPDATE ON asignaciones
FOR EACH ROW EXECUTE FUNCTION tg_validar_asignacion();

-- El supervisor designado solo puede emitir su concepto después de terminado el turno.
CREATE OR REPLACE FUNCTION tg_validar_concepto() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = casino, pg_temp AS $$
DECLARE v_supervisor_usuario bigint; v_fin timestamptz;
BEGIN
  PERFORM fn_exigir_rol('supervisor');
  SELECT e.usuario_id, t.fin INTO v_supervisor_usuario, v_fin
  FROM asignaciones a JOIN empleados e ON e.id = a.supervisor_id
  JOIN turnos t ON t.id = a.turno_id WHERE a.id = NEW.asignacion_id;
  IF NOT FOUND OR v_supervisor_usuario IS DISTINCT FROM fn_actor() THEN
    RAISE EXCEPTION 'Solo el supervisor de esta asignación puede emitir el concepto' USING ERRCODE = 'CA119';
  END IF;
  IF now() < v_fin THEN
    RAISE EXCEPTION 'El concepto solo se puede emitir al terminar el turno' USING ERRCODE = 'CA120';
  END IF;
  IF TG_OP = 'UPDATE' THEN
    RAISE EXCEPTION 'Un concepto ya emitido no puede modificarse' USING ERRCODE = 'CA121';
  END IF;
  RETURN NEW;
END
$$;
CREATE TRIGGER tr_validar_concepto BEFORE INSERT OR UPDATE ON conceptos
FOR EACH ROW EXECUTE FUNCTION tg_validar_concepto();

-- Funciones de gestión de empleados.
CREATE OR REPLACE FUNCTION fn_crear_empleado(
  p_nombre text, p_documento text, p_cargo text, p_salario numeric,
  p_usuario text, p_salt text, p_verificador text
) RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path = casino, pg_temp AS $$
DECLARE v_usuario_id bigint; v_id bigint;
BEGIN
  PERFORM fn_exigir_rol('administrador');
  IF p_nombre IS NULL OR btrim(p_nombre) = '' OR p_documento IS NULL OR btrim(p_documento) = ''
     OR p_cargo NOT IN ('administrador', 'crupier', 'supervisor')
     OR p_salario IS NULL OR p_salario <= 0 THEN
    RAISE EXCEPTION 'Datos de empleado inválidos' USING ERRCODE = 'CA101';
  END IF;
  v_usuario_id := fn_crear_usuario(p_usuario, p_salt, p_verificador, p_cargo);
  INSERT INTO empleados (usuario_id, nombre, documento, cargo, salario_mensual)
  VALUES (v_usuario_id, btrim(p_nombre), btrim(p_documento), p_cargo, p_salario)
  RETURNING id INTO v_id;
  RETURN v_id;
EXCEPTION WHEN unique_violation THEN
  RAISE EXCEPTION 'Ya existe un empleado con ese documento' USING ERRCODE = 'CA101';
END
$$;

CREATE OR REPLACE FUNCTION fn_actualizar_empleado(
  p_id bigint, p_nombre text, p_documento text, p_cargo text, p_salario numeric
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = casino, pg_temp AS $$
BEGIN
  PERFORM fn_exigir_rol('administrador');
  IF p_nombre IS NULL OR btrim(p_nombre) = '' OR p_documento IS NULL OR btrim(p_documento) = ''
     OR p_cargo NOT IN ('administrador', 'crupier', 'supervisor')
     OR p_salario IS NULL OR p_salario <= 0 THEN
    RAISE EXCEPTION 'Datos de empleado inválidos' USING ERRCODE = 'CA101';
  END IF;
  UPDATE empleados SET nombre = btrim(p_nombre), documento = btrim(p_documento),
       cargo = p_cargo, salario_mensual = p_salario WHERE id = p_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Empleado no encontrado' USING ERRCODE = 'CA102'; END IF;
EXCEPTION WHEN unique_violation THEN
  RAISE EXCEPTION 'Ya existe un empleado con ese documento' USING ERRCODE = 'CA101';
END
$$;

CREATE OR REPLACE FUNCTION fn_desactivar_empleado(p_id bigint) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = casino, pg_temp AS $$
BEGIN
  PERFORM fn_exigir_rol('administrador');
  IF EXISTS (
    SELECT 1 FROM asignaciones a JOIN turnos t ON t.id = a.turno_id
    WHERE (a.crupier_id = p_id OR a.supervisor_id = p_id) AND t.fin > now()
  ) THEN
    RAISE EXCEPTION 'El empleado tiene una asignación vigente o futura' USING ERRCODE = 'CA122';
  END IF;
  UPDATE empleados SET activo = false WHERE id = p_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Empleado no encontrado' USING ERRCODE = 'CA102'; END IF;
END
$$;

CREATE OR REPLACE FUNCTION fn_asignar_competencia(p_empleado_id bigint, p_juego_id bigint) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = casino, pg_temp AS $$
BEGIN
  PERFORM fn_exigir_rol('administrador');
  INSERT INTO competencias (empleado_id, juego_id) VALUES (p_empleado_id, p_juego_id)
  ON CONFLICT DO NOTHING;
END
$$;

CREATE OR REPLACE FUNCTION fn_quitar_competencia(p_empleado_id bigint, p_juego_id bigint) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = casino, pg_temp AS $$
BEGIN
  PERFORM fn_exigir_rol('administrador');
  IF EXISTS (
    SELECT 1 FROM asignaciones a JOIN turnos t ON t.id = a.turno_id
    JOIN mesas m ON m.id = a.mesa_id
    WHERE (a.crupier_id = p_empleado_id OR a.supervisor_id = p_empleado_id)
      AND m.juego_id = p_juego_id AND t.fin > now()
  ) THEN
    RAISE EXCEPTION 'No se puede quitar la competencia: hay asignaciones vigentes o futuras' USING ERRCODE = 'CA123';
  END IF;
  DELETE FROM competencias WHERE empleado_id = p_empleado_id AND juego_id = p_juego_id;
END
$$;

-- Gestión de mesas.
CREATE OR REPLACE FUNCTION fn_crear_mesa(p_codigo text, p_juego_id bigint, p_minimo numeric, p_maximo numeric)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path = casino, pg_temp AS $$
DECLARE v_id bigint;
BEGIN
  PERFORM fn_exigir_rol('administrador');
  IF p_codigo IS NULL OR btrim(p_codigo) = '' OR p_minimo IS NULL OR p_minimo <= 0
     OR p_maximo IS NULL OR p_maximo < p_minimo THEN
    RAISE EXCEPTION 'El mínimo de la mesa debe ser positivo y no superar el máximo' USING ERRCODE = 'CA103';
  END IF;
  INSERT INTO mesas (codigo, juego_id, monto_minimo, monto_maximo)
  VALUES (btrim(p_codigo), p_juego_id, p_minimo, p_maximo) RETURNING id INTO v_id;
  RETURN v_id;
EXCEPTION WHEN unique_violation THEN
  RAISE EXCEPTION 'El código de la mesa ya existe' USING ERRCODE = 'CA103';
END
$$;

CREATE OR REPLACE FUNCTION fn_actualizar_mesa(p_id bigint, p_codigo text, p_juego_id bigint, p_minimo numeric, p_maximo numeric)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = casino, pg_temp AS $$
DECLARE v_juego_anterior bigint;
BEGIN
  PERFORM fn_exigir_rol('administrador');
  IF p_codigo IS NULL OR btrim(p_codigo) = '' OR p_minimo IS NULL OR p_minimo <= 0
     OR p_maximo IS NULL OR p_maximo < p_minimo THEN
    RAISE EXCEPTION 'El mínimo de la mesa debe ser positivo y no superar el máximo' USING ERRCODE = 'CA103';
  END IF;
  SELECT juego_id INTO v_juego_anterior FROM mesas WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Mesa no encontrada' USING ERRCODE = 'CA104'; END IF;
  IF v_juego_anterior IS DISTINCT FROM p_juego_id AND (
    EXISTS (SELECT 1 FROM rondas WHERE mesa_id = p_id)
    OR EXISTS (SELECT 1 FROM asignaciones WHERE mesa_id = p_id)
  ) THEN
    RAISE EXCEPTION 'No se puede cambiar el juego de una mesa con rondas o asignaciones' USING ERRCODE = 'CA124';
  END IF;
  UPDATE mesas SET codigo = btrim(p_codigo), juego_id = p_juego_id,
    monto_minimo = p_minimo, monto_maximo = p_maximo WHERE id = p_id;
EXCEPTION WHEN unique_violation THEN
  RAISE EXCEPTION 'El código de la mesa ya existe' USING ERRCODE = 'CA103';
END
$$;

CREATE OR REPLACE FUNCTION fn_desactivar_mesa(p_id bigint) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = casino, pg_temp AS $$
BEGIN
  PERFORM fn_exigir_rol('administrador');
  -- Serializa la desactivacion con nuevas asignaciones (tr_validar_asignacion usa FOR SHARE).
  PERFORM 1 FROM mesas WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Mesa no encontrada' USING ERRCODE = 'CA104'; END IF;
  IF EXISTS (SELECT 1 FROM rondas WHERE mesa_id = p_id AND estado = 'abierta') THEN
    RAISE EXCEPTION 'No se puede desactivar una mesa con ronda abierta' USING ERRCODE = 'CA125';
  END IF;
  IF EXISTS (
    SELECT 1 FROM asignaciones a JOIN turnos t ON t.id = a.turno_id
    WHERE a.mesa_id = p_id AND t.fin > now()
  ) THEN
    RAISE EXCEPTION 'No se puede desactivar una mesa con asignaciones vigentes o futuras' USING ERRCODE = 'CA125';
  END IF;
  UPDATE mesas SET activa = false WHERE id = p_id;
END
$$;

-- Respaldo de integridad para UPDATE directo, aun sin usar la funcion publica.
CREATE OR REPLACE FUNCTION tg_proteger_juego_mesa() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = casino, pg_temp AS $$
BEGIN
  IF OLD.juego_id IS DISTINCT FROM NEW.juego_id AND (
    EXISTS (SELECT 1 FROM asignaciones WHERE mesa_id = OLD.id)
    OR EXISTS (SELECT 1 FROM rondas WHERE mesa_id = OLD.id)
  ) THEN
    RAISE EXCEPTION 'No se puede cambiar el juego de una mesa con rondas o asignaciones' USING ERRCODE = 'CA124';
  END IF;
  -- Protege incluso UPDATE directo sobre mesas.activa, sin usar fn_desactivar_mesa.
  IF OLD.activa AND NOT NEW.activa THEN
    IF EXISTS (SELECT 1 FROM rondas WHERE mesa_id = OLD.id AND estado = 'abierta')
       OR EXISTS (
         SELECT 1 FROM asignaciones a JOIN turnos t ON t.id = a.turno_id
         WHERE a.mesa_id = OLD.id AND t.fin > now()
       ) THEN
      RAISE EXCEPTION 'No se puede desactivar una mesa con ronda abierta o asignaciones vigentes o futuras' USING ERRCODE = 'CA125';
    END IF;
  END IF;
  RETURN NEW;
END
$$;
CREATE TRIGGER tr_proteger_juego_mesa BEFORE UPDATE OF juego_id, activa ON mesas
FOR EACH ROW EXECUTE FUNCTION tg_proteger_juego_mesa();

-- Jornadas y turnos.
CREATE OR REPLACE FUNCTION fn_crear_jornada(p_fecha date) RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path = casino, pg_temp AS $$
DECLARE v_id bigint;
BEGIN
  PERFORM fn_exigir_rol('administrador');
  INSERT INTO jornadas(fecha) VALUES (p_fecha)
  ON CONFLICT (fecha) DO UPDATE SET fecha = EXCLUDED.fecha RETURNING id INTO v_id;
  RETURN v_id;
END
$$;

CREATE OR REPLACE FUNCTION fn_crear_turno(p_jornada_id bigint, p_inicio timestamptz, p_fin timestamptz)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path = casino, pg_temp AS $$
DECLARE v_id bigint;
BEGIN
  PERFORM fn_exigir_rol('administrador');
  INSERT INTO turnos(jornada_id, numero, inicio, fin)
  VALUES (p_jornada_id, NULL, p_inicio, p_fin) RETURNING id INTO v_id;
  RETURN v_id;
END
$$;

CREATE OR REPLACE FUNCTION fn_eliminar_turno(p_id bigint) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = casino, pg_temp AS $$
DECLARE v_restriccion text;
BEGIN
  PERFORM fn_exigir_rol('administrador');
  -- Bloquear el turno y sus asignaciones evita perder un concepto o una ronda
  -- que otra transaccion este creando de forma simultanea.
  PERFORM 1 FROM turnos WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Turno no encontrado' USING ERRCODE = 'CA105'; END IF;
  PERFORM 1 FROM asignaciones WHERE turno_id = p_id ORDER BY id FOR UPDATE;
  IF EXISTS (SELECT 1 FROM rondas r JOIN asignaciones a ON a.id = r.asignacion_id WHERE a.turno_id = p_id)
     OR EXISTS (SELECT 1 FROM conceptos c JOIN asignaciones a ON a.id = c.asignacion_id WHERE a.turno_id = p_id) THEN
    RAISE EXCEPTION 'No se puede eliminar un turno con rondas o conceptos emitidos' USING ERRCODE = 'CA126';
  END IF;
  BEGIN
    DELETE FROM asignaciones WHERE turno_id = p_id;
    DELETE FROM turnos WHERE id = p_id;
  EXCEPTION WHEN foreign_key_violation THEN
    GET STACKED DIAGNOSTICS v_restriccion = CONSTRAINT_NAME;
    IF v_restriccion IN ('conceptos_asignacion_id_fkey', 'rondas_asignacion_id_fkey') THEN
      RAISE EXCEPTION 'No se puede eliminar un turno con rondas o conceptos emitidos' USING ERRCODE = 'CA126';
    END IF;
    RAISE;
  END;
END
$$;

-- Asignaciones y conceptos.
CREATE OR REPLACE FUNCTION fn_crear_asignacion(p_turno_id bigint, p_mesa_id bigint, p_crupier_id bigint, p_supervisor_id bigint)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path = casino, pg_temp AS $$
DECLARE v_id bigint; v_restriccion text;
BEGIN
  PERFORM fn_exigir_rol('administrador');
  INSERT INTO asignaciones(turno_id, jornada_id, mesa_id, crupier_id, supervisor_id)
  VALUES (p_turno_id, (SELECT jornada_id FROM turnos WHERE id = p_turno_id), p_mesa_id, p_crupier_id, p_supervisor_id)
  RETURNING id INTO v_id;
  RETURN v_id;
EXCEPTION WHEN unique_violation THEN
  GET STACKED DIAGNOSTICS v_restriccion = CONSTRAINT_NAME;
  CASE v_restriccion
    WHEN 'asignaciones_turno_id_mesa_id_key' THEN
      RAISE EXCEPTION 'La mesa ya tiene crupier en este turno' USING ERRCODE = 'CA116';
    WHEN 'asignaciones_turno_id_crupier_id_key' THEN
      RAISE EXCEPTION 'El crupier ya atiende otra mesa en este turno' USING ERRCODE = 'CA117';
    WHEN 'asignaciones_jornada_id_crupier_id_mesa_id_key' THEN
      RAISE EXCEPTION 'El crupier ya estuvo en esta mesa hoy; debe rotar' USING ERRCODE = 'CA118';
    ELSE RAISE;
  END CASE;
END
$$;

CREATE OR REPLACE FUNCTION fn_eliminar_asignacion(p_id bigint) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = casino, pg_temp AS $$
DECLARE v_restriccion text;
BEGIN
  PERFORM fn_exigir_rol('administrador');
  PERFORM 1 FROM asignaciones WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Asignación no encontrada' USING ERRCODE = 'CA106'; END IF;
  IF EXISTS (SELECT 1 FROM rondas WHERE asignacion_id = p_id)
     OR EXISTS (SELECT 1 FROM conceptos WHERE asignacion_id = p_id) THEN
    RAISE EXCEPTION 'No se puede eliminar una asignación con rondas o concepto emitido' USING ERRCODE = 'CA126';
  END IF;
  BEGIN
    DELETE FROM asignaciones WHERE id = p_id;
  EXCEPTION WHEN foreign_key_violation THEN
    GET STACKED DIAGNOSTICS v_restriccion = CONSTRAINT_NAME;
    IF v_restriccion IN ('conceptos_asignacion_id_fkey', 'rondas_asignacion_id_fkey') THEN
      RAISE EXCEPTION 'No se puede eliminar una asignación con rondas o concepto emitido' USING ERRCODE = 'CA126';
    END IF;
    RAISE;
  END;
END
$$;

CREATE OR REPLACE FUNCTION fn_emitir_concepto(p_asignacion_id bigint, p_concepto text, p_observacion text)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path = casino, pg_temp AS $$
DECLARE v_id bigint;
BEGIN
  PERFORM fn_exigir_rol('supervisor');
  INSERT INTO conceptos(asignacion_id, concepto, observacion)
  VALUES (p_asignacion_id, p_concepto, p_observacion) RETURNING id INTO v_id;
  RETURN v_id;
EXCEPTION WHEN unique_violation THEN
  RAISE EXCEPTION 'Ya existe un concepto para esta asignación' USING ERRCODE = 'CA121';
END
$$;

-- Versión definitiva de la función de consulta compartida con André.
CREATE OR REPLACE FUNCTION fn_crupier_asignado(p_mesa_id bigint, p_momento timestamptz)
RETURNS TABLE (asignacion_id bigint, crupier_id bigint, supervisor_id bigint)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = casino, pg_temp AS $$
  SELECT a.id, a.crupier_id, a.supervisor_id
  FROM asignaciones a JOIN turnos t ON t.id = a.turno_id
  JOIN mesas m ON m.id = a.mesa_id
  WHERE a.mesa_id = p_mesa_id AND m.activa
    AND p_momento >= t.inicio AND p_momento < t.fin
$$;

-- Vistas de consulta (columnas snake_case para las Server Actions).
CREATE OR REPLACE VIEW v_juegos AS
SELECT id, nombre, registro_detallado FROM juegos;

CREATE OR REPLACE VIEW v_empleados AS
SELECT e.id, u.usuario, e.nombre, e.documento, e.cargo, e.salario_mensual, e.activo,
       coalesce((SELECT jsonb_agg(jsonb_build_object('juegoId', j.id, 'juego', j.nombre) ORDER BY j.nombre)
         FROM competencias c JOIN juegos j ON j.id = c.juego_id WHERE c.empleado_id = e.id), '[]'::jsonb) AS competencias
FROM empleados e JOIN usuarios u ON u.id = e.usuario_id;

CREATE OR REPLACE VIEW v_mesas AS
SELECT m.id, m.codigo, m.juego_id, j.nombre AS juego, j.registro_detallado,
       m.monto_minimo, m.monto_maximo, m.activa
FROM mesas m JOIN juegos j ON j.id = m.juego_id;

CREATE OR REPLACE VIEW v_jornadas AS SELECT id, fecha FROM jornadas;
CREATE OR REPLACE VIEW v_turnos AS SELECT id, jornada_id, numero, inicio, fin FROM turnos;

CREATE OR REPLACE VIEW v_asignaciones AS
SELECT a.id, a.turno_id, t.numero AS turno_numero, t.inicio, t.fin,
       a.jornada_id, a.mesa_id, m.codigo AS mesa_codigo, j.nombre AS juego,
       a.crupier_id, ec.nombre AS crupier_nombre,
       a.supervisor_id, es.nombre AS supervisor_nombre,
       c.concepto, c.observacion
FROM asignaciones a
JOIN turnos t ON t.id = a.turno_id
JOIN mesas m ON m.id = a.mesa_id
JOIN juegos j ON j.id = m.juego_id
JOIN empleados ec ON ec.id = a.crupier_id
JOIN empleados es ON es.id = a.supervisor_id
LEFT JOIN conceptos c ON c.asignacion_id = a.id;

CREATE OR REPLACE VIEW v_mis_turnos_supervisor AS
SELECT va.* FROM v_asignaciones va
JOIN empleados e ON e.id = va.supervisor_id
JOIN jornadas jo ON jo.id = va.jornada_id
WHERE e.usuario_id = fn_actor() AND jo.fecha = (now() AT TIME ZONE 'America/Bogota')::date;
