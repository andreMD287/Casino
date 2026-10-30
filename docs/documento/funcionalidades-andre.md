# Funcionalidades implementadas — André

*Backend: base del proyecto, autenticación Zero Knowledge, gestión de rondas y gestión de apuestas.*
Las capturas de cada funcionalidad las integra Hania.

## 1. Base del proyecto

- Proyecto Next.js 16 (App Router, TypeScript estricto, Tailwind, `src/`, alias `@/*`).
- Base de datos recreable desde cero con `db/run_all.sh` (con `--tests` corre las pruebas y falla si hay algún `FALLO`).
- Roles `casino_owner`, `casino_app`, `casino_lectura`; esquema del contrato con índices para todas las FK.
- `crearAccion`: envoltorio común de todas las Server Actions (sesión, rol, zod, formulario firmado,
  transacción con actor, traducción de errores, modo mock).
- Modo mock (`MODO_MOCK=1`) con datos coherentes en memoria para los cuatro roles.
- Permisos mínimos y auditoría (`db/50_permisos_auditoria.sql`).

## 2. Autenticación y sesiones (todos los roles)

| Funcionalidad | Acción | Rol |
|---|---|---|
| Iniciar sesión (SRP-6a + SHA-256, autenticación mutua) | `iniciarSesion` → `loginPaso1`, `loginPaso2` | público |
| Cerrar sesión | `cerrarSesion` | cualquiera |
| Registro de jugadores (la clave se deriva en el navegador) | `registrarJugador` | público |
| Formulario seguro firmado | `obtenerCamposSeguros` | cualquiera |
| Control de acceso por rol en páginas | `exigirSesion(...roles)` | — |

Restricciones: usuario `^[a-z0-9_.]{3,30}$` y único (`CA003`), documento único (`CA013`), mayoría de edad
(trigger de Andrés), desafío de uso único que vence en 2 minutos (`CA005`), bloqueo tras 5 fallos en
15 minutos (`CA006`), sesión de 8 horas.

## 3. Gestión de rondas (caso de uso, CRUD completo)

| Operación | Acción | Función SQL | Rol |
|---|---|---|---|
| Crear (abrir) ronda | `abrirRonda(mesaId)` | `fn_abrir_ronda` | crupier asignado |
| Consultar | `listarRondas(mesaId)`, `obtenerRonda(id)`, `misMesasActuales()` | vistas `v_rondas`, `v_mis_mesas_actuales` | crupier, supervisor, administrador |
| Actualizar (cerrar con resultado y liquidar) | `cerrarRonda(id, opcionesGanadoras)` | `fn_cerrar_ronda` | crupier asignado |
| Eliminar (anular) | `anularRonda(id)` | `fn_anular_ronda` | crupier asignado o administrador |
| Reporte mesa-turno | `reporteMesaTurno(jornadaId)` | `v_reporte_mesa_turno` | administrador |

Restricciones (todas en la BD):
- Número correlativo por mesa (1, 2, 3…) asignado por trigger, con la mesa bloqueada.
- Solo el crupier asignado a la mesa en el turno vigente abre la ronda (`CA207`); la mesa debe estar activa y
  la ronda iniciar dentro del turno de la asignación (`CA201`).
- Una sola ronda abierta por mesa (`CA208`, índice único parcial).
- El resultado es un conjunto de opciones del juego de la mesa (`CA202`); obligatorio en juegos con registro
  detallado (`CA212`) y prohibido en póker (`CA216`).
- El cierre es atómico: liquida todas las apuestas, deja `cierre = clock_timestamp()`, impide el doble
  cierre (`CA203`) y evalúa el riesgo de cada jugador afectado.
- Anular una ronda abierta devuelve todas sus apuestas pendientes.
- El reporte muestra, por mesa y turno, total apostado, premios, resultado nominal del casino (perdidas − premios)
  y el concepto del supervisor, para evidenciar que el concepto es independiente del resultado.

## 4. Gestión de apuestas (caso de uso, CRUD completo)

| Operación | Acción | Función SQL | Rol |
|---|---|---|---|
| Crear apuesta (juegos con registro detallado) | `registrarApuesta` | `fn_registrar_apuesta` | crupier asignado |
| Crear apuesta resuelta (póker) | `registrarApuestaResuelta` | `fn_registrar_apuesta_resuelta` | crupier asignado |
| Consultar | `listarApuestas(rondaId)`, `buscarJugadorParaApuesta(codigo)` | `v_apuestas`, `v_jugador_para_apuesta` | crupier (y supervisor/admin para listar) |
| Actualizar (liquidación) | al cerrar la ronda | `fn_cerrar_ronda` | crupier asignado |
| Eliminar (anular) | `anularApuesta(id)` | `fn_anular_apuesta` | crupier asignado |
| CRUD de opciones de apuesta | `listarOpciones`, `crearOpcion`, `actualizarOpcion`, `desactivarOpcion` | `fn_crear_opcion`, `fn_actualizar_opcion`, `fn_desactivar_opcion` | administrador (listar: todos) |

Restricciones (trigger + función, se cumplen aunque se haga `INSERT` directo):
- Ronda abierta (`CA203`), opción activa y del juego de la mesa (`CA204`).
- Monto entre el mínimo y el máximo de la mesa (`CA205`); saldo suficiente (`CA010`), con el jugador
  bloqueado para que dos apuestas simultáneas no lo dejen en negativo.
- Jugador autorizado (`fn_puede_apostar`: inactivo, suspendido o en investigación, de Andrés).
- Factor de pago copiado de la opción (`CA206`); no se puede cambiar el factor de una opción con apuestas
  pendientes (`CA213`); nombre único por juego (`CA214`).
- Movimientos de saldo: al apostar se descuenta (`apuesta`); si gana se acreditan `devolucion` (monto) y
  `premio` (monto × factor); si pierde no hay movimiento. Anular genera una `devolucion`.
- Póker: la apuesta se guarda ya ganada o perdida (`CA209`/`CA210` impiden mezclar los dos modos).

## 5. Pruebas

| Archivo | Qué cubre | Resultado |
|---|---|---|
| `db/tests/10_auth.sql` | autenticación, sesiones, roles, permisos de `casino_app` | 29 OK |
| `db/tests/30_rondas_apuestas.sql` | 40 casos de rondas y apuestas (incluye saldo final exacto y póker) | 40 OK, 1 PENDIENTE (jugador suspendido: espera `fn_puede_apostar` real) |
| `scripts/probar-auth.ts` | login SRP de punta a punta contra la base | 22 OK |
| `docs/pruebas/concurrencia.md` | dos apuestas simultáneas que superan el saldo | B espera el bloqueo y falla con `CA010` |
