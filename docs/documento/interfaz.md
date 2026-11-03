# Diseño e implementación de la interfaz — Casino

## Identidad visual

La interfaz adopta la opción 6 acordada por el equipo: morado ciruela, carbón, marfil y dorado cálido. Se utiliza una tipografía serif para encabezados y una sans-serif legible para controles y tablas. El diseño es adaptable: escritorio para administración y tablet para crupier.

## Arquitectura del frontend

- Next.js App Router con Server Components para obtener información en las rutas y Client Components para formularios, filtros y confirmaciones.
- Se utilizan las Server Actions declaradas en `src/server/acciones/*.ts`; la interfaz no escribe directamente en las tablas ni calcula saldos o liquidaciones.
- `src/components/navegacion/menu.ts` define los enlaces permitidos por rol, mientras cada `layout.tsx` aplica `exigirSesion(rol)` en el servidor. Ocultar menús no sustituye la validación de permisos del servidor.
- Las escrituras reciben `CamposSeguros`; después de un éxito se invoca `router.refresh()` para mostrar información persistida.
- Inicio de sesión con `iniciarSesion` y registro mediante `derivarCredenciales`: la contraseña no se envía como dato de registro.
- Los errores mostrados proceden de `Resultado.error.mensaje`; `CA007` solicita recarga del formulario.
- Los importes se reciben como cadenas; se formatean con `Intl.NumberFormat('es-CO')`. Las fechas se presentan en `America/Bogota`.

## Rutas diseñadas

Públicas `/login` y `/registro`.
Administrador `/admin`, `/admin/empleados`, `/admin/empleados/[id]`, `/admin/mesas`, `/admin/mesas/[id]`, `/admin/turnos`, `/admin/opciones`, `/admin/jugadores`, `/admin/jugadores/[id]`, `/admin/riesgo`, `/admin/reportes`.
Crupier `/crupier` y `/crupier/mesas/[mesaId]`.
Supervisor `/supervisor` y `/supervisor/mesas/[mesaId]`.
Jugador `/jugador`.
Especiales `/prohibido` y `not-found`.

## Criterios de usabilidad

Los controles importantes incorporan etiquetas y mensajes de error, las acciones destructivas exigen confirmación y los botones de escritura permanecen deshabilitados durante la operación. Las tablas ofrecen estados vacíos. La pantalla del crupier conserva un flujo continuo buscar jugador → seleccionar opción → monto → confirmar. Los resultados de apuestas, bloqueos y suspensiones se delegan al servidor.

## Estado de verificación

Este documento describe el código de frontend creado como **paquete separado**, todavía no integrado ni probado en el repositorio real. Requiere validación con `npm run lint`, `npm run build` y `MODO_MOCK=0`, además de una prueba manual con los cuatro roles.
