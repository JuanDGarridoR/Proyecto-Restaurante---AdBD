<?php
/*------------------------------------------------------------------*/
// Inicio de sesión y permisos por rol.
// El usuario se autentica con fn_autenticar() (clave con hash en la BD).
// Cada opción del programa indica qué roles pueden usarla; el
// Administrador puede usarlas todas.
/*------------------------------------------------------------------*/

function sesion_iniciar() {
    if (session_status() != PHP_SESSION_ACTIVE)
        session_start();
}

/**
 * @brief Usuario autenticado: array(id, nombre, login, roles) o null.
 */
function sesion_usuario() {
    return isset($_SESSION['usuario']) ? $_SESSION['usuario'] : null;
}

function sesion_id() {
    $usuario = sesion_usuario();
    return $usuario ? intval($usuario['id']) : 0;
}

/**
 * @brief ¿El usuario autenticado tiene alguno de los roles indicados?
 */
function sesion_tiene_rol(...$roles) {
    $usuario = sesion_usuario();
    if (!$usuario)
        return false;
    return count(array_intersect($roles, $usuario['roles'])) > 0;
}

function sesion_es_admin() {
    return sesion_tiene_rol('Administrador');
}

/*------------------------------------------------------------------*/
/**
 * @brief Roles que pueden usar cada opción. '*' = cualquier usuario
 *        autenticado. Las opciones que no aparecen solo las usa el
 *        Administrador.
 */
function sesion_permisos()
/*--------------------------------------------------------------------*/
{
    $maitre = array('Maitre', 'Recepcionista');
    $mesero = array('Mesero');
    $cocina = array('Cocinero');
    $gerencia = array('Gerente');
    return array(
        'menu_opciones'          => array('*'),
        'desplegar_menu'         => array('*'),
        'buscar_platos'          => array('*'),
        'cambiar_clave'          => array('*'),
        'salir'                  => array('*'),

        'reservaciones'          => $maitre,
        'agregar_reservacion'    => $maitre,
        'editar_reservacion'     => $maitre,
        'cancelar_reservacion'   => $maitre,
        'ejecutar_cron_reservas' => $maitre,

        'realizar_pedidos'       => $mesero,
        'registrar_pedido'       => $mesero,
        'pedidos'                => $mesero,
        'ver_pedido'             => $mesero,
        'estado_pedido'          => $mesero,
        'ajax_entregar_pedido'   => $mesero,

        'registrar_cliente'      => array_merge($maitre, $mesero),
        'notificaciones'         => array_merge($maitre, $mesero),
        'ajax_notificaciones'    => array_merge($maitre, $mesero),
        'ajax_marcar_leida'      => array_merge($maitre, $mesero),
        'historial_clientes'     => array_merge($maitre, $gerencia),

        'cocina'                 => $cocina,
        'tomar_orden'            => $cocina,
        'marcar_preparada'       => $cocina,

        'reportes'               => $gerencia,
    );
}

/**
 * @brief ¿El usuario autenticado puede usar la opción?
 */
function sesion_puede($opcion) {
    if (!sesion_usuario())
        return false;
    if (sesion_es_admin())
        return true;
    $permisos = sesion_permisos();
    if (!isset($permisos[$opcion]))
        return false;
    return in_array('*', $permisos[$opcion]) || sesion_tiene_rol(...$permisos[$opcion]);
}

/**
 * @brief Carga en la sesión los datos y roles actuales del usuario.
 */
function sesion_cargar_usuario($conn, $usuario_id) {
    $filas = reserva_consulta($conn, "
        SELECT u.id, u.nombre, u.login, array_to_json(array_remove(array_agg(r.nombre ORDER BY r.nombre), NULL)) AS roles
        FROM usuarios u
        LEFT JOIN actuaciones a ON a.usuario_id = u.id
        LEFT JOIN roles r ON r.id = a.rol_id
        WHERE u.id = $1 AND u.activo
        GROUP BY u.id", array($usuario_id));
    if (!$filas)
        return false;
    $usuario = $filas[0];
    $usuario['roles'] = json_decode($usuario['roles'], true);
    $_SESSION['usuario'] = $usuario;
    return true;
}

/*------------------------------------------------------------------*/
/**
 * @brief Formulario de inicio de sesión.
 */
function fn_login($conn, $mensaje = "")
/*--------------------------------------------------------------------*/
{
    $login = isset($_REQUEST['login']) ? htmlspecialchars($_REQUEST['login'], ENT_QUOTES) : "";
    return "<h1>Ingreso al sistema</h1>"
         . $mensaje
         . "<form method='post' action='./' class='FORMULARIO_LOGIN'>"
         . "<input type='hidden' name='opcion' value='autenticar'>"
         . "<label>Usuario:</label> <input type='text' name='login' value='$login' autocomplete='username' required autofocus>"
         . "<label>Clave:</label> <input type='password' name='clave' autocomplete='current-password' required>"
         . "<button type='submit'>Ingresar</button>"
         . "</form>"
         . "<p>Los clientes no ingresan al sistema: hacen sus reservaciones a través del maitre y sus pedidos a través del mesero.</p>";
}

function fn_autenticar($conn) {
    if ($_SERVER['REQUEST_METHOD'] != 'POST')
        return fn_login($conn);
    $login = isset($_REQUEST['login']) ? trim($_REQUEST['login']) : "";
    $clave = isset($_REQUEST['clave']) ? $_REQUEST['clave'] : "";

    $filas = reserva_consulta($conn, 'SELECT fn_autenticar($1, $2) AS id', array($login, $clave));
    $usuario_id = ($filas && $filas[0]['id'] !== null) ? intval($filas[0]['id']) : 0;
    if ($usuario_id == 0)
        return fn_login($conn, mensaje_error("Usuario o clave incorrectos, o el usuario está inactivo."));

    session_regenerate_id(true);
    sesion_cargar_usuario($conn, $usuario_id);
    $_REQUEST = array();
    return fn_menu_opciones($conn);
}

function fn_salir($conn) {
    $_SESSION = array();
    session_destroy();
    sesion_iniciar();
    return fn_login($conn, mensaje_ok("Sesión cerrada."));
}

/*------------------------------------------------------------------*/
/**
 * @brief Permite a cualquier usuario cambiar su propia clave.
 */
function fn_cambiar_clave($conn)
/*--------------------------------------------------------------------*/
{
    $mensaje = "";
    if ($_SERVER['REQUEST_METHOD'] == 'POST') {
        $actual = isset($_REQUEST['actual']) ? $_REQUEST['actual'] : "";
        $nueva = isset($_REQUEST['nueva']) ? $_REQUEST['nueva'] : "";
        $repetida = isset($_REQUEST['repetida']) ? $_REQUEST['repetida'] : "";
        $usuario = sesion_usuario();
        $valida = reserva_consulta($conn, 'SELECT fn_autenticar($1, $2) AS id', array($usuario['login'], $actual));
        if (!$valida || intval($valida[0]['id']) != sesion_id())
            $mensaje = mensaje_error("La clave actual no es correcta.");
        elseif ($nueva !== $repetida)
            $mensaje = mensaje_error("La clave nueva y su confirmación no coinciden.");
        elseif (!@pg_query_params($conn, 'SELECT fn_establecer_clave($1, $2)', array(sesion_id(), $nueva)))
            $mensaje = mensaje_error(error_bd($conn));
        else
            $mensaje = mensaje_ok("Clave actualizada correctamente.");
    }

    return fn_boton_menu_principal()
         . "<h2>Cambiar mi clave</h2>"
         . $mensaje
         . "<form method='post' action='./'>"
         . "<input type='hidden' name='opcion' value='cambiar_clave'>"
         . "<label>Clave actual:</label> <input type='password' name='actual' required>"
         . "<label>Clave nueva:</label> <input type='password' name='nueva' minlength='6' required>"
         . "<label>Repita la clave nueva:</label> <input type='password' name='repetida' minlength='6' required>"
         . "<button type='submit'>Guardar clave</button>"
         . "</form>";
}

/*------------------------------------------------------------------*/
// Utilidades de mensajes compartidas por los módulos
/*------------------------------------------------------------------*/

/**
 * @brief Extrae el mensaje legible de un error de PostgreSQL (sin
 *        "ERROR:" ni el CONTEXT de las funciones PL/pgSQL).
 */
function error_bd($conn) {
    $error = pg_last_error($conn);
    if (preg_match('/ERROR:\s*(.*?)(?:\n|CONTEXT:|$)/s', $error, $partes))
        return trim($partes[1]);
    return trim($error);
}

function mensaje_ok($texto) {
    return "<p class='MENSAJE OK'>" . htmlspecialchars($texto) . "</p>";
}

function mensaje_error($texto) {
    return "<p class='MENSAJE ERROR'>" . htmlspecialchars($texto) . "</p>";
}

/**
 * @brief Barra superior con el usuario autenticado y sus roles.
 */
function sesion_barra() {
    $usuario = sesion_usuario();
    if (!$usuario)
        return "";
    return "<div class='BARRA_USUARIO'>"
         . "<span>" . htmlspecialchars($usuario['nombre']) . " · " . htmlspecialchars(implode(', ', $usuario['roles'])) . "</span>"
         . "<a href='?opcion=cambiar_clave'>Cambiar clave</a>"
         . "<a href='?opcion=salir'>Salir</a>"
         . "</div>";
}

?>
