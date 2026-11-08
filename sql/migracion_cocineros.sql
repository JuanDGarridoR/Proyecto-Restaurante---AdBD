-- ====================================================================
-- Script de Migración: Preparación de platos con autorización de cocineros
-- Base de datos: PostgreSQL (restaurante)
-- ====================================================================

BEGIN;

-- 1. Tabla de autorizaciones cocinero <-> ítem del menú (relación N:M)
-- Incluye fecha de autorización y restricción de unicidad.
CREATE TABLE IF NOT EXISTS autorizaciones (
    id SERIAL PRIMARY KEY,
    cocinero_id INT NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
    plato_id INT NOT NULL REFERENCES platos(id) ON DELETE CASCADE,
    fecha_autorizacion TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_cocinero_plato UNIQUE (cocinero_id, plato_id)
);

-- Columna para identificar platos especiales (solo autorizables a mejores cocineros)
ALTER TABLE platos ADD COLUMN IF NOT EXISTS es_especial BOOLEAN DEFAULT FALSE;

-- Asegurar tiempos de preparación e identificar el plato especial 'Salmon al limon'
UPDATE platos SET es_especial = TRUE WHERE nombre ILIKE '%salmon%';
UPDATE platos SET tiempo = INTERVAL '35 minutes' WHERE nombre ILIKE '%salmon%' AND (tiempo IS NULL OR tiempo = INTERVAL '0');
UPDATE platos SET tiempo = INTERVAL '40 minutes' WHERE nombre ILIKE '%bandeja%' AND tiempo IS NULL;
UPDATE platos SET tiempo = INTERVAL '10 minutes' WHERE nombre ILIKE '%buñuelo%' AND tiempo IS NULL;

-- 2. Columnas en la tabla ordenes (detalle del pedido)
-- Reutiliza estado (1: En preparación, 2: Preparado, 3: Entregado) y solicitado.
-- Agrega cocinero asignado, hora en que se tomó y hora en que se terminó.
ALTER TABLE ordenes ADD COLUMN IF NOT EXISTS cocinero_id INT REFERENCES usuarios(id);
ALTER TABLE ordenes ADD COLUMN IF NOT EXISTS hora_tomado TIMESTAMP WITH TIME ZONE;
ALTER TABLE ordenes ADD COLUMN IF NOT EXISTS hora_terminado TIMESTAMP WITH TIME ZONE;

-- 3. Poblar autorizaciones iniciales para al menos 3 cocineros con perfiles distintos
-- Cocineros existentes:
-- id 4: Miguel Rodriguez (Especialidad: Carnes y entradas)
-- id 5: Sofia Martinez   (Chef Principal: Platos fuertes y Plato Especial Salmon al limon)
-- id 9: Mariana Lopez    (Especialidad: Postres y bebidas)

-- Migrar especialidades previas a autorizaciones
INSERT INTO autorizaciones (cocinero_id, plato_id, fecha_autorizacion)
SELECT DISTINCT e.cocinero_id, e.plato_id, CURRENT_TIMESTAMP
FROM especialidades e
ON CONFLICT (cocinero_id, plato_id) DO NOTHING;

-- Asegurar autorizaciones específicas para Sofia Martinez (id 5) -> Incluye Plato Especial
INSERT INTO autorizaciones (cocinero_id, plato_id, fecha_autorizacion)
SELECT 5, p.id, CURRENT_TIMESTAMP
FROM platos p
WHERE p.nombre IN ('Salmon al limon', 'Pasta carbonara', 'Pollo a la parrilla', 'Ensalada mediterranea')
ON CONFLICT (cocinero_id, plato_id) DO NOTHING;

-- Autorizaciones para Miguel Rodriguez (id 4) -> Platos de parrilla y entradas (NO tiene plato especial)
INSERT INTO autorizaciones (cocinero_id, plato_id, fecha_autorizacion)
SELECT 4, p.id, CURRENT_TIMESTAMP
FROM platos p
WHERE p.nombre IN ('Pollo a la parrilla', 'Hamburguesa de la casa', 'Bruschettas de tomate', 'Sopa de tomate')
ON CONFLICT (cocinero_id, plato_id) DO NOTHING;

-- Autorizaciones para Mariana Lopez (id 9) -> Postres y bebidas
INSERT INTO autorizaciones (cocinero_id, plato_id, fecha_autorizacion)
SELECT 9, p.id, CURRENT_TIMESTAMP
FROM platos p
WHERE p.nombre IN ('Tiramisu', 'Cheesecake de frutos rojos', 'Limonada natural', 'Jugo de mango', 'Cafe americano')
ON CONFLICT (cocinero_id, plato_id) DO NOTHING;

-- Backfill de ordenes históricas desde preparaciones
UPDATE ordenes o
SET cocinero_id = p.cocinero_id,
    hora_tomado = o.solicitado
FROM preparaciones p
WHERE p.orden_id = o.id AND o.cocinero_id IS NULL;

UPDATE ordenes
SET hora_terminado = hora_tomado + INTERVAL '20 minutes'
WHERE estado IN (2, 3) AND hora_terminado IS NULL AND hora_tomado IS NOT NULL;

-- 4. Trigger que impide asignar un ítem a un cocinero no autorizado (a nivel de BD)
CREATE OR REPLACE FUNCTION trg_validar_autorizacion_cocinero()
RETURNS trigger AS $$
BEGIN
    IF NEW.cocinero_id IS NOT NULL THEN
        IF NOT EXISTS (
            SELECT 1 FROM autorizaciones
            WHERE cocinero_id = NEW.cocinero_id AND plato_id = NEW.plato_id
        ) THEN
            RAISE EXCEPTION 'No estás autorizado para preparar este plato (cocinero %, plato %)', NEW.cocinero_id, NEW.plato_id;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_check_autorizacion_cocinero ON ordenes;
CREATE TRIGGER trg_check_autorizacion_cocinero
BEFORE INSERT OR UPDATE OF cocinero_id, plato_id ON ordenes
FOR EACH ROW
EXECUTE FUNCTION trg_validar_autorizacion_cocinero();

-- 5. Función / Procedimiento "cola del cocinero"
-- Dado un cocinero, muestra solo los ítems pendientes que está autorizado a preparar,
-- ordenados por tiempo de preparación descendente y luego por hora del pedido.
CREATE OR REPLACE FUNCTION cola_cocinero(p_cocinero_id INT)
RETURNS TABLE (
    orden_id INT,
    pedido_id INT,
    plato_id INT,
    plato_nombre TEXT,
    es_especial BOOLEAN,
    tiempo_preparacion INTERVAL,
    solicitado TIMESTAMP WITH TIME ZONE,
    cantidad INT,
    estado INT,
    cocinero_id INT,
    cocinero_nombre TEXT,
    hora_tomado TIMESTAMP WITH TIME ZONE
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        o.id AS orden_id,
        o.pedido_id,
        p.id AS plato_id,
        p.nombre AS plato_nombre,
        COALESCE(p.es_especial, FALSE) AS es_especial,
        COALESCE(p.tiempo, INTERVAL '0 minutes') AS tiempo_preparacion,
        o.solicitado,
        o.cantidad,
        o.estado,
        o.cocinero_id,
        u.nombre AS cocinero_nombre,
        o.hora_tomado
    FROM ordenes o
    JOIN platos p ON p.id = o.plato_id
    LEFT JOIN usuarios u ON u.id = o.cocinero_id
    WHERE o.estado = 1 -- En preparación
      AND (o.cocinero_id IS NULL OR o.cocinero_id = p_cocinero_id)
      AND EXISTS (
          SELECT 1 FROM autorizaciones a
          WHERE a.cocinero_id = p_cocinero_id
            AND a.plato_id = o.plato_id
      )
    ORDER BY 
        COALESCE(p.tiempo, INTERVAL '0 minutes') DESC, 
        o.solicitado ASC;
END;
$$ LANGUAGE plpgsql;

-- Vista general de la cocina para supervisión
CREATE OR REPLACE VIEW v_cola_cocina AS
SELECT 
    o.id AS orden_id,
    o.pedido_id,
    p.id AS plato_id,
    p.nombre AS plato_nombre,
    COALESCE(p.es_especial, FALSE) AS es_especial,
    COALESCE(p.tiempo, INTERVAL '0 minutes') AS tiempo_preparacion,
    o.solicitado,
    o.cantidad,
    o.estado,
    o.cocinero_id,
    u.nombre AS cocinero_nombre,
    o.hora_tomado
FROM ordenes o
JOIN platos p ON p.id = o.plato_id
LEFT JOIN usuarios u ON u.id = o.cocinero_id
WHERE o.estado = 1
ORDER BY COALESCE(p.tiempo, INTERVAL '0 minutes') DESC, o.solicitado ASC;

-- 6. Procedimiento para que el cocinero "tome" un ítem
-- Bloquea la fila con SELECT ... FOR UPDATE para evitar colisiones entre cocineros.
-- Valida que esté autorizado y que nadie más lo haya tomado.
CREATE OR REPLACE FUNCTION tomar_orden(p_orden_id INT, p_cocinero_id INT)
RETURNS void AS $$
DECLARE
    v_plato_id INT;
    v_estado INT;
    v_cocinero_id INT;
    v_es_cocinero BOOLEAN;
    v_autorizado BOOLEAN;
BEGIN
    -- Validar que el usuario sea Cocinero
    SELECT EXISTS (
        SELECT 1 FROM actuaciones a
        JOIN roles r ON r.id = a.rol_id
        WHERE a.usuario_id = p_cocinero_id AND r.nombre = 'Cocinero'
    ) INTO v_es_cocinero;

    IF NOT v_es_cocinero THEN
        RAISE EXCEPTION 'El usuario % no tiene el rol de Cocinero', p_cocinero_id;
    END IF;

    -- Bloqueo de fila
    SELECT plato_id, estado, cocinero_id
    INTO v_plato_id, v_estado, v_cocinero_id
    FROM ordenes
    WHERE id = p_orden_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'La orden % no existe', p_orden_id;
    END IF;

    -- Validar que nadie más la haya tomado
    IF v_cocinero_id IS NOT NULL THEN
        RAISE EXCEPTION 'El ítem ya fue tomado por otro cocinero';
    END IF;

    -- Validar estado
    IF v_estado != 1 THEN
        RAISE EXCEPTION 'El ítem no está en preparación (estado actual: %)', v_estado;
    END IF;

    -- Validar autorización
    SELECT EXISTS (
        SELECT 1 FROM autorizaciones
        WHERE cocinero_id = p_cocinero_id AND plato_id = v_plato_id
    ) INTO v_autorizado;

    IF NOT v_autorizado THEN
        RAISE EXCEPTION 'No estás autorizado para preparar este plato';
    END IF;

    -- Asignar y registrar hora
    UPDATE ordenes
    SET cocinero_id = p_cocinero_id,
        hora_tomado = CURRENT_TIMESTAMP
    WHERE id = p_orden_id;

    -- Sincronizar preparaciones
    INSERT INTO preparaciones (cocinero_id, orden_id)
    VALUES (p_cocinero_id, p_orden_id);
END;
$$ LANGUAGE plpgsql;

-- Procedimiento SQL invocable con CALL
CREATE OR REPLACE PROCEDURE pr_tomar_orden(p_orden_id INT, p_cocinero_id INT)
AS $$
BEGIN
    PERFORM tomar_orden(p_orden_id, p_cocinero_id);
END;
$$ LANGUAGE plpgsql;

-- 7. Procedimiento para marcar un ítem como "Preparado"
-- Solo lo puede hacer el cocinero que lo tomó.
CREATE OR REPLACE FUNCTION marcar_orden_preparada(p_orden_id INT, p_cocinero_id INT)
RETURNS void AS $$
DECLARE
    v_cocinero_id INT;
    v_estado INT;
BEGIN
    SELECT cocinero_id, estado
    INTO v_cocinero_id, v_estado
    FROM ordenes
    WHERE id = p_orden_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'La orden % no existe', p_orden_id;
    END IF;

    IF v_cocinero_id IS NULL THEN
        RAISE EXCEPTION 'El ítem aún no ha sido tomado por ningún cocinero';
    END IF;

    IF v_cocinero_id != p_cocinero_id THEN
        RAISE EXCEPTION 'Solo el cocinero que tomó el ítem puede marcarlo como Preparado';
    END IF;

    IF v_estado = 2 THEN
        RAISE EXCEPTION 'El ítem ya fue marcado como Preparado';
    ELSIF v_estado = 3 THEN
        RAISE EXCEPTION 'El ítem ya fue entregado';
    END IF;

    UPDATE ordenes
    SET estado = 2,
        hora_terminado = CURRENT_TIMESTAMP
    WHERE id = p_orden_id;
END;
$$ LANGUAGE plpgsql;

-- Procedimiento SQL invocable con CALL
CREATE OR REPLACE PROCEDURE pr_marcar_orden_preparada(p_orden_id INT, p_cocinero_id INT)
AS $$
BEGIN
    PERFORM marcar_orden_preparada(p_orden_id, p_cocinero_id);
END;
$$ LANGUAGE plpgsql;

-- 8. Datos de prueba: Órdenes pendientes sin cocinero asignado
-- Creamos un pedido de prueba si no hay órdenes pendientes sin asignar
DO $$
DECLARE
    v_pedido_id INT;
    v_cliente_id INT;
    v_mesero_id INT;
BEGIN
    SELECT id INTO v_cliente_id FROM usuarios WHERE nombre = 'Julian Herrera' LIMIT 1;
    SELECT u.id INTO v_mesero_id FROM usuarios u JOIN actuaciones a ON a.usuario_id = u.id JOIN roles r ON r.id = a.rol_id WHERE r.nombre = 'Mesero' LIMIT 1;

    -- Crear nuevo pedido para pruebas de cocina si no existe uno reciente activo
    INSERT INTO pedidos (cliente_id, mesero_id)
    VALUES (v_cliente_id, v_mesero_id)
    RETURNING id INTO v_pedido_id;

    -- Insertar ítems con diferentes tiempos y platos:
    -- 1. Salmon al limon (Plato especial, 35 min) -> Autorizado solo para Sofia
    INSERT INTO ordenes (plato_id, pedido_id, estado, cantidad, solicitado)
    SELECT id, v_pedido_id, 1, 1, CURRENT_TIMESTAMP - INTERVAL '10 minutes'
    FROM platos WHERE nombre = 'Salmon al limon';

    -- 2. Pollo a la parrilla (30 min) -> Autorizado para Sofia y Miguel
    INSERT INTO ordenes (plato_id, pedido_id, estado, cantidad, solicitado)
    SELECT id, v_pedido_id, 1, 2, CURRENT_TIMESTAMP - INTERVAL '8 minutes'
    FROM platos WHERE nombre = 'Pollo a la parrilla';

    -- 3. Bruschettas de tomate (15 min) -> Autorizado para Miguel
    INSERT INTO ordenes (plato_id, pedido_id, estado, cantidad, solicitado)
    SELECT id, v_pedido_id, 1, 1, CURRENT_TIMESTAMP - INTERVAL '5 minutes'
    FROM platos WHERE nombre = 'Bruschettas de tomate';

    -- 4. Tiramisu (10 min) -> Autorizado para Mariana
    INSERT INTO ordenes (plato_id, pedido_id, estado, cantidad, solicitado)
    SELECT id, v_pedido_id, 1, 1, CURRENT_TIMESTAMP - INTERVAL '2 minutes'
    FROM platos WHERE nombre = 'Tiramisu';

    -- 5. Limonada natural (5 min) -> Autorizado para Mariana
    INSERT INTO ordenes (plato_id, pedido_id, estado, cantidad, solicitado)
    SELECT id, v_pedido_id, 1, 2, CURRENT_TIMESTAMP - INTERVAL '1 minute'
    FROM platos WHERE nombre = 'Limonada natural';
END $$;

COMMIT;
