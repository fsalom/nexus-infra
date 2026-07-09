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

cd "$BASE/nexus-infra"
docker compose up -d --build

# microworkout: migraciones y estáticos (idempotente)
docker compose run --rm workout-admin python manage.py migrate --noinput || true
docker compose run --rm workout-admin python manage.py collectstatic --noinput || true

docker compose ps
