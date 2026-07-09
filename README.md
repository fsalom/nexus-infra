# nexus-infra

Despliegue conjunto de [**gastos-python**](https://github.com/fsalom/gastos-python),
[**python-microworkout**](https://github.com/fsalom/python-microworkout) y el SSO
[**nexus-auth**](https://github.com/fsalom/nexus-auth) en un solo host, detrás de
**Caddy** (HTTPS automático, enrutado por subdominio y **login único vía forward-auth**).

```
                        ┌──────────── Caddy (80/443, TLS) ────────────┐
   auth.DOMINIO    ─────┤                                              ├──> auth          (SSO: login/portal/admin)
   gastos.DOMINIO  ──▶ forward-auth ──┤ (login único; deja pasar o no) ├──> gastos        (FastAPI + SQLite)
   workout.DOMINIO ──▶ forward-auth ──┤                                ├──> workout-api   (FastAPI/ASGI)
                        └──────────────────────────────────────────────┘──> workout-admin (Django/WSGI)
                                                                            workout-db     (PostgreSQL/PostGIS)
```

Antes de entrar a gastos o workout, Caddy consulta a `auth` (`/verify`): si no hay sesión
te manda al login de `auth.DOMINIO`; si la hay, deja pasar. gastos ya no tiene contraseña propia.

## Requisitos

- Un host con **Docker** y **Docker Compose**.
- Los tres repos clonados **uno al lado del otro**:
  ```
  git clone https://github.com/fsalom/nexus-infra.git
  git clone https://github.com/fsalom/gastos-python.git
  git clone https://github.com/fsalom/python-microworkout.git
  git clone https://github.com/fsalom/nexus-auth.git   # SSO
  ```
- DNS: `auth.DOMINIO`, `gastos.DOMINIO` y `workout.DOMINIO` con registro **A/AAAA** apuntando al host.

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
La primera vez te pedirá login en `auth.DOMINIO`; entra con `NEXUS_ADMIN_USER`/`NEXUS_ADMIN_PASSWORD`
y en `https://auth.DOMINIO/admin` das de alta usuarios, grupos y qué app puede usar cada uno.

## Despliegue automático (GitHub Actions)

`.github/workflows/deploy.yml` despliega por SSH (manual desde **Actions → deploy → Run workflow**,
o al hacer **push a main**): entra al servidor, actualiza los 4 repos en `~/nexus` y hace
`docker compose up -d --build` (más `migrate`/`collectstatic` de microworkout). La lógica está en
`deploy/deploy.sh`, reutilizable a mano en el servidor.

Secrets del repo (*Settings → Secrets and variables → Actions*):

| Secret | ¿Necesario? | Por defecto |
|---|---|---|
| `SSH_PRIVATE_KEY` | **sí** | — (clave privada con acceso al servidor) |
| `SSH_HOST` | no | `161.35.215.164` |
| `SSH_USER` | no | `root` |
| `SSH_PORT` | no | `22` |
| `GH_TOKEN` | repos privados | — (PAT *fine-grained* con `Contents: read` a los 4 repos) |
| `INFRA_ENV` | recomendado | contenido **completo** de `nexus-infra/.env` |
| `MICROWORKOUT_ENV` | recomendado | contenido **completo** de `python-microworkout/.env` |

Con `INFRA_ENV`/`MICROWORKOUT_ENV` puestos, la pipeline **crea los `.env` en el servidor** y el
despliegue es 100% desde GitHub. Si no los pones, deja los `.env` creados a mano en el servidor
(la pipeline los respeta).

Preparar el servidor **una vez**:
1. Docker y Docker Compose instalados (`curl -fsSL https://get.docker.com | sh`); tu clave
   **pública** en `~/.ssh/authorized_keys`.
2. Nada más: los repos se clonan solos en `~/nexus` (con `GH_TOKEN` si son privados) y los
   `.env` se materializan desde los secrets.
3. Crea los `.env` (no van en git): `~/nexus/nexus-infra/.env` y `~/nexus/python-microworkout/.env`.
4. DNS de `auth`/`gastos`/`workout.DOMINIO` → `161.35.215.164`.

## Notas

- **Login único (SSO)**: `nexus-auth` centraliza el acceso. Caddy protege gastos y workout
  con `forward_auth` (patrón ext_authz: el proxy pregunta y deja pasar o no; el servicio no
  está en el camino de los datos). La cookie de sesión es del dominio padre (`.DOMINIO`), así
  vale para todos los subdominios; los clientes API/móvil pueden usar `Authorization: Bearer`
  (`POST https://auth.DOMINIO/api/token`). El cron de gastos se salta el SSO (va por token).
- **Caddy sustituye al nginx de microworkout** como borde único: hace TLS y enruta
  igual que aquél (`/admin` y `/o` → Django, `/static` y `/media` → ficheros del volumen,
  el resto → FastAPI). El nginx del repo de microworkout no se usa aquí.
- **Postgres compartido**: un único servicio `db` (PostGIS) con **3 bases de datos** —
  `microworkout`, `gastos` y `auth` (las dos últimas las crea `deploy/initdb/99-extra-dbs.sql`
  al inicializar). gastos y auth conectan por `DATABASE_URL` (`…@db:5432/gastos|auth`) con el
  usuario/clave de `POSTGRES_USER`/`POSTGRES_PASSWORD`; microworkout usa la BBDD `microworkout`.
- **Datos persistentes** (volúmenes): `pg_data` (las 3 BBDD), `pg_backups` (`pg_dumpall` diario),
  `workout_media`, `workout_static` y los certificados en `caddy_data`.
- **Cron de gastos** (precios + snapshot + copia): en el `crontab` del host,
  ```
  0 7 * * *  curl -fsS -X POST -H "X-Cron-Token: TU_TOKEN" https://gastos.DOMINIO/api/cron/daily
  ```
- Comandos útiles: `docker compose ps`, `docker compose logs -f caddy`,
  `docker compose logs -f workout-api`.
