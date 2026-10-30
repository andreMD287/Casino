-- 02_esquema.sql (André) — esquema base del contrato A5, tal cual, más índices para las FK.
SET ROLE casino_owner;
SET search_path = casino, public;

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

-- ---------------------------------------------------------------------------
-- Índices para las FK que no quedan cubiertas por una PK, UNIQUE o índice
-- cuya primera columna sea la FK (PostgreSQL no los crea solo).
-- ---------------------------------------------------------------------------
CREATE INDEX ix_desafios_login_usuario       ON desafios_login (usuario_id, creado_en);
CREATE INDEX ix_sesiones_usuario             ON sesiones (usuario_id);
CREATE INDEX ix_competencias_juego           ON competencias (juego_id);
CREATE INDEX ix_mesas_juego                  ON mesas (juego_id);
CREATE INDEX ix_asignaciones_mesa            ON asignaciones (mesa_id);
CREATE INDEX ix_asignaciones_crupier         ON asignaciones (crupier_id);
CREATE INDEX ix_asignaciones_supervisor      ON asignaciones (supervisor_id);
CREATE INDEX ix_rondas_asignacion            ON rondas (asignacion_id);
CREATE INDEX ix_resultados_ronda_opcion      ON resultados_ronda (opcion_id);
CREATE INDEX ix_apuestas_ronda               ON apuestas (ronda_id);
CREATE INDEX ix_apuestas_opcion              ON apuestas (opcion_id);
CREATE INDEX ix_apuestas_registrada_por      ON apuestas (registrada_por);
CREATE INDEX ix_movimientos_apuesta          ON movimientos_saldo (apuesta_id);
CREATE INDEX ix_movimientos_creado_por       ON movimientos_saldo (creado_por);
CREATE INDEX ix_suspensiones_jugador         ON suspensiones (jugador_id);
CREATE INDEX ix_investigaciones_jugador      ON investigaciones (jugador_id);
CREATE INDEX ix_investigaciones_cerrada_por  ON investigaciones (cerrada_por);
CREATE INDEX ix_abonos_empleado_empleado     ON abonos_empleado (empleado_id);
CREATE INDEX ix_abonos_empleado_creado_por   ON abonos_empleado (creado_por);
