# Estado de pruebas de integración del casino

**Corte de evidencias:** 2 de noviembre de 2026. **Rama:** `andres/backend`. **Último commit compartido en este corte:** `10f4d2f` (incorpora las reglas definitivas de `main`, commit `71e2a1d`). **Pull request:** [#2 — borrador](https://github.com/andreMD287/Casino/pull/2) hacia `main`; todavía no está fusionado.

## Resumen de resultados reproducidos por Andrés

| Área | Evidencia y resultado local |
|---|---|
| PostgreSQL: `run_all.sh --tests` | **121 OK, 0 FALLO, 0 PENDIENTE, código de salida 0.** La base `casino` se reconstruyó y aplicó el esquema, funciones y semillas 90–93. |
| SRP: `npm run probar:auth` | **22 OK, 0 FALLO, código de salida 0** con PostgreSQL real; incluyó M2, sesiones, desafíos, roles, formularios firmados y rechazos. |
| `npm run lint` y `npm run build` | Ambos correctos tras los cambios de riesgo y la integración de ruleta. La salida de Next.js solo mostraba `/` y `/_not-found`; no certifica todavía el frontend de los cuatro roles. |
| Permisos de las funciones públicas | **20/20** nombres comprobados: existentes y con `EXECUTE` habilitado para `casino_app`. |
| Restricciones como `casino_app` | Escritura directa en `jugadores` rechazada; función interna `fn_mover_saldo` rechazada; intento de jugador de ejecutar `fn_actualizar_umbral` rechazado con `CA002`. Todas estas pruebas se hicieron con `ROLLBACK`. |
| Lectura de vistas | **14/14** vistas consultadas con `casino_app` sin errores; ficha de `jugador1` localizada por `usuario_id`. |
| Estructura del contrato de datos | **20/20** vistas con las columnas esperadas según la auditoría de `information_schema.columns`; esto no comprueba todavía todas las transformaciones TypeScript. |
| Conexión real Node.js (`pg`) | **9/9** consultas completadas como `casino_app` contra la base `casino`, código 0. |
| Aislamiento de supervisión | `supervisor1`: 5 asignaciones propias, 0 ajenas; `supervisor2`: 4 propias, 0 ajenas, en la consulta de la vista correspondiente. |
| Permisos y conceptos por rol | **7** comprobaciones de administración de mesas, restricciones y pausa voluntaria; **6** de conceptos de supervisión (rol, duplicación y turno futuro). Códigos de salida 0 y `ROLLBACK`. |

**Datos iniciales de semillas:** 7 empleados, 3 mesas, 5 jugadores, 10 rondas y 62 apuestas. Las posteriores pruebas de registro SRP crearon jugadores adicionales en el entorno de prueba; ver ocho jugadores después de esas operaciones no implica que la semilla original haya creado ocho.

## Historial de incidencias y correcciones

1. **Primera batería integral:** `OK=39, FALLO=2, PENDIENTE=0`. Los tests de autenticación y apuestas de André intentaban insertar documentos alfanuméricos (`T-1001`, `DOC-t_jug1`) incompatibles con la validación de documentos. André corrigió los datos de prueba en `main`.
2. **Primera integración con `main` (`dbe045f`):** `OK=109, FALLO=0, PENDIENTE=0`, verificado por Andrés. Los permisos inicialmente pendientes se incorporaron a `50_permisos_auditoria.sql`.
3. **Resultados de ruleta (`214196f`):** André añadió `CA217`, la obligatoriedad de un único Pleno y la derivación de color/paridad/docena; reportó 114 comprobaciones aprobadas al integrarlo con la rama de Andrés. Las pruebas de ruleta figuran también entre las 121 ejecutadas localmente después.
4. **Ajustes de riesgo:** el equipo acordó pérdidas diarias *brutas* (apuestas perdidas sin descontar premios), bloqueo de empleados en turno `CA311`, prohibición de autocierre de investigaciones `CA310` y pausa voluntaria únicamente por el jugador. La primera ejecución nueva falló durante `92_semilla_jugadores.sql`: una apuesta histórica de supervisor quedó bloqueada al coincidir con su turno vigente. Se corrigió la semilla asignando el escenario ganador histórico a un jugador que no es empleado, **sin eliminar el trigger ni relajar la regla**.
5. **Verificación final del módulo:** `OK=121, FALLO=0, PENDIENTE=0`, código 0. Se comprobaron umbral estricto, pérdidas brutas con premios, turnos de crupieres y supervisores, investigaciones propias y resultados coherentes de ruleta. Los cambios quedaron publicados en `f0fd284`.
6. **Autenticación Node.js:** una ejecución devolvió `ECONNREFUSED` porque el script apuntó por defecto a `localhost:5432`, mientras Docker publicaba PostgreSQL en `127.0.0.1:55433`. Al establecer `PGHOST`, `PGPORT`, `PGUSER` y `PGPASSWORD` correctamente, `npm run probar:auth` obtuvo **22 OK, 0 FALLO**, código 0. No hubo que cambiar la lógica SRP.
7. **Contrato común:** André publicó en `main` las reglas definitivas A2.5 (ruleta), A2.7 (pérdida diaria bruta), A2.8 (pausa del jugador), A2.18 (empleado en turno) y A2.19 (investigación propia), además de actualizar `docs/errores.md`. Andrés integró el commit `71e2a1d` con el merge `10f4d2f` y lo publicó en su rama. `CA308` sigue reservado para retiros durante investigaciones.

## Seguridad y autorizaciones

- Se consultaron los permisos `EXECUTE` de las veinte funciones públicas de Andrés y todas devolvieron `OK` para el rol técnico `casino_app`.
- `casino_app` puede leer las vistas autorizadas, pero no modificar directamente el saldo de `jugadores` ni llamar a funciones internas como `fn_mover_saldo`.
- El actor de negocio se determina a través de `app.usuario_id`; los tests comprobaron el rechazo `CA002` de un jugador que intentó ejecutar una operación administrativa.
- Los conceptos de supervisión se rechazaron para otro supervisor (`CA119`), para el administrador (`CA002`), al duplicarlos (`CA121`) y antes del fin de turno (`CA120`); el supervisor autorizado pudo emitir el suyo dentro de la transacción de prueba.
- La existencia de permisos y las pruebas SQL no bastan para certificar que una Server Action invocada por un navegador valida correctamente cookies, sesiones y firmas. Esa prueba de extremo a extremo sigue pendiente.

## Reproducción de pruebas integrales

1. Comprobar que `andres/backend` incluye el `main` correspondiente y que Docker contiene exclusivamente los datos de prueba que se pueden reconstruir.
2. Copiar los SQL actualizados: `docker cp .\db\. casino-postgres:/tmp/casino-db/`.
3. Ejecutar `bash /tmp/casino-db/run_all.sh --tests` **dentro de `casino-postgres`**, con `CASINO_APP_PASSWORD` obtenido de `.env.local` y `PGHOST=/var/run/postgresql`, `PGPORT=5432`, `PGUSER=postgres`. **Esta operación destruye y recrea la base de pruebas `casino`.**
4. Confirmar `Resultado: OK=121  FALLO=0  PENDIENTE=0` y código de salida 0.
5. Ejecutar `npm run lint` y `npm run build`.
6. Para reproducir `npm run probar:auth` en Windows con Docker, usar `PGHOST=127.0.0.1`, `PGPORT=55433`, `PGUSER=postgres` y `PGPASSWORD` con la contraseña local de PostgreSQL. Retirar esas variables de la sesión una vez terminada la prueba; no publicarlas en Git.

**Nota:** las funciones opcionales `fn_registrar_consignacion` y `fn_registrar_retiro` todavía no existen. Los avisos al crear privilegios son informativos; no equivalen a pruebas aprobadas de consignación o retiro.

## Validaciones pendientes para el proyecto completo

- Integración del frontend de Hania: comprobar rutas, formularios y componentes visibles de los cuatro roles con `MODO_MOCK=0` y la base real.
- Pruebas de Server Actions mediante la capa real Next.js/HTTP, incluidas las sesiones, firmas y el manejo de `CA217`, `CA310`, `CA311` y de los rechazos habituales.
- Recorrido de operaciones de administrador (empleados, competencias, mesas, jornadas, turnos y asignaciones), crupier (rondas/apuestas/liquidación), supervisor (conceptos) y jugador (historial y pausa) desde el navegador.
- Revisión explícita de si el enunciado exige consignaciones y retiros funcionales; no afirmar que están implementados mientras sus acciones no tengan respaldo SQL.
- Pruebas de integración y evidencias visuales posteriores al merge definitivo del frontend, antes de cerrar el PR #2.

Los resultados anteriores describen las ejecuciones registradas en este entorno y **no constituyen una garantía de ausencia de fallos no cubiertos**.
