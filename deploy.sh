#!/usr/bin/env bash
# Despliegue de punta a punta de FinTech Nova en una EC2 del AWS Academy Learner Lab.
#
#   1. Verifica los .env locales (que existan y que las credenciales coincidan con las de db).
#   2. Construye las 7 imagenes y las publica en Docker Hub.
#   3. (Opcional, --crear-ec2) Crea Security Group, par de llaves y EC2 con la AWS CLI.
#   4. Deja la instancia lista: instala Docker y el plugin de Docker Compose.
#   5. Copia docker-compose.yml y los .env por SSH (nunca por Git).
#   6. docker compose pull + up -d y espera a que los 7 servicios esten healthy.
#   7. Prueba el servicio publico con curl: frontend, los 5 /api/* y que el puerto 80 este cerrado.
#
# Uso (desde la raiz del repo, en Linux, macOS o Git Bash):
#   ./deploy.sh --host <ip-publica> --key <llave.pem>     # EC2 creada a mano por la consola
#   ./deploy.sh --crear-ec2                              # crea la EC2 con la AWS CLI
#   ./deploy.sh --help                                   # todas las opciones
#
# No hace falta copiar init-scripts/ ni el certificado TLS a la EC2: los init-scripts van dentro
# de la imagen de db, y el certificado lo genera el contenedor web al arrancar (ver SEGURIDAD.md).
set -euo pipefail

# ---------------------------------------------------------------------------------------------
# Configuracion (se puede cambiar con opciones o variables de entorno)
# ---------------------------------------------------------------------------------------------
DOCKERHUB_USER="${DOCKERHUB_USER:-tu-usuario}"
# El tag de cada imagen sale de docker-compose.yml (ver imagen_de), asi lo que se publica es
# exactamente lo que la EC2 descarga. Para sacar una version nueva, se cambia el tag en el compose.
HTTPS_PORT=8443
SERVICIOS=(db api-clientes api-pagos api-facturas api-transacciones api-tarjetas web)
APIS=(clientes pagos facturas transacciones tarjetas)
# Servicios que leen la base y tienen que usar el mismo usuario y clave que MYSQL_USER/MYSQL_PASSWORD.
APIS_CON_DB=(api-clientes api-pagos api-facturas api-transacciones api-tarjetas)

HOST=""
SSH_KEY=""
SSH_USER=""
SSH_PORT=22
SO="ubuntu"                 # ubuntu (Ubuntu Server 26.04) o al2023 (Amazon Linux 2023)
CREAR_EC2=false
BUILD=true
REMOTE_DIR="fintech-nova"   # relativo al home del usuario remoto
REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
TIPO_INSTANCIA="t3.medium"
DISCO_GB=20

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ESTADO_DIR="$RAIZ/.deploy"  # datos de la ultima EC2 creada (ignorado por Git)

# ---------------------------------------------------------------------------------------------
# Utilidades
# ---------------------------------------------------------------------------------------------
if [ -t 1 ]; then V=$'\e[32m'; R=$'\e[31m'; A=$'\e[33m'; N=$'\e[1m'; X=$'\e[0m'; else V=""; R=""; A=""; N=""; X=""; fi
paso()  { printf '\n%s==> %s%s\n' "$N" "$*" "$X"; }
ok()    { printf '  %s✔%s %s\n' "$V" "$X" "$*"; }
aviso() { printf '  %s!%s %s\n' "$A" "$X" "$*"; }
error() { printf '%sERROR:%s %s\n' "$R" "$X" "$*" >&2; exit 1; }

ayuda() {
  cat <<EOF
Uso: ./deploy.sh [opciones]

Destino (uno de los dos):
  --host IP              IP o DNS publico de una EC2 ya creada
  --crear-ec2            Crea Security Group, par de llaves y EC2 ($TIPO_INSTANCIA) con la AWS CLI.
                         Necesita las credenciales del Learner Lab ("AWS Details" -> ~/.aws/credentials).

Opciones:
  --key RUTA             Llave privada SSH (.pem). Con --crear-ec2 se genera sola.
  --user USUARIO         Usuario SSH (por defecto: ubuntu para Ubuntu, ec2-user para Amazon Linux)
  --so ubuntu|al2023     Sistema operativo de la EC2 (por defecto: ubuntu)
  --ssh-port PUERTO      Puerto SSH (por defecto: 22)
  --sin-build            No construye ni publica las imagenes (usa las que ya estan en Docker Hub)
  --dockerhub-user U     Cuenta de Docker Hub (por defecto: $DOCKERHUB_USER)
  --region REGION        Region de AWS (por defecto: $REGION)
  -h, --help             Muestra esta ayuda

Ejemplos:
  ./deploy.sh --crear-ec2
  ./deploy.sh --host 54.10.20.30 --key ~/.ssh/labsuser.pem
  ./deploy.sh --host 54.10.20.30 --key ~/.ssh/labsuser.pem --so al2023 --sin-build
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --host)           HOST="${2:?falta el valor de --host}"; shift 2 ;;
    --key)            SSH_KEY="${2:?falta el valor de --key}"; shift 2 ;;
    --user)           SSH_USER="${2:?falta el valor de --user}"; shift 2 ;;
    --so)             SO="${2:?falta el valor de --so}"; shift 2 ;;
    --ssh-port)       SSH_PORT="${2:?falta el valor de --ssh-port}"; shift 2 ;;
    --crear-ec2)      CREAR_EC2=true; shift ;;
    --sin-build)      BUILD=false; shift ;;
    --dockerhub-user) DOCKERHUB_USER="${2:?falta el valor de --dockerhub-user}"; shift 2 ;;
    --region)         REGION="${2:?falta el valor de --region}"; shift 2 ;;
    -h|--help)        ayuda; exit 0 ;;
    *)                ayuda >&2; error "opcion desconocida: $1" ;;
  esac
done

case "$SO" in
  ubuntu) SSH_USER="${SSH_USER:-ubuntu}" ;;
  al2023) SSH_USER="${SSH_USER:-ec2-user}" ;;
  *)      error "--so tiene que ser ubuntu o al2023" ;;
esac
if $CREAR_EC2 && [ -n "$HOST" ]; then error "usar --host o --crear-ec2, no los dos"; fi
if ! $CREAR_EC2 && [ -z "$HOST" ]; then ayuda >&2; error "falta --host o --crear-ec2"; fi
if ! $CREAR_EC2 && [ -z "$SSH_KEY" ]; then error "falta --key con la llave SSH de la instancia"; fi

cd "$RAIZ"
mkdir -p "$ESTADO_DIR"
KNOWN_HOSTS="$ESTADO_DIR/known_hosts"

# ---------------------------------------------------------------------------------------------
# 1. Requisitos y .env locales
# ---------------------------------------------------------------------------------------------
paso "1/7 Verificando requisitos y archivos .env"

for cmd in ssh curl tar; do
  command -v "$cmd" >/dev/null || error "falta '$cmd' en esta maquina"
done
if $BUILD || $CREAR_EC2; then command -v docker >/dev/null || error "falta 'docker' en esta maquina"; fi
ok "herramientas necesarias presentes"

# Lee una variable de un .env sin ejecutarlo (sin "source": el archivo no es un script).
leer_env() { sed -n "s/^$2=//p" "$1" | tail -n 1 | tr -d '\r'; }

for s in "${SERVICIOS[@]}"; do
  [ "$s" = web ] && continue   # web no tiene secretos ni env_file
  f="aplicaciones-contenedores/$s/.env"
  [ -f "$f" ] || error "falta $f (copiar aplicaciones-contenedores/$s/env.example y completarlo)"
done
DB_ENV=aplicaciones-contenedores/db/.env
for v in MYSQL_ROOT_PASSWORD MYSQL_USER MYSQL_PASSWORD; do
  [ -n "$(leer_env "$DB_ENV" "$v")" ] || error "$v esta vacio en $DB_ENV"
done
# Un DB_PASSWORD distinto al de la base da 500 en la API aunque el contenedor quede healthy
# (ERRORES.md, api-transacciones error 1). Se compara aca, antes de desplegar.
for s in "${APIS_CON_DB[@]}"; do
  f="aplicaciones-contenedores/$s/.env"
  [ "$(leer_env "$f" DB_HOST)" = db ] || error "$f: DB_HOST tiene que ser 'db' (el servicio de Compose)"
  [ "$(leer_env "$f" DB_USER)" = "$(leer_env "$DB_ENV" MYSQL_USER)" ] \
    || error "$f: DB_USER no coincide con MYSQL_USER de $DB_ENV"
  [ "$(leer_env "$f" DB_PASSWORD)" = "$(leer_env "$DB_ENV" MYSQL_PASSWORD)" ] \
    || error "$f: DB_PASSWORD no coincide con MYSQL_PASSWORD de $DB_ENV"
done
ok "6 archivos .env presentes y con credenciales coherentes (no se muestran)"

# ---------------------------------------------------------------------------------------------
# 2. Build y push
# ---------------------------------------------------------------------------------------------
# Imagen de un servicio con el tag que declara docker-compose.yml (por ejemplo web -> ...:1.2.0).
imagen_de() {
  local tag
  tag="$(grep -E "^ *image: *[^ ]*/fintech-nova-$1:" docker-compose.yml | head -n 1 | tr -d '\r ' | sed 's/.*://')"
  [ -n "$tag" ] || error "no se encontro la imagen de $1 en docker-compose.yml"
  printf '%s/fintech-nova-%s:%s' "$DOCKERHUB_USER" "$1" "$tag"
}

if $BUILD; then
  paso "2/7 Construyendo y publicando las imagenes en Docker Hub ($DOCKERHUB_USER, tags de docker-compose.yml)"
  for s in "${SERVICIOS[@]}"; do
    img="$(imagen_de "$s")"
    # linux/amd64: la t3.medium es x86. Sin esto, alguien con una Mac M1/M2 publicaria imagenes ARM.
    docker build --platform linux/amd64 -q -t "$img" "aplicaciones-contenedores/$s" >/dev/null \
      || error "fallo el build de $s"
    ok "build $img"
  done
  for s in "${SERVICIOS[@]}"; do
    img="$(imagen_de "$s")"
    docker push -q "$img" >/dev/null \
      || error "fallo el push de $img (hace falta 'docker login' con la cuenta $DOCKERHUB_USER)"
    ok "push $img"
  done
else
  paso "2/7 Build y push omitidos (--sin-build): se usan las imagenes publicadas"
fi

# ---------------------------------------------------------------------------------------------
# 3. (Opcional) Crear la EC2 con la AWS CLI
# ---------------------------------------------------------------------------------------------
# Si no esta instalada, se usa la imagen oficial amazon/aws-cli con las credenciales de ~/.aws.
aws_cli() {
  if command -v aws >/dev/null; then
    aws --region "$REGION" --output text "$@"
  else
    local dir_aws="$HOME/.aws"
    # En Git Bash, Docker Desktop necesita la ruta en formato Windows (C:\Users\...).
    if command -v cygpath >/dev/null; then dir_aws="$(cygpath -w "$dir_aws")"; fi
    MSYS_NO_PATHCONV=1 docker run --rm -i -v "$dir_aws:/root/.aws:ro" \
      -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_SESSION_TOKEN \
      amazon/aws-cli --region "$REGION" --output text "$@"
  fi
}

if $CREAR_EC2; then
  paso "3/7 Creando la infraestructura en AWS ($REGION)"
  if [ ! -f "$HOME/.aws/credentials" ] && [ -z "${AWS_ACCESS_KEY_ID:-}" ]; then
    error "sin credenciales de AWS: en el Learner Lab, 'AWS Details' -> 'AWS CLI: Show' y pegar ese bloque en ~/.aws/credentials"
  fi
  aws_cli sts get-caller-identity --query Account >/dev/null \
    || error "sin credenciales de AWS: copiar 'AWS Details' del Learner Lab a ~/.aws/credentials"
  ok "credenciales de AWS validas"

  SUFIJO="$(date +%Y%m%d-%H%M%S)"
  MI_IP="$(curl -fsS https://checkip.amazonaws.com | tr -d '[:space:]')"
  [ -n "$MI_IP" ] || error "no se pudo averiguar la IP publica de esta maquina"
  ok "IP de esta maquina: $MI_IP (unico origen permitido para SSH)"

  case "$SO" in
    ubuntu) PARAM_AMI=/aws/service/canonical/ubuntu/server/26.04/stable/current/amd64/hvm/ebs-gp3/ami-id ;;
    al2023) PARAM_AMI=/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 ;;
  esac
  AMI="$(aws_cli ssm get-parameter --name "$PARAM_AMI" --query Parameter.Value)" \
    || error "no se encontro la AMI ($PARAM_AMI). Probar con --so al2023"
  VPC="$(aws_cli ec2 describe-vpcs --filters Name=is-default,Values=true --query 'Vpcs[0].VpcId')"
  [ "$VPC" != None ] || error "la cuenta no tiene VPC por defecto"
  # El disco raiz se llama distinto segun la AMI (/dev/sda1 en Ubuntu, /dev/xvda en Amazon Linux).
  DISCO_RAIZ="$(aws_cli ec2 describe-images --image-ids "$AMI" --query 'Images[0].RootDeviceName')"
  ok "AMI $AMI ($SO), VPC por defecto $VPC"

  # Par de llaves: la clave privada se guarda FUERA del repo, con permisos 600.
  KEY_NAME="fintech-nova-$SUFIJO"
  SSH_KEY="$HOME/.ssh/$KEY_NAME.pem"
  mkdir -p "$HOME/.ssh"
  ( umask 077; aws_cli ec2 create-key-pair --key-name "$KEY_NAME" --key-type rsa \
      --query KeyMaterial > "$SSH_KEY" )
  chmod 600 "$SSH_KEY"
  ok "par de llaves $KEY_NAME -> $SSH_KEY"

  # Security Group: SSH solo desde esta IP y HTTPS 8443 desde cualquier lado. Nada mas: el 80
  # queda cerrado. La salida queda con la regla por defecto (todo), que necesitan apt/dnf,
  # docker pull y las APIs externas de api-pagos y api-transacciones.
  SG="$(aws_cli ec2 create-security-group --group-name "fintech-nova-$SUFIJO" --vpc-id "$VPC" \
        --description "FinTech Nova: SSH desde el equipo, HTTPS 8443 publico" --query GroupId)"
  aws_cli ec2 authorize-security-group-ingress --group-id "$SG" --ip-permissions \
    "IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges=[{CidrIp=$MI_IP/32,Description=SSH equipo}]" \
    "IpProtocol=tcp,FromPort=$HTTPS_PORT,ToPort=$HTTPS_PORT,IpRanges=[{CidrIp=0.0.0.0/0,Description=HTTPS publico}]" \
    >/dev/null
  ok "Security Group $SG: 22/tcp desde $MI_IP/32, $HTTPS_PORT/tcp desde 0.0.0.0/0"

  INSTANCIA="$(aws_cli ec2 run-instances --image-id "$AMI" --instance-type "$TIPO_INSTANCIA" \
    --key-name "$KEY_NAME" --security-group-ids "$SG" --associate-public-ip-address \
    --block-device-mappings "DeviceName=$DISCO_RAIZ,Ebs={VolumeSize=$DISCO_GB,VolumeType=gp3}" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=fintech-nova}]" \
    --query 'Instances[0].InstanceId')"
  ok "instancia $INSTANCIA creada, esperando a que arranque..."
  aws_cli ec2 wait instance-running --instance-ids "$INSTANCIA"
  HOST="$(aws_cli ec2 describe-instances --instance-ids "$INSTANCIA" \
          --query 'Reservations[0].Instances[0].PublicIpAddress')"
  ok "instancia en ejecucion, IP publica $HOST"

  # Datos para AWS_EC2.md y para borrar todo despues. Sin secretos (la llave queda en ~/.ssh).
  cat > "$ESTADO_DIR/ec2.env" <<EOF
FECHA=$SUFIJO
REGION=$REGION
INSTANCIA=$INSTANCIA
IP_PUBLICA=$HOST
AMI=$AMI
SO=$SO
VPC=$VPC
SECURITY_GROUP=$SG
KEY_NAME=$KEY_NAME
SSH_KEY=$SSH_KEY
SSH_USER=$SSH_USER
IP_EQUIPO=$MI_IP
EOF
  ok "datos guardados en .deploy/ec2.env"
else
  paso "3/7 Creacion de la EC2 omitida: se usa $HOST"
  [ -f "$SSH_KEY" ] || error "no existe la llave $SSH_KEY"
fi

# ---------------------------------------------------------------------------------------------
# 4. Preparar la instancia
# ---------------------------------------------------------------------------------------------
SSH_OPTS=(-i "$SSH_KEY" -p "$SSH_PORT" -o BatchMode=yes -o ConnectTimeout=10
          -o StrictHostKeyChecking=accept-new
          # Comillas dentro del valor: ssh corta la opcion en el primer espacio (la ruta puede tenerlos).
          -o "UserKnownHostsFile=\"$KNOWN_HOSTS\"")
# shellcheck disable=SC2029 # ~/$REMOTE_DIR se expande a proposito del lado local
remoto() { ssh "${SSH_OPTS[@]}" "$SSH_USER@$HOST" "$@"; }

paso "4/7 Preparando la instancia ($SSH_USER@$HOST): Docker + plugin de Compose"
# Cada sesion del Learner Lab puede reutilizar la IP con otra instancia: se olvida la huella vieja.
ssh-keygen -R "[$HOST]:$SSH_PORT" -f "$KNOWN_HOSTS" >/dev/null 2>&1 || true
ssh-keygen -R "$HOST" -f "$KNOWN_HOSTS" >/dev/null 2>&1 || true
# Una EC2 recien creada tarda en aceptar SSH: se reintenta hasta 2,5 minutos.
for i in $(seq 1 30); do
  ERROR_SSH="$(remoto true 2>&1)" && break
  if [ "$i" -eq 30 ]; then
    printf '%s\n' "$ERROR_SSH" | tail -n 5 | sed 's/^/  ssh: /' >&2
    error "no se pudo conectar por SSH a $SSH_USER@$HOST:$SSH_PORT"
  fi
  sleep 5
done
ok "conexion SSH establecida"

# El script remoto es idempotente: si Docker y Compose ya estan, no reinstala nada.
if ! remoto 'bash -s' <<'REMOTO'; then
set -euo pipefail
. /etc/os-release
if ! command -v docker >/dev/null; then
  echo "  instalando Docker ($PRETTY_NAME)..."
  case "$ID" in
    ubuntu|debian)
      # La variable va en el mismo comando: el sudo-rs de Ubuntu 26.04 ignora "sudo -E".
      sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
      sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq docker.io >/dev/null
      sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq docker-compose-v2 >/dev/null 2>&1 || true ;;
    amzn|fedora|rhel)
      sudo dnf install -y -q docker >/dev/null ;;
    *) echo "sistema no soportado: $ID" >&2; exit 1 ;;
  esac
fi
# Arranca Docker y lo deja habilitado al reiniciar la instancia.
if [ -d /run/systemd/system ]; then
  sudo systemctl enable --now docker >/dev/null 2>&1
elif ! pgrep -x dockerd >/dev/null; then
  # Sin systemd (por ejemplo, el contenedor que simula la EC2 para probar este script).
  sudo sh -c 'nohup dockerd >/var/log/dockerd.log 2>&1 &'
fi
for i in $(seq 1 60); do
  sudo docker info >/dev/null 2>&1 && break
  if [ "$i" -eq 60 ]; then echo "el daemon de Docker no responde" >&2; exit 1; fi
  sleep 1
done
# Plugin de Compose: Amazon Linux no lo empaqueta, y en Ubuntu puede faltar el paquete.
if ! sudo docker compose version >/dev/null 2>&1; then
  echo "  instalando el plugin de Docker Compose..."
  sudo mkdir -p /usr/local/lib/docker/cli-plugins
  sudo curl -fsSL -o /usr/local/lib/docker/cli-plugins/docker-compose \
    "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-$(uname -m)"
  sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
fi
# El usuario queda en el grupo docker para las proximas sesiones SSH (en esta se usa sudo).
sudo usermod -aG docker "$USER"
echo "  $(sudo docker --version)"
echo "  $(sudo docker compose version)"
REMOTO
  error "no se pudo preparar la instancia (ver la salida de arriba)"
fi
ok "Docker y Docker Compose listos"

# ---------------------------------------------------------------------------------------------
# 5. Copiar compose y .env
# ---------------------------------------------------------------------------------------------
paso "5/7 Copiando docker-compose.yml y los .env a ~/$REMOTE_DIR"
# Se mandan por el canal cifrado de SSH, nunca por Git. Quedan con permisos 600 (solo el usuario).
ARCHIVOS=(docker-compose.yml)
for s in "${SERVICIOS[@]}"; do
  [ "$s" = web ] || ARCHIVOS+=("aplicaciones-contenedores/$s/.env")
done
tar -cf - "${ARCHIVOS[@]}" | remoto "umask 077 && mkdir -p ~/$REMOTE_DIR && tar -xf - -C ~/$REMOTE_DIR \
  && echo 'DOCKERHUB_USER=$DOCKERHUB_USER' > ~/$REMOTE_DIR/.env \
  && find ~/$REMOTE_DIR -name .env -exec chmod 600 {} +"
ok "${#ARCHIVOS[@]} archivos copiados (compose + 6 .env)"

# ---------------------------------------------------------------------------------------------
# 6. Levantar el stack
# ---------------------------------------------------------------------------------------------
paso "6/7 docker compose pull + up -d"
if ! SALIDA="$(remoto "cd ~/$REMOTE_DIR && sudo DOCKERHUB_USER='$DOCKERHUB_USER' docker compose pull -q && sudo DOCKERHUB_USER='$DOCKERHUB_USER' docker compose up -d --remove-orphans" 2>&1)"; then
  printf '%s\n' "$SALIDA" | tail -n 15 | sed 's/^/  /'
  error "fallo docker compose pull/up en la instancia"
fi
ok "imagenes descargadas de Docker Hub y contenedores creados"
# Espera a que los 7 servicios esten healthy (Spring Boot y la primera inicializacion de
# MariaDB tardan): hasta 5 minutos.
for i in $(seq 1 60); do
  SALUD="$(remoto "cd ~/$REMOTE_DIR && sudo DOCKERHUB_USER='$DOCKERHUB_USER' docker compose ps --format '{{.Service}} {{.Health}}'")"
  SANOS="$(grep -c ' healthy$' <<<"$SALUD" || true)"
  [ "$SANOS" -ge "${#SERVICIOS[@]}" ] && break
  if [ "$i" -eq 60 ]; then
    remoto "cd ~/$REMOTE_DIR && sudo DOCKERHUB_USER='$DOCKERHUB_USER' docker compose ps"
    error "a los 5 minutos solo $SANOS/${#SERVICIOS[@]} servicios estan healthy (ver 'docker compose logs')"
  fi
  sleep 5
done
remoto "cd ~/$REMOTE_DIR && sudo DOCKERHUB_USER='$DOCKERHUB_USER' docker compose ps --format 'table {{.Service}}\t{{.Status}}\t{{.Ports}}'" | sed 's/^/  /'
ok "${#SERVICIOS[@]}/${#SERVICIOS[@]} servicios healthy"

# ---------------------------------------------------------------------------------------------
# 7. Pruebas desde afuera (como un usuario cualquiera)
# ---------------------------------------------------------------------------------------------
URL="https://$HOST:$HTTPS_PORT"
paso "7/7 Probando el servicio publico en $URL"
FALLAS=0
probar() {
  local ruta="$1" codigo
  # -k: el certificado es autofirmado. Se reintenta por si NGINX todavia esta arrancando.
  for _ in 1 2 3 4 5; do
    codigo="$(curl -sk -o /dev/null -w '%{http_code}' --max-time 10 "$URL$ruta" || true)"
    [ "$codigo" = 200 ] && break
    sleep 3
  done
  if [ "$codigo" = 200 ]; then ok "curl -k $URL$ruta -> 200"
  else printf '  %s✘%s curl -k %s%s -> %s\n' "$R" "$X" "$URL" "$ruta" "$codigo"; FALLAS=$((FALLAS + 1)); fi
}
probar /
for api in "${APIS[@]}"; do probar "/api/$api"; done

# HTTP sin cifrar no tiene que responder en ningun lado.
if curl -s -o /dev/null --max-time 5 "http://$HOST:80/"; then
  printf '  %s✘%s el puerto 80 responde: tiene que estar cerrado\n' "$R" "$X"; FALLAS=$((FALLAS + 1))
else
  ok "puerto 80 cerrado (sin respuesta HTTP)"
fi
if curl -s -o /dev/null --max-time 5 "http://$HOST:$HTTPS_PORT/" -w '%{http_code}' | grep -q '^400$'; then
  ok "HTTP plano contra el $HTTPS_PORT -> 400 (solo acepta TLS)"
fi

if [ "$FALLAS" -gt 0 ]; then error "$FALLAS prueba(s) fallaron"; fi

cat <<EOF

${V}${N}Despliegue OK${X}: $URL  (el navegador va a advertir por el certificado autofirmado)
SSH:  ssh -i "$SSH_KEY" $SSH_USER@$HOST

Evidencia para el README y AWS_EC2.md (todo en ESTA misma sesion del Learner Lab):
  [ ] Navegador en $URL/ con la portada de integrantes
  [ ] ABM de las 5 entidades desde el navegador
  [ ] Los 6 curl -k (/ y /api/*) desde una maquina del grupo
  [ ] docker compose ps en la EC2 (7 servicios healthy)
  [ ] Consola de AWS: detalle de la instancia (AMI, tipo, IP), VPC y subred
  [ ] Security Group: reglas de entrada y de salida
EOF
if $CREAR_EC2; then echo "Datos de la instancia (para AWS_EC2.md): .deploy/ec2.env"; fi
