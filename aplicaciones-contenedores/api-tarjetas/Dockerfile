# ============================================
# Stage 1: Build — compilar con .NET SDK 8.0
# ============================================
FROM mcr.microsoft.com/dotnet/sdk:8.0-alpine AS build

WORKDIR /build

# Copiar .csproj primero para cachear dotnet restore
COPY ApiTarjetas.csproj .
RUN dotnet restore

# Copiar el código fuente y publicar
COPY . .
RUN dotnet publish -c Release -o /app/out

# ============================================
# Stage 2: Runtime — solo ASP.NET runtime (liviana)
# ============================================
FROM mcr.microsoft.com/dotnet/aspnet:8.0-alpine

WORKDIR /app

# Crear usuario no-root para seguridad
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

# Copiar la aplicación publicada desde el stage de build
COPY --from=build /app/out .

# Cambiar a usuario no-root
USER appuser

EXPOSE 8080

# La imagen Alpine trae wget (busybox). 127.0.0.1 y no "localhost": busybox resuelve localhost a ::1
# y la app escucha solo en IPv4 (0.0.0.0, ver Program.cs).
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD wget -qO- "http://127.0.0.1:${PORT:-8080}/" > /dev/null || exit 1

ENTRYPOINT ["dotnet", "ApiTarjetas.dll"]
