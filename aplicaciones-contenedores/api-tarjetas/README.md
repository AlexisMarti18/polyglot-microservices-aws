# api-tarjetas (.NET / ASP.NET Core Minimal API)

ABM de tarjetas de *FinTech Nova* (sin datos reales de tarjeta: solo alias, titular, tipo y
límite — nada de números de tarjeta reales). Usa la base `db_tarjetas` (misma instancia
compartida de MariaDB que las otras 4, ver `../db/`). Usa `MySqlConnector` con SQL directo (sin
ORM ni migraciones), igual filosofía que `api-transacciones` en Go.

## Endpoints
| Método | Ruta             | Descripción     |
|--------|------------------|------------------|
| GET    | `/`              | Health check     |
| GET    | `/tarjetas`      | Listar todas     |
| GET    | `/tarjetas/:id`  | Obtener una      |
| POST   | `/tarjetas`      | Crear (alta)     |
| PUT    | `/tarjetas/:id`  | Modificar        |
| DELETE | `/tarjetas/:id`  | Borrar (baja)    |

Body de ejemplo (`POST` / `PUT`):
```json
{ "alias": "Visa Gold", "titular": "Juan Perez", "tipo": "credito", "limite": 500000 }
```

## Cómo levantar en LOCAL (sin Docker)

Requisitos: .NET SDK 8+, una base MariaDB/MySQL accesible.

```sh
cd api-tarjetas
cp env.example .env
export $(grep -v '^#' .env | xargs)
# Si corren las 5 APIs juntas en el host para probar con el front de Vite,
# usen PORT=8085 antes de arrancar (export PORT=8085).

dotnet run
```

Probar:
```sh
curl http://localhost:8080/tarjetas
```

## Docker
Este directorio **no incluye Dockerfile** — es parte de la consigna del TP escribirlo (ver el
`README.md` en la raíz de `tp-2026/`). Pista: acá también aplica multistage (compilar/publicar
con el SDK, correr con la imagen `aspnet` runtime, mucho más liviana).
