-- 05_contrato.sql (André) — funciones compartidas del contrato A6.
-- Las de André tienen implementación real. Las de Andrés son stubs con la misma firma;
-- él las reemplaza con CREATE OR REPLACE en 20_personal_mesas.sql / 40_riesgo_historial.sql.
SET ROLE casino_owner;
SET search_path = casino, public;

-- ---------------------------------------------------------------------------
-- fn_actor: usuario de la transacción (lo fija el backend con SET LOCAL app.usuario_id).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_actor() RETURNS bigint
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = casino, pg_temp AS $$
DECLARE
  v text := current_setting('app.usuario_id', true);
BEGIN
  IF v IS NULL OR v = '' THEN
    RAISE EXCEPTION 'No hay un usuario autenticado en esta operación' USING ERRCODE = 'CA001';
  END IF;
  RETURN v::bigint;
END
$$;

-- ---------------------------------------------------------------------------
-- fn_exigir_rol: el actor debe estar activo y tener uno de los roles indicados.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_exigir_rol(VARIADIC p_roles text[]) RETURNS void
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = casino, pg_temp AS $$
DECLARE
  v_rol text;
BEGIN
  SELECT u.rol INTO v_rol FROM usuarios u WHERE u.id = fn_actor() AND u.activo;
  IF v_rol IS NULL OR NOT (v_rol = ANY (p_roles)) THEN
    RAISE EXCEPTION 'No tienes permiso para esta operación' USING ERRCODE = 'CA002';
  END IF;
END
$$;

-- ---------------------------------------------------------------------------
-- fn_crear_usuario (interna): crea un usuario con su salt y verificador SRP.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_crear_usuario(p_usuario text, p_salt text, p_verificador text, p_rol text) RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path = casino, pg_temp AS $$
DECLARE
  v_id bigint;
BEGIN
  INSERT INTO usuarios (usuario, salt, verificador, rol)
  VALUES (p_usuario, p_salt, p_verificador, p_rol)
  RETURNING id INTO v_id;
  RETURN v_id;
EXCEPTION
  WHEN unique_violation THEN
    RAISE EXCEPTION 'El usuario "%" ya existe', p_usuario USING ERRCODE = 'CA003';
  WHEN check_violation THEN
    RAISE EXCEPTION 'Usuario o rol inválido: el usuario debe tener de 3 a 30 caracteres (a-z, 0-9, _ o .)' USING ERRCODE = 'CA011';
END
$$;

-- ---------------------------------------------------------------------------
-- fn_mover_saldo (interna): ÚNICA forma de cambiar jugadores.saldo.
-- consignacion, devolucion y premio suman; retiro y apuesta restan.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_mover_saldo(p_jugador_id bigint, p_tipo text, p_monto numeric, p_apuesta_id bigint DEFAULT NULL)
RETURNS numeric
LANGUAGE plpgsql SECURITY DEFINER SET search_path = casino, pg_temp AS $$
DECLARE
  v_saldo numeric(14,2);
  v_nuevo numeric(14,2);
BEGIN
  IF p_tipo NOT IN ('consignacion', 'retiro', 'apuesta', 'devolucion', 'premio') THEN
    RAISE EXCEPTION 'Tipo de movimiento inválido: %', p_tipo USING ERRCODE = 'CA011';
  END IF;
  IF p_monto IS NULL OR p_monto <= 0 THEN
    RAISE EXCEPTION 'El monto debe ser mayor que cero' USING ERRCODE = 'CA011';
  END IF;

  -- Bloquea la fila del jugador: dos movimientos simultáneos se serializan aquí.
  SELECT saldo INTO v_saldo FROM jugadores WHERE id = p_jugador_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'El jugador no existe' USING ERRCODE = 'CA012';
  END IF;

  v_nuevo := CASE WHEN p_tipo IN ('retiro', 'apuesta') THEN v_saldo - p_monto ELSE v_saldo + p_monto END;
  IF v_nuevo < 0 THEN
    RAISE EXCEPTION 'Saldo insuficiente: el jugador tiene % y se necesitan %', v_saldo, p_monto USING ERRCODE = 'CA010';
  END IF;

  UPDATE jugadores SET saldo = v_nuevo WHERE id = p_jugador_id;
  INSERT INTO movimientos_saldo (jugador_id, tipo, monto, saldo_resultante, apuesta_id, creado_por)
  VALUES (p_jugador_id, p_tipo, p_monto, v_nuevo, p_apuesta_id, nullif(current_setting('app.usuario_id', true), '')::bigint);
  RETURN v_nuevo;
END
$$;

-- ---------------------------------------------------------------------------
-- STUBS de Andrés (los reemplaza él). Misma firma que en el contrato.
-- ---------------------------------------------------------------------------

-- Stub funcional: asignación de la mesa en el turno que contiene ese momento.
CREATE OR REPLACE FUNCTION fn_crupier_asignado(p_mesa_id bigint, p_momento timestamptz)
RETURNS TABLE (asignacion_id bigint, crupier_id bigint, supervisor_id bigint)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = casino, pg_temp AS $$
  SELECT a.id, a.crupier_id, a.supervisor_id
  FROM asignaciones a
  JOIN turnos t ON t.id = a.turno_id
  WHERE a.mesa_id = p_mesa_id
    AND p_momento >= t.inicio AND p_momento < t.fin;
$$;

-- Stub vacío: lanza CA301 (inactivo), CA302 (suspendido hasta X) o CA303 (en investigación).
CREATE OR REPLACE FUNCTION fn_puede_apostar(p_jugador_id bigint) RETURNS void
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = casino, pg_temp AS $$
BEGIN
  RETURN;
END
$$;

-- Stub vacío: aplica A2.7, A2.9 y A2.10 después de cada liquidación y cada abono.
CREATE OR REPLACE FUNCTION fn_evaluar_riesgo(p_jugador_id bigint) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = casino, pg_temp AS $$
BEGIN
  RETURN;
END
$$;
