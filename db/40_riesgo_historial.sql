-- Modulo 40 (Andres): jugadores, autorizaciones, riesgo e historial.
-- Ajustes acordados con Andre (2026-11-02), sujetos a confirmacion de Hania
-- para actualizar el contrato comun:
-- 1) Perdida diaria BRUTA: suma de apuestas perdidas liquidadas hoy.
-- 2) Cuenta de empleado asignado a turno vigente: apuesta bloqueada (CA311).
-- 3) Administrador no cierra investigacion sobre su propia cuenta (CA310).
-- CA308 permanece reservado para la restriccion de retiros en investigacion
-- del plan original; no se reutiliza para el bloqueo por turno.
SET ROLE casino_owner;
SET search_path = casino, public;

-- Comprobar edad y documento incluso en INSERT/UPDATE SQL directos.
CREATE OR REPLACE FUNCTION tg_validar_jugador() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = casino, pg_temp AS $$
BEGIN
  IF NEW.fecha_nacimiento IS NULL OR NEW.fecha_nacimiento >
    ((now() AT TIME ZONE 'America/Bogota')::date - interval '18 years')::date THEN
    RAISE EXCEPTION 'Debe ser mayor de edad (18 anos cumplidos)' USING ERRCODE = 'CA304';
  END IF;
  IF NEW.documento IS NULL OR NEW.documento !~ '^[0-9]{6,12}$' THEN
    RAISE EXCEPTION 'El documento debe tener entre 6 y 12 digitos' USING ERRCODE = 'CA309';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER tr_validar_jugador BEFORE INSERT OR UPDATE OF fecha_nacimiento, documento ON jugadores
FOR EACH ROW EXECUTE FUNCTION tg_validar_jugador();

-- La funcion se invoca desde el trigger de apuestas y tambien desde las vistas.
-- Mantener EXACTAMENTE la firma de 05_contrato.sql.
CREATE OR REPLACE FUNCTION fn_puede_apostar(p_jugador_id bigint) RETURNS void
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = casino, pg_temp AS $$
DECLARE
  v_activo boolean;
  v_investigacion boolean;
  v_suspension record;
BEGIN
  SELECT (j.activo AND u.activo) INTO v_activo
  FROM jugadores j JOIN usuarios u ON u.id = j.usuario_id WHERE j.id = p_jugador_id;
  IF NOT FOUND OR NOT v_activo THEN
    RAISE EXCEPTION 'El jugador no existe o esta inactivo' USING ERRCODE = 'CA301';
  END IF;

  SELECT EXISTS (SELECT 1 FROM investigaciones i
                 WHERE i.jugador_id = p_jugador_id AND i.cerrada_en IS NULL)
    INTO v_investigacion;
  IF v_investigacion THEN
    RAISE EXCEPTION 'El jugador tiene una investigacion abierta y no puede apostar' USING ERRCODE = 'CA303';
  END IF;

  SELECT s.motivo, s.fin INTO v_suspension FROM suspensiones s
  WHERE s.jugador_id = p_jugador_id AND s.levantada_en IS NULL
    AND ((s.motivo = 'deuda_empleado' AND s.fin IS NULL) OR (s.fin > now()))
  ORDER BY CASE WHEN s.motivo = 'deuda_empleado' THEN 0 ELSE 1 END, s.fin DESC NULLS FIRST
  LIMIT 1;
  IF FOUND THEN
    IF v_suspension.motivo = 'deuda_empleado' THEN
      RAISE EXCEPTION 'Jugador suspendido hasta saldar la deuda del empleado' USING ERRCODE = 'CA302';
    ELSE
      RAISE EXCEPTION 'Jugador suspendido hasta %',
        to_char(v_suspension.fin AT TIME ZONE 'America/Bogota', 'YYYY-MM-DD HH24:MI')
        USING ERRCODE = 'CA302';
    END IF;
  END IF;

  -- El empleado-jugador no puede apostar mientras opera o supervisa una mesa.
  -- Se valida desde la BD, tanto para acciones como INSERT directos de apuestas.
  -- El inicio es inclusivo y el fin exclusivo: [inicio, fin).
  IF EXISTS (
    SELECT 1 FROM jugadores j
    JOIN asignaciones a ON (j.empleado_id = a.crupier_id OR j.empleado_id = a.supervisor_id)
    JOIN turnos t ON t.id = a.turno_id
    WHERE j.id = p_jugador_id AND j.empleado_id IS NOT NULL
      AND now() >= t.inicio AND now() < t.fin
  ) THEN
    RAISE EXCEPTION 'El empleado esta en turno y no puede apostar'
      USING ERRCODE = 'CA311';
  END IF;
END $$;

-- Se ejecuta tras liquidar apuestas, y despues de abonos de empleados.
-- Las filas de jugador se bloquean para hacer idempotentes las evaluaciones
-- concurrentes y para ordenar correctamente el cambio de estado.
CREATE OR REPLACE FUNCTION fn_evaluar_riesgo(p_jugador_id bigint) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = casino, pg_temp AS $$
DECLARE
  v_empleado bigint;
  v_salario numeric;
  v_umbral numeric;
  v_perdida_dia numeric;
  v_deuda numeric;
  v_ganancia_periodo numeric;
  v_ultimo_cierre timestamptz;
BEGIN
  SELECT j.empleado_id, e.salario_mensual INTO v_empleado, v_salario
  FROM jugadores j LEFT JOIN empleados e ON e.id = j.empleado_id
  WHERE j.id = p_jugador_id FOR UPDATE OF j;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Jugador inexistente' USING ERRCODE = 'CA301';
  END IF;

  SELECT valor INTO v_umbral FROM configuracion WHERE clave = 'umbral_perdida_diaria';
  -- Especificacion del grupo, punto 9: perdida diaria BRUTA.
  -- Se suman solamente los montos de apuestas PERDIDAS liquidadas hoy
  -- (fecha local de Bogota). Los premios no compensan esas perdidas.
  -- Esta definicion NO cambia la deuda ni la ganancia neta de empleados.
  SELECT coalesce(sum(a.monto), 0)
    INTO v_perdida_dia
  FROM apuestas a WHERE a.jugador_id = p_jugador_id
    AND (a.liquidada_en AT TIME ZONE 'America/Bogota')::date =
        (now() AT TIME ZONE 'America/Bogota')::date
    AND a.estado = 'perdida';

  IF v_umbral IS NOT NULL AND v_perdida_dia > v_umbral AND NOT EXISTS (
    SELECT 1 FROM suspensiones s WHERE s.jugador_id = p_jugador_id
      AND s.motivo = 'perdida_diaria' AND s.levantada_en IS NULL AND s.fin > now()
  ) THEN
    INSERT INTO suspensiones(jugador_id, motivo, fin)
      VALUES (p_jugador_id, 'perdida_diaria', now() + interval '24 hours');
  END IF;

  IF v_empleado IS NULL THEN RETURN; END IF;

  -- Contrato A2.9: deuda historica = perdidas - premios - abonos.
  SELECT coalesce(sum(CASE WHEN a.estado = 'perdida' THEN a.monto
                           WHEN a.estado = 'ganada' THEN -coalesce(a.premio, 0)
                           ELSE 0 END), 0)
    INTO v_deuda
  FROM apuestas a WHERE a.jugador_id = p_jugador_id
    AND a.estado IN ('ganada', 'perdida');
  v_deuda := v_deuda - coalesce((SELECT sum(b.monto) FROM abonos_empleado b
                                WHERE b.empleado_id = v_empleado), 0);

  IF v_deuda > 2 * v_salario THEN
    IF NOT EXISTS (SELECT 1 FROM suspensiones s WHERE s.jugador_id = p_jugador_id
                   AND s.motivo = 'deuda_empleado' AND s.levantada_en IS NULL) THEN
      INSERT INTO suspensiones(jugador_id, motivo)
        VALUES (p_jugador_id, 'deuda_empleado');
    END IF;
  ELSE
    UPDATE suspensiones SET levantada_en = now()
    WHERE jugador_id = p_jugador_id AND motivo = 'deuda_empleado'
      AND levantada_en IS NULL;
  END IF;

  -- Contrato A2.10: ganancias desde la ultima investigacion cerrada.
  SELECT max(i.cerrada_en) INTO v_ultimo_cierre FROM investigaciones i
  WHERE i.jugador_id = p_jugador_id AND i.cerrada_en IS NOT NULL;
  SELECT coalesce(sum(CASE WHEN a.estado = 'ganada' THEN coalesce(a.premio, 0)
                           WHEN a.estado = 'perdida' THEN -a.monto
                           ELSE 0 END), 0)
    INTO v_ganancia_periodo
  FROM apuestas a WHERE a.jugador_id = p_jugador_id
    AND a.estado IN ('ganada', 'perdida')
    AND (v_ultimo_cierre IS NULL OR a.liquidada_en > v_ultimo_cierre);
  IF v_ganancia_periodo > v_salario AND NOT EXISTS (
    SELECT 1 FROM investigaciones i WHERE i.jugador_id = p_jugador_id
      AND i.cerrada_en IS NULL
  ) THEN
    INSERT INTO investigaciones(jugador_id) VALUES (p_jugador_id);
  END IF;
END $$;

CREATE OR REPLACE FUNCTION fn_solicitar_pausa() RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path = casino, pg_temp AS $$
DECLARE v_jugador_id bigint; v_id bigint;
BEGIN
  PERFORM fn_exigir_rol('jugador');
  SELECT id INTO v_jugador_id FROM jugadores WHERE usuario_id = fn_actor() AND activo FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'No existe una cuenta de jugador activa' USING ERRCODE = 'CA301'; END IF;
  IF EXISTS (SELECT 1 FROM suspensiones s WHERE s.jugador_id = v_jugador_id
      AND s.motivo = 'pausa_voluntaria' AND s.levantada_en IS NULL AND s.fin > now()) THEN
    RAISE EXCEPTION 'Ya tienes una pausa voluntaria activa' USING ERRCODE = 'CA305';
  END IF;
  INSERT INTO suspensiones(jugador_id, motivo, fin)
  VALUES(v_jugador_id, 'pausa_voluntaria', now() + interval '24 hours') RETURNING id INTO v_id;
  RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION fn_registrar_abono(p_empleado_id bigint, p_monto numeric) RETURNS numeric
LANGUAGE plpgsql SECURITY DEFINER SET search_path = casino, pg_temp AS $$
DECLARE v_jugador_id bigint; v_deuda numeric;
BEGIN
  PERFORM fn_exigir_rol('administrador');
  IF p_monto IS NULL OR p_monto <= 0 THEN
    RAISE EXCEPTION 'El abono debe ser positivo' USING ERRCODE = 'CA309'; END IF;
  SELECT id INTO v_jugador_id FROM jugadores WHERE empleado_id = p_empleado_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'El empleado no tiene cuenta de juego' USING ERRCODE = 'CA306'; END IF;
  INSERT INTO abonos_empleado(empleado_id, monto, creado_por)
  VALUES(p_empleado_id, p_monto, fn_actor());
  PERFORM fn_evaluar_riesgo(v_jugador_id);
  SELECT deuda INTO v_deuda FROM v_deuda_empleado WHERE empleado_id = p_empleado_id;
  RETURN v_deuda;
END $$;

CREATE OR REPLACE FUNCTION fn_cerrar_investigacion(p_id bigint, p_resolucion text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = casino, pg_temp AS $$
BEGIN
  PERFORM fn_exigir_rol('administrador');
  IF p_resolucion IS NULL OR btrim(p_resolucion) = '' THEN
    RAISE EXCEPTION 'La resolucion es obligatoria' USING ERRCODE = 'CA309'; END IF;
  -- El admin tambien puede tener una ficha de jugador como empleado.
  -- No se le permite resolver su propia investigacion (conflicto de interes).
  IF EXISTS (
    SELECT 1 FROM investigaciones i
    JOIN jugadores j ON j.id = i.jugador_id
    JOIN empleados e ON e.id = j.empleado_id
    WHERE i.id = p_id AND e.usuario_id = fn_actor()
  ) THEN
    RAISE EXCEPTION 'No puedes cerrar una investigacion sobre tu propia cuenta'
      USING ERRCODE = 'CA310';
  END IF;
  UPDATE investigaciones SET cerrada_en = clock_timestamp(), resolucion = btrim(p_resolucion),
       cerrada_por = fn_actor() WHERE id = p_id AND cerrada_en IS NULL;
  IF NOT FOUND THEN RAISE EXCEPTION 'La investigacion ya esta cerrada o no existe' USING ERRCODE = 'CA307'; END IF;
END $$;

CREATE OR REPLACE FUNCTION fn_actualizar_umbral(p_monto numeric) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = casino, pg_temp AS $$
BEGIN
  PERFORM fn_exigir_rol('administrador');
  IF p_monto IS NULL OR p_monto <= 0 THEN
    RAISE EXCEPTION 'El umbral debe ser positivo' USING ERRCODE = 'CA309'; END IF;
  INSERT INTO configuracion(clave, valor) VALUES ('umbral_perdida_diaria', p_monto)
  ON CONFLICT (clave) DO UPDATE SET valor = EXCLUDED.valor;
END $$;

CREATE OR REPLACE FUNCTION fn_actualizar_jugador(p_id bigint, p_nombre text, p_documento text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = casino, pg_temp AS $$
BEGIN
  PERFORM fn_exigir_rol('administrador');
  IF p_nombre IS NULL OR btrim(p_nombre) = '' THEN
    RAISE EXCEPTION 'Nombre invalido' USING ERRCODE = 'CA309'; END IF;
  UPDATE jugadores SET nombre = btrim(p_nombre), documento = p_documento WHERE id = p_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Jugador no encontrado' USING ERRCODE = 'CA301'; END IF;
END $$;

CREATE OR REPLACE FUNCTION fn_desactivar_jugador(p_id bigint) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = casino, pg_temp AS $$
DECLARE v_usuario_id bigint;
BEGIN
  PERFORM fn_exigir_rol('administrador');
  UPDATE jugadores SET activo = false WHERE id = p_id RETURNING usuario_id INTO v_usuario_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Jugador no encontrado' USING ERRCODE = 'CA301'; END IF;
  UPDATE usuarios SET activo = false WHERE id = v_usuario_id;
END $$;

-- [CONSIGNACION_ADMIN_INICIO]
-- Consignacion administrativa (A7): creditos iniciales y posteriores.
-- Solo el administrador; no habilita retiros ni modifica reglas de apuestas.
-- La ficha debe estar habilitada (jugador y usuario activos). Una suspension
-- o investigacion no bloquea abonos: su restriccion aplica a apostar/retirar.
CREATE OR REPLACE FUNCTION fn_registrar_consignacion(p_jugador_id bigint, p_monto numeric)
RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path = casino, pg_temp AS $$
DECLARE
  v_saldo numeric(14,2);
  v_movimiento_id bigint;
BEGIN
  PERFORM fn_exigir_rol('administrador');

  -- No redondear silenciosamente dinero recibido por SQL directo.
  IF p_monto IS NULL OR p_monto <= 0
     OR p_monto > 999999999999.99 OR p_monto <> trunc(p_monto, 2) THEN
    RAISE EXCEPTION 'La consignacion debe ser positiva, tener maximo dos decimales y caber en el saldo'
      USING ERRCODE = 'CA309';
  END IF;

  -- El bloqueo protege la comprobacion de estado y el saldo en concurrencia.
  SELECT j.saldo INTO v_saldo
  FROM jugadores j JOIN usuarios u ON u.id = j.usuario_id
  WHERE j.id = p_jugador_id AND j.activo AND u.activo
  FOR UPDATE OF j;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'El jugador no existe o su cuenta esta inactiva'
      USING ERRCODE = 'CA301';
  END IF;
  IF v_saldo + p_monto > 999999999999.99 THEN
    RAISE EXCEPTION 'La consignacion excede la capacidad del saldo del jugador'
      USING ERRCODE = 'CA309';
  END IF;

  -- Punto de entrada contable unico: actualiza saldo, registra monto,
  -- saldo_resultante y creado_por = app.usuario_id en movimientos_saldo.
  PERFORM fn_mover_saldo(p_jugador_id, 'consignacion', p_monto);

  -- currval es POR SESION y se refiere a esta secuencia en particular;
  -- no depende de un ORDER BY id inseguro ante operaciones concurrentes.
  v_movimiento_id := currval(pg_get_serial_sequence('casino.movimientos_saldo', 'id'));
  RETURN v_movimiento_id;
END $$;
-- [CONSIGNACION_ADMIN_FIN]

-- Estado derivado: Inactivo > Investigacion > Suspendido > Activo.
CREATE OR REPLACE VIEW v_estado_jugador AS
SELECT j.id AS jugador_id,
  CASE WHEN NOT j.activo OR NOT u.activo THEN 'Inactivo'
       WHEN EXISTS(SELECT 1 FROM investigaciones i WHERE i.jugador_id = j.id AND i.cerrada_en IS NULL) THEN 'Investigación'
       WHEN EXISTS(SELECT 1 FROM suspensiones s WHERE s.jugador_id = j.id
           AND s.levantada_en IS NULL AND (s.fin > now() OR (s.motivo = 'deuda_empleado' AND s.fin IS NULL))) THEN 'Suspendido'
       ELSE 'Activo' END AS estado,
  (SELECT max(s.fin) FROM suspensiones s WHERE s.jugador_id = j.id
       AND s.levantada_en IS NULL AND s.fin > now()) AS suspendido_hasta
FROM jugadores j JOIN usuarios u ON u.id = j.usuario_id;

CREATE OR REPLACE VIEW v_jugadores AS
SELECT j.id, j.codigo, j.nombre, j.documento, j.fecha_nacimiento, j.saldo,
       ej.estado, ej.suspendido_hasta, (j.empleado_id IS NOT NULL) AS es_empleado, j.activo, j.usuario_id
FROM jugadores j JOIN v_estado_jugador ej ON ej.jugador_id = j.id;

CREATE OR REPLACE VIEW v_historial_apuestas AS
SELECT * FROM v_apuestas;

CREATE OR REPLACE VIEW v_historial_movimientos AS
SELECT m.id, m.jugador_id, m.tipo, m.monto, m.saldo_resultante,
       m.apuesta_id, m.creado_en AS fecha
FROM movimientos_saldo m;

CREATE OR REPLACE VIEW v_suspensiones AS
SELECT s.id, s.jugador_id, j.codigo AS jugador_codigo, j.nombre AS jugador_nombre,
       s.motivo, s.inicio, s.fin, s.levantada_en,
       (s.levantada_en IS NULL AND (s.fin > now() OR (s.motivo = 'deuda_empleado' AND s.fin IS NULL))) AS activa
FROM suspensiones s JOIN jugadores j ON j.id = s.jugador_id;

CREATE OR REPLACE VIEW v_investigaciones AS
SELECT i.id, i.jugador_id, j.codigo AS jugador_codigo, j.nombre AS jugador_nombre,
       i.abierta_en, i.cerrada_en, i.resolucion
FROM investigaciones i JOIN jugadores j ON j.id = i.jugador_id;

CREATE OR REPLACE VIEW v_deuda_empleado AS
SELECT j.empleado_id, j.id AS jugador_id,
  (coalesce((SELECT sum(CASE WHEN a.estado = 'perdida' THEN a.monto
                             WHEN a.estado = 'ganada' THEN -coalesce(a.premio, 0) ELSE 0 END)
             FROM apuestas a WHERE a.jugador_id = j.id AND a.estado IN ('ganada', 'perdida')), 0)
   - coalesce((SELECT sum(b.monto) FROM abonos_empleado b WHERE b.empleado_id = j.empleado_id), 0))::numeric(14,2) AS deuda
FROM jugadores j WHERE j.empleado_id IS NOT NULL;

CREATE OR REPLACE VIEW v_configuracion AS
SELECT clave, valor FROM configuracion;
