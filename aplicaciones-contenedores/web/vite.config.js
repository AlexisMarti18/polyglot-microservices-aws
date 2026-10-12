import { defineConfig } from 'vite';

// En "npm run dev", Vite proxea /api/<servicio> al puerto correspondiente en localhost,
// simulando lo que en produccion hace NGINX (ver nginx/nginx.conf). Sirve para desarrollar
// el front corriendo las 5 APIs sueltas en el host (ver el README de cada api-*), sin tener
// que levantar todo el stack con Docker.
export default defineConfig({
  server: {
    proxy: {
      '/api/clientes': { target: 'http://localhost:8081', changeOrigin: true, rewrite: (p) => p.replace(/^\/api/, '') },
      '/api/pagos': { target: 'http://localhost:8082', changeOrigin: true, rewrite: (p) => p.replace(/^\/api/, '') },
      '/api/facturas': { target: 'http://localhost:8083', changeOrigin: true, rewrite: (p) => p.replace(/^\/api/, '') },
      '/api/transacciones': { target: 'http://localhost:8084', changeOrigin: true, rewrite: (p) => p.replace(/^\/api/, '') },
      '/api/tarjetas': { target: 'http://localhost:8085', changeOrigin: true, rewrite: (p) => p.replace(/^\/api/, '') },
    },
  },
});
