# Evidencia: pruebas de punta a punta con la aplicación real

Ejecutadas el 3 de noviembre de 2026 sobre `main` (commit `6584fac`, con el trabajo de André, Andrés y Hania),
con PostgreSQL 17, la base recreada desde cero (`./db/run_all.sh`) y la aplicación compilada en modo real
(`MODO_MOCK=0`, `npm run build && npm start -- -p 3100`).

Los scripts inician sesión con SRP-6a igual que el navegador (la clave nunca viaja), guardan la cookie de sesión
y llaman las mismas Server Actions que usan las páginas, con el formulario firmado. También piden las páginas
para comprobar que abren con el rol correcto y redirigen a `/prohibido` con un rol ajeno.

| Script | Qué cubre | Resultado |
|---|---|---|
| `scripts/probar-roles.mjs` | Login de los 4 roles, todas las páginas, rondas y apuestas en ruleta, blackjack y póker, consignación, concepto del supervisor, historial del jugador, permisos por rol, cierre de sesión, registro público | **76 OK, 0 FALLO** |
| `scripts/probar-admin.mjs` | CRUD de empleados, competencias, mesas, jornadas, turnos, asignaciones y opciones; umbral, suspensiones, investigaciones, abonos; editar, desactivar e historial de jugadores; pausa voluntaria; anular apuesta y ronda | **48 OK, 0 FALLO** |

Además, en la misma versión: `./db/run_all.sh --tests` → **176 OK, 0 FALLO, 0 PENDIENTE**;
`npm run probar:auth` → **22 OK, 0 FALLO**; `npm run lint` y `npm run build` sin errores.

Para repetirlas:

```bash
./db/run_all.sh
npm run build && npm start -- -p 3100     # en otra terminal, con MODO_MOCK=0
node scripts/probar-roles.mjs
./db/run_all.sh                            # base limpia otra vez antes del segundo script
node scripts/probar-admin.mjs
```

## Salida de `scripts/probar-roles.mjs`

```
[OK] admin: login SRP real
[OK] admin: página /admin → 200
[OK] admin: página /admin/empleados → 200
[OK] admin: página /admin/mesas → 200
[OK] admin: página /admin/turnos → 200
[OK] admin: página /admin/jugadores → 200
[OK] admin: página /admin/riesgo → 200
[OK] admin: página /admin/opciones → 200
[OK] admin: página /admin/reportes → 200
[OK] admin: listarEmpleados
[OK] admin: listarMesas
[OK] admin: listarJugadores
[OK] admin: detalle mesa /admin/mesas/2 → 200
[OK] admin: detalle jugador /admin/jugadores/1 → 200
[OK] admin: detalle empleado /admin/empleados/1 → 200
[OK] admin: reporteMesaTurno
[OK] admin: listarOpciones
[OK] admin: registrarConsignacion 125.50 (saldo inicial en fichas)
[OK] admin: formulario con firma alterada → CA007
[OK] hay asignaciones en el turno vigente
[OK] crupier3: login SRP real (rol crupier)
[OK] crupier3: página /crupier → 200
[OK] crupier3: mesa BJ-01 /crupier/mesas/2 → 200
[OK] crupier3: misMesasActuales incluye BJ-01
[OK] crupier3: abrirRonda en BJ-01
[OK] crupier3: buscarJugadorParaApuesta J-000001
[OK] crupier3: registrarApuesta Mano ganadora por 5000
[OK] crupier3: monto menor al mínimo → CA205
[OK] crupier3: listarApuestas de la ronda
[OK] crupier3: cerrarRonda BJ-01 con resumen
[OK] crupier3: la apuesta quedó ganada con premio = monto × factor
[OK] crupier3: acción de administrador (listarEmpleados) → CA002
[OK] crupier3: /admin → /prohibido
[OK] crupier4: login SRP real (rol crupier)
[OK] crupier4: página /crupier → 200
[OK] crupier4: mesa POK-01 /crupier/mesas/3 → 200
[OK] crupier4: misMesasActuales incluye POK-01
[OK] crupier4: abrirRonda en POK-01
[OK] crupier4: buscarJugadorParaApuesta J-000001
[OK] crupier4: registrarApuestaResuelta (póker, ganada)
[OK] crupier4: cerrarRonda póker sin resultado
[OK] crupier4: acción de administrador (listarEmpleados) → CA002
[OK] crupier4: /admin → /prohibido
[OK] crupier2: login SRP real (rol crupier)
[OK] crupier2: página /crupier → 200
[OK] crupier2: mesa RUL-01 /crupier/mesas/1 → 200
[OK] crupier2: misMesasActuales incluye RUL-01
[OK] crupier2: segunda ronda abierta en RUL-01 → CA208
[OK] crupier2: buscarJugadorParaApuesta J-000001
[OK] crupier2: registrarApuesta Rojo por 1000
[OK] crupier2: monto menor al mínimo → CA205
[OK] crupier2: listarApuestas de la ronda
[OK] crupier2: cerrar ruleta con 17 + Rojo → CA217
[OK] crupier2: cerrarRonda RUL-01 con resumen
[OK] crupier2: la apuesta quedó ganada con premio = monto × factor
[OK] crupier2: acción de administrador (listarEmpleados) → CA002
[OK] crupier2: /admin → /prohibido
[OK] supervisor1: login SRP real
[OK] supervisor1: página /supervisor → 200
[OK] supervisor1: misTurnosSupervisor
[OK] supervisor1: mesa supervisada /supervisor/mesas/2 → 200
[OK] supervisor1: emitirConcepto en turno terminado
[OK] supervisor1: listarRondas
[OK] supervisor1: abrirRonda → CA002
[OK] jugador1: login SRP real
[OK] jugador1: página /jugador → 200
[OK] jugador1: miHistorial con apuestas y movimientos
[OK] jugador1: abrirRonda (rol no permitido) → CA002
[OK] jugador1: /admin → /prohibido
[OK] jugador1: /crupier → /prohibido
[OK] jugador1: después de cerrar sesión, /jugador → /login
[OK] login con clave incorrecta → CA004
[OK] nuevo: página pública /registro → 200
[OK] registro público de jugador (canal anónimo + firma)
[OK] registro de un menor de edad → rechazado
[OK] el jugador recién registrado inicia sesión
Resultado: OK=76  FALLO=0
```

## Salida de `scripts/probar-admin.mjs`

```
[OK] admin: login
[OK] crearEmpleado (con credenciales SRP derivadas en el cliente)
[OK] el empleado nuevo inicia sesión como crupier
[OK] actualizarEmpleado
[OK] asignarCompetencia
[OK] la competencia aparece en el empleado
[OK] quitarCompetencia
[OK] desactivarEmpleado
[OK] el empleado desactivado ya no puede iniciar sesión → CA004
[OK] crearMesa
[OK] actualizarMesa (mesa sin historial: puede cambiar de juego)
[OK] crearMesa con mínimo > máximo → rechazada
[OK] cambiar el juego de una mesa con rondas → CA124
[OK] desactivar una mesa con asignación vigente → CA125
[OK] crearJornada 2026-12-26
[OK] crearTurno de 90 minutos
[OK] turno de más de 2 horas → rechazado
[OK] turno que se solapa → rechazado
[OK] crearAsignacion (crupier y supervisor con competencia)
[OK] asignar crupier sin competencia en el juego → rechazado
[OK] listarAsignaciones de la jornada
[OK] eliminarAsignacion (sin rondas ni conceptos)
[OK] eliminarTurno (sin rondas ni conceptos)
[OK] eliminar una asignación con rondas → CA126
[OK] desactivarMesa (mesa nueva sin asignaciones vigentes)
[OK] crearOpcion
[OK] actualizarOpcion (sin apuestas pendientes: cambia el factor)
[OK] opción duplicada → CA214
[OK] desactivarOpcion
[OK] obtenerUmbral
[OK] actualizarUmbral
[OK] listarSuspensiones
[OK] listarInvestigaciones
      (no hay investigaciones abiertas; se omite cerrarInvestigacion)
[OK] registrarAbono a empleado que juega
[OK] registrarRetiro sigue fuera de alcance → CA399
[OK] registro de jugador para la prueba
[OK] consignación inicial al jugador nuevo
[OK] actualizarJugador
[OK] obtenerHistorial (admin)
[OK] el jugador solicita pausa voluntaria de 24 h
[OK] segunda pausa estando en pausa → rechazada
[OK] el crupier ve al jugador en pausa como no autorizado
[OK] apuesta de un jugador en pausa → CA302
[OK] registrar apuesta para anularla
[OK] anularApuesta devuelve el monto
[OK] anularRonda devuelve todas las apuestas pendientes
[OK] desactivarJugador
[OK] el jugador desactivado ya no inicia sesión → CA004
Resultado: OK=48  FALLO=0
```
