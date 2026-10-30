# Arquitectura

*Sección a cargo de André.*

## Idea central

**La base de datos es dueña de las reglas de negocio.** TypeScript solo valida el *formato* de las entradas,
fija quién es el actor y llama funciones `fn_*` de PostgreSQL. Cada regla (montos, saldos, turnos,
correlativos, estados) se cumple aunque alguien se conecte con el rol de la aplicación y ejecute SQL a mano.

## Capas

```
 Navegador
 ├─ Client Components (formularios, login SRP: la clave nunca sale de aquí)
 │        │  POST (Server Action)                 ▲ HTML / RSC
 ▼        ▼                                       │
 Next.js (Node)                                   │
 ├─ proxy.ts ─────────── ¿existe la cookie casino_sesion? si no → /login   (no toca la BD)
 ├─ Server Components (layouts y páginas) ── exigirSesion(rol)            (capa 1)
 ├─ Server Actions  src/server/acciones/*.ts
 │     └─ crearAccion: sesión + rol → zod → firma del formulario → transacción   (capa 2)
 ├─ src/server/db.ts: Pool de pg (10 conexiones), withTx(usuarioId, fn)
 │     BEGIN; SELECT set_config('app.usuario_id', $1, true); … ; COMMIT/ROLLBACK
 ▼        consultas parametrizadas ($1, $2) como rol casino_app
 PostgreSQL — schema casino
 ├─ Vistas v_*          (lectura; casino_app solo tiene SELECT aquí)
 ├─ Funciones fn_*      SECURITY DEFINER, search_path fijo
 │     └─ fn_exigir_rol(...) con fn_actor()                              (capa 3)
 ├─ Triggers            (correlativo de rondas, validación de apuestas, auditoría)
 └─ Tablas + CHECK / UNIQUE / FK   (dueño: casino_owner; casino_app sin privilegios)
```

### Roles de base de datos

| Rol | Login | Privilegios |
|---|---|---|
| `casino_owner` | no | Dueño de todas las tablas, vistas y funciones. Las funciones `SECURITY DEFINER` corren con sus permisos. |
| `casino_app` | sí (Next.js) | `USAGE` del schema, `EXECUTE` solo de una lista explícita de funciones públicas, `SELECT` de las vistas `v_*`. **Ningún** privilegio sobre tablas ni secuencias. |
| `casino_lectura` | no | `SELECT` de las vistas de reportes. |

Consecuencia: si alguien roba la clave de `casino_app` (o encuentra una inyección SQL), no puede hacer
`UPDATE jugadores SET saldo = …` ni leer los verificadores de `usuarios`; solo puede llamar las mismas
funciones que la aplicación, que validan rol y reglas. Las pruebas `db/tests/10_auth.sql` lo comprueban.

## Las tres capas de autorización

| Capa | Dónde | Qué hace | Si falla |
|---|---|---|---|
| 1 | `exigirSesion(...roles)` en los layouts | Sin sesión → `/login`; rol distinto → `/prohibido`. Evita mostrar páginas ajenas. | redirección |
| 2 | `crearAccion({ roles, seguro })` en cada acción | Revalida sesión (cookie → SHA-256 → `fn_obtener_sesion`) y rol, porque una Server Action se puede invocar directamente sin pasar por la página. | `CA009` / `CA002` |
| 3 | `fn_exigir_rol(...)` dentro de cada función SQL | El actor (`app.usuario_id`) debe estar activo y tener el rol. Además cada función verifica permisos finos (p. ej. que el crupier sea *el asignado* a esa mesa en ese turno). | `CA002`, `CA207` |

El `proxy.ts` no es una capa de autorización: solo mejora la experiencia (redirige pronto) y no consulta la base.

## `crearAccion`: el envoltorio de todas las acciones

```ts
export const abrirRonda = crearAccion(
  { roles: ['crupier'], seguro: true, args: z.tuple([zId, zSeguro]), mock: mock.abrirRonda },
  async ({ q }, mesaId) => {
    const [{ id }] = await q('SELECT casino.fn_abrir_ronda($1) AS id', [mesaId]);
    return leerRonda(q, id);
  },
);
```

1. Obtiene la sesión y valida el rol.
2. Valida el formato de los argumentos con zod (`CA011`).
3. Si `seguro`, verifica la firma del formulario (`CA007`, ver autenticación).
4. Con `MODO_MOCK=1` delega en el mock; si no, ejecuta dentro de `withTx(usuarioId, …)`.
5. Traduce errores: SQLSTATE `CAxxx` → `{ codigo, mensaje }`; cualquier otro → se registra en consola y
   se devuelve `CA000 "Error interno"` sin detalles.

## Flujo de una apuesta de punta a punta

1. El crupier abre la página de su mesa. El layout llama `exigirSesion('crupier')`; la página llama
   `misMesasActuales()` (vista `v_mis_mesas_actuales`, filtrada por `fn_actor()` y el turno vigente).
2. Busca al jugador por código: `buscarJugadorParaApuesta('J-000001')` → vista `v_jugador_para_apuesta`,
   que indica si puede apostar usando la misma regla que la base (`fn_puede_apostar`).
3. Envía el formulario: `registrarApuesta({ rondaId, jugadorId, opcionId, monto: '100.00' }, seguro)`.
   El monto viaja como string; nunca se convierte a `float`.
4. `crearAccion` valida sesión, rol crupier, formato y firma; abre la transacción con `app.usuario_id`.
5. `fn_registrar_apuesta` (SQL):
   - `fn_exigir_rol('crupier')`;
   - bloquea la ronda (`FOR SHARE`) y verifica que el actor sea el crupier de su asignación (`CA207`)
     y que el juego tenga registro detallado (`CA209`);
   - bloquea al jugador (`FOR UPDATE`) **antes** de leer el saldo;
   - inserta en `apuestas` con el factor de la opción. El trigger `BEFORE INSERT` revalida: ronda
     abierta (`CA203`), opción activa del juego (`CA204`), monto entre mínimo y máximo (`CA205`),
     `fn_puede_apostar` (suspensión / investigación), factor correcto (`CA206`);
   - `fn_mover_saldo(jugador, 'apuesta', monto)` descuenta y registra el movimiento (`CA010` si no alcanza).
6. `COMMIT`. La acción devuelve la apuesta leída de `v_apuestas`; el frontend hace `router.refresh()`.
7. Al cierre, `fn_cerrar_ronda` bloquea la ronda (`FOR UPDATE`, evita el doble cierre), guarda el
   resultado, liquida cada apuesta pendiente (ganada: `devolucion` + `premio = monto × factor`; perdida:
   sin movimiento), cierra la ronda con `clock_timestamp()` y llama `fn_evaluar_riesgo` por cada jugador.

Si cualquier paso falla, toda la transacción se revierte: no quedan apuestas sin descuento ni saldos a medias.

## Concurrencia

Orden fijo de bloqueos (ronda → jugadores por id) para evitar interbloqueos, `FOR UPDATE` sobre el jugador
antes de leer el saldo, `FOR UPDATE` sobre la mesa al asignar el correlativo de la ronda, y un índice único
parcial que impide dos rondas abiertas en la misma mesa. Prueba manual en `docs/pruebas/concurrencia.md`.

## Auditoría

Un trigger genérico (`tg_auditar`) escribe en `auditoria` cada `INSERT`/`UPDATE`/`DELETE` de empleados,
mesas, asignaciones, conceptos, jugadores, suspensiones, investigaciones, abonos, opciones de apuesta y
rondas, con el actor (`app.usuario_id`, o NULL en semillas) y la fila en JSON (antes y después en los UPDATE).
