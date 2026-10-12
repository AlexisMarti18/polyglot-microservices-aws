# Multistage build — api-pagos

**Decisión: no se usa multistage (1 stage sobre `node:22-alpine`).**

## Por qué no

Un build multistage sirve para dejar afuera de la imagen final lo que solo se necesita para
construir: compiladores, SDKs, dependencias de desarrollo y artefactos intermedios. En `api-pagos`
no hay nada de eso:

1. **No hay compilación.** Es JavaScript plano: `node src/server.js` ejecuta el código fuente tal
   cual. No hay TypeScript, bundler ni paso de build que genere un `dist/`.
2. **No hay devDependencies.** `package.json` declara solo `dependencies` (express, mysql2 y
   dotenv), y el único script es `start`. Con `npm ci --omit=dev` ya se instala solo lo que se usa
   en producción.
3. **Lo que queda de la instalación ya se limpia en la misma capa.**
   `npm ci --omit=dev && npm cache clean --force` corre en un solo `RUN`, así que la caché de npm
   no queda guardada en ninguna capa. En ese mismo `RUN` se borra `npm` (ver más abajo).

Un segundo stage copiaría el mismo `node_modules/` a la misma imagen base: el tamaño no cambiaría y
el `Dockerfile` sería más complejo.

## Medición

Capas de la imagen actual (`docker history`):

| Capa | Tamaño |
|---|---|
| Base `node:22-alpine` | 238 MB |
| `COPY package.json package-lock.json` | 49 kB |
| `RUN npm ci --omit=dev && npm cache clean --force && rm -rf .../npm` | 12.8 MB |
| `COPY src ./src` | 33 kB |
| **Total** | **253 MB en disco / ~63 MB comprimida** |

El 94 % de la imagen es la base de Node, y la aplicación con sus dependencias suma ~13 MB. Un
segundo stage solo podría recortar lo que el propio stage de build agrega, y acá no agrega nada que
sobre.

## Cache de capas (lo que sí se aprovecha)

Aunque haya un solo stage, el orden del `Dockerfile` aprovecha la caché:

```dockerfile
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force \
  && rm -rf /usr/local/lib/node_modules/npm /usr/local/bin/npm /usr/local/bin/npx
COPY src ./src
```

Si solo cambia el código de `src/`, Docker reutiliza la capa de `npm ci` y no reinstala nada.

## Se borra `npm` de la imagen final (sin multistage)

`npm` solo hace falta para instalar las dependencias: la app corre con `node src/server.js`. Además,
el `npm` que trae `node:22-alpine` incluye dependencias con CVE, y Trivy encontró ahí sus 13
hallazgos (8 HIGH). Por eso se borra en el mismo `RUN`, apenas termina `npm ci`.

- **Seguridad:** Trivy pasó de 13 vulnerabilidades a **0** (ver `../../SEGURIDAD.md`).
- **Tamaño:** no cambia (253 MB). `npm` vive en una capa de la imagen base, y un `rm` en una
  capa posterior solo lo oculta del sistema de archivos final: los bytes siguen en la capa de
  abajo. **Este es justamente el caso en que un multistage sí achicaría la imagen**: un runtime
  que no herede `npm` en ninguna capa.
- **Pruebas:** `which npm npx` no encuentra nada, `express`, `mysql2` y `dotenv` cargan, el
  contenedor queda `healthy` y el ABM responde igual que antes.

## Cuándo sí convendría

- **Si se pasa a TypeScript o se agrega un bundler:** un stage `build` con devDependencies
  (`tsc`, etc.) genera `dist/`, y el runtime copia solo `dist/` más las dependencias de
  producción.
- **Si se quiere achicar la base:** la imagen `node:22-alpine` trae herramientas que la app no usa
  en runtime: npm (17.2 MB; ahora se borra, pero sigue ocupando espacio en la capa base), yarn
  (5.1 MB) y corepack (0.8 MB), medidos con `du -sh`. Con un stage
  que instale las dependencias y un runtime sin gestores de paquetes (por ejemplo, una imagen
  distroless de Node) se ahorrarían esos ~23 MB, a cambio de no tener shell ni `wget` para el
  HEALTHCHECK actual. No se adoptó porque el ahorro es chico frente a los 238 MB de la base y
  complica el healthcheck y la depuración.
