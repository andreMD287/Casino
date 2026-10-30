-- 10_auth.sql (André) — autenticación Zero Knowledge (SRP-6a con SHA-256) y sesiones.
-- La BD nunca ve la clave: solo el salt y el verificador v = g^x mod N.
-- Los cálculos SRP se hacen en Node (librería secure-remote-password); aquí se guardan
-- los desafíos, se controla su uso único y vencimiento, el bloqueo por fuerza bruta y las sesiones.
SET ROLE casino_owner;
SET search_path = casino, public;

-- ---------------------------------------------------------------------------
-- Paso 1: datos SRP del usuario (solo si existe y está activo).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_srp_datos_login(p_usuario text)
RETURNS TABLE (id bigint, salt text, verificador text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = casino, pg_temp AS $$
  SELECT u.id, u.salt, u.verificador
  FROM usuarios u
  WHERE u.usuario = lower(trim(p_usuario)) AND u.activo;
$$;

-- ---------------------------------------------------------------------------
-- Guarda el desafío del paso 1 (vence en 2 minutos).
-- p_usuario_id NULL = usuario inexistente (respuesta señuelo).
-- Bloqueo: 5 intentos fallidos en 15 minutos bloquean nuevos desafíos (CA006).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_guardar_desafio(p_usuario_id bigint, p_a_publico text, p_b_publico text, p_b_secreto text)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = casino, pg_temp AS $$
DECLARE
  v_fallidos int;
  v_id uuid;
BEGIN
  IF p_a_publico !~ '^[0-9a-f]+$' OR p_b_publico !~ '^[0-9a-f]+$' OR p_b_secreto !~ '^[0-9a-f]+$'
     OR greatest(length(p_a_publico), length(p_b_publico), length(p_b_secreto)) > 1024 THEN
    RAISE EXCEPTION 'Datos de autenticación inválidos' USING ERRCODE = 'CA011';
  END IF;

  IF p_usuario_id IS NOT NULL THEN
    SELECT count(*) INTO v_fallidos
    FROM desafios_login
    WHERE usuario_id = p_usuario_id
      AND exitoso = false
      AND creado_en > now() - interval '15 minutes';
    IF v_fallidos >= 5 THEN
      RAISE EXCEPTION 'Demasiados intentos fallidos. Intenta de nuevo en 15 minutos' USING ERRCODE = 'CA006';
    END IF;
  END IF;

  INSERT INTO desafios_login (usuario_id, a_publico, b_publico, b_secreto, expira_en)
  VALUES (p_usuario_id, p_a_publico, p_b_publico, p_b_secreto, now() + interval '2 minutes')
  RETURNING id INTO v_id;
  RETURN v_id;
END
$$;

-- ---------------------------------------------------------------------------
-- Paso 2: consume el desafío (uso único). Bloquea la fila para que dos peticiones
-- simultáneas con el mismo id no lo usen dos veces.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_consumir_desafio(p_id uuid)
RETURNS TABLE (usuario_id bigint, usuario text, salt text, verificador text, rol text, a_publico text, b_secreto text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = casino, pg_temp AS $$
DECLARE
  d desafios_login%ROWTYPE;
BEGIN
  SELECT * INTO d FROM desafios_login dl WHERE dl.id = p_id FOR UPDATE;
  IF NOT FOUND OR d.usado_en IS NOT NULL OR d.expira_en <= clock_timestamp() THEN
    RAISE EXCEPTION 'El inicio de sesión venció o ya se usó; intenta de nuevo' USING ERRCODE = 'CA005';
  END IF;

  UPDATE desafios_login dl SET usado_en = clock_timestamp() WHERE dl.id = p_id;

  RETURN QUERY
    SELECT d.usuario_id, u.usuario, u.salt, u.verificador, u.rol, d.a_publico, d.b_secreto
    FROM (SELECT 1) x
    LEFT JOIN usuarios u ON u.id = d.usuario_id AND u.activo;
END
$$;

-- ---------------------------------------------------------------------------
-- Marca el resultado del desafío (cuenta para el bloqueo por fuerza bruta).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_marcar_desafio(p_id uuid, p_exitoso boolean) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = casino, pg_temp AS $$
BEGIN
  UPDATE desafios_login
  SET exitoso = p_exitoso
  WHERE id = p_id AND usado_en IS NOT NULL AND exitoso IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Desafío inválido' USING ERRCODE = 'CA005';
  END IF;
END
$$;

-- ---------------------------------------------------------------------------
-- Crea la sesión. Se guarda SHA-256(token), nunca el token.
-- Defensa en profundidad: exige un desafío exitoso de ese usuario en los últimos 2 minutos,
-- así ni siquiera con el rol de la app se puede crear una sesión sin pasar por SRP.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_crear_sesion(p_usuario_id bigint, p_token_hash text, p_canal text, p_expira timestamptz)
RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path = casino, pg_temp AS $$
DECLARE
  v_id bigint;
BEGIN
  IF p_token_hash !~ '^[0-9a-f]{64}$' OR length(p_canal) < 32 THEN
    RAISE EXCEPTION 'Datos de sesión inválidos' USING ERRCODE = 'CA011';
  END IF;
  IF p_expira > now() + interval '8 hours 1 minute' THEN
    RAISE EXCEPTION 'La sesión no puede durar más de 8 horas' USING ERRCODE = 'CA011';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM desafios_login
    WHERE usuario_id = p_usuario_id AND exitoso AND usado_en > now() - interval '2 minutes'
  ) THEN
    RAISE EXCEPTION 'Usuario o clave incorrectos' USING ERRCODE = 'CA004';
  END IF;

  INSERT INTO sesiones (usuario_id, token_hash, canal, expira_en)
  VALUES (p_usuario_id, p_token_hash, p_canal, p_expira)
  RETURNING id INTO v_id;
  RETURN v_id;
END
$$;

-- ---------------------------------------------------------------------------
-- Sesión vigente: no cerrada, no vencida y de un usuario activo.
-- nombre = nombre del empleado o del jugador (o el usuario si no tiene ficha).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_obtener_sesion(p_token_hash text)
RETURNS TABLE (usuario_id bigint, usuario text, nombre text, rol text, canal text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = casino, pg_temp AS $$
  SELECT u.id, u.usuario, coalesce(e.nombre, j.nombre, u.usuario), u.rol, s.canal
  FROM sesiones s
  JOIN usuarios u ON u.id = s.usuario_id
  LEFT JOIN empleados e ON e.usuario_id = u.id
  LEFT JOIN jugadores j ON j.usuario_id = u.id
  WHERE s.token_hash = p_token_hash
    AND s.cerrada_en IS NULL
    AND s.expira_en > now()
    AND u.activo;
$$;

CREATE OR REPLACE FUNCTION fn_cerrar_sesion(p_token_hash text) RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = casino, pg_temp AS $$
  UPDATE sesiones SET cerrada_en = now()
  WHERE token_hash = p_token_hash AND cerrada_en IS NULL;
$$;

-- ---------------------------------------------------------------------------
-- Registro público de jugadores: crea el usuario (rol jugador) y su ficha.
-- La edad mínima la valida el trigger de Andrés sobre jugadores (no se duplica aquí).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_registrar_jugador(
  p_documento text, p_nombre text, p_fecha_nacimiento date,
  p_usuario text, p_salt text, p_verificador text)
RETURNS TABLE (jugador_id bigint, codigo text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = casino, pg_temp AS $$
DECLARE
  v_usuario_id bigint;
  v_jugador jugadores%ROWTYPE;
BEGIN
  IF coalesce(trim(p_documento), '') = '' OR coalesce(trim(p_nombre), '') = '' OR p_fecha_nacimiento IS NULL THEN
    RAISE EXCEPTION 'Documento, nombre y fecha de nacimiento son obligatorios' USING ERRCODE = 'CA011';
  END IF;

  v_usuario_id := fn_crear_usuario(lower(trim(p_usuario)), p_salt, p_verificador, 'jugador');

  BEGIN
    INSERT INTO jugadores (usuario_id, documento, nombre, fecha_nacimiento)
    VALUES (v_usuario_id, trim(p_documento), trim(p_nombre), p_fecha_nacimiento)
    RETURNING * INTO v_jugador;
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'Ya existe un jugador con el documento %', trim(p_documento) USING ERRCODE = 'CA013';
  END;

  RETURN QUERY SELECT v_jugador.id, v_jugador.codigo;
END
$$;
