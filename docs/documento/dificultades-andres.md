# Dificultades y decisiones durante el desarrollo — Andrés

## Integración con una base que se construyó por partes

El proyecto se repartió entre módulos que dependen unos de otros. Al principio, los archivos de personal y riesgo no existían y varias acciones devolvían `CA099` en modo real. Para avanzar sin duplicar el trabajo de André, implementé los módulos `20` y `40` conservando la estructura y las firmas del contrato, y después conecté las acciones correspondientes.

Una dificultad fue mantener el orden de instalación SQL: esquema y funciones comunes, personal, rondas, riesgo, permisos y finalmente las semillas. El script `run_all.sh` facilitó esa integración, pero omite archivos que todavía no existen. Por eso no basta con ver el mensaje de base lista: también hay que comprobar los datos y las pruebas.

## Reglas de negocio que no dependen del frontend

La validación de turnos, rotación, competencias, límites y estados de jugadores se implementó en PostgreSQL. Esto permite que una operación no autorizada sea rechazada aun cuando alguien omita las validaciones visuales. Las restricciones combinan `CHECK`, `UNIQUE`, índices parciales, triggers y funciones de PL/pgSQL.

Una decisión importante fue calcular el estado del jugador mediante una vista en vez de guardar una etiqueta que pudiera quedar desactualizada. También se verificó que una suspensión por deuda pudiera levantarse con un abono sin cancelar otra suspensión independiente.

## Datos históricos y horarios relativos

Las pruebas necesitaban rondas de ejemplo y también escenarios de riesgo que no dependieran de una fecha fija. Los turnos de la semilla se calculan respecto al momento de instalación, con un turno vigente, uno anterior, uno futuro y uno histórico. De esa manera se pueden demostrar restricciones de rotación y preparar apuestas históricas sin confundirlas con las pérdidas del día. El turno vigente caduca naturalmente, de modo que la demo debe prepararse antes de la exposición.

## Entorno de ejecución

En Windows se presentó un bloqueo del motor de Docker Desktop. Se recuperó reiniciando el entorno WSL y volviendo a iniciar Docker. Como había otros proyectos con contenedores y bases de datos, se usó un contenedor independiente `casino-postgres` publicado en el puerto `55433`, sin reutilizar la base de datos de otro proyecto. El cliente `psql` se ejecutó dentro del contenedor, ya que no estaba disponible en PowerShell.

## Errores detectados en pruebas integrales

La primera batería completa generó **39 `OK`, 2 `FALLO`, 0 `PENDIENTE`**. Los errores aparecieron en pruebas que intentaban crear jugadores con documentos `T-1001` y `DOC-t_jug1`, incompatibles con la validación numérica del módulo de riesgo. André corrigió esos valores en `main` y, tras integrar los cambios en `andres/backend`, **reproduje localmente 109 `OK`, 0 `FALLO` y 0 `PENDIENTE`**, con código de salida 0. La validación de identidad se mantuvo sin cambios.

Se detectó además que el rol `casino_app` no tenía permiso `EXECUTE` en ocho funciones públicas revisadas del módulo nuevo. André incorporó los permisos de funciones públicas en `main`. Tras reconstruir la base, **ocho funciones representativas comprobadas** devolvieron `t` para `casino_app`; la batería de pruebas confirmó también el rechazo de acceso directo a tablas. Queda por ampliar la auditoría a las 20 funciones si se busca exhaustividad.

## Estado y tareas por cerrar

Las pruebas aisladas de los módulos 20 y 40 y la compilación inicial de las acciones de Next.js sí finalizaron correctamente. La batería integral ya se repitió correctamente tras el merge. Quedan las pruebas desde la interfaz de los cuatro roles, la conciliación de algunas reglas con la especificación original, la publicación del merge local junto con esta documentación y la integración final mediante el PR de `andres/backend`.
