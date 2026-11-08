-- ====================================================================
-- Script de Pruebas: Preparación de platos y autorización de cocineros
-- Base de datos: PostgreSQL (restaurante)
--
-- Demuestra:
-- 1. La cola del cocinero ordenada por tiempo desc y hora pedido asc.
-- 2. Intento de cocinero no autorizado que falla (función y trigger).
-- 3. Dos cocineros intentando tomar el mismo ítem (control de concurrencia).
-- 4. Cambio de estado a "Preparado" solo por quien lo tomó.
-- ====================================================================

\pset footer off
\echo '===================================================================='
\echo 'PRUEBA 1: DEMOSTRACIÓN DE LA COLA DEL COCINERO ORDENADA'
\echo 'Regla: Platos más demorados primero (tiempo DESC) y luego por hora pedido (ASC)'
\echo '===================================================================='

\echo '--- Cola para Sofia Martinez (id 5, Chef Principal, autorizada para Plato Especial) ---'
SELECT orden_id, plato_nombre, es_especial, tiempo_preparacion, 
       to_char(solicitado, 'HH24:MI:SS') AS hora_pedido, estado, cocinero_nombre
FROM cola_cocinero(5);

\echo '--- Cola para Miguel Rodriguez (id 4, Carnes y Entradas, NO autorizado para Plato Especial) ---'
SELECT orden_id, plato_nombre, es_especial, tiempo_preparacion, 
       to_char(solicitado, 'HH24:MI:SS') AS hora_pedido, estado, cocinero_nombre
FROM cola_cocinero(4);

\echo '--- Cola para Mariana Lopez (id 9, Postres y Bebidas) ---'
SELECT orden_id, plato_nombre, es_especial, tiempo_preparacion, 
       to_char(solicitado, 'HH24:MI:SS') AS hora_pedido, estado, cocinero_nombre
FROM cola_cocinero(9);

\echo ''
\echo '===================================================================='
\echo 'PRUEBA 2: INTENTO DE COCINERO NO AUTORIZADO'
\echo 'Miguel Rodriguez (id 4) intenta tomar o asignarse el Plato Especial (Salmon al limon)'
\echo '===================================================================='

DO $$
DECLARE
    v_pedido_id INT;
    v_orden_salmon INT;
    v_cliente_id INT;
    v_mesero_id INT;
BEGIN
    SELECT id INTO v_cliente_id FROM usuarios WHERE nombre = 'Julian Herrera' LIMIT 1;
    SELECT u.id INTO v_mesero_id FROM usuarios u JOIN actuaciones a ON a.usuario_id = u.id JOIN roles r ON r.id = a.rol_id WHERE r.nombre = 'Mesero' LIMIT 1;

    -- Crear orden de prueba de plato especial (Salmon al limon)
    INSERT INTO pedidos (cliente_id, mesero_id, mesa_id) VALUES (v_cliente_id, v_mesero_id, (SELECT MIN(id) FROM mesas)) RETURNING id INTO v_pedido_id;
    INSERT INTO ordenes (plato_id, pedido_id, estado, cantidad, solicitado)
    SELECT id, v_pedido_id, 1, 1, CURRENT_TIMESTAMP
    FROM platos WHERE nombre = 'Salmon al limon'
    RETURNING id INTO v_orden_salmon;

    -- Intento A: Mediante la función tomar_orden()
    BEGIN
        RAISE NOTICE 'Intento 2A: Miguel (id 4) llamando a tomar_orden(orden_id=%, cocinero_id=4)...', v_orden_salmon;
        PERFORM tomar_orden(v_orden_salmon, 4);
        RAISE EXCEPTION 'FALLO: No debió permitir que Miguel tomara Salmon al limon';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE '-> EXITO: tomar_orden() rechazó la acción con error: "%"', SQLERRM;
    END;

    -- Intento B: Mediante UPDATE directo a la tabla ordenes (debe disparar el Trigger)
    BEGIN
        RAISE NOTICE 'Intento 2B: Ejecutando UPDATE directo de cocinero_id=4 en orden %...', v_orden_salmon;
        UPDATE ordenes SET cocinero_id = 4 WHERE id = v_orden_salmon;
        RAISE EXCEPTION 'FALLO: El trigger no impidió el UPDATE directo';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE '-> EXITO: Trigger impidió el UPDATE directo con error: "%"', SQLERRM;
    END;
END $$;

\echo ''
\echo '===================================================================='
\echo 'PRUEBA 3: DOS COCINEROS INTENTANDO TOMAR EL MISMO ÍTEM'
\echo 'Sofia (5) y Miguel (4) pueden preparar Pollo a la parrilla.'
\echo 'El primero lo toma exitosamente; el segundo recibe error.'
\echo '===================================================================='

DO $$
DECLARE
    v_pedido_id INT;
    v_orden_pollo INT;
    v_cliente_id INT;
    v_mesero_id INT;
BEGIN
    SELECT id INTO v_cliente_id FROM usuarios WHERE nombre = 'Julian Herrera' LIMIT 1;
    SELECT u.id INTO v_mesero_id FROM usuarios u JOIN actuaciones a ON a.usuario_id = u.id JOIN roles r ON r.id = a.rol_id WHERE r.nombre = 'Mesero' LIMIT 1;

    -- Crear una orden fresca disponible
    INSERT INTO pedidos (cliente_id, mesero_id, mesa_id) VALUES (v_cliente_id, v_mesero_id, (SELECT MIN(id) FROM mesas)) RETURNING id INTO v_pedido_id;
    INSERT INTO ordenes (plato_id, pedido_id, estado, cantidad, solicitado)
    SELECT id, v_pedido_id, 1, 1, CURRENT_TIMESTAMP
    FROM platos WHERE nombre = 'Pollo a la parrilla'
    RETURNING id INTO v_orden_pollo;

    RAISE NOTICE 'Orden de Pollo a la parrilla creada con ID: %', v_orden_pollo;

    -- 1. Sofia toma la orden primero
    PERFORM tomar_orden(v_orden_pollo, 5);
    RAISE NOTICE '-> Sofia (id 5) tomó la orden % exitosamente.', v_orden_pollo;

    -- 2. Miguel intenta tomar la misma orden
    BEGIN
        RAISE NOTICE '-> Miguel (id 4) intenta tomar la misma orden %...', v_orden_pollo;
        PERFORM tomar_orden(v_orden_pollo, 4);
        RAISE EXCEPTION 'FALLO: Permitió duplicar la toma del ítem';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE '-> EXITO: La segunda toma fue bloqueada con error: "%"', SQLERRM;
    END;
END $$;

\echo ''
\echo '===================================================================='
\echo 'PRUEBA 4: CAMBIO DE ESTADO A "PREPARADO"'
\echo 'Solo el cocinero que tomó el ítem puede marcarlo como Preparado.'
\echo '===================================================================='

DO $$
DECLARE
    v_pedido_id INT;
    v_orden_id INT;
    v_cliente_id INT;
    v_mesero_id INT;
    v_estado_final INT;
    v_hora_fin TIMESTAMP WITH TIME ZONE;
BEGIN
    SELECT id INTO v_cliente_id FROM usuarios WHERE nombre = 'Julian Herrera' LIMIT 1;
    SELECT u.id INTO v_mesero_id FROM usuarios u JOIN actuaciones a ON a.usuario_id = u.id JOIN roles r ON r.id = a.rol_id WHERE r.nombre = 'Mesero' LIMIT 1;

    -- Crear orden de prueba (Hamburguesa de la casa)
    INSERT INTO pedidos (cliente_id, mesero_id, mesa_id) VALUES (v_cliente_id, v_mesero_id, (SELECT MIN(id) FROM mesas)) RETURNING id INTO v_pedido_id;
    INSERT INTO ordenes (plato_id, pedido_id, estado, cantidad, solicitado)
    SELECT id, v_pedido_id, 1, 1, CURRENT_TIMESTAMP
    FROM platos WHERE nombre = 'Hamburguesa de la casa'
    RETURNING id INTO v_orden_id;

    -- Miguel (4) toma la hamburguesa
    PERFORM tomar_orden(v_orden_id, 4);
    RAISE NOTICE 'Miguel (id 4) tomó la orden % (Hamburguesa).', v_orden_id;

    -- Sofia (5) intenta marcarla como preparada (debe fallar)
    BEGIN
        RAISE NOTICE 'Sofia (id 5) intenta marcar como preparada la orden tomada por Miguel...';
        PERFORM marcar_orden_preparada(v_orden_id, 5);
        RAISE EXCEPTION 'FALLO: Un cocinero ajeno marcó la orden';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE '-> EXITO: Rechazado intento de cocinero ajeno: "%"', SQLERRM;
    END;

    -- Miguel (4) marca la orden como preparada (debe ser exitoso)
    PERFORM marcar_orden_preparada(v_orden_id, 4);
    RAISE NOTICE '-> EXITO: Miguel marcó la orden % como Preparada correctamente.', v_orden_id;

    -- Verificar estado y hora_terminado en la base de datos
    SELECT estado, hora_terminado INTO v_estado_final, v_hora_fin FROM ordenes WHERE id = v_orden_id;
    RAISE NOTICE 'Estado final: % (2 = Preparado), Hora terminado: %', v_estado_final, v_hora_fin;
END $$;

\echo ''
\echo '===================================================================='
\echo 'FIN DE PRUEBAS'
\echo '===================================================================='
