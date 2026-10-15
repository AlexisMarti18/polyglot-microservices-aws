# Guía de estudio de `web`: frontend, NGINX y certificado TLS

Esta guía explica, desde cero, todo lo que hay en la carpeta `web/` y los conceptos que usa. Está
pensada para leerse de corrido la primera vez y para consultar por sección después. No hace falta
saber nada de Docker, NGINX ni criptografía para seguirla.

Los datos técnicos resumidos (decisiones, comandos, resultados de pruebas) están en
[`README.md`](./README.md), [`SEGURIDAD.md`](../../SEGURIDAD.md) y [`ERRORES.md`](../../ERRORES.md).
Acá el objetivo es **entender**.

## Índice

1. [Qué problema resuelve `web`](#1-qué-problema-resuelve-web)
2. [Conceptos previos](#2-conceptos-previos)
3. [El frontend: Vite, npm y la carpeta `dist/`](#3-el-frontend-vite-npm-y-la-carpeta-dist)
4. [El `Dockerfile`, línea por línea](#4-el-dockerfile-línea-por-línea)
5. [`.dockerignore` y `.gitattributes`](#5-dockerignore-y-gitattributes)
6. [NGINX](#6-nginx)
7. [HTTPS, TLS y el certificado](#7-https-tls-y-el-certificado)
8. [El servicio `web` en `docker-compose.yml`](#8-el-servicio-web-en-docker-composeyml)
9. [El recorrido completo de un pedido](#9-el-recorrido-completo-de-un-pedido)
10. [Cómo probar cada cosa](#10-cómo-probar-cada-cosa)
11. [Preguntas probables en la presentación](#11-preguntas-probables-en-la-presentación)
12. [Glosario](#12-glosario)

---

## 1. Qué problema resuelve `web`

El sistema FinTech Nova tiene cinco programas que guardan y devuelven datos (las **APIs**: clientes,
pagos, facturas, transacciones y tarjetas) y una base de datos. Ninguno de ellos tiene pantalla:
solo responden pedidos con texto en formato JSON.

Faltan dos cosas para que una persona pueda usar el sistema desde internet:

1. **Una pantalla.** Alguien tiene que mostrar formularios y tablas en el navegador.
2. **Una puerta de entrada segura.** No queremos que las cinco APIs y la base queden expuestas a
   internet, cada una en su puerto. Queremos **una sola puerta**, y que lo que pase por ella viaje
   cifrado.

`web` resuelve las dos. Pensalo como la **recepción de un edificio de oficinas**:

- El edificio es el servidor (la instancia EC2).
- Las oficinas son las APIs y la base de datos. No tienen puerta a la calle.
- La recepción (`web`) es la única entrada. Te entrega el folleto del edificio (la pantalla) y,
  cuando pedís algo de una oficina, el recepcionista va, lo busca y te lo trae. Vos nunca entrás
  a las oficinas.
- Además, la conversación con la recepción es privada: nadie en la calle puede escucharla (eso es
  HTTPS).

El programa que hace de recepcionista se llama **NGINX**.

---

## 2. Conceptos previos

### 2.1 Cliente, servidor, IP y puerto

- Un **servidor** es un programa que espera pedidos y los responde. Un **cliente** es el que pide.
  Tu navegador es un cliente; NGINX es un servidor.
- Cada máquina en una red tiene una **dirección IP** (por ejemplo `54.12.33.7`). Es como la
  dirección de un edificio.
- En una misma máquina pueden correr muchos servidores. Para distinguirlos, cada uno escucha en un
  **puerto**, que es un número entre 1 y 65535. Es como el número de departamento dentro del
  edificio. `https://54.12.33.7:8443` significa "el departamento 8443 del edificio 54.12.33.7".
- Hay puertos con significado convencional: **80** es HTTP sin cifrar, **443** es HTTPS. Los
  puertos **menores a 1024** son "privilegiados": en Linux, solo un programa con permisos de
  administrador puede abrirlos. Este dato vuelve a aparecer más adelante.

### 2.2 HTTP

**HTTP** es el idioma que hablan el navegador y el servidor. Un pedido tiene:

- Un **método**, que dice qué se quiere hacer: `GET` (leer), `POST` (crear), `PUT` (modificar),
  `DELETE` (borrar).
- Una **ruta**: `/api/clientes`, `/assets/index.js`.
- **Cabeceras** (*headers*): datos extra del pedido, como `Content-Type: application/json`.
- A veces un **cuerpo** (*body*): los datos que se envían, por ejemplo el cliente a crear.

La respuesta trae un **código de estado**. Los que aparecen en este TP:

| Código | Significado | Cuándo lo vas a ver |
|---|---|---|
| 200 | OK | Todo bien |
| 201 | Creado | Un `POST` que guardó algo |
| 204 | Sin contenido | Un `DELETE` exitoso |
| 400 | Pedido mal formado | Datos inválidos, o HTTP plano contra el puerto HTTPS |
| 403 | Prohibido | Un método no permitido en `/api` (por ejemplo `OPTIONS`) |
| 404 | No encontrado | Un archivo que no existe |
| 413 | Cuerpo demasiado grande | Un body de más de 64 KB |
| 429 | Demasiados pedidos | Se superó el límite por IP |
| 502 | Bad Gateway | NGINX no pudo llegar a la API (está caída o no existe) |

HTTP solo no cifra nada: cualquiera que esté en el camino puede leer lo que viaja. **HTTPS** es
HTTP adentro de un túnel cifrado. Ese túnel se llama **TLS** (sección 7).

### 2.3 Docker: imagen, contenedor, Dockerfile

El problema clásico: "en mi máquina funciona". Un programa necesita su lenguaje, sus librerías y
su configuración, y en otra máquina algo de eso falta o es otra versión.

- Una **imagen** es un paquete cerrado que contiene el programa **y todo lo que necesita** para
  correr. Es como una receta ya cocinada y congelada: se lleva a cualquier lado y es siempre igual.
- Un **contenedor** es una imagen en ejecución. De una misma imagen se pueden levantar muchos
  contenedores. El contenedor está aislado: tiene sus propios archivos, su propia red y sus propios
  procesos.
- Un **`Dockerfile`** es el archivo de texto con las instrucciones para construir una imagen
  ("partí de esta base, copiá estos archivos, corré este comando").
- **Docker Hub** es un depósito público de imágenes. Las imágenes "oficiales" (`nginx`, `node`)
  las mantienen sus autores. Nosotros publicamos ahí la nuestra para que la EC2 la descargue.
- Un **tag** es la etiqueta de versión de una imagen: en `nginx:1.30-alpine`, el tag es
  `1.30-alpine`. **Alpine** es una distribución de Linux muy chica, usada para que las imágenes
  pesen poco.

### 2.4 Docker Compose, red interna y volúmenes

- **Docker Compose** levanta varios contenedores juntos a partir de un archivo,
  `docker-compose.yml`. Cada contenedor se declara como un **servicio** (`web`, `db`,
  `api-clientes`...).
- Compose crea una **red interna** privada. Dentro de ella, cada contenedor encuentra a los demás
  **por el nombre del servicio**: `web` puede hablar con `api-clientes:8080` sin conocer su IP.
  Docker trae un mini servidor de nombres (DNS) interno que traduce el nombre a la IP.
- Desde afuera de esa red no se llega a ningún contenedor, **salvo** que se **publique un puerto**:
  `ports: ["8443:8443"]` significa "el puerto 8443 de la máquina se conecta con el 8443 del
  contenedor". En este TP **solo `web` publica un puerto**.
- Los archivos de un contenedor se pierden cuando se lo borra. Un **volumen** es una carpeta que
  Docker guarda aparte y que sobrevive. Lo usamos para el certificado.

---

## 3. El frontend: Vite, npm y la carpeta `dist/`

### 3.1 Qué es el frontend

Es lo que corre **en el navegador del usuario**: un archivo HTML, uno de JavaScript y uno de CSS.
El código fuente está en:

| Archivo | Qué es |
|---|---|
| `index.html` | La página. Casi vacía: tiene un `<div id="app">` y carga el JavaScript. |
| `src/main.js` | La lógica: arma los formularios y tablas, y llama a las APIs. |
| `src/style.css` | Los estilos. |
| `vite.config.js` | Configuración de Vite. Solo define un proxy para el modo desarrollo. |
| `package.json` | Lista de dependencias y comandos del proyecto. |
| `package-lock.json` | Las versiones **exactas** de cada dependencia (ver 3.3). |

### 3.2 Qué hace `main.js`

- Define las cinco entidades (clientes, pagos, etc.) con sus campos.
- Dibuja el **encabezado** de la aplicación (marca, título y la leyenda del stack).
- Por cada entidad arma un formulario y una tabla.
- Para leer, crear y borrar, llama a **rutas relativas**: `/api/clientes`, `/api/pagos`, etc.

"Ruta relativa" es la clave: el JavaScript no sabe la IP del servidor ni dónde están las APIs.
Pide `/api/clientes` **al mismo servidor del que se descargó la página**, o sea, a NGINX. NGINX se
encarga de llevar el pedido a la API correcta.

Dos detalles de seguridad en ese archivo:

- Todo el texto se inserta con `textContent`, nunca con `innerHTML`. Así, si alguien carga un
  cliente llamado `<script>robar()</script>`, el navegador lo muestra como texto y **no lo
  ejecuta**. Ese ataque se llama **XSS**.
- La función `pedir()` revisa si la respuesta fue exitosa. `fetch` (la función del navegador para
  hacer pedidos) solo falla si no hay red: un 400 o un 502 llegan como respuestas "normales". Sin
  esa revisión, un alta rechazada se veía como exitosa.

### 3.3 npm, `package.json` y `package-lock.json`

- **Node.js** es un programa que ejecuta JavaScript fuera del navegador. **npm** es su instalador
  de paquetes.
- `package.json` dice "necesito Vite, versión 5.4 o compatible" (`^5.4.0`).
- `package-lock.json` anota la versión exacta que se instaló (5.4.21) y la de cada
  sub-dependencia.
- `npm install` instala según `package.json` y puede elegir versiones nuevas. `npm ci` instala
  **exactamente** lo que dice el `package-lock.json` y falla si ese archivo no existe. Por eso en
  Docker se usa `npm ci`: el build da el mismo resultado hoy y dentro de seis meses.

### 3.4 Vite y el "build"

**Vite** es una herramienta con dos modos:

- **Desarrollo** (`npm run dev`): levanta un servidor local que recarga la página al guardar. Solo
  se usa en la máquina de quien programa.
- **Build** (`npm run build`): toma el código fuente, lo junta, lo comprime y deja el resultado en
  la carpeta **`dist/`**. Lo que hay en `dist/` son **archivos estáticos**: un `index.html`, un
  `.js` y un `.css`. "Estático" significa que el servidor los entrega tal cual, sin ejecutar nada.

Vite le agrega un **hash** al nombre de cada archivo (`index-BTxfMS_5.js`). Si el contenido
cambia, cambia el nombre. Eso permite decirle al navegador "guardá este archivo para siempre": si
hay una versión nueva, tendrá otro nombre.

Conclusión importante: **para servir el frontend no hace falta Node ni Vite**. Solo hacen falta
para fabricar `dist/`. Esa idea es la base del Dockerfile.

---

## 4. El `Dockerfile`, línea por línea

### 4.1 La idea: build multietapa (*multistage*)

Si construyéramos todo en una sola imagen, la imagen final tendría Node, npm, Vite y cientos de
megas de `node_modules`, que no se usan para nada al servir la página. Más peso y, sobre todo, más
programas que pueden tener fallas de seguridad.

Un **build multietapa** usa dos imágenes dentro del mismo `Dockerfile`:

```
Etapa 1 "build"  (Node)   →  fabrica dist/  →  se descarta
Etapa 2 "runtime" (NGINX)  →  recibe solo dist/  →  es la imagen final
```

Es como una fábrica: las máquinas se quedan en la fábrica y al cliente le llega solo el producto.

### 4.2 Etapa 1: fabricar `dist/`

```dockerfile
FROM node:22-alpine@sha256:0a71... AS build
```

- `FROM` elige la imagen base. Acá, Node 22 sobre Alpine.
- `@sha256:...` es el **digest**: la huella digital exacta de esa imagen. Un tag como `22-alpine`
  puede apuntar mañana a otra imagen distinta; el digest no cambia nunca. Fijarlo garantiza que
  siempre se construye sobre la misma base.
- `AS build` le pone nombre a la etapa, para referirse a ella después.

```dockerfile
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
```

- `WORKDIR` define la carpeta de trabajo dentro de la imagen.
- Se copian **primero** solo los dos archivos de dependencias y se instala.

¿Por qué no copiar todo de una vez? Por la **caché de capas**. Cada instrucción del Dockerfile
genera una "capa", y Docker reutiliza una capa si nada de lo que usa cambió. Las dependencias
cambian rara vez; el código, seguido. Con este orden, al modificar `main.js` Docker reutiliza la
capa de `npm ci` y el build tarda segundos en vez de minutos.

```dockerfile
COPY index.html vite.config.js ./
COPY src ./src
RUN npm run build
```

Se copia el código y se genera `dist/`.

### 4.3 Etapa 2: la imagen final

```dockerfile
FROM nginx:1.30-alpine@sha256:0985...
```

Empieza una imagen **nueva**, desde la imagen oficial de NGINX. Nada de la etapa 1 pasa
automáticamente.

```dockerfile
RUN apk upgrade --no-cache && apk add --no-cache openssl \
  && sed -i -e '/^user /d' -e 's,^pid .*,pid /tmp/nginx.pid;,' /etc/nginx/nginx.conf \
  && install -d -o nginx -g nginx -m 700 /etc/nginx/certs \
  && chown -R nginx:nginx /var/cache/nginx \
  && apk del --no-cache curl \
  && rm -f /usr/bin/nc /sbin/apk
```

Es un solo `RUN` con varios comandos encadenados con `&&` (cada uno corre solo si el anterior
salió bien). Va en una sola instrucción para generar una sola capa. Parte por parte:

| Comando | Qué hace | Por qué |
|---|---|---|
| `apk upgrade --no-cache` | Actualiza los paquetes de Alpine. `apk` es el instalador de Alpine. | La imagen base traía dos librerías con fallas ya corregidas por Alpine. |
| `apk add --no-cache openssl` | Instala OpenSSL. | Es la herramienta que genera el certificado. La imagen base no la trae. |
| `sed -i ... nginx.conf` | Edita la configuración principal de NGINX: borra la línea `user` y mueve el archivo `pid` a `/tmp`. | Ajustes para que NGINX corra **sin ser root** (ver abajo). |
| `install -d -o nginx -g nginx -m 700 /etc/nginx/certs` | Crea la carpeta del certificado, propiedad del usuario `nginx`, con permisos 700. | Ahí se va a guardar la clave. Solo su dueño puede entrar. |
| `chown -R nginx:nginx /var/cache/nginx` | Le da al usuario `nginx` la carpeta de caché. | NGINX necesita escribir archivos temporales ahí. |
| `apk del curl`, `rm nc apk` | Quita herramientas. | NGINX no las usa. Si alguien lograra entrar al contenedor, le servirían para descargar cosas o moverse por la red. |

**Root y no-root.** En Linux, `root` es el usuario administrador: puede hacer todo. Si NGINX
corriera como root y alguien encontrara una falla en NGINX, tendría control total del contenedor.
Corriendo como el usuario `nginx` (un usuario común que ya trae la imagen), el daño posible es
mucho menor. Este principio se llama **mínimo privilegio**: dar a cada programa solo los permisos
que necesita.

**Permisos de archivos.** Los números como `700`, `644` o `400` indican quién puede hacer qué.
Cada dígito corresponde, en orden, al dueño, al grupo y al resto; y se arma sumando 4 (leer),
2 (escribir) y 1 (ejecutar o, en carpetas, entrar):

| Modo | Significado |
|---|---|
| `644` | El dueño lee y escribe; los demás solo leen. |
| `700` | Solo el dueño puede leer, escribir y entrar. |
| `400` | Solo el dueño puede leer. Nadie puede modificar. |
| `755` | El dueño hace todo; los demás leen y ejecutan. |

```dockerfile
COPY --chmod=644 nginx/nginx.conf /etc/nginx/conf.d/default.conf
COPY --chmod=644 nginx/error.json /etc/nginx/error.json
COPY --chmod=755 nginx/40-generar-certificado.sh /docker-entrypoint.d/
RUN sed -i 's/\r$//' /etc/nginx/conf.d/default.conf /docker-entrypoint.d/40-generar-certificado.sh
```

- Se copia nuestra configuración con el nombre **`default.conf`**. No es casual: la imagen oficial
  ya trae un `default.conf` que escucha en el puerto 80. Al copiar el nuestro con el mismo nombre,
  **lo pisamos** y el puerto 80 deja de existir.
- `--chmod` fija los permisos. La configuración solo necesita leerse (644). El script necesita
  ejecutarse (755).
- El último `sed` borra los caracteres `\r` de fin de línea de Windows (ver 5.2).

```dockerfile
COPY --from=build /app/dist /usr/share/nginx/html
```

**Esta es la línea que une las dos etapas.** Trae la carpeta `dist/` desde la etapa `build` y la
pone donde NGINX busca los archivos a servir. Es lo único que pasa de una etapa a la otra.

```dockerfile
USER nginx
EXPOSE 8443
```

- `USER nginx`: a partir de acá, y cuando el contenedor arranque, todo corre como `nginx`, no como
  root.
- `EXPOSE 8443`: documenta en qué puerto escucha el contenedor. No publica nada por sí solo (eso
  lo hace Compose).

**Por qué 8443 y no 443:** un programa sin root no puede abrir puertos menores a 1024. El
enunciado permite 443 u 8443, así que 8443 nos deja correr sin root sin trucos.

```dockerfile
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -q --spider --no-check-certificate https://127.0.0.1:8443/ || exit 1
```

Un **healthcheck** es un chequeo de salud. Que un contenedor esté "corriendo" no garantiza que
funcione. Cada 30 segundos, Docker ejecuta ese comando **dentro** del contenedor: le pide la página
a NGINX. Si falla tres veces seguidas, marca el contenedor como `unhealthy`.

- `127.0.0.1` es "esta misma máquina" (acá, el propio contenedor).
- `--no-check-certificate` hace falta porque el certificado es autofirmado (sección 7).

El Dockerfile no define cómo arranca NGINX: eso (`ENTRYPOINT` y `CMD`) se **hereda** de la imagen
oficial.

---

## 5. `.dockerignore` y `.gitattributes`

### 5.1 `.dockerignore`

Cuando se ejecuta `docker build`, Docker empaqueta la carpeta entera y se la manda al motor de
construcción. Ese paquete se llama **contexto de build**. El `.dockerignore` lista lo que **no**
debe entrar en ese paquete:

- `node_modules/` y `dist/`: se generan dentro del contenedor. Mandarlos es lento e inútil.
- `.git`: el historial del repositorio no tiene nada que hacer en una imagen.
- `.env`, `*.key`, `*.pem`, `*.crt`: secretos, claves y certificados. Si no entran al contexto,
  es imposible copiarlos a la imagen por error. Es una red de seguridad.
- `*.md`: documentación.

### 5.2 `.gitattributes` y el problema de los finales de línea

Windows termina cada línea de texto con dos caracteres (`\r\n`, llamado **CRLF**); Linux, con uno
(`\n`, **LF**). Git en Windows suele convertir los archivos a CRLF al descargarlos.

Dentro de la imagen corre Linux. La primera línea del script es `#!/bin/sh`, que le dice a Linux
con qué programa ejecutarlo. Con CRLF, Linux lee `#!/bin/sh\r` y busca un programa llamado
`sh\r`, que no existe: el script falla. Al grupo ya le pasó con la base de datos.

Hay dos defensas:

- `.gitattributes` le ordena a Git guardar siempre con LF los `*.sh`, `*.conf` y el `Dockerfile`.
- El `sed 's/\r$//'` del Dockerfile borra cualquier `\r` que haya llegado igual.

---

## 6. NGINX

### 6.1 Qué es y qué tres trabajos hace acá

**NGINX** (se pronuncia "engine-ex") es un servidor web: un programa que escucha pedidos HTTP y
los responde. En este TP hace tres trabajos:

1. **Servidor de archivos estáticos.** Entrega el `index.html`, el `.js` y el `.css` de `dist/`.
2. **Proxy inverso** (*reverse proxy*). Recibe un pedido y, en vez de responderlo él, lo reenvía a
   otro servidor (una API), espera la respuesta y se la devuelve al cliente. El cliente no se
   entera de que hubo un intermediario.
3. **Terminación TLS.** Es donde termina el túnel cifrado: recibe HTTPS, lo descifra y sigue en
   HTTP común puertas adentro.

### 6.2 Cómo se lee un archivo de configuración de NGINX

- Una **directiva** es una instrucción que termina en punto y coma: `listen 8443 ssl;`.
- Un **bloque** agrupa directivas entre llaves: `server { ... }`.
- El bloque **`server`** describe un sitio: en qué puerto escucha y cómo responde.
- Los bloques **`location`**, dentro de `server`, dicen qué hacer **según la ruta** del pedido.
- Las **variables** empiezan con `$`: `$remote_addr` es la IP de quien se conectó.
- Las líneas que empiezan con `#` son comentarios.

Nuestro `nginx.conf` es un único bloque `server`, más cuatro directivas previas.

### 6.3 Antes del `server`: las zonas de límites

```nginx
limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;
limit_req_status 429;
limit_conn_zone $binary_remote_addr zone=conexiones:10m;
limit_conn_status 429;
```

NGINX necesita memoria para llevar la cuenta de cuántos pedidos hizo cada IP. Una **zona** es ese
bloc de notas:

- `zone=api:10m` crea una de 10 MB llamada `api`, con un ritmo permitido de 10 pedidos por
  segundo por IP.
- `zone=conexiones:10m` crea otra para contar conexiones simultáneas.
- Cuando alguien se pasa, responde **429** ("demasiados pedidos").

Acá solo se definen. Se **aplican** más abajo.

### 6.4 Escuchar: puerto y TLS

```nginx
listen       8443 ssl;
http2        on;
server_name  _;
server_tokens off;
```

- `listen 8443 ssl`: escucha en el puerto 8443 y **solo** acepta conexiones cifradas. No hay
  ningún `listen 80`: el puerto 80 no existe en este servidor.
- `http2 on`: habilita HTTP/2, una versión más eficiente del protocolo.
- `server_name _`: acepta cualquier nombre de host. No tenemos dominio propio.
- `server_tokens off`: no publica la versión de NGINX en las respuestas. Saber la versión exacta
  le facilita a un atacante buscar fallas conocidas.

```nginx
ssl_certificate     /etc/nginx/certs/tls.crt;
ssl_certificate_key /etc/nginx/certs/tls.key;
ssl_protocols       TLSv1.2 TLSv1.3;
ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:...;
ssl_session_tickets off;
```

- Las dos primeras líneas indican dónde están el certificado y la clave privada (sección 7).
- `ssl_protocols`: solo las versiones modernas de TLS. Las viejas (1.0 y 1.1) tienen fallas
  conocidas y se rechazan.
- `ssl_ciphers`: la lista de algoritmos de cifrado permitidos en TLS 1.2. Sin esta línea, NGINX
  aceptaba algunos anticuados. Todos los de la lista empiezan con `ECDHE`, que da *forward
  secrecy* (se explica en 7.5).

### 6.5 Protecciones generales

```nginx
resolver 127.0.0.11 valid=30s ipv6=off;
```

`127.0.0.11` es la dirección del DNS interno de Docker, el que traduce `api-clientes` a una IP.
Esta línea trabaja en equipo con `set $upstream` (ver 6.8).

```nginx
client_max_body_size 64k;
client_header_timeout 10s;
client_body_timeout   10s;
send_timeout          10s;
keepalive_timeout     10s;
limit_conn conexiones 20;
```

- `client_max_body_size 64k`: rechaza con 413 cualquier pedido cuyo cuerpo pase los 64 KB. Las
  APIs reciben JSON de unos pocos bytes; nadie legítimo manda más.
- Los cuatro **timeouts** dicen "si en 10 segundos no terminaste de mandarme el pedido, corto".
  Existe un ataque llamado **slowloris**: abrir muchas conexiones y mandar los datos de a un byte
  por vez, para ocupar al servidor sin gastar recursos propios. Con timeouts cortos no funciona.
- `limit_conn conexiones 20`: aplica la zona definida antes. Máximo 20 conexiones simultáneas
  por IP.

### 6.6 Cabeceras de seguridad

```nginx
add_header Strict-Transport-Security "max-age=31536000" always;
add_header X-Content-Type-Options "nosniff" always;
add_header X-Frame-Options "DENY" always;
add_header Referrer-Policy "no-referrer" always;
add_header Content-Security-Policy "default-src 'self'; object-src 'none'; ..." always;
```

Son instrucciones que el servidor le da **al navegador** junto con cada respuesta:

| Cabecera | Qué le dice al navegador |
|---|---|
| `Strict-Transport-Security` | "A este sitio entrá siempre por HTTPS, durante un año." |
| `X-Content-Type-Options: nosniff` | "No adivines el tipo de un archivo: usá el que yo declaro." Evita que un archivo de texto se ejecute como script. |
| `X-Frame-Options: DENY` | "No dejes que otra página me muestre dentro de un marco." Evita el *clickjacking*: una página trampa que pone la nuestra invisible encima de un botón. |
| `Referrer-Policy: no-referrer` | "No le cuentes a otros sitios desde qué página venís." |
| `Content-Security-Policy` | "Solo ejecutá scripts y cargá recursos que vengan **de este mismo servidor**." Es la defensa más fuerte contra XSS: aunque alguien lograra inyectar un script externo, el navegador se negaría a correrlo. |

`always` hace que se agreguen también en las respuestas de error.

### 6.7 Las cabeceras que reciben las APIs

```nginx
proxy_set_header Host              $host;
proxy_set_header X-Real-IP         $remote_addr;
proxy_set_header X-Forwarded-For   $remote_addr;
proxy_set_header X-Forwarded-Proto $scheme;
proxy_hide_header X-Powered-By;
```

Cuando NGINX reenvía un pedido, la API ve que **quien se conecta es NGINX**, no el usuario. Estas
líneas le pasan a la API los datos originales:

- `X-Real-IP` y `X-Forwarded-For`: la IP real del usuario. Usamos `$remote_addr`, que es la IP de
  la conexión real. Un cliente podría mandar su propia cabecera `X-Forwarded-For` con una IP
  inventada; al escribirla nosotros, la inventada se descarta.
- `X-Forwarded-Proto`: avisa que el pedido original llegó por `https`.
- `proxy_hide_header X-Powered-By`: borra de la respuesta una cabecera con la que algunos
  frameworks anuncian qué tecnología usan.

### 6.8 Los `location`: qué se hace con cada ruta

**Páginas de error**

```nginx
error_page 400 403 404 405 413 429 500 502 503 504 /_error.json;
error_page 497 =400 /_error.json;
location = /_error.json {
    internal;
    alias /etc/nginx/error.json;
}
```

Cuando NGINX mismo genera un error, por defecto muestra una página que dice "nginx". Con esto
devuelve el contenido de `error.json`: `{"error":"No se pudo procesar el pedido"}`, conservando el
código original. `internal` significa que esa ruta no se puede pedir desde afuera. Los errores que
devuelven **las APIs** (por ejemplo, "Cliente no encontrado") pasan sin tocar.

**El frontend**

```nginx
root   /usr/share/nginx/html;
location / {
    try_files $uri $uri/ /index.html;
}
location /assets/ {
    try_files $uri =404;
    expires max;
}
location ~ /\. {
    return 404;
}
```

- `root`: la carpeta donde están los archivos (ahí copiamos `dist/`).
- `location /` atiende todo lo que no coincida con otro bloque. `try_files` prueba en orden: ¿hay
  un archivo con ese nombre?, ¿una carpeta?; si no, entrega `index.html`.
- `location /assets/`: los archivos con hash. `expires max` le dice al navegador que los guarde
  sin vencimiento.
- `location ~ /\.`: el `~` indica una expresión regular. Coincide con cualquier ruta que tenga un
  archivo o carpeta que empiece con punto (`.env`, `.git`). Siempre responde 404. No hay archivos
  así en `dist/`, pero la regla evita servirlos si alguna vez se cuela uno.

**Los cinco proxys**

```nginx
location /api/clientes {
    limit_req zone=api burst=20 nodelay;
    limit_except GET POST PUT DELETE { deny all; }
    set $upstream api-clientes:8080;
    rewrite ^/api/clientes(.*)$ /clientes$1 break;
    proxy_pass http://$upstream;
}
```

Hay cinco bloques iguales, uno por API. Línea por línea:

1. `limit_req zone=api burst=20 nodelay`: aplica el límite de 10 pedidos por segundo. `burst=20`
   tolera una ráfaga de hasta 20 pedidos juntos (al cargar la página, el frontend hace varios a la
   vez); pasado eso, responde 429.
2. `limit_except GET POST PUT DELETE { deny all; }`: solo pasan los métodos que el ABM necesita.
   Cualquier otro recibe 403.
3. `set $upstream api-clientes:8080`: guarda en una variable el nombre del contenedor y su puerto.
4. `rewrite ^/api/clientes(.*)$ /clientes$1 break`: **reescribe la ruta**. El navegador pide
   `/api/clientes/5`, pero la API espera `/clientes/5`. La expresión captura lo que viene después
   de `/api/clientes` (el `(.*)`) y arma la ruta nueva (`$1` es lo capturado).
5. `proxy_pass http://$upstream`: reenvía el pedido. Notá el `http://`: puertas adentro no hay
   cifrado.

**Por qué `set $upstream` en vez de escribir el nombre directo.** Si se escribe
`proxy_pass http://api-clientes:8080;`, NGINX busca la IP de `api-clientes` **una sola vez, al
arrancar**. Eso trae dos problemas:

- Si ese contenedor no existe todavía, NGINX **no arranca**.
- Si el contenedor se recrea y cambia de IP, NGINX sigue apuntando a la IP vieja.

Con una variable más la directiva `resolver`, NGINX busca la IP **en cada pedido** (guardándola
30 segundos). Arranca siempre y, si una API falta, solo esa ruta responde 502.

---

## 7. HTTPS, TLS y el certificado

### 7.1 Los dos problemas que resuelve TLS

Cuando tu navegador habla con un servidor, los datos pasan por muchos equipos intermedios (el
wifi, el proveedor de internet, etc.). TLS resuelve dos problemas distintos:

1. **Confidencialidad:** que nadie en el camino pueda leer ni alterar lo que viaja.
2. **Autenticidad:** que el servidor sea realmente quien dice ser, y no un impostor.

### 7.2 Dos tipos de cifrado

**Cifrado simétrico.** Una sola clave sirve para cerrar y para abrir, como la llave de un
candado común. Es muy rápido. El problema: ¿cómo le hacés llegar la llave al otro sin que la
intercepten?

**Cifrado asimétrico.** Hay **dos claves** que funcionan en pareja:

- La **clave pública** se puede repartir a todo el mundo.
- La **clave privada** no se comparte jamás.

Lo que hace una, solo lo deshace la otra. La aplicación que nos importa es la **firma digital**:
el dueño firma un mensaje con su clave privada y cualquiera puede comprobar esa firma con la clave
pública. Como solo el dueño tiene la privada, una firma válida prueba que el mensaje es suyo.

TLS combina los dos: usa el asimétrico para presentarse y acordar una llave, y el simétrico
(rápido) para el resto de la conversación.

### 7.3 Qué es un certificado

Un **certificado** es un documento digital que dice: "esta clave pública pertenece a este nombre".
Contiene:

- La **clave pública** del servidor.
- El nombre al que corresponde: el **CN** (*Common Name*) y los **SAN** (*Subject Alternative
  Names*, la lista de nombres e IP válidos).
- Fechas de validez.
- La **firma** de quien lo emitió.

Es como un DNI: un documento con tus datos, firmado por una autoridad que da fe de que son
ciertos.

Esa autoridad se llama **CA** (*Certificate Authority*). Los navegadores traen de fábrica una
lista de CA en las que confían. Cuando entrás a un banco, el navegador revisa que el certificado
esté firmado por una de ellas y que el nombre coincida.

### 7.4 Certificado autofirmado

Un certificado **autofirmado** es uno que el servidor se firma a sí mismo. Es como un DNI hecho en
casa: los datos pueden ser correctos, pero no hay ninguna autoridad que los respalde.

Consecuencias:

- **El cifrado funciona exactamente igual.** La conversación es privada.
- **La autenticidad no está garantizada.** El navegador no puede comprobar quién emitió el
  certificado y muestra la advertencia "la conexión no es privada".

Por eso la advertencia es **esperada** en este TP, y por eso se usa `curl -k`: la opción `-k` le
dice a curl "no verifiques quién firmó el certificado".

¿Por qué no usamos uno "de verdad"? Una CA solo emite certificados para un **dominio** que
demuestres controlar. No tenemos dominio, y la IP de la EC2 cambia en cada sesión del sandbox.

### 7.5 El saludo inicial (*handshake*), simplificado

Antes de intercambiar datos, navegador y servidor hacen un saludo:

1. El navegador dice "hola" e informa qué versiones y algoritmos soporta.
2. El servidor responde con su **certificado**.
3. Los dos hacen un **intercambio de claves** (el `ECDHE` de la lista de cifrados): cada uno
   aporta un número aleatorio y, con matemática, ambos llegan a la **misma llave secreta** sin que
   esa llave viaje nunca por la red.
4. El servidor **firma** el intercambio con su clave privada. Así prueba que tiene la clave
   privada que corresponde al certificado.
5. Desde ahí, todo viaja cifrado con esa llave secreta, que es simétrica y se usa solo en esta
   sesión.

Como la llave de cada sesión se descarta al terminar, aunque alguien robara la clave privada más
adelante **no podría descifrar conversaciones viejas** que hubiera grabado. Esa propiedad se llama
***forward secrecy***.

### 7.6 Por qué la clave privada es el secreto más importante

Quien tenga la clave privada puede **hacerse pasar por nuestro servidor**. Por eso:

- No va al repositorio Git (el `.gitignore` ignora `*.key`, `*.pem`, `*.crt`).
- No entra a la imagen (el `.dockerignore` la excluye, y además nunca se genera en el build).
- Tiene permisos `400`: solo su dueño puede leerla.

### 7.7 La decisión central: generar el certificado al arrancar, no al construir

El enunciado deja elegir entre dos momentos:

| | En el build (`Dockerfile`) | Al arrancar el contenedor (*runtime*) |
|---|---|---|
| ¿Dónde queda la clave? | **Dentro de la imagen** | En un volumen de la máquina donde corre |
| ¿Quién puede obtenerla? | Cualquiera que descargue la imagen pública de Docker Hub | Solo quien tenga acceso a esa máquina |
| ¿Es la misma en todos los despliegues? | Sí | No: cada despliegue genera la suya |

Elegimos **runtime**. La imagen es pública: una clave generada en el build quedaría a disposición
de cualquiera, y eso contradice la regla de "nunca poner secretos en una imagen". Con runtime, la
imagen publicada tiene la carpeta `/etc/nginx/certs` vacía.

### 7.8 El script `40-generar-certificado.sh`, línea por línea

**Cómo se ejecuta.** La imagen oficial de NGINX, antes de iniciar el servidor, corre todos los
scripts que encuentre en la carpeta `/docker-entrypoint.d/`, en orden alfabético. Nosotros solo
agregamos el nuestro ahí. El `40-` del nombre lo ubica después de los que ya trae la imagen (10,
15, 20 y 30).

```sh
#!/bin/sh
set -eu
```

- `#!/bin/sh`: indica que el archivo se ejecuta con el intérprete `sh`.
- `set -eu`: si un comando falla (`-e`) o se usa una variable sin definir (`-u`), el script se
  detiene. Si no se puede generar el certificado, es mejor que el contenedor no arranque a que
  arranque roto.

```sh
CERT_DIR=/etc/nginx/certs
CRT="$CERT_DIR/tls.crt"
KEY="$CERT_DIR/tls.key"
CN="${TLS_CN:-fintech-nova.local}"
```

Variables con las rutas. `${TLS_CN:-fintech-nova.local}` significa "usá el valor de `TLS_CN` si
está definida; si no, `fintech-nova.local`". Es un nombre genérico, como permite el enunciado.

```sh
if [ -s "$CRT" ] && [ -s "$KEY" ]; then
    echo "$0: usando el certificado existente en $CERT_DIR"
    exit 0
fi
```

`-s` pregunta "¿el archivo existe y no está vacío?". Si ya hay certificado y clave, el script
termina sin hacer nada. Gracias a esto, el certificado **no cambia en cada reinicio**, y si el
grupo quisiera usar uno propio alcanza con montarlo en esa carpeta.

```sh
umask 077
openssl req -x509 -nodes -newkey rsa:2048 -sha256 -days 365 \
    -subj "/CN=$CN" \
    -addext "subjectAltName=DNS:$CN,DNS:localhost,IP:127.0.0.1" \
    -keyout "$KEY" -out "$CRT" 2>/dev/null
chmod 644 "$CRT"
chmod 400 "$KEY"
```

`umask 077` hace que todo archivo nuevo nazca accesible **solo para su dueño**. Así la clave no
queda legible por otros ni por un instante.

El comando `openssl`, opción por opción:

| Opción | Significado |
|---|---|
| `req -x509` | Generar directamente un certificado autofirmado. |
| `-nodes` | No proteger la clave con contraseña. NGINX tiene que poder leerla solo, sin que nadie tipee nada. |
| `-newkey rsa:2048` | Crear un par de claves nuevo, tipo RSA, de 2048 bits. |
| `-sha256` | Algoritmo usado para la firma. |
| `-days 365` | Válido por un año. |
| `-subj "/CN=..."` | El nombre del certificado. |
| `-addext "subjectAltName=..."` | Los nombres alternativos válidos. |
| `-keyout` / `-out` | Dónde guardar la clave privada y el certificado. |
| `2>/dev/null` | Descarta los mensajes de progreso. |

Al final, el certificado queda en `644` (es público, cualquiera puede leerlo) y la clave en `400`.

### 7.9 Terminación TLS

"Terminar" TLS significa ser el extremo del túnel cifrado. En nuestro caso:

```
Navegador ══ HTTPS (cifrado) ══► NGINX ── HTTP (sin cifrar) ──► api-clientes
            internet                       red interna de Docker
```

De NGINX hacia adentro se habla HTTP común. Es aceptable porque esa red es privada y no sale de la
máquina. La ventaja: hay **un solo certificado** que administrar, y las cinco APIs no necesitan
saber nada de TLS.

---

## 8. El servicio `web` en `docker-compose.yml`

```yaml
web:
  image: ${DOCKERHUB_USER:-tu-usuario}/fintech-nova-web:1.2.0
  ports: ["8443:8443"]
  volumes: [web_certs:/etc/nginx/certs]
  networks: [frontend]
  read_only: true
  tmpfs:
    - /tmp:uid=101,gid=101,mode=0700
    - /var/cache/nginx:uid=101,gid=101,mode=0700
  cap_drop: [ALL]
  security_opt: [no-new-privileges:true]
  logging:
    driver: json-file
    options: {max-size: "10m", max-file: "3"}
  restart: always
  deploy:
    resources:
      limits: {cpus: "0.25", memory: 64M, pids: 100}
```

| Línea | Qué hace | Por qué |
|---|---|---|
| `image` | La imagen a usar, descargada de Docker Hub. | El compose no usa `build:`. `<usuario>` es la cuenta de Docker Hub donde se publica. |
| `ports: ["8443:8443"]` | Conecta el puerto 8443 de la máquina con el 8443 del contenedor. | Es el **único** puerto publicado de todo el stack. |
| `volumes` | Monta el volumen `web_certs` en la carpeta del certificado. | El certificado sobrevive aunque se borre y recree el contenedor. |
| `networks: [frontend]` | Conecta `web` a la red `frontend`, que comparte con las APIs. | Para poder hablar con las APIs por su nombre. `web` no está en la red `backend`, así que no puede llegar a la base. |
| `read_only: true` | Todo el sistema de archivos del contenedor queda de solo lectura. | Si alguien entrara, no podría modificar la configuración ni dejar archivos. |
| `tmpfs` | Crea carpetas temporales **en memoria** para `/tmp` y la caché. | NGINX necesita escribir ahí. `uid=101` es el número del usuario `nginx`: sin eso, la carpeta sería de root y NGINX no podría usarla. |
| `cap_drop: [ALL]` | Quita todas las *capabilities*. | Son permisos especiales del sistema (por ejemplo, abrir puertos bajos). NGINX no necesita ninguna. |
| `no-new-privileges` | Impide que un proceso gane más permisos de los que tiene. | Cierra una vía clásica para convertirse en root. |
| `logging` | Rota los logs: máximo 3 archivos de 10 MB. | NGINX anota cada pedido. Sin tope, los logs podrían llenar el disco de la EC2. |
| `restart: always` | Si el contenedor se cae o la máquina se reinicia, vuelve a levantarse. | Lo exige el enunciado. |
| `limits` | Como máximo, un cuarto de CPU, 64 MB de memoria y 100 procesos. | La EC2 `t3.medium` tiene 2 CPU y 4 GB para siete contenedores. Un servicio desbocado no puede tirar abajo a los demás. |

`web` **no tiene `env_file`** porque no maneja ningún secreto, y **no tiene `depends_on`** porque,
gracias al resolver dinámico (6.8), arranca aunque las APIs todavía no estén listas.

---

## 9. El recorrido completo de un pedido

Supongamos que alguien abre `https://<ip>:8443/` y carga un cliente nuevo.

**Primero, la página:**

1. El navegador se conecta al puerto 8443 de la EC2. El Security Group de AWS deja pasar ese
   puerto.
2. Docker entrega la conexión al contenedor `web`.
3. Se hace el saludo TLS. El navegador muestra la advertencia por el certificado autofirmado y el
   usuario la acepta.
4. El navegador pide `GET /`. NGINX entra en `location /` y entrega `index.html`.
5. El HTML pide `/assets/index-xxxx.js` y el `.css`. NGINX los entrega desde `location /assets/`.
6. El JavaScript se ejecuta y dibuja la portada, los formularios y las tablas.

**Después, el alta:**

7. El usuario completa el formulario y aprieta "Agregar". El JavaScript hace
   `POST /api/clientes` con los datos en JSON.
8. NGINX recibe el pedido y entra en `location /api/clientes`. Verifica en orden: que el cuerpo no
   pase 64 KB, que la IP no haya superado el límite de pedidos y que el método esté permitido.
9. Reescribe la ruta: `/api/clientes` pasa a ser `/clientes`.
10. Le pregunta al DNS de Docker la IP de `api-clientes` y reenvía el pedido por HTTP al puerto
    8080 de ese contenedor.
11. La API valida los datos, los guarda en MariaDB y responde `201` con el cliente creado.
12. NGINX recibe esa respuesta, le agrega las cabeceras de seguridad, la cifra y la devuelve al
    navegador.
13. El JavaScript ve que la respuesta fue exitosa, limpia el formulario y recarga la tabla.

Si en el paso 10 la API estuviera caída, NGINX respondería `502` con el JSON genérico, y el
frontend mostraría "No se pudo guardar (HTTP 502)".

---

## 10. Cómo probar cada cosa

Todos los comandos se corren desde la raíz del repositorio, con el stack levantado.

| Qué querés ver | Comando | Resultado esperado |
|---|---|---|
| Que la página responde | `curl -k https://localhost:8443/` | El HTML |
| Que un proxy funciona | `curl -k https://localhost:8443/api/clientes` | Un JSON con clientes |
| Que el puerto 80 está cerrado | `curl http://localhost/` | Error de conexión |
| Que no acepta HTTP plano | `curl http://localhost:8443/` | 400 |
| El certificado | `openssl s_client -connect localhost:8443` | `CN=fintech-nova.local` |
| Las cabeceras de seguridad | `curl -k -I https://localhost:8443/` | `Content-Security-Policy`, etc. |
| Con qué usuario corre | `docker compose exec web id` | `uid=101(nginx)` |
| Los permisos de la clave | `docker compose exec web ls -l /etc/nginx/certs` | `tls.key` en `-r--------` |
| Que la imagen no trae clave | `docker run --rm --entrypoint ls <imagen> -la /etc/nginx/certs` | Carpeta vacía |
| Los pedidos registrados | `docker compose logs web` | Una línea por pedido |
| La configuración efectiva | `docker compose exec web nginx -T` | Toda la config de NGINX |

Si levantaste el stack con otro nombre de proyecto, agregá `-p <nombre>` después de
`docker compose`.

---

## 11. Preguntas probables en la presentación

**¿Por qué el Dockerfile es multietapa?**
Porque Node y Vite solo hacen falta para fabricar `dist/`. La imagen final lleva NGINX y los
archivos estáticos: pesa menos y tiene menos software que pueda tener fallas.

**¿Por qué generaron el certificado en runtime?**
Porque la imagen es pública. Generado en el build, la clave privada quedaría dentro de la imagen
y cualquiera podría descargarla.

**¿Por qué el navegador muestra una advertencia?**
Porque el certificado es autofirmado: ninguna autoridad reconocida da fe de él. El cifrado
funciona igual; lo que no se puede verificar es la identidad del servidor.

**¿Por qué 8443 y no 443?**
Porque NGINX corre sin root, y un programa sin root no puede abrir puertos menores a 1024.

**¿Por qué no hay puerto 80?**
El enunciado lo prohíbe, ni siquiera para redirigir. No hay ningún `listen 80`, y la configuración
por defecto de la imagen (que sí lo tenía) se reemplaza por la nuestra.

**¿Las APIs usan HTTPS?**
No. El TLS termina en NGINX. Puertas adentro se usa HTTP sobre la red privada de Docker.

**¿Cómo sabe NGINX dónde está cada API?**
Por el nombre del servicio en Compose. El DNS interno de Docker (`127.0.0.11`) lo traduce a la IP
del contenedor.

**¿Qué pasa si una API está caída?**
NGINX arranca igual, porque resuelve los nombres en cada pedido y no al inicio. Solo esa ruta
responde 502 y el resto del sistema sigue funcionando.

**¿Qué pasa si se reinicia el contenedor? ¿Cambia el certificado?**
No. Está guardado en el volumen `web_certs`, y el script lo reutiliza si ya existe.

**¿Cómo evitaron subir la clave al repositorio?**
Nunca existe como archivo en el repo: se genera dentro del contenedor. Además, el `.gitignore` y
el `.dockerignore` excluyen `*.key`, `*.pem` y `*.crt` como red de seguridad.

**¿Qué mejorarían?**
Agregar autenticación (hoy cualquiera que llegue al puerto puede borrar datos) y usar un
certificado emitido por una CA real, lo que requiere un dominio.

---

## 12. Glosario

| Término | Definición breve |
|---|---|
| **API** | Programa que recibe pedidos y devuelve datos, sin pantalla. |
| **ABM** | Alta, baja y modificación: crear, borrar y editar registros. |
| **Build** | Proceso de construir algo: una imagen de Docker, o la carpeta `dist/`. |
| **CA** | Autoridad certificante. Entidad que firma certificados y en la que los navegadores confían. |
| **Capa** | Cada paso de un Dockerfile genera una. Docker las reutiliza si no cambiaron. |
| **Certificado** | Documento que asocia una clave pública con un nombre. |
| **Clave privada** | La mitad secreta de un par de claves. Quien la tiene puede hacerse pasar por el servidor. |
| **CN / SAN** | Los nombres para los que vale un certificado. |
| **Contenedor** | Una imagen en ejecución, aislada del resto del sistema. |
| **CSP** | *Content-Security-Policy*. Cabecera que limita qué puede cargar y ejecutar una página. |
| **Digest** | Huella digital exacta de una imagen (`sha256:...`). |
| **DNS** | Servicio que traduce nombres a direcciones IP. |
| **Healthcheck** | Chequeo periódico para saber si un contenedor realmente funciona. |
| **Imagen** | Paquete cerrado con un programa y todo lo que necesita. |
| **Multistage** | Dockerfile con varias etapas; solo la última forma la imagen final. |
| **Proxy inverso** | Servidor que recibe pedidos y los reenvía a otros servidores. |
| **Rate limit** | Límite de pedidos por unidad de tiempo. |
| **Root** | Usuario administrador de Linux, con permiso para todo. |
| **Runtime** | El momento en que el contenedor está corriendo (en contraste con el build). |
| **TLS** | El protocolo de cifrado que convierte HTTP en HTTPS. |
| **Terminación TLS** | El punto donde se descifra el tráfico; acá, NGINX. |
| **Volumen** | Carpeta que Docker guarda aparte y que sobrevive al contenedor. |
| **XSS** | Ataque que consiste en inyectar un script propio en una página ajena. |
