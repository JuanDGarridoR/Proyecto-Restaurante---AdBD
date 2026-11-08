-- ====================================================================
-- Pruebas de las reglas de integridad (migracion_integridad.sql)
-- Cada prueba imprime OK o FALLA. Todo se deshace al final (ROLLBACK).
-- Uso: psql -d restaurante -f pruebas_integridad.sql
-- ====================================================================

BEGIN;
SET search_path = public;
SET client_min_messages = notice;
-- Los triggers diferibles se verifican en cada sentencia durante las pruebas
SET CONSTRAINTS ALL IMMEDIATE;

-- Ejecuta una sentencia que DEBE fallar y muestra el mensaje obtenido
CREATE OR REPLACE FUNCTION pg_temp.debe_fallar(p_prueba TEXT, p_sql TEXT)
RETURNS void AS $$
BEGIN
    BEGIN
        EXECUTE p_sql;
        RAISE NOTICE 'FALLA  %: la sentencia se aceptó', p_prueba;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'OK     %: %', p_prueba, SQLERRM;
    END;
END;
$$ LANGUAGE plpgsql;

-- Ejecuta una sentencia que DEBE funcionar
CREATE OR REPLACE FUNCTION pg_temp.debe_funcionar(p_prueba TEXT, p_sql TEXT)
RETURNS void AS $$
BEGIN
    EXECUTE p_sql;
    RAISE NOTICE 'OK     %', p_prueba;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'FALLA  %: %', p_prueba, SQLERRM;
END;
$$ LANGUAGE plpgsql;

-- Escenario aislado: un día futuro sin otras reservaciones
CREATE TEMP TABLE escenario AS
SELECT (CURRENT_DATE + 400)::timestamp + INTERVAL '19 hours' AS t0;

-- Reservación base: mesa 3 (4 sillas), 4 personas, 19:00-21:00
INSERT INTO reservaciones (id, cliente_id, cantidad, estado) VALUES (90001, 10, 4, 1);
INSERT INTO horarios (mesa_id, reservacion_id, inicio, duracion)
SELECT 3, 90001, t0, INTERVAL '2 hours' FROM escenario;

-- 1. Cruces en la misma mesa
INSERT INTO reservaciones (id, cliente_id, cantidad, estado) VALUES (90002, 10, 2, 1);
SELECT pg_temp.debe_fallar('Cruce en la misma mesa (20:00 en mesa 3)',
    format('INSERT INTO horarios (mesa_id, reservacion_id, inicio) VALUES (3, 90002, %L)',
           (SELECT t0 + INTERVAL '1 hour' FROM escenario)));
SELECT pg_temp.debe_funcionar('Reserva contigua en la misma mesa (21:00, intervalo semiabierto)',
    format('INSERT INTO horarios (mesa_id, reservacion_id, inicio) VALUES (3, 90002, %L)',
           (SELECT t0 + INTERVAL '2 hours' FROM escenario)));

-- 2. Sillas insuficientes
INSERT INTO reservaciones (id, cliente_id, cantidad, estado) VALUES (90003, 10, 6, 1);
SELECT pg_temp.debe_fallar('6 personas en la mesa 1 (2 sillas)',
    format('INSERT INTO horarios (mesa_id, reservacion_id, inicio) VALUES (1, 90003, %L)',
           (SELECT t0 FROM escenario)));
SELECT pg_temp.debe_fallar('Aumentar personas por encima de las sillas',
    'UPDATE reservaciones SET cantidad = 9 WHERE id = 90001');

-- 3. Cancelar libera la mesa
SELECT pg_temp.debe_funcionar('Cancelar la reservación 90001',
    'UPDATE reservaciones SET estado = 0 WHERE id = 90001');
SELECT pg_temp.debe_funcionar('La mesa 3 queda libre a las 19:00',
    format('INSERT INTO horarios (mesa_id, reservacion_id, inicio) VALUES (6, 90003, %L)',
           (SELECT t0 FROM escenario)));
SELECT pg_temp.debe_fallar('Reactivar una reserva que ahora se cruza',
    format($q$DO $d$ BEGIN
        INSERT INTO reservaciones (id, cliente_id, cantidad, estado) VALUES (90004, 10, 2, 1);
        INSERT INTO horarios (mesa_id, reservacion_id, inicio) VALUES (3, 90004, %L);
        UPDATE reservaciones SET estado = 1 WHERE id = 90001;
    END $d$$q$, (SELECT t0 FROM escenario)));

-- 4. Cupo del restaurante: con una reserva "multi-mesa" que ocupa todas
--    las mesas excepto la 10, intentar sumar más personas que el cupo
DO $$
DECLARE
    v_t0 TIMESTAMP := (SELECT t0 FROM escenario) + INTERVAL '1 day';
    v_cupo INT := fn_cupo_total();
    m RECORD;
BEGIN
    INSERT INTO reservaciones (id, cliente_id, cantidad, estado) VALUES (90010, 10, 1, 1);
    FOR m IN SELECT id FROM mesas WHERE id <> 10 LOOP
        INSERT INTO horarios (mesa_id, reservacion_id, inicio) VALUES (m.id, 90010, v_t0);
    END LOOP;
    UPDATE reservaciones SET cantidad = v_cupo - 10 WHERE id = 90010;
    RAISE NOTICE 'OK     Evento que ocupa % de % sillas', v_cupo - 10, v_cupo;
END $$;
SELECT pg_temp.debe_funcionar('Mesa 10 (10 sillas) completa el cupo exacto',
    format($q$DO $d$ BEGIN
        INSERT INTO reservaciones (id, cliente_id, cantidad, estado) VALUES (90011, 10, 10, 1);
        INSERT INTO horarios (mesa_id, reservacion_id, inicio) VALUES (10, 90011, %L);
    END $d$$q$, (SELECT t0 + INTERVAL '1 day 1 hour' FROM escenario)));
-- Como cada reserva cabe en sus mesas y las mesas no se cruzan, superar el
-- cupo implica violar primero la regla de sillas; ambas se verifican.
SELECT pg_temp.debe_fallar('Superar el cupo aumentando las personas del evento',
    format('UPDATE reservaciones SET cantidad = %s WHERE id = 90010', fn_cupo_total() - 9));
SELECT pg_temp.debe_funcionar('fn_mesas_disponibles no ofrece mesas en ese horario',
    format($q$DO $d$ BEGIN
        IF EXISTS (SELECT 1 FROM fn_mesas_disponibles(%L, 1)) THEN
            RAISE EXCEPTION 'Ofreció mesas ocupadas';
        END IF;
    END $d$$q$, (SELECT t0 + INTERVAL '1 day 1 hour' FROM escenario)));

-- 5. Reducir las sillas de una mesa con reservas futuras
SELECT pg_temp.debe_fallar('Reducir a 2 las sillas de la mesa 10 (reserva de 10 personas)',
    'UPDATE mesas SET sillas = 2 WHERE id = 10');

-- 6. Autorizaciones de cocina
SELECT pg_temp.debe_fallar('Autorizar un plato especial a un cocinero sin rol Chef',
    $q$INSERT INTO autorizaciones (cocinero_id, plato_id)
       SELECT 4, id FROM platos WHERE nombre = 'Salmon al limon'$q$);
SELECT pg_temp.debe_fallar('Autorizar un plato a quien no es cocinero',
    'INSERT INTO autorizaciones (cocinero_id, plato_id) VALUES (2, 1)');
SELECT pg_temp.debe_fallar('Marcar como especial un plato autorizado a no-chefs',
    $q$UPDATE platos SET es_especial = TRUE WHERE nombre = 'Tiramisu'$q$);

-- 7. Pedidos y estados de las órdenes
SELECT pg_temp.debe_fallar('Pedido registrado por un usuario que no es mesero',
    'INSERT INTO pedidos (cliente_id, mesero_id, mesa_id) VALUES (10, 4, 1)');
SELECT pg_temp.debe_fallar('Pedido sin mesa',
    'INSERT INTO pedidos (cliente_id, mesero_id) VALUES (10, 2)');

INSERT INTO pedidos (id, cliente_id, mesero_id, mesa_id) VALUES (90001, 10, 2, 1);
INSERT INTO ordenes (id, plato_id, pedido_id, cantidad) VALUES (90001, 8, 90001, 1);  -- Tiramisu
SELECT pg_temp.debe_funcionar('La orden nueva queda en preparación con el precio del plato',
    $q$DO $d$ BEGIN
        IF (SELECT estado FROM ordenes WHERE id = 90001) <> 1
           OR (SELECT precio FROM ordenes WHERE id = 90001) <> (SELECT precio FROM platos WHERE id = 8) THEN
            RAISE EXCEPTION 'Estado o precio inicial incorrecto';
        END IF;
    END $d$$q$);
SELECT pg_temp.debe_fallar('Entregar un plato que no está preparado',
    'UPDATE ordenes SET estado = 3 WHERE id = 90001');
SELECT pg_temp.debe_fallar('Marcar preparado sin que un cocinero lo tome',
    'UPDATE ordenes SET estado = 2 WHERE id = 90001');
SELECT pg_temp.debe_fallar('Un cocinero no autorizado toma el plato',
    'SELECT tomar_orden(90001, 4)');
SELECT pg_temp.debe_funcionar('Mariana (autorizada) toma el Tiramisu',
    'SELECT tomar_orden(90001, 9)');
SELECT pg_temp.debe_funcionar('Mariana lo marca como preparado',
    'SELECT marcar_orden_preparada(90001, 9)');
SELECT pg_temp.debe_funcionar('Se notifica al mesero que el pedido está listo',
    $q$DO $d$ BEGIN
        IF NOT EXISTS (SELECT 1 FROM notificaciones
                       WHERE tipo = 'PEDIDO_LISTO' AND referencia_id = 90001 AND destinatario_id = 2) THEN
            RAISE EXCEPTION 'No se creó la notificación';
        END IF;
    END $d$$q$);
SELECT pg_temp.debe_funcionar('El mesero entrega el plato preparado',
    'UPDATE ordenes SET estado = 3 WHERE id = 90001');
SELECT pg_temp.debe_fallar('El estado no puede retroceder',
    'UPDATE ordenes SET estado = 1 WHERE id = 90001');

UPDATE platos SET activo = FALSE WHERE id = 12;
SELECT pg_temp.debe_fallar('Pedir un plato retirado del menú',
    'INSERT INTO ordenes (plato_id, pedido_id, cantidad) VALUES (12, 90001, 1)');

-- 8. Claves
SELECT pg_temp.debe_funcionar('Autenticación correcta (ana / clave_ana_2026)',
    $q$DO $d$ BEGIN
        IF fn_autenticar('ana', 'clave_ana_2026') IS NULL THEN RAISE EXCEPTION 'No autenticó'; END IF;
        IF fn_autenticar('ana', 'otra') IS NOT NULL THEN RAISE EXCEPTION 'Aceptó una clave errada'; END IF;
    END $d$$q$);
SELECT pg_temp.debe_fallar('Clave demasiado corta', 'SELECT fn_establecer_clave(1, ''abc'')');

ROLLBACK;
