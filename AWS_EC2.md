# Configuración de AWS EC2

Datos de la **última sesión** del AWS Academy Learner Lab en la que se desplegó y probó todo el
stack: **2026-10-07**, sesión iniciada a las 13:16 (UTC−7). Todas las capturas son de esa misma
sesión y están en [`docs/capturas/`](./docs/capturas/).

> Cada vez que se relanza el sandbox, AWS entrega otra instancia, otra IP pública, otro Security
> Group y otras credenciales. La IP documentada acá ya no está activa; es la que se usó para las
> pruebas y las capturas del [README](./README.md#evidencia-de-funcionamiento).

## Resumen

| Dato | Valor |
|---|---|
| Región | `us-east-1` (N. Virginia) |
| Zona de disponibilidad | `us-east-1c` |
| Instancia | `i-028ea3351d16f69fb`, nombre `fintech-nova` |
| Tipo | `t3.medium` (2 vCPU, 4 GiB de RAM) |
| **IP pública** | **`54.152.76.222`** (asignada automáticamente; sin IP elástica) |
| DNS público | `ec2-54-152-76-222.compute-1.amazonaws.com` |
| IP privada | `172.31.34.87` (`ip-172-31-34-87.ec2.internal`) |
| URL del servicio | `https://54.152.76.222:8443/` |
| Disco | 1 volumen EBS de 20 GiB |
| Rol de IAM | Ninguno (la instancia no usa servicios de AWS) |
| Metadatos de instancia | IMDSv2 obligatorio (valor por defecto) |


## Sistema operativo / AMI

| Dato | Valor |
|---|---|
| Sistema operativo | **Ubuntu Server 26.04 LTS** (kernel `7.0.0-1006-aws`, x86_64) |
| AMI | `ami-0b6d9d3d33ba97d99` |
| Nombre en el catálogo | Ubuntu Server 26.04 LTS (HVM), SSD Volume Type |
| Proveedor | Canonical (*Verified provider*), creada el 2026-06-04 |
| Arquitectura | 64-bit (x86) |
| Usuario por defecto | `ubuntu` |

Se eligió Ubuntu porque `deploy.sh` instala Docker y Compose desde los paquetes oficiales de la
distribución (`docker.io` y `docker-compose-v2`), sin repositorios externos. El script también
soporta Amazon Linux 2023 (`--so al2023`).

## VPC y subred

| Dato | Valor |
|---|---|
| VPC | `vpc-0e6a2aaf665fa6037`: la VPC por defecto de la cuenta, la que propone el formulario de *Launch instance* |
| Subred | `subnet-0346b0543686d38c9`, en `us-east-1c` |
| IP pública | *Auto-assign public IP: Enable* |

Se usó la red por defecto porque el stack corre en una sola instancia y la única entrada es el
puerto 8443. La salida a internet, que necesitan `api-pagos` y `api-transacciones` para sus APIs
externas, va por el *internet gateway* de esa VPC con la IP pública de la instancia, sin NAT.

> En la misma cuenta del sandbox aparecen otras dos instancias, `Bastion Host` y `Lab Instance`. Las crea el propio Learner Lab y no forman parte de este despliegue.

## Security Group

`sg-0af62688c272137b8`, nombre **`fintech-nova-sg`**, creado en el mismo formulario de
*Launch instance*.

### Reglas de entrada

| Regla | Tipo | Protocolo | Puerto | Origen | Para qué |
|---|---|---|---|---|---|
| `sgr-09bc234833275d1f6` | SSH | TCP | **22** | **`<IP_ADMINISTRADOR>/32`** (IP pública autorizada, opción *My IP*) | SSH de `deploy.sh` y administración |
| `sgr-0adc20adba55d5da9` | Custom TCP | TCP | **8443** | **`0.0.0.0/0`** | HTTPS público: la única entrada al stack (NGINX en `web`) |

No hay ninguna otra regla. En particular:

- **El puerto 80 está cerrado.** No hay regla para él, NGINX no escucha en él y Compose no lo
  publica. Comprobado desde afuera: `curl -m 5 http://54.152.76.222:80/` termina por *timeout*
  ([captura](./docs/capturas/03-curl.png)).
- **Tampoco se abre el 443**, porque el HTTPS va por el 8443 (NGINX corre sin root y no puede
  abrir puertos menores a 1024). La descripción de la regla SSH dice "HTTPS 443 publico" por un
  error al cargarla; no corresponde a ninguna regla.
- **No se abren el 3306 de MariaDB ni el 8080 de las APIs:** ni siquiera se publican en el host.

### Reglas de salida

| Regla | Tipo | Protocolo | Puertos | Destino |
|---|---|---|---|---|
| `sgr-0ebe5ece8d6102f09` | All traffic | Todos | Todos | `0.0.0.0/0` |

Es la regla que AWS crea por defecto. La necesitan:

- la instalación de Docker y Compose (`apt`, puertos 80 y 443);
- `docker compose pull` desde Docker Hub (443);
- `api-pagos` → `open.er-api.com` (tipo de cambio) y `api-transacciones` → `ipapi.co`
  (geolocalización), ambas por HTTPS (443).

Limitar la salida a TCP 80 y 443 queda como mejora (ver [SEGURIDAD.md](./SEGURIDAD.md#6-security-group-de-la-ec2)).

## Conexión a la instancia

- **Método:** SSH desde Git Bash, en la PC del equipo cuya IP está autorizada en el Security
  Group.
- **Usuario:** `ubuntu`.
- **Llave:** el par `vockey` que provee el Learner Lab. La clave privada (`labsuser.pem`) se
  descarga de **AWS Details → Download PEM** y se guarda **fuera del repositorio**, en
  `~/.ssh/labsuser.pem` con permisos `600`.

```bash
ssh -i ~/.ssh/labsuser.pem ubuntu@54.152.76.222
```

`deploy.sh` usa esa misma conexión con `BatchMode=yes`, para que falle en vez de pedir datos, y
guarda la huella del servidor en `.deploy/known_hosts`, que Git ignora. Antes de conectar borra
la huella vieja de esa IP, por si el sandbox la reutiliza con otra instancia.

## Configuración previa a levantar los contenedores

La instancia se creó limpia, sin *user data*. Todo lo necesario lo hizo `deploy.sh` por SSH,
sin pasos manuales:

```bash
./deploy.sh --host 54.152.76.222 --key ~/.ssh/labsuser.pem --sin-build
```

| Paso | Qué se hizo en la instancia |
|---|---|
| 1. Docker | `apt-get install docker.io` → **Docker 29.1.3** |
| 2. Plugin de Compose | `apt-get install docker-compose-v2` → **Docker Compose 2.40.3** |
| 3. Servicio | `systemctl enable --now docker`: arranca ahora y al reiniciar la instancia |
| 4. Permisos | `usermod -aG docker ubuntu`, para usar `docker` sin `sudo` en las próximas sesiones SSH |
| 5. Archivos | Copia de `docker-compose.yml` y de los 6 `.env` a `~/fintech-nova/` por el canal SSH, con permisos `600` |
| 6. Imágenes | `docker compose pull`: las 7 imágenes públicas de Docker Hub |
| 7. Stack | `docker compose up -d` y espera hasta que los 7 servicios estén `healthy` |

Lo que **no** hizo falta:

- **`docker login` en la EC2:** las 7 imágenes son públicas. `--sin-build` usa las ya
  publicadas, así que tampoco hizo falta en la PC.
- **Copiar `db/init-scripts/`:** van dentro de la imagen `fintech-nova-db`.
- **Copiar el certificado TLS:** lo genera el contenedor `web` al arrancar, en el volumen
  `web_certs` de la instancia (ver [SEGURIDAD.md](./SEGURIDAD.md#2-certificado-tls)).

Resultado: 7/7 servicios `healthy`, los 6 `curl -k` con 200, el puerto 80 cerrado y HTTP plano
contra el 8443 rechazado con 400 ([captura](./docs/capturas/02-deploy.png)).

## Cómo se creó la infraestructura

Por la **consola web** de AWS (*EC2 → Instances → Launch instances*), en un único formulario:

| Sección del formulario | Valor |
|---|---|
| Name | `fintech-nova` |
| Application and OS Images | Ubuntu Server 26.04 LTS, 64-bit (x86) |
| Instance type | `t3.medium` |
| Key pair | `vockey` |
| Network settings | VPC por defecto, *Auto-assign public IP: Enable*, *Create security group* `fintech-nova-sg` con las 2 reglas de entrada |
| Configure storage | 20 GiB (en lugar de los 8 GiB por defecto: las 7 imágenes y sus capas ocupan varios GB) |

Los datos se verificaron después con la **AWS CLI** desde CloudShell:

```bash
aws ec2 describe-instances \
  --filters Name=tag:Name,Values=fintech-nova Name=instance-state-name,Values=running \
  --query 'Reservations[0].Instances[0].{ID:InstanceId,Tipo:InstanceType,AMI:ImageId,IP:PublicIpAddress,DNS:PublicDnsName,VPC:VpcId,Subred:SubnetId,AZ:Placement.AvailabilityZone,SG:SecurityGroups[0].GroupId}' \
  --output table
```

```
| AMI                   | AZ         | DNS                                       | ID                  | IP            | SG                   | Subred                   | Tipo      | VPC                   |
| ami-0b6d9d3d33ba97d99 | us-east-1c | ec2-54-152-76-222.compute-1.amazonaws.com | i-028ea3351d16f69fb | 54.152.76.222 | sg-0af62688c272137b8 | subnet-0346b0543686d38c9 | t3.medium | vpc-0e6a2aaf665fa6037 |
```

![Salida de la AWS CLI en CloudShell](./docs/capturas/10-aws-cli.png)

> **Nota sobre esta captura:** se ocultó un dato personal (el correo de la cuenta, arriba a la
> derecha) y el procesamiento de la imagen alteró algunos caracteres. Por ejemplo, la IP de la
> tabla se lee `24.152.76.222` en lugar de `54.152.76.222`, y varios IDs (Security Group, subred,
> VPC y AMI) difieren en uno o dos caracteres. **Los valores correctos son los de la tabla de texto
> de arriba.** Se pueden contrastar con el panel superior de la misma captura (ID de la instancia,
> IP pública y privada) y con los apartados 1 a 3 de [Evidencia de funcionamiento](./README.md#evidencia-de-funcionamiento).

La terminal propia del Learner Lab no tenía credenciales para la CLI; por eso se usó CloudShell
(ver [ERRORES.md](./ERRORES.md#aws-academy-learner-lab)).

`deploy.sh` también puede crear el Security Group, el par de llaves y la instancia con la AWS CLI
(`./deploy.sh --crear-ec2`), con las mismas reglas. En esta sesión no se usó: la infraestructura
se creó por la consola para documentar cada paso.
