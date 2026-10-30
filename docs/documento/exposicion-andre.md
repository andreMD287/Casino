# Guion de exposición — partes de André

## 1. Introducción al framework (≈ 5 min)

- Qué es Next.js: React + servidor en un mismo proyecto. Versión 16.4, App Router.
- Tres ideas: **Server Components** (leen datos en el servidor), **Server Actions** (escrituras como
  funciones), **Proxy** (antes middleware). Diagrama de `framework.md`.
- Por qué encaja: tipos compartidos, sin API REST que mantener, el código de servidor no llega al navegador.

## 2. Explicación técnica: arquitectura (≈ 6 min)

- Diagrama de capas de `arquitectura.md`: navegador → Server Actions → `crearAccion` → `pg` → `fn_*` `SECURITY DEFINER` → tablas.
- "La BD es dueña de las reglas": demostrar que `casino_app` no puede hacer `UPDATE jugadores SET saldo` (42501).
- Las tres capas de autorización con un ejemplo: un jugador que llama `abrirRonda` → rechazado en `crearAccion` (`CA002`) y, aunque se saltara esa capa, en `fn_exigir_rol`.
- Flujo de una apuesta de punta a punta; mostrar el trigger rechazando un `INSERT` directo con monto inválido.
- Concurrencia: dos sesiones de psql (`docs/pruebas/concurrencia.md`) y la captura de `pg_locks`.

## 3. Explicación técnica: autenticación Zero Knowledge (≈ 6 min)

- Qué se guarda: salt y verificador. Mostrar la tabla `usuarios` (no hay clave ni hash de clave).
- Diagrama SRP-6a de `autenticacion.md`; dónde entra SHA-256 (x, token de sesión, firma del formulario).
- Demostración en las herramientas del navegador: en la pestaña Red solo viajan `A`, `M1`; la cookie es `HttpOnly`.
- Defensas: señuelo para usuarios inexistentes, desafío de uso único de 2 minutos, bloqueo tras 5 fallos.

## 4. Análisis crítico desde el backend y la seguridad (≈ 4 min)

| Aspecto | Valoración |
|---|---|
| Calidad / seguridad | Muy buena separación servidor/cliente (`server-only`), pero las Server Actions son endpoints públicos: hay que validar todo en cada una. |
| Curva de aprendizaje | Media-alta: límites servidor/cliente, serialización, cambios entre versiones (proxy, Cache Components). |
| Ventajas | Un solo lenguaje y tipos de punta a punta; las acciones hacen innecesaria una API REST; despliegue simple. |
| Desventajas | Documentación y ejemplos desactualizados entre versiones; depurar Server Actions es menos transparente que una API REST. |
| Limitaciones | SRP depende de una librería pequeña; no reemplaza HTTPS; las acciones no sirven como API para terceros. |

## 5. Conclusiones (aporte a las de los tres)

- Poner las reglas en PostgreSQL hizo que el frontend y el backend en TypeScript fueran delgados y que las
  reglas se pudieran probar con SQL (`run_all.sh --tests`).
- Next.js facilitó el trabajo en paralelo gracias al contrato de tipos y al modo mock.
