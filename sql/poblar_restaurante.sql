-- poblar_restaurante.sql
-- Base de datos: restaurante
-- PostgreSQL
-- Los IDs no se especifican manualmente; se utilizan las secuencias/DEFAULT.
-- Los estados 1, 2 y 3 son datos de prueba porque no se definió su semántica exacta.

BEGIN;

-- 1. ROLES
INSERT INTO roles (nombre) VALUES
('Administrador'), ('Mesero'), ('Cocinero'), ('Gerente'), ('Recepcionista');

-- 2. TIPOS
INSERT INTO tipos (nombre) VALUES
('Entrada'), ('Plato fuerte'), ('Postre'), ('Bebida'), ('Ensalada');

-- 3. USUARIOS
-- Estructura: id, nombre, clave BYTEA, fecha_clave TIMESTAMP.
INSERT INTO usuarios (nombre, clave, fecha_clave) VALUES
('Ana Torres', convert_to('clave_ana_2026','UTF8'), '2026-08-01 08:00:00'),
('Carlos Mendoza', convert_to('clave_carlos_2026','UTF8'), '2026-08-02 08:00:00'),
('Laura Gomez', convert_to('clave_laura_2026','UTF8'), '2026-08-03 08:00:00'),
('Miguel Rodriguez', convert_to('clave_miguel_2026','UTF8'), '2026-08-04 08:00:00'),
('Sofia Martinez', convert_to('clave_sofia_2026','UTF8'), '2026-08-05 08:00:00'),
('Andres Perez', convert_to('clave_andres_2026','UTF8'), '2026-08-06 08:00:00'),
('Valentina Rojas', convert_to('clave_valentina_2026','UTF8'), '2026-08-07 08:00:00'),
('Diego Castro', convert_to('clave_diego_2026','UTF8'), '2026-08-08 08:00:00'),
('Mariana Lopez', convert_to('clave_mariana_2026','UTF8'), '2026-08-09 08:00:00'),
('Julian Herrera', convert_to('clave_julian_2026','UTF8'), '2026-08-10 08:00:00');

-- 4. MESAS
INSERT INTO mesas (sillas) VALUES
(2), (2), (4), (4), (4), (6), (6), (8), (8), (10);

-- 5. PLATOS
INSERT INTO platos (tipo_id, nombre, descripcion, tiempo, precio) VALUES
((SELECT id FROM tipos WHERE nombre='Entrada'), 'Bruschettas de tomate', 'Pan tostado con tomate fresco, albahaca y aceite de oliva.', INTERVAL '15 minutes', 14000),
((SELECT id FROM tipos WHERE nombre='Entrada'), 'Sopa de tomate', 'Sopa cremosa de tomate con hierbas aromaticas.', INTERVAL '20 minutes', 12000),
((SELECT id FROM tipos WHERE nombre='Plato fuerte'), 'Pollo a la parrilla', 'Pechuga de pollo a la parrilla acompanada de vegetales.', INTERVAL '30 minutes', 28000),
((SELECT id FROM tipos WHERE nombre='Plato fuerte'), 'Pasta carbonara', 'Pasta con salsa cremosa, queso y tocineta.', INTERVAL '25 minutes', 26000),
((SELECT id FROM tipos WHERE nombre='Plato fuerte'), 'Salmon al limon', 'Filete de salmon con salsa de limon y guarnicion.', INTERVAL '35 minutes', 42000),
((SELECT id FROM tipos WHERE nombre='Plato fuerte'), 'Hamburguesa de la casa', 'Hamburguesa artesanal con queso, vegetales y papas.', INTERVAL '25 minutes', 30000),
((SELECT id FROM tipos WHERE nombre='Ensalada'), 'Ensalada mediterranea', 'Mezcla de vegetales frescos, aceitunas y queso.', INTERVAL '15 minutes', 22000),
((SELECT id FROM tipos WHERE nombre='Postre'), 'Tiramisu', 'Postre italiano de cafe, mascarpone y cacao.', INTERVAL '10 minutes', 16000),
((SELECT id FROM tipos WHERE nombre='Postre'), 'Cheesecake de frutos rojos', 'Tarta de queso con salsa de frutos rojos.', INTERVAL '10 minutes', 17000),
((SELECT id FROM tipos WHERE nombre='Bebida'), 'Limonada natural', 'Limonada preparada con limon fresco.', INTERVAL '5 minutes', 9000),
((SELECT id FROM tipos WHERE nombre='Bebida'), 'Jugo de mango', 'Jugo natural de mango.', INTERVAL '5 minutes', 10000),
((SELECT id FROM tipos WHERE nombre='Bebida'), 'Cafe americano', 'Cafe preparado al momento.', INTERVAL '5 minutes', 7000);

-- 6. ACTUACIONES
INSERT INTO actuaciones (rol_id, usuario_id) VALUES
((SELECT id FROM roles WHERE nombre='Administrador'), (SELECT id FROM usuarios WHERE nombre='Ana Torres')),
((SELECT id FROM roles WHERE nombre='Mesero'), (SELECT id FROM usuarios WHERE nombre='Carlos Mendoza')),
((SELECT id FROM roles WHERE nombre='Mesero'), (SELECT id FROM usuarios WHERE nombre='Laura Gomez')),
((SELECT id FROM roles WHERE nombre='Cocinero'), (SELECT id FROM usuarios WHERE nombre='Miguel Rodriguez')),
((SELECT id FROM roles WHERE nombre='Cocinero'), (SELECT id FROM usuarios WHERE nombre='Sofia Martinez')),
((SELECT id FROM roles WHERE nombre='Gerente'), (SELECT id FROM usuarios WHERE nombre='Andres Perez')),
((SELECT id FROM roles WHERE nombre='Recepcionista'), (SELECT id FROM usuarios WHERE nombre='Valentina Rojas')),
((SELECT id FROM roles WHERE nombre='Mesero'), (SELECT id FROM usuarios WHERE nombre='Diego Castro')),
((SELECT id FROM roles WHERE nombre='Cocinero'), (SELECT id FROM usuarios WHERE nombre='Mariana Lopez'));

-- 7. ESPECIALIDADES
INSERT INTO especialidades (cocinero_id, plato_id) VALUES
((SELECT id FROM usuarios WHERE nombre='Miguel Rodriguez'), (SELECT id FROM platos WHERE nombre='Pollo a la parrilla')),
((SELECT id FROM usuarios WHERE nombre='Miguel Rodriguez'), (SELECT id FROM platos WHERE nombre='Hamburguesa de la casa')),
((SELECT id FROM usuarios WHERE nombre='Sofia Martinez'), (SELECT id FROM platos WHERE nombre='Pasta carbonara')),
((SELECT id FROM usuarios WHERE nombre='Sofia Martinez'), (SELECT id FROM platos WHERE nombre='Salmon al limon')),
((SELECT id FROM usuarios WHERE nombre='Mariana Lopez'), (SELECT id FROM platos WHERE nombre='Tiramisu')),
((SELECT id FROM usuarios WHERE nombre='Mariana Lopez'), (SELECT id FROM platos WHERE nombre='Cheesecake de frutos rojos')),
((SELECT id FROM usuarios WHERE nombre='Mariana Lopez'), (SELECT id FROM platos WHERE nombre='Limonada natural'));

-- 8. PEDIDOS
INSERT INTO pedidos (cliente_id, mesero_id) VALUES
((SELECT id FROM usuarios WHERE nombre='Julian Herrera'), (SELECT id FROM usuarios WHERE nombre='Carlos Mendoza')),
((SELECT id FROM usuarios WHERE nombre='Mariana Lopez'), (SELECT id FROM usuarios WHERE nombre='Laura Gomez')),
((SELECT id FROM usuarios WHERE nombre='Diego Castro'), (SELECT id FROM usuarios WHERE nombre='Carlos Mendoza')),
((SELECT id FROM usuarios WHERE nombre='Valentina Rojas'), (SELECT id FROM usuarios WHERE nombre='Diego Castro')),
((SELECT id FROM usuarios WHERE nombre='Andres Perez'), (SELECT id FROM usuarios WHERE nombre='Laura Gomez'));

-- 9. ORDENES
INSERT INTO ordenes (plato_id, pedido_id, estado, cantidad, solicitado) VALUES
((SELECT id FROM platos WHERE nombre='Bruschettas de tomate'), (SELECT p.id FROM pedidos p JOIN usuarios u ON u.id=p.cliente_id WHERE u.nombre='Julian Herrera' ORDER BY p.id LIMIT 1), 1, 1, '2026-08-20 12:05:00-05'),
((SELECT id FROM platos WHERE nombre='Pollo a la parrilla'), (SELECT p.id FROM pedidos p JOIN usuarios u ON u.id=p.cliente_id WHERE u.nombre='Julian Herrera' ORDER BY p.id LIMIT 1), 2, 2, '2026-08-20 12:10:00-05'),
((SELECT id FROM platos WHERE nombre='Limonada natural'), (SELECT p.id FROM pedidos p JOIN usuarios u ON u.id=p.cliente_id WHERE u.nombre='Julian Herrera' ORDER BY p.id LIMIT 1), 1, 2, '2026-08-20 12:11:00-05'),
((SELECT id FROM platos WHERE nombre='Pasta carbonara'), (SELECT p.id FROM pedidos p JOIN usuarios u ON u.id=p.cliente_id WHERE u.nombre='Mariana Lopez' ORDER BY p.id LIMIT 1), 2, 1, '2026-08-20 13:15:00-05'),
((SELECT id FROM platos WHERE nombre='Ensalada mediterranea'), (SELECT p.id FROM pedidos p JOIN usuarios u ON u.id=p.cliente_id WHERE u.nombre='Mariana Lopez' ORDER BY p.id LIMIT 1), 1, 1, '2026-08-20 13:16:00-05'),
((SELECT id FROM platos WHERE nombre='Tiramisu'), (SELECT p.id FROM pedidos p JOIN usuarios u ON u.id=p.cliente_id WHERE u.nombre='Mariana Lopez' ORDER BY p.id LIMIT 1), 3, 1, '2026-08-20 13:45:00-05'),
((SELECT id FROM platos WHERE nombre='Hamburguesa de la casa'), (SELECT p.id FROM pedidos p JOIN usuarios u ON u.id=p.cliente_id WHERE u.nombre='Diego Castro' ORDER BY p.id LIMIT 1), 2, 2, '2026-08-21 19:05:00-05'),
((SELECT id FROM platos WHERE nombre='Cafe americano'), (SELECT p.id FROM pedidos p JOIN usuarios u ON u.id=p.cliente_id WHERE u.nombre='Diego Castro' ORDER BY p.id LIMIT 1), 1, 2, '2026-08-21 19:06:00-05'),
((SELECT id FROM platos WHERE nombre='Salmon al limon'), (SELECT p.id FROM pedidos p JOIN usuarios u ON u.id=p.cliente_id WHERE u.nombre='Valentina Rojas' ORDER BY p.id LIMIT 1), 2, 1, '2026-08-22 20:00:00-05'),
((SELECT id FROM platos WHERE nombre='Cheesecake de frutos rojos'), (SELECT p.id FROM pedidos p JOIN usuarios u ON u.id=p.cliente_id WHERE u.nombre='Valentina Rojas' ORDER BY p.id LIMIT 1), 1, 1, '2026-08-22 20:40:00-05'),
((SELECT id FROM platos WHERE nombre='Pollo a la parrilla'), (SELECT p.id FROM pedidos p JOIN usuarios u ON u.id=p.cliente_id WHERE u.nombre='Andres Perez' ORDER BY p.id LIMIT 1), 3, 1, '2026-08-23 14:00:00-05'),
((SELECT id FROM platos WHERE nombre='Limonada natural'), (SELECT p.id FROM pedidos p JOIN usuarios u ON u.id=p.cliente_id WHERE u.nombre='Andres Perez' ORDER BY p.id LIMIT 1), 3, 1, '2026-08-23 14:01:00-05');

-- 10. PREPARACIONES
INSERT INTO preparaciones (cocinero_id, orden_id)
SELECT (SELECT id FROM usuarios WHERE nombre='Miguel Rodriguez'), o.id
FROM ordenes o JOIN platos p ON p.id=o.plato_id
WHERE p.nombre IN ('Bruschettas de tomate','Pollo a la parrilla','Hamburguesa de la casa');

INSERT INTO preparaciones (cocinero_id, orden_id)
SELECT (SELECT id FROM usuarios WHERE nombre='Sofia Martinez'), o.id
FROM ordenes o JOIN platos p ON p.id=o.plato_id
WHERE p.nombre IN ('Pasta carbonara','Salmon al limon','Ensalada mediterranea');

INSERT INTO preparaciones (cocinero_id, orden_id)
SELECT (SELECT id FROM usuarios WHERE nombre='Mariana Lopez'), o.id
FROM ordenes o JOIN platos p ON p.id=o.plato_id
WHERE p.nombre IN ('Tiramisu','Cheesecake de frutos rojos','Limonada natural','Cafe americano');

-- 11. RESERVACIONES
INSERT INTO reservaciones (cliente_id, cantidad, estado) VALUES
((SELECT id FROM usuarios WHERE nombre='Julian Herrera'), 2, 1),
((SELECT id FROM usuarios WHERE nombre='Mariana Lopez'), 4, 1),
((SELECT id FROM usuarios WHERE nombre='Diego Castro'), 6, 2),
((SELECT id FROM usuarios WHERE nombre='Valentina Rojas'), 8, 1),
((SELECT id FROM usuarios WHERE nombre='Andres Perez'), 4, 3),
((SELECT id FROM usuarios WHERE nombre='Laura Gomez'), 2, 1);

-- 12. HORARIOS
-- No hay solapamientos en una misma mesa y cada reserva cabe en la mesa.
INSERT INTO horarios (mesa_id, reservacion_id, inicio, duracion) VALUES
((SELECT id FROM mesas WHERE sillas=2 ORDER BY id LIMIT 1), (SELECT r.id FROM reservaciones r JOIN usuarios u ON u.id=r.cliente_id WHERE u.nombre='Julian Herrera' ORDER BY r.id LIMIT 1), '2026-08-25 12:00:00', INTERVAL '2 hours'),
((SELECT id FROM mesas WHERE sillas=4 ORDER BY id LIMIT 1), (SELECT r.id FROM reservaciones r JOIN usuarios u ON u.id=r.cliente_id WHERE u.nombre='Mariana Lopez' ORDER BY r.id LIMIT 1), '2026-08-25 13:00:00', INTERVAL '2 hours'),
((SELECT id FROM mesas WHERE sillas=6 ORDER BY id LIMIT 1), (SELECT r.id FROM reservaciones r JOIN usuarios u ON u.id=r.cliente_id WHERE u.nombre='Diego Castro' ORDER BY r.id LIMIT 1), '2026-08-26 19:00:00', INTERVAL '2 hours 30 minutes'),
((SELECT id FROM mesas WHERE sillas=8 ORDER BY id LIMIT 1), (SELECT r.id FROM reservaciones r JOIN usuarios u ON u.id=r.cliente_id WHERE u.nombre='Valentina Rojas' ORDER BY r.id LIMIT 1), '2026-08-27 19:00:00', INTERVAL '2 hours'),
((SELECT id FROM mesas WHERE sillas=4 ORDER BY id OFFSET 1 LIMIT 1), (SELECT r.id FROM reservaciones r JOIN usuarios u ON u.id=r.cliente_id WHERE u.nombre='Andres Perez' ORDER BY r.id LIMIT 1), '2026-08-28 13:00:00', INTERVAL '2 hours'),
((SELECT id FROM mesas WHERE sillas=2 ORDER BY id OFFSET 1 LIMIT 1), (SELECT r.id FROM reservaciones r JOIN usuarios u ON u.id=r.cliente_id WHERE u.nombre='Laura Gomez' ORDER BY r.id LIMIT 1), '2026-08-25 18:00:00', INTERVAL '2 hours');

COMMIT;

-- ============================================================
-- VALIDACIONES
-- Las consultas que comprueban errores deben devolver 0 filas.
-- ============================================================

-- Cantidad de registros por tabla
SELECT 'actuaciones' tabla, COUNT(*) registros FROM actuaciones
UNION ALL SELECT 'especialidades', COUNT(*) FROM especialidades
UNION ALL SELECT 'horarios', COUNT(*) FROM horarios
UNION ALL SELECT 'mesas', COUNT(*) FROM mesas
UNION ALL SELECT 'ordenes', COUNT(*) FROM ordenes
UNION ALL SELECT 'pedidos', COUNT(*) FROM pedidos
UNION ALL SELECT 'platos', COUNT(*) FROM platos
UNION ALL SELECT 'preparaciones', COUNT(*) FROM preparaciones
UNION ALL SELECT 'reservaciones', COUNT(*) FROM reservaciones
UNION ALL SELECT 'roles', COUNT(*) FROM roles
UNION ALL SELECT 'tipos', COUNT(*) FROM tipos
UNION ALL SELECT 'usuarios', COUNT(*) FROM usuarios
ORDER BY tabla;

-- IDs duplicados (debe devolver 0 filas)
SELECT 'actuaciones' tabla, id, COUNT(*) cantidad FROM actuaciones GROUP BY id HAVING COUNT(*)>1
UNION ALL SELECT 'especialidades', id, COUNT(*) FROM especialidades GROUP BY id HAVING COUNT(*)>1
UNION ALL SELECT 'horarios', id, COUNT(*) FROM horarios GROUP BY id HAVING COUNT(*)>1
UNION ALL SELECT 'mesas', id, COUNT(*) FROM mesas GROUP BY id HAVING COUNT(*)>1
UNION ALL SELECT 'ordenes', id, COUNT(*) FROM ordenes GROUP BY id HAVING COUNT(*)>1
UNION ALL SELECT 'pedidos', id, COUNT(*) FROM pedidos GROUP BY id HAVING COUNT(*)>1
UNION ALL SELECT 'platos', id, COUNT(*) FROM platos GROUP BY id HAVING COUNT(*)>1
UNION ALL SELECT 'preparaciones', id, COUNT(*) FROM preparaciones GROUP BY id HAVING COUNT(*)>1
UNION ALL SELECT 'reservaciones', id, COUNT(*) FROM reservaciones GROUP BY id HAVING COUNT(*)>1
UNION ALL SELECT 'roles', id, COUNT(*) FROM roles GROUP BY id HAVING COUNT(*)>1
UNION ALL SELECT 'tipos', id, COUNT(*) FROM tipos GROUP BY id HAVING COUNT(*)>1
UNION ALL SELECT 'usuarios', id, COUNT(*) FROM usuarios GROUP BY id HAVING COUNT(*)>1;

-- Claves foráneas inválidas
SELECT a.id FROM actuaciones a LEFT JOIN roles r ON r.id=a.rol_id LEFT JOIN usuarios u ON u.id=a.usuario_id WHERE r.id IS NULL OR u.id IS NULL;
SELECT e.id FROM especialidades e LEFT JOIN usuarios u ON u.id=e.cocinero_id LEFT JOIN platos p ON p.id=e.plato_id WHERE u.id IS NULL OR p.id IS NULL;
SELECT p.id FROM pedidos p LEFT JOIN usuarios c ON c.id=p.cliente_id LEFT JOIN usuarios m ON m.id=p.mesero_id WHERE c.id IS NULL OR m.id IS NULL;
SELECT o.id FROM ordenes o LEFT JOIN platos p ON p.id=o.plato_id LEFT JOIN pedidos pe ON pe.id=o.pedido_id WHERE p.id IS NULL OR pe.id IS NULL;
SELECT pr.id FROM preparaciones pr LEFT JOIN usuarios u ON u.id=pr.cocinero_id LEFT JOIN ordenes o ON o.id=pr.orden_id WHERE u.id IS NULL OR o.id IS NULL;
SELECT h.id FROM horarios h LEFT JOIN mesas m ON m.id=h.mesa_id LEFT JOIN reservaciones r ON r.id=h.reservacion_id WHERE m.id IS NULL OR r.id IS NULL;

-- Reservaciones cuya cantidad supera la capacidad de la mesa (0 filas)
SELECT r.id reservacion, r.cantidad, m.id mesa, m.sillas
FROM reservaciones r JOIN horarios h ON h.reservacion_id=r.id JOIN mesas m ON m.id=h.mesa_id
WHERE r.cantidad > m.sillas;

-- Horarios solapados en una misma mesa (0 filas)
SELECT h1.mesa_id, h1.id horario_1, h2.id horario_2,
       h1.inicio inicio_1, h1.inicio+h1.duracion fin_1,
       h2.inicio inicio_2, h2.inicio+h2.duracion fin_2
FROM horarios h1 JOIN horarios h2
  ON h1.mesa_id=h2.mesa_id AND h1.id<h2.id
WHERE h1.inicio < h2.inicio+h2.duracion
  AND h2.inicio < h1.inicio+h1.duracion;

-- Reservaciones con más de un horario (0 filas)
SELECT reservacion_id, COUNT(*) cantidad_horarios
FROM horarios GROUP BY reservacion_id HAVING COUNT(*)>1;

-- Cantidades de órdenes no válidas (0 filas)
SELECT id, cantidad FROM ordenes WHERE cantidad<=0;

-- Platos con precio/tiempo no válidos (0 filas)
SELECT id, nombre, precio, tiempo FROM platos
WHERE precio<=0 OR tiempo<=INTERVAL '0 seconds';

-- Duraciones fuera del rango esperado (0 filas)
SELECT id, duracion FROM horarios
WHERE duracion<INTERVAL '1 hour' OR duracion>INTERVAL '3 hours';

-- FIN
