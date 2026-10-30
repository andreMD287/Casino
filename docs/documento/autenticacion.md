# Autenticación Zero Knowledge con SRP-6a y SHA-256

*Sección a cargo de André.*

## Requisito

El enunciado pide autenticación **Zero Knowledge**, manejo de sesiones y almacenamiento de contraseñas con
**SHA-256**. Usamos el protocolo **SRP-6a** (Secure Remote Password, RFC 2945 / RFC 5054): el servidor
verifica que el usuario conoce la clave sin que la clave, ni un hash que sirva para entrar, viaje nunca por la red.

## Librería y verificación de SHA-256

Librería: [`secure-remote-password`](https://github.com/LinusU/secure-remote-password) **0.3.1** (la misma en el
navegador y en el servidor). Revisamos su código en `node_modules/secure-remote-password`:

| Qué se verificó | Dónde | Resultado |
|---|---|---|
| Función hash | `lib/params.js`: `hashFunction: 'sha256'`, `H = sha256`; en el navegador `browser/sha256.js` (SHA-256 en JS puro) | **SHA-256** ✔ |
| Derivación de x | `client.js` → `derivePrivateKey`: `x = H(s, H(I + ':' + p))` | `x = SHA-256(salt ‖ SHA-256(usuario ":" clave))` ✔ (igual al contrato) |
| Grupo | `lib/params.js`: primo seguro de **2048 bits** (RFC 5054), `g = 2` | ✔ |
| Multiplicador | `k = H(N, g)` | SRP-**6a** (no SRP-6 con k = 3) ✔ |
| Aleatoriedad | `crypto.randomBytes` en Node, `crypto.getRandomValues` en el navegador; salt, `a` y `b` de 256 bits | ✔ |

No hubo que configurar ni reemplazar la librería, así que el plan B (desafío-respuesta con SHA-256) no fue necesario.

## Qué se guarda

En la tabla `usuarios` solo hay **salt** (aleatorio, 32 bytes) y **verificador** `v = g^x mod N`.
No se guarda la clave ni un hash de la clave. Obtener la clave a partir de `v` exige resolver un logaritmo
discreto en un grupo de 2048 bits, y aun así habría que probar clave por clave (cada intento cuesta una
exponenciación modular). El verificador no sirve para iniciar sesión: el servidor no puede hacerse pasar por
el usuario con lo que tiene guardado.

## Protocolo

```
 Navegador (conoce usuario I y clave p)                     Servidor (conoce s y v)
 ───────────────────────────────────────                    ─────────────────────────────
 a = aleatorio,  A = g^a mod N
                          ── loginPaso1(I, A) ──────────►
                                                            fn_srp_datos_login(I) → s, v
                                                            (si I no existe: s = HMAC(SECRETO, I),
                                                             v falso derivado del mismo secreto)
                                                            b = aleatorio, B = k·v + g^b mod N
                                                            fn_guardar_desafio(id, A, B, b)  vence en 2 min
                          ◄── { idDesafio, s, B } ─────────
 x = H(s, H(I ":" p))
 u = H(A, B)
 S = (B − k·g^x)^(a + u·x) mod N,   K = H(S)
 M1 = H(H(N) xor H(g), H(I), s, A, B, K)
                          ── loginPaso2(idDesafio, M1) ──►
                                                            fn_consumir_desafio(id)  (uso único, CA005)
                                                            S = (A·v^u)^b mod N,  K = H(S)
                                                            compara M1   ── no coincide → CA004
                                                            M2 = H(A, M1, K)
                                                            token = 32 bytes aleatorios
                                                            fn_crear_sesion(SHA-256(token), canal, 8 h)
                          ◄── { M2, rol } + cookie ────────  Set-Cookie: casino_sesion=token
                                                              (httpOnly, sameSite=strict, secure)
 verifica M2 con K   ── no coincide → CA008
 (el servidor también demostró conocer v)
```

Ambos lados llegan a la misma clave de sesión `K` sin transmitirla. `M1` prueba que el cliente conoce la
clave; `M2` prueba que el servidor conoce el verificador (autenticación **mutua**: un servidor falso no
puede calcular `M2`).

## Dónde se usa SHA-256

1. **Derivación de x** (y de `u`, `k`, `K`, `M1`, `M2`) dentro de SRP-6a.
2. **Hash del token de sesión:** la cookie lleva un token aleatorio de 32 bytes; la base guarda
   `SHA-256(token)` en `sesiones.token_hash`. Si alguien lee la tabla de sesiones, no obtiene cookies válidas.
3. **Firma del formulario seguro:** `firma = SHA-256(canal + fechahora)`, donde `canal` es un secreto
   aleatorio de la sesión que nunca sale del servidor. `crearAccion` recalcula la firma, la compara con
   `timingSafeEqual` y exige menos de 30 minutos de antigüedad (`CA007`). Sin sesión (registro de
   jugadores) se usa un canal anónimo que pone el proxy en una cookie `httpOnly`.

## Por qué es Zero Knowledge

- La clave nunca sale del navegador: solo viajan `I`, `A`, `M1` (y, al registrarse, `s` y `v`).
- Lo que ve un espía en la red (`A`, `B`, `s`, `M1`, `M2`) no permite probar claves sin conocer `a` o `b`:
  no hay un "hash de la clave" que atacar fuera de línea.
- Lo que guarda el servidor (`s`, `v`) no permite iniciar sesión.
- Cada login usa efímeros nuevos (`a`, `b`): una respuesta grabada no sirve para otro intento, y el
  desafío es de **uso único** y vence en **2 minutos**.

## Defensas adicionales

| Defensa | Implementación |
|---|---|
| No revelar si un usuario existe | Respuesta **señuelo**: para un usuario inexistente el paso 1 devuelve un salt `HMAC-SHA256(SECRETO_SERVIDOR, usuario)` (estable entre intentos) y un `B` con un verificador falso; también se guarda un desafío. El paso 2 hace el mismo cálculo y falla con el mismo `CA004`. Medido: ≈ 40 ms en ambos casos. |
| Fuerza bruta | 5 intentos fallidos de un usuario en 15 minutos bloquean nuevos desafíos (`CA006`), contado en `desafios_login`. |
| Sesión creada sin SRP | `fn_crear_sesion` exige un desafío exitoso de ese usuario en los últimos 2 minutos: ni con el rol de la app se puede crear una sesión a mano. |
| Robo de la tabla `sesiones` | Solo hay `SHA-256(token)`. |
| XSS / CSRF sobre la cookie | `httpOnly` (JavaScript no la lee), `sameSite=strict`, `secure` en producción; además el formulario firmado. |
| Sesiones | Duran 8 horas; `fn_obtener_sesion` descarta sesiones cerradas, vencidas o de usuarios desactivados. `cerrarSesion` marca `cerrada_en` y borra la cookie. |

## Pruebas

- `db/tests/10_auth.sql`: registro, duplicados, desafío reutilizado / vencido / señuelo, bloqueo, sesión
  vencida / cerrada / de usuario inactivo, `CA001`/`CA002`, y que `casino_app` no puede tocar tablas.
- `npm run probar:auth` (`scripts/probar-auth.ts`): el flujo completo con la librería real contra la base:
  login correcto con verificación de M2, clave incorrecta, usuario inexistente con la misma respuesta,
  desafío reutilizado y vencido, sesión vencida y cerrada, acción con rol no permitido, firma alterada y bloqueo.

## Limitaciones

- **Dependemos de una librería pequeña** (`secure-remote-password`, poco mantenida). La auditamos a mano,
  pero un error en ella comprometería el login. Es JavaScript puro: el cálculo en el navegador tarda unos
  cientos de milisegundos en equipos lentos.
- **Más difícil de depurar** que un login con contraseña: un error en cualquier parámetro (usuario con
  mayúsculas, salt distinto) da simplemente "clave incorrecta". Por eso normalizamos el usuario a minúsculas
  en los dos lados.
- **No reemplaza HTTPS.** SRP protege la clave, pero el código JavaScript que hace el cálculo llega por la red:
  sin HTTPS, un atacante en el medio podría inyectar un script que capture la clave al escribirla. La cookie
  `secure` también requiere HTTPS en producción.
- **El bloqueo revela existencia:** después de 5 fallos, un usuario real recibe `CA006` y uno inexistente no.
  Se podría ocultar contando también los fallos de nombres inexistentes; quedó como mejora pendiente.
- **El bloqueo permite molestar a otro usuario:** quien conozca un nombre de usuario puede fallar 5 veces y
  dejarlo 15 minutos sin poder entrar. Es el costo habitual de este tipo de bloqueo.
- El `b` del servidor queda guardado en `desafios_login` mientras vive el desafío (2 minutos); solo lo puede
  leer el dueño de la base, no `casino_app`.
