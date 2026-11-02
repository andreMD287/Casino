# Evidencia: dos apuestas simultáneas que superan el saldo

Ejecución real del procedimiento de [`concurrencia.md`](concurrencia.md), el 2 de noviembre de 2026, sobre la base
completa (módulos de André y Andrés, con sus semillas) en PostgreSQL 17.

- Mesa `RUL-01` (ruleta, mínimo 1000, máximo 100000), ronda abierta 6, crupier asignado `crupier2`.
- Jugador `J-000003` con saldo inicial **10000.00**.
- Dos sesiones registran al mismo tiempo una apuesta de **6000** cada una: una sola cabe, las dos juntas no.

## Preparación (superusuario)

```
SELECT fn_mover_saldo(3, 'retiro', saldo - 10000) AS saldo_inicial FROM jugadores WHERE id = 3;
 saldo_inicial
---------------
      10000.00
```

## Sesión A

```
     hora     |                paso
--------------+-------------------------------------
 18:51:23.999 | Sesion A: BEGIN
 18:51:24.000 | Sesion A: registrar apuesta de 6000
 apuesta_id
------------
         63                      ← registrada en 33 ms; A conserva el bloqueo del jugador
 18:51:24.034 | Sesion A: después de registrar
 SELECT pg_sleep(6);             ← A mantiene la transacción abierta 6 segundos
 18:51:30.041 | Sesion A: COMMIT
COMMIT
```

## Sesión B (empieza 1,5 s después)

```
     hora     |                paso
--------------+-------------------------------------
 18:51:25.538 | Sesion B: BEGIN
 18:51:25.539 | Sesion B: registrar apuesta de 6000
ERROR:  Saldo insuficiente: el jugador tiene 4000.00 y se necesitan 6000      (SQLSTATE CA010)
CONTEXTO:  PL/pgSQL function fn_mover_saldo(bigint,text,numeric,bigint) line 21 at RAISE
Duración: 4513,828 ms           ← B esperó 4,5 s a que A terminara y solo entonces leyó el saldo
ROLLBACK
```

## Bloqueos mientras B espera (tercera sesión, 18:51:27.565)

```
  sesion  |  pid  | wait_event_type |  wait_event   | bloqueado_por |   locktype    |        mode         | granted
----------+-------+-----------------+---------------+---------------+---------------+---------------------+---------
 Sesion A | 23500 | Timeout         | PgSleep       | {}            | relation      | AccessShareLock     | t
 Sesion A | 23500 | Timeout         | PgSleep       | {}            | relation      | RowShareLock        | t
 Sesion A | 23500 | Timeout         | PgSleep       | {}            | relation      | RowExclusiveLock    | t
 Sesion A | 23500 | Timeout         | PgSleep       | {}            | transactionid | ExclusiveLock       | t
 Sesion B | 13060 | Lock            | transactionid | {23500}       | relation      | RowShareLock        | t
 Sesion B | 13060 | Lock            | transactionid | {23500}       | transactionid | ExclusiveLock       | t
 Sesion B | 13060 | Lock            | transactionid | {23500}       | tuple         | AccessExclusiveLock | t
 Sesion B | 13060 | Lock            | transactionid | {23500}       | transactionid | ShareLock           | f
```

Lectura: la sesión B está **bloqueada por la sesión A** (`bloqueado_por = {23500}`). Espera un `ShareLock` sobre la
transacción de A que aún no se le concede (`granted = f`). Es el `SELECT ... FOR UPDATE` sobre la fila del jugador
que hace `fn_registrar_apuesta` antes de leer el saldo. B ya tiene el bloqueo de tupla (`tuple`), y A tiene
`RowExclusiveLock` sobre `jugadores` porque ya actualizó el saldo.

## Resultado final

```
 id |  codigo  |  saldo
----+----------+---------
  3 | J-000003 | 4000.00

  tipo   |   monto   | saldo_resultante | apuesta_id
---------+-----------+------------------+------------
 apuesta |   6000.00 |          4000.00 |         63
 retiro  | 706000.00 |         10000.00 |
```

Se aplicó una sola apuesta. El saldo nunca fue negativo y la segunda apuesta no dejó rastro (ni apuesta ni
movimiento), porque su transacción se revirtió completa.
