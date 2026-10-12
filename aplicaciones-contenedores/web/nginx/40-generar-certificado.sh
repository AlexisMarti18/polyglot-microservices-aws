#!/bin/sh
# Genera el certificado TLS autofirmado al ARRANCAR el contenedor (runtime), no en el build:
# asi la clave privada nunca queda dentro de la imagen publica de Docker Hub ni en Git.
#
# La imagen oficial de nginx ejecuta los scripts de /docker-entrypoint.d/ antes de iniciar NGINX.
# Si ya hay un certificado en /etc/nginx/certs (volumen de Compose o uno montado a mano), se usa
# ese y no se genera otro: la clave sobrevive a los "docker compose up" y no cambia en cada reinicio.
set -eu

CERT_DIR=/etc/nginx/certs
CRT="$CERT_DIR/tls.crt"
KEY="$CERT_DIR/tls.key"
# No hay dominio y la IP de la EC2 cambia en cada sesion del sandbox: alcanza con un nombre generico.
CN="${TLS_CN:-fintech-nova.local}"

if [ -s "$CRT" ] && [ -s "$KEY" ]; then
    echo "$0: usando el certificado existente en $CERT_DIR"
    exit 0
fi

echo "$0: generando certificado autofirmado para CN=$CN"
# umask 077: la clave se crea directamente con permisos 600 (solo la lee el usuario nginx).
umask 077
openssl req -x509 -nodes -newkey rsa:2048 -sha256 -days 365 \
    -subj "/CN=$CN" \
    -addext "subjectAltName=DNS:$CN,DNS:localhost,IP:127.0.0.1" \
    -keyout "$KEY" -out "$CRT" 2>/dev/null
chmod 644 "$CRT"
# 400: ni el propio usuario nginx puede modificar la clave despues de crearla.
chmod 400 "$KEY"
