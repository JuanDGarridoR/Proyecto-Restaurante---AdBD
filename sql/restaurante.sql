CREATE DATABASE restaurante;

CREATE TABLE tipos (
    id SERIAL PRIMARY KEY,
    nombre TEXT
);

CREATE TABLE roles (
    id SERIAL PRIMARY KEY,
    nombre TEXT
);

CREATE TABLE mesas (
    id SERIAL PRIMARY KEY,
    sillas INT
);

CREATE TABLE usuarios (
    id SERIAL PRIMARY KEY,
    nombre TEXT,
    clave BYTEA,
    fecha_clave TIMESTAMP
);

CREATE TABLE actuaciones (
    id SERIAL PRIMARY KEY,
    rol_id INT REFERENCES roles(id),
    usuario_id INT REFERENCES usuarios(id)
);

CREATE TABLE platos (
    id SERIAL PRIMARY KEY,
    tipo_id INT REFERENCES tipos(id),
    nombre TEXT,
    descripcion TEXT,
    tiempo INTERVAL,
    precio NUMERIC
);

CREATE TABLE especialidades (
    id SERIAL PRIMARY KEY,
    cocinero_id INT REFERENCES usuarios(id),
    plato_id INT REFERENCES platos(id)
);

CREATE TABLE pedidos (
    id SERIAL PRIMARY KEY,
    cliente_id INT REFERENCES usuarios(id),
    mesero_id INT REFERENCES usuarios(id)
);

CREATE TABLE ordenes (
    id SERIAL PRIMARY KEY,
    plato_id INT REFERENCES platos(id),
    pedido_id INT REFERENCES pedidos(id),
    estado INT,
    cantidad INT CHECK (cantidad > 0),
    solicitado TIMESTAMP WITH TIME ZONE
);

CREATE TABLE preparaciones (
    id SERIAL PRIMARY KEY,
    cocinero_id INT REFERENCES usuarios(id),
    orden_id INT REFERENCES ordenes(id)
);

CREATE TABLE reservaciones (
    id SERIAL PRIMARY KEY,
    cliente_id INT REFERENCES usuarios(id),
    cantidad INT CHECK (cantidad > 0),
    estado INT
);

CREATE TABLE horarios (
    id SERIAL PRIMARY KEY,
    mesa_id INT REFERENCES mesas(id),
    reservacion_id INT REFERENCES reservaciones(id),
    inicio TIMESTAMP,
    duracion INTERVAL CHECK (duracion < INTERVAL '2 hours')
);