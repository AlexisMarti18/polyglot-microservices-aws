USE db_clientes;

CREATE TABLE IF NOT EXISTS clientes (
    id INT AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    email VARCHAR(150) NOT NULL,
    dni VARCHAR(20)
);

INSERT INTO clientes (nombre, email, dni) VALUES
('Ana Torres', 'ana.torres@example.com', '30111222'),
('Luis Fernandez', 'luis.fernandez@example.com', '28999888'),
('Sofia Martinez', 'sofia.martinez@example.com', '35222111');
