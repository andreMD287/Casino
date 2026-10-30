# Prueba de concurrencia: dos apuestas simultáneas que superan el saldo

**Objetivo.** Mostrar que dos crupieres (o dos pestañas) que registran apuestas al mismo tiempo para el
mismo jugador no pueden dejarlo con saldo negativo. `fn_registrar_apuesta` bloquea la fila del jugador
(`SELECT ... FOR UPDATE`) **antes** de leer el saldo: la segunda transacción espera a que la primera
termine, lee el saldo ya descontado y falla con `CA010`.

## Preparación (superusuario)

Requiere la base con semillas y un turno vigente (`db/demo/turno_actual.sql` si el turno ya pasó).

```sql
-- psql -d casino   (superusuario)
SET search_path = casino;

-- Ronda abierta de la mesa R-01 y su crupier asignado
SELECT r.id AS ronda, e.usuario_id AS crupier_usuario
FROM rondas r JOIN asignaciones a ON a.id = r.asignacion_id JOIN empleados e ON e.id = a.crupier_id
JOIN mesas m ON m.id = r.mesa_id
WHERE m.codigo = 'R-01' AND r.estado = 'abierta';
-- Si no hay ronda abierta: SELECT set_config('app.usuario_id', '<crupier_usuario>', false); SELECT fn_abrir_ronda(<mesa_id>);

-- Dejar al jugador 3 con saldo exacto de 1000 (siempre con fn_mover_saldo)
SELECT fn_mover_saldo(3, 'retiro', saldo - 1000) FROM jugadores WHERE id = 3 AND saldo > 1000;
SELECT id, codigo, saldo FROM jugadores WHERE id = 3;          -- 1000.00

-- Opción "Rojo" de la ruleta
SELECT o.id FROM opciones_apuesta o JOIN juegos j ON j.id = o.juego_id WHERE j.nombre = 'Ruleta' AND o.nombre = 'Rojo';
```

Cada apuesta será de **600**: una sola cabe (1000 ≥ 600), las dos juntas no (1200 > 1000).

## Paso a paso con dos sesiones de psql

Abrir dos terminales con `psql -d casino`. En ambas:

```sql
SET search_path = casino;
SELECT set_config('app.usuario_id', '<crupier_usuario>', false);
```

| # | Sesión A | Sesión B |
|---|---|---|
| 1 | `BEGIN;` | |
| 2 | `SELECT fn_registrar_apuesta(<ronda>, 3, <rojo>, 600);` → devuelve el id. A tiene el bloqueo de la fila del jugador. | |
| 3 | | `BEGIN;` |
| 4 | | `SELECT fn_registrar_apuesta(<ronda>, 3, <rojo>, 600);` → **se queda esperando** |
| 5 | (en una tercera terminal, ver la consulta de `pg_locks` de abajo y tomar la captura) | |
| 6 | `COMMIT;` | |
| 7 | | Se libera y falla: `ERROR: Saldo insuficiente: el jugador tiene 400.00 y se necesitan 600` (SQLSTATE `CA010`) |
| 8 | | `ROLLBACK;` |

Resultado final: `SELECT saldo FROM jugadores WHERE id = 3;` → **400.00** (una sola apuesta aplicada, nunca negativo).

## Consulta para la captura (tercera terminal, durante el paso 5)

```sql
SELECT a.pid,
       a.state,
       a.wait_event_type,
       a.wait_event,
       pg_blocking_pids(a.pid) AS bloqueado_por,
       l.locktype, l.mode, l.granted,
       left(a.query, 60) AS consulta
FROM pg_stat_activity a
JOIN pg_locks l ON l.pid = a.pid
WHERE a.datname = 'casino'
  AND (l.locktype IN ('transactionid', 'tuple') OR l.relation = 'casino.jugadores'::regclass)
ORDER BY a.pid, l.granted DESC;
```

Qué se ve:

- La sesión B aparece con `wait_event_type = Lock`, `wait_event = transactionid` y `bloqueado_por = {pid de A}`.
- B tiene un `ShareLock` sobre el `transactionid` de A con `granted = false`: está esperando que A termine.
- A tiene `RowExclusiveLock` sobre `casino.jugadores` (la fila bloqueada con `FOR UPDATE`).

## Por qué funciona

1. Orden de bloqueos fijo en todas las funciones: primero la ronda (`FOR SHARE` al apostar,
   `FOR UPDATE` al cerrar o anular) y después los jugadores, en orden de id. Así no hay interbloqueos
   entre una apuesta y un cierre de ronda.
2. `fn_mover_saldo` vuelve a bloquear la fila del jugador y calcula el saldo nuevo con el valor ya
   comprometido por la otra transacción (en `READ COMMITTED`, después de esperar un bloqueo se lee la
   versión más reciente de la fila).
3. Además, `jugadores.saldo` tiene `CHECK (saldo >= 0)` y `movimientos_saldo.saldo_resultante` también:
   aunque una función tuviera un error, la BD rechazaría un saldo negativo.

Esta prueba se ejecutó el 29 de octubre de 2026 con PostgreSQL 17 y dio el resultado esperado
(B esperó y luego falló con CA010; saldo final 400.00).
