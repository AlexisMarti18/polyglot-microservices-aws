require('dotenv').config();
const express = require('express');
const pagosRouter = require('./routes/pagos');

const app = express();
// No anunciar el framework en la cabecera X-Powered-By (NGINX la reenvía tal cual).
app.disable('x-powered-by');
// Límite del body: un pago pesa pocos bytes; lo que supere 32 KB se rechaza con 413.
app.use(express.json({ limit: '32kb' }));

app.get('/', (_req, res) => {
  res.json({ status: 'ok', servicio: 'api-pagos' });
});

app.use('/pagos', pagosRouter);

app.use((_req, res) => {
  res.status(404).json({ error: 'Not Found' });
});

// Errores del parser de JSON (body > 32 KB o JSON mal formado): responder JSON, no la página HTML de Express.
app.use((err, _req, res, _next) => {
  if (err.type === 'entity.too.large') return res.status(413).json({ error: 'Body demasiado grande' });
  if (err.type === 'entity.parse.failed') return res.status(400).json({ error: 'JSON mal formado' });
  console.error(err);
  res.status(500).json({ error: 'Error interno' });
});

const PORT = process.env.PORT || 8080;
app.listen(PORT, '0.0.0.0', () => {
  console.log(`API de pagos escuchando en el puerto ${PORT}`);
});
