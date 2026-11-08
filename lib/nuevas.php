<?php

function fn_ver_mesas($conn, $mensaje = "") {
    $sentencia = "SELECT MES.id, MES.sillas, COUNT(HOR.id) AS horarios
                  FROM mesas AS MES
                  LEFT JOIN horarios AS HOR ON HOR.mesa_id = MES.id
                  GROUP BY MES.id, MES.sillas
                  ORDER BY MES.id";
    $resultado = procesar_query($sentencia, $conn);

    $cupo = 0;
    $siguiente_id = 1;
    foreach ($resultado->datos as $mesa) {
        $cupo += intval($mesa['sillas']);
        $siguiente_id = max($siguiente_id, intval($mesa['id']) + 1);
    }

    $html = fn_boton_menu_principal();
    $html .= "<h2>Gestión de mesas</h2>";
    $html .= $mensaje;
    $html .= "<p>Cupo total del restaurante: " . $cupo . " sillas en " . $resultado->cantidad . " mesas</p>";
    $scr_reservas = "window.open('?opcion=reservaciones', '_top');";
    $html .= "<button onClick=\"$scr_reservas\">Gestionar reservaciones</button>";

    $html .= "<table><tr><th>Mesa</th><th>Sillas</th><th>Reservas</th><th>Acciones</th></tr>";
    foreach ($resultado->datos as $mesa) {
        $scr_editar = "window.open('?opcion=editar_mesa&mesa_id=" . $mesa['id'] . "', '_top');";
        $html .= "<tr><td>" . $mesa['id'] . "</td><td>" . $mesa['sillas'] . "</td><td>" . $mesa['horarios'] . "</td><td>"
               . "<button onClick=\"$scr_editar\">Modificar</button>"
               . "<form method='post' action='./' style='display:inline' onSubmit=\"return confirm('¿Eliminar la mesa " . $mesa['id'] . "?');\">"
               . "<input type='hidden' name='opcion' value='eliminar_mesa'>"
               . "<input type='hidden' name='mesa_id' value='" . $mesa['id'] . "'>"
               . "<button type='submit'>Eliminar</button>"
               . "</form>"
               . "</td></tr>";
    }
    $html .= "</table>";

    $html .= "<h2>Registrar una mesa nueva</h2>";
    $html .= "<form method='post' action='./'>"
           . "<input type='hidden' name='opcion' value='agregar_mesa'>"
           . "<label>Número de mesa:</label> <input type='number' name='mesa_id' min='1' value='" . $siguiente_id . "' required>"
           . "<label>Sillas:</label> <input type='number' name='sillas' min='1' max='" . MESAS_MAX_SILLAS . "' required>"
           . "<button type='submit'>Guardar mesa</button>"
           . "</form>";

    return $html;
}

define('MESAS_MAX_SILLAS', 50);

/*------------------------------------------------------------------*/
/**
 * @brief Valida que un dato recibido sea un entero dentro de un rango.
 * @return int|null El entero validado, o null si el dato no es válido.
 */
function mesa_validar_entero($nombre, $minimo, $maximo)
/*--------------------------------------------------------------------*/
{
    if (!isset($_REQUEST[$nombre]))
        return null;
    $valor = filter_var(trim($_REQUEST[$nombre]), FILTER_VALIDATE_INT,
                        array('options' => array('min_range' => $minimo, 'max_range' => $maximo)));
    return ($valor === false) ? null : $valor;
}

function mesa_existe($conn, $mesa_id) {
    $resultado = procesar_query("SELECT id FROM mesas WHERE id = " . intval($mesa_id), $conn);
    return $resultado->cantidad > 0;
}

function fn_agregar_mesa($conn) {
    $mesa_id = mesa_validar_entero('mesa_id', 1, 2147483647);
    $sillas = mesa_validar_entero('sillas', 1, MESAS_MAX_SILLAS);

    if ($mesa_id === null)
        return fn_ver_mesas($conn, "<p>Error: el número de mesa debe ser un entero mayor que cero.</p>");
    if ($sillas === null)
        return fn_ver_mesas($conn, "<p>Error: las sillas deben ser un entero entre 1 y " . MESAS_MAX_SILLAS . ".</p>");
    if (mesa_existe($conn, $mesa_id))
        return fn_ver_mesas($conn, "<p>Error: ya existe una mesa con el número $mesa_id.</p>");

    $res = @pg_query_params($conn, 'INSERT INTO mesas (id, sillas) VALUES ($1, $2)', array($mesa_id, $sillas));
    if ($res)
        return fn_ver_mesas($conn, "<p>Mesa $mesa_id registrada correctamente con $sillas sillas.</p>");

    return fn_ver_mesas($conn, "<p>Error al guardar la mesa: " . error_bd($conn) . "</p>");
}

function fn_editar_mesa($conn) {
    $mesa_id = mesa_validar_entero('mesa_id', 1, 2147483647);
    if ($mesa_id === null || !mesa_existe($conn, $mesa_id))
        return fn_ver_mesas($conn, "<p>Error: la mesa indicada no existe.</p>");

    if (isset($_REQUEST['sillas'])) {
        $sillas = mesa_validar_entero('sillas', 1, MESAS_MAX_SILLAS);
        if ($sillas === null) {
            $mensaje = "<p>Error: las sillas deben ser un entero entre 1 y " . MESAS_MAX_SILLAS . ".</p>";
        } else {
            $res = @pg_query_params($conn, 'UPDATE mesas SET sillas = $1 WHERE id = $2', array($sillas, $mesa_id));
            if ($res)
                return fn_ver_mesas($conn, "<p>Mesa $mesa_id actualizada correctamente: ahora tiene $sillas sillas.</p>");
            $mensaje = "<p>Error al actualizar la mesa: " . error_bd($conn) . "</p>";
        }
    } else
        $mensaje = "";

    $resultado = procesar_query("SELECT id, sillas FROM mesas WHERE id = $mesa_id", $conn);
    $mesa = $resultado->datos[0];

    $html = fn_boton_menu_principal();
    $html .= "<h2>Modificar la mesa " . $mesa['id'] . "</h2>";
    $html .= $mensaje;
    $html .= "<form method='post' action='./'>"
           . "<input type='hidden' name='opcion' value='editar_mesa'>"
           . "<input type='hidden' name='mesa_id' value='" . $mesa['id'] . "'>"
           . "<label>Sillas:</label> <input type='number' name='sillas' min='1' max='" . MESAS_MAX_SILLAS . "' value='" . $mesa['sillas'] . "' required>"
           . "<button type='submit'>Guardar cambios</button>"
           . "</form>";
    $html .= "<a href='?opcion=ver_mesas'>Volver a las mesas</a>";

    return $html;
}

function fn_eliminar_mesa($conn) {
    $mesa_id = mesa_validar_entero('mesa_id', 1, 2147483647);
    if ($_SERVER['REQUEST_METHOD'] != 'POST')
        return fn_ver_mesas($conn, "<p>Error: use el botón Eliminar de la tabla para borrar una mesa.</p>");
    if ($mesa_id === null || !mesa_existe($conn, $mesa_id))
        return fn_ver_mesas($conn, "<p>Error: la mesa indicada no existe.</p>");

    // Las reservaciones se asocian a la mesa a través de sus horarios
    $resultado = procesar_query("SELECT COUNT(*) AS cantidad FROM horarios WHERE mesa_id = $mesa_id", $conn);
    $horarios = intval($resultado->datos[0]['cantidad']);
    if ($horarios > 0)
        return fn_ver_mesas($conn, "<p>No se puede eliminar la mesa $mesa_id: tiene $horarios reservación(es) asociada(s).</p>");
    if (pedido_tiene_columna($conn, 'pedidos', 'mesa_id')) {
        $resultado = procesar_query("SELECT COUNT(*) AS cantidad FROM pedidos WHERE mesa_id = $mesa_id", $conn);
        $pedidos = intval($resultado->datos[0]['cantidad']);
        if ($pedidos > 0)
            return fn_ver_mesas($conn, "<p>No se puede eliminar la mesa $mesa_id: tiene $pedidos pedido(s) asociado(s).</p>");
    }

    $res = @pg_query_params($conn, 'DELETE FROM mesas WHERE id = $1', array($mesa_id));
    if ($res)
        return fn_ver_mesas($conn, "<p>Mesa $mesa_id eliminada correctamente.</p>");

    return fn_ver_mesas($conn, "<p>Error al eliminar la mesa: " . error_bd($conn) . "</p>");
}

function fn_buscar_platos($conn) {
    $html = fn_boton_menu_principal();
    $html .= "<h2>Platos con precio máximo</h2>";

    if (!isset($_REQUEST['precio_max'])) {
        $html .= "<form method='get'>"
               . "<input type='hidden' name='opcion' value='buscar_platos'>"
               . "<label>Muestra los platos que cuestan igual o menos que: $</label>"
               . "<input type='number' name='precio_max'>"
               . "<button type='submit'>Ver platos</button>"
               . "</form>";
    } else {
        $precio = intval($_REQUEST['precio_max']);
        $sentencia = "SELECT nombre, descripcion, precio FROM platos WHERE activo AND precio <= $precio ORDER BY precio";
        $resultado = procesar_query($sentencia, $conn);

        $html .= "<p>Platos de hasta $" . $precio . "</p>";

        if ($resultado->cantidad == 0) {
            $html .= "<p>No hay platos con ese precio o menos</p>";
        } else {
            $html .= "<table><tr><th>Nombre</th><th>Descripcion</th><th>Precio</th></tr>";
            foreach ($resultado->datos as $plato) {
                $html .= "<tr><td>" . $plato['nombre'] . "</td><td>" . $plato['descripcion'] . "</td><td>$" . $plato['precio'] . "</td></tr>";
            }
            $html .= "</table>";
        }
    }

    return $html;
}

?>
