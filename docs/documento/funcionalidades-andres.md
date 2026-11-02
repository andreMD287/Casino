# Funcionalidades implementadas — Andrés

## Responsabilidad dentro del equipo

Me encargué de la lógica de empleados, mesas y turnos, además de las validaciones de riesgo y el historial de jugadores. André preparó el esquema base, autenticación, rondas y apuestas; Hania desarrolla la interfaz. Por eso mis funciones conservan las firmas del contrato común y se integran mediante las acciones de Next.js.

## Empleados y competencias

El administrador puede crear, editar y desactivar empleados. Se guarda nombre, documento, cargo, salario mensual y la cuenta de usuario asociada. El trigger de empleados conserva la consistencia entre cargo y rol. La desactivación se bloquea cuando el empleado está asignado a un turno vigente o futuro. También se pueden agregar y retirar competencias por juego; una competencia utilizada en una asignación vigente o futura no se puede retirar.

Archivos: `db/20_personal_mesas.sql`, `src/server/acciones/personal.ts`.

## Mesas, jornadas y turnos

Cada mesa tiene código, tipo de juego y límites de apuesta. El administrador puede crearla, actualizarla o desactivarla respetando sus restricciones. Las jornadas agrupan turnos numerados correlativamente; los turnos duran como máximo dos horas y no pueden solaparse en la misma jornada.

Las asignaciones relacionan una mesa, un turno, un crupier y un supervisor. La base rechaza a quien tenga cargo incorrecto, esté inactivo, desconozca el juego, ya atienda otra mesa en ese turno o repita mesa durante la jornada. Las funciones verifican que no se eliminen turnos o asignaciones vinculados a rondas.

Archivos: `db/20_personal_mesas.sql`, `src/server/acciones/mesas.ts`.

## Conceptos de supervisores

El supervisor asignado emite, al finalizar el turno, un único concepto entre cuatro valores: Genera ganancias, Genera pérdidas, Sospecha de fraude o Comportamiento neutro. Se trata de una apreciación subjetiva que no se calcula a partir del resultado nominal de la mesa. La función y el trigger impiden conceptos anticipados, duplicados o emitidos por otro supervisor.

## Jugadores, autorización y riesgo

El registro de jugadores exige mayoría de edad y un documento con formato válido. Antes de aceptar una apuesta, `fn_puede_apostar` rechaza jugadores inactivos, suspendidos o con una investigación abierta. `fn_evaluar_riesgo` examina las apuestas liquidadas y puede generar una suspensión de 24 horas por superar el umbral diario. El jugador también puede solicitar una pausa voluntaria por 24 horas.

Cuando un jugador también es empleado, se calcula la deuda acumulada y se suspende si supera dos salarios mensuales. Registrar un abono disminuye la deuda y puede levantar la suspensión. Si su ganancia neta supera un salario mensual, se abre una investigación que debe cerrar el administrador.

Archivos: `db/40_riesgo_historial.sql`, `src/server/acciones/riesgo.ts`.

## Historial y trazabilidad

Las vistas permiten consultar el estado, saldo, apuestas, movimientos, suspensiones, investigaciones y deuda de una cuenta de empleado-jugador. Los estados no se almacenan como un campo editable: se calculan de acuerdo con suspensiones e investigaciones vigentes. Las lecturas se realizan mediante vistas, y las escrituras mediante funciones protegidas de PostgreSQL.

## Datos de prueba y validación

Las semillas `91` y `92` agregan empleados, competencias, mesas, turnos, jugadores y escenarios para mostrar reglas de riesgo. Junto con la semilla `93` de André, la ejecución del 2 de noviembre de 2026 creó siete empleados, tres mesas, cinco jugadores, diez rondas y 62 apuestas.

Los tests de `db/tests/20_personal_mesas.sql` y `db/tests/40_riesgo_historial.sql` terminaron individualmente sin `FALLO`. La ejecución integral del mismo día registró 39 comprobaciones `OK`, dos archivos de prueba con fallo y cero `PENDIENTE`. Los fallos correspondieron a documentos alfanuméricos en `10_auth.sql` y `30_rondas_apuestas.sql`. André los corrigió en `main`; luego de fusionar esos cambios localmente en `andres/backend`, **repetí la batería SQL y obtuve 109 `OK`, 0 `FALLO`, 0 `PENDIENTE`, con código de salida 0**.

Las acciones TypeScript de mis módulos pasaron `npm run lint` y `npm run build` también después del merge. **Verifiqué que ocho funciones públicas consultadas devuelven `t`** en `has_function_privilege` para `casino_app`. La verificación exhaustiva de las 20 funciones y las pruebas desde formularios reales siguen pendientes hasta integrar el frontend.

## Funciones opcionales y decisiones pendientes

Consignaciones y retiros todavía retornan `CA399` (No disponible) en modo real; son opcionales en el alcance acordado. El cálculo diario sigue la fórmula de pérdidas netas definida en el contrato común, pendiente de conciliación con la especificación inicial. También requiere confirmación y prueba la restricción de empleados que juegan durante su turno y la prohibición de cerrar investigaciones propias.
