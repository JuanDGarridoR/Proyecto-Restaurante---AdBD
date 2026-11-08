-- ====================================================================
-- Instalación completa de la base de datos del restaurante
--
-- Uso (como superusuario, desde cualquier carpeta):
--     psql -U postgres -f sql/instalar.sql
--
-- Crea el rol de la aplicación (estudiante) y la base de datos
-- restaurante, y carga en orden:
--   1. restaurante_llena.sql          estructura y datos base
--   2. migracion_cocineros.sql        autorizaciones y cola de cocina
--   3. migracion_notificaciones.sql   notificaciones a meseros y maitres
--   4. migracion_reportes.sql         reportes, historial y 60 días de datos
--   5. migracion_integridad.sql       reglas de negocio en la BD, login y permisos
--
-- Si la base de datos restaurante ya existe, el script se detiene sin
-- modificarla. Para reinstalar: DROP DATABASE restaurante;
-- ====================================================================

\set ON_ERROR_STOP on

SELECT 'CREATE ROLE estudiante LOGIN'
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'estudiante') \gexec

SELECT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'restaurante') AS ya_existe \gset
\if :ya_existe
    \echo 'La base de datos restaurante ya existe. Bórrela (DROP DATABASE restaurante;) para reinstalar.'
    \quit
\endif

CREATE DATABASE restaurante ENCODING 'UTF8' TEMPLATE template0;
\connect restaurante

\echo '== 1/5 Estructura y datos base'
\ir restaurante_llena.sql
-- El volcado deja vacío el search_path; se restablece para las migraciones
SET search_path = public;
SET client_min_messages = warning;

\echo '== 2/5 Cocineros'
\ir migracion_cocineros.sql
SET search_path = public;

\echo '== 3/5 Notificaciones'
\ir migracion_notificaciones.sql
SET search_path = public;

\echo '== 4/5 Reportes'
\ir migracion_reportes.sql
SET search_path = public;

\echo '== 5/5 Integridad, login y permisos'
\ir migracion_integridad.sql

\echo 'Instalación terminada. Ingrese a la aplicación con usuario ana y clave clave_ana_2026 (Administrador).'
