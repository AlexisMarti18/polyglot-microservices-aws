# ============================================
# Stage 1: Build — compilar con Maven + JDK 21
# ============================================
FROM maven:3.9-eclipse-temurin-21-alpine AS build

WORKDIR /build

# Copiar pom.xml primero para cachear dependencias Maven
COPY pom.xml .
RUN mvn dependency:go-offline -B

# Copiar el código fuente y compilar
COPY src ./src
RUN mvn clean package -DskipTests -B

# ============================================
# Stage 2: Runtime — solo JRE Alpine (liviana)
# ============================================
FROM eclipse-temurin:21-jre-alpine

WORKDIR /app

# Crear usuario no-root para seguridad
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

# Copiar el JAR compilado desde el stage de build
COPY --from=build /build/target/api-facturas.jar api-facturas.jar

# Cambiar a usuario no-root
USER appuser

# La JVM dimensiona el heap segun la memoria del contenedor (limite de docker-compose.yml) y no
# segun la de la EC2: 75% del limite para el heap, el resto para metaspace, threads y buffers.
# SerialGC: con 1 CPU o menos es el recolector que menos memoria y CPU consume.
ENV JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=75 -XX:+UseSerialGC"

EXPOSE 8080

# La imagen Alpine trae wget (busybox). La API no tiene ruta "/": se consulta el listado, que
# ademas confirma que la conexion a db_facturas funciona. 127.0.0.1: busybox resuelve localhost a ::1.
# start-period largo: Spring Boot tarda en arrancar con poca CPU.
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD wget -qO- "http://127.0.0.1:${PORT:-8080}/facturas" > /dev/null || exit 1

ENTRYPOINT ["java", "-jar", "api-facturas.jar"]
