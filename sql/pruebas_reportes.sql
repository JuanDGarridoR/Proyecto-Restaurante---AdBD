-- ====================================================================
-- Script de Pruebas: Reportes del Administrador e Historial de Clientes
-- Base de datos: PostgreSQL (restaurante)
--
-- Demuestra:
-- 1. Reporte de Reservaciones por periodo (semanal y mensual) con ocupación.
-- 2. Reporte de Ítems más solicitados (Top N con RANK general y por categoría).
-- 3. Reporte de Ventas por periodo con ticket promedio y variación porcentual (LAG).
-- 4. Historial completo de clientes (resumen de gasto, visitas, plato favorito y timeline).
-- 5. Comparativa EXPLAIN ANALYZE antes y después de índices.
-- 6. Consulta y refresco de la vista materializada de ventas diarias.
-- ====================================================================

\pset footer off

\echo '===================================================================='
\echo '1. REPORTE DE RESERVACIONES POR PERIODO (SEMANAL)'
\echo 'Incluye: # Reservas, # Personas, Cancelaciones, Cupo y % Ocupación'
\echo '===================================================================='
SELECT periodo, fecha_inicio_periodo, numero_reservaciones, numero_personas, 
       cancelaciones, cupo_total_disponible, porcentaje_ocupacion || '%' AS ocupacion
FROM reporte_reservaciones('semana', (CURRENT_DATE - INTERVAL '35 days')::date, CURRENT_DATE);

\echo ''
\echo '===================================================================='
\echo '2. REPORTE DE ÍTEMS MÁS SOLICITADOS (TOP 8 DEL MENÚ)'
\echo 'Incluye: Cantidad vendida, Ingresos, Ranking en Categoría y Ranking General'
\echo '===================================================================='
SELECT ranking_general AS rank_gral, plato_nombre, categoria, cantidad_vendida, 
       '$' || to_char(ingresos_generados, 'FM999,999,999') AS ingresos,
       ranking_categoria AS rank_cat
FROM reporte_items_mas_solicitados((CURRENT_DATE - INTERVAL '60 days')::date, CURRENT_DATE, 8);

\echo ''
\echo '===================================================================='
\echo '3. REPORTE DE VENTAS POR PERIODO (SEMANAL)'
\echo 'Incluye: Total vendido, # Pedidos, Ticket promedio y Variación % vs anterior (LAG)'
\echo '===================================================================='
SELECT periodo, fecha_inicio_periodo,
       '$' || to_char(total_vendido, 'FM999,999,999') AS ventas,
       numero_pedidos,
       '$' || to_char(ticket_promedio, 'FM999,999') AS ticket_prom,
       COALESCE('$' || to_char(ventas_periodo_anterior, 'FM999,999,999'), 'N/A') AS ventas_ant,
       COALESCE(to_char(variacion_porcentual, 'FM990.99') || '%', 'N/A') AS variacion
FROM reporte_ventas_periodo('semana', (CURRENT_DATE - INTERVAL '40 days')::date, CURRENT_DATE);

\echo ''
\echo '===================================================================='
\echo '4. HISTORIAL DE CLIENTES'
\echo 'Resumen de cliente (total gastado, visitas, plato favorito) y cronología'
\echo '===================================================================='
\echo '--- Resumen de Cliente (Ana Torres, id 1) ---'
SELECT cliente_id, nombre, documento, 
       '$' || to_char(total_gastado, 'FM999,999,999') AS total_gastado, 
       numero_visitas, plato_favorito, cantidad_plato_favorito
FROM historial_cliente_resumen(1);

\echo ''
\echo '--- Cronología Detallada (Últimos 6 eventos de Ana Torres) ---'
SELECT to_char(fecha, 'YYYY-MM-DD HH24:MI') AS fecha, tipo_evento, referencia_id, 
       detalle, '$' || to_char(monto, 'FM999,999') AS monto, estado_texto
FROM historial_cliente_timeline(1)
LIMIT 6;

\echo ''
\echo '===================================================================='
\echo '5. VISTA MATERIALIZADA DE VENTAS DIARIAS (Últimos 5 días)'
\echo '===================================================================='
SELECT fecha, numero_pedidos, total_items, 
       '$' || to_char(total_vendido, 'FM999,999,999') AS total_vendido,
       '$' || to_char(ticket_promedio, 'FM999,999') AS ticket_promedio
FROM vm_ventas_diarias
ORDER BY fecha DESC
LIMIT 5;

\echo ''
\echo '--- Refrescando la vista materializada ---'
SELECT refrescar_ventas_diarias();
\echo 'Vista materializada refrescada exitosamente.'

\echo ''
\echo '===================================================================='
\echo '6. COMPARATIVA EXPLAIN ANALYZE (ANTES Y DESPUÉS DE ÍNDICES)'
\echo '===================================================================='

\echo '--- Consulta A: Filtrado de órdenes por rango de fechas (solicitado) ---'
\echo '[ANTES] Sin índice / Escaneo secuencial (Seq Scan):'
SET enable_indexscan = off;
SET enable_bitmapscan = off;
EXPLAIN ANALYZE
SELECT o.plato_id, SUM(o.cantidad)
FROM ordenes o
WHERE o.solicitado BETWEEN '2026-09-01' AND '2026-10-01'
GROUP BY o.plato_id;

\echo ''
\echo '[DESPUÉS] Con índice idx_ordenes_solicitado (Index Scan):'
SET enable_indexscan = on;
SET enable_bitmapscan = on;
SET enable_seqscan = off;
EXPLAIN ANALYZE
SELECT o.plato_id, SUM(o.cantidad)
FROM ordenes o
WHERE o.solicitado BETWEEN '2026-09-01' AND '2026-10-01'
GROUP BY o.plato_id;

\echo ''
\echo '--- Consulta B: Filtrado de horarios de reservaciones por fecha (inicio) ---'
\echo '[ANTES] Sin índice / Escaneo secuencial (Seq Scan):'
SET enable_indexscan = off;
SET enable_bitmapscan = off;
SET enable_seqscan = on;
EXPLAIN ANALYZE
SELECT h.mesa_id, COUNT(*)
FROM horarios h
WHERE h.inicio BETWEEN '2026-09-01' AND '2026-10-01'
GROUP BY h.mesa_id;

\echo ''
\echo '[DESPUÉS] Con índice idx_horarios_inicio (Index Scan):'
SET enable_indexscan = on;
SET enable_bitmapscan = on;
SET enable_seqscan = off;
EXPLAIN ANALYZE
SELECT h.mesa_id, COUNT(*)
FROM horarios h
WHERE h.inicio BETWEEN '2026-09-01' AND '2026-10-01'
GROUP BY h.mesa_id;
RESET enable_seqscan;
RESET enable_indexscan;
RESET enable_bitmapscan;

\echo ''
\echo '===================================================================='
\echo 'FIN DE PRUEBAS DE REPORTES'
\echo '===================================================================='
