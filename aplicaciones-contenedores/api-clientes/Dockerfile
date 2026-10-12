# ============================================
# Stage 1: Builder — instalar dependencias en un venv
# El venv aísla las deps del Python del sistema y se copia entero al runtime,
# sin arrastrar la caché de pip ni capas intermedias.
# ============================================
FROM python:3.12-slim AS builder

RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Copiar requirements primero para cachear la instalación de dependencias
COPY requirements.txt .
# pip se desinstala del venv al terminar: en runtime no se instala nada, y así el venv no
# arrastra una segunda copia de pip (~13 MB y sus CVE; ver MULTISTAGE.md y SEGURIDAD.md en la raíz).
RUN pip install --no-cache-dir -r requirements.txt && pip uninstall -y pip

# ============================================
# Stage 2: Runtime — solo el venv y el código
# ============================================
FROM python:3.12-slim

# Sin .pyc en disco, logs sin buffer (docker logs) y venv activo
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/opt/venv/bin:$PATH"

WORKDIR /app

# Crear usuario no-root para seguridad
RUN groupadd -r appgroup && useradd -r -g appgroup appuser

# Copiar el venv desde el builder y el código (queda de root y solo lectura para appuser)
COPY --from=builder /opt/venv /opt/venv
COPY app.py db_config.py main.py ./

# Cambiar a usuario no-root
USER appuser

EXPOSE 8080

# La imagen slim no trae curl/wget: se usa Python, que ya está disponible.
# 127.0.0.1 y no "localhost": gunicorn escucha solo en IPv4 (0.0.0.0).
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD python -c "import os, urllib.request; urllib.request.urlopen('http://127.0.0.1:%s/' % (os.environ.get('PORT') or '8080'), timeout=4)" || exit 1

# Gunicorn en lugar del servidor de desarrollo de Flask (app.run).
# sh -c para expandir PORT; exec para que gunicorn sea PID 1 y reciba el SIGTERM de docker stop.
# --no-control-socket: gunicorn 26 abre un socket de control en $HOME, que appuser no tiene (ver ERRORES.md en la raíz).
CMD ["sh", "-c", "exec gunicorn --bind 0.0.0.0:${PORT:-8080} --workers 2 --no-control-socket main:app"]
