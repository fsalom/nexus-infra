# nexus-infra

Despliegue conjunto de [**gastos-python**](https://github.com/fsalom/gastos-python) y
[**python-microworkout**](https://github.com/fsalom/python-microworkout) en un solo host,
detrás de **Caddy** (HTTPS automático, enrutado por subdominio).

```
                       ┌─────────── Caddy (80/443, TLS) ───────────┐
   gastos.DOMINIO  ────┤                                            ├──> gastos            (FastAPI + SQLite)
   workout.DOMINIO ────┤  /admin,/o → admin · /static,/media → files├──> workout-api       (FastAPI/ASGI)
                       └────────────────────────────────────────────┘──> workout-admin     (Django/WSGI)
                                                                          workout-db        (PostgreSQL/PostGIS)
```

## Requisitos

- Un host con **Docker** y **Docker Compose**.
- Los tres repos clonados **uno al lado del otro**:
  ```
  git clone https://github.com/fsalom/nexus-infra.git
  git clone https://github.com/fsalom/gastos-python.git
  git clone https://github.com/fsalom/python-microworkout.git
  ```
- DNS: `gastos.DOMINIO` y `workout.DOMINIO` con registro **A/AAAA** apuntando al host.

## Puesta en marcha

```bash
cd nexus-infra
cp .env.example .env                 # DOMAIN, ACME_EMAIL, GASTOS_PASSWORD…

# microworkout lee su configuración de ../python-microworkout/.env
# (POSTGRES_USER/PASSWORD/DB, SECRET_KEY, ALLOWED_HOSTS, DEBUG=False, etc.).
# Créalo con tus valores antes de levantar.

docker compose up -d --build
```

La primera vez, prepara la BD de microworkout:

```bash
docker compose run --rm workout-admin python manage.py migrate
docker compose run --rm workout-admin python manage.py collectstatic --noinput
```

Listo: `https://gastos.DOMINIO` y `https://workout.DOMINIO` (Caddy saca los certificados solo).

## Notas

- **Caddy sustituye al nginx de microworkout** como borde único: hace TLS y enruta
  igual que aquél (`/admin` y `/o` → Django, `/static` y `/media` → ficheros del volumen,
  el resto → FastAPI). El nginx del repo de microworkout no se usa aquí.
- **Datos persistentes** (volúmenes): `gastos_data`, `workout_pgdata`, `workout_media`,
  `workout_static`, `workout_backups` y los certificados en `caddy_data`.
- **`POSTGRES_HOST`** se fuerza a `db` (alias de red de `workout-db`), así el `.env` de
  microworkout funciona sin cambios.
- **Cron de gastos** (precios + snapshot + copia): en el `crontab` del host,
  ```
  0 7 * * *  curl -fsS -X POST -H "X-Cron-Token: TU_TOKEN" https://gastos.DOMINIO/api/cron/daily
  ```
- Comandos útiles: `docker compose ps`, `docker compose logs -f caddy`,
  `docker compose logs -f workout-api`.
