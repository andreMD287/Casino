# Descripción del framework: Next.js

*Sección a cargo de André.*

## Qué es

Next.js es un framework de React, mantenido por Vercel, para construir aplicaciones web completas: la
misma base de código contiene la interfaz (componentes React) y el código de servidor (lectura de datos,
escrituras, autenticación). Usamos **Next.js 16.4** con **React 19**, TypeScript estricto y Tailwind CSS 4,
ejecutado sobre Node.js.

## Piezas que usa el proyecto

| Pieza | Qué es | Cómo la usamos |
|---|---|---|
| **App Router** (`src/app`) | El enrutamiento se define con carpetas: cada `page.tsx` es una ruta y cada `layout.tsx` envuelve a sus hijas. | Una sección por rol (administrador, crupier, supervisor, jugador). El layout de cada sección llama `exigirSesion(rol)`. |
| **Server Components** | Componentes que se ejecutan solo en el servidor. Pueden ser `async` y leer datos directamente; al navegador solo llega el HTML/resultado, no el código ni las credenciales. | Las páginas leen datos llamando acciones de lectura (que consultan las vistas `v_*`). |
| **Client Components** (`'use client'`) | Componentes interactivos que corren en el navegador. | Formularios, el login (el cálculo SRP con la clave ocurre aquí y la clave nunca sale del navegador). |
| **Server Actions** (`'use server'`) | Funciones de servidor que el navegador invoca como si fueran funciones locales. Next genera un endpoint POST por cada una, con un id no adivinable. | Toda escritura (y las lecturas) pasa por `src/server/acciones/*.ts`, envueltas en `crearAccion`. |
| **Proxy** (`src/proxy.ts`) | Código que corre antes de cada petición. En Next 16 reemplaza a `middleware.ts` (que quedó deprecado; solo cambió el nombre). | Solo verifica que exista la cookie de sesión y redirige a `/login`. No consulta la base. |
| **`cookies()`**, **`redirect()`** | APIs del servidor para leer/escribir cookies y redirigir. | Cookie `casino_sesion` (`httpOnly`, `sameSite=strict`, `secure` en producción). |

Decisión de configuración: Next 16 trae activado *Cache Components* (prerenderizado parcial y caché por
componente). Lo desactivamos porque casi todas las páginas dependen de la sesión del usuario; el modelo
dinámico clásico (cada petición se renderiza con su cookie) es más simple y evita mostrar datos en caché
de otro usuario.

## Por qué encaja con este proyecto

1. **Un solo lenguaje y un solo despliegue.** Frontend y backend en TypeScript, con tipos compartidos
   (`src/lib/contrato.ts`): si el contrato cambia, el compilador marca en ambos lados lo que se rompe.
2. **Server Actions = capa de servicio delgada.** Cada acción valida el formato (zod), fija el actor y llama
   una función `fn_*` de PostgreSQL. No hace falta diseñar una API REST, versionarla ni escribir un cliente HTTP.
3. **Seguridad por defecto.** El código de los Server Components y Server Actions nunca llega al navegador,
   y `import 'server-only'` hace que el build falle si alguien importa la conexión a la base desde un
   componente de cliente. Las acciones solo aceptan POST con su id y Next compara el `Origin` con el `Host`
   (protección básica contra CSRF), a lo que sumamos el formulario firmado con SHA-256.
4. **Encaja con "la base de datos es dueña de las reglas".** Como no hay ORM, el servidor es un pasamanos
   seguro hacia funciones `SECURITY DEFINER`; Next aporta el enrutamiento, la sesión y la interfaz.
5. **Trabajo en paralelo.** Con `MODO_MOCK=1` las mismas acciones devuelven datos de ejemplo, así el
   frontend avanza sin base de datos.

## Limitaciones que encontramos (para el análisis crítico)

- Cambia rápido: la versión 16 renombró `middleware` a `proxy` y activó Cache Components por defecto;
  mucha documentación y ejemplos en internet están desactualizados.
- Las Server Actions son endpoints públicos aunque no se vean: cualquiera con el id puede invocarlas.
  Por eso **toda** acción revalida sesión y rol en el servidor (`crearAccion`) y la base lo vuelve a validar.
- Las Server Actions se ejecutan en serie por cliente y no están pensadas como API para terceros.
- El límite entre código de servidor y de cliente no siempre es obvio para quien empieza
  (qué se puede importar dónde, qué se serializa).
