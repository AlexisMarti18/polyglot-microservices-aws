USE db_transacciones;

CREATE TABLE IF NOT EXISTS transacciones (
    id INT AUTO_INCREMENT PRIMARY KEY,
    origen_ip VARCHAR(45) NOT NULL,
    pais VARCHAR(60),
    monto DECIMAL(12,2) NOT NULL,
    tipo VARCHAR(30) NOT NULL
);

INSERT INTO transacciones (origen_ip, pais, monto, tipo) VALUES
('8.8.8.8', NULL, 3000.00, 'compra'),
('1.1.1.1', NULL, 15000.00, 'retiro');
