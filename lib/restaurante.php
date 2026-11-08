<?php
/*------------------------------------------------------------------*/
/**
 * @brief Genera el código HTML de un botón para regresar al inicio.
 * @return string Cadena de texto con el botón HTML.
 * @pre Ninguna.
 * @post El botón redirige a la opción raíz mediante JavaScript.
 */
function fn_boton_menu_principal()
/*--------------------------------------------------------------------*/
{
    $scr_menu = "window.open('./', '_top');";
    $retorno = "<button onClick=\"$scr_menu\">Menu del programa</button>";
    return $retorno;
}

/*------------------------------------------------------------------*/
/**
 * @brief Tablero principal: muestra una sección por cada rol del usuario
 *        con las opciones que ese rol puede usar.
 * @param resource $conn Recurso de conexión a la base de datos.
 * @return string Fragmento HTML con el menú de navegación por rol.
 * @pre Debe haber un usuario autenticado.
 * @post El administrador ve las secciones de todos los roles.
 */
function fn_menu_opciones($conn)
/*--------------------------------------------------------------------*/
{
    $secciones = array(
        'Administrador' => array(
            'descripcion' => 'Información del restaurante, empleados, cocina y reportes',
            'opciones' => array(
                'ver_mesas' => 'Mesas y cupo',
                'gestionar_menu' => 'Menú del restaurante',
                'empleados' => 'Empleados y usuarios',
                'autorizaciones_cocina' => 'Platos autorizados a cocineros',
                'reportes' => 'Reportes y estadísticas',
                'historial_clientes' => 'Historial de clientes',
            )),
        'Maitre' => array(
            'descripcion' => 'Reservaciones y asignación de mesas',
            'opciones' => array(
                'reservaciones' => 'Gestionar reservaciones',
                'registrar_cliente&volver=reservaciones' => 'Registrar cliente',
                'notificaciones' => 'Notificaciones',
                'historial_clientes' => 'Historial de clientes',
            )),
        'Mesero' => array(
            'descripcion' => 'Pedidos de las mesas y entregas',
            'opciones' => array(
                'realizar_pedidos' => 'Registrar pedido',
                'pedidos' => 'Pedidos y entregas',
                'registrar_cliente&volver=realizar_pedidos' => 'Registrar cliente',
                'notificaciones' => 'Notificaciones',
            )),
        'Cocinero' => array(
            'descripcion' => 'Platos por preparar (los más demorados primero)',
            'opciones' => array(
                'cocina' => 'Mi cola de preparación',
            )),
        'Gerente' => array(
            'descripcion' => 'Indicadores del negocio',
            'opciones' => array(
                'reportes' => 'Reportes y estadísticas',
                'historial_clientes' => 'Historial de clientes',
            )),
    );
    // El recepcionista trabaja como maitre
    $alias = array('Recepcionista' => 'Maitre');

    $usuario = sesion_usuario();
    $mostrar = array();
    foreach ($usuario['roles'] as $rol) {
        $rol = isset($alias[$rol]) ? $alias[$rol] : $rol;
        if (isset($secciones[$rol]))
            $mostrar[$rol] = true;
    }
    if (sesion_es_admin())
        foreach ($secciones as $rol => $seccion)
            $mostrar[$rol] = true;

    $retorno = "<h1>Bienvenido(a), " . htmlspecialchars($usuario['nombre']) . "</h1>";
    $retorno .= "<div class='TABLERO'>";
    foreach ($secciones as $rol => $seccion) {
        if (!isset($mostrar[$rol]))
            continue;
        $retorno .= "<section class='ROL'><h2>$rol</h2><p>" . $seccion['descripcion'] . "</p><div class='MENU_OPCIONES'>";
        foreach ($seccion['opciones'] as $opcion => $texto) {
            // Solo se muestran las opciones que el rol realmente puede usar
            if (!sesion_puede(strtok($opcion, '&')))
                continue;
            $script = "window.open('?opcion=$opcion', '_top');";
            $retorno .= "<button onClick=\"$script\">$texto</button>";
        }
        $retorno .= "</div></section>";
    }
    $retorno .= "<section class='ROL'><h2>Consulta</h2><p>Carta del restaurante</p><div class='MENU_OPCIONES'>"
              . "<button onClick=\"window.open('?opcion=desplegar_menu', '_top');\">Ver la carta</button>"
              . "<button onClick=\"window.open('?opcion=buscar_platos', '_top');\">Platos por precio</button>"
              . "</div></section>";
    $retorno .= "</div>";
    return $retorno;
}

/*------------------------------------------------------------------*/
/**
 * @brief Consulta y visualiza la carta de platos agrupados por tipo.
 * @param resource $conexion_bd Recurso de conexión a la base de datos.
 * @return string Lista HTML (ul) con las secciones y platos del restaurante.
 * @pre Debe existir la tabla platos y tipos con datos íntegros.
 * @post Genera la visualización estructurada del menú (solo platos activos).
 */
function fn_desplegar_menu($conn)
/*--------------------------------------------------------------------*/
{
    $sentencia = "
    SELECT platos.id
         , platos.nombre
         , tipos.nombre AS tipo
         , descripcion
         , precio
         , EXTRACT(EPOCH FROM tiempo)::int / 60 AS minutos
    FROM platos
    LEFT JOIN tipos ON platos.tipo_id=tipos.id
    WHERE platos.activo
        ORDER BY tipos.id, platos.nombre
        ;";
    $resultado = procesar_query($sentencia, $conn);
    $retorno = fn_boton_menu_principal()."<br />";
    $tipo = "<div class='SECCION'>";
    foreach ($resultado->datos AS $plato) {
    if ($tipo != $plato['tipo']) {
        $retorno.= "</div><div class='SECCION'><h2>".htmlspecialchars($plato['tipo'])."</h2>";
        $tipo = $plato['tipo'];
    }
        $retorno.= "<div class='PLATO'>"
                 .     "<span class='NOMBRE'>".htmlspecialchars($plato['nombre'])."</span>"
                 .     "<span class='DESCRIPCION'>".htmlspecialchars($plato['descripcion'])." (".$plato['minutos']." min)</span>"
                 .     "<span class='PRECIO'>".pedido_dinero($plato['precio'])."</span>"
                 . "</div>";
    }
    $retorno .= "</div>";
    $retorno = "<ul>$retorno</ul>";
    return $retorno;
}

/*------------------------------------------------------------------*/
/**
 * @brief Gestiona el flujo de pedidos, listando mesas o procesando una específica.
 * @param resource $conexion_bd Recurso de conexión a la base de datos.
 * @return string HTML con el listado de mesas disponibles o el formulario de pedido.
 * @pre El parámetro mesa_id en $_REQUEST determina el flujo de la función.
 * @post Facilita la selección de mesa para iniciar un pedido.
 */
function fn_realizar_pedidos($conn, $mensaje = "")
/*--------------------------------------------------------------------*/
{
    $scr_cliente = "window.open('?opcion=registrar_cliente&volver=realizar_pedidos', '_top');";
    $retorno = fn_boton_menu_principal().pedido_boton_lista()
             . "<button onClick=\"$scr_cliente\">Registrar cliente</button><br />".$mensaje;
    if (!pedido_modelo_listo($conn))
        return $retorno.pedido_aviso_modelo();

    // Cliente preseleccionado (p. ej. recién registrado)
    $cliente_id = mesa_validar_entero('cliente_id', 1, 2147483647);
    $param_cliente = ($cliente_id === null) ? "" : "&cliente_id=$cliente_id";

    if (isset($_REQUEST['mesa_id']))
        $accion = "pedido_mesa";
    else
        $accion = "listar_mesas";

    switch ($accion) {
    case 'listar_mesas':
        //----------------------------------------
        // Listado de mesas
        //----------------------------------------
        // Todas las mesas, con el cliente que la tenga reservada hoy
        $sentencia = "
            SELECT MES.id
                 , MES.sillas
                 , string_agg(DISTINCT USR.nombre, ', ') as nombre_usr
            FROM mesas AS MES
            LEFT JOIN horarios      AS HOR ON MES.id = HOR.mesa_id
                                          AND HOR.inicio BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '1 day'
            LEFT JOIN reservaciones AS RES ON RES.id = HOR.reservacion_id
                                          AND RES.estado IS DISTINCT FROM ".RESERVA_CANCELADA."
            LEFT JOIN usuarios      AS USR ON USR.id = RES.cliente_id
            GROUP BY MES.id, MES.sillas
            ORDER BY MES.id
            ";
        $resultado = procesar_query($sentencia, $conn);

        $botones_mesas = "";
        foreach ($resultado->datos as $mesa) {
            $script = "window.open('?opcion=realizar_pedidos&mesa_id=".$mesa['id'].$param_cliente."', '_top');";
            $reserva = ($mesa['nombre_usr'] != "") ? "<br><small>Reserva hoy: ".htmlspecialchars($mesa['nombre_usr'])."</small>" : "";
            $botones_mesas.= "<button onClick=\"$script\">Mesa ".$mesa['id']." (".$mesa['sillas']." sillas)$reserva</button>";
        }
        $retorno .= "<h2>Seleccione la mesa del pedido</h2>";
        $retorno .= "<div class='MENU_OPCIONES'>".$botones_mesas."</div>";
        break;
    case 'pedido_mesa':
        $valores = ($cliente_id === null) ? array() : array('cliente_id' => $cliente_id);
        $retorno .= pedido_formulario($conn, intval($_REQUEST['mesa_id']), $valores, pedido_ficha_nueva());
    }

    return $retorno;
}
//------------------------------------------------------------
?>
