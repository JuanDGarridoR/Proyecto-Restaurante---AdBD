<?php
//------------------------------------------------------------
ini_set('display_errors', 1);
ini_set('display_startup_errors', 1);
error_reporting(E_ALL);

require_once("etc/parametros.php");
require_once("lib/libreria.php");
require_once("lib/sesion.php");
require_once("lib/restaurante.php");
require_once("lib/nuevas.php");
require_once("lib/menu.php");
require_once("lib/empleados.php");
require_once("lib/reservaciones.php");
require_once("lib/pedidos.php");
require_once("lib/cocina.php");
require_once("lib/notificaciones.php");
require_once("lib/reportes.php");

//------------------------------------------------------------
sesion_iniciar();
$conn = pg_conectar($host, $dbname, $user);

$opcion = "";
if (isset($_REQUEST['opcion']) && is_string($_REQUEST['opcion']))
    $opcion = $_REQUEST['opcion'];

// Los datos y roles del usuario se releen en cada petición para que los
// cambios del administrador (roles, desactivación) apliquen de inmediato
if (sesion_usuario() && !sesion_cargar_usuario($conn, sesion_id())) {
    $_SESSION = array();
    $opcion = "login";
}

if (!sesion_usuario()) {
    if ($opcion != "autenticar")
        $opcion = "login";
    $contenido = ($opcion == "autenticar") ? fn_autenticar($conn) : fn_login($conn);
} elseif ($opcion == "" || $opcion == "login" || $opcion == "autenticar") {
    $contenido = fn_menu_opciones($conn);
} elseif (!function_exists("fn_" . $opcion)) {
    $contenido = fn_menu_opciones($conn);
} elseif (!sesion_puede($opcion)) {
    $contenido = fn_boton_menu_principal()
               . mensaje_error("Su rol no tiene permiso para usar esta opción.");
} else {
    $funcion = "fn_" . $opcion;
    $contenido = $funcion($conn);
}

//------------------------------------------------------------
$esqueleto = file_get_contents("esqueleto.html");
$html = sprintf($esqueleto, sesion_barra(), $contenido);
print $html;

//------------------------------------------------------------
?>
