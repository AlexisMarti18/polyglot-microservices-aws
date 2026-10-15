# web (Vite)

Panel único que consume las 5 APIs del TP (clientes, pagos, facturas, transacciones, tarjetas).
Permite dar de alta, modificar (PUT) y borrar registros de cada entidad: el botón "Editar" de cada
fila carga el registro en el mismo formulario de alta. Si no cambió ningún campo, no se envía nada.
Es JavaScript vanilla + Vite (sin framework), pensado para mantener el ejercicio de Docker en
foco. Todas las llamadas van a rutas relativas `/api/<servicio>/...`.

## Cómo levantar en LOCAL (sin Docker)

### Opción A: con `npm run dev` (recomendado para desarrollar el front)
Vite trae un proxy configurado en `vite.config.js` que redirige cada `/api/<servicio>` al puerto
correspondiente en tu máquina. Para que funcione, corran las 5 APIs sueltas (ver el `README.md`
de cada `api-*`) en estos puertos:

| Servicio            | Puerto sugerido en local |
|----------------------|--------------------------|
| api-clientes         | 8081                     |
| api-pagos            | 8082                     |
| api-facturas         | 8083                     |
| api-transacciones    | 8084                     |
| api-tarjetas         | 8085                     |

```sh
cd web
npm install
npm run dev
```
Abrir `http://localhost:5173`.

### Opción B: build + servir estático (simula producción)
```sh
cd web
npm install
npm run build      # genera dist/
npm run preview    # sirve dist/ en un puerto local, PERO sin el proxy de /api
```
Para probar `/api/...` de verdad como en producción hace falta el reverse proxy de NGINX — por
eso el flujo real de este TP es dockerizar `web/` con NGINX sirviendo `dist/` (ver la sección
[Docker](#docker) más abajo) y usando `nginx/nginx.conf`, con los 5 proxys.

## Docker

> Para entender cada archivo y concepto desde cero (NGINX, TLS, multistage), ver [`GUIA.md`](./GUIA.md).

`web` es la **única entrada pública** del stack: sirve el front y reenvía `/api/<servicio>` a cada
API por la red `frontend` de Compose. Termina TLS y escucha **solo HTTPS en el puerto 8443**. No hay
puerto 80 en ningún lado.

| Archivo | Qué hace |
|---|---|
| `Dockerfile` | Multistage, con las imágenes base fijadas por digest. `node:22-alpine` corre `npm ci` + `npm run build`; `nginx:1.30-alpine` sirve solo `dist/`. Node, npm y `node_modules` no llegan a la imagen final. |
| `nginx/nginx.conf` | Se instala como `/etc/nginx/conf.d/default.conf` (reemplaza el server por defecto, que escucha en 80). HTTPS en 8443, TLS 1.2/1.3 con cifrados fuertes, cabeceras de seguridad, timeouts de 10 s, límite de body (64 KB → 413), rate limit en `/api` (10 r/s por IP, ráfaga 20 → 429), máximo 20 conexiones por IP, solo GET/POST/PUT/DELETE en `/api` y los 5 proxys. |
| `nginx/error.json` | Cuerpo genérico para los errores que genera NGINX (502, 413, 429...), en lugar de la página por defecto, que dice "nginx". |
| `nginx/40-generar-certificado.sh` | La imagen oficial de NGINX lo ejecuta al arrancar el contenedor. Si no hay certificado en `/etc/nginx/certs`, genera uno autofirmado con OpenSSL. Ver `SEGURIDAD.md`. |
| `.dockerignore` | Deja afuera `node_modules`, `dist`, `.git`, `.env`, docs, certificados y claves. |
| `.gitattributes` | Fuerza LF en `*.sh`, `*.conf` y `Dockerfile` (con CRLF, `#!/bin/sh\r` no ejecuta). |

Decisiones:

- **8443 y no 443:** NGINX corre como el usuario `nginx` (uid 101), no como root, y los puertos
  < 1024 requieren privilegios. Se publica `8443:8443` para que el puerto sea el mismo adentro, afuera
  y en el Security Group.
- **Certificado en runtime y no en build:** la imagen es pública en Docker Hub; si la clave se
  generara en el `Dockerfile`, cualquiera podría descargarla. Así la imagen tiene
  `/etc/nginx/certs` vacío.
- **Resolución DNS por pedido** (`resolver 127.0.0.11` + `set $upstream`): NGINX arranca aunque
  alguna API no exista todavía (esa ruta responde 502) y no queda con una IP vieja si un contenedor
  se recrea. Por eso `web` no necesita `depends_on`.
- **Sin `env_file`:** `web` no tiene secretos. `TLS_CN` es opcional (por defecto,
  `fintech-nova.local`).

### Build y prueba local

Desde la raíz del repo:

```sh
docker build -t ${DOCKERHUB_USER}/fintech-nova-web:1.2.0 ./aplicaciones-contenedores/web

# Solo web (las rutas /api responden 502 porque no hay APIs):
docker run --rm -p 8443:8443 ${DOCKERHUB_USER}/fintech-nova-web:1.2.0
curl -k https://localhost:8443/
```

Con todo el stack (`docker compose up -d`), abrir `https://localhost:8443` y aceptar la advertencia
del certificado autofirmado.

### Publicar

```sh
docker login
docker push ${DOCKERHUB_USER}/fintech-nova-web:1.2.0
```

La imagen es pública: la EC2 la descarga con `docker compose pull` sin necesidad de `docker login`.
