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
El `Dockerfile` es multistage: `dotnet/sdk:8.0-alpine` restaura y publica la app, y la imagen final
(`dotnet/aspnet:8.0-alpine`, mucho más liviana) solo lleva el runtime y la app publicada, con el
usuario no-root `appuser`. Ver el [README de la raíz](../../README.md) y
[SEGURIDAD.md](../../SEGURIDAD.md).
