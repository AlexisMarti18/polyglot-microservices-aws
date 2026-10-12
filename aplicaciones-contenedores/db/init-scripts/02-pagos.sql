USE db_pagos;

CREATE TABLE IF NOT EXISTS pagos (
    id INT AUTO_INCREMENT PRIMARY KEY,
    monto_ars DECIMAL(12,2) NOT NULL,
    monto_usd DECIMAL(12,2),
    medio_pago VARCHAR(30) NOT NULL,
    fecha TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO pagos (monto_ars, monto_usd, medio_pago) VALUES
(50000.00, NULL, 'transferencia'),
(12000.00, NULL, 'tarjeta_debito');
