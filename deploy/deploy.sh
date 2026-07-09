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

# .env desde los secrets (si la pipeline los pasa por entorno); si no, se usa
# el .env que ya exista en el servidor (creado a mano).
if [ -n "${INFRA_ENV:-}" ]; then
  printf '%s\n' "$INFRA_ENV" > "$BASE/nexus-infra/.env"
  echo "== escrito nexus-infra/.env desde secret =="
fi
if [ -n "${MICROWORKOUT_ENV:-}" ]; then
  printf '%s\n' "$MICROWORKOUT_ENV" > "$BASE/python-microworkout/.env"
  echo "== escrito python-microworkout/.env desde secret =="
fi

cd "$BASE/nexus-infra"
docker compose up -d --build

# microworkout: migraciones y estáticos (idempotente)
docker compose run --rm workout-admin python manage.py migrate --noinput || true
docker compose run --rm workout-admin python manage.py collectstatic --noinput || true

docker compose ps
