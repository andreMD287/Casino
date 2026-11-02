# Estado de pruebas de integración del casino

**Fecha de corte:** 2 de noviembre de 2026. **Rama:** `andres/backend`. **Commit inicial publicado:** `43e06c6`. **Pull request:** [#2 — Draft](https://github.com/andreMD287/Casino/pull/2) hacia `main`. El PR es un borrador y aún no está fusionado.

## Resultados observados

| Comprobación | Evidencia y resultado |
|---|---|
| `npm run lint` | Terminó correctamente con los tres archivos de acciones reales. |
| `npm run build` | Next.js 16.4.3 compiló y verificó TypeScript sin errores; la interfaz de Hania no estaba integrada en esa rama. |
| `db/run_all.sh` | Ejecutó `00`, `01`, `02`, `05`, `10`, `20`, `30`, `40`, `50` y semillas `90` a `93`; terminó `Base casino lista`. |
| Conteo de semillas | 7 empleados, 3 mesas, 5 jugadores, 10 rondas y 62 apuestas. |
| Tests independientes de `20_personal_mesas.sql` | Código de salida 0 y avisos `[OK]` para restricciones de turnos, cargos, competencias y conceptos. |
| Tests independientes de `40_riesgo_historial.sql` | Código de salida 0 y avisos `[OK]` para edad, suspensiones, deuda, abonos, investigaciones e historial. |
| `run_all.sh --tests` integral (primera ejecución, antes de correcciones) | `OK=39`, `FALLO=2`, `PENDIENTE=0`, código de salida 1. |
| `run_all.sh --tests` después del merge local `dbe045f` | **109 OK, 0 FALLO, 0 PENDIENTE; código de salida 0**, verificado en `casino-postgres` por Andrés. André reportó aparte **22/22** en la prueba de login, no repetida localmente en esta evidencia. |
| Consulta `has_function_privilege` tras el merge | Las ocho funciones públicas consultadas del módulo Andrés devolvieron `t`. La comprobación exhaustiva de las 20 funciones queda como verificación adicional. |
| Git | Commit `43e06c6` publicado y merge `dbe045f` realizado localmente en `andres/backend`. En la captura de consola la rama estaba `ahead 2`, por lo que **el merge aún no se había publicado en `origin/andres/backend`**. PR #2 sigue Draft. |

## Fallos concretos de la batería integral

1. `db/tests/10_auth.sql` — intento de crear un jugador con documento `T-1001`, que incumple la validación numérica de 6 a 12 dígitos.
2. `db/tests/30_rondas_apuestas.sql` — intento de insertar un jugador con documento `DOC-t_jug1` y otros ejemplos del mismo estilo; el trigger `tg_validar_jugador` rechaza el formato.

**Estado resuelto:** André ajustó ambos archivos en `main`, y Andrés repitió las pruebas desde la rama que incorporó `origin/main`. El resultado integral fue 109 OK, 0 FALLO y 0 PENDIENTE.

## Permisos pendientes

La primera versión de `db/50_permisos_auditoria.sql` no concedía a `casino_app` las funciones públicas de los módulos de Andrés. André agregó las concesiones `EXECUTE` en `main`. La consulta local posterior confirmó `t` para ocho funciones públicas representativas. La solución mantiene el principio de menor privilegio: **no** dar acceso directo a funciones internas como `fn_mover_saldo` o `fn_evaluar_riesgo`. Para certificar todas las funciones deben comprobarse las 20 firmas y repetir los rechazos de acceso directo como `casino_app`.

**Responsable del ajuste:** André, dueño del archivo de permisos. **Verificación realizada por Andrés:** ocho permisos `EXECUTE` correctos. Las pruebas SQL integrales también comprobaron rechazo de `INSERT` directo en `apuestas`, `UPDATE` directo de `jugadores.saldo` y lectura directa de `usuarios` con `casino_app`.

## Procedimiento ejecutado para reproducir la integración

1. Desde `andres/backend` se ejecutó `git fetch origin` y `git merge --no-edit origin/main`, que creó el commit local `dbe045f` sin conflictos. El merge **no** equivale a fusionar el PR hacia `main`.
2. Copiar el directorio actualizado con `docker cp .\db\. casino-postgres:/tmp/casino-db/`.
3. Ejecutar `run_all.sh --tests` dentro de `casino-postgres`, con `PGHOST=/var/run/postgresql`, `PGPORT=5432`, `PGUSER=postgres` y `CASINO_APP_PASSWORD` recuperada de `.env.local`. Esto **recrea la base `casino`** del contenedor aislado.
4. Se confirmó `Resultado: OK=109  FALLO=0  PENDIENTE=0`, código de salida 0, y pasaron `npm run lint` y `npm run build`.
5. Se verificó `has_function_privilege('casino_app', oid, 'EXECUTE')`: ocho funciones devolvieron `t`; las pruebas integrales rechazaron acceso directo a tablas. Queda opcional comprobar exhaustivamente las 20 funciones.
6. Pendiente de este corte documental: publicar el merge y la documentación en `andres/backend` para actualizar el PR #2. La demostración con los cuatro roles sigue siendo una validación separada con Hania.

## Pruebas de aceptación aún necesarias

- Completado: `run_all.sh --tests` con **109 OK, 0 FALLO, 0 PENDIENTE** (2 de noviembre de 2026).
- Login real SRP y cierre de sesión para los cuatro roles; rechazos de acceso cruzado tanto en servidor como en BD.
- Flujo de administrador: crear/editar/desactivar empleados y mesas, turnos y asignaciones, con rechazos de competencia y rotación.
- Flujo de crupier: abrir ronda, registrar apuesta, rechazar saldo o monto indebidos, cerrar ronda y comprobar liquidación y saldos.
- Flujo de jugador: historial y pausa voluntaria con bloqueo de apuestas.
- Flujo de administrador de riesgo: umbral, suspensiones, abono y cierre de investigación.
- Flujo de supervisor: concepto al terminar el turno, sin usar el resultado nominal como sustituto del juicio subjetivo.
- Prueba con `casino_app` y evidencias visuales con el frontend integrado por Hania.

## Decisiones por conciliar con la especificación

- La pérdida diaria está calculada en código como pérdidas **netas de premios**, según el contrato A2; la especificación del grupo define la suma de apuestas perdidas.
- La especificación del grupo indica que un empleado no debe apostar durante un turno activo y que un administrador no puede cerrar su propia investigación. Falta confirmar la implementación y generar pruebas de ambos casos.
- Confirmar el mecanismo acordado de pausa voluntaria y el criterio de validación del resultado ganador de cada juego.

Estas cuestiones requieren acuerdo de los integrantes y no deben resolverse cambiando de forma unilateral `docs/CONTRATO.md`, `db/02_esquema.sql` o archivos asignados a otra persona.
