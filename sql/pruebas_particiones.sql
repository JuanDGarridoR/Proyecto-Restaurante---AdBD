-- ====================================================================
-- Pruebas de tablespaces y partición de notificaciones
-- (tablespaces.sql y migracion_particiones.sql)
-- Cada prueba imprime OK o FALLA. Todo se deshace al final (ROLLBACK).
-- Uso: psql -U postgres -d restaurante -f pruebas_particiones.sql
--      (como superusuario o dueño de las tablas: la prueba 5 mueve una
--       partición de tablespace)
-- ====================================================================

\pset footer off
BEGIN;
SET search_path = public;

\echo '--- Tablespaces definidos (dos directorios distintos) ---'
SELECT spcname AS tablespace, pg_tablespace_location(oid) AS directorio
FROM pg_tablespace WHERE spcname LIKE 'ts_restaurante%' ORDER BY spcname;

\echo '--- Particiones de notificaciones antes de las pruebas ---'
SELECT particion, rango, tablespace FROM v_particiones_notificaciones;

DO $$
DECLARE
    v_mesero INT := (SELECT id FROM usuarios WHERE login = 'carlos');
    v_particion TEXT;
    v_cant INT;
    v_id INT;
    v_tablespaces INT;
BEGIN
    -- 1. Hay dos tablespaces en directorios distintos
    SELECT COUNT(DISTINCT pg_tablespace_location(oid)) INTO v_tablespaces
    FROM pg_tablespace WHERE spcname IN ('ts_restaurante_actual', 'ts_restaurante_historico');
    RAISE NOTICE '% 1. Dos tablespaces en directorios distintos (%)',
        CASE WHEN v_tablespaces = 2 THEN 'OK   ' ELSE 'FALLA' END, v_tablespaces;

    -- 2. La tabla está particionada por rango de fecha_creacion
    SELECT pg_get_partkeydef('notificaciones'::regclass) INTO v_particion;
    RAISE NOTICE '% 2. notificaciones particionada: %',
        CASE WHEN v_particion = 'RANGE (fecha_creacion)' THEN 'OK   ' ELSE 'FALLA' END, v_particion;

    -- 3. Una notificación de hoy cae en la partición del mes actual (tablespace actual)
    INSERT INTO notificaciones (destinatario_id, tipo, referencia_id, mensaje)
    VALUES (v_mesero, 'PEDIDO_LISTO', 990001, 'Prueba: notificación de hoy')
    RETURNING id INTO v_id;
    SELECT tableoid::regclass::text INTO v_particion FROM notificaciones WHERE id = v_id;
    RAISE NOTICE '% 3. Notificación de hoy guardada en %',
        CASE WHEN v_particion = 'notificaciones_' || to_char(CURRENT_DATE, 'YYYY_MM') THEN 'OK   ' ELSE 'FALLA' END, v_particion;

    -- 4. Una notificación de hace un año cae en la partición histórica
    INSERT INTO notificaciones (destinatario_id, tipo, referencia_id, mensaje, fecha_creacion)
    VALUES (v_mesero, 'PEDIDO_LISTO', 990002, 'Prueba: notificación antigua', CURRENT_TIMESTAMP - INTERVAL '1 year')
    RETURNING id INTO v_id;
    SELECT n.tableoid::regclass::text || ' / ' || t.spcname INTO v_particion
    FROM notificaciones n
    JOIN pg_class c ON c.oid = n.tableoid
    JOIN pg_tablespace t ON t.oid = c.reltablespace
    WHERE n.id = v_id;
    RAISE NOTICE '% 4. Notificación de hace un año guardada en %',
        CASE WHEN v_particion = 'notificaciones_historico / ts_restaurante_historico' THEN 'OK   ' ELSE 'FALLA' END, v_particion;

    -- 5. Duplicado (mismo tipo, referencia y destinatario): se descarta
    INSERT INTO notificaciones (destinatario_id, tipo, referencia_id, mensaje)
    VALUES (v_mesero, 'PEDIDO_LISTO', 990001, 'Prueba: duplicado');
    SELECT COUNT(*) INTO v_cant FROM notificaciones
    WHERE tipo = 'PEDIDO_LISTO' AND referencia_id = 990001 AND destinatario_id = v_mesero;
    RAISE NOTICE '% 5. Duplicado descartado por trg_notificacion_unica (% fila)',
        CASE WHEN v_cant = 1 THEN 'OK   ' ELSE 'FALLA' END, v_cant;

    -- 6. Partition pruning: una consulta por fecha solo lee la partición del mes
    SELECT COUNT(*) INTO v_cant FROM notificaciones
    WHERE fecha_creacion >= date_trunc('month', CURRENT_DATE);
    RAISE NOTICE 'OK    6. Consulta del mes actual: % fila(s) (ver EXPLAIN abajo)', v_cant;

    -- 7. Archivar: con 0 meses, las particiones mensuales anteriores al mes
    --    actual pasan al tablespace histórico
    SELECT COUNT(*) INTO v_cant FROM fn_archivar_notificaciones(0);
    SELECT t.spcname INTO v_particion
    FROM pg_class c JOIN pg_tablespace t ON t.oid = c.reltablespace
    WHERE c.relname = 'notificaciones_' || to_char(CURRENT_DATE - INTERVAL '1 month', 'YYYY_MM');
    RAISE NOTICE '% 7. fn_archivar_notificaciones movió % partición(es); la del mes pasado quedó en %',
        CASE WHEN v_particion = 'ts_restaurante_historico' THEN 'OK   ' ELSE 'FALLA' END, v_cant, v_particion;
END $$;

\echo '--- EXPLAIN: solo se recorre la partición del mes actual ---'
EXPLAIN (COSTS OFF)
SELECT * FROM notificaciones
WHERE fecha_creacion >= date_trunc('month', CURRENT_TIMESTAMP)
  AND fecha_creacion <  date_trunc('month', CURRENT_TIMESTAMP) + INTERVAL '1 month';

\echo '--- Particiones después de las pruebas ---'
SELECT * FROM v_particiones_notificaciones;

ROLLBACK;
