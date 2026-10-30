-- 30_rondas_apuestas.sql (André) — gestión de rondas y gestión de apuestas.
-- Reglas de negocio en la BD: los triggers las hacen cumplir incluso con INSERT directo,
-- y las funciones fn_* (SECURITY DEFINER) son la única vía de escritura para la app.
--
-- Orden de bloqueos (para no generar interbloqueos):
--   ronda (FOR UPDATE al cerrar/anular, FOR SHARE al apostar) → jugadores (por id ascendente).
SET ROLE casino_owner;
SET search_path = casino, public;

-- ===========================================================================
-- Auxiliares
-- ===========================================================================

-- Empleado activo del actor (NULL si el actor no es empleado).
CREATE OR REPLACE FUNCTION fn_actor_empleado() RETURNS bigint
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = casino, pg_temp AS $$
  SELECT e.id FROM empleados e WHERE e.usuario_id = fn_actor() AND e.activo;
$$;

-- Motivo por el que un jugador no puede apostar (NULL si puede). Reutiliza fn_puede_apostar,
-- que es exactamente la regla que aplica el trigger de apuestas.
CREATE OR REPLACE FUNCTION fn_motivo_no_apuesta(p_jugador_id bigint) RETURNS text
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = casino, pg_temp AS $$
BEGIN
  PERFORM fn_puede_apostar(p_jugador_id);
  RETURN NULL;
EXCEPTION WHEN OTHERS THEN
  RETURN SQLERRM;
END
$$;

-- Ronda con los datos de su mesa, juego y asignación. Bloquea la ronda según p_modo.
CREATE OR REPLACE FUNCTION fn_ronda_para_operar(p_ronda_id bigint, p_modo text)
RETURNS TABLE (id bigint, mesa_id bigint, estado text, juego_id bigint, registro_detallado boolean, crupier_id bigint)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = casino, pg_temp AS $$
BEGIN
  IF p_modo = 'actualizar' THEN
    PERFORM 1 FROM rondas r WHERE r.id = p_ronda_id FOR UPDATE;
  ELSE
    PERFORM 1 FROM rondas r WHERE r.id = p_ronda_id FOR SHARE;
  END IF;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'La ronda no existe' USING ERRCODE = 'CA215';
  END IF;
  RETURN QUERY
    SELECT r.id, r.mesa_id, r.estado, m.juego_id, j.registro_detallado, a.crupier_id
    FROM rondas r
    JOIN mesas m ON m.id = r.mesa_id
    JOIN juegos j ON j.id = m.juego_id
    JOIN asignaciones a ON a.id = r.asignacion_id
    WHERE r.id = p_ronda_id;
END
$$;

-- ===========================================================================
-- Triggers
-- ===========================================================================

-- BEFORE INSERT en rondas: correlativo por mesa y validación de mesa, asignación y turno.
-- La validación de "turno vigente AHORA" va en fn_abrir_ronda, para permitir semillas históricas.
CREATE OR REPLACE FUNCTION tg_rondas_antes_insertar() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = casino, pg_temp AS $$
DECLARE
  v_activa boolean;
  v_asig_mesa bigint;
  v_t_inicio timestamptz;
  v_t_fin timestamptz;
BEGIN
  -- Bloquear la mesa serializa la asignación del correlativo.
  SELECT m.activa INTO v_activa FROM mesas m WHERE m.id = NEW.mesa_id FOR UPDATE;
  IF NOT FOUND OR NOT v_activa THEN
    RAISE EXCEPTION 'La mesa no existe o no está activa' USING ERRCODE = 'CA201';
  END IF;

  SELECT a.mesa_id, t.inicio, t.fin INTO v_asig_mesa, v_t_inicio, v_t_fin
  FROM asignaciones a JOIN turnos t ON t.id = a.turno_id
  WHERE a.id = NEW.asignacion_id;
  IF NOT FOUND OR v_asig_mesa <> NEW.mesa_id THEN
    RAISE EXCEPTION 'La asignación no corresponde a esta mesa' USING ERRCODE = 'CA201';
  END IF;
  IF NEW.inicio < v_t_inicio OR NEW.inicio >= v_t_fin THEN
    RAISE EXCEPTION 'La ronda debe iniciar dentro del turno de la asignación' USING ERRCODE = 'CA201';
  END IF;

  SELECT coalesce(max(r.numero), 0) + 1 INTO NEW.numero FROM rondas r WHERE r.mesa_id = NEW.mesa_id;
  RETURN NEW;
END
$$;

CREATE TRIGGER tr_rondas_antes_insertar
  BEFORE INSERT ON rondas
  FOR EACH ROW EXECUTE FUNCTION tg_rondas_antes_insertar();

-- BEFORE INSERT en resultados_ronda: la opción debe ser del juego de la mesa de la ronda.
CREATE OR REPLACE FUNCTION tg_resultados_ronda_antes_insertar() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = casino, pg_temp AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM rondas r
    JOIN mesas m ON m.id = r.mesa_id
    JOIN opciones_apuesta o ON o.juego_id = m.juego_id
    WHERE r.id = NEW.ronda_id AND o.id = NEW.opcion_id
  ) THEN
    RAISE EXCEPTION 'El resultado debe ser una opción del juego de la mesa' USING ERRCODE = 'CA202';
  END IF;
  RETURN NEW;
END
$$;

CREATE TRIGGER tr_resultados_ronda_antes_insertar
  BEFORE INSERT ON resultados_ronda
  FOR EACH ROW EXECUTE FUNCTION tg_resultados_ronda_antes_insertar();

-- BEFORE INSERT en apuestas: defensa en profundidad (se cumple aunque se haga INSERT directo).
CREATE OR REPLACE FUNCTION tg_apuestas_antes_insertar() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = casino, pg_temp AS $$
DECLARE
  v_estado text;
  v_juego bigint;
  v_detallado boolean;
  v_min numeric;
  v_max numeric;
  v_o_juego bigint;
  v_o_factor numeric;
  v_o_activa boolean;
BEGIN
  -- FOR SHARE: si otra transacción está cerrando la ronda, se espera y se ve el estado final.
  SELECT r.estado, m.juego_id, j.registro_detallado, m.monto_minimo, m.monto_maximo
    INTO v_estado, v_juego, v_detallado, v_min, v_max
  FROM rondas r
  JOIN mesas m ON m.id = r.mesa_id
  JOIN juegos j ON j.id = m.juego_id
  WHERE r.id = NEW.ronda_id
  FOR SHARE OF r;
  IF NOT FOUND OR v_estado <> 'abierta' THEN
    RAISE EXCEPTION 'La ronda no está abierta' USING ERRCODE = 'CA203';
  END IF;

  SELECT o.juego_id, o.factor_pago, o.activa INTO v_o_juego, v_o_factor, v_o_activa
  FROM opciones_apuesta o WHERE o.id = NEW.opcion_id;
  IF NOT FOUND OR NOT v_o_activa OR v_o_juego <> v_juego THEN
    RAISE EXCEPTION 'La opción de apuesta no está activa o no es del juego de esta mesa' USING ERRCODE = 'CA204';
  END IF;

  IF NEW.monto < v_min OR NEW.monto > v_max THEN
    RAISE EXCEPTION 'El monto debe estar entre % y % en esta mesa', v_min, v_max USING ERRCODE = 'CA205';
  END IF;

  PERFORM fn_puede_apostar(NEW.jugador_id);

  IF NEW.factor_pago <> v_o_factor THEN
    RAISE EXCEPTION 'El factor de pago no coincide con el de la opción (%)', v_o_factor USING ERRCODE = 'CA206';
  END IF;

  -- Juegos con registro detallado: la apuesta nace pendiente. Sin registro detallado: nace resuelta.
  IF v_detallado AND NEW.estado <> 'pendiente' THEN
    RAISE EXCEPTION 'En este juego la apuesta se registra antes del resultado' USING ERRCODE = 'CA210';
  END IF;
  IF NOT v_detallado AND NEW.estado NOT IN ('ganada', 'perdida') THEN
    RAISE EXCEPTION 'Este juego no tiene registro detallado: la apuesta se registra con su resultado' USING ERRCODE = 'CA209';
  END IF;
  RETURN NEW;
END
$$;

CREATE TRIGGER tr_apuestas_antes_insertar
  BEFORE INSERT ON apuestas
  FOR EACH ROW EXECUTE FUNCTION tg_apuestas_antes_insertar();

-- ===========================================================================
-- Rondas
-- ===========================================================================

-- Abre una ronda en la mesa. El actor debe ser el crupier asignado a la mesa en el turno vigente.
CREATE OR REPLACE FUNCTION fn_abrir_ronda(p_mesa_id bigint) RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path = casino, pg_temp AS $$
DECLARE
  v_asignacion bigint;
  v_id bigint;
  v_restriccion text;
BEGIN
  PERFORM fn_exigir_rol('crupier');

  SELECT ca.asignacion_id INTO v_asignacion
  FROM fn_crupier_asignado(p_mesa_id, now()) ca
  WHERE ca.crupier_id = fn_actor_empleado();
  IF v_asignacion IS NULL THEN
    RAISE EXCEPTION 'No eres el crupier asignado a esta mesa en el turno actual' USING ERRCODE = 'CA207';
  END IF;

  BEGIN
    INSERT INTO rondas (mesa_id, asignacion_id) VALUES (p_mesa_id, v_asignacion)
    RETURNING id INTO v_id;
  EXCEPTION WHEN unique_violation THEN
    GET STACKED DIAGNOSTICS v_restriccion = CONSTRAINT_NAME;
    IF v_restriccion = 'ux_rondas_una_abierta_por_mesa' THEN
      RAISE EXCEPTION 'Ya hay una ronda abierta en esta mesa' USING ERRCODE = 'CA208';
    END IF;
    RAISE;
  END;
  RETURN v_id;
END
$$;

-- Cierra la ronda con su resultado y liquida todas las apuestas pendientes (una sola transacción).
CREATE OR REPLACE FUNCTION fn_cerrar_ronda(p_ronda_id bigint, p_opciones bigint[])
RETURNS TABLE (ganadas int, perdidas int, total_apostado numeric, total_premios numeric, resultado_casino numeric)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = casino, pg_temp AS $$
DECLARE
  r record;
  a record;
  v_opciones bigint[] := coalesce(p_opciones, '{}');
  v_premio numeric(14,2);
  v_jugadores bigint[] := '{}';
  v_jugador bigint;
BEGIN
  PERFORM fn_exigir_rol('crupier');

  -- 1. Bloquear la ronda y verificar que siga abierta (evita el doble cierre).
  SELECT * INTO r FROM fn_ronda_para_operar(p_ronda_id, 'actualizar');
  IF r.estado <> 'abierta' THEN
    RAISE EXCEPTION 'La ronda no está abierta' USING ERRCODE = 'CA203';
  END IF;

  -- 2. El actor debe ser el crupier de la asignación de la ronda.
  IF r.crupier_id IS DISTINCT FROM fn_actor_empleado() THEN
    RAISE EXCEPTION 'No eres el crupier asignado a esta ronda' USING ERRCODE = 'CA207';
  END IF;

  -- 3. Resultado.
  IF r.registro_detallado THEN
    IF cardinality(v_opciones) = 0 THEN
      RAISE EXCEPTION 'Debes indicar al menos una opción ganadora' USING ERRCODE = 'CA212';
    END IF;
    INSERT INTO resultados_ronda (ronda_id, opcion_id)
    SELECT DISTINCT p_ronda_id, o FROM unnest(v_opciones) AS o;
  ELSIF cardinality(v_opciones) > 0 THEN
    RAISE EXCEPTION 'Las rondas de juegos sin registro detallado se cierran sin resultado' USING ERRCODE = 'CA216';
  END IF;

  -- 4. Liquidar las apuestas pendientes (por jugador ascendente: orden fijo de bloqueos).
  FOR a IN
    SELECT ap.id, ap.jugador_id, ap.opcion_id, ap.monto, ap.factor_pago
    FROM apuestas ap
    WHERE ap.ronda_id = p_ronda_id AND ap.estado = 'pendiente'
    ORDER BY ap.jugador_id, ap.id
    FOR UPDATE
  LOOP
    IF a.opcion_id = ANY (v_opciones) THEN
      v_premio := round(a.monto * a.factor_pago, 2);
      UPDATE apuestas SET estado = 'ganada', premio = v_premio, liquidada_en = clock_timestamp() WHERE id = a.id;
      PERFORM fn_mover_saldo(a.jugador_id, 'devolucion', a.monto, a.id);
      PERFORM fn_mover_saldo(a.jugador_id, 'premio', v_premio, a.id);
    ELSE
      -- Perdida: no hay movimiento, el monto ya quedó en el casino al apostar.
      UPDATE apuestas SET estado = 'perdida', liquidada_en = clock_timestamp() WHERE id = a.id;
    END IF;
    IF NOT (a.jugador_id = ANY (v_jugadores)) THEN
      v_jugadores := v_jugadores || a.jugador_id;
    END IF;
  END LOOP;

  -- 5. Cerrar la ronda (clock_timestamp: now() repetiría la hora de inicio de la transacción).
  UPDATE rondas SET estado = 'cerrada', cierre = clock_timestamp() WHERE id = p_ronda_id;

  -- 6. Evaluar el riesgo de cada jugador afectado.
  FOREACH v_jugador IN ARRAY v_jugadores LOOP
    PERFORM fn_evaluar_riesgo(v_jugador);
  END LOOP;

  -- 7. Resumen de la ronda.
  RETURN QUERY
    SELECT count(*) FILTER (WHERE ap.estado = 'ganada')::int,
           count(*) FILTER (WHERE ap.estado = 'perdida')::int,
           coalesce(sum(ap.monto), 0)::numeric(14,2),
           coalesce(sum(ap.premio), 0)::numeric(14,2),
           (coalesce(sum(ap.monto) FILTER (WHERE ap.estado = 'perdida'), 0) - coalesce(sum(ap.premio), 0))::numeric(14,2)
    FROM apuestas ap
    WHERE ap.ronda_id = p_ronda_id AND ap.estado IN ('ganada', 'perdida');
END
$$;

-- Anula una ronda abierta: devuelve todas sus apuestas pendientes.
-- Puede hacerlo el crupier de la ronda o un administrador.
CREATE OR REPLACE FUNCTION fn_anular_ronda(p_ronda_id bigint) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = casino, pg_temp AS $$
DECLARE
  r record;
  a record;
BEGIN
  PERFORM fn_exigir_rol('crupier', 'administrador');
  SELECT * INTO r FROM fn_ronda_para_operar(p_ronda_id, 'actualizar');
  IF r.estado <> 'abierta' THEN
    RAISE EXCEPTION 'Solo se puede anular una ronda abierta' USING ERRCODE = 'CA203';
  END IF;
  IF (SELECT u.rol FROM usuarios u WHERE u.id = fn_actor()) = 'crupier'
     AND r.crupier_id IS DISTINCT FROM fn_actor_empleado() THEN
    RAISE EXCEPTION 'No eres el crupier asignado a esta ronda' USING ERRCODE = 'CA207';
  END IF;

  FOR a IN
    SELECT ap.id, ap.jugador_id, ap.monto FROM apuestas ap
    WHERE ap.ronda_id = p_ronda_id AND ap.estado = 'pendiente'
    ORDER BY ap.jugador_id, ap.id
    FOR UPDATE
  LOOP
    UPDATE apuestas SET estado = 'anulada' WHERE id = a.id;
    PERFORM fn_mover_saldo(a.jugador_id, 'devolucion', a.monto, a.id);
  END LOOP;

  UPDATE rondas SET estado = 'anulada', cierre = clock_timestamp() WHERE id = p_ronda_id;
END
$$;

-- ===========================================================================
-- Apuestas
-- ===========================================================================

-- Validaciones comunes a los dos tipos de registro. Devuelve el factor de la opción.
-- Bloquea primero la ronda (FOR SHARE) y luego al jugador (FOR UPDATE), antes de leer el saldo.
CREATE OR REPLACE FUNCTION fn_preparar_apuesta(p_ronda_id bigint, p_jugador_id bigint, p_opcion_id bigint, p_detallado_esperado boolean)
RETURNS numeric
LANGUAGE plpgsql SECURITY DEFINER SET search_path = casino, pg_temp AS $$
DECLARE
  r record;
  v_factor numeric;
BEGIN
  PERFORM fn_exigir_rol('crupier');
  SELECT * INTO r FROM fn_ronda_para_operar(p_ronda_id, 'compartir');
  IF r.crupier_id IS DISTINCT FROM fn_actor_empleado() THEN
    RAISE EXCEPTION 'No eres el crupier asignado a esta ronda' USING ERRCODE = 'CA207';
  END IF;
  IF p_detallado_esperado AND NOT r.registro_detallado THEN
    RAISE EXCEPTION 'Este juego no tiene registro detallado: registra la apuesta con su resultado' USING ERRCODE = 'CA209';
  END IF;
  IF NOT p_detallado_esperado AND r.registro_detallado THEN
    RAISE EXCEPTION 'Este juego tiene registro detallado: registra la apuesta antes del resultado' USING ERRCODE = 'CA210';
  END IF;

  PERFORM 1 FROM jugadores j WHERE j.id = p_jugador_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'El jugador no existe' USING ERRCODE = 'CA012';
  END IF;

  SELECT o.factor_pago INTO v_factor FROM opciones_apuesta o WHERE o.id = p_opcion_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'La opción de apuesta no existe' USING ERRCODE = 'CA204';
  END IF;
  RETURN v_factor;
END
$$;

-- Registra una apuesta pendiente (juegos con registro detallado) y descuenta el monto.
CREATE OR REPLACE FUNCTION fn_registrar_apuesta(p_ronda_id bigint, p_jugador_id bigint, p_opcion_id bigint, p_monto numeric)
RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path = casino, pg_temp AS $$
DECLARE
  v_factor numeric;
  v_id bigint;
BEGIN
  v_factor := fn_preparar_apuesta(p_ronda_id, p_jugador_id, p_opcion_id, true);
  INSERT INTO apuestas (ronda_id, jugador_id, opcion_id, monto, factor_pago, registrada_por)
  VALUES (p_ronda_id, p_jugador_id, p_opcion_id, p_monto, v_factor, fn_actor())
  RETURNING id INTO v_id;
  PERFORM fn_mover_saldo(p_jugador_id, 'apuesta', p_monto, v_id);   -- CA010 si no alcanza
  RETURN v_id;
END
$$;

-- Póker (sin registro detallado): registra la apuesta ya resuelta, descuenta y, si ganó, acredita.
CREATE OR REPLACE FUNCTION fn_registrar_apuesta_resuelta(p_ronda_id bigint, p_jugador_id bigint, p_opcion_id bigint, p_monto numeric, p_ganada boolean)
RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path = casino, pg_temp AS $$
DECLARE
  v_factor numeric;
  v_premio numeric(14,2);
  v_id bigint;
BEGIN
  IF p_ganada IS NULL THEN
    RAISE EXCEPTION 'Indica si la apuesta fue ganada o perdida' USING ERRCODE = 'CA011';
  END IF;
  v_factor := fn_preparar_apuesta(p_ronda_id, p_jugador_id, p_opcion_id, false);
  v_premio := CASE WHEN p_ganada THEN round(p_monto * v_factor, 2) END;

  INSERT INTO apuestas (ronda_id, jugador_id, opcion_id, monto, factor_pago, estado, premio, liquidada_en, registrada_por)
  VALUES (p_ronda_id, p_jugador_id, p_opcion_id, p_monto, v_factor,
          CASE WHEN p_ganada THEN 'ganada' ELSE 'perdida' END, v_premio, clock_timestamp(), fn_actor())
  RETURNING id INTO v_id;

  PERFORM fn_mover_saldo(p_jugador_id, 'apuesta', p_monto, v_id);   -- CA010 si no alcanza
  IF p_ganada THEN
    PERFORM fn_mover_saldo(p_jugador_id, 'devolucion', p_monto, v_id);
    PERFORM fn_mover_saldo(p_jugador_id, 'premio', v_premio, v_id);
  END IF;
  PERFORM fn_evaluar_riesgo(p_jugador_id);
  RETURN v_id;
END
$$;

-- Anula una apuesta pendiente de una ronda abierta y devuelve el monto.
CREATE OR REPLACE FUNCTION fn_anular_apuesta(p_apuesta_id bigint) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = casino, pg_temp AS $$
DECLARE
  v_ronda bigint;
  r record;
  ap record;
BEGIN
  PERFORM fn_exigir_rol('crupier');
  SELECT a.ronda_id INTO v_ronda FROM apuestas a WHERE a.id = p_apuesta_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'La apuesta no existe' USING ERRCODE = 'CA215';
  END IF;

  SELECT * INTO r FROM fn_ronda_para_operar(v_ronda, 'compartir');
  IF r.crupier_id IS DISTINCT FROM fn_actor_empleado() THEN
    RAISE EXCEPTION 'No eres el crupier asignado a esta ronda' USING ERRCODE = 'CA207';
  END IF;

  SELECT a.id, a.jugador_id, a.monto, a.estado INTO ap FROM apuestas a WHERE a.id = p_apuesta_id FOR UPDATE;
  IF ap.estado <> 'pendiente' OR r.estado <> 'abierta' THEN
    RAISE EXCEPTION 'Solo se puede anular una apuesta pendiente de una ronda abierta' USING ERRCODE = 'CA211';
  END IF;

  UPDATE apuestas SET estado = 'anulada' WHERE id = p_apuesta_id;
  PERFORM fn_mover_saldo(ap.jugador_id, 'devolucion', ap.monto, p_apuesta_id);
END
$$;

-- ===========================================================================
-- CRUD de opciones de apuesta (solo administrador). "Eliminar" = desactivar.
-- ===========================================================================

CREATE OR REPLACE FUNCTION fn_crear_opcion(p_juego_id bigint, p_nombre text, p_factor numeric) RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path = casino, pg_temp AS $$
DECLARE
  v_id bigint;
BEGIN
  PERFORM fn_exigir_rol('administrador');
  IF NOT EXISTS (SELECT 1 FROM juegos WHERE id = p_juego_id) THEN
    RAISE EXCEPTION 'El juego no existe' USING ERRCODE = 'CA215';
  END IF;
  IF coalesce(trim(p_nombre), '') = '' OR p_factor IS NULL OR p_factor <= 0 THEN
    RAISE EXCEPTION 'El nombre es obligatorio y el factor debe ser mayor que cero' USING ERRCODE = 'CA011';
  END IF;
  INSERT INTO opciones_apuesta (juego_id, nombre, factor_pago) VALUES (p_juego_id, trim(p_nombre), p_factor)
  RETURNING id INTO v_id;
  RETURN v_id;
EXCEPTION WHEN unique_violation THEN
  RAISE EXCEPTION 'Ya existe una opción con ese nombre en el juego' USING ERRCODE = 'CA214';
END
$$;

CREATE OR REPLACE FUNCTION fn_actualizar_opcion(p_id bigint, p_nombre text, p_factor numeric) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = casino, pg_temp AS $$
DECLARE
  v_factor numeric;
BEGIN
  PERFORM fn_exigir_rol('administrador');
  IF coalesce(trim(p_nombre), '') = '' OR p_factor IS NULL OR p_factor <= 0 THEN
    RAISE EXCEPTION 'El nombre es obligatorio y el factor debe ser mayor que cero' USING ERRCODE = 'CA011';
  END IF;
  SELECT factor_pago INTO v_factor FROM opciones_apuesta WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'La opción de apuesta no existe' USING ERRCODE = 'CA215';
  END IF;
  IF v_factor <> p_factor AND EXISTS (SELECT 1 FROM apuestas WHERE opcion_id = p_id AND estado = 'pendiente') THEN
    RAISE EXCEPTION 'No se puede cambiar el factor: la opción tiene apuestas pendientes' USING ERRCODE = 'CA213';
  END IF;
  UPDATE opciones_apuesta SET nombre = trim(p_nombre), factor_pago = p_factor WHERE id = p_id;
EXCEPTION WHEN unique_violation THEN
  RAISE EXCEPTION 'Ya existe una opción con ese nombre en el juego' USING ERRCODE = 'CA214';
END
$$;

CREATE OR REPLACE FUNCTION fn_desactivar_opcion(p_id bigint) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = casino, pg_temp AS $$
BEGIN
  PERFORM fn_exigir_rol('administrador');
  UPDATE opciones_apuesta SET activa = false WHERE id = p_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'La opción de apuesta no existe' USING ERRCODE = 'CA215';
  END IF;
END
$$;

-- ===========================================================================
-- Vistas (lectura para la app)
-- ===========================================================================

CREATE OR REPLACE VIEW v_opciones AS
SELECT o.id, o.juego_id, o.nombre, o.factor_pago, o.activa
FROM opciones_apuesta o;

CREATE OR REPLACE VIEW v_rondas AS
SELECT r.id, r.mesa_id, m.codigo AS mesa_codigo, r.asignacion_id, r.numero, r.inicio, r.cierre, r.estado,
       coalesce((SELECT jsonb_agg(jsonb_build_object('opcionId', o.id, 'nombre', o.nombre) ORDER BY o.id)
                 FROM resultados_ronda rr JOIN opciones_apuesta o ON o.id = rr.opcion_id
                 WHERE rr.ronda_id = r.id), '[]'::jsonb) AS resultado
FROM rondas r
JOIN mesas m ON m.id = r.mesa_id;

CREATE OR REPLACE VIEW v_apuestas AS
SELECT a.id, a.ronda_id, m.codigo AS mesa_codigo, r.numero AS ronda_numero,
       a.jugador_id, j.codigo AS jugador_codigo, j.nombre AS jugador_nombre,
       a.opcion_id, o.nombre AS opcion, a.monto, a.factor_pago, a.estado, a.premio,
       a.creada_en, a.liquidada_en
FROM apuestas a
JOIN rondas r ON r.id = a.ronda_id
JOIN mesas m ON m.id = r.mesa_id
JOIN jugadores j ON j.id = a.jugador_id
JOIN opciones_apuesta o ON o.id = a.opcion_id;

-- Mesas del crupier actor en el turno vigente, con su ronda abierta (si hay).
CREATE OR REPLACE VIEW v_mis_mesas_actuales AS
SELECT a.id AS asignacion_id,
       m.id AS mesa_id, m.codigo AS mesa_codigo, m.juego_id, jg.nombre AS juego, jg.registro_detallado,
       m.monto_minimo, m.monto_maximo, m.activa AS mesa_activa,
       t.inicio AS inicio_turno, t.fin AS fin_turno,
       (SELECT r.id FROM rondas r WHERE r.mesa_id = m.id AND r.estado = 'abierta') AS ronda_abierta_id
FROM asignaciones a
JOIN turnos t ON t.id = a.turno_id
JOIN mesas m ON m.id = a.mesa_id
JOIN juegos jg ON jg.id = m.juego_id
JOIN empleados e ON e.id = a.crupier_id
WHERE e.usuario_id = fn_actor()
  AND now() >= t.inicio AND now() < t.fin;

-- Jugador buscado por el crupier para registrar una apuesta.
-- puede_apostar/motivo salen de fn_puede_apostar (la misma regla que aplica el trigger).
CREATE OR REPLACE VIEW v_jugador_para_apuesta AS
SELECT x.jugador_id, x.codigo, x.nombre, x.saldo, x.motivo IS NULL AS puede_apostar, x.motivo
FROM (
  SELECT j.id AS jugador_id, j.codigo, j.nombre, j.saldo, fn_motivo_no_apuesta(j.id) AS motivo
  FROM jugadores j
) x;

-- Reporte por asignación (mesa y turno). Resultado nominal del casino = montos perdidos − premios.
-- Se muestra junto al concepto del supervisor para evidenciar que son independientes.
CREATE OR REPLACE VIEW v_reporte_mesa_turno AS
SELECT a.id AS asignacion_id, jo.id AS jornada_id, jo.fecha, t.numero AS turno_numero,
       m.codigo AS mesa_codigo, ec.nombre AS crupier, es.nombre AS supervisor,
       coalesce(sum(ap.monto) FILTER (WHERE ap.estado IN ('ganada', 'perdida')), 0)::numeric(14,2) AS total_apostado,
       coalesce(sum(ap.premio), 0)::numeric(14,2) AS total_premios,
       (coalesce(sum(ap.monto) FILTER (WHERE ap.estado = 'perdida'), 0) - coalesce(sum(ap.premio), 0))::numeric(14,2) AS resultado_nominal,
       c.concepto
FROM asignaciones a
JOIN turnos t ON t.id = a.turno_id
JOIN jornadas jo ON jo.id = t.jornada_id
JOIN mesas m ON m.id = a.mesa_id
JOIN empleados ec ON ec.id = a.crupier_id
JOIN empleados es ON es.id = a.supervisor_id
LEFT JOIN conceptos c ON c.asignacion_id = a.id
LEFT JOIN rondas r ON r.asignacion_id = a.id
LEFT JOIN apuestas ap ON ap.ronda_id = r.id
GROUP BY a.id, jo.id, jo.fecha, t.numero, m.codigo, ec.nombre, es.nombre, c.concepto;
