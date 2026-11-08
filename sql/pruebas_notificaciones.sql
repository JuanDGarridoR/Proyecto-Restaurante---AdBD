-- ====================================================================
-- Script de Pruebas: Sistema de Notificaciones
-- Base de datos: PostgreSQL (restaurante)
--
-- Demuestra:
-- 1. Pedido con varios ítems: notificación aparece SOLO al terminar el último.
-- 2. Reserva a 15 min genera notificación; reserva a 3 horas NO.
-- 3. Ejecución repetida (idempotencia) sin generar duplicados.
-- 4. Entrega del pedido (estado 3) marca la notificación como leída automáticamente.
--
-- Todo se deshace al final (ROLLBACK), así que puede repetirse.
-- Uso: psql -d restaurante -f pruebas_notificaciones.sql
-- ====================================================================

\pset footer off
BEGIN;
SET search_path = public;
-- Los triggers diferibles se verifican en cada sentencia durante las pruebas
SET CONSTRAINTS ALL IMMEDIATE;

\echo '===================================================================='
\echo 'PRUEBA 1: PEDIDO CON VARIOS ÍTEMS'
\echo 'La notificación al mesero solo debe crearse al terminar el ÚLTIMO ítem'
\echo '===================================================================='

DO $$
DECLARE
    v_pedido_id INT;
    v_orden1_id INT;
    v_orden2_id INT;
    v_cliente_id INT;
    v_mesero_id INT;
    v_notif_count INT;
    v_cocinero1 INT;
    v_cocinero2 INT;
BEGIN
    SELECT id INTO v_cliente_id FROM usuarios WHERE nombre = 'Julian Herrera' LIMIT 1;
    -- Mesero Carlos Mendoza (id 2)
    SELECT id INTO v_mesero_id FROM usuarios WHERE nombre = 'Carlos Mendoza' LIMIT 1;

    -- Crear nuevo pedido con 2 platos
    INSERT INTO pedidos (cliente_id, mesero_id, mesa_id) VALUES (v_cliente_id, v_mesero_id, (SELECT MIN(id) FROM mesas)) RETURNING id INTO v_pedido_id;

    INSERT INTO ordenes (plato_id, pedido_id, estado, cantidad, solicitado)
    SELECT id, v_pedido_id, 1, 1, CURRENT_TIMESTAMP FROM platos WHERE nombre = 'Pollo a la parrilla'
    RETURNING id INTO v_orden1_id;

    INSERT INTO ordenes (plato_id, pedido_id, estado, cantidad, solicitado)
    SELECT id, v_pedido_id, 1, 1, CURRENT_TIMESTAMP FROM platos WHERE nombre = 'Tiramisu'
    RETURNING id INTO v_orden2_id;

    RAISE NOTICE 'Pedido #% creado con órdenes: #% y #% (ambas en preparación).', v_pedido_id, v_orden1_id, v_orden2_id;

    -- Cada plato lo toma un cocinero autorizado para prepararlo (regla 3.5)
    SELECT a.cocinero_id INTO v_cocinero1 FROM autorizaciones a JOIN ordenes o ON o.plato_id = a.plato_id
    WHERE o.id = v_orden1_id ORDER BY a.cocinero_id LIMIT 1;
    SELECT a.cocinero_id INTO v_cocinero2 FROM autorizaciones a JOIN ordenes o ON o.plato_id = a.plato_id
    WHERE o.id = v_orden2_id ORDER BY a.cocinero_id LIMIT 1;
    PERFORM tomar_orden(v_orden1_id, v_cocinero1);
    PERFORM tomar_orden(v_orden2_id, v_cocinero2);

    -- Paso 1: Ningún ítem preparado
    SELECT COUNT(*) INTO v_notif_count FROM notificaciones WHERE tipo = 'PEDIDO_LISTO' AND referencia_id = v_pedido_id;
    RAISE NOTICE '-> Estado inicial: % notificaciones encontradas (esperado: 0).', v_notif_count;

    -- Paso 2: Se prepara SOLO el ítem 1 (Pollo)
    PERFORM marcar_orden_preparada(v_orden1_id, v_cocinero1);
    SELECT COUNT(*) INTO v_notif_count FROM notificaciones WHERE tipo = 'PEDIDO_LISTO' AND referencia_id = v_pedido_id;
    IF v_notif_count = 0 THEN
        RAISE NOTICE '-> Solo ítem 1 preparado: % notificaciones (CORRECTO: falta el ítem 2).', v_notif_count;
    ELSE
        RAISE EXCEPTION 'FALLO: Se generó notificación antes de terminar todos los ítems';
    END IF;

    -- Paso 3: Se prepara el ítem 2 (Tiramisú) -> ¡Ahora sí están TODOS preparados!
    PERFORM marcar_orden_preparada(v_orden2_id, v_cocinero2);
    SELECT COUNT(*) INTO v_notif_count FROM notificaciones WHERE tipo = 'PEDIDO_LISTO' AND referencia_id = v_pedido_id;
    IF v_notif_count = 1 THEN
        RAISE NOTICE '-> Ítem 2 preparado (todos listos): % notificación creada para mesero % (CORRECTO).', v_notif_count, v_mesero_id;
    ELSE
        RAISE EXCEPTION 'FALLO: No se generó la notificación tras terminar todos los ítems';
    END IF;
END $$;

\echo ''
\echo '--- Notificación generada en la tabla ---'
SELECT id, destinatario_id, tipo, referencia_id, mensaje, leida, fecha_creacion
FROM notificaciones
WHERE tipo = 'PEDIDO_LISTO'
ORDER BY id DESC LIMIT 1;

\echo ''
\echo '===================================================================='
\echo 'PRUEBA 2: RESERVA PRÓXIMA (30 MIN) VS RESERVA LEJANA (3 HORAS)'
\echo '===================================================================='

DO $$
DECLARE
    v_cliente_id INT;
    v_reserva_cercana INT;
    v_reserva_lejana INT;
    v_mesa1_id INT;
    v_mesa2_id INT;
    v_inicio_cercana TIMESTAMP := date_trunc('minute', LOCALTIMESTAMP + INTERVAL '15 minutes');
    v_inicio_lejana TIMESTAMP := date_trunc('minute', LOCALTIMESTAMP + INTERVAL '3 hours');
    v_creadas INT;
    v_notif_cercana INT;
    v_notif_lejana INT;
BEGIN
    SELECT id INTO v_cliente_id FROM usuarios WHERE nombre = 'Julian Herrera' LIMIT 1;
    -- Mesas libres en cada horario (no se cruzan con reservas existentes)
    SELECT d.mesa_id INTO v_mesa1_id FROM fn_mesas_disponibles(v_inicio_cercana, 2) d LIMIT 1;
    SELECT d.mesa_id INTO v_mesa2_id FROM fn_mesas_disponibles(v_inicio_lejana, 4) d LIMIT 1;

    -- Reserva A: Empieza en 15 minutos (DENTRO del rango de 30 minutos)
    INSERT INTO reservaciones (cliente_id, cantidad, estado) VALUES (v_cliente_id, 2, 1) RETURNING id INTO v_reserva_cercana;
    INSERT INTO horarios (mesa_id, reservacion_id, inicio, duracion)
    VALUES (v_mesa1_id, v_reserva_cercana, v_inicio_cercana, INTERVAL '2 hours');

    -- Reserva B: Empieza en 3 horas (FUERA del rango de 30 minutos)
    INSERT INTO reservaciones (cliente_id, cantidad, estado) VALUES (v_cliente_id, 4, 1) RETURNING id INTO v_reserva_lejana;
    INSERT INTO horarios (mesa_id, reservacion_id, inicio, duracion)
    VALUES (v_mesa2_id, v_reserva_lejana, v_inicio_lejana, INTERVAL '2 hours');

    RAISE NOTICE 'Reserva cercana #% (inicia en 15m) y lejana #% (inicia en 3h) creadas.', v_reserva_cercana, v_reserva_lejana;

    -- Ejecutar la función de detección de reservas próximas (30 min)
    v_creadas := fn_notificar_reservas_proximas(30);
    RAISE NOTICE '-> fn_notificar_reservas_proximas(30) retornó % notificaciones nuevas.', v_creadas;

    -- Verificar que la reserva cercana tiene notificación y la lejana no
    SELECT COUNT(*) INTO v_notif_cercana FROM notificaciones WHERE tipo = 'RESERVA_PROXIMA' AND referencia_id = v_reserva_cercana;
    SELECT COUNT(*) INTO v_notif_lejana FROM notificaciones WHERE tipo = 'RESERVA_PROXIMA' AND referencia_id = v_reserva_lejana;

    IF v_notif_cercana > 0 AND v_notif_lejana = 0 THEN
        RAISE NOTICE '-> EXITO: Reserva cercana tiene % notificación; reserva a 3h tiene % notificaciones.', v_notif_cercana, v_notif_lejana;
    ELSE
        RAISE EXCEPTION 'FALLO: Filtrado incorrecto de tiempo en reservas';
    END IF;
END $$;

\echo ''
\echo '--- Notificación de reserva próxima generada para el Maitre ---'
SELECT id, destinatario_id, tipo, referencia_id, mensaje, leida
FROM notificaciones
WHERE tipo = 'RESERVA_PROXIMA'
ORDER BY id DESC LIMIT 1;

\echo ''
\echo '===================================================================='
\echo 'PRUEBA 3: EJECUTAR EL PROCESO DOS VECES SIN GENERAR DUPLICADOS'
\echo '===================================================================='

DO $$
DECLARE
    v_creadas_segunda_vez INT;
BEGIN
    -- Ejecución 2 de reservas próximas: debe detectar que ya están notificadas y no duplicar
    v_creadas_segunda_vez := fn_notificar_reservas_proximas(30);
    RAISE NOTICE '-> Segunda ejecución de fn_notificar_reservas_proximas(30) retornó: % nuevas (esperado: 0).', v_creadas_segunda_vez;

    IF v_creadas_segunda_vez = 0 THEN
        RAISE NOTICE '-> EXITO: No se generaron duplicados de reservas próximas.';
    ELSE
        RAISE EXCEPTION 'FALLO: Se crearon duplicados en la segunda ejecución';
    END IF;
END $$;

\echo ''
\echo '===================================================================='
\echo 'PRUEBA 4: ENTREGA DEL PEDIDO MARCA LA NOTIFICACIÓN COMO LEÍDA'
\echo '===================================================================='

DO $$
DECLARE
    v_notif RECORD;
    v_pedido_id INT;
BEGIN
    -- Tomar la última notificación no leída de pedido listo
    SELECT id, referencia_id, leida, fecha_lectura INTO v_notif
    FROM notificaciones
    WHERE tipo = 'PEDIDO_LISTO' AND NOT leida
    ORDER BY id DESC LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No se encontró notificación de PEDIDO_LISTO no leída para la prueba';
    END IF;

    v_pedido_id := v_notif.referencia_id;
    RAISE NOTICE 'Notificación #% (Pedido #%): leida = % (esperado: false).', v_notif.id, v_pedido_id, v_notif.leida;

    -- El mesero marca el pedido como "Entregado" (estado = 3)
    RAISE NOTICE 'Mesero actualiza todas las órdenes del pedido #% a estado = 3 (Entregado)...', v_pedido_id;
    UPDATE ordenes SET estado = 3 WHERE pedido_id = v_pedido_id;

    -- Verificar que el trigger trg_check_pedido_entregado marcó la notificación como leída
    SELECT id, leida, fecha_lectura INTO v_notif
    FROM notificaciones
    WHERE id = v_notif.id;

    IF v_notif.leida = TRUE AND v_notif.fecha_lectura IS NOT NULL THEN
        RAISE NOTICE '-> EXITO: Notificación #% ahora tiene leida = % y fecha_lectura = % (actualizado automáticamente por el trigger).',
            v_notif.id, v_notif.leida, v_notif.fecha_lectura;
    ELSE
        RAISE EXCEPTION 'FALLO: La notificación no fue marcada como leída automáticamente';
    END IF;
END $$;

ROLLBACK;

\echo ''
\echo '===================================================================='
\echo 'FIN DE PRUEBAS DE NOTIFICACIONES (cambios deshechos con ROLLBACK)'
\echo '===================================================================='
