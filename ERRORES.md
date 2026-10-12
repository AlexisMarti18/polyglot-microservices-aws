# Glosario de errores

Errores que aparecieron al dockerizar y desplegar los microservicios, con su causa y su solución,
separados por componente.

- [api-clientes (Python / Flask)](#api-clientes-python--flask)
- [api-pagos (Node / Express)](#api-pagos-node--express)
- [web (Vite + NGINX)](#web-vite--nginx)
- [api-transacciones (Go)](#api-transacciones-go)
- [deploy.sh](#deploysh)
- [AWS Academy Learner Lab](#aws-academy-learner-lab)

## api-clientes (Python / Flask)

### 1. Gunicorn 26 no puede crear su socket de control (`/home/appuser`)

- **Síntoma:** el contenedor arranca, responde y queda `healthy`, pero en
  `docker compose logs api-clientes` aparece:
  ```
  [1] [INFO] Listening at: http://0.0.0.0:8080 (1)
  ...
  [1] [ERROR] Control server error: [Errno 13] Permission denied: '/home/appuser'
  ```
- **Causa:** Gunicorn 26 abre por defecto un socket de control (lo usa la herramienta `gunicornc`)
  en `$HOME/.gunicorn/gunicorn.ctl`, según `gunicorn --help`:
  ```
  --control-socket PATH   Unix socket path for control interface.
                          [/home/appuser/.gunicorn/gunicorn.ctl]
  --no-control-socket     Disable control socket. [False]
  ```
  El usuario no-root se crea con `useradd -r`, que no crea el directorio home, así que Gunicorn no
  tiene dónde crear el socket.
- **Solución:** se agregó `--no-control-socket` al `CMD` del `Dockerfile`:
  ```dockerfile
  CMD ["sh", "-c", "exec gunicorn --bind 0.0.0.0:${PORT:-8080} --workers 2 --no-control-socket main:app"]
  ```
  El socket de control no se usa. Desactivarlo evita crear un home con permisos de escritura solo
  para eso, y así el usuario de la app sigue sin lugares donde escribir dentro de la imagen.
- **Alternativa descartada:** crear el usuario con home (`useradd -m`). El error desaparece, pero
  queda un servicio escuchando que nadie usa y un directorio con permisos de escritura.
- **Verificación:** con la imagen reconstruida, los logs muestran solo el arranque de Gunicorn y de
  sus 2 workers, sin errores. El contenedor queda `healthy` y el ABM responde GET 200, POST 201,
  PUT 200, DELETE 204 y 404 al pedir el registro borrado.

### 2. Inyección SQL por PyMySQL 1.1.0 y falta de validación de tipos (OWASP A05 / A03)

- **Síntoma:** `pip-audit` reporta `PyMySQL 1.1.0 — PYSEC-2026-502`: *"allows SQL injection if used
  with untrusted JSON input because keys are not escaped by `escape_dict`"*. `main.py` pasaba los
  campos del JSON a la consulta sin revisar su tipo (`nombre = data['nombre']`), así que un objeto
  JSON llegaba como parámetro. Con `cursor.mogrify` (que arma el SQL **sin ejecutarlo**) se confirmó
  que la clave del objeto entra en el SQL sin escapar la comilla:
  ```sql
  INSERT INTO clientes (nombre, email, dni) VALUES ({"x', (SELECT ...), '1')#": '1'}, 'a@x.com', '1')
  ```
  El riesgo es mayor porque el usuario de la base tiene `ALL PRIVILEGES` sobre las 5 bases (ver
  `db/init-scripts/00-databases.sh`).
- **Causa:** una versión vulnerable del driver, sumada a la falta de validación de la entrada.
- **Solución (dos capas):**
  1. `requirements.txt`: `PyMySQL==1.2.3`. Esta versión rechaza los `dict` como parámetro
     (`TypeError: dict can not be used as parameter`). Flask-MySQL 1.5.2 le sigue pasando `db=`, que
     la 1.2.3 acepta como alias obsoleto.
  2. `main.py`: la función `leer_cliente()` valida el body de POST y PUT antes de tocar la base. El
     body tiene que ser un objeto JSON, `nombre` y `email` texto obligatorio, y `dni` texto u omitido.
     Si no, responde **400** con un mensaje JSON. Antes, un body inválido daba 500.
- **Verificación:** `nombre` como objeto, `email` como lista, `dni` numérico, body lista, JSON roto
  o sin `Content-Type` → 400. El ABM normal sigue igual (201/200/204). `pip-audit` ya no reporta
  PyMySQL.

### 3. Endurecimiento: tamaño del body y cabeceras (OWASP A06 / A02)

- **Body sin límite:** la API aceptaba un PUT de 2 MB. Ahora `app.py` define
  `MAX_CONTENT_LENGTH = 16 KB`, y lo que lo supera recibe **413** `{"error":"Body demasiado grande"}`
  (con un `errorhandler(413)` en `main.py`, para responder JSON en lugar de HTML). Verificado: 20 KB → 413;
  10 KB → se procesa normal.
- **Cabecera `Server: gunicorn`:** Gunicorn la agrega siempre (sin versión) y no tiene opción para
  quitarla. No se parcheó: NGINX no reenvía al cliente la cabecera `Server` del backend
  (`proxy_hide_header` por defecto), así que no se ve por la ruta pública.

### 4. `env.example` apuntaba a una base inexistente (`DB_NAME=db`)

- **Síntoma (previsto):** si se copia `env.example` a `.env` completando solo `DB_USER` y
  `DB_PASSWORD`, como indica el README, todos los endpoints de `/clientes` responden 500 y en los
  logs aparece `Unknown database 'db'`. En la prueba local no se vio porque el `.env` ya tenía el
  valor correcto.
- **Causa:** el template tenía `DB_NAME=db`, pero la base se llama `db_clientes`. El fallback de
  `db_config.py` (`os.environ.get('DB_NAME') or 'db_clientes'`) no actúa, porque `"db"` no está
  vacío.
- **Solución:** `DB_NAME=db_clientes` y `DB_PORT=3306` en `env.example`, igual que en `api-pagos`.
  Importa porque `deploy.sh` arma los `.env` en una EC2 nueva.
- **Verificación:** con las variables de `env.example` cargadas, `db_config.py` configura
  `MYSQL_DATABASE_DB=db_clientes`, `MYSQL_DATABASE_HOST=db` y `MYSQL_DATABASE_PORT=3306`. En Docker,
  con un `.env` armado desde `env.example` (completando solo usuario y contraseña), la API queda
  `healthy` y el ABM responde GET 200, POST 201, PUT 200, DELETE 204 y 404 al pedir el borrado.

### Problemas previstos (no llegaron a ser errores)

Se resolvieron en el diseño, antes de que aparecieran:

| Riesgo | Qué habría pasado | Cómo se evitó |
|---|---|---|
| Servidor de desarrollo de Flask | `python main.py` corre `app.run()`, que muestra `WARNING: This is a development server` y no está pensado para producción. | Se usa Gunicorn (`gunicorn main:app`). `main.py` registra las rutas sobre `app`, así que no hubo que tocar el código. |
| HEALTHCHECK sin curl/wget | `python:3.12-slim` no trae ni curl ni wget, así que un `HEALTHCHECK` con esos comandos fallaría siempre. | Se usa `urllib` de Python, que ya está en la imagen. |
| `localhost` vs IPv4 | En `api-pagos`, `localhost` resolvía a `::1` y el healthcheck fallaba (ver api-pagos, error 2). | El healthcheck usa `127.0.0.1`, porque Gunicorn escucha solo en IPv4 (`0.0.0.0`). |
| `PORT` vacío | Con `PORT=` en el `.env`, `os.environ.get('PORT', '8080')` devuelve `''` y la URL del healthcheck queda rota. | El healthcheck usa `os.environ.get('PORT') or '8080'`, y el `CMD` usa `${PORT:-8080}`. Los dos toman 8080 si la variable está vacía. |
| Señales en `docker stop` | Si `sh` queda como PID 1, no reenvía el SIGTERM y Docker mata el contenedor a los 10 s. | `exec gunicorn ...`: Gunicorn reemplaza a `sh` y pasa a ser PID 1. `docker stop` tarda menos de 1 s. |

## api-pagos (Node / Express)

### 1. `npm ci` falla por falta de `package-lock.json`

- **Síntoma:** el enunciado pide instalar las dependencias con `npm ci`, pero el código entregado
  solo trae `package.json`. `npm ci` requiere un lockfile y termina con:
  ```
  npm error code EUSAGE
  npm error The `npm ci` command can only install with an existing package-lock.json or
  npm error npm-shrinkwrap.json with lockfileVersion >= 1.
  ```
- **Causa:** el repositorio de referencia no incluía `package-lock.json`.
- **Solución:** se ejecutó `npm install` (Node 22 / npm 10) en `api-pagos/` para generar el
  `package-lock.json`, que se agrega a Git. `node_modules/` queda fuera de Git (`.gitignore`) y del
  build context (`.dockerignore`). Así el build es reproducible: siempre se instalan las mismas
  versiones (express 4.22.3, mysql2 3.24.4, dotenv 16.6.1).
- **Verificación:** `npm ci --omit=dev` dentro de un contenedor `node:22-alpine` (la misma base que
  la imagen final) instala 80 paquetes y los módulos cargan correctamente. `npm audit` reporta
  0 vulnerabilidades.

### 2. El HEALTHCHECK falla con `localhost` (IPv6 vs IPv4)

- **Síntoma:** el contenedor arranca (`API de pagos escuchando en el puerto 8080`), pero dentro del
  contenedor `wget http://localhost:8080/` devuelve
  `wget: can't connect to remote host: Connection refused`, y el HEALTHCHECK nunca pasa a `healthy`.
- **Causa:** `src/server.js` escucha en `0.0.0.0`, es decir, solo en IPv4. En Alpine, el `wget` de
  busybox resuelve `localhost` a `::1` (IPv6), donde no hay nada escuchando. Con
  `wget http://127.0.0.1:8080/` responde bien.
- **Solución:** el HEALTHCHECK usa `127.0.0.1` en lugar de `localhost`:
  ```dockerfile
  HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD wget -qO- "http://127.0.0.1:${PORT:-8080}/" > /dev/null || exit 1
  ```
  No se tocó el código de la app. NGINX no se ve afectado, porque llega por el nombre del servicio
  (`api-pagos`) y el DNS de Docker devuelve una IPv4.
- **Verificación:** el contenedor pasa a `healthy`, tanto con `PORT=8080` como con `PORT=9090`.

### 3. `db` no inicializa las bases: `/bin/bash^M: bad interpreter` (CRLF en Windows)

Este error es del componente `db`, pero apareció en la prueba integrada de `api-pagos`, porque
`db_pagos` nunca llegaba a crearse.

- **Síntoma:** `docker compose up -d db api-pagos` aborta con
  `dependency failed to start: container tp1-db-1 is unhealthy`. En `docker compose logs db`:
  ```
  running /docker-entrypoint-initdb.d/00-databases.sh
  /docker-entrypoint-initdb.d/00-databases.sh: /bin/bash^M: bad interpreter: No such file or directory
  ```
  MariaDB crea `db_clientes` y el usuario, aborta en ese script y se reinicia. Como el volumen ya
  tiene datos, **no vuelve a correr la inicialización**, así que `db_pagos` y las demás bases no
  se crean nunca.
- **Causa:** en el repo los archivos están con LF (`git ls-files --eol` → `i/lf`), pero Git para
  Windows tiene `core.autocrlf=true` y los convierte a CRLF al hacer checkout (`w/crlf`).
  `docker build` copia esa versión CRLF a la imagen, y el `\r` rompe el shebang de bash. Afecta a
  cualquier imagen de `db` construida desde Windows, incluida la que se publique en Docker Hub.
- **Solución aplicada (local):** convertir a LF la copia de trabajo de `db/init-scripts/*`
  (`sed -i 's/\r$//'`), reconstruir la imagen de `db` y borrar el volumen a medio inicializar
  (`docker compose down -v`, que solo afecta a `tp1_db_data`). `git diff` queda vacío porque el
  contenido ya es idéntico al del repo.
- **Solución definitiva (aplicada):** se agregó en la raíz un
  `.gitattributes` que fuerza LF en los archivos que terminan dentro de imágenes Linux (`*.sh`,
  `*.sql`, `Dockerfile`, etc.).
- **Verificación:** los 6 scripts de init corren, `db` no se reinicia y `db` y `api-pagos` quedan
  `healthy`.

### 4. Endurecimiento: cabecera `X-Powered-By` y tamaño del body (OWASP A02 / A06)

Surgió de la revisión OWASP previa al commit. `npm audit` da 0 vulnerabilidades, y la inyección SQL
no aplica: `mysql2` convierte los objetos a `'[object Object]'` y pone entre comillas lo que llega
en la URL (comprobado con `mysql2.format`, que no ejecuta nada).

- **`X-Powered-By: Express`:** revelaba el framework, y NGINX reenvía esa cabecera tal cual. Se
  agregó `app.disable('x-powered-by')` en `src/server.js`. Verificado: la respuesta ya no la trae.
- **Límite del body:** se fijó explícitamente en `express.json({ limit: '32kb' })` (el valor por
  defecto era 100 kB). `api-clientes` usa 16 KB.
- **Errores en JSON:** si el body pasa el límite o el JSON está mal formado, Express respondía con su
  página HTML. Un middleware de errores devuelve ahora JSON: **413** `Body demasiado grande` y
  **400** `JSON mal formado`. Verificado: un body de 40 KB → 413, uno de 20 KB se procesa normal, y un
  JSON roto → 400. El ABM sigue igual.

### 5. Body sin validar en POST y PUT: datos basura y 500 en lugar de 400 (OWASP A05)

- **Síntoma:** `src/routes/pagos.js` solo revisaba en `POST` que los campos existieran, y en `PUT`
  no revisaba nada. Con mysql2 3.24.4 (comprobado con `mysql2.format`, que no ejecuta nada):
  - `{"monto_ars": 1, "medio_pago": {}}` se guardaba con `medio_pago = '[object Object]'` y
    respondía **201**;
  - un array se expande en varios valores (`VALUES (1, 2, NULL, 'x')`), y la consulta fallaba con
    **500**;
  - `PUT {}` llamaba igual a la API de tipo de cambio con `undefined` e intentaba guardar `NULL` en
    `monto_ars` (`NOT NULL`), y respondía **500**.
- **Causa:** faltaba validar los tipos. No es una inyección SQL, porque mysql2 escapa los valores
  (ver el error 4), pero entraban datos inválidos y los errores del cliente llegaban como fallas
  del servidor.
- **Solución:** la función `leerPago()` valida el body de `POST` y `PUT` **antes** de llamar a la API
  externa. Es el mismo criterio que `leer_cliente()` en `api-clientes`:
  - el body tiene que ser un objeto JSON;
  - `monto_ars` tiene que ser un número finito o un texto numérico (`"50000"`, que antes se
    aceptaba);
  - `medio_pago` tiene que ser un texto no vacío.
  Si no se cumple, responde **400** con `{"error": "..."}`. El frontend manda `monto_ars` como número,
  así que no se ve afectado.
- **Verificación (Node 22.23.3 local, sin DB):** objeto, array, texto no numérico, `1e999`,
  `medio_pago` vacío u objeto, body array, `PUT {}` y un POST sin `Content-Type` → 400, sin llamar a
  la API externa. Un body válido pasa la validación, llama a la API externa y llega a la consulta.
  Sin base disponible responde 500 `Error al crear el pago`, que es lo esperado.
- **Verificación en Docker (Docker Desktop 29.8.0):** con la imagen reconstruida y `db` en la misma
  red, el ABM sigue igual: POST 201 con `monto_usd` calculado, PUT 200, DELETE 204, GET del borrado
  404 y PUT a un id inexistente 404. Con MariaDB real, `medio_pago: {}`, `monto_ars: [1, 2]` y
  `PUT {}` responden 400, y el registro queda sin cambios.

## web (Vite + NGINX)

### 1. `npm ci` necesita `package-lock.json`

- **Síntoma:** el front solo traía `package.json`, así que `npm ci` en la etapa `build` fallaba.
  Es el mismo caso que el error 1 de `api-pagos`.
- **Solución:** se generó el lockfile con `npm install --package-lock-only` y se commiteó. Fija
  `vite` en 5.4.21 y hace que el build sea reproducible.

### 2. El HEALTHCHECK marca `unhealthy` por el certificado autofirmado

- **Síntoma:** NGINX respondía bien desde afuera (`curl -k` → 200), pero el contenedor quedaba
  `unhealthy`. Adentro, `wget --spider https://127.0.0.1:8443/` fallaba con
  `ssl_client: SSL_connect ... certificate verify failed`.
- **Causa:** se asumió que el `wget` de busybox no valida certificados. En Alpine 3.24, busybox
  delega el TLS en `ssl_client` (OpenSSL), que **sí** valida, y el certificado es autofirmado.
- **Solución:** `wget -q --spider --no-check-certificate`. Saltear la validación es aceptable
  porque es una llamada a `127.0.0.1` dentro del propio contenedor.

### 3. `web` se reinicia en loop con `read_only`: `mkdir() "/var/cache/nginx/client_temp" failed (13: Permission denied)`

- **Síntoma:** con `read_only: true` y `tmpfs: [/tmp, /var/cache/nginx]` en Compose, `web` quedaba
  `Restarting (1)`. En `docker compose logs web` aparecía ese `[emerg]`.
- **Causa:** el `chown nginx` sobre `/var/cache/nginx` del `Dockerfile` no sirve cuando se monta un
  `tmpfs` encima, porque el `tmpfs` se crea vacío y como root. NGINX corre como `nginx` (uid 101) y
  no puede crear sus carpetas temporales.
- **Solución:** montar los `tmpfs` con el dueño correcto:
  `/var/cache/nginx:uid=101,gid=101,mode=0700` (lo mismo para `/tmp`, donde queda el pid).
- **Verificación:** `web` queda `healthy`, y `touch` sobre la config o sobre `dist/` responde
  `Read-only file system`.

### 4. CVE de la imagen base `nginx:1.30-alpine`

- **Síntoma:** Trivy reportó `libexpat` (CVE-2026-93990, HIGH) y `libpng` (CVE-2026-46675).
- **Solución:** `apk upgrade --no-cache` en el `Dockerfile`. Después, Trivy informa 0
  vulnerabilidades. Detalle en `SEGURIDAD.md`.

### 5. Compose rechaza `pids_limit`: `can't set distinct values on 'pids_limit' and 'deploy.resources.limits.pids'`

- **Síntoma:** al agregar `pids_limit: 100` al servicio `web`, `docker compose config` falla con
  ese mensaje y `up` no recrea el contenedor (sigue corriendo el anterior, sin los cambios).
- **Causa:** el servicio ya usa `deploy.resources.limits` para CPU y memoria. Compose no acepta el
  tope de procesos en las dos formas a la vez.
- **Solución:** declararlo dentro del mismo bloque: `limits: {cpus: "0.25", memory: 64M, pids: 100}`.
- **Verificación:** `docker inspect -f '{{.HostConfig.PidsLimit}}'` → `100`.

### 6. Las páginas de error devuelven 403: `open() ".../errors/error.json" failed (13: Permission denied)`

- **Síntoma:** después de configurar `error_page ... /_error.json`, todos los errores de NGINX
  (502, 404, 413, 429) pasaron a responder **403** con la página por defecto.
- **Causa:** `COPY --chmod=644 nginx/error.json /usr/share/nginx/errors/error.json` crea la carpeta
  `errors/` y le aplica **el mismo modo 644**. Una carpeta sin permiso de ejecución no se puede
  abrir (`drw-r--r--`), así que el usuario `nginx` no llega al archivo.
- **Solución:** copiar el archivo a una carpeta que ya existe con permisos correctos:
  `/etc/nginx/error.json`.
- **Verificación:** `/api/tarjetas` (sin backend) → 502 con `{"error":"No se pudo procesar el pedido"}`
  y `Content-Type: application/json`.

### Problemas previstos (no llegaron a ser errores)

- **Puerto 80 del server por defecto:** la imagen oficial trae `conf.d/default.conf` escuchando
  en 80. El `nginx.conf` del grupo se copia **con ese mismo nombre** para reemplazarlo. Se
  verificó que no hay nada escuchando en 80.
- **CRLF en scripts:** para que `40-generar-certificado.sh` no se rompa como `00-databases.sh`
  (error 3 de `api-pagos`), `web/.gitattributes` fuerza LF y el `Dockerfile` además corre
  `sed 's/\r$//'` sobre el script y la config.
- **NGINX no arranca si falta una API:** con `proxy_pass http://api-facturas:8080` fijo, NGINX
  resuelve el nombre al arrancar y termina con `host not found in upstream` si ese contenedor no
  existe. Con `resolver 127.0.0.11` + `set $upstream`, resuelve en cada pedido: mientras faltaban
  `api-facturas` y `api-tarjetas`, esas rutas respondían 502 y el resto funcionaba.

## api-transacciones (Go)

### 1. `/api/transacciones` responde 500 aunque el contenedor está `healthy`

- **Síntoma:** en la prueba integrada con los 7 servicios (2026-10-03), las otras 4 APIs
  respondían 200 por NGINX, pero `GET /api/transacciones` devolvía 500 y el `POST` respondía
  `Error al crear la transaccion`. El contenedor figuraba `healthy`. En `docker compose logs db`
  aparecía:
  ```
  [Warning] Access denied for user 'appuser'@'172.20.0.4' (using password: YES)
  ```
- **Causa:** el `.env` local de `api-transacciones` tenía un `DB_PASSWORD` distinto del
  `MYSQL_PASSWORD` de `db/.env`. El HEALTHCHECK consulta `/`, que no toca la base, así que no
  detectaba el problema.
- **Solución:** usar en `DB_USER` / `DB_PASSWORD` los mismos valores que `MYSQL_USER` /
  `MYSQL_PASSWORD` de `db/.env`. El `env.example` ahora trae `DB_HOST=db`, `DB_PORT=3306` y
  `DB_NAME=db_transacciones`, y aclara de dónde salen las credenciales.
- **Verificación:** `GET` → 200 y `POST` → 201. Como ipapi.co respondía `RateLimited`, el alta se
  guardó con `pais: ""`, que es el comportamiento esperado cuando falla la API externa.
- **Lección:** un healthcheck sobre `/` solo prueba que el proceso escucha. En `api-facturas`
  el HEALTHCHECK consulta `/facturas`, que sí pasa por la base. Para las demás APIs, sumar una
  ruta `/health` que verifique la conexión queda como mejora (ver README).

## deploy.sh

Los tres errores aparecieron al probar el script **sin AWS**, contra un contenedor que simula una
EC2 recién creada (SSH, usuario con `sudo` y sin Docker), con `ubuntu:26.04` y `amazonlinux:2023`.
En la EC2 real habrían aparecido en plena sesión del Learner Lab, con el tiempo corriendo.

### 1. Ubuntu 26.04 ignora `sudo -E`: `sudo: preserving the entire environment is not supported`

- **Síntoma:** al instalar Docker salían esos avisos y una cascada de errores de `debconf`
  (`unable to initialize frontend: Dialog`, `Readline`, `Teletype`) antes de que terminara.
- **Causa:** el script hacía `export DEBIAN_FRONTEND=noninteractive` y después `sudo -E apt-get`.
  Ubuntu 26.04 trae `sudo-rs` (la reimplementación en Rust), que no soporta `-E`. La variable no
  llegaba a `apt-get`, y `debconf` intentaba abrir un diálogo sin terminal.
- **Solución:** pasar la variable en el mismo comando:
  `sudo DEBIAN_FRONTEND=noninteractive apt-get ...`, que funciona con `sudo` y con `sudo-rs`.
- **Verificación:** la instalación en Ubuntu 26.04 muestra solo las versiones de Docker y Compose.

### 2. `Cannot connect to the Docker daemon` en `docker compose pull`

- **Síntoma:** el paso 4 terminaba con "Docker y Docker Compose listos", pero el paso 6 fallaba
  porque el daemon no estaba corriendo. El script no daba un mensaje claro.
- **Causa:** sin `systemd` como proceso principal, que es el caso del contenedor de prueba,
  `systemctl enable --now docker` habilita el servicio pero no lo arranca, y devuelve éxito igual.
  Además, la espera de `docker info` no fallaba al agotarse.
- **Solución:** si existe `/run/systemd/system` se usa `systemctl`; si no, se arranca `dockerd` en
  segundo plano. Después se espera hasta 60 s a que `docker info` responda; si no responde, el
  script falla diciendo que el daemon no responde. Los errores de `pull`/`up` ahora se muestran
  con un `ERROR:` explícito.
- **Verificación:** en una instancia nueva, el paso 4 termina con el daemon funcionando y el paso 6
  descarga las 7 imágenes. En una EC2 real (con `systemd`), el camino es `systemctl enable --now`.

### 3. `Host key verification failed` por los espacios en la ruta del repo

- **Síntoma:** con una instancia nueva en la misma dirección que una anterior, que es lo que pasa
  cuando el Learner Lab reutiliza una IP, el script no conectaba por SSH:
  ```
  ssh: Offending ED25519 key in /d/Facultad:1
  ssh: Host key for [localhost]:2222 has changed and you have requested strict checking.
  ```
  Además, había aparecido un archivo suelto llamado `/d/Facultad`.
- **Causa:** la ruta del repo tiene espacios (`D:\Facultad cuarto año\...`). `ssh` corta el valor
  de `-o UserKnownHostsFile=<ruta>` en el primer espacio, así que guardaba las huellas en
  `/d/Facultad`. Mientras tanto, `ssh-keygen -R` borraba la huella vieja del archivo correcto
  (`.deploy/known_hosts`), que `ssh` nunca leía.
- **Solución:** comillas dentro del valor de la opción:
  `-o "UserKnownHostsFile=\"$KNOWN_HOSTS\""`.
- **Verificación:** con una huella vieja guardada y una instancia nueva en la misma dirección, el
  script borra la huella, acepta la nueva y despliega. No se vuelve a crear `/d/Facultad`.
- **Lección:** probar los scripts desde una ruta con espacios. En Windows es lo normal (`Program
  Files`, nombres con tilde), y en Linux casi nunca pasa.

## AWS Academy Learner Lab

Aparecieron durante el despliegue real del 2026-10-07. El `deploy.sh` en sí funcionó en el primer
intento; los dos problemas fueron al consultar los datos de la instancia con la AWS CLI.

### 1. `Unable to locate credentials` en la terminal del Learner Lab

- **Síntoma:** al correr `aws ec2 describe-instances` en la terminal que muestra la página del
  Learner Lab, junto a las instrucciones, la AWS CLI respondía:
  ```
  Unable to locate credentials. You can configure credentials by running "aws configure".
  ```
- **Causa:** esa terminal no tenía las credenciales de la sesión cargadas en `~/.aws/credentials`.
  El Learner Lab las muestra en **AWS Details → AWS CLI: Show**, pero no las configura solas en
  esa terminal. Además, son temporales: cambian en cada sesión del sandbox.
- **Solución:** usar **AWS CloudShell** (ícono `>_` de la barra superior de la consola web), que
  ya viene autenticado con el usuario de la sesión y con la región `us-east-1`. Ahí los mismos
  comandos funcionaron sin configurar nada (ver la
  [captura](./docs/capturas/10-aws-cli.png)).
- **Alternativa:** copiar el bloque de **AWS CLI: Show** a `~/.aws/credentials` y definir
  `AWS_DEFAULT_REGION=us-east-1`. Hay que repetirlo en cada sesión.

### 2. La terminal del Learner Lab no permite pegar texto

- **Síntoma:** al intentar la alternativa anterior, no se podía pegar el bloque de credenciales en
  la terminal del lab, y tipear a mano una clave de 40 caracteres y un token de sesión largo no es
  viable.
- **Solución:** la misma: CloudShell, que sí acepta pegar con Ctrl+Shift+V o clic derecho → Paste.
- **Lección:** las credenciales de AWS no se pegan en chats, capturas ni archivos del repositorio.
  Las capturas de esta sesión se revisaron antes de subirlas para confirmar que ninguna muestra la
  *Access Key*, la *Secret Key* ni la llave `.pem`.
