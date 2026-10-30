#!/usr/bin/env bash
# run_all.sh (André) — recrea la base "casino" desde cero y, con --tests, corre las pruebas.
#
#   ./db/run_all.sh            # recrea la base y carga esquema, funciones y semillas
#   ./db/run_all.sh --tests    # además ejecuta db/tests/*.sql y cuenta OK / FALLO / PENDIENTE
#
# Variables (se toman del entorno o de .env / .env.local en la raíz del proyecto):
#   PGHOST, PGPORT, PGUSER, PGPASSWORD  superusuario de PostgreSQL (solo para este script)
#   CASINO_APP_PASSWORD                 clave del rol casino_app (la misma de DATABASE_URL)
#   PSQL                                (opcional) ruta a psql si no está en el PATH
set -euo pipefail

DIR_DB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RAIZ="$(dirname "$DIR_DB")"
CON_TESTS=0
[[ "${1:-}" == "--tests" ]] && CON_TESTS=1

# ---- Cargar .env sin ejecutarlo como shell; el entorno tiene prioridad ----
cargar_env() {
  local archivo="$1" linea clave valor
  [[ -f "$archivo" ]] || return 0
  while IFS= read -r linea || [[ -n "$linea" ]]; do
    linea="${linea%$'\r'}"
    [[ "$linea" =~ ^[[:space:]]*# || "$linea" != *=* ]] && continue
    clave="${linea%%=*}"; clave="${clave//[[:space:]]/}"
    valor="${linea#*=}"
    valor="${valor%\"}"; valor="${valor#\"}"; valor="${valor%\'}"; valor="${valor#\'}"
    case "$clave" in
      PGHOST|PGPORT|PGUSER|PGPASSWORD|CASINO_APP_PASSWORD|PSQL)
        [[ -z "${!clave:-}" ]] && export "$clave=$valor" ;;
    esac
  done < "$archivo"
}
cargar_env "$RAIZ/.env.local"
cargar_env "$RAIZ/.env"

: "${CASINO_APP_PASSWORD:?Falta CASINO_APP_PASSWORD (ver .env.example)}"
export PGCLIENTENCODING=UTF8

# ---- Ubicar psql (en Windows suele no estar en el PATH) ----
if [[ -z "${PSQL:-}" ]]; then
  if command -v psql >/dev/null 2>&1; then
    PSQL=psql
  else
    PSQL="$(ls -d /c/Program\ Files/PostgreSQL/*/bin/psql.exe 2>/dev/null | sort -V | tail -n 1 || true)"
  fi
fi
[[ -n "${PSQL:-}" ]] || { echo "No encontré psql. Agrégalo al PATH o define PSQL=/ruta/a/psql" >&2; exit 1; }

psql_admin() { "$PSQL" -X -q -v ON_ERROR_STOP=1 -d postgres "$@"; }
psql_casino() { "$PSQL" -X -q -v ON_ERROR_STOP=1 -d casino "$@"; }

echo "==> Recreando la base casino"
psql_admin -c "DROP DATABASE IF EXISTS casino WITH (FORCE)"
psql_admin -c "CREATE DATABASE casino ENCODING 'UTF8' TEMPLATE template0"

ORDEN=(00 01 02 05 10 20 30 40 50 90 91 92 93)
for prefijo in "${ORDEN[@]}"; do
  archivo="$(ls "$DIR_DB"/"${prefijo}"_*.sql 2>/dev/null | head -n 1 || true)"
  if [[ -z "$archivo" ]]; then
    echo "AVISO: no existe db/${prefijo}_*.sql; se omite"
    continue
  fi
  echo "==> $(basename "$archivo")"
  if [[ "$prefijo" == "01" ]]; then
    psql_casino -v app_password="$CASINO_APP_PASSWORD" -f "$archivo"
  else
    psql_casino -f "$archivo"
  fi
done
echo "==> Base casino lista"

[[ "$CON_TESTS" == 1 ]] || exit 0

echo
echo "==> Pruebas"
TOTAL_OK=0; TOTAL_FALLO=0; TOTAL_PEND=0; ARCHIVOS_ROTOS=0
shopt -s nullglob
for prueba in "$DIR_DB"/tests/*.sql; do
  echo "--- $(basename "$prueba")"
  set +e
  salida="$(psql_casino -f "$prueba" 2>&1)"
  estado=$?
  set -e
  echo "$salida" | grep -E '\[(OK|FALLO|PENDIENTE)\]' | sed -E 's/^.*(\[(OK|FALLO|PENDIENTE)\])/\1/' || true
  if [[ $estado -ne 0 ]]; then
    echo "$salida" | grep -vE '\[(OK|FALLO|PENDIENTE)\]' | tail -n 5
    echo "[FALLO] el archivo $(basename "$prueba") terminó con error"
    ARCHIVOS_ROTOS=$((ARCHIVOS_ROTOS + 1))
  fi
  TOTAL_OK=$((TOTAL_OK + $(echo "$salida" | grep -c '\[OK\]' || true)))
  TOTAL_FALLO=$((TOTAL_FALLO + $(echo "$salida" | grep -c '\[FALLO\]' || true)))
  TOTAL_PEND=$((TOTAL_PEND + $(echo "$salida" | grep -c '\[PENDIENTE\]' || true)))
done
TOTAL_FALLO=$((TOTAL_FALLO + ARCHIVOS_ROTOS))

echo
echo "Resultado: OK=$TOTAL_OK  FALLO=$TOTAL_FALLO  PENDIENTE=$TOTAL_PEND"
[[ $TOTAL_FALLO -eq 0 ]] || exit 1
