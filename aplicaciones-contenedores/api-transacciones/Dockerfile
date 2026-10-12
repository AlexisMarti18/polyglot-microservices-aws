# Contexto de build: esta carpeta (igual que el resto de los servicios):
#   docker build -t <usuario>/fintech-nova-api-transacciones:1.0.0 ./aplicaciones-contenedores/api-transacciones

FROM golang:1.27-alpine AS builder

WORKDIR /src

COPY go.mod go.sum ./
RUN go mod download && go mod verify

COPY *.go ./

# Binario estatico (sin cgo) y sin tabla de simbolos ni info de debug: no depende de libc y pesa menos.
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o main .


FROM alpine:3.24.2

# ca-certificates: la geolocalizacion llama a https://ipapi.co y sin CAs falla el TLS.
RUN apk add --no-cache ca-certificates
RUN addgroup -S app && adduser -S -G app app

USER app

COPY --from=builder /src/main /usr/local/bin/main

EXPOSE 8080

# wget de busybox (ya viene en Alpine) contra la ruta de health check "/".
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- "http://127.0.0.1:${PORT:-8080}/" > /dev/null || exit 1

ENTRYPOINT ["/usr/local/bin/main"]
