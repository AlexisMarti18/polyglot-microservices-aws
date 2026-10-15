# api-pagos (Node.js / Express)

ABM de pagos de *FinTech Nova*. Usa la base `db_pagos` (misma instancia compartida de MariaDB
que las otras 4, ver `../db/`). Al crear o modificar un pago, esta API llama a una **API pública
externa** (`https://open.er-api.com`, sin API key) para convertir el monto de ARS a USD y lo
guarda en `monto_usd`. Si esa API externa no responde, el pago se guarda igual con
`monto_usd: null` (ver `src/exchangeRate.js`).

## Endpoints
| Método | Ruta         | Descripción     |
|--------|--------------|------------------|
| GET    | `/`          | Health check     |
| GET    | `/pagos`     | Listar todos     |
| GET    | `/pagos/:id` | Obtener uno      |
| POST   | `/pagos`     | Crear (alta)     |
| PUT    | `/pagos/:id` | Modificar        |
| DELETE | `/pagos/:id` | Borrar (baja)    |

Body de ejemplo (`POST` / `PUT`):
```json
{ "monto_ars": 50000, "medio_pago": "transferencia" }
```

Validación del body (`POST` / `PUT`): tiene que ser un objeto JSON, con `monto_ars` como número (o
texto numérico, por ejemplo `"50000"`) y `medio_pago` como texto no vacío. Si no se cumple, responde
`400` sin llamar a la API externa. Si el JSON está mal formado responde `400`, y si el body pasa de
32 KB, `413`. Los errores siempre vienen como `{"error": "..."}` (ver `../../ERRORES.md`).

## Cómo levantar en LOCAL (sin Docker)

Requisitos: Node.js 20+, acceso a internet (para la API de tipo de cambio) y una base
MariaDB/MySQL accesible.

```sh
cd api-pagos
npm install

cp env.example .env
# Editar .env. Si corren las 5 APIs juntas en el host para probar con el front de Vite,
# usen PORT=8082 para que no choque con las demás.

npm start
```

Probar:
```sh
curl http://localhost:8080/pagos
curl -X POST http://localhost:8080/pagos \
  -H "Content-Type: application/json" \
  -d '{"monto_ars": 50000, "medio_pago": "transferencia"}'
```

## Docker

### Imagen

`Dockerfile` de **un solo stage** sobre `node:22-alpine`:

- **Sin multistage:** es JavaScript plano (no hay compilación) y no hay devDependencies.
  `npm ci --omit=dev` ya deja solo lo necesario; un segundo stage no achicaría la imagen.
- **Dependencias reproducibles:** se copian `package.json` y `package-lock.json` antes que el código
  y se instala con `npm ci`, así que si solo cambia `src/` se reutiliza la capa de dependencias.
- **No-root:** corre como el usuario `node` (uid 1000) de la imagen oficial. El código es de root y
  la app no lo puede modificar.
- **Arranque:** `node src/server.js` directo (sin `npm start`), para que sea PID 1 y reciba `SIGTERM`.
- **Sin `npm` en runtime:** se borra después de `npm ci`, porque el `npm` de la imagen base trae
  dependencias con CVE. Con esto, Trivy pasa a 0 vulnerabilidades (ver `MULTISTAGE.md` y `../../SEGURIDAD.md`).
- **HEALTHCHECK:** `wget` a `http://127.0.0.1:${PORT}/`. Se usa `127.0.0.1` y no `localhost` porque
  busybox resuelve `localhost` a `::1` y la app escucha solo en IPv4 (ver `../../ERRORES.md`).
- **Tamaño:** ~63 MB comprimida (253 MB en disco, de los cuales 238 MB son la base de Node).
- `.dockerignore` deja fuera `node_modules/`, `.env`, `env.example`, `*.md` y certificados y claves.
  El build context pesa ~42 kB.

### Construir

Desde la raíz del repo, con esta carpeta como contexto:

```sh
docker build -t ${DOCKERHUB_USER}/fintech-nova-api-pagos:1.0.0 ./aplicaciones-contenedores/api-pagos
```

### Configuración

Copiar `env.example` a `.env` y completar `DB_USER`/`DB_PASSWORD` con los mismos valores que
`MYSQL_USER`/`MYSQL_PASSWORD` de `../db/.env`. En Compose, `DB_HOST=db` (nombre del servicio de la
base compartida) y `DB_NAME=db_pagos`. El `.env` nunca se sube a Git.

### Levantar con Compose

El servicio `api-pagos` del `docker-compose.yml` raíz se conecta a las redes `frontend` y `backend`, espera a que
`db` esté `healthy`, tiene `restart: always` y límites de 0.25 CPU / 128 MiB, y **no publica puertos**:
solo se accede a través de `web` (`/api/pagos`).

```sh
docker compose up -d --pull never db api-pagos   # --pull never: usa las imágenes construidas en local
docker compose ps                                 # ambos deben quedar "healthy"
```

Probar desde dentro de la red (la API no está expuesta al host). El nombre de la red es
`<proyecto>_backend`, donde el proyecto es el nombre de la carpeta del repo (se ve con
`docker network ls`):

```sh
docker run --rm --network <proyecto>_backend busybox wget -qO- http://api-pagos:8080/pagos
```

### Salida a internet

La API necesita salir a `https://open.er-api.com`, lo que la red por defecto de Compose permite. Si
la API externa no responde (timeout de 5 s), el pago se guarda igual con `monto_usd: null`. Esto se
verificó corriendo el contenedor en una red `--internal`, sin salida a internet.
