# Casino — Bases de Datos, Administración y Aplicaciones

Proyecto de la Pontificia Universidad Javeriana para gestionar la operación de un casino: usuarios y roles, empleados, mesas, jornadas, turnos, rondas, apuestas, movimientos en fichas, suspensiones e investigaciones.

**Tecnologías:** Next.js 16.4.3 con App Router y Server Actions, React 19, TypeScript, PostgreSQL 16, SQL/PLpgSQL, `pg` y Tailwind CSS. El acceso a datos no usa ORM. Las tablas, restricciones y funciones viven en el esquema `casino`.

**Integrantes:** André Landinez (infraestructura, autenticación, rondas y apuestas), Andrés Barrios (personal, mesas, turnos, riesgo e historial) y Valentina Carreño / Hania (interfaz web por rol).

El contrato común está en [`docs/CONTRATO.md`](docs/CONTRATO.md). El modelo de datos y la explicación de las funcionalidades se encuentran en [`docs/documento/`](docs/documento/).

## 1. Requisitos

- Node.js 20.9 o superior y npm.
- Docker Desktop con soporte de contenedores Linux **o** PostgreSQL 16 instalado localmente.
- PowerShell en Windows para el procedimiento con Docker; alternativamente `bash` y `psql` para la instalación directa.
- Puertos disponibles: `3000` para Next.js y `55433` para PostgreSQL en los ejemplos con Docker.

Las instrucciones de Docker se refieren a un **entorno local de demostración**. No se deben reutilizar contraseñas, puertos o configuraciones de este ejemplo en un servidor de producción.

## 2. Descargar las dependencias

```powershell
# En la carpeta raíz del repositorio
npm ci
npm run lint
npm run build
```

El comando `npm ci` instala las dependencias según `package-lock.json`. Compilar Next.js verifica TypeScript, pero **no demuestra por sí solo que las funciones SQL y la interfaz sean operativas**.

## 3. PostgreSQL 16 con Docker Desktop (Windows)

Este procedimiento crea un contenedor aislado llamado `casino-postgres`, en el puerto `55433` del computador; el puerto `5432` permanece dentro del contenedor.

```powershell
# Primero, confirmar que no existe un contenedor con ese nombre
# y que el puerto 55433 está disponible.
docker ps -a --filter "name=casino-postgres"

$clavePg = Read-Host "Contraseña local para el usuario postgres"
docker run -d `
  --name casino-postgres `
  --env "POSTGRES_PASSWORD=$clavePg" `
  --publish 55433:5432 `
  --mount "type=volume,source=casino-pgdata,target=/var/lib/postgresql/data" `
  postgres:16

docker exec casino-postgres pg_isready -U postgres
```

Si el contenedor ya existe, **no vuelvas a ejecutar `docker run` con el mismo nombre**. Comprueba `docker ps -a` y utiliza `docker start casino-postgres` si aparece detenido.

### Configuración de `.env.local`

Crear una copia de `.env.example` llamada `.env.local` y configurar valores **locales**:

```dotenv
DATABASE_URL=postgresql://casino_app:CLAVE_APP@127.0.0.1:55433/casino
CASINO_APP_PASSWORD=CLAVE_APP
SECRETO_SERVIDOR=SECRETO_ALEATORIO_DE_32_BYTES_O_MAS
MODO_MOCK=0
MOCK_ROL=administrador
```

`CLAVE_APP` es una contraseña creada para el rol `casino_app`; debe ser igual en `DATABASE_URL` y `CASINO_APP_PASSWORD`. `SECRETO_SERVIDOR` debe generarse de forma aleatoria, por ejemplo con `node -e "process.stdout.write(require('crypto').randomBytes(32).toString('hex'))"`. No subas `.env.local` a GitHub ni compartas su contenido.

### Cargar esquema, funciones y semillas

El contenedor trae `psql` y `bash`. Desde la raíz del repositorio, en PowerShell:

```powershell
docker exec casino-postgres mkdir -p /tmp/casino-db
docker cp .\db\. casino-postgres:/tmp/casino-db/

# Recuperar la clave de casino_app sin mostrarla en pantalla.
$claveApp = ((Get-Content '.env.local' |
  Where-Object { $_ -match '^CASINO_APP_PASSWORD=' } |
  Select-Object -First 1) -replace '^CASINO_APP_PASSWORD=', '').Trim()

if (-not $claveApp) { throw 'Falta CASINO_APP_PASSWORD en .env.local' }

docker exec `
  -e "CASINO_APP_PASSWORD=$claveApp" `
  -e "PGHOST=/var/run/postgresql" `
  -e "PGPORT=5432" `
  -e "PGUSER=postgres" `
  casino-postgres `
  bash /tmp/casino-db/run_all.sh
```

**Advertencia importante:** `run_all.sh` ejecuta `DROP DATABASE IF EXISTS casino WITH (FORCE)` y vuelve a crear la base `casino` en el servidor indicado. Úsalo únicamente en el contenedor de prueba preparado para este proyecto; **destruye los datos previos de esa base**. No lo dirijas a bases de otros trabajos ni a un servidor de producción.

Si los archivos se modifican después de `docker cp`, hay que copiarlos otra vez antes de reconstruir.

## 4. Datos de prueba

La ejecución integrada del **2 de noviembre de 2026** produjo:

| Entidad | Filas |
|---|---:|
| Empleados | 7 |
| Mesas | 3 |
| Jugadores | 5 |
| Rondas | 10 |
| Apuestas | 62 |

Las mesas precargadas son `RUL-01` (Ruleta), `BJ-01` (Blackjack) y `POK-01` (Póker). Se programan turnos con horarios relativos a la inicialización y un histórico para escenarios de riesgo. Las credenciales de demostración se encuentran en el contrato compartido y en `docs/documento/datos-prueba.md`.

Puedes comprobar los datos con:

```powershell
docker exec casino-postgres psql -X -U postgres -d casino `
  -c "SELECT (SELECT count(*) FROM casino.empleados) AS empleados,
             (SELECT count(*) FROM casino.mesas) AS mesas,
             (SELECT count(*) FROM casino.jugadores) AS jugadores,
             (SELECT count(*) FROM casino.rondas) AS rondas,
             (SELECT count(*) FROM casino.apuestas) AS apuestas;"
```

## 5. Ejecutar Next.js

```powershell
npm run dev
```

Abrir `http://localhost:3000`. `MODO_MOCK=1` permite desarrollar la interfaz con datos de ejemplo; `MODO_MOCK=0` requiere PostgreSQL, permisos y sesiones reales.

**Estado de integración:** `andres/backend`, tras el merge de `origin/main`, compiló y pasó la batería SQL de 109 comprobaciones. El build todavía enumera únicamente `/` y `/_not-found`, por lo que **no hay evidencia de que la interfaz de Hania esté integrada en esta rama**. Antes de la demostración se deben probar los cuatro roles con `MODO_MOCK=0`.

## 6. Pruebas SQL

Para ejecutar todos los archivos de `db/tests/` con una reconstrucción limpia de la base:

```powershell
# Copiar los cambios recientes antes de ejecutar pruebas.
docker cp .\db\. casino-postgres:/tmp/casino-db/

docker exec `
  -e "CASINO_APP_PASSWORD=$claveApp" `
  -e "PGHOST=/var/run/postgresql" `
  -e "PGPORT=5432" `
  -e "PGUSER=postgres" `
  casino-postgres `
  bash /tmp/casino-db/run_all.sh --tests
```

**Verificación integral del 2 de noviembre de 2026:** después de incorporar `origin/main` en `andres/backend` (merge local `dbe045f`), se ejecutó `run_all.sh --tests` en `casino-postgres` y se obtuvo **109 OK, 0 FALLO, 0 PENDIENTE, código de salida 0**. Anteriormente se habían producido 39 OK y dos fallos por documentos alfanuméricos de pruebas, corregidos por André en `main`. André también reportó **22/22** en su prueba de login, resultado que todavía no se ha reproducido de manera independiente en este entorno. Véase [`docs/pruebas/estado-integracion.md`](docs/pruebas/estado-integracion.md).

André incorporó en `main` concesiones `EXECUTE` para las funciones públicas del módulo. Después de la reconstrucción, **las ocho funciones consultadas** mediante `has_function_privilege` devolvieron `t`; el conjunto completo de 20 funciones debe revisarse si se requiere una verificación exhaustiva. Las funciones opcionales de consignación y retiro aún no existen y generan avisos informativos durante la instalación. Un build exitoso no sustituye las pruebas de autorización.

### Comprobar permisos sin modificar la BD

```powershell
docker exec casino-postgres psql -X -U postgres -d casino `
  -c "SELECT p.proname, has_function_privilege('casino_app', p.oid, 'EXECUTE') AS ejecutable
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'casino' AND p.proname IN
       ('fn_crear_empleado','fn_crear_mesa','fn_crear_turno','fn_crear_asignacion',
        'fn_solicitar_pausa','fn_registrar_abono','fn_cerrar_investigacion','fn_actualizar_umbral')
      ORDER BY p.proname;"
```

## 7. Preparación de la demostración

El turno vigente de las semillas dura un tiempo limitado. Antes de una demo se puede ejecutar:

```powershell
docker cp .\db\demo\turno_actual.sql casino-postgres:/tmp/turno_actual.sql
docker exec casino-postgres psql -X -U postgres -d casino `
  -v ON_ERROR_STOP=1 -f /tmp/turno_actual.sql
```

El script respeta competencias y rotación. Si no encuentra una combinación permitida de personal para las tres mesas, mostrará un error; en una base exclusiva de demostración se puede reconstruir con `run_all.sh`. No se deben desactivar controles para hacer funcionar la demo.

## 8. Estructura del repositorio

```text
src/app/                 Páginas y layouts de Next.js (frontend)
src/components/          Componentes de interfaz (al integrarse)
src/lib/                 Contratos TypeScript y cliente SRP
src/server/acciones/     Acciones de servidor por dominio
src/server/auth/         Sesiones y autorización
db/02_esquema.sql         Tablas, restricciones e índices
db/10_auth.sql           Autenticación
db/20_personal_mesas.sql Personal, mesas, jornadas y turnos
db/30_rondas_apuestas.sql Rondas y apuestas
db/40_riesgo_historial.sql Jugadores, suspensiones e historial
db/50_permisos_auditoria.sql Privilegios y auditoría
db/90_*.sql a 93_*.sql  Semillas de demostración
db/tests/               Pruebas SQL
db/demo/                Preparación del turno actual
docs/documento/          Documentación técnica por integrante
```

## 9. Problemas frecuentes

- **`psql` no se reconoce en PowerShell:** usar `docker exec casino-postgres psql ...` o instalar el cliente de PostgreSQL en Windows.
- **Docker Engine no inicia:** comprobar Docker Desktop y WSL 2; no borrar volúmenes ni restaurar a fábrica sin revisar los datos de otros proyectos.
- **Puerto `55433` ocupado:** comprobar `docker ps` y elegir otro puerto, actualizando también `DATABASE_URL`.
- **La aplicación devuelve `CA000` o `permission denied`:** revisar permisos y los registros del servidor; confirmar que `casino_app` tiene `EXECUTE` en las funciones públicas y `SELECT` en las vistas.
- **`CA007` al escribir:** recargar el formulario para renovar la firma y la fecha.
- **No aparece turno vigente:** preparar `db/demo/turno_actual.sql` o reconstruir la base de demo respetando rotación.
- **Los tests integrales fallan después del merge:** comprobar que `origin/main` haya sido integrado y que se copiara al contenedor el `db/` actualizado; no eliminar validaciones para que pasen las pruebas.
- **`npm run build` muestra solo `/`:** todavía no está incorporada la interfaz funcional en la rama que se está compilando.

## 10. Documentos y sustentación

- [`docs/documento/framework.md`](docs/documento/framework.md): framework.
- [`docs/documento/arquitectura.md`](docs/documento/arquitectura.md): arquitectura.
- [`docs/documento/autenticacion.md`](docs/documento/autenticacion.md): SRP-6a y seguridad.
- [`docs/documento/modelo-datos.md`](docs/documento/modelo-datos.md): entidades, relaciones, restricciones y vistas.
- [`docs/documento/funcionalidades-andres.md`](docs/documento/funcionalidades-andres.md): funcionalidades de Andrés.
- [`docs/documento/dificultades-andres.md`](docs/documento/dificultades-andres.md): dificultades y decisiones.
- [`docs/documento/datos-prueba.md`](docs/documento/datos-prueba.md): escenarios de demostración.
- [`docs/pruebas/estado-integracion.md`](docs/pruebas/estado-integracion.md): resultados y dependencias abiertas.

La exposición debe cubrir la arquitectura, el flujo de una apuesta, la autenticación de conocimiento cero, las funciones y restricciones SQL, el control por roles y un análisis crítico de Next.js y PostgreSQL, con evidencias del sistema realmente funcionando.
