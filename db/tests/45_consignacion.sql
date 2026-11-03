-- 45_consignacion.sql: pruebas aisladas de consignacion administrativa.
-- Usa actores reales, rol efectivo casino_app y ROLLBACK final.
-- No requiere jugadores registrados fuera de las semillas 90-92.
\set ON_ERROR_STOP 1
SET client_min_messages = notice;
SET search_path = casino, public;
BEGIN;

-- Actor administrador creado por la semilla base.
SELECT set_config('app.usuario_id', (SELECT id::text FROM casino.usuarios WHERE usuario='admin'), true);
SET LOCAL ROLE casino_app;

DO $$
DECLARE
  v_jugador bigint;
  v_saldo_previo numeric;
  v_mov_1 bigint;
  v_mov_2 bigint;
  v_m record;
  v_saldo_final numeric;
  v_conteo_previo bigint;
  v_conteo_final bigint;
BEGIN
  IF current_user = 'casino_app' THEN
    RAISE NOTICE '[OK] Conexion SQL usa efectivamente casino_app';
  ELSE
    RAISE NOTICE '[FALLO] La prueba no usa casino_app';
  END IF;

  SELECT id, saldo INTO v_jugador, v_saldo_previo
  FROM casino.v_jugadores WHERE codigo = 'J-000001';
  IF v_jugador IS NULL THEN
    RAISE EXCEPTION 'Falta el jugador de la semilla J-000001';
  END IF;
  SELECT count(*) INTO v_conteo_previo
  FROM casino.v_historial_movimientos WHERE jugador_id = v_jugador;

  v_mov_1 := casino.fn_registrar_consignacion(v_jugador, 125.50);
  SELECT * INTO v_m FROM casino.v_historial_movimientos WHERE id = v_mov_1;
  SELECT saldo INTO v_saldo_final FROM casino.v_jugadores WHERE id=v_jugador;

  IF v_mov_1 IS NOT NULL AND v_m.id = v_mov_1 THEN
    RAISE NOTICE '[OK] Funcion devuelve ID exacto del movimiento';
  ELSE
    RAISE NOTICE '[FALLO] El ID no corresponde al movimiento registrado';
  END IF;
  IF v_m.tipo = 'consignacion' AND v_m.monto = 125.50 AND v_m.apuesta_id IS NULL THEN
    RAISE NOTICE '[OK] Movimiento consignacion sin apuesta asociada';
  ELSE
    RAISE NOTICE '[FALLO] Tipo, monto o apuesta_id incorrectos';
  END IF;
  IF v_saldo_final = v_saldo_previo + 125.50
     AND v_m.saldo_resultante = v_saldo_final THEN
    RAISE NOTICE '[OK] Saldo y saldo_resultante se incrementan exactamente 125.50';
  ELSE
    RAISE NOTICE '[FALLO] Saldo o saldo_resultante inconsistente';
  END IF;
  IF v_m.fecha IS NOT NULL THEN
    RAISE NOTICE '[OK] El movimiento contiene fecha para el historial';
  ELSE
    RAISE NOTICE '[FALLO] El movimiento no contiene fecha';
  END IF;

  v_mov_2 := casino.fn_registrar_consignacion(v_jugador, 0.01);
  SELECT saldo INTO v_saldo_final FROM casino.v_jugadores WHERE id = v_jugador;
  SELECT count(*) INTO v_conteo_final
  FROM casino.v_historial_movimientos WHERE jugador_id = v_jugador;
  IF v_mov_2 <> v_mov_1 AND v_saldo_final = v_saldo_previo + 125.51
     AND v_conteo_final = v_conteo_previo + 2 THEN
    RAISE NOTICE '[OK] Consignaciones sucesivas crean movimientos distintos y saldo correcto';
  ELSE
    RAISE NOTICE '[FALLO] Las consignaciones sucesivas no cuadran';
  END IF;

  PERFORM set_config('test45.jugador_id', v_jugador::text, true);
  PERFORM set_config('test45.mov_1', v_mov_1::text, true);
  PERFORM set_config('test45.mov_2', v_mov_2::text, true);
  PERFORM set_config('test45.conteo', v_conteo_final::text, true);
END $$;

-- Errores de validacion y jugador inexistente, bajo casino_app.
DO $$
DECLARE
  v_j bigint := current_setting('test45.jugador_id')::bigint;
  v_caso record;
  v_codigo text;
BEGIN
  FOR v_caso IN
    SELECT * FROM (VALUES
      ('Monto cero', '0', 'CA309'),
      ('Monto negativo', '-1', 'CA309'),
      ('Monto NULL', 'NULL', 'CA309'),
      ('Monto con tres decimales', '1.001', 'CA309'),
      ('Monto fuera de rango', '1000000000000', 'CA309')
    ) AS c(descripcion, monto, esperado)
  LOOP
    BEGIN
      EXECUTE format('SELECT casino.fn_registrar_consignacion(%s,%s)', v_j, v_caso.monto);
      RAISE NOTICE '[FALLO] %: operacion aceptada', v_caso.descripcion;
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_codigo = RETURNED_SQLSTATE;
      IF v_codigo = v_caso.esperado THEN
        RAISE NOTICE '[OK] % rechazado con %', v_caso.descripcion, v_codigo;
      ELSE
        RAISE NOTICE '[FALLO] %: se esperaba %, se obtuvo %', v_caso.descripcion, v_caso.esperado, v_codigo;
      END IF;
    END;
  END LOOP;

  BEGIN
    PERFORM casino.fn_registrar_consignacion(999999999, 10.00);
    RAISE NOTICE '[FALLO] Jugador inexistente aceptado';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_codigo = RETURNED_SQLSTATE;
    IF v_codigo = 'CA301' THEN
      RAISE NOTICE '[OK] Jugador inexistente rechazado con CA301';
    ELSE
      RAISE NOTICE '[FALLO] Jugador inexistente: codigo %', v_codigo;
    END IF;
  END;

  IF (SELECT count(*) FROM casino.v_historial_movimientos WHERE jugador_id=v_j)
       = current_setting('test45.conteo')::bigint THEN
    RAISE NOTICE '[OK] Los intentos rechazados no crean movimientos';
  ELSE
    RAISE NOTICE '[FALLO] Los intentos rechazados alteraron el historial';
  END IF;
END $$;

-- Auditar en tabla base: casino_app no tiene SELECT directo sobre ella.
RESET ROLE;
DO $$
DECLARE
  v_admin bigint := (SELECT id FROM casino.usuarios WHERE usuario='admin');
  v_j bigint := current_setting('test45.jugador_id')::bigint;
  v_id_1 bigint := current_setting('test45.mov_1')::bigint;
  v_id_2 bigint := current_setting('test45.mov_2')::bigint;
BEGIN
  IF (SELECT count(*) FROM casino.movimientos_saldo
      WHERE id IN (v_id_1,v_id_2) AND jugador_id=v_j AND creado_por=v_admin)=2 THEN
    RAISE NOTICE '[OK] Ambos movimientos conservan al administrador creador';
  ELSE
    RAISE NOTICE '[FALLO] Los movimientos no guardaron correctamente creado_por';
  END IF;
END $$;

-- Una ficha inactiva no admite consignacion. Se modifica como fixture
-- dentro de esta transaccion, que termina en ROLLBACK.
UPDATE casino.jugadores SET activo = false WHERE codigo = 'J-000005';
SELECT set_config('app.usuario_id', (SELECT id::text FROM casino.usuarios WHERE usuario='admin'), true);
SET LOCAL ROLE casino_app;
DO $$
DECLARE v_j bigint; v_codigo text;
BEGIN
  SELECT id INTO v_j FROM casino.v_jugadores WHERE codigo='J-000005';
  BEGIN
    PERFORM casino.fn_registrar_consignacion(v_j, 10.00);
    RAISE NOTICE '[FALLO] Ficha inactiva acepto consignacion';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_codigo = RETURNED_SQLSTATE;
    IF v_codigo = 'CA301' THEN
      RAISE NOTICE '[OK] Ficha inactiva rechazada con CA301';
    ELSE
      RAISE NOTICE '[FALLO] Ficha inactiva: codigo %', v_codigo;
    END IF;
  END;
END $$;

-- Una ficha activa cuyo usuario esta inactivo tampoco admite consignacion.
RESET ROLE;
UPDATE casino.jugadores SET activo=true WHERE codigo='J-000005';
UPDATE casino.usuarios SET activo=false WHERE id=(SELECT usuario_id FROM casino.jugadores WHERE codigo='J-000005');
SET LOCAL ROLE casino_app;
DO $$
DECLARE v_j bigint; v_codigo text;
BEGIN
  SELECT id INTO v_j FROM casino.v_jugadores WHERE codigo='J-000005';
  BEGIN
    PERFORM casino.fn_registrar_consignacion(v_j, 10.00);
    RAISE NOTICE '[FALLO] Usuario inactivo acepto consignacion';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_codigo = RETURNED_SQLSTATE;
    IF v_codigo = 'CA301' THEN
      RAISE NOTICE '[OK] Usuario inactivo rechazado con CA301';
    ELSE
      RAISE NOTICE '[FALLO] Usuario inactivo: codigo %', v_codigo;
    END IF;
  END;
END $$;

-- Los otros tres roles tienen que ser rechazados aun con acceso a la funcion.
RESET ROLE;
SELECT set_config('app.usuario_id', (SELECT id::text FROM casino.usuarios WHERE usuario='jugador1'), true);
SET LOCAL ROLE casino_app;
DO $$
DECLARE v_codigo text;
BEGIN
  BEGIN
    PERFORM casino.fn_registrar_consignacion(current_setting('test45.jugador_id')::bigint, 10);
    RAISE NOTICE '[FALLO] Jugador pudo consignar';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_codigo = RETURNED_SQLSTATE;
    IF v_codigo='CA002' THEN RAISE NOTICE '[OK] Rol jugador bloqueado con CA002';
    ELSE RAISE NOTICE '[FALLO] Rol jugador: codigo %', v_codigo; END IF;
  END;
END $$;

RESET ROLE;
SELECT set_config('app.usuario_id', (SELECT id::text FROM casino.usuarios WHERE usuario='crupier1'), true);
SET LOCAL ROLE casino_app;
DO $$
DECLARE v_codigo text;
BEGIN
  BEGIN
    PERFORM casino.fn_registrar_consignacion(current_setting('test45.jugador_id')::bigint, 10);
    RAISE NOTICE '[FALLO] Crupier pudo consignar';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_codigo = RETURNED_SQLSTATE;
    IF v_codigo='CA002' THEN RAISE NOTICE '[OK] Rol crupier bloqueado con CA002';
    ELSE RAISE NOTICE '[FALLO] Rol crupier: codigo %', v_codigo; END IF;
  END;
END $$;

RESET ROLE;
SELECT set_config('app.usuario_id', (SELECT id::text FROM casino.usuarios WHERE usuario='supervisor1'), true);
SET LOCAL ROLE casino_app;
DO $$
DECLARE v_codigo text;
BEGIN
  BEGIN
    PERFORM casino.fn_registrar_consignacion(current_setting('test45.jugador_id')::bigint, 10);
    RAISE NOTICE '[FALLO] Supervisor pudo consignar';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_codigo = RETURNED_SQLSTATE;
    IF v_codigo='CA002' THEN RAISE NOTICE '[OK] Rol supervisor bloqueado con CA002';
    ELSE RAISE NOTICE '[FALLO] Rol supervisor: codigo %', v_codigo; END IF;
  END;
END $$;

RESET ROLE;
SELECT set_config('app.usuario_id', '', true);
SET LOCAL ROLE casino_app;
DO $$
DECLARE v_codigo text;
BEGIN
  BEGIN
    PERFORM casino.fn_registrar_consignacion(current_setting('test45.jugador_id')::bigint, 10);
    RAISE NOTICE '[FALLO] Operacion sin actor aceptada';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_codigo = RETURNED_SQLSTATE;
    IF v_codigo='CA001' THEN RAISE NOTICE '[OK] Sin actor rechazado con CA001';
    ELSE RAISE NOTICE '[FALLO] Sin actor: codigo %', v_codigo; END IF;
  END;
END $$;

-- El rol de lectura no puede ejecutar funciones administrativas.
RESET ROLE;
SET LOCAL ROLE casino_lectura;
DO $$
DECLARE v_codigo text;
BEGIN
  BEGIN
    PERFORM casino.fn_registrar_consignacion(current_setting('test45.jugador_id')::bigint, 10);
    RAISE NOTICE '[FALLO] Rol de lectura pudo ejecutar la funcion administrativa';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_codigo = RETURNED_SQLSTATE;
    IF v_codigo='42501' THEN RAISE NOTICE '[OK] Rol de lectura sin EXECUTE (42501)';
    ELSE RAISE NOTICE '[FALLO] Rol de lectura: codigo %', v_codigo; END IF;
  END;
END $$;

ROLLBACK;
