# Seguridad

Medidas de seguridad aplicadas en el despliegue de FinTech Nova: los 7 componentes (`db`, las 5
APIs y `web`), la orquestación y el despliegue con `deploy.sh`. Los datos de la sesión real del
Learner Lab (instancia, VPC, subred y reglas efectivas del Security Group) están en
[AWS_EC2.md](./AWS_EC2.md).

## 1. Gestión de secretos

- **Nada hardcodeado en las imágenes ni en Compose.** Cada API lee sus credenciales de la base
  (`DB_USER`, `DB_PASSWORD`) desde variables de entorno, que Compose carga con `env_file`:
  ```yaml
  api-clientes:
    env_file: [./aplicaciones-contenedores/api-clientes/.env]
  ```
- **Plantillas sin secretos.** Cada componente tiene un `env.example` con los valores no sensibles
  (`DB_HOST=db`, `DB_PORT=3306`, `DB_NAME`, `PORT=8080`) y las credenciales vacías. El `.env` real
  se crea copiando la plantilla y usa las mismas credenciales que `MYSQL_USER` / `MYSQL_PASSWORD` de
  `db/.env`.
- **Fuera de Git:** el `.gitignore` de la raíz ignora `.env` y `.env.*` (salvo `env.example`).
  Antes de cada commit se verifica con `git status` y
  `git check-ignore -v aplicaciones-contenedores/*/.env`.
- **Fuera de las imágenes:** los `.dockerignore` de todos los componentes excluyen `.env` y
  `.env.*` (los de `db` y `api-transacciones` son listas blancas: solo entra lo que el build
  necesita). Así las imágenes públicas de Docker Hub no contienen credenciales; verificado con el
  escaneo de secretos de la [sección 3](#escaneo-de-secretos-antes-de-publicar-2026-10-03).
- **Cuidado con `docker compose config`:** muestra los `.env` expandidos, contraseñas incluidas.
  Para validar se usa `docker compose config --quiet`, y su salida no se pega en issues ni en
  capturas.
- **Riesgo conocido:** `db_config.py` (api-clientes) y `src/db.js` (api-pagos) traen contraseñas
  de respaldo escritas en el código (`testuserpass` / `apppass`) para correr sin Docker. En los
  contenedores no se usan, porque el `.env` las reemplaza. Se dejaron para no modificar el código de
  referencia.
- **Cómo llegan a la EC2:** `deploy.sh` empaqueta `docker-compose.yml` y los 6 `.env` con `tar` y
  los manda **por el canal cifrado de SSH**, sin pasar por Git ni por Docker Hub. En la instancia
  se extraen con `umask 077` y quedan en modo `600` (solo los lee el usuario que despliega). `web`
  no tiene `.env`: no maneja secretos.
- **Controles antes de desplegar:** `deploy.sh` verifica que existan los 6 `.env`, que `db/.env`
  tenga `MYSQL_ROOT_PASSWORD`, `MYSQL_USER` y `MYSQL_PASSWORD`, y que cada API use `DB_HOST=db` y
  el mismo usuario y clave que la base. Los valores se comparan sin imprimirse. Así se evita el
  error de `ERRORES.md` (api-transacciones 1), donde una clave distinta daba 500 con el contenedor
  `healthy`.
- **Llave SSH:** con `--crear-ec2`, el par de llaves se crea en AWS y la clave privada se guarda en
  `~/.ssh/fintech-nova-<fecha>.pem` con modo `600`, **fuera del repositorio**. `.gitignore` excluye
  `*.pem` y la carpeta `.deploy/`, donde el script guarda los datos de la instancia (sin secretos)
  y sus huellas SSH.
- **Huella del servidor SSH:** el script usa `StrictHostKeyChecking=accept-new` con un
  `known_hosts` propio (`.deploy/known_hosts`). Acepta la huella de una instancia nueva y rechaza
  una huella **cambiada** durante la sesión. Como el Learner Lab reutiliza IPs entre sesiones, la
  huella vieja de esa IP se borra al empezar cada despliegue.

## 2. Certificado TLS

El TLS termina en `web` (NGINX), que es la única entrada pública: **HTTPS en el puerto 8443**. El
puerto 80 no se escucha ni se publica. Las APIs no publican puertos: solo se accede a ellas por
HTTP dentro de la red interna de Compose, detrás de NGINX.

**Cuándo se genera: en runtime, al primer arranque del contenedor.** La imagen oficial de NGINX
ejecuta los scripts de `/docker-entrypoint.d/` antes de iniciar el servidor.
`web/nginx/40-generar-certificado.sh` revisa si hay un certificado en `/etc/nginx/certs`. Si no hay,
genera uno autofirmado con OpenSSL: RSA 2048, SHA-256, 365 días, `CN=fintech-nova.local` y SAN con
`localhost` y `127.0.0.1`. No hay dominio y la IP de la EC2 cambia entre sesiones, así que el nombre
es genérico.

**Por qué runtime y no build-time:** la imagen de `web` es pública en Docker Hub. Si la clave se
generara en el `Dockerfile`, quedaría embebida en una capa y cualquiera podría descargarla y
descifrar el tráfico (o hacerse pasar por el servidor). Con runtime:

- La imagen publicada tiene `/etc/nginx/certs` vacío. Verificado con
  `docker run --rm --entrypoint ls <imagen> -la /etc/nginx/certs`.
- La clave solo existe dentro del volumen `web_certs` de la EC2 donde se generó. Cada despliegue
  tiene su propia clave.
- No hace falta copiar ni transferir la clave: nunca pasa por Git, por `scp` ni por la máquina de
  quien despliega.

**Cómo se protege la clave:**

- Se crea con `umask 077`: `tls.key` queda en modo `400` (solo lectura), dueño `nginx` (uid 101), dentro de una
  carpeta `700`. El certificado público queda en `644`.
- El volumen `web_certs` hace que la clave persista entre `docker compose up` y reinicios. Si el
  volumen ya tiene un certificado, el script lo reutiliza y no genera otro. Para rotarla:
  `docker compose down`, `docker volume rm <proyecto>_web_certs` y `docker compose up -d`. También
  hay que rotarla antes de que venza (365 días).
- Si el grupo quisiera usar un certificado propio, alcanza con montarlo en `/etc/nginx/certs`
  (`tls.crt` y `tls.key`): el script lo detecta y no lo pisa.
- Defensa en profundidad: el `.gitignore` de la raíz ignora `*.pem`, `*.key` y `*.crt` (verificado
  con `git check-ignore -v`, por ejemplo sobre `web/nginx/certs/server.key`), y los `.dockerignore`
  de las APIs y de `web` excluyen esos mismos patrones del build context.

**Configuración TLS de NGINX** (`web/nginx/nginx.conf`): solo TLS 1.2 y 1.3 (en 1.2, únicamente cifrados ECDHE con AES-GCM o ChaCha20), HTTP/2,
`ssl_session_tickets off`. Si alguien habla HTTP plano contra el 8443, NGINX responde 400 y no
sirve contenido.

**Verificación:** `curl -k` es apropiado porque el certificado es autofirmado, y la advertencia del
navegador es esperada. `openssl s_client -connect <host>:8443` muestra `subject=CN=fintech-nova.local`
y el SAN.

## 3. Escaneos de seguridad

Corridos localmente: el 2026-09-27 (api-clientes y api-pagos), el 2026-09-30 (web) y el 2026-10-03 (api-facturas, api-transacciones, api-tarjetas y db, más el escaneo de secretos de las 7 imágenes antes de publicarlas).

| Herramienta | Componente | Resultado |
|---|---|---|
| `npm audit --omit=dev` | api-pagos | **0 vulnerabilidades.** |
| `pip-audit -r requirements.txt` | api-clientes | Primero: 20 avisos en 4 paquetes. Después de subir PyMySQL: 18, en Werkzeug 2.3.7, Flask 2.3.3 y python-dotenv 1.0.1, **ninguno explotable en este código** (ver tabla). |
| Revisión manual OWASP Top 10 (2025) | api-clientes y api-pagos | Una inyección SQL en api-clientes (corregida) y endurecimientos menores. Detalle en la sección 5. |
| Trivy 0.74.0 `image` (vulnerabilidades, secretos, configuración) | api-clientes y api-pagos | 0 CRITICAL, 0 secretos, 0 errores de configuración. api-pagos: **0 vulnerabilidades** después de las mejoras. Detalle abajo. |
| Trivy 0.74.0 `config` | los 7 `Dockerfile` | **0 errores de configuración** (en `db`, un falso positivo explicado abajo). |
| Trivy 0.74.0 `image` | api-facturas, api-transacciones, api-tarjetas y db | 0 secretos. **api-facturas: 7 CRITICAL** en Spring Boot 3.3.4 y **db: 55 HIGH** en la imagen base, ambos *pendientes*. api-tarjetas: 0; api-transacciones: 1 LOW. Detalle en los hallazgos 3 a 5. |
| Trivy 0.74.0 `image --scanners secret` + búsqueda manual | las 7 imágenes publicadas | **0 secretos** (ver "Escaneo de secretos antes de publicar"). |

Avisos que quedan en api-clientes y por qué no aplican:

| Paquete | Aviso | Por qué no se puede explotar |
|---|---|---|
| Werkzeug | DoS al procesar `multipart/form-data` | La API solo lee JSON (`get_json`) y nunca procesa formularios. |
| Werkzeug | RCE en el debugger | El debugger no se usa: la app corre con Gunicorn, sin modo debug. |
| Werkzeug | `safe_join` con rutas y nombres de dispositivo de Windows | Afecta solo a Windows, y la app no usa `safe_join` ni `send_from_directory`. |
| Flask | Falta `Vary: Cookie` al acceder a `session` | La app no usa `session`. |
| python-dotenv | `set_key()` sigue symlinks | La app solo usa `load_dotenv()`. |

### Trivy

Corrido con la imagen oficial `aquasec/trivy:0.74.0` y la base de vulnerabilidades del
2026-09-27, desde la raíz del repo:

```sh
# Imagen: vulnerabilidades (SO + paquetes), secretos y configuración
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v trivy-cache:/root/.cache/ \
  aquasec/trivy image --scanners vuln,secret,misconfig ${DOCKERHUB_USER}/fintech-nova-api-clientes:1.0.0
# Dockerfile: malas configuraciones
docker run --rm -v "$PWD/aplicaciones-contenedores/api-clientes:/src:ro" aquasec/trivy config /src
```

Lo mismo para `api-pagos`. Se corrió dos veces: sobre las imágenes originales y después de aplicar
los arreglos.

#### Resumen

| Imagen | Capa | Primer escaneo (C / H / M / L) | Después de los arreglos (C / H / M / L) |
|---|---|---|---|
| api-clientes | Sistema operativo (Debian 13.7, base `python:3.12-slim`) | 0 / 44 / 53 / 57 (+2 sin clasificar) | igual (sin arreglo publicado, ver abajo) |
| api-clientes | Paquetes de Python | 0 / 1 / 17 / 3 | **0 / 1 / 12 / 2** |
| api-pagos | Sistema operativo (Alpine 3.24.2, base `node:22-alpine`) | 0 / 0 / 0 / 0 | 0 / 0 / 0 / 0 |
| api-pagos | Paquetes de Node | 0 / 8 / 4 / 1 | **0 / 0 / 0 / 0** |
| web | Sistema operativo (Alpine 3.24.2, base `nginx:1.30-alpine`) | 0 / 1 / 0 / 0 (+1 sin clasificar) | **0 / 0 / 0 / 0** |
| api-facturas | Sistema operativo (Alpine 3.24.2, base `eclipse-temurin:21-jre-alpine`) | 0 / 0 / 0 / 0 | — |
| api-facturas | Dependencias Java (el `.jar` de Spring Boot 3.3.4) | **7 / 30 / 32 / 14** | *pendiente* (ver [Hallazgo 3](#hallazgo-3--api-facturas-spring-boot-334-con-7-critical-pendiente)) |
| api-transacciones | Sistema operativo (Alpine 3.24.2) | 0 / 0 / 0 / 0 | — |
| api-transacciones | Binario de Go | 0 / 0 / 0 / 1 | *pendiente* (1 LOW, ver abajo) |
| api-tarjetas | Sistema operativo (Alpine 3.24.2, base `dotnet/aspnet:8.0-alpine`) | 0 / 0 / 0 / 0 | — |
| api-tarjetas | Runtime .NET 8 y dependencias (`MySqlConnector`) | 0 / 0 / 0 / 0 | — |
| db | Sistema operativo (RHEL 9.8, base `mariadb:11.8.9-ubi9`) | 0 / 55 / 379 / 106 | *pendiente* (ver [Hallazgo 4](#hallazgo-4--db-paquetes-de-la-imagen-base-sin-actualizar-pendiente)) |
| db | `gosu` de la imagen oficial (binario de Go) | 1 / 21 / 21 / 2 | igual (viene de la imagen base) |

Las filas de api-facturas, api-transacciones, api-tarjetas y db se escanearon el 2026-10-03 con la
misma versión de Trivy, sobre las imágenes publicadas.

C = CRITICAL, H = HIGH, M = MEDIUM, L = LOW.

**web** (escaneado el 2026-09-30 con Trivy 0.74.0, corrido desde su imagen de Docker
`aquasec/trivy:0.74.0`):

- `libexpat` 2.8.4 (CVE-2026-93990, HIGH) y `libpng` 1.6.58 (CVE-2026-46675, sin clasificar)
  venían en la imagen base, pero Alpine ya tenía la versión corregida. Se arreglaron con
  `apk upgrade --no-cache` en el `Dockerfile`, en la misma capa que el `apk add`.
- `npm audit` sobre el front reporta 2 avisos (1 HIGH) en `vite` 5.4 y `esbuild`. Todos afectan
  **al servidor de desarrollo** (`npm run dev`): lectura de archivos, CORS, `launch-editor` en
  Windows. En la imagen no hay Node ni Vite, solo los estáticos de `dist/` servidos por NGINX, así
  que no aplican al despliegue. Se aceptan: arreglarlos obliga a pasar a Vite 8 (cambio
  incompatible) sin beneficio para producción. Recomendación: no exponer `npm run dev` fuera de
  `localhost`.

- En los dos escaneos: **0 secretos** en las imágenes y **0 errores de configuración** en las
  imágenes y en los `Dockerfile` (`trivy config`).
- Ninguno de los arreglos toca el código de las apps.

#### Hallazgo 1 — api-pagos: `npm` de la imagen base con 13 vulnerabilidades (8 HIGH)

- **Qué se encontró:** Trivy reportó 13 vulnerabilidades (8 HIGH, 4 MEDIUM, 1 LOW) en paquetes de
  Node. Los HIGH:

  | Paquete | CVE | Tipo |
  |---|---|---|
  | brace-expansion 2.0.2 | CVE-2026-13149, CVE-2026-14257, CVE-2026-69152 | Denegación de servicio |
  | pacote 19.0.2 y 20.0.1 | CVE-2026-9496 | Denegación de servicio |
  | picomatch 4.0.3 | CVE-2026-33671 | ReDoS (expresión regular) |
  | ip-address 10.1.0 | CVE-2026-69192 | Parseo inconsistente de IPs |
  | sigstore 3.1.0 | CVE-2026-48815 | Acepta certificados no autorizados |

- **Causa:** **todas** estaban en `/usr/local/lib/node_modules/npm`, es decir, en las dependencias
  internas del `npm` que trae `node:22-alpine`. Ninguna estaba en el código ni en
  `/app/node_modules` (express, mysql2, dotenv), que ya había salido limpio en `npm audit`. `npm`
  solo se usa en el build (`npm ci`), porque la app corre con `node src/server.js`.
- **Arreglo:** en `aplicaciones-contenedores/api-pagos/Dockerfile`, borrar `npm` en el mismo
  `RUN` que instala las dependencias:
  ```dockerfile
  RUN npm ci --omit=dev && npm cache clean --force \
    && rm -rf /usr/local/lib/node_modules/npm /usr/local/bin/npm /usr/local/bin/npx
  ```
- **Verificación:** Trivy pasa a **0 vulnerabilidades** en toda la imagen. `which npm npx` no
  encuentra nada, `express`, `mysql2` y `dotenv` cargan, el contenedor queda `healthy` y el ABM
  responde igual.
- **Límite:** la imagen sigue pesando 253 MB. `npm` vive en una capa de la imagen base, y un `rm`
  en una capa posterior lo quita del sistema de archivos final sin liberar esos bytes (ver
  `aplicaciones-contenedores/api-pagos/MULTISTAGE.md`).

#### Hallazgo 2 — api-clientes: `pip` duplicado dentro del venv

- **Qué se encontró:** entre los paquetes de Python, `pip` 25.0.1 aparecía con 12 hallazgos
  (10 MEDIUM, 2 LOW). En realidad eran 6 CVE (CVE-2025-8869, CVE-2026-13346, CVE-2026-1703,
  CVE-2026-3219, CVE-2026-6357 y CVE-2026-8643) reportados **dos veces**: una en
  `/usr/local/lib/python3.12` y otra en `/opt/venv/lib/python3.12`.
- **Causa:** `python -m venv` instala una copia propia de `pip` dentro del venv. El stage `builder`
  la usaba para instalar las dependencias, y el runtime la heredaba al copiar `/opt/venv`, aunque
  en ejecución no se instala nada. Además, esa copia ocupaba 13 de los 22 MB del venv.
- **Arreglo:** en `aplicaciones-contenedores/api-clientes/Dockerfile`, desinstalar `pip` del venv
  al terminar la instalación, todavía en el `builder`:
  ```dockerfile
  RUN pip install --no-cache-dir -r requirements.txt && pip uninstall -y pip
  ```
- **Verificación:**
  - Los paquetes de Python bajan de 21 hallazgos a 15, sin el `pip` del venv.
  - El venv pasa de 22 MB a 8.4 MB y la imagen de 206 a **188 MB**, menos que una versión de un
    solo stage (ver `aplicaciones-contenedores/api-clientes/MULTISTAGE.md`).
  - Las dependencias se importan bien, el contenedor queda `healthy` y el ABM y las pruebas de
    validación dan lo mismo que antes.

#### Lo que queda sin arreglar y por qué se acepta

| Hallazgo (api-clientes) | Por qué no se arregló | Por qué no se puede explotar acá |
|---|---|---|
| **Sistema operativo Debian:** 156 hallazgos, que son 68 CVE distintos, porque el mismo CVE aparece en varios paquetes. Los HIGH son 8: util-linux (CVE-2026-76642, CVE-2026-78408, CVE-2026-78409, CVE-2026-78410, en `mount` y `nsenter`), acl (CVE-2026-54369), ncurses (CVE-2025-69720), systemd-homed (CVE-2026-16742) y perl Archive::Tar (CVE-2026-9538). | **No hay arreglo:** Trivy muestra 0 versiones corregidas publicadas por Debian. | Afectan a herramientas del sistema (mount, nsenter, systemd-homed, Archive::Tar) o a librerías que la app no usa para procesar entradas externas, y el proceso corre sin root. Se corrigen reconstruyendo la imagen cuando Debian publique las versiones nuevas. |
| **Werkzeug 2.3.7** (1 HIGH: CVE-2024-34069, RCE en el debugger; 6 MEDIUM), **Flask 2.3.3** y **python-dotenv 1.0.1** | Arreglarlos implica pasar a Werkzeug y Flask 3.x, un salto de versión mayor que exige volver a probar la app. | Son los mismos avisos de `pip-audit` (tabla de arriba): no hay debugger, formularios multipart, `session`, `safe_join` ni `set_key`. |
| **`pip` de la imagen base** (`/usr/local`, los mismos 6 CVE) | Viene en la capa de `python:3.12-slim`. | La app no instala paquetes en ejecución. |

#### Hallazgo 3 — api-facturas: Spring Boot 3.3.4 con 7 CRITICAL (*pendiente*)

- **Qué se encontró:** 83 vulnerabilidades (7 CRITICAL, 30 HIGH) en las dependencias Java del
  `.jar`. **Todas tienen versión corregida.** Por paquete (CRITICAL + HIGH): `tomcat-embed-core`
  10.1.30 (21, entre ellos los 7 CRITICAL), `jackson-databind` y `jackson-core` 2.17.2 (8),
  `spring-webmvc`, `spring-core` y `spring-expression` 6.1.13 (5), `spring-boot` 3.3.4 (2) y
  `spring-data-commons` (1).
- **Causa:** el `pom.xml` usa `spring-boot-starter-parent` **3.3.4** (2024), que fija esas versiones
  de Tomcat, Jackson y Spring. La imagen base (`eclipse-temurin:21-jre-alpine`) sale limpia.
- **Riesgo:** `api-facturas` no es accesible desde afuera: solo le llega lo que NGINX reenvía de
  `/api/facturas` (métodos GET/POST/PUT/DELETE, body de hasta 64 KB, rate limit). Igual son
  vulnerabilidades del servidor HTTP que procesa esos pedidos. Por ejemplo, la más conocida
  (CVE-2025-24813, Tomcat) necesita el servlet por defecto con escritura habilitada, que Spring
  Boot no habilita. Las demás no se analizaron una por una.
- **Arreglo propuesto:** subir `spring-boot-starter-parent` a la última 3.5.x, que trae Tomcat,
  Jackson y Spring corregidos. No cambia la lógica de negocio, pero hay que volver a probar el ABM,
  reconstruir y volver a publicar la imagen, y repetir Trivy. Queda para que lo decida el
  responsable de `api-facturas`.

#### Hallazgo 4 — db: paquetes de la imagen base sin actualizar (*pendiente*)

- **Qué se encontró:** 540 hallazgos en paquetes de RHEL 9.8 (0 CRITICAL, 55 HIGH): `rsync`,
  `libevent`, `openssl`, `expat`, `pcre2`, `curl`, entre otros. **98 tienen versión corregida**; el
  resto todavía no tiene arreglo de Red Hat. Además, el binario `gosu` de la imagen oficial (lo usa
  el entrypoint para bajar de root a `mysql`) está compilado con una versión vieja de Go: 1
  CRITICAL y 21 HIGH en la librería estándar.
- **Causa:** el enunciado fija la imagen `mariadb:11.8.9-ubi9`, que se publicó antes de esos
  parches. El `Dockerfile` de `db` no actualiza paquetes.
- **Riesgo:** MariaDB no publica puertos: solo la alcanzan las 5 APIs por la red `backend`. La
  mayoría de los paquetes afectados son herramientas que el servidor no usa (`rsync`, `curl`,
  `perl-DBI`).
- **Arreglo propuesto:** agregar `RUN microdnf update -y && microdnf clean all` al `Dockerfile` de
  `db`, igual que el `apk upgrade` de `web`, para aplicar los 98 parches disponibles. `gosu` solo se
  corrige cuando MariaDB publique una imagen nueva.

#### Hallazgo 5 — api-transacciones: 1 LOW en una dependencia de Go

`filippo.io/edwards25519` v1.1.0 (CVE-2026-26958, LOW), dependencia indirecta del driver de MySQL.
Se corrige con `go get filippo.io/edwards25519@v1.1.1` y reconstruyendo la imagen. Queda
*pendiente*, por bajo riesgo: la API no usa criptografía de curvas elípticas.

#### api-tarjetas

0 vulnerabilidades en el sistema operativo, el runtime de .NET 8 y `MySqlConnector` 2.3.7.

#### Escaneo de los `Dockerfile` (`trivy config`)

0 errores en `api-facturas`, `api-transacciones` y `api-tarjetas`. En `db` aparece un aviso,
`DS-0002` ("Image user should not be 'root'"), que es un **falso positivo**. Nuestro `Dockerfile`
no declara `USER`, pero la imagen hereda el usuario `mysql` de la oficial:
`docker image inspect -f '{{.Config.User}}' ${DOCKERHUB_USER}/fintech-nova-db:1.0.0` → `mysql`. Trivy
solo mira el `Dockerfile` y no ve lo que define la imagen base.

### Escaneo de secretos antes de publicar (2026-10-03)

Antes del primer `docker push` de las 7 imágenes se hicieron tres controles, para confirmar que no
se filtrara ninguna credencial en Docker Hub:

| Control | Resultado |
|---|---|
| `trivy image --scanners secret` sobre las 7 imágenes | **0 secretos** en todas. |
| Búsqueda de archivos dentro de cada imagen (`.env`, `env.example`, `*.key`, `*.pem`, `*.crt`, `id_rsa*`, `.git`, `.npmrc`) | Ningún archivo propio. Solo aparecen archivos públicos de las imágenes base (ver abajo). |
| Variables de entorno (`docker inspect`) e historial de capas (`docker history`) | Sin contraseñas ni tokens. Ninguna capa propia usa `MYSQL_*` ni `DB_PASSWORD`. |
| `/etc/nginx/certs` en `web` | Vacío: el certificado se genera al arrancar. |

Archivos encontrados que **no** son secretos:

- `db`: `/usr/share/doc/perl-Net-SSLeay/examples/server_key.pem` es la clave de **ejemplo** de la
  documentación del paquete `perl-Net-SSLeay`. Ya viene en `mariadb:11.8.9-ubi9`
  (`rpm -qf` → `perl-Net-SSLeay-1.94-3.el9`) y no se usa para nada.
- `db` y `api-facturas`: el certificado público de una CA de GnuPG
  (`sks-keyservers.netCA.pem`).
- `api-clientes`: `cacert.pem` es el conjunto de certificados de CA públicos que trae `pip`, y la
  variable `GPG_KEY` es la huella de la clave **pública** con la que la imagen oficial de Python
  verifica sus descargas.

No se corrió Checkov.

## 4. Buenas prácticas aplicadas

### Imágenes

| Práctica | api-clientes | api-pagos |
|---|---|---|
| Imagen base oficial y liviana | `python:3.12-slim` | `node:22-alpine` |
| Usuario no-root | `appuser` (uid 999), creado en el Dockerfile | `node` (uid 1000), el de la imagen oficial |
| Código de solo lectura | Es de root: `appuser` no puede modificarlo (`touch /app/main.py` → *Permission denied*) | Es de root: `node` no puede modificarlo (`touch /app/src/x` → *Permission denied*) |
| Dependencias fijadas | Versiones exactas en `requirements.txt` | `package-lock.json` + `npm ci --omit=dev` (sin devDependencies) |
| Build context mínimo (`.dockerignore`) | Excluye venv, `__pycache__`, Git, `.env`, docs y certificados (4.29 kB) | Excluye `node_modules`, Git, `.env`, docs y certificados (~42 kB) |
| Sin herramientas de instalación en runtime | Multistage: pip corre en el `builder` con `--no-cache-dir` y se desinstala del venv | `npm cache clean --force` y se borra `npm` en la misma capa |
| Servidor de producción | Gunicorn, no el servidor de desarrollo de Flask | `node` directo, sin `npm start` |
| PID 1 y señales | `exec gunicorn`: `docker stop` tarda < 1 s | `node` es PID 1 y recibe el SIGTERM |
| HEALTHCHECK sin herramientas extra | `urllib` de Python (la imagen `slim` no trae curl) | `wget` de busybox, que ya viene en Alpine |

| Práctica | api-facturas | api-transacciones | api-tarjetas | db |
|---|---|---|---|---|
| Imagen base oficial | `eclipse-temurin:21-jre-alpine` | `alpine:3.24.2` | `dotnet/aspnet:8.0-alpine` | `mariadb:11.8.9-ubi9` (la exige el enunciado) |
| Multistage | Maven + JDK 21 → solo JRE y el `.jar` | `golang:1.27-alpine` → solo el binario estático (`CGO_ENABLED=0`, `-ldflags="-s -w"`) | SDK 8.0 → runtime `aspnet` | No hace falta: no compila nada |
| Tamaño final | 376 MB | **25 MB** | 159 MB | 703 MB (casi todo es la imagen base) |
| Usuario no-root | `appuser`, creado en el Dockerfile | `app`, creado en el Dockerfile | `appuser`, creado en el Dockerfile | `mysql`, heredado de la imagen oficial: el entrypoint arranca como root, prepara el volumen y baja a `mysql` con `gosu` |
| Build context mínimo | Excluye `target/`, Git, `.env`, IDE, docs y certificados | Lista blanca: solo `*.go`, `go.mod` y `go.sum` | Excluye `bin/`, `obj/`, Git, `.env`, IDE, docs y certificados | Lista blanca: solo el `Dockerfile` y `init-scripts/` |
| Dependencias fijadas | `pom.xml` con versiones del parent de Spring Boot | `go.sum`, y `go mod verify` en el build | `PackageReference` con versión exacta | Tag exacto de la imagen |
| HEALTHCHECK | `wget` a `/facturas`: prueba también la conexión a la base | `wget` a `/` | `wget` a `/` | `healthcheck.sh --connect --innodb_initialized` (script oficial) |
| Salida HTTPS | No usa | `ca-certificates`, para validar el TLS de ipapi.co | No usa | No usa |
| Memoria | `JAVA_TOOL_OPTIONS=-XX:MaxRAMPercentage=75 -XX:+UseSerialGC`: heap de 384 MiB con el límite de 512M (verificado con `-XX:+PrintFlagsFinal`) | — | — | Datos en el volumen `db_data` |

**web** (`nginx:1.30-alpine`, multistage con `node:22-alpine`):

| Práctica | Cómo |
|---|---|
| Imagen final sin herramientas de build | Multistage: Node, npm, Vite y `node_modules` quedan en la etapa `build`. La final solo tiene NGINX, OpenSSL y los ~40 kB de `dist/`. |
| Usuario no-root | `USER nginx` (uid 101). Se quitó la directiva `user` de `nginx.conf`, el pid va a `/tmp` y `nginx` solo puede escribir su caché y `/etc/nginx/certs`. Por eso escucha en 8443 (sin root no puede usar puertos < 1024). |
| Config de solo lectura | `default.conf`, el script y `dist/` son de root. `nginx` no puede modificarlos. |
| Filesystem de solo lectura (Compose) | `read_only: true`, con `tmpfs` para `/tmp` y `/var/cache/nginx` (uid 101). Solo el volumen `web_certs` es persistente y escribible. |
| Sin privilegios extra (Compose) | `cap_drop: [ALL]` y `no-new-privileges:true`. |
| Sin clave en la imagen | El certificado se genera en runtime (sección 2). |
| HEALTHCHECK sin herramientas extra | `wget` de busybox contra `https://127.0.0.1:8443/`. |
| Cabeceras de seguridad | `Strict-Transport-Security`, `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, `Referrer-Policy: no-referrer` y una `Content-Security-Policy` estricta (`default-src 'self'; object-src 'none'`; el build de Vite no usa scripts inline). `server_tokens off` oculta la versión, y `proxy_hide_header X-Powered-By` la de los backends. |
| Límites de entrada | `client_max_body_size 64k` (413), `limit_req` de 10 pedidos/s por IP con ráfaga de 20 en `/api/*` (429) y `limit_conn` de 20 conexiones simultáneas por IP (429). |
| Timeouts cortos | `client_header_timeout`, `client_body_timeout`, `send_timeout` y `keepalive_timeout` en 10 s (por defecto son 60-65 s), contra conexiones lentas tipo slowloris. Probado: una conexión con cabeceras incompletas se corta a los 10 s con 408. |
| Solo los métodos necesarios | `limit_except GET POST PUT DELETE` en `/api/*`: `OPTIONS` y `PATCH` → 403, `TRACE` → 405. En el frontend, todo lo que no sea GET/HEAD → 405. |
| Sin datos del servidor en los errores | Los errores que genera NGINX (400, 403, 404, 405, 413, 429, 5xx) devuelven un JSON genérico en vez de la página por defecto, que dice "nginx". Los errores de las APIs pasan sin cambios. |
| Archivos ocultos | `location ~ /\.` → 404 (`/.env`, `/.git/config`). |
| IP del cliente no falsificable | `X-Forwarded-For` lleva solo `$remote_addr`: lo que mande el cliente en esa cabecera se descarta. |
| Imágenes base fijadas por digest | `node:22-alpine@sha256:…` y `nginx:1.30-alpine@sha256:…`: el build no cambia aunque alguien mueva el tag. |
| Sin herramientas de más | Se quitan `curl`, `nc` y `apk` de la imagen final. Quedan `wget` (HEALTHCHECK) y `openssl` (certificado). No hay archivos setuid/setgid. |
| Permisos mínimos | Config y `error.json` en `644` de root; clave TLS en `400`. |
| Límite de procesos (Compose) | `deploy.resources.limits.pids: 100` (uso real: 13). |
| Rotación de logs (Compose) | `json-file` con `max-size: 10m` y `max-file: 3`: los logs de acceso no pueden llenar el disco de la EC2. |

### Orquestación (`docker-compose.yml`)

- **Sin puertos publicados:** las APIs y MariaDB no tienen `ports:`. Solo se accede a ellas por las
  redes internas (`frontend` y `backend`), y la única entrada pública es `web` por HTTPS en el 8443.
- **Por qué `docker compose ps` muestra `80/tcp` en `web`** (se ve en la
  [captura del despliegue en la EC2](./docs/capturas/04-compose-ps.png)):
  `80/tcp, 0.0.0.0:8443->8443/tcp`. El `80/tcp` es el `EXPOSE 80` que declara la imagen oficial
  `nginx:1.30-alpine` y que `web` hereda. `EXPOSE` es solo documentación: no abre ni publica nada, y
  Docker no tiene una instrucción para quitar un `EXPOSE` heredado (nuestro Dockerfile declara solo
  `EXPOSE 8443`). La diferencia se ve en la propia salida: un puerto publicado en el host aparece
  como `0.0.0.0:8443->8443/tcp`; el `80/tcp` a secas no está publicado. El 80 queda cerrado por
  tres capas independientes:
  1. **Contenedor:** `nginx.conf` reemplaza el server por defecto de la imagen y el único `listen`
     es `8443 ssl`; nada escucha en el 80.
  2. **Compose:** la única publicación es `ports: ["8443:8443"]`.
  3. **Security Group:** no hay regla de entrada para el 80.

  Comprobado desde afuera en la EC2 (2026-10-07): `curl -m 5 http://54.152.76.222:80/` termina
  por *timeout* ([captura](./docs/capturas/03-curl.png)), y `deploy.sh` hace la misma prueba en cada
  despliegue.

  *Alternativa evaluada y descartada:* ocultar el `80/tcp` reconstruyendo la imagen final desde
  `scratch` (`COPY --from=nginx / /`), que copia los archivos pero no la metadata. Obliga a
  redeclarar a mano `ENTRYPOINT`, `CMD`, `STOPSIGNAL` y `ENV` de la imagen oficial, y a mantenerlos
  sincronizados en cada actualización de NGINX. El cambio es solo estético y no mejora la
  seguridad, así que no lo justifica.
- **Mínimo privilegio de red:** en lugar de una única red compartida, el stack usa dos redes. `web` y las APIs comparten la red `frontend`, y las APIs y `db` comparten la red `backend`. Esto asegura que un compromiso de `web` (el único servicio expuesto) no otorgue conectividad de red directa contra MariaDB (puerto 3306), requiriendo un movimiento lateral mucho más difícil a través de las APIs para explotar la base de datos.
- **Límites de recursos** (CPU / memoria, con el uso medido el 2026-10-03 con los 7 servicios
  levantados):

  | Servicio | Límite | Uso medido |
  |---|---|---|
  | db | 0.50 / 512M | ~103 MiB |
  | api-facturas | 0.50 / 512M | ~191 MiB |
  | api-tarjetas | 0.25 / 256M | ~34 MiB |
  | api-clientes | 0.25 / 128M | ~56 MiB |
  | api-pagos | 0.25 / 128M | ~20 MiB |
  | api-transacciones | 0.25 / 128M | ~7 MiB |
  | web | 0.25 / 64M | ~14 MiB |

  En total los límites suman ~1,7 GiB de los 4 GiB de la `t3.medium`. Un proceso desbocado no
  puede tirar abajo la EC2 entera.
- **Imágenes publicadas, sin `build:`**, con tags de versión fijos (`:1.0.0`, y `web` en `:1.2.0`, pendiente de publicar; la última publicada es `:1.1.0`; nunca `latest`).
- **`restart: always`**, y `depends_on` con `condition: service_healthy` sobre `db`.

### Aplicación

- **Consultas parametrizadas:** las dos APIs usan parámetros (`%s` en PyMySQL, `?` en mysql2) y
  nunca concatenan SQL.
- **Validación de entrada (api-clientes):** POST y PUT exigen un objeto JSON con `nombre` y
  `email` de tipo texto, y `dni` texto u omitido. Si no se cumple, responden 400.
- **Límite del body:** 16 KB en api-clientes y 32 KB en api-pagos. Si se supera, responden 413.
- **Sin información del stack en las respuestas:** api-pagos no envía `X-Powered-By`. Los errores
  al cliente son mensajes genéricos en JSON, sin trazas; el detalle queda solo en los logs.
- **Falla segura con terceros (api-pagos):** si la API de tipo de cambio falla o tarda más de
  5 s, el pago se guarda igual con `monto_usd = null`. La consulta sale por HTTPS.

## 5. Revisión OWASP Top 10 (2025)

| Categoría | Hallazgo | Estado |
|---|---|---|
| A05 Injection + A03 Supply Chain | **api-clientes:** PyMySQL 1.1.0 no escapaba las claves de un `dict`, y el código pasaba el JSON sin validar tipos. Se confirmó con `cursor.mogrify` que la clave entraba sin escapar al SQL. | **Corregido:** PyMySQL 1.2.3 + validación de tipos. Un objeto como `nombre` → 400. |
| A05 Injection | **api-pagos:** `mysql2` convierte los objetos a `'[object Object]'` y pone entre comillas lo que llega en la URL (`'1 OR 1=1'`). | Sin hallazgo. |
| A02 Security Misconfiguration | `X-Powered-By: Express` (api-pagos) | **Corregido:** `app.disable('x-powered-by')`. |
| A02 Security Misconfiguration | `Server: gunicorn` (api-clientes). Gunicorn no permite quitarla, pero no incluye la versión. | Aceptado: NGINX no reenvía la cabecera `Server` del backend. |
| A06 Insecure Design | api-clientes aceptaba bodies de 2 MB | **Corregido:** límite de 16 KB → 413. |
| A01 Broken Access Control | El mismo usuario de base tiene `ALL PRIVILEGES` sobre las 5 bases, así que una inyección en una API alcanzaría a las demás. | *Pendiente, a acordar con el grupo:* un usuario por base. |
| A01 / A07 | Las APIs no tienen autenticación: cualquiera que llegue al HTTPS puede listar o borrar datos, DNI y emails incluidos. | Viene del caso de referencia, fuera del alcance del TP. Mejora posible: autenticación en NGINX o en las APIs. |
| A06 Insecure Design | No hay límite de pedidos, y cada POST o PUT de pagos consulta a un tercero. | **Corregido en `web`:** `limit_req` de 10 r/s por IP (ráfaga 20) en `/api/*` → 429. Probado con 40 pedidos simultáneos: 31 × 200 y 9 × 429. |
| A09 Logging & Alerting | Gunicorn y Express no registran cada pedido; solo registran los errores. | **Corregido en `web`:** NGINX registra cada pedido (IP, método, ruta, código) en su log de acceso (`docker compose logs web`). |

### Revisión de `web` contra OWASP Top 10 (2025) y CIS (Docker y NGINX)

Hecha el 2026-10-01 sobre el contenedor en ejecución. Cada hallazgo se comprobó antes y después
del arreglo. Los números de control CIS son orientativos: pueden variar según la versión del
benchmark.

| # | Hallazgo (evidencia) | Referencia | Estado |
|---|---|---|---|
| 1 | Sin autenticación: cualquiera que llegue al 8443 puede listar y borrar datos. | A01, A07 | Sin cambios. Viene del caso de referencia; requiere acuerdo del grupo. |
| 2 | TLS 1.2 aceptaba cifrados débiles (`AES128-SHA`, `AES256-SHA256`, `CAMELLIA128-SHA`: CBC y sin forward secrecy). | A04 · CIS NGINX 4.1.5 | **Corregido:** `ssl_ciphers` solo con ECDHE + AES-GCM/ChaCha20. Los débiles se rechazan. |
| 3 | Timeouts por defecto (60-65 s) y sin límite de conexiones por IP. | A02, A06 · CIS NGINX 2.4.3, 2.4.4, 5.2.1, 5.2.4 | **Corregido:** timeouts de 10 s y `limit_conn 20`. |
| 4 | Logs de Docker sin rotación. | A09 · CIS NGINX 3.4 | **Corregido:** `max-size: 10m`, `max-file: 3`. |
| 5 | Contenedor sin límite de procesos. | A02 · CIS Docker 5.28 | **Corregido:** `pids: 100`. |
| 6 | El frontend ignoraba los errores de las APIs: un alta rechazada parecía exitosa. | A10 | **Corregido:** `main.js` revisa `res.ok` y muestra un aviso; el formulario no se limpia si falla. |
| 7 | El cliente podía falsificar `X-Forwarded-For` (el backend recibía `1.2.3.4, 172.18.0.1`). | A02 | **Corregido:** el backend recibe solo la IP real. La cabecera `Host` se sigue reenviando tal cual: sin dominio propio no hay contra qué validarla. |
| 8 | Imágenes base por tag flotante. | A03, A08 · CIS Docker 4.2 | **Corregido:** fijadas por digest. La imagen propia se publica con tag de versión fijo (`${DOCKERHUB_USER}/fintech-nova-web:1.0.0` en esa revisión; hoy va por `1.2.0`). |
| 9 | `default.conf` en `755` y clave TLS en `600`. | A02 · CIS NGINX 2.3.2, 4.1.3 | **Corregido:** `644` y `400`. |
| 10 | Sin regla para archivos ocultos, `OPTIONS` llegaba a las APIs, páginas de error con "nginx", y `curl`/`nc`/`apk` en la imagen. | A02 · CIS NGINX 2.5.2, 2.5.3, 5.1.2 · CIS Docker 4.3 | **Corregido** (ver la tabla de buenas prácticas de `web`). |

Sin hallazgos: XSS e inyección (A05; `main.js` solo usa `textContent`, y la CSP bloquea scripts
inline y externos), secretos en la imagen, archivos setuid/setgid, TLS 1.0 y 1.1 (rechazados).

Desvíos de CIS que se aceptan porque los impone el enunciado o el contexto:

- **`restart: always`:** CIS Docker 5.14 recomienda `on-failure:5`; el enunciado exige `always`.
- **Sin redirección HTTP → HTTPS:** CIS NGINX 4.1.1 la pide; el enunciado prohíbe usar el puerto 80.
- **Puerto publicado en `0.0.0.0`:** CIS Docker 5.13 pide atarlo a una interfaz; acá tiene que ser
  público.
- **OCSP stapling:** no aplica a un certificado autofirmado.

## 6. Security Group de la EC2

Reglas que crea `deploy.sh --crear-ec2`. Si la EC2 se crea a mano por la consola, hay que cargar
las mismas.

**Entrada:**

| Puerto | Protocolo | Origen | Para qué |
|---|---|---|---|
| 22 | TCP | IP pública del equipo que despliega (`/32`, la detecta el script con `checkip.amazonaws.com`) | SSH de `deploy.sh` y administración |
| 8443 | TCP | `0.0.0.0/0` | HTTPS público: la única entrada al stack (NGINX) |

No hay ninguna otra regla de entrada. En particular, **el 80 queda cerrado**, y tampoco se abren el
3306 de MariaDB ni el 8080 de las APIs: esos puertos ni siquiera se publican en el host. Al
terminar, `deploy.sh` comprueba desde afuera que el 80 no responde y que HTTP plano contra el 8443
recibe 400.

**Salida:** la regla por defecto de AWS (todo el tráfico hacia `0.0.0.0/0`). La necesitan:

- la instalación de Docker (`apt` en Ubuntu usa HTTP en el 80; `dnf` en Amazon Linux usa HTTPS) y
  la descarga del plugin de Compose desde GitHub (443);
- `docker compose pull` desde Docker Hub (443);
- `api-pagos` → `open.er-api.com` y `api-transacciones` → `ipapi.co` (443).

El tráfico al DNS de la VPC y al servicio de hora de Amazon no pasa por el Security Group.

**Mejora posible:** limitar la salida a TCP 80 y 443. No se hizo para no romper la instalación en
una instancia nueva, y porque la salida no expone servicios.

**Por qué el SSH acotado a una IP:** el 22 abierto a internet recibe intentos automáticos de login a
los pocos minutos. Con la IP del equipo, solo quien despliega puede intentar conectarse. Además,
la instancia solo acepta autenticación por llave, no por contraseña: es la configuración por
defecto de las AMI de Ubuntu y Amazon Linux.

**En el despliegue real (2026-10-07):** el Security Group `sg-0af62688c272137b8`
(`fintech-nova-sg`) quedó exactamente con estas reglas: 22 desde `<IP_ADMINISTRADOR>/32`, 8443 desde
`0.0.0.0/0` y la salida por defecto. Los IDs, la VPC, la subred y el detalle de las reglas
están en [AWS_EC2.md](./AWS_EC2.md#security-group).
