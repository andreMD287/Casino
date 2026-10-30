# PARTE A — CONTRATO COMÚN DEL PROYECTO

> Esta Parte A es idéntica en los prompts de André, Andrés y Hania. Es la fuente de verdad compartida: si algo de tu Parte B parece contradecirla, manda la Parte A. Guárdala también en el repositorio como `docs/CONTRATO.md`.

## A1. Contexto

- Curso: Bases de Datos, Administración y Aplicaciones (Pontificia Universidad Javeriana, Ing. Ricardo Naranjo Faccini).
- Proyecto: aplicación web para la gestión de un casino. Framework asignado por el profesor: **Next.js**. Solo se puede usar Next.js.
- Grupo: **André** (backend: autenticación, rondas y apuestas, base del proyecto), **Andrés** (backend: personal, mesas, riesgo e historial), **Hania** (todo el frontend).
- **Entrega: martes 3 de noviembre de 2026.** Exposición de 45 minutos el 9 o el 23 de noviembre.

### Lo que exige el enunciado del profesor

1. Autenticación de usuarios **Zero Knowledge**: login, manejo de sesiones y almacenamiento de contraseñas usando **SHA-256**.
2. Control de acceso por roles: **administrador, crupier, supervisor, jugador**. Cada rol ve únicamente las funcionalidades que le corresponden.
3. Mínimo 3 casos de uso, con CRUD completo y las restricciones del contexto. Elegidos: **Gestión de mesas**, **Gestión de rondas** y **Gestión de apuestas**.
4. Funcionalidad adicional obligatoria **Interfaz de usuario**, más 3 adicionales. Elegidas: **Gestión de empleados**, **Historial de clientes** y **Validación de autorizaciones/suspensiones**. Opcional si sobra tiempo: **Gestión de consignaciones/retiros**.
5. Base de datos relacional, persistencia, lógica de negocio correcta y arquitectura coherente con el framework.
6. Entregables:
   - Código fuente completo e instrucciones de instalación.
   - Documento técnico: descripción del framework, arquitectura, modelo de datos, funcionalidades implementadas y dificultades encontradas.
   - Evidencia de funcionamiento: datos de prueba y capturas.
7. Exposición: introducción al framework, demostración, explicación técnica, análisis crítico (calidad, facilidad de uso, curva de aprendizaje, ventajas, desventajas, limitaciones) y conclusiones.

### Reglas del casino (contexto del primer parcial)

- **Registro de jugadores:** obligatorio antes de jugar. Se guarda código único de cliente, documento, nombre completo, edad (no se admiten menores) y saldo en fichas.
- **Mesas:** cada una tiene identificador, tipo de juego, monto mínimo y monto máximo por jugada.
- **Crupieres:** a cada mesa se le asigna un crupier por turno.
  - Un crupier solo atiende una mesa a la vez por turno.
  - Los crupieres rotan entre turnos y no repiten mesa durante la misma jornada.
- **Turnos:** su duración se define cada día y no puede superar 2 horas.
- **Supervisores:**
  - Cada mesa tiene un supervisor.
  - Al final de cada turno, el supervisor emite un concepto subjetivo sobre el crupier: "Genera ganancias", "Genera pérdidas", "Sospecha de fraude" o "Comportamiento neutro".
  - Ese concepto no depende de las ganancias o pérdidas nominales de la mesa.
- **Competencias:** crupieres y supervisores solo pueden asignarse a mesas de juegos que conocen.
- **Rondas:** cada ronda pertenece a una mesa, tiene número correlativo, hora de inicio y hora de cierre. En una ronda los jugadores hacen una o más apuestas.
- **Apuestas en juegos con registro detallado:** se registra jugador, ronda, tipo de apuesta, monto y factor de pago.
  - Se verifica que el monto esté dentro del mínimo y el máximo de la mesa.
  - Se verifica que el jugador tenga saldo suficiente.
- **Cierre de ronda:** el crupier ingresa el resultado y el sistema procesa automáticamente cada apuesta.
  - Si coincide con el resultado: queda **Ganada**, con premio = monto × factor, acreditado de inmediato.
  - Si no coincide: queda **Perdida** y el monto queda a favor del casino.
- **Juegos sin registro detallado (póker):** las apuestas se registran solo cuando se conoce el resultado.
- **Autoexclusión:** un jugador queda **Suspendido** 24 horas si su pérdida en el día supera un umbral configurado o si pide una pausa voluntaria.
- **Empleados que juegan:**
  - Si sus pérdidas superan 2 meses de salario, quedan **Suspendidos**. Vuelven a jugar automáticamente cuando la deuda baja de ese límite.
  - Si sus ganancias superan 1 mes de salario, quedan en **Investigación** y no pueden apostar hasta que la investigación termine.

## A2. Decisiones de interpretación (ya tomadas; no se cambian sin acuerdo de los tres)

1. **Usuarios:** cada usuario tiene un solo rol. Un empleado que juega tiene una cuenta de jugador aparte, vinculada con `jugadores.empleado_id`.
2. **Registro de apuestas:** las apuestas las registra el crupier asignado a la mesa en el turno vigente, en nombre del jugador.
3. **Movimientos de saldo en una apuesta:**
   - Al registrar la apuesta se descuenta el monto (movimiento `apuesta`).
   - Si gana, premio = monto × factor, y se acreditan dos movimientos: `devolucion` (el monto) y `premio` (el premio).
   - Si pierde, no hay movimiento: el monto ya quedó en el casino.
4. **Anulación:** una apuesta solo se anula con la ronda abierta y estado pendiente, y genera una `devolucion`. Anular una ronda abierta devuelve todas sus apuestas pendientes.
5. **Resultado de una ronda:** es un conjunto de opciones ganadoras del juego (por ejemplo "Pleno 17", "Negro", "Impar"). Una apuesta gana si su opción está en ese conjunto.
6. **Póker (`registro_detallado = false`):** solo se usa `registrarApuestaResuelta`, que guarda la apuesta ya ganada o perdida. Valida mínimo, máximo, saldo y autorización. El cierre de esas rondas no lleva resultado.
7. **Pérdida neta del día:** suma de montos de apuestas perdidas menos suma de premios de apuestas ganadas, liquidadas hoy. "Hoy" es la fecha en America/Bogota. Si supera `configuracion.umbral_perdida_diaria`, se crea una suspensión `perdida_diaria` de 24 horas desde ese momento. Esta regla aplica a todos los jugadores, incluidas las cuentas de empleados.
8. **Pausa voluntaria:** suspensión `pausa_voluntaria` de 24 horas, solicitada por el propio jugador.
9. **Deuda del empleado:** pérdida neta acumulada histórica de su cuenta de jugador menos sus abonos acumulados.
   - Si la deuda supera 2 × salario mensual, se abre una suspensión `deuda_empleado` sin fecha de fin.
   - Cuando la deuda vuelve a ser ≤ 2 × salario (por ejemplo, tras un abono), la suspensión se levanta sola (`levantada_en`).
10. **Ganancias del empleado:** ganancia neta acumulada desde el cierre de su última investigación (o desde siempre, si no tiene). Si supera 1 × salario mensual, se abre una investigación. Mientras esté abierta, no puede apostar ni retirar. Solo el administrador la cierra.
11. **Estado del jugador:** es derivado, no guardado. Lo calcula la vista `v_estado_jugador` con esta prioridad: `Inactivo` > `Investigación` > `Suspendido` > `Activo`.
12. **Edad:** se guarda `fecha_nacimiento` y se exigen 18 años cumplidos al registrar.
13. **Asignaciones:** cada asignación es una fila por (turno, mesa), con crupier y supervisor.
    - Un supervisor puede supervisar varias mesas en el mismo turno.
    - El crupier debe tener cargo `crupier` y el supervisor cargo `supervisor`. Ambos deben estar activos y tener la competencia del juego de la mesa.
14. **Concepto del supervisor:** uno por asignación, solo después de que termina el turno, y solo lo emite el supervisor de esa asignación.
15. **Turnos de una jornada:** no se solapan, y la fecha local de su inicio coincide con la fecha de la jornada.
16. **Eliminar:** en empleados, mesas, opciones de apuesta y jugadores significa desactivar. Turnos y asignaciones se eliminan solo si no tienen rondas.
17. **Retiros:** un jugador en investigación no puede retirar. Un jugador suspendido sí puede.

## A3. Stack y convenciones

- **Framework:** Next.js estable actual con App Router, TypeScript estricto, npm y Tailwind (viene en el esqueleto).
- **Base de datos:** PostgreSQL 16, driver `pg`. **No usar ORM.** El esquema vive solo en `db/*.sql`, y la BD se recrea desde cero con `db/run_all.sh`; no hay migraciones incrementales.
- **SRP-6a:** librería `secure-remote-password`. Hay que verificar que use **SHA-256**; si no, configurarla o cambiarla por otra implementación de SRP-6a con SHA-256.
- **Validación:** `zod` valida el formato de las entradas en las acciones (tipos, requeridos, positivos). Las reglas de negocio no se validan en TypeScript; viven en la BD.
- **Schema y zona horaria:** todo vive en el schema `casino`. La base usa `ALTER DATABASE casino SET timezone = 'America/Bogota'`.
- **Cabecera de los archivos SQL:** cada `.sql` desde `02` empieza con `SET ROLE casino_owner; SET search_path = casino, public;`.
- **Escrituras:** toda escritura pasa por una función `casino.fn_*` con `SECURITY DEFINER` y `SET search_path = casino, pg_temp`.
- **Lecturas:** pasan por vistas `casino.v_*` o por funciones. El rol `casino_app`, con el que conecta Next.js, **no tiene privilegios sobre tablas**: solo `USAGE` del schema, `EXECUTE` de las funciones públicas y `SELECT` de las vistas.
- **Actor:** el backend hace `SET LOCAL app.usuario_id = <id>` dentro de cada transacción. Las funciones obtienen el actor con `casino.fn_actor()` y exigen permisos con `casino.fn_exigir_rol(VARIADIC p_roles text[])`.
- **Errores:** se lanzan con `RAISE EXCEPTION 'mensaje claro para el usuario' USING ERRCODE = 'CAxxx';`. Cada responsable documenta sus códigos en `docs/errores.md`:

| Rango | Ámbito | Responsable |
|---|---|---|
| `CA0xx` | Autenticación y común | André |
| `CA1xx` | Personal, mesas, turnos | Andrés |
| `CA2xx` | Rondas y apuestas | André |
| `CA3xx` | Jugadores, riesgo, historial | Andrés |

- **Saldo:** el saldo de un jugador **solo** se modifica con `casino.fn_mover_saldo`, nunca con `UPDATE` directo.
- **Dinero:** en la BD es `numeric(14,2)`; en TypeScript es `string` (tipo `Dinero`). Nunca se usa `float` para calcular.
- **Fechas:** `timestamptz` en la BD y string ISO en TypeScript. Se muestran en hora de Bogotá.
- **Git:** cada uno trabaja en su rama (`andre/...`, `andres/...`, `hania/...`) y abre PR a `main`. Antes de cada merge debe pasar `./db/run_all.sh --tests` completo y `npm run build`.

## A4. Propiedad de archivos (nadie edita archivos ajenos)

| Ruta | Dueño |
|---|---|
| `db/00_extensiones.sql`, `db/01_roles_bd.sql`, `db/02_esquema.sql`, `db/05_contrato.sql`, `db/10_auth.sql`, `db/30_rondas_apuestas.sql`, `db/50_permisos_auditoria.sql`, `db/90_semilla_base.sql`, `db/93_semilla_juego.sql`, `db/run_all.sh` | André |
| `db/20_personal_mesas.sql`, `db/40_riesgo_historial.sql`, `db/91_semilla_personal_mesas.sql`, `db/92_semilla_jugadores.sql`, `db/demo/turno_actual.sql` | Andrés |
| `db/tests/10_*.sql`, `db/tests/30_*.sql` | André |
| `db/tests/20_*.sql`, `db/tests/40_*.sql` | Andrés |
| `src/lib/contrato.ts`, `src/lib/srp-cliente.ts`, `src/middleware.ts`, `src/server/db.ts`, `src/server/accion.ts`, `src/server/auth/**`, `src/server/acciones/auth.ts`, `src/server/acciones/rondas.ts`, `src/server/acciones/apuestas.ts`, `src/server/mocks/auth.ts`, `src/server/mocks/rondas.ts`, `src/server/mocks/apuestas.ts`, `scripts/**`, `.github/CODEOWNERS` | André |
| `src/server/acciones/personal.ts`, `src/server/acciones/mesas.ts`, `src/server/acciones/riesgo.ts`, `src/server/mocks/personal.ts`, `src/server/mocks/mesas.ts`, `src/server/mocks/riesgo.ts` | Andrés |
| `src/app/**` (páginas, layouts y estilos), `src/components/**`, `public/**` | Hania |
| `README.md` | Andrés |
| `docs/CONTRATO.md` | André es el custodio; los cambios se hacen solo con acuerdo de los tres |

André crea en la fase 0 **todos** los archivos de `src/server/acciones/*` y `src/server/mocks/*`, incluidos los de Andrés, con implementaciones mock. Desde ese momento cada archivo pasa a su dueño.

## A5. Esquema base (`db/02_esquema.sql`, lo escribe André en la fase 0)

André debe implementarlo tal cual. Además debe crear un índice por cada FK que no tenga uno, porque PostgreSQL no los crea solo.

```sql
CREATE SEQUENCE seq_codigo_jugador;

CREATE TABLE usuarios (
  id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  usuario      text NOT NULL UNIQUE CHECK (usuario ~ '^[a-z0-9_.]{3,30}$'),
  salt         text NOT NULL,
  verificador  text NOT NULL,                 -- verificador SRP-6a (x = SHA-256(salt | SHA-256(usuario ":" clave)))
  rol          text NOT NULL CHECK (rol IN ('administrador','crupier','supervisor','jugador')),
  activo       boolean NOT NULL DEFAULT true,
  creado_en    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE desafios_login (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id  bigint REFERENCES usuarios(id),  -- NULL = usuario inexistente (respuesta señuelo)
  a_publico   text NOT NULL,
  b_publico   text NOT NULL,
  b_secreto   text NOT NULL,
  creado_en   timestamptz NOT NULL DEFAULT now(),
  expira_en   timestamptz NOT NULL,
  usado_en    timestamptz,
  exitoso     boolean
);

CREATE TABLE sesiones (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  usuario_id  bigint NOT NULL REFERENCES usuarios(id),
  token_hash  text NOT NULL UNIQUE,            -- SHA-256 del token de la cookie
  canal       text NOT NULL,                   -- para la firma del formulario seguro
  creada_en   timestamptz NOT NULL DEFAULT now(),
  expira_en   timestamptz NOT NULL,
  cerrada_en  timestamptz,
  CHECK (expira_en > creada_en)
);

CREATE TABLE juegos (
  id                  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  nombre              text NOT NULL UNIQUE,
  registro_detallado  boolean NOT NULL
);

CREATE TABLE opciones_apuesta (
  id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  juego_id     bigint NOT NULL REFERENCES juegos(id),
  nombre       text NOT NULL,
  factor_pago  numeric(8,2) NOT NULL CHECK (factor_pago > 0),
  activa       boolean NOT NULL DEFAULT true,
  UNIQUE (juego_id, nombre)
);

CREATE TABLE empleados (
  id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  usuario_id       bigint NOT NULL UNIQUE REFERENCES usuarios(id),
  documento        text NOT NULL UNIQUE,
  nombre           text NOT NULL,
  cargo            text NOT NULL CHECK (cargo IN ('administrador','crupier','supervisor')),
  salario_mensual  numeric(14,2) NOT NULL CHECK (salario_mensual > 0),
  activo           boolean NOT NULL DEFAULT true
);

CREATE TABLE competencias (
  empleado_id  bigint NOT NULL REFERENCES empleados(id),
  juego_id     bigint NOT NULL REFERENCES juegos(id),
  PRIMARY KEY (empleado_id, juego_id)
);

CREATE TABLE mesas (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  codigo        text NOT NULL UNIQUE,
  juego_id      bigint NOT NULL REFERENCES juegos(id),
  monto_minimo  numeric(14,2) NOT NULL,
  monto_maximo  numeric(14,2) NOT NULL,
  activa        boolean NOT NULL DEFAULT true,
  CHECK (monto_minimo > 0 AND monto_maximo >= monto_minimo)
);

CREATE TABLE jornadas (
  id     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  fecha  date NOT NULL UNIQUE
);

CREATE TABLE turnos (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  jornada_id  bigint NOT NULL REFERENCES jornadas(id),
  numero      int NOT NULL CHECK (numero > 0),
  inicio      timestamptz NOT NULL,
  fin         timestamptz NOT NULL,
  UNIQUE (jornada_id, numero),
  CHECK (fin > inicio AND fin - inicio <= interval '2 hours')
);

CREATE TABLE asignaciones (
  id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  turno_id       bigint NOT NULL REFERENCES turnos(id),
  jornada_id     bigint NOT NULL REFERENCES jornadas(id),   -- copia de turnos.jornada_id; la llena un trigger de Andrés
  mesa_id        bigint NOT NULL REFERENCES mesas(id),
  crupier_id     bigint NOT NULL REFERENCES empleados(id),
  supervisor_id  bigint NOT NULL REFERENCES empleados(id),
  CHECK (crupier_id <> supervisor_id),
  UNIQUE (turno_id, mesa_id),               -- una mesa, un crupier por turno
  UNIQUE (turno_id, crupier_id),            -- un crupier, una mesa por turno
  UNIQUE (jornada_id, crupier_id, mesa_id)  -- rotación: no repite mesa en la jornada
);

CREATE TABLE conceptos (
  id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  asignacion_id  bigint NOT NULL UNIQUE REFERENCES asignaciones(id),
  concepto       text NOT NULL CHECK (concepto IN ('Genera ganancias','Genera pérdidas','Sospecha de fraude','Comportamiento neutro')),
  observacion    text,
  emitido_en     timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE jugadores (
  id                bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  usuario_id        bigint NOT NULL UNIQUE REFERENCES usuarios(id),
  codigo            text NOT NULL UNIQUE DEFAULT ('J-' || lpad(nextval('casino.seq_codigo_jugador')::text, 6, '0')),
  documento         text NOT NULL UNIQUE,
  nombre            text NOT NULL,
  fecha_nacimiento  date NOT NULL,
  saldo             numeric(14,2) NOT NULL DEFAULT 0 CHECK (saldo >= 0),
  empleado_id       bigint UNIQUE REFERENCES empleados(id),
  activo            boolean NOT NULL DEFAULT true,
  creado_en         timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE rondas (
  id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  mesa_id        bigint NOT NULL REFERENCES mesas(id),
  asignacion_id  bigint NOT NULL REFERENCES asignaciones(id),
  numero         int NOT NULL,                 -- correlativo por mesa; lo asigna un trigger de André
  inicio         timestamptz NOT NULL DEFAULT now(),
  cierre         timestamptz,
  estado         text NOT NULL DEFAULT 'abierta' CHECK (estado IN ('abierta','cerrada','anulada')),
  UNIQUE (mesa_id, numero),
  CHECK (cierre IS NULL OR cierre > inicio),
  CHECK ((estado = 'abierta') = (cierre IS NULL))
);
CREATE UNIQUE INDEX ux_rondas_una_abierta_por_mesa ON rondas (mesa_id) WHERE estado = 'abierta';

CREATE TABLE resultados_ronda (
  ronda_id   bigint NOT NULL REFERENCES rondas(id),
  opcion_id  bigint NOT NULL REFERENCES opciones_apuesta(id),
  PRIMARY KEY (ronda_id, opcion_id)
);

CREATE TABLE apuestas (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  ronda_id        bigint NOT NULL REFERENCES rondas(id),
  jugador_id      bigint NOT NULL REFERENCES jugadores(id),
  opcion_id       bigint NOT NULL REFERENCES opciones_apuesta(id),
  monto           numeric(14,2) NOT NULL CHECK (monto > 0),
  factor_pago     numeric(8,2) NOT NULL CHECK (factor_pago > 0),   -- copiado de la opción al apostar
  estado          text NOT NULL DEFAULT 'pendiente' CHECK (estado IN ('pendiente','ganada','perdida','anulada')),
  premio          numeric(14,2),
  creada_en       timestamptz NOT NULL DEFAULT now(),
  liquidada_en    timestamptz,
  registrada_por  bigint NOT NULL REFERENCES usuarios(id),
  CHECK ((estado = 'ganada') = (premio IS NOT NULL)),
  CHECK ((estado IN ('ganada','perdida')) = (liquidada_en IS NOT NULL))
);
CREATE INDEX ix_apuestas_pendientes ON apuestas (ronda_id) WHERE estado = 'pendiente';
CREATE INDEX ix_apuestas_jugador_liquidacion ON apuestas (jugador_id, liquidada_en);

CREATE TABLE movimientos_saldo (
  id                bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  jugador_id        bigint NOT NULL REFERENCES jugadores(id),
  tipo              text NOT NULL CHECK (tipo IN ('consignacion','retiro','apuesta','devolucion','premio')),
  monto             numeric(14,2) NOT NULL CHECK (monto > 0),
  saldo_resultante  numeric(14,2) NOT NULL CHECK (saldo_resultante >= 0),
  apuesta_id        bigint REFERENCES apuestas(id),
  creado_en         timestamptz NOT NULL DEFAULT now(),
  creado_por        bigint REFERENCES usuarios(id),
  CHECK ((tipo IN ('apuesta','devolucion','premio')) = (apuesta_id IS NOT NULL))
);
CREATE INDEX ix_movimientos_jugador_fecha ON movimientos_saldo (jugador_id, creado_en);

CREATE TABLE configuracion (
  clave  text PRIMARY KEY,                     -- 'umbral_perdida_diaria'
  valor  numeric(14,2) NOT NULL CHECK (valor > 0)
);

CREATE TABLE suspensiones (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  jugador_id    bigint NOT NULL REFERENCES jugadores(id),
  motivo        text NOT NULL CHECK (motivo IN ('perdida_diaria','pausa_voluntaria','deuda_empleado')),
  inicio        timestamptz NOT NULL DEFAULT now(),
  fin           timestamptz,                   -- inicio + 24 h; NULL solo en deuda_empleado
  levantada_en  timestamptz,                   -- deuda_empleado: cuando la deuda baja del límite
  CHECK ((motivo = 'deuda_empleado') = (fin IS NULL)),
  CHECK (fin IS NULL OR fin > inicio)
);
CREATE UNIQUE INDEX ux_suspension_deuda_activa ON suspensiones (jugador_id)
  WHERE motivo = 'deuda_empleado' AND levantada_en IS NULL;

CREATE TABLE investigaciones (
  id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  jugador_id   bigint NOT NULL REFERENCES jugadores(id),
  abierta_en   timestamptz NOT NULL DEFAULT now(),
  cerrada_en   timestamptz,
  resolucion   text,
  cerrada_por  bigint REFERENCES usuarios(id),
  CHECK ((cerrada_en IS NULL) = (resolucion IS NULL))
);
CREATE UNIQUE INDEX ux_investigacion_abierta ON investigaciones (jugador_id) WHERE cerrada_en IS NULL;

CREATE TABLE abonos_empleado (
  id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  empleado_id  bigint NOT NULL REFERENCES empleados(id),
  monto        numeric(14,2) NOT NULL CHECK (monto > 0),
  creado_en    timestamptz NOT NULL DEFAULT now(),
  creado_por   bigint REFERENCES usuarios(id)
);

CREATE TABLE auditoria (                       -- sin FK a propósito: es una bitácora
  id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tabla        text NOT NULL,
  operacion    text NOT NULL,
  registro_id  bigint,
  usuario_id   bigint,
  datos        jsonb,
  fecha        timestamptz NOT NULL DEFAULT now()
);
```

Los cambios a este esquema se hacen así: quien necesite el cambio se lo pide a André, que lo aplica. Si el cambio afecta los tipos de `src/lib/contrato.ts`, se avisa también a Hania.

## A6. Funciones SQL compartidas

| Función | Dueño | Estado en la fase 0 | Comportamiento |
|---|---|---|---|
| `fn_actor() RETURNS bigint` | André | Real | Lee `current_setting('app.usuario_id', true)`. Si no hay actor, lanza `CA001`. |
| `fn_exigir_rol(VARIADIC p_roles text[]) RETURNS void` | André | Real | El usuario actor debe estar activo y tener uno de esos roles. Si no, lanza `CA002`. |
| `fn_crear_usuario(p_usuario, p_salt, p_verificador, p_rol) RETURNS bigint` | André | Real | Interna. Si el usuario ya existe, lanza `CA003`. |
| `fn_mover_saldo(p_jugador_id bigint, p_tipo text, p_monto numeric, p_apuesta_id bigint DEFAULT NULL) RETURNS numeric` | André | Real | Interna. Bloquea al jugador con `FOR UPDATE`, suma o resta según el tipo, inserta el movimiento con `saldo_resultante` y devuelve el saldo nuevo. Si el saldo no alcanza, lanza `CA010`. |
| `fn_crupier_asignado(p_mesa_id bigint, p_momento timestamptz) RETURNS TABLE (asignacion_id bigint, crupier_id bigint, supervisor_id bigint)` | Andrés | Stub funcional | Devuelve la asignación de esa mesa en el turno que contiene ese momento, o 0 filas. El stub hace esa consulta directa. |
| `fn_puede_apostar(p_jugador_id bigint) RETURNS void` | Andrés | Stub vacío | Lanza `CA301` (inactivo), `CA302` (suspendido hasta X) o `CA303` (en investigación). |
| `fn_evaluar_riesgo(p_jugador_id bigint) RETURNS void` | Andrés | Stub vacío | Aplica las decisiones A2.7, A2.9 y A2.10. Se llama después de cada liquidación y de cada abono. |

Los tipos de movimiento suman o restan así: `consignacion`, `devolucion` y `premio` suman; `retiro` y `apuesta` restan.

Las funciones internas (`fn_crear_usuario`, `fn_mover_saldo`, `fn_crupier_asignado`, `fn_puede_apostar` y `fn_evaluar_riesgo`) **no** tienen `EXECUTE` para `casino_app`. Solo las llaman otras funciones `SECURITY DEFINER`.

## A7. Contrato TypeScript

Todas las funciones de `src/server/acciones/*.ts` llevan `'use server'` y devuelven `Resultado<T>`. Las de escritura reciben `seguro: CamposSeguros` como último parámetro. Las acciones **no** revalidan rutas: después de una escritura exitosa, el frontend llama `router.refresh()`.

Con `MODO_MOCK=1` en `.env.local`, cada acción devuelve datos de `src/server/mocks/<modulo>.ts`, y la sesión se simula con el rol de `MOCK_ROL` (`administrador`, `crupier`, `supervisor` o `jugador`). Así Hania trabaja sin base de datos y sin depender de nadie.

```ts
// ===== src/lib/contrato.ts (tipos; lo crea André en la fase 0) =====
export type Rol = 'administrador' | 'crupier' | 'supervisor' | 'jugador';
export type Dinero = string;          // numeric de PostgreSQL como string; nunca float
export type FechaISO = string;
export type Resultado<T> = { ok: true; datos: T } | { ok: false; error: { codigo: string; mensaje: string } };
export type CamposSeguros = { fechahora: string; firma: string };   // firma = SHA-256(canal + fechahora)
export type Sesion = { usuarioId: number; usuario: string; nombre: string; rol: Rol };
export type Credenciales = { usuario: string; salt: string; verificador: string };

export type Juego = { id: number; nombre: string; registroDetallado: boolean };
export type Cargo = 'administrador' | 'crupier' | 'supervisor';
export type Empleado = { id: number; usuario: string; nombre: string; documento: string; cargo: Cargo;
  salarioMensual: Dinero; activo: boolean; competencias: { juegoId: number; juego: string }[] };
export type Mesa = { id: number; codigo: string; juegoId: number; juego: string; registroDetallado: boolean;
  montoMinimo: Dinero; montoMaximo: Dinero; activa: boolean };
export type Jornada = { id: number; fecha: string };
export type Turno = { id: number; jornadaId: number; numero: number; inicio: FechaISO; fin: FechaISO };
export type Concepto = 'Genera ganancias' | 'Genera pérdidas' | 'Sospecha de fraude' | 'Comportamiento neutro';
export type Asignacion = { id: number; turnoId: number; turnoNumero: number; inicio: FechaISO; fin: FechaISO;
  mesaId: number; mesaCodigo: string; juego: string; crupierId: number; crupierNombre: string;
  supervisorId: number; supervisorNombre: string; concepto: Concepto | null; observacion: string | null };

export type EstadoJugador = 'Activo' | 'Suspendido' | 'Investigación' | 'Inactivo';
export type Jugador = { id: number; codigo: string; nombre: string; documento: string; fechaNacimiento: string;
  saldo: Dinero; estado: EstadoJugador; suspendidoHasta: FechaISO | null; esEmpleado: boolean; activo: boolean };
export type Movimiento = { id: number; tipo: 'consignacion' | 'retiro' | 'apuesta' | 'devolucion' | 'premio';
  monto: Dinero; saldoResultante: Dinero; fecha: FechaISO; apuestaId: number | null };
export type Suspension = { id: number; jugadorId: number; jugadorCodigo: string; jugadorNombre: string;
  motivo: 'perdida_diaria' | 'pausa_voluntaria' | 'deuda_empleado'; inicio: FechaISO; fin: FechaISO | null;
  levantadaEn: FechaISO | null; activa: boolean };
export type Investigacion = { id: number; jugadorId: number; jugadorCodigo: string; jugadorNombre: string;
  abiertaEn: FechaISO; cerradaEn: FechaISO | null; resolucion: string | null };

export type OpcionApuesta = { id: number; juegoId: number; nombre: string; factorPago: string; activa: boolean };
export type EstadoRonda = 'abierta' | 'cerrada' | 'anulada';
export type Ronda = { id: number; mesaId: number; numero: number; inicio: FechaISO; cierre: FechaISO | null;
  estado: EstadoRonda; resultado: { opcionId: number; nombre: string }[] };
export type EstadoApuesta = 'pendiente' | 'ganada' | 'perdida' | 'anulada';
export type Apuesta = { id: number; rondaId: number; mesaCodigo: string; rondaNumero: number; jugadorId: number;
  jugadorCodigo: string; jugadorNombre: string; opcionId: number; opcion: string; monto: Dinero;
  factorPago: string; estado: EstadoApuesta; premio: Dinero | null; creadaEn: FechaISO; liquidadaEn: FechaISO | null };
export type Historial = { jugador: Jugador; apuestas: Apuesta[]; movimientos: Movimiento[];
  suspensiones: Suspension[]; investigaciones: Investigacion[]; deudaEmpleado: Dinero | null };
export type MesaCrupier = { asignacionId: number; mesa: Mesa; inicioTurno: FechaISO; finTurno: FechaISO;
  rondaAbierta: Ronda | null };
export type ResumenLiquidacion = { ganadas: number; perdidas: number; totalApostado: Dinero;
  totalPremios: Dinero; resultadoCasino: Dinero };
export type JugadorParaApuesta = { jugadorId: number; codigo: string; nombre: string; saldo: Dinero;
  puedeApostar: boolean; motivo: string | null };
export type FilaReporte = { fecha: string; turnoNumero: number; mesaCodigo: string; crupier: string;
  supervisor: string; totalApostado: Dinero; totalPremios: Dinero; resultadoNominal: Dinero; concepto: Concepto | null };
```

**Funciones de André.**

```ts
// src/lib/srp-cliente.ts (navegador; la clave nunca sale de aquí)
derivarCredenciales(usuario: string, clave: string): Promise<Credenciales>
iniciarSesion(usuario: string, clave: string): Promise<Resultado<{ rol: Rol }>>   // hace los 2 pasos SRP y verifica M2

// src/server/auth/sesion.ts (solo servidor)
obtenerSesion(): Promise<Sesion | null>
exigirSesion(...roles: Rol[]): Promise<Sesion>      // sin sesión → redirect('/login'); rol no permitido → redirect('/prohibido')

// src/server/acciones/auth.ts
loginPaso1(usuario: string, A: string): Promise<Resultado<{ idDesafio: string; salt: string; B: string }>>
loginPaso2(idDesafio: string, M1: string): Promise<Resultado<{ M2: string; rol: Rol }>>
cerrarSesion(): Promise<void>
obtenerCamposSeguros(): Promise<CamposSeguros>
registrarJugador(datos: { documento: string; nombre: string; fechaNacimiento: string }, cred: Credenciales, seguro: CamposSeguros): Promise<Resultado<{ jugadorId: number; codigo: string }>>

// src/server/acciones/rondas.ts
misMesasActuales(): Promise<Resultado<MesaCrupier[]>>                                   // crupier
listarRondas(mesaId: number): Promise<Resultado<Ronda[]>>                               // crupier, supervisor, administrador
obtenerRonda(rondaId: number): Promise<Resultado<Ronda>>
abrirRonda(mesaId: number, seguro: CamposSeguros): Promise<Resultado<Ronda>>             // crupier
cerrarRonda(rondaId: number, opcionesGanadoras: number[], seguro: CamposSeguros): Promise<Resultado<ResumenLiquidacion>>
anularRonda(rondaId: number, seguro: CamposSeguros): Promise<Resultado<null>>
reporteMesaTurno(jornadaId: number): Promise<Resultado<FilaReporte[]>>                  // administrador

// src/server/acciones/apuestas.ts
listarOpciones(juegoId: number): Promise<Resultado<OpcionApuesta[]>>
crearOpcion(juegoId: number, datos: { nombre: string; factorPago: string }, seguro: CamposSeguros): Promise<Resultado<OpcionApuesta>>    // administrador
actualizarOpcion(id: number, datos: { nombre: string; factorPago: string }, seguro: CamposSeguros): Promise<Resultado<OpcionApuesta>>
desactivarOpcion(id: number, seguro: CamposSeguros): Promise<Resultado<null>>
buscarJugadorParaApuesta(codigo: string): Promise<Resultado<JugadorParaApuesta>>       // crupier
listarApuestas(rondaId: number): Promise<Resultado<Apuesta[]>>
registrarApuesta(datos: { rondaId: number; jugadorId: number; opcionId: number; monto: Dinero }, seguro: CamposSeguros): Promise<Resultado<Apuesta>>
registrarApuestaResuelta(datos: { rondaId: number; jugadorId: number; opcionId: number; monto: Dinero; ganada: boolean }, seguro: CamposSeguros): Promise<Resultado<Apuesta>>   // póker
anularApuesta(apuestaId: number, seguro: CamposSeguros): Promise<Resultado<null>>
```

**Funciones de Andrés.**

```ts
// src/server/acciones/personal.ts (administrador, salvo que se indique otra cosa)
listarJuegos(): Promise<Resultado<Juego[]>>                                             // cualquier rol autenticado
listarEmpleados(): Promise<Resultado<Empleado[]>>
crearEmpleado(datos: { nombre: string; documento: string; cargo: Cargo; salarioMensual: Dinero }, cred: Credenciales, seguro: CamposSeguros): Promise<Resultado<Empleado>>
actualizarEmpleado(id: number, datos: { nombre: string; documento: string; cargo: Cargo; salarioMensual: Dinero }, seguro: CamposSeguros): Promise<Resultado<Empleado>>
desactivarEmpleado(id: number, seguro: CamposSeguros): Promise<Resultado<null>>
asignarCompetencia(empleadoId: number, juegoId: number, seguro: CamposSeguros): Promise<Resultado<null>>
quitarCompetencia(empleadoId: number, juegoId: number, seguro: CamposSeguros): Promise<Resultado<null>>

// src/server/acciones/mesas.ts
listarMesas(): Promise<Resultado<Mesa[]>>                                               // administrador, crupier, supervisor
crearMesa(datos: { codigo: string; juegoId: number; montoMinimo: Dinero; montoMaximo: Dinero }, seguro: CamposSeguros): Promise<Resultado<Mesa>>
actualizarMesa(id: number, datos: { codigo: string; juegoId: number; montoMinimo: Dinero; montoMaximo: Dinero }, seguro: CamposSeguros): Promise<Resultado<Mesa>>
desactivarMesa(id: number, seguro: CamposSeguros): Promise<Resultado<null>>
listarJornadas(): Promise<Resultado<Jornada[]>>
crearJornada(fecha: string, seguro: CamposSeguros): Promise<Resultado<Jornada>>
listarTurnos(jornadaId: number): Promise<Resultado<Turno[]>>
crearTurno(jornadaId: number, datos: { inicio: FechaISO; fin: FechaISO }, seguro: CamposSeguros): Promise<Resultado<Turno>>
eliminarTurno(id: number, seguro: CamposSeguros): Promise<Resultado<null>>
listarAsignaciones(jornadaId: number): Promise<Resultado<Asignacion[]>>
crearAsignacion(datos: { turnoId: number; mesaId: number; crupierId: number; supervisorId: number }, seguro: CamposSeguros): Promise<Resultado<Asignacion>>
eliminarAsignacion(id: number, seguro: CamposSeguros): Promise<Resultado<null>>
misTurnosSupervisor(): Promise<Resultado<Asignacion[]>>                                 // supervisor
emitirConcepto(asignacionId: number, concepto: Concepto, observacion: string | null, seguro: CamposSeguros): Promise<Resultado<Asignacion>>   // supervisor

// src/server/acciones/riesgo.ts
listarJugadores(filtro?: string): Promise<Resultado<Jugador[]>>                         // administrador
obtenerHistorial(jugadorId: number): Promise<Resultado<Historial>>                      // administrador
miHistorial(): Promise<Resultado<Historial>>                                            // jugador
actualizarJugador(id: number, datos: { nombre: string; documento: string }, seguro: CamposSeguros): Promise<Resultado<Jugador>>
desactivarJugador(id: number, seguro: CamposSeguros): Promise<Resultado<null>>
solicitarPausa(seguro: CamposSeguros): Promise<Resultado<Suspension>>                    // jugador
listarSuspensiones(soloActivas: boolean): Promise<Resultado<Suspension[]>>
listarInvestigaciones(soloAbiertas: boolean): Promise<Resultado<Investigacion[]>>
cerrarInvestigacion(id: number, resolucion: string, seguro: CamposSeguros): Promise<Resultado<null>>
registrarAbono(empleadoId: number, monto: Dinero, seguro: CamposSeguros): Promise<Resultado<{ deudaRestante: Dinero }>>
obtenerUmbral(): Promise<Resultado<{ umbralPerdidaDiaria: Dinero }>>
actualizarUmbral(monto: Dinero, seguro: CamposSeguros): Promise<Resultado<null>>
// Opcionales (consignaciones/retiros). Se declaran desde la fase 0; si no se implementan, devuelven error CA399 "No disponible".
registrarConsignacion(jugadorId: number, monto: Dinero, seguro: CamposSeguros): Promise<Resultado<Movimiento>>
registrarRetiro(jugadorId: number, monto: Dinero, seguro: CamposSeguros): Promise<Resultado<Movimiento>>
```

## A8. Usuarios y datos de prueba

- Todos los usuarios de prueba tienen la clave **`Casino2026*`**.
- Sus verificadores SRP los genera `scripts/generar-usuarios-semilla.ts` (André), porque SRP no se puede calcular en SQL.
- Usuarios:
  - `admin` (administrador)
  - `crupier1`, `crupier2`, `crupier3`, `crupier4` (crupier)
  - `supervisor1`, `supervisor2` (supervisor)
  - `jugador1`, `jugador2`, `jugador3` (jugador)
  - `crupier1.juega` (jugador; cuenta de juego del empleado `crupier1`)
  - `supervisor1.juega` (jugador; cuenta de juego del empleado `supervisor1`)
- Orden y dueño de las semillas:
  - `90_semilla_base.sql` (André): usuarios, juegos (Ruleta y Blackjack con registro detallado, Póker sin registro detallado) y sus opciones de apuesta con factores.
  - `91_semilla_personal_mesas.sql` (Andrés): empleados con salario, competencias, mesas, la jornada de hoy con un turno ya terminado, el turno actual y el siguiente, asignaciones que cumplen la rotación, y el umbral de pérdida diaria.
  - `92_semilla_jugadores.sql` (Andrés): fichas de jugador, saldo inicial mediante `fn_mover_saldo('consignacion')`, y escenarios cerca de cada límite.
  - `93_semilla_juego.sql` (André): rondas y apuestas generadas **con las funciones reales**, para que el historial y los reportes tengan datos.
- Como los turnos duran máximo 2 horas, `db/demo/turno_actual.sql` (Andrés) crea un turno vigente con sus asignaciones. Se usa antes de cualquier demo.

## A9. Comunicación entre integrantes (regla estricta)

- No reportes avances ni pidas revisiones. Cada uno trabaja de forma independiente.
- Solo se comunica a otra persona cuando **se necesita trabajo de ella**:
  - algo del contrato que no existe o no funciona como dice el contrato,
  - un cambio en el esquema o en el contrato,
  - un dato que solo ella tiene.
- **Única excepción:** André avisa una sola vez a Andrés y a Hania cuando la fase 0 está en `main`, porque ambos dependen de ella para arrancar.
- El agente no se comunica directamente: le redacta el mensaje a su humano y sigue con otra tarea que no dependa de eso, usando el mock o el stub mientras tanto. Formato del mensaje:

```
Para: <André | Andrés | Hania>
Necesito: <función, archivo o cambio exacto, con su firma>
Para qué: <una línea>
Mientras tanto: <qué hago para no quedar bloqueado>
```

- Un cambio que afecte `src/lib/contrato.ts` o `02_esquema.sql` requiere el acuerdo de los tres, y lo aplica André.

## A10. Documento técnico, evidencias y exposición

| Pieza | Responsable |
|---|---|
| Documento: descripción del framework | André |
| Documento: arquitectura (App Router, Server Components para leer, Server Actions para escribir, BD dueña de las reglas, capas de autorización) | André |
| Documento: autenticación Zero Knowledge con SRP-6a y SHA-256 | André |
| Documento: modelo de datos (diagrama entidad-relación y justificación de constraints y triggers) | Andrés |
| Documento: instrucciones de instalación (`README.md`) | Andrés |
| Documento: datos de prueba (usuarios y escenarios) | Andrés |
| Documento: funcionalidades implementadas | Cada uno lo suyo; Hania integra las capturas |
| Documento: dificultades encontradas | Cada uno lo suyo |
| Evidencia: capturas por rol, incluidos los casos rechazados | Hania |
| Exposición: introducción al framework | André |
| Exposición: demostración | Hania la conduce; cada uno explica su parte |
| Exposición: explicación técnica | André (autenticación y arquitectura), Andrés (base de datos) |
| Exposición: análisis crítico | André (backend y seguridad), Andrés (BD con Next.js), Hania (frontend) |
| Exposición: conclusiones | Los tres |

Cada uno escribe sus secciones en `docs/documento/<seccion>.md`. Al final se integran en un solo documento.

## A11. Cronograma

| Día | Qué se hace |
|---|---|
| Jueves 29 oct | Fase 0 (André). Andrés y Hania leen el contrato y empiezan con mocks y stubs. |
| Viernes 30 – domingo 1 nov | Desarrollo en paralelo. |
| Lunes 2 nov | Integración en `main`, `run_all.sh --tests` completo, recorrido de punta a punta con los 4 roles y capturas. |
| Martes 3 nov | Documento técnico, README y entrega. |
