-- ====================================================================
-- Tablespaces del restaurante (requisito técnico 6.1)
--
-- Crea dos espacios de trabajo en directorios distintos del disco:
--   ts_restaurante_actual     datos recientes (notificaciones del mes
--                             anterior en adelante)
--   ts_restaurante_historico  datos antiguos (notificaciones archivadas)
--
-- Los tablespaces son objetos de todo el servidor (no de una base de
-- datos), así que este script lo ejecuta un superusuario y FUERA de una
-- transacción (CREATE TABLESPACE no admite BEGIN/COMMIT).
--
-- Los directorios deben existir, estar vacíos y pertenecer al usuario
-- del sistema operativo que ejecuta PostgreSQL (postgres). En Linux:
--
--   sudo mkdir -p /var/lib/pgsql/tablespaces/restaurante_actual \
--                 /var/lib/pgsql/tablespaces/restaurante_historico
--   sudo chown -R postgres:postgres /var/lib/pgsql/tablespaces
--
-- Otra carpeta base se indica con la variable ts_dir:
--   psql -U postgres -v ts_dir=/otra/ruta -f sql/instalar.sql
--
-- Es idempotente: si los tablespaces ya existen no hace nada.
-- ====================================================================

\if :{?ts_dir}
\else
    \set ts_dir /var/lib/pgsql/tablespaces
\endif
\set ts_actual :ts_dir /restaurante_actual
\set ts_historico :ts_dir /restaurante_historico

\echo 'Tablespace actual:   ' :ts_actual
\echo 'Tablespace histórico:' :ts_historico

SELECT format('CREATE TABLESPACE ts_restaurante_actual LOCATION %L', :'ts_actual')
WHERE NOT EXISTS (SELECT 1 FROM pg_tablespace WHERE spcname = 'ts_restaurante_actual') \gexec

SELECT format('CREATE TABLESPACE ts_restaurante_historico LOCATION %L', :'ts_historico')
WHERE NOT EXISTS (SELECT 1 FROM pg_tablespace WHERE spcname = 'ts_restaurante_historico') \gexec

COMMENT ON TABLESPACE ts_restaurante_actual IS 'Restaurante: datos recientes (particiones del mes anterior en adelante)';
COMMENT ON TABLESPACE ts_restaurante_historico IS 'Restaurante: datos antiguos (particiones archivadas)';

-- El usuario de la aplicación puede crear objetos en ellos
SELECT 'GRANT CREATE ON TABLESPACE ts_restaurante_actual, ts_restaurante_historico TO estudiante'
WHERE EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'estudiante') \gexec

SELECT spcname AS tablespace, pg_tablespace_location(oid) AS directorio
FROM pg_tablespace
WHERE spcname LIKE 'ts_restaurante%'
ORDER BY spcname;
