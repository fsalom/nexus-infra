#!/usr/bin/env bash
# Despliegue idempotente en el servidor: actualiza los 4 repos y levanta la infra.
# Lo ejecuta la pipeline por SSH, pero también sirve a mano en el servidor.
set -euo pipefail

BASE="${NEXUS_DIR:-$HOME/nexus}"          # carpeta donde viven los repos, uno al lado del otro
GH="${GIT_BASE:-https://github.com/fsalom}"   # para repos privados: https://TOKEN@github.com/fsalom
REPOS="nexus-infra gastos-python python-microworkout nexus-auth"

mkdir -p "$BASE"; cd "$BASE"
for r in $REPOS; do
  if [ -d "$r/.git" ]; then
    echo "== actualizando $r =="; git -C "$r" pull --ff-only
  else
    echo "== clonando $r =="; git clone "$GH/$r.git" "$r"
  fi
done

# Materializa cada .env juntando la parte no sensible (Variables, editables en
# la UI de GitHub) + la parte sensible (Secrets). Compat: si se pasa el blob
# antiguo (INFRA_ENV/MICROWORKOUT_ENV) se usa; si no hay nada, se respeta el
# .env que ya exista en el servidor.
write_env() {  # $1=fichero  $2=vars  $3=secrets  $4=blob_legacy
  if [ -n "$(printf '%s' "${2}${3}" | tr -d '[:space:]')" ]; then
    printf '%s\n%s\n' "$2" "$3" > "$1"; echo "== escrito $1 (variables + secrets) =="
  elif [ -n "$(printf '%s' "$4" | tr -d '[:space:]')" ]; then
    printf '%s\n' "$4" > "$1"; echo "== escrito $1 (blob) =="
  fi
}
write_env "$BASE/nexus-infra/.env"        "${INFRA_VARS:-}"       "${INFRA_SECRETS:-}"       "${INFRA_ENV:-}"
write_env "$BASE/python-microworkout/.env" "${MICROWORKOUT_VARS:-}" "${MICROWORKOUT_SECRETS:-}" "${MICROWORKOUT_ENV:-}"

cd "$BASE/nexus-infra"
docker compose up -d --build

# el Caddyfile va bind-mounted: compose no ve sus cambios, así que se recarga
docker compose exec -T caddy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile 2>/dev/null \
  || docker compose restart caddy || true

# microworkout: migraciones y estáticos (idempotente).
# collectstatic va como root: el volumen workout_static (vacío) es de root y el
# usuario de la app no puede escribir; los ficheros luego solo se leen (Caddy los sirve).
docker compose run --rm workout-admin python manage.py migrate --noinput || true
docker compose run --rm --user root workout-admin python manage.py collectstatic --noinput || true

docker compose ps
