# Restaurante: Bases de datos, administración y aplicaciones

Sistema para gestionar las mesas, reservaciones, menú, pedidos, cocina y entregas de un restaurante.
Está hecho en PostgreSQL y PHP (sin frameworks).

Las reglas del enunciado se validan **en la base de datos** con restricciones, triggers y funciones,
no solo en la aplicación. Si alguien modifica los datos directamente con SQL, las reglas se siguen cumpliendo.

## Instalación

1. Requisitos: PostgreSQL 13 o superior y PHP 8 con la extensión `pgsql` habilitada
   (en `php.ini`: `extension=pgsql`).
2. Cree los dos directorios de los tablespaces (deben pertenecer al usuario `postgres`):

   ```bash
   sudo mkdir -p /var/lib/pgsql/tablespaces/restaurante_actual /var/lib/pgsql/tablespaces/restaurante_historico
   sudo chown -R postgres:postgres /var/lib/pgsql/tablespaces
   ```

3. Cree la base de datos completa con un solo comando, como superusuario:

   ```bash
   psql -U postgres -f sql/instalar.sql
   ```

   Si usó otra carpeta para los tablespaces, indíquela con `-v ts_dir=/otra/ruta`.
   Este script crea el rol `estudiante`, los tablespaces y la base `restaurante`. Luego carga el volcado
   y las migraciones en orden. Si la base ya existe, se detiene sin tocarla
   (para reinstalar: `psql -U postgres -c "DROP DATABASE restaurante WITH (FORCE);"`).
4. Revise la conexión en [etc/parametros.php](etc/parametros.php) (host, base de datos, usuario).
   Si el servidor pide clave o usa otro puerto, puede definir las variables de entorno
   `PGPASSWORD` / `PGPORT`, que libpq lee automáticamente.
5. Publique la carpeta en Apache, o pruébela con el servidor de PHP:

   ```bash
   php -S localhost:8000
   ```

### Usuarios de prueba

| Usuario | Clave | Nombre | Roles |
|---|---|---|---|
| `ana` | `clave_ana_2026` | Ana Torres | Administrador |
| `valentina` | `clave_valentina_2026` | Valentina Rojas | Maitre, Recepcionista |
| `carlos` | `clave_carlos_2026` | Carlos Mendoza | Mesero |
| `laura` | `clave_laura_2026` | Laura Gomez | Mesero |
| `diego` | `clave_diego_2026` | Diego Castro | Mesero |
| `sofia` | `clave_sofia_2026` | Sofia Martinez | Cocinero, **Chef** (platos especiales) |
| `miguel` | `clave_miguel_2026` | Miguel Rodriguez | Cocinero |
| `mariana` | `clave_mariana_2026` | Mariana Lopez | Cocinero |
| `andres` | `clave_andres_2026` | Andres Perez | Gerente (reportes) |

Los clientes (por ejemplo, Julian Herrera) no inician sesión. Reservan a través del maitre y piden a través del mesero.
Las claves se guardan como `sha256(sal || clave)`.

## Cómo se cumple cada requerimiento

| Requerimiento | Dónde se garantiza |
|---|---|
| **3.1 Mesas** con identificador y número de asientos; cupo total | Admin → *Mesas y cupo* ([lib/nuevas.php](lib/nuevas.php)). `CHECK (sillas > 0)`, función `fn_cupo_total()` y vista `v_cupo_restaurante`. |
| **3.2 Reservaciones**: no se cruzan en la misma mesa | Trigger de restricción `trg_horario_valido` → `fn_validar_reservacion()`. Usa intervalos semiabiertos `tsrange [inicio, inicio+2h)` con índice GiST. |
| **3.2 / 4.4** No se supera el cupo en ningún horario (2 h por reserva) | `fn_validar_reservacion()` revisa que las mesas tengan sillas suficientes y suma las personas activas en cada instante del intervalo. Los triggers son `DEFERRABLE INITIALLY DEFERRED`, así que se puede cambiar mesa y personas en la misma transacción. Un `pg_advisory_xact_lock` evita condiciones de carrera. |
| **3.2** Validar disponibilidad | Maitre → *Consultar mesas disponibles* (`fn_mesas_disponibles()` y `fn_ocupacion()`). |
| **3.3 Menú**: nombre, descripción, precio, tiempo, categoría; agregar, modificar, eliminar | Admin → *Menú del restaurante* ([lib/menu.php](lib/menu.php)). Un plato que ya se pidió se *retira* (`activo = false`) en lugar de borrarse, para conservar el historial. Hay `CHECK`s de precio y tiempo, y un nombre único entre los platos disponibles. |
| **3.4 Pedidos** asociados a mesa y cliente, con varios ítems, estado inicial «En preparación» | Mesero → *Registrar pedido*. Trigger `trg_pedido_mesero` (lo registra un Mesero y lleva mesa y cliente). Trigger `trg_orden_nueva` (estado inicial 1 y precio congelado al momento del pedido). |
| **3.5 Preparación**: solo platos autorizados, el cocinero elige, En preparación → Preparado | Cocinero → *Mi cola de preparación* ([lib/cocina.php](lib/cocina.php)). `cola_cocinero()` ordena por tiempo de preparación descendente. `tomar_orden()` usa `FOR UPDATE` y valida la autorización. `trg_orden_estado` impide marcar «Preparado» si ningún cocinero tomó el plato. |
| Platos especiales solo para los mejores cocineros | Rol **Chef**. El trigger `trg_autorizacion_valida` rechaza autorizar un plato especial a quien no es Chef. `trg_plato_especial` impide volver especial un plato ya autorizado a quien no es Chef. |
| **3.6 Entregas** y notificación al mesero | El trigger `trg_check_pedido_listo` notifica al mesero cuando todos los platos están preparados. El mesero entrega desde la notificación o desde *Pedidos y entregas*. `trg_orden_estado` solo permite entregar platos preparados y nunca deja retroceder un estado. |
| **3.7 Reportes** de reservaciones, platos más pedidos y ventas por día, semana o mes | Admin o Gerente → *Reportes* ([lib/reportes.php](lib/reportes.php)). Funciones `reporte_*` con `RANK()` y `LAG()`, vista materializada `vm_ventas_diarias`, gráficas y exportación a CSV. |
| **4.1 Notificaciones** al maitre por reservas próximas | `fn_notificar_reservas_proximas(30)`. Se ejecuta sola cada vez que el maitre consulta sus notificaciones (cada 20 s), así que no depende de cron. Opcional: [sql/cron_notificar_reservas.sh](sql/cron_notificar_reservas.sh). |
| **4.2 Empleados** | Admin → *Empleados y usuarios* ([lib/empleados.php](lib/empleados.php)): crear, modificar, asignar varios roles, desactivar y cambiar la clave. |
| **4.3 Historial de clientes** | *Historial de clientes* (`historial_cliente_resumen()` y `historial_cliente_timeline()`). |
| **4.5 Interfaz por rol** | Inicio de sesión ([lib/sesion.php](lib/sesion.php)) y tablero con una sección por rol. Cada opción declara qué roles pueden usarla. El administrador puede usarlas todas. |
| **6.1 Tablespaces** (2, en directorios distintos) | [sql/tablespaces.sql](sql/tablespaces.sql): `ts_restaurante_actual` y `ts_restaurante_historico`. |
| **6.1 Tabla particionada por fechas** | [sql/migracion_particiones.sql](sql/migracion_particiones.sql): `notificaciones` particionada por `RANGE (fecha_creacion)`. Una partición histórica en `ts_restaurante_historico` y una por mes en `ts_restaurante_actual`. `fn_archivar_notificaciones()` mueve las particiones viejas al tablespace histórico. Vista `v_particiones_notificaciones`. |

## Estructura

```
index.php                  enrutador: ?opcion=X → fn_X($conn), con control de sesión y permisos
esqueleto.html             plantilla de la página
lib/sesion.php             inicio de sesión, permisos por rol, mensajes
lib/restaurante.php        tablero por rol, carta, selección de mesa para pedidos
lib/nuevas.php             mesas
lib/menu.php               menú y categorías
lib/empleados.php          empleados, usuarios y registro rápido de clientes
lib/reservaciones.php      reservaciones y disponibilidad
lib/pedidos.php            pedidos y entregas
lib/cocina.php             autorizaciones y cola del cocinero
lib/notificaciones.php     notificaciones (widget con actualización automática)
lib/reportes.php           reportes e historial de clientes
sql/instalar.sql           instalación completa (usa los archivos siguientes)
sql/tablespaces.sql        tablespaces ts_restaurante_actual y ts_restaurante_historico
sql/restaurante_llena.sql  volcado: estructura y datos base
sql/migracion_*.sql        migraciones (cocineros, notificaciones, reportes, integridad, particiones)
sql/pruebas_*.sql          pruebas de cada módulo
docs/insumo_documentacion.md  información completa para redactar la documentación del proyecto
```

## Pruebas

```bash
psql -U postgres -d restaurante -f sql/pruebas_integridad.sql
psql -U postgres -d restaurante -f sql/pruebas_cocineros.sql
psql -U postgres -d restaurante -f sql/pruebas_notificaciones.sql
psql -U postgres -d restaurante -f sql/pruebas_reportes.sql
psql -U postgres -d restaurante -f sql/pruebas_particiones.sql
```

Cada caso imprime `OK`/`FALLA` o `EXITO`/`FALLO`: cruces, sillas, cupo, cancelación, autorizaciones, platos especiales,
estados de los pedidos, notificaciones, claves, tablespaces y particiones. Las pruebas de integridad,
notificaciones y particiones se deshacen al final con `ROLLBACK`. Las de cocineros sí guardan sus datos de prueba.

> Nota: superar el cupo total implica primero violar la regla de sillas, porque cada reserva debe caber
> en sus mesas y las mesas no se cruzan. Por eso, en la práctica, el mensaje que aparece es el de las sillas.
> La verificación explícita del cupo se mantiene como una segunda defensa.
