USE db_tarjetas;

CREATE TABLE IF NOT EXISTS tarjetas (
    id INT AUTO_INCREMENT PRIMARY KEY,
    alias VARCHAR(50) NOT NULL,
    titular VARCHAR(100) NOT NULL,
    tipo VARCHAR(20) NOT NULL,
    limite DECIMAL(12,2) NOT NULL
);

INSERT INTO tarjetas (alias, titular, tipo, limite) VALUES
('Visa Gold', 'Juan Perez', 'credito', 500000.00),
('Master Debit', 'Maria Gomez', 'debito', 100000.00);
