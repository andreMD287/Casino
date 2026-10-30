# Casino — Bases de Datos (Javeriana)

Aplicación web para la gestión de un casino. Next.js 16 (App Router, Server Actions) + PostgreSQL (16 o superior), sin ORM.
El contrato común del equipo está en [`docs/CONTRATO.md`](docs/CONTRATO.md).

> README mínimo de la fase 0 (André). Andrés lo completa con la instalación detallada.

## Requisitos

- Node.js 20+ y npm
- PostgreSQL 16+ con acceso de superusuario (solo para crear la base)
- Bash (en Windows, Git Bash) para `db/run_all.sh`

## Arranque

```bash
npm install
cp .env.example .env.local      # completar PGPASSWORD, CASINO_APP_PASSWORD (igual en DATABASE_URL) y SECRETO_SERVIDOR
./db/run_all.sh                 # recrea la base "casino" desde cero (DROP + CREATE)
./db/run_all.sh --tests         # igual, y además corre db/tests/*.sql (OK / FALLO / PENDIENTE)
npm run dev                     # http://localhost:3000
```

Si `psql` no está en el PATH, `run_all.sh` lo busca en `C:\Program Files\PostgreSQL\*\bin` o se le puede indicar con `PSQL=/ruta/a/psql`.

### Sin base de datos (frontend)

Con `MODO_MOCK=1` en `.env.local`, todas las acciones responden con datos de ejemplo en memoria y la sesión
se simula con el rol de `MOCK_ROL` (`administrador`, `crupier`, `supervisor` o `jugador`).
El login también funciona en este modo (SRP de verdad contra usuarios en memoria).

## Usuarios de prueba

Clave de todos: `Casino2026*`

| Usuario | Rol |
|---|---|
| `admin` | administrador |
| `crupier1` … `crupier4` | crupier |
| `supervisor1`, `supervisor2` | supervisor |
| `jugador1`, `jugador2`, `jugador3`, `crupier1.juega`, `supervisor1.juega` | jugador |

Los verificadores SRP se generan con `npm run semilla:usuarios` (escribe `db/90_semilla_base.sql`).

## Scripts

| Comando | Qué hace |
|---|---|
| `npm run db` / `npm run db:test` | `db/run_all.sh` sin / con pruebas |
| `npm run probar:auth` | prueba de punta a punta del login SRP contra la BD |
| `npm run semilla:usuarios` | regenera los usuarios de prueba con su salt y verificador |
| `npm run build` | compilación de producción |
