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
El `Dockerfile` es multistage: `maven:3.9-eclipse-temurin-21-alpine` compila el `.jar` y la imagen
final (`eclipse-temurin:21-jre-alpine`) solo lleva el JRE y el `.jar`, con el usuario no-root
`appuser`. El heap de la JVM se calcula sobre el límite de memoria del contenedor
(`JAVA_TOOL_OPTIONS`), y el `HEALTHCHECK` consulta `/facturas`, que además comprueba la conexión a
la base. Ver el [README de la raíz](../../README.md) y [SEGURIDAD.md](../../SEGURIDAD.md).
