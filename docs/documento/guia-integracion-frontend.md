# Guía de integración entre frontend y backend — Casino

**Versión de referencia:** rama `andres/backend`, commit `f0fd284`, posterior a la integración de `origin/main` que incluye `214196f`. **Verificar el commit actual antes de conectar componentes.** Esta guía describe las firmas revisadas en `src/server/acciones/`, no constituye una prueba HTTP del frontend.

## 1. Reglas compartidas

- Los componentes deben llamar las **Server Actions exportadas**, no acceder directamente a PostgreSQL ni ejecutar SQL desde el navegador.
- Las acciones devuelven `Resultado<T>`: `{ ok: true, datos: T }` o `{ ok: false, error: { codigo, mensaje } }`. Evaluar `res.ok` antes de usar `res.datos`.
- Las acciones protegidas con `seguro: true` requieren el último argumento `CamposSeguros`, obtenido mediante `obtenerCamposSeguros()` de `@/server/acciones/auth` **justo antes de ejecutar** la acción. No construir ni inventar la firma en el cliente.
- `Dinero` y `factorPago` son **cadenas decimales** (`"12000.00"`), no números de JavaScript. No usar `parseFloat` para calcular saldos de apuestas.
- Las fechas de turno deben enviarse como ISO con zona horaria explícita (ejemplo `2026-11-02T09:00:00-05:00`); la jornada usa `YYYY-MM-DD`.
- Los roles válidos son `administrador`, `crupier`, `supervisor`, `jugador`. Las acciones ya verifican rol y sesión; las restricciones de negocio también se verifican en PostgreSQL.
- MODO_MOCK=1 sirve para maquetación; **validación final en MODO_MOCK=0** y PostgreSQL real.
- Los arreglos/objetos resultantes usan propiedades camelCase, conforme a `src/lib/contrato.ts`.

## 2. Autenticación y seguridad

| Exportación | Propósito / uso |
|---|---|
| `loginPaso1(usuario, A)` | Inicio de login SRP-6a. No inventar manualmente `A`. |
| `loginPaso2(idDesafio, M1)` | Completa autenticación SRP-6a, crea sesión y devuelve `M2`. Usar el cliente SRP de `src/lib/srp-cliente.ts`. |
| `registrarJugador(datos, credenciales, seguro)` | Registro público; `datos={documento,nombre,fechaNacimiento}`. Credenciales SRP calculadas en cliente. |
| `obtenerCamposSeguros()` | Obtener `{fechahora,firma}` para la siguiente escritura. |
| `cerrarSesion()` | Cierra la sesión actual. |
| `obtenerSesion()` desde `@/server/auth/sesion` | Leer rol/usuario desde un componente de servidor. |

### Patrón básico de una acción

```ts
import { obtenerCamposSeguros } from '@/server/acciones/auth';
import { crearMesa } from '@/server/acciones/mesas';

// En una interacción autorizada de administrador:
const seguro = await obtenerCamposSeguros();
const res = await crearMesa(
  { codigo: 'RUL-04', juegoId: 1, montoMinimo: '100', montoMaximo: '1000' },
  seguro,
);
if (!res.ok) {
  // Mostrar res.error.mensaje; si es CA007, renovar los campos seguros.
} else {
  // Mostrar/actualizar datos con res.datos (tipo Mesa).
}
```

Ejemplo de interfaz; no ejecutar la creación con ese código literal contra la base de demostración salvo que se desee agregar una mesa real.

## 3. Personal — `@/server/acciones/personal`

| Acción | Roles | Argumentos | Devuelve |
|---|---|---|---|
| `listarJuegos` | Todos | `()` | `Juego[]` |
| `listarEmpleados` | Administrador | `()` | `Empleado[]` |
| `crearEmpleado` | Administrador | `(datos, credenciales, seguro)` | `Empleado` |
| `actualizarEmpleado` | Administrador | `(empleadoId, datos, seguro)` | `Empleado` |
| `desactivarEmpleado` | Administrador | `(empleadoId, seguro)` | `null` |
| `asignarCompetencia` | Administrador | `(empleadoId, juegoId, seguro)` | `null` |
| `quitarCompetencia` | Administrador | `(empleadoId, juegoId, seguro)` | `null` |

`datos` de empleado: `{ nombre: string, documento: string, cargo: 'administrador'|'crupier'|'supervisor', salarioMensual: string }`. `credenciales` es `{usuario,salt,verificador}` SRP, generado apropiadamente en el cliente. `Empleado.competencias` es una lista de `{ juegoId, juego }`.

## 4. Mesas, jornadas y supervisión — `@/server/acciones/mesas`

| Acción | Roles | Argumentos | Devuelve |
|---|---|---|---|
| `listarMesas` | Administrador, crupier, supervisor | `()` | `Mesa[]` |
| `crearMesa` | Administrador | `(datosMesa, seguro)` | `Mesa` |
| `actualizarMesa` | Administrador | `(mesaId, datosMesa, seguro)` | `Mesa` |
| `desactivarMesa` | Administrador | `(mesaId, seguro)` | `null` |
| `listarJornadas` | Administrador, supervisor | `()` | `Jornada[]` |
| `crearJornada` | Administrador | `(fechaYYYYMMDD, seguro)` | `Jornada` |
| `listarTurnos` | Administrador, supervisor | `(jornadaId)` | `Turno[]` |
| `crearTurno` | Administrador | `(jornadaId, {inicio,fin}, seguro)` | `Turno` |
| `eliminarTurno` | Administrador | `(turnoId, seguro)` | `null` |
| `listarAsignaciones` | Administrador, supervisor | `(jornadaId)` | `Asignacion[]` |
| `crearAsignacion` | Administrador | `({turnoId,mesaId,crupierId,supervisorId}, seguro)` | `Asignacion` |
| `eliminarAsignacion` | Administrador | `(asignacionId, seguro)` | `null` |
| `misTurnosSupervisor` | Supervisor | `()` | `Asignacion[]` de la jornada actual |
| `emitirConcepto` | Supervisor | `(asignacionId, concepto, observacionO_null, seguro)` | `Asignacion` |

`datosMesa={codigo,juegoId,montoMinimo,montoMaximo}`; fechas ISO con offset. Los conceptos permitidos son **exactamente** `Genera ganancias`, `Genera pérdidas`, `Sospecha de fraude`, `Comportamiento neutro`.

**Reglas a mostrar en la UI:** máximo dos horas por turno, no solapamiento, competencias del crupier/supervisor, rotación de crupier por mesa durante la jornada, concepto solo al finalizar y únicamente por el supervisor asignado. No intentar sustituir las validaciones SQL con la interfaz.

## 5. Jugadores, riesgo e historial — `@/server/acciones/riesgo`

| Acción | Roles | Argumentos | Devuelve |
|---|---|---|---|
| `listarJugadores` | Administrador | `(filtro?: string)` | `Jugador[]` |
| `obtenerHistorial` | Administrador | `(jugadorId)` | `Historial` |
| `miHistorial` | Jugador | `()` | `Historial` de la cuenta autenticada |
| `actualizarJugador` | Administrador | `(jugadorId, {nombre,documento}, seguro)` | `Jugador` |
| `desactivarJugador` | Administrador | `(jugadorId, seguro)` | `null` |
| `solicitarPausa` | Jugador | `(seguro)` | `Suspension` |
| `listarSuspensiones` | Administrador | `(soloActivas: boolean)` | `Suspension[]` |
| `listarInvestigaciones` | Administrador | `(soloAbiertas: boolean)` | `Investigacion[]` |
| `cerrarInvestigacion` | Administrador | `(investigacionId, resolucion, seguro)` | `null` |
| `registrarAbono` | Administrador | `(jugadorId, montoString, seguro)` | `{deudaRestante: string}` |
| `obtenerUmbral` | Administrador | `()` | `{umbralPerdidaDiaria: string}` |
| `actualizarUmbral` | Administrador | `(montoString, seguro)` | `null` |

`Historial={jugador,apuestas,movimientos,suspensiones,investigaciones,deudaEmpleado}`. `Jugador.estado` es uno de `Activo`, `Suspendido`, `Investigación`, `Inactivo`.

**Decisión de equipo:** pausa voluntaria solo desde la cuenta del jugador. No añadir una opción de pausa administrativa. `registrarConsignacion` y `registrarRetiro` aparecen como exportaciones opcionales pero **no están implementadas en SQL**: devuelven `CA399` en modo real; no habilitar pantallas que las anuncien como funcionales.

**Reglas recientes:** pérdidas brutas del día mayores que el umbral → suspensión; empleado con asignación en turno vigente → `CA311` al intentar apostar; administrador que cierre investigación propia → `CA310`.

## 6. Rondas y apuestas — módulos de André

| Acción | Roles | Argumentos |
|---|---|---|
| `misMesasActuales` | Crupier | `()` |
| `listarRondas` | Crupier, supervisor, administrador | `(mesaId)` |
| `obtenerRonda` | Crupier, supervisor, administrador | `(rondaId)` |
| `abrirRonda` | Crupier | `(mesaId, seguro)` |
| `cerrarRonda` | Crupier | `(rondaId, opcionesGanadoras: number[], seguro)` |
| `anularRonda` | Crupier, administrador | `(rondaId, seguro)` |
| `reporteMesaTurno` | Administrador | `(jornadaId)` |
| `listarOpciones` | Todos | `(juegoId)` |
| `crearOpcion`, `actualizarOpcion` | Administrador | `(juegoId, {nombre,factorPago}, seguro)` / `(opcionId, {nombre,factorPago}, seguro)` |
| `desactivarOpcion` | Administrador | `(opcionId, seguro)` |
| `buscarJugadorParaApuesta` | Crupier | `(codigoJugador)` |
| `listarApuestas` | Crupier, supervisor, administrador | `(rondaId)` |
| `registrarApuesta` | Crupier | `({rondaId,jugadorId,opcionId,monto}, seguro)` |
| `registrarApuestaResuelta` | Crupier | `({rondaId,jugadorId,opcionId,monto,ganada}, seguro)` |
| `anularApuesta` | Crupier | `(apuestaId, seguro)` |

**Ruleta:** al cerrar, el resultado debe incluir exactamente un número pleno; `CA217` rechaza resultados incoherentes y el SQL determina color, paridad y docena. Para el cero, solo gana el pleno cero. Esto ya fue aprobado en las pruebas SQL de integración; falta verlo operando desde la interfaz.

## 7. Errores relevantes de la UI

| Código | Cuándo mostrarlo |
|---|---|
| `CA002` | Rol insuficiente: acción no permitida |
| `CA007` | Formulario seguro inválido o vencido: recargar/renovar |
| `CA009` | Sesión vencida: enviar al login |
| `CA305` | Segunda pausa voluntaria no permitida |
| `CA310` | Administrador intenta cerrar su propia investigación |
| `CA311` | Empleado intenta apostar mientras está en turno |
| `CA217` | Resultado de ruleta incoherente |
| `CA000` | Error interno: no mostrar información técnica confidencial |

No depender de textos literales para lógica de UI: utilizar `error.codigo` y presentar `error.mensaje` al usuario con contexto cuando corresponda.

## 8. Criterios de aceptación antes del merge final

1. Confirmar que la rama de frontend esté publicada y basada en el `main` más reciente; evitar cambios paralelos a contratos compartidos sin coordinación.
2. Probar login y logout para los cuatro roles con `MODO_MOCK=0`.
3. Verificar navegación y bloqueo por roles, tanto por URL como por acción.
4. Probar un flujo positivo y negativo por formulario importante (administración de mesas, asignaciones, concepto, ronda, apuesta, historial y pausa).
5. Verificar que el frontend actualice datos tras cada operación y que las cifras monetarias se mantengan correctas.
6. Ejecutar `npm run lint`, `npm run build`, la batería SQL y `npm run probar:auth` con variables `PGHOST=127.0.0.1` y `PGPORT=55433` cuando PostgreSQL está publicado en ese puerto.
7. Mantener un PR en borrador hasta que el equipo vea las pruebas funcionales; los tests SQL y de autenticación no equivalen a tests HTTP de la interfaz.

**Evidencia disponible antes del frontend:** 121 OK SQL; 22 OK SRP; 20 funciones públicas con `EXECUTE`; 14 vistas consultables; 20 vistas con campos esperados; nueve consultas Node/`pg` correctas; lectura de supervisores y siete operaciones de permisos validadas. Estos resultados pertenecen al backend, no certifican las pantallas de Hania.
