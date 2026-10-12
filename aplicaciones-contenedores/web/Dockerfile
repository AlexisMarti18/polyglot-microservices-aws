# Imagenes base fijadas por digest: un tag puede apuntar a otra imagen manana, el digest no.
# Para actualizarlas: docker buildx imagetools inspect <imagen>:<tag>

# ============================================
# Stage 1 — build: Node compila el front con Vite y genera dist/ (HTML, JS y CSS estaticos).
# Node, npm, vite y node_modules se quedan en esta etapa: no llegan a la imagen final.
# ============================================
FROM node:22-alpine@sha256:0a7108bf6c7bf5de370ffb1a3ed6be93d405b43ff159f681a8d18c0e2bc2e402 AS build

WORKDIR /app

# Copiar manifiestos primero para cachear la instalacion de dependencias
COPY package.json package-lock.json ./
RUN npm ci

COPY index.html vite.config.js ./
COPY src ./src
RUN npm run build

# ============================================
# Stage 2 — runtime: NGINX sirve dist/, termina TLS y hace de reverse proxy hacia las 5 APIs.
# ============================================
FROM nginx:1.30-alpine@sha256:0985e772fb9f729e6fa0980da05fca5d9c468e870eed43071545afa9d2e27d94

# - apk upgrade: aplica los parches de Alpine publicados despues de la imagen base (Trivy
#   encontro CVE ya corregidos en libexpat y libpng; ver SEGURIDAD.md).
# - openssl: para generar el certificado autofirmado al arrancar (la imagen base no lo trae).
# - Ajustes para correr como el usuario "nginx" (uid 101) en vez de root: se quita la directiva
#   "user" (solo sirve si arranca como root), el pid va a /tmp y el usuario puede escribir su cache
#   y la carpeta del certificado.
# - Al final se quitan curl, nc y apk: NGINX no los usa y solo le servirian a un atacante que
#   entrara al contenedor. La base de paquetes (/lib/apk/db) se conserva para que Trivy pueda
#   seguir escaneando la imagen. wget se queda porque lo usa el HEALTHCHECK.
RUN apk upgrade --no-cache && apk add --no-cache openssl \
  && sed -i -e '/^user /d' -e 's,^pid .*,pid /tmp/nginx.pid;,' /etc/nginx/nginx.conf \
  && install -d -o nginx -g nginx -m 700 /etc/nginx/certs \
  && chown -R nginx:nginx /var/cache/nginx \
  && apk del --no-cache curl \
  && rm -f /usr/bin/nc /sbin/apk

# Config, pagina de error y script quedan de root y de solo lectura para nginx.
# --chmod explicito: al construir desde Windows los archivos llegan como 755. Ojo: --chmod tambien
# se aplica a las carpetas que COPY crea, y una carpeta 644 no se puede abrir (ver ERRORES.md);
# por eso error.json va a /etc/nginx, que ya existe.
COPY --chmod=644 nginx/nginx.conf /etc/nginx/conf.d/default.conf
COPY --chmod=644 nginx/error.json /etc/nginx/error.json
COPY --chmod=755 nginx/40-generar-certificado.sh /docker-entrypoint.d/
# Si el repo se clono en Windows con core.autocrlf=true, los archivos llegan con CRLF y
# "#!/bin/sh\r" no ejecuta (ver ERRORES.md).
RUN sed -i 's/\r$//' /etc/nginx/conf.d/default.conf /docker-entrypoint.d/40-generar-certificado.sh

COPY --from=build /app/dist /usr/share/nginx/html

USER nginx

# Solo HTTPS. No hay puerto 80.
EXPOSE 8443

# busybox wget ya viene en Alpine. Valida certificados con OpenSSL, asi que hace falta
# --no-check-certificate para el autofirmado (ver ERRORES.md).
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -q --spider --no-check-certificate https://127.0.0.1:8443/ || exit 1

# ENTRYPOINT, CMD ("nginx -g 'daemon off;'") y STOPSIGNAL se heredan de la imagen oficial.
