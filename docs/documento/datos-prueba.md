# Datos de prueba — Casino (Andrés)

Este documento describe **las semillas propuestas** en `db/91_semilla_personal_mesas.sql` y `db/92_semilla_jugadores.sql`. Los resultados deben confirmarse ejecutando `run_all.sh` y las pruebas de integración contra PostgreSQL antes de la entrega.

## Usuarios

`db/90_semilla_base.sql`, mantenido por André, genera las credenciales SRP de los usuarios `admin`, `crupier1` a `crupier4`, `supervisor1` y `supervisor2`, `jugador1` a `jugador3`, `crupier1.juega` y `supervisor1.juega`. La clave de **solo demostración** se encuentra documentada en el contrato. No utilizar esas credenciales en producción.

## Empleados y competencias

| Usuario | Cargo | Competencias | Salario mensual (fichas) |
|---|---|---|---:|
| `admin` | Administrador | — | 5.000.000 |
| `crupier1` | Crupier | Ruleta, Póker | 1.800.000 |
| `crupier2` | Crupier | Ruleta, Blackjack | 1.900.000 |
| `crupier3` | Crupier | Ruleta, Blackjack, Póker | 2.000.000 |
| `crupier4` | Crupier | Blackjack, Póker | 2.100.000 |
| `supervisor1` | Supervisor | Ruleta, Blackjack, Póker | 2.300.000 |
| `supervisor2` | Supervisor | Ruleta, Póker | 2.400.000 |

Por ejemplo, asignar `crupier2` a Póker o `supervisor2` a Blackjack debe rechazarse con el error de competencia.

## Mesas y jornada

- `RUL-01`: Ruleta, 1.000–100.000 fichas.
- `BJ-01`: Blackjack, 5.000–200.000 fichas.
- `POK-01`: Póker, 10.000–500.000 fichas.
- Umbral de pérdidas diarias: 300.000 fichas (según el contrato vigente: **pérdidas netas**).
- Se crean un turno terminado, uno vigente y uno futuro, todos de menos de dos horas. Los horarios se calculan **en el momento de ejecutar las semillas**, y se asignan los tres juegos en cada uno.
- Se prepara además un turno histórico de tres días antes para las apuestas que demuestran deuda y ganancias acumuladas.

El turno vigente caduca de forma natural. Ejecutar `db/demo/turno_actual.sql` antes de una demostración. Si ya se agotó la rotación de personal de la jornada, conviene **recrear la base de demostración** con `run_all.sh` en el contenedor dedicado en vez de evadir las reglas de rotación. Atención: `run_all.sh` elimina la base `casino` del servidor al que se conecte.

## Jugadores y escenarios

| Cuenta | Saldo inicial | Escenario preparado |
|---|---:|---|
| `jugador1` | 1.000.000 | Jugador activo para rondas y apuestas normales |
| `jugador2` | 1.000.000 | Tres apuestas perdidas de 75.000 en el turno anterior, 225.000 en pérdidas si el turno comenzó hoy |
| `jugador3` | 700.000 | Jugador activo con saldo disponible |
| `crupier1.juega` | 4.500.000 | 3.500.000 de pérdidas históricas, próximo al límite de dos salarios (3.600.000) |
| `supervisor1.juega` | 100.000 | Premio histórico de 2.100.000, próximo al salario de 2.300.000 |

**Saldo inicial** se refiere a la consignación original. Las apuestas históricas modifican ese saldo mediante `fn_mover_saldo`; por tanto, el saldo actual de cada cuenta será distinto. Las apuestas creadas posteriormente por la semilla `93` también lo modificarán.

En `92` el histórico se crea con los triggers y las validaciones reales de rondas y apuestas. Los movimientos de saldo se registran mediante `fn_mover_saldo`, nunca mediante `UPDATE jugadores SET saldo`. Las marcas de tiempo de los movimientos de ejemplo se sitúan en sus rondas históricas.

## Evidencia recomendada para el profesor

1. Administrador: empleados, competencias y mesas con rechazo por competencia.
2. Administrador: jornada, turnos, asignación válida y rechazo por rotación.
3. Crupier: registrar apuesta correcta; rechazar monto fuera de rango y saldo insuficiente.
4. Jugador: consultar historial y solicitar pausa de 24 horas.
5. Administrador: ajustar umbral, consultar suspensiones e investigaciones, registrar abono.
6. Supervisor: emitir concepto **después** del turno y visualizarlo junto al reporte nominal.

Las semillas acercan cuentas a los umbrales; no las bloquean anticipadamente para no interrumpir las rondas de `93`. Los bloqueos se prueban en `db/tests/40_riesgo_historial.sql` y durante la demostración.

## Pendientes de decisión del grupo

- Diferencia entre pérdida diaria bruta del documento de requerimientos y pérdida diaria neta del contrato implementado.
- Bloqueo de empleados que juegan durante su turno, y reglas de aprobación de investigación propia.
- Permisos `EXECUTE` para las funciones públicas de Andrés en `db/50_permisos_auditoria.sql` (responsabilidad de André).
- Ajuste de los documentos de prueba alfanuméricos de `db/tests/30_rondas_apuestas.sql` a la validación numérica del módulo 40 (responsabilidad de André).
