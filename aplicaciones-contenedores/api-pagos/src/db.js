const mysql = require('mysql2/promise');

// Esta API se conecta a "db_pagos", UNA de las 5 bases que viven en la MISMA instancia
// compartida de MariaDB (ver tp-2026/db).
const pool = mysql.createPool({
  host: process.env.DB_HOST || 'localhost',
  port: Number(process.env.DB_PORT) || 3306,
  database: process.env.DB_NAME || 'db_pagos',
  user: process.env.DB_USER || 'appuser',
  password: process.env.DB_PASSWORD || 'apppass',
  waitForConnections: true,
  connectionLimit: 5,
});

module.exports = pool;
