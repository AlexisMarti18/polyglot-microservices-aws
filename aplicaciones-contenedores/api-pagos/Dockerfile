# ============================================
# Stage único — Node 22 LTS Alpine
# No hace falta multistage: es JS plano (sin compilación) y no hay devDependencies,
# así que "npm ci --omit=dev" ya deja solo lo necesario para producción.
# ============================================
FROM node:22-alpine

ENV NODE_ENV=production

WORKDIR /app

# Copiar manifiestos primero para cachear la instalación de dependencias
COPY package.json package-lock.json ./
# Después de instalar se borra npm: la app corre con "node" y no lo usa en runtime, y el npm
# de la imagen base trae dependencias con CVE (ver SEGURIDAD.md en la raíz).
RUN npm ci --omit=dev && npm cache clean --force \
  && rm -rf /usr/local/lib/node_modules/npm /usr/local/bin/npm /usr/local/bin/npx

# Copiar el código fuente (queda de root y solo lectura para el usuario de la app)
COPY src ./src

# Usuario no-root que ya trae la imagen oficial de Node
USER node

EXPOSE 8080

# Alpine trae wget (busybox): no hace falta instalar curl.
# 127.0.0.1 y no "localhost": busybox resuelve localhost a ::1 y la app escucha solo en IPv4.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- "http://127.0.0.1:${PORT:-8080}/" > /dev/null || exit 1

# node directo (sin npm start) para que sea PID 1 y reciba SIGTERM de docker stop
CMD ["node", "src/server.js"]
