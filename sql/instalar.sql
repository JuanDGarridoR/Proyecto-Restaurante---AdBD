-- ====================================================================
-- Instalación completa de la base de datos del restaurante
--
-- Uso (como superusuario, desde la carpeta del proyecto):
--     psql -U postgres -f sql/instalar.sql
--
-- Antes de ejecutarlo deben existir los directorios de los tablespaces
-- (ver sql/tablespaces.sql). En Linux:
--     sudo mkdir -p /var/lib/pgsql/tablespaces/restaurante_actual \
--                   /var/lib/pgsql/tablespaces/restaurante_historico
--     sudo chown -R postgres:postgres /var/lib/pgsql/tablespaces
-- Para usar otra carpeta base:
--     psql -U postgres -v ts_dir=/otra/ruta -f sql/instalar.sql
--
-- Crea el rol de la aplicación (estudiante), los tablespaces y la base
-- de datos restaurante, y carga en orden:
--   0. tablespaces.sql                ts_restaurante_actual / _historico
--   1. restaurante_llena.sql          estructura y datos base
--   2. migracion_cocineros.sql        autorizaciones y cola de cocina
--   3. migracion_notificaciones.sql   notificaciones a meseros y maitres
--   4. migracion_reportes.sql         reportes, historial y 60 días de datos
--   5. migracion_integridad.sql       reglas de negocio en la BD, login y permisos
--   6. migracion_particiones.sql      notificaciones particionada por fecha
--
-- Si la base de datos restaurante ya existe, el script se detiene sin
-- modificarla. Para reinstalar: DROP DATABASE restaurante WITH (FORCE);
-- ====================================================================

\set ON_ERROR_STOP on

SELECT 'CREATE ROLE estudiante LOGIN'
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'estudiante') \gexec

SELECT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'restaurante') AS ya_existe \gset
\if :ya_existe
    \echo 'La base de datos restaurante ya existe. Bórrela (DROP DATABASE restaurante WITH (FORCE);) para reinstalar.'
    \quit
\endif

-- Los tablespaces se crean antes que la base: si falta un directorio,
-- la instalación se detiene aquí sin dejar una base a medio crear
\echo '== 0/6 Tablespaces'
\ir tablespaces.sql

CREATE DATABASE restaurante ENCODING 'UTF8' TEMPLATE template0;
\connect restaurante

\echo '== 1/6 Estructura y datos base'
\ir restaurante_llena.sql
-- El volcado deja vacío el search_path; se restablece para las migraciones
SET search_path = public;
SET client_min_messages = warning;

\echo '== 2/6 Cocineros'
\ir migracion_cocineros.sql
SET search_path = public;

\echo '== 3/6 Notificaciones'
\ir migracion_notificaciones.sql
SET search_path = public;

\echo '== 4/6 Reportes'
\ir migracion_reportes.sql
SET search_path = public;

\echo '== 5/6 Integridad, login y permisos'
\ir migracion_integridad.sql
SET search_path = public;

\echo '== 6/6 Partición de notificaciones en los tablespaces'
\ir migracion_particiones.sql

\echo 'Instalación terminada. Ingrese a la aplicación con usuario ana y clave clave_ana_2026 (Administrador).'
