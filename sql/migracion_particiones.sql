-- ====================================================================
-- Script de Migración: Partición de notificaciones por fechas
-- Base de datos: PostgreSQL (restaurante)
--
-- Requisito técnico 6.1: "Particionar una tabla por fechas para que use
-- los tablespaces definidos".
--
-- Se particiona la tabla notificaciones por RANGE (fecha_creacion):
--   notificaciones_historico   (MINVALUE .. inicio del mes anterior)
--                              -> tablespace ts_restaurante_historico
--   notificaciones_AAAA_MM     una partición por mes, desde el mes
--                              anterior hasta 3 meses adelante
--                              -> tablespace ts_restaurante_actual
--   notificaciones_default     fechas fuera de los rangos anteriores
--                              -> tablespace ts_restaurante_actual
--
-- Por qué notificaciones: crece todos los días (cada pedido listo y cada
-- reserva próxima generan filas), se consulta casi siempre por las más
-- recientes (no leídas) y ninguna otra tabla tiene llaves foráneas hacia
-- ella, así que se puede particionar sin afectar el resto del modelo.
--
-- Una tabla particionada no admite un UNIQUE que no incluya la columna de
-- partición, así que la regla "una sola notificación por (tipo,
-- referencia, destinatario)" pasa a garantizarse con el trigger
-- trg_notificacion_unica, y las funciones que insertan ya no usan
-- ON CONFLICT.
--
-- Requiere: tablespaces.sql y migracion_notificaciones.sql.
-- Es idempotente: si la tabla ya está particionada no la vuelve a crear.
-- ====================================================================

BEGIN;

SET search_path = public;

-- --------------------------------------------------------------------
-- 1. Crear (si falta) la partición mensual de un mes dado
-- --------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_crear_particion_notificaciones(
    p_mes DATE,
    p_tablespace TEXT DEFAULT 'ts_restaurante_actual'
)
RETURNS TEXT AS $$
DECLARE
    v_desde DATE := date_trunc('month', p_mes)::date;
    v_hasta DATE := (date_trunc('month', p_mes) + INTERVAL '1 month')::date;
    v_nombre TEXT := 'notificaciones_' || to_char(p_mes, 'YYYY_MM');
BEGIN
    IF to_regclass('public.' || v_nombre) IS NOT NULL THEN
        RETURN v_nombre || ' (ya existía)';
    END IF;
    EXECUTE format(
        'CREATE TABLE %I PARTITION OF notificaciones
             FOR VALUES FROM (%L) TO (%L) TABLESPACE %I',
        v_nombre, v_desde, v_hasta, p_tablespace);
    RETURN v_nombre;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION fn_crear_particion_notificaciones(DATE, TEXT) IS
    'Crea la partición mensual notificaciones_AAAA_MM en el tablespace indicado';

-- --------------------------------------------------------------------
-- 2. Archivar: mueve al tablespace histórico las particiones mensuales
--    de hace más de p_meses meses (las filas no cambian, solo el disco)
-- --------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_archivar_notificaciones(p_meses INT DEFAULT 3)
RETURNS SETOF TEXT AS $$
DECLARE
    v_particion RECORD;
    v_limite DATE := (date_trunc('month', CURRENT_DATE) - make_interval(months => p_meses))::date;
BEGIN
    FOR v_particion IN
        SELECT c.relname
        FROM pg_inherits i
        JOIN pg_class c ON c.oid = i.inhrelid
        LEFT JOIN pg_tablespace t ON t.oid = c.reltablespace
        WHERE i.inhparent = 'notificaciones'::regclass
          AND c.relname ~ '^notificaciones_\d{4}_\d{2}$'
          AND to_date(substring(c.relname from '\d{4}_\d{2}$'), 'YYYY_MM') < v_limite
          AND COALESCE(t.spcname, '') <> 'ts_restaurante_historico'
        ORDER BY c.relname
    LOOP
        EXECUTE format('ALTER TABLE %I SET TABLESPACE ts_restaurante_historico', v_particion.relname);
        RETURN NEXT v_particion.relname;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION fn_archivar_notificaciones(INT) IS
    'Mueve a ts_restaurante_historico las particiones mensuales con más de N meses';

-- --------------------------------------------------------------------
-- 3. Convertir notificaciones en tabla particionada (una sola vez)
-- --------------------------------------------------------------------
DO $$
DECLARE
    v_mes DATE := date_trunc('month', CURRENT_DATE)::date;
    v_i INT;
BEGIN
    IF (SELECT relkind FROM pg_class WHERE oid = 'public.notificaciones'::regclass) = 'p' THEN
        RAISE NOTICE 'notificaciones ya está particionada; no se modifica.';
        RETURN;
    END IF;

    -- Conservar las filas actuales y la secuencia de ids
    CREATE TEMP TABLE tmp_notificaciones ON COMMIT DROP AS SELECT * FROM notificaciones;
    ALTER SEQUENCE notificaciones_id_seq OWNED BY NONE;
    DROP TABLE notificaciones;

    CREATE TABLE notificaciones (
        id INT NOT NULL DEFAULT nextval('notificaciones_id_seq'),
        destinatario_id INT NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
        tipo VARCHAR(50) NOT NULL CHECK (tipo IN ('PEDIDO_LISTO', 'RESERVA_PROXIMA')),
        referencia_id INT NOT NULL,
        mensaje TEXT NOT NULL,
        fecha_creacion TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
        leida BOOLEAN NOT NULL DEFAULT FALSE,
        fecha_lectura TIMESTAMP WITH TIME ZONE,
        -- La llave primaria de una tabla particionada debe incluir la
        -- columna de partición
        CONSTRAINT notificaciones_pkey PRIMARY KEY (id, fecha_creacion)
    ) PARTITION BY RANGE (fecha_creacion);

    ALTER SEQUENCE notificaciones_id_seq OWNED BY notificaciones.id;

    -- Histórico: todo lo anterior al mes pasado
    EXECUTE format(
        'CREATE TABLE notificaciones_historico PARTITION OF notificaciones
             FOR VALUES FROM (MINVALUE) TO (%L) TABLESPACE ts_restaurante_historico',
        (v_mes - INTERVAL '1 month')::date);

    -- Mes anterior, mes actual y 3 meses adelante
    FOR v_i IN -1..3 LOOP
        PERFORM fn_crear_particion_notificaciones((v_mes + make_interval(months => v_i))::date);
    END LOOP;

    -- Cualquier otra fecha (p. ej. más allá de los meses creados)
    CREATE TABLE notificaciones_default PARTITION OF notificaciones DEFAULT
        TABLESPACE ts_restaurante_actual;

    INSERT INTO notificaciones SELECT * FROM tmp_notificaciones;
END $$;

COMMENT ON TABLE notificaciones IS
    'Avisos a meseros (pedido listo) y maitres (reserva próxima). Particionada por RANGE (fecha_creacion)';

-- Índices: se crean en la tabla madre y PostgreSQL los replica en cada partición
CREATE INDEX IF NOT EXISTS idx_notif_destinatario_leida ON notificaciones (destinatario_id, leida);
CREATE INDEX IF NOT EXISTS idx_notif_unica ON notificaciones (tipo, referencia_id, destinatario_id);

-- --------------------------------------------------------------------
-- 4. Unicidad (tipo, referencia, destinatario) con trigger
--    Si la notificación ya existe, la inserción se descarta en silencio
--    (mismo efecto que el ON CONFLICT DO NOTHING de la versión anterior).
-- --------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_notificacion_unica()
RETURNS trigger AS $$
BEGIN
    -- Serializa las inserciones de la misma notificación entre sesiones
    PERFORM pg_advisory_xact_lock(hashtextextended(
        'notificacion:' || NEW.tipo || ':' || NEW.referencia_id || ':' || NEW.destinatario_id, 0));
    IF EXISTS (SELECT 1 FROM notificaciones n
               WHERE n.tipo = NEW.tipo
                 AND n.referencia_id = NEW.referencia_id
                 AND n.destinatario_id = NEW.destinatario_id) THEN
        RETURN NULL;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_notificacion_unica ON notificaciones;
CREATE TRIGGER trg_notificacion_unica
BEFORE INSERT ON notificaciones
FOR EACH ROW
EXECUTE FUNCTION trg_notificacion_unica();

-- --------------------------------------------------------------------
-- 5. Funciones que insertan notificaciones, sin ON CONFLICT
--    (misma lógica que migracion_notificaciones.sql)
-- --------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_notificar_pedido_listo()
RETURNS trigger AS $$
DECLARE
    v_total_items INT;
    v_items_preparados INT;
    v_mesero_id INT;
    v_cliente_nombre TEXT;
    v_mensaje TEXT;
    v_notif_id INT;
BEGIN
    IF NEW.estado = 2 THEN
        SELECT COUNT(*), COUNT(*) FILTER (WHERE estado >= 2)
        INTO v_total_items, v_items_preparados
        FROM ordenes
        WHERE pedido_id = NEW.pedido_id;

        -- Solo si todos los ítems del pedido ya están Preparados (o más)
        IF v_total_items > 0 AND v_total_items = v_items_preparados THEN
            SELECT p.mesero_id, u.nombre
            INTO v_mesero_id, v_cliente_nombre
            FROM pedidos p
            LEFT JOIN usuarios u ON u.id = p.cliente_id
            WHERE p.id = NEW.pedido_id;

            IF v_mesero_id IS NOT NULL THEN
                v_mensaje := 'El pedido #' || NEW.pedido_id ||
                             COALESCE(' (' || v_cliente_nombre || ')', '') ||
                             ' está listo para entregar (' || v_total_items || ' plato(s) preparado(s)).';

                v_notif_id := NULL;
                -- trg_notificacion_unica descarta los duplicados
                INSERT INTO notificaciones (destinatario_id, tipo, referencia_id, mensaje, fecha_creacion, leida)
                VALUES (v_mesero_id, 'PEDIDO_LISTO', NEW.pedido_id, v_mensaje, CURRENT_TIMESTAMP, FALSE)
                RETURNING id INTO v_notif_id;

                IF v_notif_id IS NOT NULL THEN
                    PERFORM pg_notify('notificaciones_canal', json_build_object(
                        'notificacion_id', v_notif_id,
                        'tipo', 'PEDIDO_LISTO',
                        'referencia_id', NEW.pedido_id,
                        'destinatario_id', v_mesero_id,
                        'mensaje', v_mensaje,
                        'fecha_creacion', CURRENT_TIMESTAMP
                    )::text);
                END IF;
            END IF;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fn_notificar_reservas_proximas(p_minutos INT DEFAULT 30)
RETURNS INT AS $$
DECLARE
    r RECORD;
    m RECORD;
    v_mensaje TEXT;
    v_notificaciones_creadas INT := 0;
    v_notif_id INT;
BEGIN
    FOR r IN (
        SELECT res.id AS reservacion_id,
               h.mesa_id,
               h.inicio,
               res.cantidad,
               COALESCE(u.nombre, 'Cliente') AS cliente_nombre,
               ROUND(EXTRACT(EPOCH FROM (h.inicio - CURRENT_TIMESTAMP)) / 60) AS minutos_faltantes
        FROM reservaciones res
        JOIN horarios h ON h.reservacion_id = res.id
        LEFT JOIN usuarios u ON u.id = res.cliente_id
        WHERE res.estado = 1
          AND h.inicio >= CURRENT_TIMESTAMP
          AND h.inicio <= CURRENT_TIMESTAMP + (p_minutos || ' minutes')::interval
    ) LOOP
        FOR m IN (
            SELECT DISTINCT u.id AS maitre_id
            FROM usuarios u
            JOIN actuaciones a ON a.usuario_id = u.id
            JOIN roles ro ON ro.id = a.rol_id
            WHERE ro.nombre IN ('Maitre', 'Recepcionista')
        ) LOOP
            v_mensaje := 'Reserva próxima en ' || GREATEST(0, r.minutos_faltantes) || ' min: ' ||
                         'Mesa #' || r.mesa_id || ' para ' || r.cliente_nombre ||
                         ' (' || r.cantidad || ' personas) a las ' || to_char(r.inicio, 'HH24:MI') || '.';

            v_notif_id := NULL;
            -- trg_notificacion_unica descarta los duplicados
            INSERT INTO notificaciones (destinatario_id, tipo, referencia_id, mensaje, fecha_creacion, leida)
            VALUES (m.maitre_id, 'RESERVA_PROXIMA', r.reservacion_id, v_mensaje, CURRENT_TIMESTAMP, FALSE)
            RETURNING id INTO v_notif_id;

            IF v_notif_id IS NOT NULL THEN
                v_notificaciones_creadas := v_notificaciones_creadas + 1;
                PERFORM pg_notify('notificaciones_canal', json_build_object(
                    'notificacion_id', v_notif_id,
                    'tipo', 'RESERVA_PROXIMA',
                    'referencia_id', r.reservacion_id,
                    'destinatario_id', m.maitre_id,
                    'mensaje', v_mensaje,
                    'fecha_creacion', CURRENT_TIMESTAMP
                )::text);
            END IF;
        END LOOP;
    END LOOP;

    RETURN v_notificaciones_creadas;
END;
$$ LANGUAGE plpgsql;

-- --------------------------------------------------------------------
-- 6. Vista de apoyo: cómo quedó repartida la tabla
-- --------------------------------------------------------------------
CREATE OR REPLACE VIEW v_particiones_notificaciones AS
SELECT c.relname AS particion,
       pg_get_expr(c.relpartbound, c.oid) AS rango,
       COALESCE(t.spcname, '(tablespace por defecto)') AS tablespace,
       (SELECT COUNT(*) FROM notificaciones n WHERE n.tableoid = c.oid) AS filas
FROM pg_inherits i
JOIN pg_class c ON c.oid = i.inhrelid
LEFT JOIN pg_tablespace t ON t.oid = c.reltablespace
WHERE i.inhparent = 'notificaciones'::regclass
ORDER BY c.relname;

-- --------------------------------------------------------------------
-- 7. Permisos para el usuario de la aplicación
-- --------------------------------------------------------------------
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'estudiante') THEN
        GRANT SELECT, INSERT, UPDATE, DELETE ON notificaciones TO estudiante;
        GRANT SELECT ON v_particiones_notificaciones TO estudiante;
        GRANT USAGE, SELECT ON SEQUENCE notificaciones_id_seq TO estudiante;
        GRANT EXECUTE ON FUNCTION trg_notificacion_unica(), trg_notificar_pedido_listo(),
                                  fn_notificar_reservas_proximas(INT) TO estudiante;
    END IF;
END $$;

COMMIT;

SELECT * FROM v_particiones_notificaciones;
