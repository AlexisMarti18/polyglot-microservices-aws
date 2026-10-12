USE db_facturas;

CREATE TABLE IF NOT EXISTS facturas (
    id INT AUTO_INCREMENT PRIMARY KEY,
    numero VARCHAR(30) NOT NULL,
    monto DECIMAL(12,2) NOT NULL,
    cliente_id INT NOT NULL,
    fecha_emision DATE NOT NULL
);

INSERT INTO facturas (numero, monto, cliente_id, fecha_emision) VALUES
('A-0001', 25000.00, 1, '2026-01-15'),
('A-0002', 8000.00, 2, '2026-02-03');
