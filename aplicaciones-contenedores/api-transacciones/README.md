# api-transacciones (Go)

ABM de transacciones de *FinTech Nova*, escrito con la librería estándar de Go
(`net/http` + `database/sql`, sin frameworks). Usa la base `db_transacciones` (misma instancia
compartida de MariaDB que las otras 4, ver `../db/`). Al crear o modificar una transacción, esta
API llama a una **API pública externa** (`https://ipapi.co`, sin API key) para geolocalizar la
IP de origen y completar el campo `pais`. Si esa API externa no responde, la transacción se
guarda igual con `pais: ""` (ver `geolocation.go`).

## Endpoints
| Método | Ruta                  | Descripción     |
|--------|------------------------|------------------|
| GET    | `/`                    | Health check     |
| GET    | `/transacciones`       | Listar todas     |
| GET    | `/transacciones/:id`   | Obtener una      |
| POST   | `/transacciones`       | Crear (alta)     |
| PUT    | `/transacciones/:id`   | Modificar        |
| DELETE | `/transacciones/:id`   | Borrar (baja)    |

Body de ejemplo (`POST` / `PUT`):
```json
{ "origen_ip": "8.8.8.8", "monto": 3000, "tipo": "compra" }
```

## Cómo levantar en LOCAL (sin Docker)

Requisitos: Go 1.22+, acceso a internet (para la API de geolocalización), una base
MariaDB/MySQL accesible.

```sh
cd api-transacciones
go mod tidy   # descarga el driver de MySQL (github.com/go-sql-driver/mysql)

cp env.example .env
export $(grep -v '^#' .env | xargs)
# Si corren las 5 APIs juntas en el host para probar con el front de Vite,
# usen PORT=8084 antes de arrancar (export PORT=8084).

go run .
```

Probar:
```sh
curl http://localhost:8080/transacciones
```

## Docker
Este directorio **no incluye Dockerfile** — es parte de la consigna del TP escribirlo (ver el
`README.md` en la raíz de `tp-2026/`). Pista: Go compila a un binario estático, así que el
multistage acá te puede dejar una imagen final buscando solo `FROM scratch` o `alpine`.
