# Base de datos local

Una imagen de MariaDB 11.8.9 alberga cinco bases: `db_clientes`, `db_pagos`,
`db_facturas`, `db_transacciones` y `db_tarjetas`. El archivo `00-databases.sh`
crea las bases y concede permisos al usuario de aplicación compartido; los
archivos SQL numerados crean las tablas y cargan datos de ejemplo.

## Preparar y levantar

1. Copiar `env.example` a `.env` en esta carpeta. Completar
   `MYSQL_ROOT_PASSWORD`, `MYSQL_USER` y `MYSQL_PASSWORD` con valores locales.
   Dejar `MYSQL_DATABASE=db_clientes`. No subir `.env` a Git.
2. Desde la raíz del repositorio, construir con **esta carpeta como contexto**:

   ```sh
   docker build -t ${DOCKERHUB_USER}/fintech-nova-db:1.0.0 ./aplicaciones-contenedores/db
   ```

3. Levantar el servicio definido en Compose sin descargar una imagen:

   ```sh
   docker compose -p fintech-db-local up -d --pull never db
docker compose -p fintech-db-local ps
   ```

Compose mantiene los datos en un volumen nombrado y conecta `db` a la red
`backend` (la comparten solo las APIs y `db`). No publica el puerto 3306 al host. Las APIs en la misma red deben
usar `DB_HOST=db`, `DB_PORT=3306` y el nombre de su propia base en `DB_NAME`.
La imagen incluye una verificación de salud con el script oficial de MariaDB;
esperar a que `ps` indique `healthy` antes de consultar la base recién iniciada.

## Comprobar la inicialización

```sh
docker compose -p fintech-db-local exec db sh -c 'MYSQL_PWD="$MYSQL_PASSWORD" mariadb -u "$MYSQL_USER" -e "SHOW DATABASES; SHOW TABLES FROM db_clientes; SHOW TABLES FROM db_pagos; SHOW TABLES FROM db_facturas; SHOW TABLES FROM db_transacciones; SHOW TABLES FROM db_tarjetas;"'
```

Los scripts en `/docker-entrypoint-initdb.d` se ejecutan **solo cuando el
volumen está vacío**. Al detener y volver a levantar el servicio, los datos
persisten. Si se modifican los scripts después de la primera inicialización,
hay que aplicar una migración a la base existente; reconstruir la imagen no
repite la inicialización. Para terminar la prueba sin borrar los datos:

```sh
docker compose -p fintech-db-local down
```

El usuario de aplicación tiene permisos sobre las cinco bases. Esta instancia
comparte servidor y credenciales entre las APIs; la separación es por esquema.
