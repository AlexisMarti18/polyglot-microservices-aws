#!/bin/bash
# Los microservicios de este TP comparten UNA SOLA instancia de MariaDB (un solo contenedor),
# pero cada uno tiene su PROPIA base de datos dentro de esa instancia (aislamiento logico, no
# fisico). La imagen oficial de mariadb solo crea automaticamente la base de MYSQL_DATABASE y le
# da permisos a MYSQL_USER sobre ella; este script (se ejecuta con bash, no con el cliente mysql,
# por eso puede leer variables de entorno) crea las 4 bases restantes y extiende los permisos del
# mismo usuario de aplicacion a todas.
set -e

mariadb -u root -p"$MYSQL_ROOT_PASSWORD" <<-EOSQL
    CREATE DATABASE IF NOT EXISTS db_clientes;
    CREATE DATABASE IF NOT EXISTS db_pagos;
    CREATE DATABASE IF NOT EXISTS db_facturas;
    CREATE DATABASE IF NOT EXISTS db_transacciones;
    CREATE DATABASE IF NOT EXISTS db_tarjetas;

    GRANT ALL PRIVILEGES ON db_clientes.* TO '$MYSQL_USER'@'%';
    GRANT ALL PRIVILEGES ON db_pagos.* TO '$MYSQL_USER'@'%';
    GRANT ALL PRIVILEGES ON db_facturas.* TO '$MYSQL_USER'@'%';
    GRANT ALL PRIVILEGES ON db_transacciones.* TO '$MYSQL_USER'@'%';
    GRANT ALL PRIVILEGES ON db_tarjetas.* TO '$MYSQL_USER'@'%';
    FLUSH PRIVILEGES;
EOSQL
