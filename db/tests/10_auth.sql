-- tests/10_auth.sql (André) — autenticación, sesiones, roles y permisos de casino_app.
-- Todo en una transacción con ROLLBACK. Las pruebas de permisos usan SET ROLE casino_app.
\set ON_ERROR_STOP 1
SET client_min_messages = notice;
SET search_path = casino, public;
BEGIN;

CREATE FUNCTION pg_temp.verifica(p_desc text, p_cond boolean, p_detalle text DEFAULT '') RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  IF coalesce(p_cond, false) THEN RAISE NOTICE '[OK] %', p_desc;
  ELSE RAISE NOTICE '[FALLO] % %', p_desc, p_detalle; END IF;
END $$;

CREATE FUNCTION pg_temp.espera_error(p_desc text, p_codigo text, p_sql text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE p_sql;
  RAISE NOTICE '[FALLO] % (se esperaba %, no hubo error)', p_desc, p_codigo;
EXCEPTION WHEN OTHERS THEN
  IF SQLSTATE = p_codigo THEN RAISE NOTICE '[OK] %', p_desc;
  ELSE RAISE NOTICE '[FALLO] % (se esperaba %, llegó %: %)', p_desc, p_codigo, SQLSTATE, SQLERRM; END IF;
END $$;

GRANT EXECUTE ON FUNCTION pg_temp.verifica(text, boolean, text), pg_temp.espera_error(text, text, text) TO casino_app;

-- ===========================================================================
-- Registro y datos de login (como casino_app, igual que la aplicación)
-- ===========================================================================
SET ROLE casino_app;

DO $$
DECLARE
  r record;
BEGIN
  SELECT * INTO r FROM casino.fn_registrar_jugador('T-1001', 'Tester Auth', DATE '1995-05-05', 'T_Auth', 'abcd1234abcd1234', repeat('ab', 128));
  PERFORM pg_temp.verifica('registro: crea el jugador con código J-xxxxxx', r.codigo ~ '^J-\d{6}$', coalesce(r.codigo, 'NULL'));
  PERFORM pg_temp.verifica('registro: el usuario se normaliza a minúsculas y queda con salt y verificador',
    EXISTS (SELECT 1 FROM casino.fn_srp_datos_login('t_auth') d WHERE d.salt = 'abcd1234abcd1234'));
END $$;

SELECT pg_temp.espera_error('registro: usuario repetido → CA003', 'CA003',
  $q$SELECT * FROM casino.fn_registrar_jugador('T-1002', 'Otro', DATE '1990-01-01', 't_auth', 'aa', 'bb')$q$);
SELECT pg_temp.espera_error('registro: documento repetido → CA013', 'CA013',
  $q$SELECT * FROM casino.fn_registrar_jugador('T-1001', 'Otro', DATE '1990-01-01', 't_auth2', 'aa', 'bb')$q$);
SELECT pg_temp.espera_error('registro: usuario con formato inválido → CA011', 'CA011',
  $q$SELECT * FROM casino.fn_registrar_jugador('T-1003', 'Otro', DATE '1990-01-01', 'a b', 'aa', 'bb')$q$);

SELECT pg_temp.verifica('datos de login: usuario inexistente no devuelve filas',
  NOT EXISTS (SELECT 1 FROM casino.fn_srp_datos_login('no_existe')));

-- ===========================================================================
-- Desafíos: uso único, vencimiento, señuelo y bloqueo por fuerza bruta
-- ===========================================================================
DO $$
DECLARE
  v_uid bigint := (SELECT id FROM casino.fn_srp_datos_login('t_auth'));
  v_id uuid;
  r record;
BEGIN
  v_id := casino.fn_guardar_desafio(v_uid, 'aa', 'bb', 'cc');
  SELECT * INTO r FROM casino.fn_consumir_desafio(v_id);
  PERFORM pg_temp.verifica('desafío: consumirlo devuelve los datos del usuario', r.usuario = 't_auth' AND r.b_secreto = 'cc' AND r.rol = 'jugador');
  PERFORM pg_temp.espera_error('desafío: reutilizarlo → CA005', 'CA005', format('SELECT * FROM casino.fn_consumir_desafio(%L)', v_id));
  PERFORM casino.fn_marcar_desafio(v_id, false);

  v_id := casino.fn_guardar_desafio(NULL, 'aa', 'bb', 'cc');
  SELECT * INTO r FROM casino.fn_consumir_desafio(v_id);
  PERFORM pg_temp.verifica('desafío señuelo: se consume igual, sin usuario', r.usuario_id IS NULL AND r.b_secreto = 'cc');

  PERFORM pg_temp.espera_error('desafío inexistente → CA005', 'CA005',
    format('SELECT * FROM casino.fn_consumir_desafio(%L)', gen_random_uuid()));
END $$;

RESET ROLE;
DO $$
DECLARE
  v_uid bigint := (SELECT id FROM casino.usuarios WHERE usuario = 't_auth');
  v_id uuid;
BEGIN
  INSERT INTO casino.desafios_login (usuario_id, a_publico, b_publico, b_secreto, creado_en, expira_en)
  VALUES (v_uid, 'aa', 'bb', 'cc', now() - interval '5 minutes', now() - interval '3 minutes')
  RETURNING id INTO v_id;
  PERFORM pg_temp.espera_error('desafío vencido → CA005', 'CA005', format('SELECT * FROM casino.fn_consumir_desafio(%L)', v_id));

  -- Ya hay 1 fallido; se agregan 4 más (5 en 15 minutos).
  INSERT INTO casino.desafios_login (usuario_id, a_publico, b_publico, b_secreto, expira_en, usado_en, exitoso)
  SELECT v_uid, 'aa', 'bb', 'cc', now() + interval '2 minutes', now(), false FROM generate_series(1, 4);
  PERFORM pg_temp.espera_error('5 intentos fallidos en 15 minutos bloquean nuevos desafíos → CA006', 'CA006',
    format('SELECT casino.fn_guardar_desafio(%s, %L, %L, %L)', v_uid, 'aa', 'bb', 'cc'));

  -- Fallidos de hace más de 15 minutos ya no cuentan.
  UPDATE casino.desafios_login SET creado_en = now() - interval '16 minutes' WHERE usuario_id = v_uid;
  PERFORM pg_temp.verifica('pasados 15 minutos se puede volver a intentar',
    casino.fn_guardar_desafio(v_uid, 'aa', 'bb', 'cc') IS NOT NULL);
END $$;

-- ===========================================================================
-- Sesiones
-- ===========================================================================
SET ROLE casino_app;
SELECT pg_temp.espera_error('crear sesión sin un desafío exitoso reciente → CA004', 'CA004',
  format('SELECT casino.fn_crear_sesion(%s, %L, %L, now() + interval ''1 hour'')',
         (SELECT id FROM casino.fn_srp_datos_login('t_auth')), repeat('1', 64), repeat('c', 64)));

DO $$
DECLARE
  v_uid bigint := (SELECT id FROM casino.fn_srp_datos_login('t_auth'));
  v_id uuid := casino.fn_guardar_desafio(v_uid, 'aa', 'bb', 'cc');
BEGIN
  PERFORM casino.fn_consumir_desafio(v_id);
  PERFORM casino.fn_marcar_desafio(v_id, true);
  PERFORM casino.fn_crear_sesion(v_uid, repeat('a', 64), repeat('c', 64), now() + interval '8 hours');
  PERFORM pg_temp.verifica('sesión vigente: se obtiene con su rol y nombre',
    EXISTS (SELECT 1 FROM casino.fn_obtener_sesion(repeat('a', 64)) s WHERE s.rol = 'jugador' AND s.nombre = 'Tester Auth'));
  PERFORM pg_temp.espera_error('una sesión no puede durar más de 8 horas → CA011', 'CA011',
    format('SELECT casino.fn_crear_sesion(%s, %L, %L, now() + interval ''9 hours'')', v_uid, repeat('b', 64), repeat('c', 64)));
  PERFORM casino.fn_cerrar_sesion(repeat('a', 64));
  PERFORM pg_temp.verifica('sesión cerrada: ya no se obtiene', NOT EXISTS (SELECT 1 FROM casino.fn_obtener_sesion(repeat('a', 64))));
END $$;

RESET ROLE;
DO $$
DECLARE
  v_uid bigint := (SELECT id FROM casino.usuarios WHERE usuario = 't_auth');
BEGIN
  INSERT INTO casino.sesiones (usuario_id, token_hash, canal, creada_en, expira_en)
  VALUES (v_uid, repeat('d', 64), repeat('c', 64), now() - interval '9 hours', now() - interval '1 hour'),
         (v_uid, repeat('e', 64), repeat('c', 64), now(), now() + interval '1 hour');
  PERFORM pg_temp.verifica('sesión vencida: no se obtiene', NOT EXISTS (SELECT 1 FROM casino.fn_obtener_sesion(repeat('d', 64))));
  UPDATE casino.usuarios SET activo = false WHERE id = v_uid;
  PERFORM pg_temp.verifica('usuario desactivado: su sesión deja de valer', NOT EXISTS (SELECT 1 FROM casino.fn_obtener_sesion(repeat('e', 64))));
  PERFORM pg_temp.verifica('usuario desactivado: no recibe datos de login', NOT EXISTS (SELECT 1 FROM casino.fn_srp_datos_login('t_auth')));
  UPDATE casino.usuarios SET activo = true WHERE id = v_uid;
END $$;

-- ===========================================================================
-- Actor y roles (capa 3 de autorización)
-- ===========================================================================
SELECT set_config('app.usuario_id', '', true);
SELECT pg_temp.espera_error('sin actor → CA001', 'CA001', $q$SELECT casino.fn_exigir_rol('administrador')$q$);
SELECT set_config('app.usuario_id', (SELECT id::text FROM casino.usuarios WHERE usuario = 't_auth'), true);
SELECT pg_temp.espera_error('rol no permitido (jugador pide administrador) → CA002', 'CA002', $q$SELECT casino.fn_exigir_rol('administrador')$q$);
SELECT pg_temp.espera_error('función de administrador llamada por un jugador → CA002', 'CA002',
  $q$SELECT casino.fn_crear_opcion(1, 'Hack', 100)$q$);

-- ===========================================================================
-- Permisos: casino_app no puede tocar tablas ni funciones internas
-- ===========================================================================
SET ROLE casino_app;
SELECT pg_temp.espera_error('casino_app: INSERT directo en apuestas → sin permiso', '42501',
  $q$INSERT INTO casino.apuestas (ronda_id, jugador_id, opcion_id, monto, factor_pago, registrada_por) VALUES (1, 1, 1, 10, 1, 1)$q$);
SELECT pg_temp.espera_error('casino_app: UPDATE directo de jugadores.saldo → sin permiso', '42501',
  $q$UPDATE casino.jugadores SET saldo = 1000000$q$);
SELECT pg_temp.espera_error('casino_app: SELECT directo de usuarios (verificadores) → sin permiso', '42501',
  $q$SELECT * FROM casino.usuarios$q$);
SELECT pg_temp.espera_error('casino_app: llamar fn_mover_saldo (interna) → sin permiso', '42501',
  $q$SELECT casino.fn_mover_saldo(1, 'consignacion', 1000)$q$);
SELECT pg_temp.espera_error('casino_app: llamar fn_crear_usuario (interna) → sin permiso', '42501',
  $q$SELECT casino.fn_crear_usuario('x_hack', 'aa', 'bb', 'administrador')$q$);
SELECT pg_temp.verifica('casino_app: sí puede leer las vistas', (SELECT count(*) FROM casino.v_opciones) > 0);
RESET ROLE;

ROLLBACK;
