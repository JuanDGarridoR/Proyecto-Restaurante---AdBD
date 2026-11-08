-- ====================================================================
-- Script de Migración: Integridad, seguridad y gestión de empleados/menú
-- Base de datos: PostgreSQL (restaurante)
--
-- Debe ejecutarse DESPUÉS de:
--   restaurante_llena.sql, migracion_cocineros.sql,
--   migracion_notificaciones.sql y migracion_reportes.sql
--
-- Lleva a la base de datos (y no solo a la aplicación) las reglas del
-- enunciado:
--   * Las reservaciones no se cruzan en la misma mesa.
--   * No se supera el cupo del restaurante en ningún horario
--     (ocupación estimada de 2 horas por reserva).
--   * La mesa asignada tiene sillas suficientes.
--   * Los platos especiales solo se autorizan a cocineros con rol Chef.
--   * Solo se prepara un plato si un cocinero autorizado lo tomó, el
--     estado de un plato nunca retrocede y solo se entrega lo preparado.
--   * Los pedidos los registra un usuario con rol Mesero.
--   * Las claves se guardan como hash SHA-256 con sal.
-- Es idempotente: puede ejecutarse varias veces.
-- ====================================================================

BEGIN;

SET search_path = public;

-- Agrega una restricción solo si aún no existe (idempotencia)
CREATE OR REPLACE FUNCTION pg_temp.agregar_restriccion(p_tabla TEXT, p_nombre TEXT, p_definicion TEXT)
RETURNS void AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = p_nombre) THEN
        EXECUTE format('ALTER TABLE %I ADD CONSTRAINT %I %s', p_tabla, p_nombre, p_definicion);
    END IF;
END;
$$ LANGUAGE plpgsql;

-- ====================================================================
-- 1. Roles y actuaciones
-- ====================================================================

-- Unifica roles repetidos (p. ej. 'Maitre' insertado dos veces)
UPDATE actuaciones a
SET rol_id = d.conservar_id
FROM (SELECT id, MIN(id) OVER (PARTITION BY nombre) AS conservar_id FROM roles) d
WHERE a.rol_id = d.id AND d.id <> d.conservar_id;

DELETE FROM roles r USING roles k
WHERE r.nombre = k.nombre AND r.id > k.id;

ALTER TABLE roles ALTER COLUMN nombre SET NOT NULL;
SELECT pg_temp.agregar_restriccion('roles', 'uq_roles_nombre', 'UNIQUE (nombre)');

INSERT INTO roles (nombre) VALUES
    ('Administrador'), ('Maitre'), ('Mesero'), ('Cocinero'), ('Chef'), ('Cliente')
ON CONFLICT (nombre) DO NOTHING;

-- Una misma persona no repite un rol
DELETE FROM actuaciones a USING actuaciones b
WHERE a.usuario_id = b.usuario_id AND a.rol_id = b.rol_id AND a.id > b.id;
DELETE FROM actuaciones WHERE usuario_id IS NULL OR rol_id IS NULL;

ALTER TABLE actuaciones ALTER COLUMN usuario_id SET NOT NULL;
ALTER TABLE actuaciones ALTER COLUMN rol_id SET NOT NULL;
SELECT pg_temp.agregar_restriccion('actuaciones', 'uq_actuaciones_usuario_rol', 'UNIQUE (usuario_id, rol_id)');

-- Sofia Martinez es la chef principal (puede preparar platos especiales)
INSERT INTO actuaciones (rol_id, usuario_id)
SELECT r.id, u.id
FROM roles r, usuarios u
WHERE r.nombre = 'Chef' AND u.nombre = 'Sofia Martinez'
ON CONFLICT DO NOTHING;

-- Los usuarios sin ningún rol son clientes
INSERT INTO actuaciones (rol_id, usuario_id)
SELECT (SELECT id FROM roles WHERE nombre = 'Cliente'), u.id
FROM usuarios u
WHERE NOT EXISTS (SELECT 1 FROM actuaciones a WHERE a.usuario_id = u.id);

-- ¿El usuario tiene alguno de los roles indicados?
CREATE OR REPLACE FUNCTION fn_tiene_rol(p_usuario_id INT, VARIADIC p_roles TEXT[])
RETURNS BOOLEAN AS $$
    SELECT EXISTS (
        SELECT 1
        FROM actuaciones a
        JOIN roles r ON r.id = a.rol_id
        WHERE a.usuario_id = p_usuario_id
          AND r.nombre = ANY (p_roles)
    );
$$ LANGUAGE sql STABLE;

-- ====================================================================
-- 2. Usuarios: login, estado y claves con hash
-- ====================================================================

ALTER TABLE usuarios ADD COLUMN IF NOT EXISTS documento VARCHAR(50);
ALTER TABLE usuarios ADD COLUMN IF NOT EXISTS login TEXT;
ALTER TABLE usuarios ADD COLUMN IF NOT EXISTS telefono VARCHAR(30);
ALTER TABLE usuarios ADD COLUMN IF NOT EXISTS activo BOOLEAN NOT NULL DEFAULT TRUE;
ALTER TABLE usuarios ADD COLUMN IF NOT EXISTS sal TEXT;
ALTER TABLE usuarios ALTER COLUMN nombre SET NOT NULL;

-- Login inicial: primer nombre en minúsculas y sin tildes (ana, carlos, ...)
-- Solo para empleados; los clientes no inician sesión.
WITH base AS (
    SELECT u.id,
           lower(translate(split_part(u.nombre, ' ', 1), 'ÁÉÍÓÚÜÑáéíóúüñ', 'AEIOUUNaeiouun')) AS login_base
    FROM usuarios u
    WHERE u.login IS NULL
      AND u.clave IS NOT NULL
      AND fn_tiene_rol(u.id, 'Administrador', 'Gerente', 'Maitre', 'Recepcionista', 'Mesero', 'Cocinero')
), numerados AS (
    SELECT id, login_base,
           ROW_NUMBER() OVER (PARTITION BY login_base ORDER BY id) AS n
    FROM base
)
UPDATE usuarios u
SET login = CASE WHEN n.n = 1 AND NOT EXISTS (SELECT 1 FROM usuarios o WHERE o.login = n.login_base)
                 THEN n.login_base
                 ELSE n.login_base || u.id END
FROM numerados n
WHERE n.id = u.id;

CREATE UNIQUE INDEX IF NOT EXISTS uq_usuarios_login ON usuarios (lower(login));
CREATE UNIQUE INDEX IF NOT EXISTS uq_usuarios_documento ON usuarios (documento) WHERE documento IS NOT NULL;

-- Las claves existentes estaban guardadas en texto plano (bytea). Se
-- reemplazan por sha256(sal || clave). Solo se convierten las filas que
-- aún no tienen sal, así que el script puede repetirse sin dañarlas.
UPDATE usuarios
SET sal = gen_random_uuid()::text
WHERE sal IS NULL AND clave IS NOT NULL;

UPDATE usuarios
SET clave = sha256(convert_to(sal, 'UTF8') || clave)
WHERE clave IS NOT NULL
  AND length(clave) <> 32;          -- un hash SHA-256 siempre mide 32 bytes

CREATE OR REPLACE FUNCTION fn_hash_clave(p_sal TEXT, p_clave TEXT)
RETURNS BYTEA AS $$
    SELECT sha256(convert_to(p_sal || p_clave, 'UTF8'));
$$ LANGUAGE sql IMMUTABLE;

-- Asigna una clave nueva a un usuario (genera sal nueva)
CREATE OR REPLACE FUNCTION fn_establecer_clave(p_usuario_id INT, p_clave TEXT)
RETURNS void AS $$
DECLARE
    v_sal TEXT := gen_random_uuid()::text;
BEGIN
    IF p_clave IS NULL OR length(p_clave) < 6 THEN
        RAISE EXCEPTION 'La clave debe tener al menos 6 caracteres';
    END IF;
    UPDATE usuarios
    SET sal = v_sal,
        clave = fn_hash_clave(v_sal, p_clave),
        fecha_clave = LOCALTIMESTAMP
    WHERE id = p_usuario_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'El usuario % no existe', p_usuario_id;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Devuelve el id del usuario si el login y la clave son correctos y
-- el usuario está activo; NULL en otro caso.
CREATE OR REPLACE FUNCTION fn_autenticar(p_login TEXT, p_clave TEXT)
RETURNS INT AS $$
    SELECT u.id
    FROM usuarios u
    WHERE lower(u.login) = lower(trim(p_login))
      AND u.activo
      AND u.clave IS NOT NULL
      AND u.clave = fn_hash_clave(u.sal, p_clave);
$$ LANGUAGE sql STABLE;

-- ====================================================================
-- 3. Mesas, categorías y platos
-- ====================================================================

ALTER TABLE mesas ALTER COLUMN sillas SET NOT NULL;
SELECT pg_temp.agregar_restriccion('mesas', 'ck_mesas_sillas', 'CHECK (sillas > 0)');

ALTER TABLE tipos ALTER COLUMN nombre SET NOT NULL;
SELECT pg_temp.agregar_restriccion('tipos', 'uq_tipos_nombre', 'UNIQUE (nombre)');

ALTER TABLE platos ADD COLUMN IF NOT EXISTS es_especial BOOLEAN DEFAULT FALSE;
ALTER TABLE platos ADD COLUMN IF NOT EXISTS activo BOOLEAN NOT NULL DEFAULT TRUE;
UPDATE platos SET es_especial = FALSE WHERE es_especial IS NULL;
UPDATE platos SET tiempo = INTERVAL '15 minutes' WHERE tiempo IS NULL;
ALTER TABLE platos ALTER COLUMN es_especial SET NOT NULL;
ALTER TABLE platos ALTER COLUMN nombre SET NOT NULL;
ALTER TABLE platos ALTER COLUMN precio SET NOT NULL;
ALTER TABLE platos ALTER COLUMN tiempo SET NOT NULL;
ALTER TABLE platos ALTER COLUMN tipo_id SET NOT NULL;
SELECT pg_temp.agregar_restriccion('platos', 'ck_platos_precio', 'CHECK (precio > 0)');
SELECT pg_temp.agregar_restriccion('platos', 'ck_platos_tiempo', 'CHECK (tiempo > INTERVAL ''0'')');
CREATE UNIQUE INDEX IF NOT EXISTS uq_platos_nombre_activo ON platos (lower(nombre)) WHERE activo;

-- Cupo total del restaurante = suma de sillas de todas las mesas
CREATE OR REPLACE FUNCTION fn_cupo_total()
RETURNS INT AS $$
    SELECT COALESCE(SUM(sillas), 0)::int FROM mesas;
$$ LANGUAGE sql STABLE;

CREATE OR REPLACE VIEW v_cupo_restaurante AS
SELECT COUNT(*)::int AS mesas,
       COALESCE(SUM(sillas), 0)::int AS cupo_total
FROM mesas;

-- ====================================================================
-- 4. Autorizaciones de cocina: solo cocineros, y los platos especiales
--    solo para cocineros con rol Chef
-- ====================================================================

CREATE OR REPLACE FUNCTION trg_validar_autorizacion()
RETURNS trigger AS $$
DECLARE
    v_especial BOOLEAN;
    v_plato TEXT;
BEGIN
    IF NOT fn_tiene_rol(NEW.cocinero_id, 'Cocinero') THEN
        RAISE EXCEPTION 'El usuario % no tiene el rol Cocinero', NEW.cocinero_id;
    END IF;

    SELECT es_especial, nombre INTO v_especial, v_plato FROM platos WHERE id = NEW.plato_id;
    IF v_especial AND NOT fn_tiene_rol(NEW.cocinero_id, 'Chef') THEN
        RAISE EXCEPTION 'El plato «%» es especial: solo se autoriza a cocineros con rol Chef', v_plato;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_autorizacion_valida ON autorizaciones;
CREATE TRIGGER trg_autorizacion_valida
BEFORE INSERT OR UPDATE ON autorizaciones
FOR EACH ROW EXECUTE FUNCTION trg_validar_autorizacion();

-- Si un plato pasa a ser especial, no puede quedar autorizado a quien no es Chef
CREATE OR REPLACE FUNCTION trg_plato_especial()
RETURNS trigger AS $$
DECLARE
    v_cocineros TEXT;
BEGIN
    IF NEW.es_especial AND NOT OLD.es_especial THEN
        SELECT string_agg(u.nombre, ', ' ORDER BY u.nombre) INTO v_cocineros
        FROM autorizaciones a
        JOIN usuarios u ON u.id = a.cocinero_id
        WHERE a.plato_id = NEW.id AND NOT fn_tiene_rol(a.cocinero_id, 'Chef');
        IF v_cocineros IS NOT NULL THEN
            RAISE EXCEPTION 'No se puede marcar «%» como especial: está autorizado a cocineros que no son Chef (%). Revoque primero esas autorizaciones', NEW.nombre, v_cocineros;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_plato_especial ON platos;
CREATE TRIGGER trg_plato_especial
BEFORE UPDATE OF es_especial ON platos
FOR EACH ROW EXECUTE FUNCTION trg_plato_especial();

-- Al quitar el rol Chef se revocan las autorizaciones de platos especiales;
-- al quitar el rol Cocinero, todas.
CREATE OR REPLACE FUNCTION trg_actuacion_eliminada()
RETURNS trigger AS $$
DECLARE
    v_rol TEXT;
BEGIN
    SELECT nombre INTO v_rol FROM roles WHERE id = OLD.rol_id;
    IF v_rol = 'Cocinero' THEN
        DELETE FROM autorizaciones WHERE cocinero_id = OLD.usuario_id;
    ELSIF v_rol = 'Chef' THEN
        DELETE FROM autorizaciones a USING platos p
        WHERE p.id = a.plato_id AND p.es_especial AND a.cocinero_id = OLD.usuario_id;
    END IF;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_actuacion_eliminada ON actuaciones;
CREATE TRIGGER trg_actuacion_eliminada
AFTER DELETE ON actuaciones
FOR EACH ROW EXECUTE FUNCTION trg_actuacion_eliminada();

-- ====================================================================
-- 5. Pedidos y órdenes
-- ====================================================================

ALTER TABLE pedidos ADD COLUMN IF NOT EXISTS mesa_id INT REFERENCES mesas(id);
ALTER TABLE ordenes ADD COLUMN IF NOT EXISTS precio NUMERIC;
ALTER TABLE ordenes ADD COLUMN IF NOT EXISTS hora_entregado TIMESTAMP WITH TIME ZONE;

UPDATE ordenes o SET precio = p.precio FROM platos p WHERE p.id = o.plato_id AND o.precio IS NULL;
UPDATE ordenes SET estado = 1 WHERE estado IS NULL;
UPDATE ordenes SET solicitado = CURRENT_TIMESTAMP WHERE solicitado IS NULL;

ALTER TABLE ordenes ALTER COLUMN estado SET DEFAULT 1;
ALTER TABLE ordenes ALTER COLUMN estado SET NOT NULL;
ALTER TABLE ordenes ALTER COLUMN solicitado SET DEFAULT CURRENT_TIMESTAMP;
ALTER TABLE ordenes ALTER COLUMN solicitado SET NOT NULL;
ALTER TABLE ordenes ALTER COLUMN cantidad SET NOT NULL;
ALTER TABLE ordenes ALTER COLUMN plato_id SET NOT NULL;
ALTER TABLE ordenes ALTER COLUMN pedido_id SET NOT NULL;
SELECT pg_temp.agregar_restriccion('ordenes', 'ck_ordenes_estado', 'CHECK (estado IN (1, 2, 3))');
SELECT pg_temp.agregar_restriccion('ordenes', 'ck_ordenes_precio', 'CHECK (precio IS NULL OR precio >= 0)');

-- Estados de un plato del pedido: 1 En preparación, 2 Preparado, 3 Entregado
CREATE OR REPLACE FUNCTION trg_orden_nueva()
RETURNS trigger AS $$
DECLARE
    v_activo BOOLEAN;
    v_precio NUMERIC;
    v_nombre TEXT;
BEGIN
    SELECT activo, precio, nombre INTO v_activo, v_precio, v_nombre FROM platos WHERE id = NEW.plato_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'El plato % no existe', NEW.plato_id;
    END IF;
    IF NOT v_activo THEN
        RAISE EXCEPTION 'El plato «%» ya no está en el menú', v_nombre;
    END IF;
    -- El precio queda congelado al momento del pedido
    NEW.precio := COALESCE(NEW.precio, v_precio);
    NEW.estado := COALESCE(NEW.estado, 1);
    NEW.solicitado := COALESCE(NEW.solicitado, CURRENT_TIMESTAMP);
    IF NEW.estado <> 1 AND TG_OP = 'INSERT' AND current_setting('restaurante.carga_historica', true) IS DISTINCT FROM 'on' THEN
        RAISE EXCEPTION 'Un plato nuevo debe quedar «En preparación»';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_orden_nueva ON ordenes;
CREATE TRIGGER trg_orden_nueva
BEFORE INSERT ON ordenes
FOR EACH ROW EXECUTE FUNCTION trg_orden_nueva();

CREATE OR REPLACE FUNCTION trg_orden_estado()
RETURNS trigger AS $$
BEGIN
    IF NEW.estado = OLD.estado THEN
        RETURN NEW;
    END IF;
    IF NEW.estado < OLD.estado THEN
        RAISE EXCEPTION 'El estado de la orden % no puede retroceder', OLD.id;
    END IF;
    IF NEW.estado = 2 THEN
        IF NEW.cocinero_id IS NULL THEN
            RAISE EXCEPTION 'La orden % no puede quedar «Preparado»: ningún cocinero autorizado la ha tomado', OLD.id;
        END IF;
        NEW.hora_terminado := COALESCE(NEW.hora_terminado, CURRENT_TIMESTAMP);
    ELSIF NEW.estado = 3 THEN
        IF OLD.estado <> 2 THEN
            RAISE EXCEPTION 'La orden % aún no está preparada: solo se entregan platos preparados', OLD.id;
        END IF;
        NEW.hora_entregado := COALESCE(NEW.hora_entregado, CURRENT_TIMESTAMP);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_orden_estado ON ordenes;
CREATE TRIGGER trg_orden_estado
BEFORE UPDATE OF estado ON ordenes
FOR EACH ROW EXECUTE FUNCTION trg_orden_estado();

-- El pedido lo registra un mesero
CREATE OR REPLACE FUNCTION trg_pedido_mesero()
RETURNS trigger AS $$
BEGIN
    IF NEW.mesero_id IS NULL OR NOT fn_tiene_rol(NEW.mesero_id, 'Mesero') THEN
        RAISE EXCEPTION 'El pedido debe registrarlo un usuario con rol Mesero';
    END IF;
    IF NEW.cliente_id IS NULL THEN
        RAISE EXCEPTION 'El pedido debe estar asociado a un cliente';
    END IF;
    IF TG_OP = 'INSERT' AND NEW.mesa_id IS NULL THEN
        RAISE EXCEPTION 'El pedido debe estar asociado a una mesa';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_pedido_mesero ON pedidos;
CREATE TRIGGER trg_pedido_mesero
BEFORE INSERT OR UPDATE OF mesero_id, cliente_id, mesa_id ON pedidos
FOR EACH ROW EXECUTE FUNCTION trg_pedido_mesero();

-- Estado de cada pedido = estado del plato menos avanzado
CREATE OR REPLACE VIEW v_pedidos AS
SELECT p.id AS pedido_id,
       p.mesa_id,
       p.cliente_id,
       c.nombre AS cliente,
       p.mesero_id,
       m.nombre AS mesero,
       MIN(o.solicitado) AS solicitado,
       MIN(o.estado) AS estado,
       COALESCE(SUM(o.cantidad), 0)::int AS platos,
       COUNT(o.id) FILTER (WHERE o.estado = 1)::int AS platos_en_preparacion,
       COALESCE(SUM(o.cantidad * COALESCE(o.precio, pl.precio)), 0) AS total
FROM pedidos p
LEFT JOIN usuarios c ON c.id = p.cliente_id
LEFT JOIN usuarios m ON m.id = p.mesero_id
LEFT JOIN ordenes o ON o.pedido_id = p.id
LEFT JOIN platos pl ON pl.id = o.plato_id
GROUP BY p.id, c.nombre, m.nombre;

-- ====================================================================
-- 6. Reservaciones: sin cruces en la misma mesa y sin superar el cupo
-- ====================================================================

-- Estados: 0 Cancelada, 1 Activa, 2 Cumplida, 3 No asistió
UPDATE reservaciones SET estado = 1 WHERE estado IS NULL;
ALTER TABLE reservaciones ALTER COLUMN estado SET DEFAULT 1;
ALTER TABLE reservaciones ALTER COLUMN estado SET NOT NULL;
ALTER TABLE reservaciones ALTER COLUMN cantidad SET NOT NULL;
ALTER TABLE reservaciones ALTER COLUMN cliente_id SET NOT NULL;
SELECT pg_temp.agregar_restriccion('reservaciones', 'ck_reservaciones_estado', 'CHECK (estado IN (0, 1, 2, 3))');

UPDATE horarios SET duracion = INTERVAL '2 hours' WHERE duracion IS NULL;
ALTER TABLE horarios ALTER COLUMN duracion SET DEFAULT INTERVAL '2 hours';
ALTER TABLE horarios ALTER COLUMN duracion SET NOT NULL;
ALTER TABLE horarios ALTER COLUMN mesa_id SET NOT NULL;
ALTER TABLE horarios ALTER COLUMN reservacion_id SET NOT NULL;
ALTER TABLE horarios ALTER COLUMN inicio SET NOT NULL;
SELECT pg_temp.agregar_restriccion('horarios', 'ck_horarios_duracion', 'CHECK (duracion > INTERVAL ''0'')');

-- Índice GiST sobre el intervalo ocupado para buscar cruces rápidamente
CREATE INDEX IF NOT EXISTS idx_horarios_rango
    ON horarios USING gist (tsrange(inicio, inicio + duracion, '[)'));

-- Valida una reservación. Se usa desde los triggers de horarios,
-- reservaciones y mesas. Lanza una excepción si:
--   a) las mesas asignadas no tienen sillas suficientes,
--   b) alguna mesa ya está ocupada en ese horario por otra reserva activa,
--   c) en algún momento del intervalo se superaría el cupo del restaurante.
CREATE OR REPLACE FUNCTION fn_validar_reservacion(p_reservacion_id INT)
RETURNS void AS $$
DECLARE
    v_estado INT;
    v_cantidad INT;
    v_sillas INT;
    v_cupo INT;
    h RECORD;
    v_cruce RECORD;
    v_pico RECORD;
BEGIN
    SELECT estado, cantidad INTO v_estado, v_cantidad
    FROM reservaciones WHERE id = p_reservacion_id;
    IF NOT FOUND OR v_estado = 0 THEN
        RETURN;                     -- las canceladas no ocupan mesas
    END IF;

    -- Serializa la validación de reservaciones concurrentes
    PERFORM pg_advisory_xact_lock(hashtext('restaurante.reservaciones'));

    -- a) Sillas suficientes en las mesas asignadas
    SELECT SUM(m.sillas) INTO v_sillas
    FROM horarios h2 JOIN mesas m ON m.id = h2.mesa_id
    WHERE h2.reservacion_id = p_reservacion_id;
    IF v_sillas IS NULL THEN
        RETURN;                     -- aún sin mesa asignada
    END IF;
    IF v_cantidad > v_sillas THEN
        RAISE EXCEPTION 'La reservación % es para % personas y las mesas asignadas solo tienen % sillas',
            p_reservacion_id, v_cantidad, v_sillas;
    END IF;

    v_cupo := fn_cupo_total();

    FOR h IN
        SELECT mesa_id, inicio, inicio + duracion AS fin,
               tsrange(inicio, inicio + duracion, '[)') AS rango
        FROM horarios WHERE reservacion_id = p_reservacion_id
    LOOP
        -- b) La misma mesa no puede estar en dos reservas activas a la vez
        SELECT o.reservacion_id, o.inicio, o.inicio + o.duracion AS fin INTO v_cruce
        FROM horarios o
        JOIN reservaciones r ON r.id = o.reservacion_id
        WHERE o.mesa_id = h.mesa_id
          AND o.reservacion_id <> p_reservacion_id
          AND r.estado <> 0
          AND tsrange(o.inicio, o.inicio + o.duracion, '[)') && h.rango
        ORDER BY o.inicio
        LIMIT 1;
        IF FOUND THEN
            RAISE EXCEPTION 'La mesa % ya está reservada de % a % (reservación %)',
                h.mesa_id, to_char(v_cruce.inicio, 'YYYY-MM-DD HH24:MI'),
                to_char(v_cruce.fin, 'HH24:MI'), v_cruce.reservacion_id;
        END IF;

        -- c) Cupo: la ocupación solo crece cuando empieza una reserva, así que
        --    basta revisar el inicio del intervalo y los inicios dentro de él.
        WITH activos AS (
            SELECT DISTINCT r.id, r.cantidad, o.inicio,
                   tsrange(o.inicio, o.inicio + o.duracion, '[)') AS rango
            FROM horarios o
            JOIN reservaciones r ON r.id = o.reservacion_id
            WHERE r.estado <> 0
              AND tsrange(o.inicio, o.inicio + o.duracion, '[)') && h.rango
        ), momentos AS (
            SELECT h.inicio AS momento
            UNION
            SELECT inicio FROM activos WHERE inicio > h.inicio
        )
        SELECT mo.momento,
               (SELECT COALESCE(SUM(x.cantidad), 0)
                FROM (SELECT DISTINCT a.id, a.cantidad FROM activos a WHERE a.rango @> mo.momento) x) AS personas
        INTO v_pico
        FROM momentos mo
        ORDER BY personas DESC, mo.momento
        LIMIT 1;

        IF v_pico.personas > v_cupo THEN
            RAISE EXCEPTION 'Se supera el cupo del restaurante: el % habría % personas y el cupo es de %',
                to_char(v_pico.momento, 'YYYY-MM-DD HH24:MI'), v_pico.personas, v_cupo;
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION trg_horario_valido()
RETURNS trigger AS $$
BEGIN
    PERFORM fn_validar_reservacion(NEW.reservacion_id);
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION trg_reservacion_valida()
RETURNS trigger AS $$
BEGIN
    PERFORM fn_validar_reservacion(NEW.id);
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Al reducir las sillas de una mesa se revalidan sus reservas futuras
CREATE OR REPLACE FUNCTION trg_mesa_sillas()
RETURNS trigger AS $$
DECLARE
    r RECORD;
BEGIN
    IF NEW.sillas < OLD.sillas THEN
        FOR r IN
            SELECT DISTINCT h.reservacion_id
            FROM horarios h JOIN reservaciones res ON res.id = h.reservacion_id
            WHERE h.mesa_id = NEW.id AND res.estado = 1
              AND h.inicio + h.duracion > LOCALTIMESTAMP
        LOOP
            PERFORM fn_validar_reservacion(r.reservacion_id);
        END LOOP;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Triggers de restricción diferibles: se verifican al confirmar la
-- transacción, cuando la reservación ya tiene su cantidad y sus mesas
-- definitivas (por ejemplo, al cambiar a la vez la mesa y las personas).
DROP TRIGGER IF EXISTS trg_horario_valido ON horarios;
CREATE CONSTRAINT TRIGGER trg_horario_valido
AFTER INSERT OR UPDATE ON horarios
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION trg_horario_valido();

DROP TRIGGER IF EXISTS trg_reservacion_valida ON reservaciones;
CREATE CONSTRAINT TRIGGER trg_reservacion_valida
AFTER UPDATE OF cantidad, estado ON reservaciones
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION trg_reservacion_valida();

DROP TRIGGER IF EXISTS trg_mesa_sillas ON mesas;
CREATE CONSTRAINT TRIGGER trg_mesa_sillas
AFTER UPDATE OF sillas ON mesas
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION trg_mesa_sillas();

-- Mesas libres para un horario: sin reservas activas que se crucen con
-- [inicio, inicio + 2 horas) y con sillas suficientes. También informa
-- la ocupación máxima del restaurante en ese intervalo.
CREATE OR REPLACE FUNCTION fn_mesas_disponibles(
    p_inicio TIMESTAMP,
    p_personas INT,
    p_excluir_reservacion INT DEFAULT 0
)
RETURNS TABLE (mesa_id INT, sillas INT) AS $$
    SELECT m.id, m.sillas
    FROM mesas m
    WHERE m.sillas >= p_personas
      AND NOT EXISTS (
          SELECT 1
          FROM horarios h
          JOIN reservaciones r ON r.id = h.reservacion_id
          WHERE h.mesa_id = m.id
            AND r.estado <> 0
            AND h.reservacion_id <> p_excluir_reservacion
            AND tsrange(h.inicio, h.inicio + h.duracion, '[)')
                && tsrange(p_inicio, p_inicio + INTERVAL '2 hours', '[)')
      )
    ORDER BY m.sillas, m.id;
$$ LANGUAGE sql STABLE;

-- Personas con reserva activa en un momento dado
CREATE OR REPLACE FUNCTION fn_ocupacion(p_momento TIMESTAMP)
RETURNS INT AS $$
    SELECT COALESCE(SUM(r.cantidad), 0)::int
    FROM reservaciones r
    WHERE r.estado <> 0
      AND EXISTS (SELECT 1 FROM horarios h
                  WHERE h.reservacion_id = r.id
                    AND tsrange(h.inicio, h.inicio + h.duracion, '[)') @> p_momento);
$$ LANGUAGE sql STABLE;

-- ====================================================================
-- 7. Notificaciones: la vista materializada la refresca el dueño
-- ====================================================================

CREATE OR REPLACE FUNCTION refrescar_ventas_diarias()
RETURNS void AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY vm_ventas_diarias;
EXCEPTION WHEN OTHERS THEN
    REFRESH MATERIALIZED VIEW vm_ventas_diarias;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- ====================================================================
-- 8. Permisos para el usuario de la aplicación (estudiante)
-- ====================================================================

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'estudiante') THEN
        GRANT USAGE ON SCHEMA public TO estudiante;
        GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO estudiante;
        GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO estudiante;
        GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO estudiante;
        GRANT EXECUTE ON ALL PROCEDURES IN SCHEMA public TO estudiante;
        ALTER DEFAULT PRIVILEGES IN SCHEMA public
            GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO estudiante;
        ALTER DEFAULT PRIVILEGES IN SCHEMA public
            GRANT USAGE, SELECT ON SEQUENCES TO estudiante;
    END IF;
END $$;

COMMIT;
