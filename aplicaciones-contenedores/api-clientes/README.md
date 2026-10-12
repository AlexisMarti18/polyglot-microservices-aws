# api-clientes (Python / Flask)

ABM de clientes de *FinTech Nova*. Usa la base `db_clientes`, que vive en la **misma instancia**
de MariaDB que las otras 4 bases del TP (ver `../db/`).

## Endpoints
| Método | Ruta            | Descripción          |
|--------|-----------------|-----------------------|
| GET    | `/`             | Health check          |
| GET    | `/clientes`     | Listar todos          |
| GET    | `/clientes/:id` | Obtener uno           |
| POST   | `/clientes`     | Crear (alta)          |
| PUT    | `/clientes/:id` | Modificar             |
| DELETE | `/clientes/:id` | Borrar (baja)         |

Body de ejemplo (`POST` / `PUT`):
```json
{ "nombre": "Ana Torres", "email": "ana@example.com", "dni": "30111222" }
```

Validación del body (`POST` / `PUT`): tiene que ser un objeto JSON, con `nombre` y `email` como
texto obligatorio y `dni` como texto u omitido. Si no se cumple, responde `400`; si el body pasa
de 16 KB, `413`. Los errores siempre vienen como `{"error": "..."}` (ver `../../ERRORES.md`).

## Cómo levantar en LOCAL (sin Docker)

Requisitos: Python 3.11+ y una base MariaDB/MySQL accesible (puede ser la de `../db/`, levantada
suelta con `docker run`, o cualquier MySQL local).

```sh
cd api-clientes
python3 -m venv venv
source venv/bin/activate        # en Windows: venv\Scripts\activate
pip install -r requirements.txt

cp env.example .env
# Editar .env: DB_HOST=localhost (o la IP/host de tu MariaDB), y el resto de las credenciales.
# Si van a correr las 5 APIs juntas en el host (sin Docker) para probar con el front de Vite,
# usen PORT=8081 para que no choque con las demás.

export $(grep -v '^#' .env | xargs)   # carga las variables del .env en la shell (Linux/Mac)
python main.py
```

Probar:
```sh
curl http://localhost:8080/clientes
```

## Docker

Imagen: `${DOCKERHUB_USER}/fintech-nova-api-clientes:1.0.0`.

### Build y ejecución

Desde la raíz del repo (el contexto de build es la carpeta del componente):

```sh
docker build -t ${DOCKERHUB_USER}/fintech-nova-api-clientes:1.0.0 ./aplicaciones-contenedores/api-clientes

cp aplicaciones-contenedores/api-clientes/env.example aplicaciones-contenedores/api-clientes/.env
# Completar DB_USER / DB_PASSWORD con los MYSQL_USER / MYSQL_PASSWORD de db/.env

docker compose up -d db api-clientes
```

El servicio no publica puertos al host: se accede por la red `interna` de Compose (NGINX lo
proxya en `/api/clientes` hacia `api-clientes:8080`). Para probar desde adentro:

```sh
docker compose exec api-clientes python -c "import urllib.request;print(urllib.request.urlopen('http://127.0.0.1:8080/clientes').read().decode())"
```

### Decisiones

| Tema | Decisión | Por qué |
|---|---|---|
| Imagen base | `python:3.12-slim` | Oficial, Debian (glibc) y más chica que la completa. |
| Multistage + venv | `builder` crea `/opt/venv`, instala las deps y desinstala `pip` del venv; el runtime copia solo el venv y el código. | El venv aísla las deps del Python del sistema y se copia como una unidad. Sin `pip` en el venv, la imagen queda en 188 MB, menos que con un solo stage (ver `MULTISTAGE.md`). |
| Servidor | Gunicorn 26.2.0, 2 workers (`gunicorn main:app`) | `app.run()` es el servidor de desarrollo de Flask, no apto para producción. No hizo falta tocar el código. |
| Arranque | `sh -c "exec gunicorn --bind 0.0.0.0:${PORT:-8080} ..."` | Respeta `PORT`; con `exec` gunicorn es PID 1 y recibe el SIGTERM de `docker stop`. |
| `--no-control-socket` | Desactiva el socket de control de gunicorn. | Gunicorn 26 lo crea en `$HOME` y `appuser` no tiene home (ver `../../ERRORES.md`). No se usa. |
| Usuario | `appuser` (uid 999), no-root | El código queda de root y es solo lectura para la app. |
| HEALTHCHECK | `urllib` de Python contra `http://127.0.0.1:$PORT/` | `slim` no trae curl/wget. `127.0.0.1` porque gunicorn escucha solo en IPv4. |
| Variables | `PYTHONDONTWRITEBYTECODE=1`, `PYTHONUNBUFFERED=1` | Sin `.pyc` en disco y logs inmediatos en `docker logs`. |
| Recursos (Compose) | `cpus: "0.25"`, `memory: 128M` | En la prueba local usó ~58 MiB con 2 workers. |

### Verificación local (Docker Desktop, 2026-09-27)

- Contexto de build: 4.29 kB. Imagen: 188 MB en disco / 45.6 MB comprimida.
- `docker run --rm --entrypoint id ...` → `uid=999(appuser)`.
- `docker compose up -d --pull never db api-clientes` → ambos `healthy`.
- ABM por la red interna: GET 200, POST 201, PUT 200, DELETE 204, GET del borrado 404.
- Con `PORT=9090` escucha en 9090 y queda `healthy`; `docker stop` tarda < 1 s.
- Pendiente: `docker push` y `curl -k https://<ip-ec2>:<puerto>/api/clientes` con `web` y la EC2.
