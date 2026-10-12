FROM mariadb:11.8.9-ubi9
COPY init-scripts/ /docker-entrypoint-initdb.d/
HEALTHCHECK --interval=10s --timeout=5s --start-period=30s --retries=6 \
  CMD healthcheck.sh --connect --innodb_initialized
