<?php
/*------------------------------------------------------------------*/
// Registro y gestión de pedidos.
// Un pedido (tabla pedidos) pertenece a un cliente, un mesero y una mesa;
// cada plato solicitado es una fila de la tabla ordenes con su cantidad,
// su estado y el precio que tenía el plato al momento de pedirlo.
// El estado del pedido es el del plato menos avanzado.
/*------------------------------------------------------------------*/

define('PEDIDO_EN_PREPARACION', 1);
define('PEDIDO_ENTREGADO', 3);

function pedido_estados() {
    return array(1 => 'En preparación', 2 => 'Preparado', 3 => 'Entregado');
}

function pedido_nombre_estado($estado) {
    $estados = pedido_estados();
    if ($estado === null)
        return "Sin platos";
    return isset($estados[$estado]) ? $estados[$estado] : "Estado $estado";
}

function pedido_dinero($valor) {
    return "$" . number_format(floatval($valor), 0, ',', '.');
}

/*------------------------------------------------------------------*/
/**
 * @brief Indica si existe una columna en la base de datos.
 */
function pedido_tiene_columna($conn, $tabla, $columna)
/*--------------------------------------------------------------------*/
{
    static $existe = array();
    if (!isset($existe["$tabla.$columna"])) {
        $resultado = reserva_consulta($conn, "
            SELECT 1 FROM information_schema.columns
            WHERE table_schema = 'public' AND table_name = $1 AND column_name = $2", array($tabla, $columna));
        $existe["$tabla.$columna"] = ($resultado !== null && count($resultado) > 0);
    }
    return $existe["$tabla.$columna"];
}

/*------------------------------------------------------------------*/
/**
 * @brief Indica si la base de datos tiene las columnas pedidos.mesa_id y
 *        ordenes.precio que necesita el registro de pedidos. La consulta
 *        de pedidos funciona aunque no existan.
 */
function pedido_modelo_listo($conn)
/*--------------------------------------------------------------------*/
{
    return pedido_tiene_columna($conn, 'pedidos', 'mesa_id')
        && pedido_tiene_columna($conn, 'ordenes', 'precio');
}

// Expresiones SQL que se adaptan a las columnas disponibles
function pedido_sql_mesa($conn) {
    return pedido_tiene_columna($conn, 'pedidos', 'mesa_id') ? "PED.mesa_id" : "NULL::integer";
}

function pedido_sql_precio($conn) {
    return pedido_tiene_columna($conn, 'ordenes', 'precio') ? "COALESCE(ORD.precio, PLA.precio)" : "PLA.precio";
}

function pedido_sql_precio_actual($conn) {
    return pedido_tiene_columna($conn, 'ordenes', 'precio') ? "ORD.precio IS NULL" : "true";
}

function pedido_aviso_modelo() {
    return "<p>La base de datos aún no permite guardar la mesa del pedido ni el precio de cada plato. "
         . "Un administrador debe agregar las columnas pedidos.mesa_id y ordenes.precio.</p>";
}

/*------------------------------------------------------------------*/
// Fichas de un solo uso: evitan que un mismo formulario registre el
// pedido dos veces (doble clic, recargar la página o volver atrás).
/*------------------------------------------------------------------*/
function pedido_ficha_nueva() {
    if (session_status() != PHP_SESSION_ACTIVE)
        session_start();
    $ficha = bin2hex(random_bytes(16));
    $_SESSION['fichas_pedido'][$ficha] = true;
    return $ficha;
}

function pedido_ficha_valida($ficha) {
    if (session_status() != PHP_SESSION_ACTIVE)
        session_start();
    return $ficha != "" && isset($_SESSION['fichas_pedido'][$ficha]);
}

function pedido_ficha_usar($ficha) {
    unset($_SESSION['fichas_pedido'][$ficha]);
}

function pedido_meseros($conn) {
    return procesar_query("
        SELECT USR.id, USR.nombre
        FROM usuarios AS USR
        JOIN actuaciones AS ACT ON ACT.usuario_id = USR.id
        JOIN roles AS ROL ON ROL.id = ACT.rol_id
        WHERE ROL.nombre = 'Mesero' AND USR.activo
        GROUP BY USR.id, USR.nombre
        ORDER BY USR.nombre", $conn);
}

// Un mesero registra pedidos a su nombre; el administrador puede elegir el mesero
function pedido_mesero_fijo() {
    return (!sesion_es_admin() && sesion_tiene_rol('Mesero')) ? sesion_id() : null;
}

function pedido_clientes($conn) {
    return procesar_query("SELECT id, nombre FROM usuarios WHERE activo ORDER BY nombre", $conn);
}

/*------------------------------------------------------------------*/
/**
 * @brief Lee y valida los datos del formulario de pedido.
 * @param array $errores Recibe los mensajes de los datos inválidos.
 * @return array Datos validados (mesa_id, cliente_id, mesero_id y
 *         platos como plato_id => cantidad).
 */
function pedido_leer_formulario($conn, &$errores)
/*--------------------------------------------------------------------*/
{
    $errores = array();
    $datos = array();

    $datos['mesa_id'] = mesa_validar_entero('mesa_id', 1, 2147483647);
    if ($datos['mesa_id'] === null || !mesa_existe($conn, $datos['mesa_id']))
        $errores[] = "Seleccione una mesa existente.";

    $datos['cliente_id'] = mesa_validar_entero('cliente_id', 1, 2147483647);
    if ($datos['cliente_id'] === null
        || count(reserva_consulta($conn, 'SELECT id FROM usuarios WHERE id = $1', array($datos['cliente_id']))) == 0)
        $errores[] = "Seleccione un cliente existente.";

    $datos['mesero_id'] = mesa_validar_entero('mesero_id', 1, 2147483647);
    if (pedido_mesero_fijo() !== null)
        $datos['mesero_id'] = pedido_mesero_fijo();
    $es_mesero = false;
    foreach (pedido_meseros($conn)->datos as $mesero)
        if ($mesero['id'] == $datos['mesero_id'])
            $es_mesero = true;
    if (!$es_mesero)
        $errores[] = "Seleccione un mesero válido (usuario con rol Mesero).";

    $platos = array();
    foreach (procesar_query("SELECT id, nombre FROM platos WHERE activo", $conn)->datos as $plato)
        $platos[$plato['id']] = $plato['nombre'];

    $datos['platos'] = array();
    $cantidades = (isset($_REQUEST['cantidad']) && is_array($_REQUEST['cantidad'])) ? $_REQUEST['cantidad'] : array();
    foreach ($cantidades as $plato_id => $cantidad) {
        $cantidad = trim($cantidad);
        if ($cantidad === "" || $cantidad === "0")
            continue;
        if (!isset($platos[$plato_id])) {
            $errores[] = "El plato " . htmlspecialchars($plato_id) . " no existe en el menú.";
            continue;
        }
        $valor = filter_var($cantidad, FILTER_VALIDATE_INT, array('options' => array('min_range' => 1, 'max_range' => 50)));
        if ($valor === false)
            $errores[] = "La cantidad de «" . $platos[$plato_id] . "» debe ser un entero entre 0 y 50.";
        else
            $datos['platos'][intval($plato_id)] = $valor;
    }
    if (count($datos['platos']) == 0 && count($errores) == 0)
        $errores[] = "Agregue al menos un plato con cantidad mayor que cero.";

    return $datos;
}

/*------------------------------------------------------------------*/
/**
 * @brief Guarda el pedido y sus platos en una sola transacción, con el
 *        precio vigente de cada plato y el estado «En preparación».
 * @param int $pedido_id Recibe el id del pedido creado.
 * @return string Mensaje de error, o "" si se guardó.
 */
function pedido_guardar($conn, $datos, &$pedido_id)
/*--------------------------------------------------------------------*/
{
    $anidada = reserva_transaccion_iniciar($conn);
    $error = "";

    $nuevo = reserva_consulta($conn, 'INSERT INTO pedidos (cliente_id, mesero_id, mesa_id) VALUES ($1, $2, $3) RETURNING id',
                              array($datos['cliente_id'], $datos['mesero_id'], $datos['mesa_id']));
    if ($nuevo === null)
        $error = "Error al guardar el pedido: " . error_bd($conn);
    else
        $pedido_id = intval($nuevo[0]['id']);

    foreach ($datos['platos'] as $plato_id => $cantidad) {
        if ($error != "")
            break;
        $res = @pg_query_params($conn, '
            INSERT INTO ordenes (plato_id, pedido_id, estado, cantidad, solicitado, precio)
            SELECT id, $2, $3, $4, now(), precio FROM platos WHERE id = $1',
            array($plato_id, $pedido_id, PEDIDO_EN_PREPARACION, $cantidad));
        if (!$res)
            $error = "Error al guardar los platos del pedido: " . error_bd($conn);
        elseif (pg_affected_rows($res) != 1)
            $error = "El plato $plato_id ya no existe en el menú.";
    }

    reserva_transaccion_terminar($conn, $anidada, $error == "");
    return $error;
}

/*------------------------------------------------------------------*/
/**
 * @brief Formulario para registrar un pedido en una mesa.
 */
function pedido_formulario($conn, $mesa_id, $valores, $ficha, $mensaje = "")
/*--------------------------------------------------------------------*/
{
    if (!mesa_existe($conn, $mesa_id))
        return "<p>Error: la mesa indicada no existe.</p>";

    // Por omisión el cliente es quien tiene reservada la mesa hoy
    if (!isset($valores['cliente_id'])) {
        $reserva = reserva_consulta($conn, "
            SELECT RES.cliente_id
            FROM horarios AS HOR
            JOIN reservaciones AS RES ON RES.id = HOR.reservacion_id
            WHERE HOR.mesa_id = $1
              AND RES.estado IS DISTINCT FROM $2
              AND HOR.inicio::date = CURRENT_DATE
            ORDER BY abs(extract(epoch FROM HOR.inicio - LOCALTIMESTAMP))
            LIMIT 1", array($mesa_id, RESERVA_CANCELADA));
        if ($reserva)
            $valores['cliente_id'] = $reserva[0]['cliente_id'];
    }
    $valor = function ($campo) use ($valores) {
        return isset($valores[$campo]) ? $valores[$campo] : "";
    };

    $html = "<h2>Pedido para la mesa $mesa_id</h2>";
    $html .= $mensaje;
    $html .= "<form method='post' action='./'>"
           . "<input type='hidden' name='opcion' value='registrar_pedido'>"
           . "<input type='hidden' name='mesa_id' value='$mesa_id'>"
           . "<input type='hidden' name='ficha' value='$ficha'>";

    if (pedido_mesero_fijo() !== null) {
        $usuario = sesion_usuario();
        $html .= "<input type='hidden' name='mesero_id' value='" . pedido_mesero_fijo() . "'>"
               . "<label>Mesero: <strong>" . htmlspecialchars($usuario['nombre']) . "</strong></label>";
    } else {
        $html .= "<label>Mesero:</label> <select name='mesero_id' required><option value=''></option>";
        foreach (pedido_meseros($conn)->datos as $mesero) {
            $marcado = ($valor('mesero_id') == $mesero['id']) ? " selected" : "";
            $html .= "<option value='" . $mesero['id'] . "'$marcado>" . htmlspecialchars($mesero['nombre']) . "</option>";
        }
        $html .= "</select>";
    }

    $html .= "<label>Cliente:</label> <select name='cliente_id' required><option value=''></option>";
    foreach (pedido_clientes($conn)->datos as $cliente) {
        $marcado = ($valor('cliente_id') == $cliente['id']) ? " selected" : "";
        $html .= "<option value='" . $cliente['id'] . "'$marcado>" . htmlspecialchars($cliente['nombre']) . "</option>";
    }
    $html .= "</select>";

    $cantidades = (isset($valores['cantidad']) && is_array($valores['cantidad'])) ? $valores['cantidad'] : array();
    $platos = procesar_query("
        SELECT platos.id, platos.nombre, tipos.nombre AS tipo, precio
        FROM platos
        LEFT JOIN tipos ON platos.tipo_id = tipos.id
        WHERE platos.activo
        ORDER BY tipos.id, platos.nombre", $conn);
    $html .= "<table><tr><th>Plato</th><th>Tipo</th><th>Precio</th><th>Cantidad</th></tr>";
    foreach ($platos->datos as $plato) {
        $cantidad = isset($cantidades[$plato['id']]) ? htmlspecialchars($cantidades[$plato['id']], ENT_QUOTES) : "0";
        $html .= "<tr><td>" . htmlspecialchars($plato['nombre']) . "</td><td>" . $plato['tipo'] . "</td><td>" . pedido_dinero($plato['precio'])
               . "</td><td><input type='number' name='cantidad[" . $plato['id'] . "]' min='0' max='50' value='$cantidad'></td></tr>";
    }
    $html .= "</table>";
    $html .= "<button type='submit'>Registrar pedido</button>"
           . "</form>";

    return $html;
}

function fn_registrar_pedido($conn) {
    $retorno = fn_boton_menu_principal() . pedido_boton_lista() . "<br />";
    if (!pedido_modelo_listo($conn))
        return $retorno . pedido_aviso_modelo();
    if ($_SERVER['REQUEST_METHOD'] != 'POST')
        return fn_realizar_pedidos($conn);

    $ficha = isset($_REQUEST['ficha']) ? $_REQUEST['ficha'] : "";
    if (!pedido_ficha_valida($ficha))
        return fn_pedidos($conn, "<p>Este formulario ya se había enviado, así que el pedido no se registró de nuevo. Revise la lista de pedidos.</p>");

    $datos = pedido_leer_formulario($conn, $errores);
    if (count($errores) == 0) {
        $pedido_id = 0;
        $error = pedido_guardar($conn, $datos, $pedido_id);
        if ($error == "") {
            pedido_ficha_usar($ficha);
            $_REQUEST = array();
            return fn_ver_pedido($conn, $pedido_id, "<p>Pedido $pedido_id registrado correctamente en estado «En preparación».</p>");
        }
        $errores[] = $error;
    }

    $mensaje = reserva_mensajes($errores);
    if ($datos['mesa_id'] === null || !mesa_existe($conn, $datos['mesa_id']))
        return fn_realizar_pedidos($conn) . $mensaje;
    return $retorno . pedido_formulario($conn, $datos['mesa_id'], $_REQUEST, $ficha, $mensaje);
}

function pedido_boton_lista() {
    $scr_pedidos = "window.open('?opcion=pedidos', '_top');";
    return "<button onClick=\"$scr_pedidos\">Ver pedidos</button>";
}

/*------------------------------------------------------------------*/
/**
 * @brief Lista los pedidos registrados con su total y su estado.
 */
function fn_pedidos($conn, $mensaje = "")
/*--------------------------------------------------------------------*/
{
    $scr_nuevo = "window.open('?opcion=realizar_pedidos', '_top');";
    $html = fn_boton_menu_principal() . "<button onClick=\"$scr_nuevo\">Realizar pedido</button>";
    $html .= "<h2>Pedidos y entregas</h2>";
    $html .= $mensaje;
    $html .= notificaciones_widget($conn, 'Mesero');

    // Filtros: pendientes (sin entregar) o todos; solo los míos o de todos los meseros
    $ver = (isset($_REQUEST['ver']) && $_REQUEST['ver'] == 'todos') ? 'todos' : 'pendientes';
    $mios = pedido_mesero_fijo() !== null && !(isset($_REQUEST['mios']) && $_REQUEST['mios'] == '0');
    $condiciones = array();
    $parametros = array();
    if ($ver == 'pendientes')
        $condiciones[] = "estado < " . PEDIDO_ENTREGADO;
    if ($mios) {
        $parametros[] = sesion_id();
        $condiciones[] = "mesero_id = $" . count($parametros);
    }
    $where = count($condiciones) ? "WHERE " . implode(" AND ", $condiciones) : "";

    $pedidos = reserva_consulta($conn, "
        SELECT pedido_id AS id, mesa_id, cliente, mesero, estado, platos, platos_en_preparacion, total,
               to_char(solicitado, 'YYYY-MM-DD HH24:MI') AS fecha
        FROM v_pedidos
        $where
        ORDER BY (estado = 2) DESC, solicitado DESC NULLS LAST, pedido_id DESC
        LIMIT 200", $parametros);

    $enlace = function ($param_ver, $param_mios, $texto, $activo) {
        if ($activo)
            return "<strong>$texto</strong> ";
        return "<a class='FILTRO' href='?opcion=pedidos&ver=$param_ver&mios=$param_mios'>$texto</a> ";
    };
    $html .= "<p>" . $enlace('pendientes', $mios ? 1 : 0, "Sin entregar", $ver == 'pendientes')
           . $enlace('todos', $mios ? 1 : 0, "Todos", $ver == 'todos');
    if (pedido_mesero_fijo() !== null)
        $html .= " | " . $enlace($ver, 1, "Mis pedidos", $mios) . $enlace($ver, 0, "De todos los meseros", !$mios);
    $html .= "</p>";

    $html .= "<table><tr><th>Pedido</th><th>Fecha</th><th>Mesa</th><th>Cliente</th><th>Mesero</th><th>Platos</th><th>Total</th><th>Estado</th><th>Acciones</th></tr>";
    foreach ($pedidos as $pedido) {
        $scr_ver = "window.open('?opcion=ver_pedido&pedido_id=" . $pedido['id'] . "', '_top');";
        $acciones = "<button onClick=\"$scr_ver\">Ver detalle</button>";
        $estado = pedido_nombre_estado($pedido['estado']);
        if ($pedido['estado'] == 2) {
            $estado = "<strong>Listo para entregar</strong>";
            $acciones .= pedido_boton_entregar($pedido['id']);
        } elseif ($pedido['estado'] == 1) {
            $estado .= " (" . $pedido['platos_en_preparacion'] . " en cocina)";
        }
        $html .= "<tr" . ($pedido['estado'] == 2 ? " class='LISTO'" : "") . "><td>" . $pedido['id'] . "</td><td>" . $pedido['fecha'] . "</td><td>" . ($pedido['mesa_id'] ?: "Sin registrar")
               . "</td><td>" . htmlspecialchars($pedido['cliente']) . "</td><td>" . htmlspecialchars($pedido['mesero'])
               . "</td><td>" . $pedido['platos'] . "</td><td>" . pedido_dinero($pedido['total'])
               . "</td><td>$estado</td><td>$acciones</td></tr>";
    }
    $html .= "</table>";
    if (count($pedidos) == 0)
        $html .= "<p>No hay pedidos con este filtro.</p>";

    return $html;
}

function pedido_boton_entregar($pedido_id) {
    return "<form method='post' action='./' style='display:inline'>"
         . "<input type='hidden' name='opcion' value='estado_pedido'>"
         . "<input type='hidden' name='pedido_id' value='$pedido_id'>"
         . "<input type='hidden' name='estado' value='" . PEDIDO_ENTREGADO . "'>"
         . "<button type='submit'>Entregar</button>"
         . "</form>";
}

/*------------------------------------------------------------------*/
/**
 * @brief Muestra el detalle de un pedido, su total y el cambio de estado.
 */
function fn_ver_pedido($conn, $pedido_id = null, $mensaje = "")
/*--------------------------------------------------------------------*/
{
    if ($pedido_id === null)
        $pedido_id = mesa_validar_entero('pedido_id', 1, 2147483647);

    $pedido = ($pedido_id === null) ? array() : reserva_consulta($conn, "
        SELECT PED.id, " . pedido_sql_mesa($conn) . " AS mesa_id, CLI.nombre AS cliente, MSR.nombre AS mesero
        FROM pedidos AS PED
        LEFT JOIN usuarios AS CLI ON CLI.id = PED.cliente_id
        LEFT JOIN usuarios AS MSR ON MSR.id = PED.mesero_id
        WHERE PED.id = $1", array($pedido_id));
    if (count($pedido) == 0)
        return fn_pedidos($conn, "<p>Error: el pedido indicado no existe.</p>");
    $pedido = $pedido[0];

    $ordenes = reserva_consulta($conn, "
        SELECT PLA.nombre
             , ORD.cantidad
             , " . pedido_sql_precio($conn) . " AS precio
             , " . pedido_sql_precio_actual($conn) . " AS precio_actual
             , ORD.cantidad * " . pedido_sql_precio($conn) . " AS subtotal
             , ORD.estado
             , to_char(ORD.solicitado, 'YYYY-MM-DD HH24:MI') AS solicitado
             , COC.nombre AS cocinero
        FROM ordenes AS ORD
        JOIN platos AS PLA ON PLA.id = ORD.plato_id
        LEFT JOIN usuarios AS COC ON COC.id = ORD.cocinero_id
        WHERE ORD.pedido_id = $1
        ORDER BY ORD.id", array($pedido_id));

    $total = 0;
    $estado = null;
    $hay_precio_actual = false;
    $preparados = 0;
    foreach ($ordenes as $orden) {
        $total += floatval($orden['subtotal']);
        $estado = ($estado === null) ? intval($orden['estado']) : min($estado, intval($orden['estado']));
        $hay_precio_actual = $hay_precio_actual || $orden['precio_actual'] == 't';
        if ($orden['estado'] == 2)
            $preparados++;
    }

    $html = fn_boton_menu_principal() . pedido_boton_lista();
    $html .= "<h2>Pedido $pedido_id</h2>";
    $html .= $mensaje;
    $html .= "<p>Mesa: " . ($pedido['mesa_id'] ?: "Sin registrar") . " · Cliente: " . htmlspecialchars($pedido['cliente'])
           . " · Mesero: " . htmlspecialchars($pedido['mesero']) . " · Estado: " . pedido_nombre_estado($estado) . "</p>";

    $html .= "<table><tr><th>Plato</th><th>Cantidad</th><th>Precio</th><th>Subtotal</th><th>Estado</th><th>Cocinero</th><th>Solicitado</th></tr>";
    foreach ($ordenes as $orden) {
        $html .= "<tr" . ($orden['estado'] == 2 ? " class='LISTO'" : "") . "><td>" . htmlspecialchars($orden['nombre']) . "</td><td>" . $orden['cantidad']
               . "</td><td>" . pedido_dinero($orden['precio']) . ($orden['precio_actual'] == 't' ? "*" : "")
               . "</td><td>" . pedido_dinero($orden['subtotal']) . "</td><td>" . pedido_nombre_estado(intval($orden['estado']))
               . "</td><td>" . htmlspecialchars($orden['cocinero'] ?: "Sin asignar")
               . "</td><td>" . $orden['solicitado'] . "</td></tr>";
    }
    $html .= "<tr><th colspan='3'>Total</th><th>" . pedido_dinero($total) . "</th><th colspan='3'></th></tr>";
    $html .= "</table>";
    if ($hay_precio_actual)
        $html .= "<p>* Pedido anterior al registro de precios: se usa el precio actual del plato.</p>";

    // El cocinero marca cada plato como «Preparado»; el mesero entrega los preparados
    if ($preparados > 0) {
        $texto = ($estado == 2) ? "Todos los platos están listos." : "Hay $preparados plato(s) listo(s); los demás siguen en cocina.";
        $html .= "<p>$texto</p>" . pedido_boton_entregar($pedido_id);
    } elseif ($estado == PEDIDO_EN_PREPARACION) {
        $html .= "<p>Los platos están en cocina. Recibirá una notificación cuando el pedido esté listo para entregar.</p>";
    }

    return $html;
}

/*------------------------------------------------------------------*/
/**
 * @brief Registra la entrega de los platos preparados de un pedido
 *        (Preparado → Entregado). Marcar «Preparado» le corresponde al
 *        cocinero; la base de datos impide entregar platos sin preparar
 *        y retroceder estados.
 */
function fn_estado_pedido($conn)
/*--------------------------------------------------------------------*/
{
    $pedido_id = mesa_validar_entero('pedido_id', 1, 2147483647);
    if ($_SERVER['REQUEST_METHOD'] != 'POST')
        return fn_pedidos($conn, mensaje_error("Use el botón Entregar del pedido."));
    if ($pedido_id === null)
        return fn_pedidos($conn, mensaje_error("El pedido indicado no existe."));
    if (mesa_validar_entero('estado', 1, 3) !== PEDIDO_ENTREGADO)
        return fn_ver_pedido($conn, $pedido_id, mensaje_error("El mesero solo registra entregas; el cocinero marca los platos como preparados."));

    $anidada = reserva_transaccion_iniciar($conn);
    $res = @pg_query_params($conn, 'UPDATE ordenes SET estado = $1 WHERE pedido_id = $2 AND estado = 2',
                            array(PEDIDO_ENTREGADO, $pedido_id));
    $error = "";
    if (!$res)
        $error = "Error al registrar la entrega: " . error_bd($conn);
    elseif (pg_affected_rows($res) == 0)
        $error = "El pedido $pedido_id no tiene platos preparados pendientes de entrega.";
    $entregados = $res ? pg_affected_rows($res) : 0;
    reserva_transaccion_terminar($conn, $anidada, $error == "");

    if ($error != "")
        return fn_ver_pedido($conn, $pedido_id, mensaje_error($error));
    return fn_ver_pedido($conn, $pedido_id, mensaje_ok("Se registró la entrega de $entregados plato(s) del pedido $pedido_id."));
}

?>
