-- ====================================================================
-- Script de Migración: Reportes del Administrador e Historial de Clientes
-- Base de datos: PostgreSQL (restaurante)
-- ====================================================================

BEGIN;

-- 1. Actualización de esquema: documento en usuarios, precio en ordenes y mesa_id en pedidos
ALTER TABLE usuarios ADD COLUMN IF NOT EXISTS documento VARCHAR(50);
ALTER TABLE ordenes ADD COLUMN IF NOT EXISTS precio NUMERIC;
ALTER TABLE pedidos ADD COLUMN IF NOT EXISTS mesa_id INT REFERENCES mesas(id);

-- Poblar documentos para usuarios existentes si no los tienen
UPDATE usuarios 
SET documento = 'CC-' || (10000000 + id)
WHERE documento IS NULL;

-- Sincronizar precios de platos en órdenes existentes
UPDATE ordenes o
SET precio = p.precio
FROM platos p
WHERE p.id = o.plato_id AND o.precio IS NULL;

-- 2. Índices de rendimiento para consultas y reportes
CREATE INDEX IF NOT EXISTS idx_ordenes_solicitado ON ordenes(solicitado);
CREATE INDEX IF NOT EXISTS idx_ordenes_pedido ON ordenes(pedido_id);
CREATE INDEX IF NOT EXISTS idx_ordenes_plato ON ordenes(plato_id);
CREATE INDEX IF NOT EXISTS idx_horarios_inicio ON horarios(inicio);
CREATE INDEX IF NOT EXISTS idx_horarios_reservacion ON horarios(reservacion_id);
CREATE INDEX IF NOT EXISTS idx_pedidos_cliente ON pedidos(cliente_id);
CREATE INDEX IF NOT EXISTS idx_reservaciones_cliente ON reservaciones(cliente_id);
CREATE INDEX IF NOT EXISTS idx_usuarios_documento ON usuarios(documento);
CREATE INDEX IF NOT EXISTS idx_usuarios_nombre ON usuarios(nombre);

-- 3. Generación de datos de prueba para los últimos 2 meses (60 días) con generate_series
DO $$
DECLARE
    v_fecha DATE;
    v_dia_ts TIMESTAMP WITH TIME ZONE;
    v_cliente_id INT;
    v_mesero_id INT;
    v_mesa_id INT;
    v_pedido_id INT;
    v_reserva_id INT;
    v_plato_id INT;
    v_precio NUMERIC;
    v_cant_pedidos INT;
    v_cant_reservas INT;
    v_cant_platos INT;
    v_hora TIMESTAMP WITH TIME ZONE;
    v_num_personas INT;
    v_estado_res INT;
    v_necesita_generar BOOLEAN;
    i INT;
    j INT;
    k INT;
    v_ya_generado BOOLEAN;
BEGIN
    -- Verificar si faltan datos históricos suficientes para los 60 días
    SELECT COUNT(*) < 100 FROM ordenes INTO v_necesita_generar;

    IF v_necesita_generar THEN
        RAISE NOTICE 'Generando 60 días de datos históricos (reservaciones y pedidos) con generate_series...';

        FOR v_fecha IN 
            SELECT (CURRENT_DATE - (n || ' days')::interval)::date
            FROM generate_series(60, 1, -1) AS n
        LOOP
            v_dia_ts := v_fecha::timestamp with time zone;

            -- Generar entre 4 y 7 reservaciones por día
            v_cant_reservas := 4 + (abs(hashtext(v_fecha::text)) % 4);
            FOR j IN 1..v_cant_reservas LOOP
                -- Cliente aleatorio (de los usuarios existentes)
                SELECT id INTO v_cliente_id FROM usuarios ORDER BY random() LIMIT 1;
                -- Mesa aleatoria
                SELECT id, sillas INTO v_mesa_id, v_num_personas FROM mesas ORDER BY random() LIMIT 1;
                v_num_personas := LEAST(v_num_personas, 2 + (j % 4) * 2);

                -- Hora entre 12:00 y 21:00
                v_hora := v_dia_ts + ((12 + (j * 2) % 9) || ' hours')::interval + ((j * 15) % 60 || ' minutes')::interval;

                -- 85% activas (1), 15% canceladas (0)
                v_estado_res := CASE WHEN (j % 6 = 0) THEN 0 ELSE 1 END;

                INSERT INTO reservaciones (cliente_id, cantidad, estado)
                VALUES (v_cliente_id, v_num_personas, v_estado_res)
                RETURNING id INTO v_reserva_id;

                INSERT INTO horarios (mesa_id, reservacion_id, inicio, duracion)
                VALUES (v_mesa_id, v_reserva_id, v_hora, INTERVAL '1 hour 45 minutes');
            END LOOP;

            -- Generar entre 6 y 12 pedidos por día
            v_cant_pedidos := 6 + (abs(hashtext((v_fecha + 1)::text)) % 7);
            FOR j IN 1..v_cant_pedidos LOOP
                SELECT id INTO v_cliente_id FROM usuarios ORDER BY random() LIMIT 1;
                SELECT u.id INTO v_mesero_id 
                FROM usuarios u 
                JOIN actuaciones a ON a.usuario_id = u.id 
                JOIN roles r ON r.id = a.rol_id 
                WHERE r.nombre = 'Mesero' 
                ORDER BY random() LIMIT 1;

                SELECT id INTO v_mesa_id FROM mesas ORDER BY random() LIMIT 1;

                v_hora := v_dia_ts + ((11 + (j * 1) % 11) || ' hours')::interval + ((j * 7) % 60 || ' minutes')::interval;

                INSERT INTO pedidos (cliente_id, mesero_id, mesa_id)
                VALUES (v_cliente_id, v_mesero_id, v_mesa_id)
                RETURNING id INTO v_pedido_id;

                -- Entre 1 y 4 platos por pedido
                v_cant_platos := 1 + (j % 4);
                FOR k IN 1..v_cant_platos LOOP
                    SELECT id, precio INTO v_plato_id, v_precio FROM platos ORDER BY random() LIMIT 1;

                    INSERT INTO ordenes (plato_id, pedido_id, estado, cantidad, solicitado, precio, hora_tomado, hora_terminado)
                    VALUES (
                        v_plato_id,
                        v_pedido_id,
                        3, -- Entregado
                        1 + (k % 2),
                        v_hora,
                        v_precio,
                        v_hora + INTERVAL '5 minutes',
                        v_hora + INTERVAL '25 minutes'
                    );
                END LOOP;
            END LOOP;
        END LOOP;
        RAISE NOTICE 'Generación de datos históricos completada exitosamente.';
    ELSE
        RAISE NOTICE 'Datos históricos recientes ya existentes en la base de datos.';
    END IF;
END $$;

-- 4. Reporte 1: Reservaciones por periodo (día, semana, mes) con porcentaje de ocupación
CREATE OR REPLACE FUNCTION reporte_reservaciones(
    p_granularidad TEXT,
    p_fecha_inicio DATE,
    p_fecha_fin DATE
)
RETURNS TABLE (
    periodo TEXT,
    fecha_inicio_periodo DATE,
    numero_reservaciones BIGINT,
    numero_personas BIGINT,
    cancelaciones BIGINT,
    cupo_total_disponible NUMERIC,
    porcentaje_ocupacion NUMERIC
) AS $$
DECLARE
    v_cupo_base NUMERIC;
BEGIN
    SELECT COALESCE(SUM(sillas), 0) INTO v_cupo_base FROM mesas;

    RETURN QUERY
    WITH datos_res AS (
        SELECT 
            CASE 
                WHEN lower(p_granularidad) IN ('dia', 'day') 
                    THEN to_char(date_trunc('day', h.inicio), 'YYYY-MM-DD')
                WHEN lower(p_granularidad) IN ('semana', 'week') 
                    THEN to_char(date_trunc('week', h.inicio), 'IYYY-"W"IW')
                WHEN lower(p_granularidad) IN ('mes', 'month') 
                    THEN to_char(date_trunc('month', h.inicio), 'YYYY-MM')
                ELSE to_char(date_trunc('day', h.inicio), 'YYYY-MM-DD')
            END AS per,
            date_trunc(
                CASE 
                    WHEN lower(p_granularidad) IN ('dia', 'day') THEN 'day'
                    WHEN lower(p_granularidad) IN ('semana', 'week') THEN 'week'
                    WHEN lower(p_granularidad) IN ('mes', 'month') THEN 'month'
                    ELSE 'day'
                END, 
                h.inicio
            )::date AS fecha_inicio,
            res.id AS reserva_id,
            res.cantidad,
            res.estado,
            DATE(h.inicio) AS fecha_dia
        FROM reservaciones res
        JOIN horarios h ON h.reservacion_id = res.id
        WHERE DATE(h.inicio) BETWEEN p_fecha_inicio AND p_fecha_fin
    )
    SELECT 
        d.per AS periodo,
        d.fecha_inicio AS fecha_inicio_periodo,
        COUNT(d.reserva_id) AS numero_reservaciones,
        COALESCE(SUM(CASE WHEN d.estado != 0 THEN d.cantidad ELSE 0 END), 0) AS numero_personas,
        COUNT(*) FILTER (WHERE d.estado = 0) AS cancelaciones,
        (v_cupo_base * GREATEST(1, COUNT(DISTINCT d.fecha_dia)))::numeric AS cupo_total_disponible,
        ROUND(
            (COALESCE(SUM(CASE WHEN d.estado != 0 THEN d.cantidad ELSE 0 END), 0)::numeric / 
             NULLIF(v_cupo_base * GREATEST(1, COUNT(DISTINCT d.fecha_dia)), 0)) * 100, 
            2
        ) AS porcentaje_ocupacion
    FROM datos_res d
    GROUP BY d.per, d.fecha_inicio
    ORDER BY d.fecha_inicio ASC;
END;
$$ LANGUAGE plpgsql;

-- 5. Reporte 2: Ítems más solicitados (Top N con funciones de ventana RANK)
CREATE OR REPLACE FUNCTION reporte_items_mas_solicitados(
    p_fecha_inicio DATE,
    p_fecha_fin DATE,
    p_top_n INT DEFAULT 10
)
RETURNS TABLE (
    plato_id INT,
    plato_nombre TEXT,
    categoria TEXT,
    cantidad_vendida BIGINT,
    ingresos_generados NUMERIC,
    ranking_categoria BIGINT,
    ranking_general BIGINT
) AS $$
BEGIN
    RETURN QUERY
    WITH agregados AS (
        SELECT 
            p.id AS p_id,
            p.nombre AS p_nom,
            COALESCE(t.nombre, 'Sin categoría') AS p_cat,
            SUM(o.cantidad)::bigint AS cant_vendida,
            SUM(o.cantidad * COALESCE(o.precio, p.precio, 0))::numeric AS ingresos
        FROM ordenes o
        JOIN platos p ON p.id = o.plato_id
        LEFT JOIN tipos t ON t.id = p.tipo_id
        WHERE DATE(o.solicitado) BETWEEN p_fecha_inicio AND p_fecha_fin
        GROUP BY p.id, p.nombre, t.nombre
    )
    SELECT 
        a.p_id AS plato_id,
        a.p_nom AS plato_nombre,
        a.p_cat AS categoria,
        a.cant_vendida AS cantidad_vendida,
        a.ingresos AS ingresos_generados,
        RANK() OVER (PARTITION BY a.p_cat ORDER BY a.cant_vendida DESC)::bigint AS ranking_categoria,
        RANK() OVER (ORDER BY a.cant_vendida DESC)::bigint AS ranking_general
    FROM agregados a
    ORDER BY ranking_general ASC, a.cant_vendida DESC
    LIMIT p_top_n;
END;
$$ LANGUAGE plpgsql;

-- 6. Reporte 3: Ventas totales por periodo con ticket promedio y variación respecto al periodo anterior (LAG)
CREATE OR REPLACE FUNCTION reporte_ventas_periodo(
    p_granularidad TEXT,
    p_fecha_inicio DATE,
    p_fecha_fin DATE
)
RETURNS TABLE (
    periodo TEXT,
    fecha_inicio_periodo DATE,
    total_vendido NUMERIC,
    numero_pedidos BIGINT,
    ticket_promedio NUMERIC,
    ventas_periodo_anterior NUMERIC,
    variacion_porcentual NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    WITH ventas_base AS (
        SELECT 
            CASE 
                WHEN lower(p_granularidad) IN ('dia', 'day') 
                    THEN to_char(date_trunc('day', o.solicitado), 'YYYY-MM-DD')
                WHEN lower(p_granularidad) IN ('semana', 'week') 
                    THEN to_char(date_trunc('week', o.solicitado), 'IYYY-"W"IW')
                WHEN lower(p_granularidad) IN ('mes', 'month') 
                    THEN to_char(date_trunc('month', o.solicitado), 'YYYY-MM')
                ELSE to_char(date_trunc('day', o.solicitado), 'YYYY-MM-DD')
            END AS per,
            date_trunc(
                CASE 
                    WHEN lower(p_granularidad) IN ('dia', 'day') THEN 'day'
                    WHEN lower(p_granularidad) IN ('semana', 'week') THEN 'week'
                    WHEN lower(p_granularidad) IN ('mes', 'month') THEN 'month'
                    ELSE 'day'
                END, 
                o.solicitado
            )::date AS f_inicio,
            COUNT(DISTINCT p.id)::bigint AS cant_pedidos,
            SUM(o.cantidad * COALESCE(o.precio, pla.precio, 0))::numeric AS tot_vendido
        FROM pedidos p
        JOIN ordenes o ON o.pedido_id = p.id
        JOIN platos pla ON pla.id = o.plato_id
        WHERE DATE(o.solicitado) BETWEEN p_fecha_inicio AND p_fecha_fin
        GROUP BY per, f_inicio
    )
    SELECT 
        v.per AS periodo,
        v.f_inicio AS fecha_inicio_periodo,
        v.tot_vendido AS total_vendido,
        v.cant_pedidos AS numero_pedidos,
        ROUND(v.tot_vendido / NULLIF(v.cant_pedidos, 0), 2) AS ticket_promedio,
        LAG(v.tot_vendido) OVER (ORDER BY v.f_inicio) AS ventas_periodo_anterior,
        ROUND(
            ((v.tot_vendido - LAG(v.tot_vendido) OVER (ORDER BY v.f_inicio)) / 
             NULLIF(LAG(v.tot_vendido) OVER (ORDER BY v.f_inicio), 0)) * 100, 
            2
        ) AS variacion_porcentual
    FROM ventas_base v
    ORDER BY v.f_inicio ASC;
END;
$$ LANGUAGE plpgsql;

-- 7. Historial de Clientes: Resumen y Cronología Detallada
CREATE OR REPLACE FUNCTION historial_cliente_resumen(p_cliente_id INT)
RETURNS TABLE (
    cliente_id INT,
    nombre TEXT,
    documento VARCHAR(50),
    total_gastado NUMERIC,
    numero_visitas BIGINT,
    plato_favorito TEXT,
    cantidad_plato_favorito BIGINT
) AS $$
BEGIN
    RETURN QUERY
    WITH datos_pedidos AS (
        SELECT 
            COUNT(DISTINCT p.id)::bigint AS visitas_pedidos,
            COALESCE(SUM(o.cantidad * COALESCE(o.precio, pla.precio, 0)), 0)::numeric AS gasto_pedidos
        FROM pedidos p
        JOIN ordenes o ON o.pedido_id = p.id
        JOIN platos pla ON pla.id = o.plato_id
        WHERE p.cliente_id = p_cliente_id
    ),
    datos_reservas AS (
        SELECT COUNT(*)::bigint AS visitas_reservas
        FROM reservaciones res
        WHERE res.cliente_id = p_cliente_id AND res.estado != 0
    ),
    fav AS (
        SELECT pla.nombre AS nom_plato, SUM(o.cantidad)::bigint AS cant_pedida
        FROM pedidos p
        JOIN ordenes o ON o.pedido_id = p.id
        JOIN platos pla ON pla.id = o.plato_id
        WHERE p.cliente_id = p_cliente_id
        GROUP BY pla.id, pla.nombre
        ORDER BY cant_pedida DESC
        LIMIT 1
    )
    SELECT 
        u.id AS cliente_id,
        u.nombre,
        u.documento,
        COALESCE(dp.gasto_pedidos, 0)::numeric AS total_gastado,
        (COALESCE(dp.visitas_pedidos, 0) + COALESCE(dr.visitas_reservas, 0))::bigint AS numero_visitas,
        COALESCE(f.nom_plato, 'Sin pedidos aún') AS plato_favorito,
        COALESCE(f.cant_pedida, 0)::bigint AS cantidad_plato_favorito
    FROM usuarios u
    LEFT JOIN datos_pedidos dp ON true
    LEFT JOIN datos_reservas dr ON true
    LEFT JOIN fav f ON true
    WHERE u.id = p_cliente_id;
END;
$$ LANGUAGE plpgsql;

-- Cronología detallada del cliente (reservaciones y pedidos combinados)
CREATE OR REPLACE FUNCTION historial_cliente_timeline(p_cliente_id INT)
RETURNS TABLE (
    fecha TIMESTAMP WITH TIME ZONE,
    tipo_evento TEXT,
    referencia_id INT,
    detalle TEXT,
    monto NUMERIC,
    estado_texto TEXT
) AS $$
BEGIN
    RETURN QUERY
    -- Pedidos del cliente
    SELECT 
        MIN(o.solicitado) AS fecha,
        'Pedido'::text AS tipo_evento,
        p.id AS referencia_id,
        'Pedido #' || p.id || ' con ' || COALESCE(SUM(o.cantidad), 0) || ' plato(s)' AS detalle,
        COALESCE(SUM(o.cantidad * COALESCE(o.precio, pla.precio, 0)), 0)::numeric AS monto,
        CASE MIN(o.estado)
            WHEN 1 THEN 'En preparación'
            WHEN 2 THEN 'Preparado'
            WHEN 3 THEN 'Entregado'
            ELSE 'Desconocido'
        END AS estado_texto
    FROM pedidos p
    JOIN ordenes o ON o.pedido_id = p.id
    JOIN platos pla ON pla.id = o.plato_id
    WHERE p.cliente_id = p_cliente_id
    GROUP BY p.id

    UNION ALL

    -- Reservaciones del cliente
    SELECT 
        h.inicio AS fecha,
        'Reservación'::text AS tipo_evento,
        res.id AS referencia_id,
        'Reserva Mesa #' || h.mesa_id || ' para ' || res.cantidad || ' personas' AS detalle,
        0::numeric AS monto,
        CASE res.estado
            WHEN 0 THEN 'Cancelada'
            WHEN 1 THEN 'Activa'
            WHEN 2 THEN 'Completada'
            ELSE 'Estado ' || res.estado
        END AS estado_texto
    FROM reservaciones res
    JOIN horarios h ON h.reservacion_id = res.id
    WHERE res.cliente_id = p_cliente_id

    ORDER BY fecha DESC;
END;
$$ LANGUAGE plpgsql;

-- 8. Vista Materializada para Ventas Diarias con instrucción de refresco
CREATE MATERIALIZED VIEW IF NOT EXISTS vm_ventas_diarias AS
SELECT 
    DATE(o.solicitado) AS fecha,
    COUNT(DISTINCT p.id)::bigint AS numero_pedidos,
    SUM(o.cantidad)::bigint AS total_items,
    SUM(o.cantidad * COALESCE(o.precio, pla.precio, 0))::numeric AS total_vendido,
    ROUND(SUM(o.cantidad * COALESCE(o.precio, pla.precio, 0))::numeric / NULLIF(COUNT(DISTINCT p.id), 0), 2) AS ticket_promedio
FROM pedidos p
JOIN ordenes o ON o.pedido_id = p.id
JOIN platos pla ON pla.id = o.plato_id
WHERE o.solicitado IS NOT NULL
GROUP BY DATE(o.solicitado)
ORDER BY fecha DESC;

CREATE UNIQUE INDEX IF NOT EXISTS uq_vm_ventas_diarias_fecha ON vm_ventas_diarias(fecha);

CREATE OR REPLACE FUNCTION refrescar_ventas_diarias()
RETURNS void AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY vm_ventas_diarias;
EXCEPTION WHEN OTHERS THEN
    REFRESH MATERIALIZED VIEW vm_ventas_diarias;
END;
$$ LANGUAGE plpgsql;

COMMIT;
