# Multistage build — api-clientes

**Decisión: sí, se usa multistage (2 stages).** La primera versión pesaba *más* que una imagen
de un solo stage. Se corrigió quitando `pip` del venv, y ahora la multistage es la más chica (ver
la medición más abajo).

## Qué hace cada stage

```
builder (python:3.12-slim)             runtime (python:3.12-slim)
─────────────────────────────          ──────────────────────────────
python -m venv /opt/venv               usuario appuser (no-root)
pip install -r requirements.txt  ──►   COPY --from=builder /opt/venv
pip uninstall -y pip                   COPY app.py db_config.py main.py
                                       HEALTHCHECK + CMD gunicorn
```

El `builder` crea un entorno virtual en `/opt/venv`, instala ahí las dependencias y después
desinstala `pip` del venv. El `runtime` parte de una imagen limpia y copia solo el venv (ya sin
pip) y los tres archivos `.py`.

## Por qué sí

1. **El enunciado pide pensar si conviene un venv**, y multistage + venv es el patrón estándar
   para eso: todas las dependencias quedan en un solo directorio (`/opt/venv`), que se copia como
   una unidad al runtime, separado del Python del sistema.
2. **El runtime no hereda nada de la instalación.** Lo que `pip` deje durante el build (caché,
   archivos temporales, capas intermedias) queda en el `builder` y no llega a la imagen final.
3. **Deja lugar para dependencias compiladas.** Hoy las dependencias son Python puro y no necesitan
   compilador. Si en el futuro se agrega una que sí (por ejemplo, `mysqlclient`), `gcc` y los
   headers se instalan solo en el `builder` y el runtime no crece.
4. **Cache de capas.** `requirements.txt` se copia antes que el código, así que si solo cambia un
   `.py`, el `pip install` no se vuelve a ejecutar.

## Medición del tamaño

Para comparar, se construyeron variantes de un solo stage con el mismo código y las mismas
dependencias (2026-09-27, Docker Desktop):

| Variante | Tamaño en disco |
|---|---|
| Base `python:3.12-slim` sola (referencia) | 179 MB |
| Un stage, `pip install --no-cache-dir` | 201 MB |
| Un stage, `pip install` con caché | 205 MB |
| Multistage con venv, **primera versión** | 206 MB |
| **Multistage con venv sin pip (la imagen actual)** | **188 MB** (45.6 MB comprimida) |

Las variantes de un solo stage se midieron con PyMySQL 1.1.0, antes de subirlo a 1.2.3. La
diferencia de tamaño entre las dos versiones del driver es despreciable.

### Por qué la primera versión pesaba más

- **Las dependencias son chicas y no se compilan.** Flask, PyMySQL, Gunicorn y demás suman unos
  8 MB, y no hay herramientas de compilación que dejar afuera. La caché de pip, lo único que el
  multistage evitaba arrastrar, pesa ~4 MB, y `--no-cache-dir` ya la evita en un solo stage.
- **El venv traía su propia copia de `pip`.** `python -m venv` instala `pip` dentro de
  `/opt/venv`: eran 13 MB de los 22 MB del venv, según `du -sh`. Eso se sumaba al `pip` que ya trae
  la imagen base. En un solo stage, en cambio, se usa el `pip` del sistema.

### Qué se cambió

En el `builder`, `pip` se desinstala del venv después de instalar las dependencias. En runtime no
se instala nada, así que no hace falta:

```dockerfile
RUN pip install --no-cache-dir -r requirements.txt && pip uninstall -y pip
```

Resultado:

- El venv pasó de 22 MB a 8.4 MB y la imagen de 206 MB a **188 MB**, 13 MB menos que la mejor
  variante de un solo stage.
- Trivy dejó de reportar los 6 CVE del `pip` del venv (ver `../../SEGURIDAD.md`).
- Queda el `pip` de la imagen base (`/usr/local`), que no se usa, con sus 6 CVE.
- Pruebas: la imagen importa todas las dependencias, queda `healthy` y el ABM completo y las
  pruebas de validación dan los mismos resultados que antes.
