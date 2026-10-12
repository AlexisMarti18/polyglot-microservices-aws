# api-facturas (Java / Spring Boot)

ABM de facturas de *FinTech Nova*. Usa la base `db_facturas` (misma instancia compartida de
MariaDB que las otras 4, ver `../db/`).

## Endpoints
| Método | Ruta            | Descripción     |
|--------|-----------------|------------------|
| GET    | `/facturas`     | Listar todas     |
| GET    | `/facturas/:id` | Obtener una      |
| POST   | `/facturas`     | Crear (alta)     |
| PUT    | `/facturas/:id` | Modificar        |
| DELETE | `/facturas/:id` | Borrar (baja)    |

Body de ejemplo (`POST` / `PUT`):
```json
{ "numero": "A-0003", "monto": 12000.50, "clienteId": 1, "fechaEmision": "2026-03-01" }
```

## Cómo levantar en LOCAL (sin Docker)

Requisitos: JDK 21+, Maven 3.9+, una base MariaDB/MySQL accesible.

```sh
cd api-facturas
cp env.example .env
export $(grep -v '^#' .env | xargs)
# Si corren las 5 APIs juntas en el host para probar con el front de Vite,
# usen PORT=8083 antes de arrancar (export PORT=8083).

mvn spring-boot:run
```

Probar:
```sh
curl http://localhost:8080/facturas
```

## Docker
Este directorio **no incluye Dockerfile** — es parte de la consigna del TP escribirlo (ver el
`README.md` en la raíz de `tp-2026/`). Pista: acá el multistage (compilar con Maven, correr con
un JRE) no es opcional si quieren una imagen final liviana.
