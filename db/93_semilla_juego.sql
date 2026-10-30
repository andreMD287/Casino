-- 93_semilla_juego.sql (André) — rondas y apuestas generadas con las funciones REALES.
-- Requiere 91 (mesas, turno actual y asignaciones) y 92 (jugadores con saldo) de Andrés.
-- Cada operación se hace con el actor del crupier asignado en el turno actual
-- (set_config('app.usuario_id', ..., true) = SET LOCAL), así pasa por todas las reglas.
-- Montos: siempre el mínimo de la mesa, para no acercarse al umbral de pérdida diaria
-- (nadie queda suspendido sin querer).
SET ROLE casino_owner;
SET search_path = casino, public;

DO $$
DECLARE
  a record;
  v_jugadores bigint[];
  v_n int;
  v_ronda bigint;
  v_ronda_abierta_hecha boolean := false;
  i int;
  k int;
  v_resultados text[][] := ARRAY[
    ARRAY['Pleno 17', 'Negro', 'Impar'],
    ARRAY['Pleno 4',  'Negro', 'Par'],
    ARRAY['Pleno 32', 'Rojo',  'Par']
  ];
  v_apuestas_ruleta text[] := ARRAY['Rojo', 'Negro', 'Par', 'Impar', 'Pleno 17', 'Primera docena'];
  v_ganadoras bigint[];
BEGIN
  SELECT array_agg(j.id ORDER BY j.id) INTO v_jugadores
  FROM jugadores j
  WHERE j.activo AND j.saldo >= 500 AND fn_motivo_no_apuesta(j.id) IS NULL;
  v_n := coalesce(cardinality(v_jugadores), 0);

  IF v_n = 0 OR NOT EXISTS (
    SELECT 1 FROM asignaciones x JOIN turnos t ON t.id = x.turno_id WHERE now() >= t.inicio AND now() < t.fin
  ) THEN
    RAISE NOTICE '93_semilla_juego: no hay turno vigente con asignaciones o jugadores con saldo (faltan 91/92); se omite';
    RETURN;
  END IF;

  FOR a IN
    SELECT x.id AS asignacion_id, m.id AS mesa_id, m.codigo, m.monto_minimo, jg.id AS juego_id, jg.nombre AS juego,
           jg.registro_detallado, e.usuario_id AS crupier_usuario
    FROM asignaciones x
    JOIN turnos t ON t.id = x.turno_id
    JOIN mesas m ON m.id = x.mesa_id AND m.activa
    JOIN juegos jg ON jg.id = m.juego_id
    JOIN empleados e ON e.id = x.crupier_id
    WHERE now() >= t.inicio AND now() < t.fin
    ORDER BY jg.registro_detallado DESC, jg.nombre DESC, m.codigo
  LOOP
    PERFORM set_config('app.usuario_id', a.crupier_usuario::text, true);

    IF a.registro_detallado THEN
      -- Tres rondas cerradas con apuestas ganadas y perdidas
      FOR i IN 1..3 LOOP
        v_ronda := fn_abrir_ronda(a.mesa_id);
        FOR k IN 1..least(v_n, 3) LOOP
          PERFORM fn_registrar_apuesta(v_ronda, v_jugadores[1 + ((i + k) % v_n)],
            (SELECT o.id FROM opciones_apuesta o WHERE o.juego_id = a.juego_id AND o.activa AND o.nombre =
               CASE WHEN a.juego = 'Ruleta' THEN v_apuestas_ruleta[1 + ((i * 2 + k) % 6)]
                    WHEN (i + k) % 3 = 0 THEN 'Blackjack' ELSE 'Mano ganadora' END),
            a.monto_minimo);
        END LOOP;

        IF a.juego = 'Ruleta' THEN
          SELECT array_agg(o.id) INTO v_ganadoras FROM opciones_apuesta o
          WHERE o.juego_id = a.juego_id AND o.nombre = ANY (v_resultados[i:i][1:3]);
        ELSE
          SELECT array_agg(o.id) INTO v_ganadoras FROM opciones_apuesta o
          WHERE o.juego_id = a.juego_id AND o.nombre = CASE WHEN i = 2 THEN 'Blackjack' ELSE 'Mano ganadora' END;
        END IF;
        PERFORM * FROM fn_cerrar_ronda(v_ronda, v_ganadoras);
      END LOOP;

      -- Una ronda abierta con apuestas pendientes (en la primera mesa con registro detallado)
      IF NOT v_ronda_abierta_hecha THEN
        v_ronda := fn_abrir_ronda(a.mesa_id);
        FOR k IN 1..least(v_n, 2) LOOP
          PERFORM fn_registrar_apuesta(v_ronda, v_jugadores[k],
            (SELECT o.id FROM opciones_apuesta o WHERE o.juego_id = a.juego_id AND o.activa ORDER BY o.id DESC LIMIT 1 OFFSET k),
            a.monto_minimo);
        END LOOP;
        v_ronda_abierta_hecha := true;
      END IF;
    ELSE
      -- Póker: una ronda con apuestas ya resueltas, luego se cierra sin resultado
      v_ronda := fn_abrir_ronda(a.mesa_id);
      FOR k IN 1..least(v_n, 3) LOOP
        PERFORM fn_registrar_apuesta_resuelta(v_ronda, v_jugadores[k],
          (SELECT o.id FROM opciones_apuesta o WHERE o.juego_id = a.juego_id AND o.activa ORDER BY o.id LIMIT 1),
          a.monto_minimo, k % 2 = 1);
      END LOOP;
      PERFORM * FROM fn_cerrar_ronda(v_ronda, NULL);
    END IF;
  END LOOP;

  PERFORM set_config('app.usuario_id', '', true);
  RAISE NOTICE '93_semilla_juego: % rondas y % apuestas creadas',
    (SELECT count(*) FROM rondas), (SELECT count(*) FROM apuestas);
END
$$;
