# Códigos de error

Las funciones SQL lanzan `RAISE EXCEPTION '...' USING ERRCODE = 'CAxxx'`. `crearAccion` devuelve
`{ ok: false, error: { codigo, mensaje } }` con ese código y mensaje. Cualquier otro error se registra en
la consola del servidor y llega al cliente como `CA000 "Error interno"`.

| Rango | Ámbito | Responsable |
|---|---|---|
| `CA0xx` | Autenticación y común | André |
| `CA1xx` | Personal, mesas, turnos | Andrés |
| `CA2xx` | Rondas y apuestas | André |
| `CA3xx` | Jugadores, riesgo, historial | Andrés |

## CA0xx — Autenticación y común (André)

| Código | Mensaje | Dónde |
|---|---|---|
| CA000 | Error interno | `crearAccion` (error no controlado) |
| CA001 | No hay un usuario autenticado en esta operación | `fn_actor` |
| CA002 | No tienes permiso para esta operación | `fn_exigir_rol`, `crearAccion` |
| CA003 | El usuario "x" ya existe | `fn_crear_usuario` |
| CA004 | Usuario o clave incorrectos | login paso 2 (cualquier credencial inválida, incluido usuario inexistente), `fn_crear_sesion` |
| CA005 | El inicio de sesión venció o ya se usó; intenta de nuevo | `fn_consumir_desafio`, `fn_marcar_desafio` |
| CA006 | Demasiados intentos fallidos. Intenta de nuevo en 15 minutos | `fn_guardar_desafio` (5 fallos en 15 min) |
| CA007 | Formulario vencido o inválido, recarga la página | `crearAccion` (firma o fechahora del formulario seguro) |
| CA008 | No se pudo verificar el servidor | `srp-cliente.ts` (M2 no coincide) |
| CA009 | Tu sesión no es válida o venció; inicia sesión de nuevo | `crearAccion` (acción privada sin sesión) |
| CA010 | Saldo insuficiente: el jugador tiene X y se necesitan Y | `fn_mover_saldo` |
| CA011 | Datos inválidos: … | zod en `crearAccion`, validaciones de formato en SQL |
| CA012 | El jugador no existe | `fn_mover_saldo`, apuestas, `buscarJugadorParaApuesta` |
| CA013 | Ya existe un jugador con el documento X | `fn_registrar_jugador` |
| CA099 | Pendiente de implementar | acciones de Andrés en modo real hasta que las implemente |

## CA2xx — Rondas y apuestas (André)

| Código | Mensaje | Dónde |
|---|---|---|
| CA201 | La mesa no existe o no está activa / La asignación no corresponde a esta mesa / La ronda debe iniciar dentro del turno de la asignación | trigger `BEFORE INSERT` de `rondas` |
| CA202 | El resultado debe ser una opción del juego de la mesa | trigger `BEFORE INSERT` de `resultados_ronda` |
| CA203 | La ronda no está abierta | trigger de `apuestas`, `fn_cerrar_ronda` (doble cierre), `fn_anular_ronda` |
| CA204 | La opción de apuesta no está activa o no es del juego de esta mesa | trigger de `apuestas` |
| CA205 | El monto debe estar entre X y Y en esta mesa | trigger de `apuestas` |
| CA206 | El factor de pago no coincide con el de la opción | trigger de `apuestas` |
| CA207 | No eres el crupier asignado a esta mesa / ronda | `fn_abrir_ronda`, apuestas, cierre y anulación |
| CA208 | Ya hay una ronda abierta en esta mesa | `fn_abrir_ronda` (índice único parcial) |
| CA209 | Este juego no tiene registro detallado: registra la apuesta con su resultado | `fn_registrar_apuesta`, trigger |
| CA210 | Este juego tiene registro detallado: registra la apuesta antes del resultado | `fn_registrar_apuesta_resuelta`, trigger |
| CA211 | Solo se puede anular una apuesta pendiente de una ronda abierta | `fn_anular_apuesta` |
| CA212 | Debes indicar al menos una opción ganadora | `fn_cerrar_ronda` |
| CA213 | No se puede cambiar el factor: la opción tiene apuestas pendientes | `fn_actualizar_opcion` |
| CA214 | Ya existe una opción con ese nombre en el juego | `fn_crear_opcion`, `fn_actualizar_opcion` |
| CA215 | La ronda / apuesta / opción / juego no existe | varias |
| CA216 | Las rondas de juegos sin registro detallado se cierran sin resultado | `fn_cerrar_ronda` (póker) |

## CA1xx y CA3xx — Andrés

Los documenta Andrés. Los mocks de la fase 0 ya usan: CA101–CA116 (personal y mesas) y
CA301 (inactivo), CA302 (suspendido), CA303 (en investigación), CA304, CA305, CA399 (no disponible).
