@echo off
rem Instala la base de datos restaurante en Windows.
rem Ejecutar con clic derecho -> "Ejecutar como administrador".
cd /d "%~dp0"
set PSQL="C:\Program Files\PostgreSQL\18\bin\psql.exe"
set HBA=C:\Program Files\PostgreSQL\18\data\pg_hba.conf
set SERVICIO=postgresql-x64-18

echo == 1. Abriendo PostgreSQL temporalmente sin clave
copy /Y "%HBA%" "%HBA%.respaldo" >nul
powershell -NoProfile -Command "$f='%HBA%'; (Get-Content $f) -replace '^((local|host)\s.*\s)(trust-256|scram-sha-256|md5|trust)\s*$', '${1}trust' | Set-Content $f"
net stop %SERVICIO%
net start %SERVICIO%

echo.
echo == 2. Clave de postgres = postgres
%PSQL% -h localhost -U postgres -c "ALTER USER postgres PASSWORD 'postgres';"

echo.
echo == 3. Carpetas de tablespaces
if not exist C:\pg_tablespaces\restaurante_actual mkdir C:\pg_tablespaces\restaurante_actual
if not exist C:\pg_tablespaces\restaurante_historico mkdir C:\pg_tablespaces\restaurante_historico
icacls C:\pg_tablespaces /grant *S-1-5-20:(OI)(CI)F /T

echo.
echo == 4. Creando la base restaurante
%PSQL% -h localhost -U postgres -v ts_dir=C:/pg_tablespaces -f sql/instalar.sql

echo.
echo == 5. Clave de estudiante = estudiante
%PSQL% -h localhost -U postgres -c "ALTER ROLE estudiante PASSWORD 'estudiante';"

echo.
echo == 6. Volviendo a exigir clave
powershell -NoProfile -Command "$f='%HBA%'; (Get-Content $f) -replace '^((local|host)\s.*\s)trust\s*$', '${1}scram-sha-256' | Set-Content $f"
net stop %SERVICIO%
net start %SERVICIO%

echo.
echo Listo. Revise arriba que no haya lineas con ERROR.
pause
