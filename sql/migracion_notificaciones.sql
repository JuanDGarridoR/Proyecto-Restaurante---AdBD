-- ====================================================================
-- Script de Migración: Sistema de Notificaciones
-- Base de datos: PostgreSQL (restaurante)
-- ====================================================================

BEGIN;

-- 1. Rol Maitre (en caso de que no exista) y asignación
INSERT INTO roles (nombre) VALUES ('Maitre') ON CONFLICT DO NOTHING;

-- Asegurar que Valentina Rojas (id 7) tenga el rol de Maitre además de Recepcionista
INSERT INTO actuaciones (rol_id, usuario_id)
SELECT r.id, 7
FROM roles r
WHERE r.nombre = 'Maitre'
  AND NOT EXISTS (
      SELECT 1 FROM actuaciones a WHERE a.usuario_id = 7 AND a.rol_id = r.id
  );

-- 2. Tabla de notificaciones
CREATE TABLE IF NOT EXISTS notificaciones (
    id SERIAL PRIMARY KEY,
    destinatario_id INT NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
    tipo VARCHAR(50) NOT NULL CHECK (tipo IN ('PEDIDO_LISTO', 'RESERVA_PROXIMA')),
    referencia_id INT NOT NULL,
    mensaje TEXT NOT NULL,
    fecha_creacion TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    leida BOOLEAN NOT NULL DEFAULT FALSE,
    fecha_lectura TIMESTAMP WITH TIME ZONE,
    CONSTRAINT uq_notificacion_unica UNIQUE (tipo, referencia_id, destinatario_id)
);

CREATE INDEX IF NOT EXISTS idx_notif_destinatario_leida ON notificaciones(destinatario_id, leida);

-- 3. Trigger: Pedido listo -> mesero
-- Cuando TODOS los ítems de un pedido queden en "Preparado" (estado = 2 o superior),
-- genera una notificación al mesero que registró el pedido.
-- No genera duplicados si el trigger se dispara más de una vez.
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
        -- Contar total de ítems e ítems preparados
        SELECT 
            COUNT(*),
            COUNT(*) FILTER (WHERE estado >= 2)
        INTO 
            v_total_items,
            v_items_preparados
        FROM ordenes
        WHERE pedido_id = NEW.pedido_id;

        -- Solo si todos los ítems del pedido ya están en estado Preparado (o superior)
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

                -- Inserción segura contra duplicados
                INSERT INTO notificaciones (destinatario_id, tipo, referencia_id, mensaje, fecha_creacion, leida)
                VALUES (v_mesero_id, 'PEDIDO_LISTO', NEW.pedido_id, v_mensaje, CURRENT_TIMESTAMP, FALSE)
                ON CONFLICT (tipo, referencia_id, destinatario_id) DO NOTHING
                RETURNING id INTO v_notif_id;

                -- Notificación en tiempo real vía pg_notify
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

DROP TRIGGER IF EXISTS trg_check_pedido_listo ON ordenes;
CREATE TRIGGER trg_check_pedido_listo
AFTER INSERT OR UPDATE OF estado ON ordenes
FOR EACH ROW
EXECUTE FUNCTION trg_notificar_pedido_listo();

-- 4. Trigger: Pedido entregado -> marcar notificación como leída automáticamente
CREATE OR REPLACE FUNCTION trg_pedido_entregado_marcar_leida()
RETURNS trigger AS $$
DECLARE
    v_total_items INT;
    v_items_entregados INT;
BEGIN
    IF NEW.estado = 3 THEN
        SELECT COUNT(*), COUNT(*) FILTER (WHERE estado = 3)
        INTO v_total_items, v_items_entregados
        FROM ordenes
        WHERE pedido_id = NEW.pedido_id;

        IF v_total_items > 0 AND v_total_items = v_items_entregados THEN
            UPDATE notificaciones
            SET leida = TRUE,
                fecha_lectura = CURRENT_TIMESTAMP
            WHERE tipo = 'PEDIDO_LISTO'
              AND referencia_id = NEW.pedido_id
              AND NOT leida;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_check_pedido_entregado ON ordenes;
CREATE TRIGGER trg_check_pedido_entregado
AFTER INSERT OR UPDATE OF estado ON ordenes
FOR EACH ROW
EXECUTE FUNCTION trg_pedido_entregado_marcar_leida();

-- 5. Función / Procedimiento: Reserva próxima -> maitre
-- Genera notificaciones para reservaciones activas que empiezan en los próximos N minutos (default 30).
-- Evita duplicados con ON CONFLICT y emite pg_notify en tiempo real.
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
        SELECT 
            res.id AS reservacion_id,
            h.mesa_id,
            h.inicio,
            res.cantidad,
            COALESCE(u.nombre, 'Cliente') AS cliente_nombre,
            ROUND(EXTRACT(EPOCH FROM (h.inicio - CURRENT_TIMESTAMP))/60) AS minutos_faltantes
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

            INSERT INTO notificaciones (destinatario_id, tipo, referencia_id, mensaje, fecha_creacion, leida)
            VALUES (m.maitre_id, 'RESERVA_PROXIMA', r.reservacion_id, v_mensaje, CURRENT_TIMESTAMP, FALSE)
            ON CONFLICT (tipo, referencia_id, destinatario_id) DO NOTHING
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

-- 6. Procedimientos para listar notificaciones no leídas y marcarlas como leídas
CREATE OR REPLACE FUNCTION listar_notificaciones_no_leidas(p_empleado_id INT)
RETURNS TABLE (
    notificacion_id INT,
    tipo VARCHAR(50),
    referencia_id INT,
    mensaje TEXT,
    fecha_creacion TIMESTAMP WITH TIME ZONE,
    leida BOOLEAN,
    fecha_lectura TIMESTAMP WITH TIME ZONE
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        n.id AS notificacion_id,
        n.tipo,
        n.referencia_id,
        n.mensaje,
        n.fecha_creacion,
        n.leida,
        n.fecha_lectura
    FROM notificaciones n
    WHERE n.destinatario_id = p_empleado_id
      AND NOT n.leida
    ORDER BY n.fecha_creacion DESC;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION marcar_notificacion_leida(p_notificacion_id INT)
RETURNS void AS $$
BEGIN
    UPDATE notificaciones
    SET leida = TRUE,
        fecha_lectura = CURRENT_TIMESTAMP
    WHERE id = p_notificacion_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE pr_marcar_notificacion_leida(p_notificacion_id INT)
AS $$
BEGIN
    PERFORM marcar_notificacion_leida(p_notificacion_id);
END;
$$ LANGUAGE plpgsql;

COMMIT;
