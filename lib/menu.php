<?php
/*------------------------------------------------------------------*/
// Gestión del menú (Administrador).
// Cada ítem tiene nombre, descripción, precio, tiempo de preparación y
// categoría (tabla tipos: entrada, plato fuerte, postre, bebida...).
// Un plato que ya se pidió alguna vez no se borra: se retira del menú
// (activo = false) para conservar el historial de pedidos y ventas.
/*------------------------------------------------------------------*/

/**
 * @brief Lee y valida los datos del formulario de plato.
 * @param array $errores Recibe los mensajes de los datos inválidos.
 */
function menu_leer_formulario($conn, &$errores)
{
    $errores = array();
    $datos = array();
    $datos['nombre'] = isset($_REQUEST['nombre']) ? trim($_REQUEST['nombre']) : "";
    $datos['descripcion'] = isset($_REQUEST['descripcion']) ? trim($_REQUEST['descripcion']) : "";
    if ($datos['nombre'] == "" || preg_match_all("/./us", $datos['nombre']) > 100)
        $errores[] = "El nombre es obligatorio (máximo 100 caracteres).";

    $datos['precio'] = mesa_validar_entero('precio', 1, 100000000);
    if ($datos['precio'] === null)
        $errores[] = "El precio debe ser un entero mayor que cero.";

    $datos['minutos'] = mesa_validar_entero('minutos', 1, 600);
    if ($datos['minutos'] === null)
        $errores[] = "El tiempo de preparación debe estar entre 1 y 600 minutos.";

    $datos['tipo_id'] = mesa_validar_entero('tipo_id', 1, 2147483647);
    if ($datos['tipo_id'] === null
        || count(reserva_consulta($conn, 'SELECT 1 FROM tipos WHERE id = $1', array($datos['tipo_id']))) == 0)
        $errores[] = "Seleccione una categoría válida.";

    $datos['es_especial'] = isset($_REQUEST['es_especial']) ? 't' : 'f';
    $datos['activo'] = isset($_REQUEST['activo']) ? 't' : 'f';
    return $datos;
}

/**
 * @brief Formulario para crear o modificar un plato.
 */
function menu_formulario($conn, $valores, $titulo, $boton)
{
    $valor = function ($campo) use ($valores) {
        return isset($valores[$campo]) ? htmlspecialchars($valores[$campo], ENT_QUOTES) : "";
    };
    $marcado = function ($campo, $omision) use ($valores) {
        if (!isset($valores[$campo]))
            return $omision ? " checked" : "";
        return in_array($valores[$campo], array('t', 'on', '1', true), true) ? " checked" : "";
    };

    $html = "<h2>$titulo</h2>"
          . "<form method='post' action='./'>"
          . "<input type='hidden' name='opcion' value='guardar_plato'>";
    if (isset($valores['plato_id']) && $valores['plato_id'] != "")
        $html .= "<input type='hidden' name='plato_id' value='" . $valor('plato_id') . "'>";

    $html .= "<label>Nombre:</label> <input type='text' name='nombre' maxlength='100' value='" . $valor('nombre') . "' required>"
           . "<label>Descripción:</label> <input type='text' name='descripcion' value='" . $valor('descripcion') . "'>"
           . "<label>Precio:</label> <input type='number' name='precio' min='1' value='" . $valor('precio') . "' required>"
           . "<label>Tiempo de preparación (min):</label> <input type='number' name='minutos' min='1' max='600' value='" . $valor('minutos') . "' required>"
           . "<label>Categoría:</label> <select name='tipo_id' required><option value=''></option>";
    foreach (procesar_query("SELECT id, nombre FROM tipos ORDER BY id", $conn)->datos as $tipo) {
        $sel = ($valor('tipo_id') == $tipo['id']) ? " selected" : "";
        $html .= "<option value='" . $tipo['id'] . "'$sel>" . htmlspecialchars($tipo['nombre']) . "</option>";
    }
    $html .= "</select>"
           . "<label><input type='checkbox' name='es_especial'" . $marcado('es_especial', false) . "> Plato especial (solo chefs)</label>"
           . "<label><input type='checkbox' name='activo'" . $marcado('activo', true) . "> Disponible en el menú</label>"
           . "<button type='submit'>$boton</button>"
           . "</form>";
    return $html;
}

/*------------------------------------------------------------------*/
/**
 * @brief Página de gestión del menú: listado de ítems y formulario.
 */
function fn_gestionar_menu($conn, $mensaje = "", $formulario = null)
/*--------------------------------------------------------------------*/
{
    $platos = procesar_query("
        SELECT p.id, p.nombre, p.descripcion, p.precio, p.es_especial, p.activo,
               EXTRACT(EPOCH FROM p.tiempo)::int / 60 AS minutos,
               t.nombre AS tipo,
               (SELECT COUNT(*) FROM ordenes o WHERE o.plato_id = p.id) AS pedidos,
               (SELECT COUNT(*) FROM autorizaciones a WHERE a.plato_id = p.id) AS cocineros
        FROM platos p
        LEFT JOIN tipos t ON t.id = p.tipo_id
        ORDER BY p.activo DESC, t.id, p.nombre", $conn);

    $html = fn_boton_menu_principal()
          . "<button onClick=\"window.open('?opcion=autorizaciones_cocina', '_top');\">Autorizaciones de cocina</button>"
          . "<h2>Menú del restaurante</h2>"
          . $mensaje;

    $html .= "<table><tr><th>Plato</th><th>Categoría</th><th>Precio</th><th>Tiempo</th><th>Especial</th><th>Cocineros</th><th>Pedidos</th><th>Estado</th><th>Acciones</th></tr>";
    foreach ($platos->datos as $plato) {
        $scr_editar = "window.open('?opcion=editar_plato&plato_id=" . $plato['id'] . "', '_top');";
        $nombre = htmlspecialchars($plato['nombre'], ENT_QUOTES);
        $accion_borrar = ($plato['pedidos'] > 0) ? "Retirar" : "Eliminar";
        $acciones = "<button onClick=\"$scr_editar\">Modificar</button>";
        if ($plato['activo'] == 't' || $plato['pedidos'] == 0)
            $acciones .= "<form method='post' action='./' style='display:inline' onSubmit=\"return confirm('¿$accion_borrar «{$nombre}» del menú?');\">"
                       . "<input type='hidden' name='opcion' value='eliminar_plato'>"
                       . "<input type='hidden' name='plato_id' value='" . $plato['id'] . "'>"
                       . "<button type='submit'>$accion_borrar</button>"
                       . "</form>";
        $html .= "<tr" . ($plato['activo'] == 't' ? "" : " class='INACTIVO'") . ">"
               . "<td><strong>" . htmlspecialchars($plato['nombre']) . "</strong><br><small>" . htmlspecialchars($plato['descripcion']) . "</small></td>"
               . "<td>" . htmlspecialchars($plato['tipo']) . "</td>"
               . "<td>" . pedido_dinero($plato['precio']) . "</td>"
               . "<td>" . $plato['minutos'] . " min</td>"
               . "<td>" . ($plato['es_especial'] == 't' ? "⭐ Sí" : "No") . "</td>"
               . "<td>" . $plato['cocineros'] . "</td>"
               . "<td>" . $plato['pedidos'] . "</td>"
               . "<td>" . ($plato['activo'] == 't' ? "Disponible" : "Retirado") . "</td>"
               . "<td>$acciones</td></tr>";
    }
    $html .= "</table>";

    if ($formulario === null)
        $formulario = menu_formulario($conn, array(), "Agregar un ítem al menú", "Guardar plato");
    $html .= $formulario;

    // Categorías
    $html .= "<h2>Categorías</h2><p>";
    $tipos = procesar_query("SELECT t.nombre, COUNT(p.id) AS platos FROM tipos t LEFT JOIN platos p ON p.tipo_id = t.id AND p.activo GROUP BY t.id ORDER BY t.id", $conn);
    $nombres = array();
    foreach ($tipos->datos as $tipo)
        $nombres[] = htmlspecialchars($tipo['nombre']) . " (" . $tipo['platos'] . ")";
    $html .= implode(" · ", $nombres) . "</p>"
           . "<form method='post' action='./'>"
           . "<input type='hidden' name='opcion' value='agregar_categoria'>"
           . "<label>Nueva categoría:</label> <input type='text' name='categoria' maxlength='50' required>"
           . "<button type='submit'>Agregar categoría</button>"
           . "</form>";

    return $html;
}

// Compatibilidad con el enlace anterior «Agregar plato»
function fn_agregar_plato($conn) {
    return fn_gestionar_menu($conn);
}

function fn_editar_plato($conn) {
    $plato_id = mesa_validar_entero('plato_id', 1, 2147483647);
    $actual = ($plato_id === null) ? array() : reserva_consulta($conn, "
        SELECT id AS plato_id, nombre, descripcion, precio::bigint AS precio, tipo_id,
               EXTRACT(EPOCH FROM tiempo)::int / 60 AS minutos,
               es_especial, activo
        FROM platos WHERE id = $1", array($plato_id));
    if (!$actual)
        return fn_gestionar_menu($conn, mensaje_error("El plato indicado no existe."));

    $formulario = menu_formulario($conn, $actual[0], "Modificar «" . htmlspecialchars($actual[0]['nombre']) . "»", "Guardar cambios")
                . "<a href='?opcion=gestionar_menu'>No modificar</a>";
    return fn_gestionar_menu($conn, "", $formulario);
}

/*------------------------------------------------------------------*/
/**
 * @brief Crea o modifica un plato. Los errores de la BD (nombre repetido,
 *        plato especial autorizado a no-chefs...) se muestran al usuario.
 */
function fn_guardar_plato($conn)
/*--------------------------------------------------------------------*/
{
    if ($_SERVER['REQUEST_METHOD'] != 'POST')
        return fn_gestionar_menu($conn);

    $plato_id = mesa_validar_entero('plato_id', 1, 2147483647);
    $datos = menu_leer_formulario($conn, $errores);
    if (count($errores) == 0) {
        $parametros = array($datos['nombre'], $datos['descripcion'], $datos['precio'], $datos['minutos'],
                            $datos['tipo_id'], $datos['es_especial'], $datos['activo']);
        if ($plato_id === null) {
            $res = @pg_query_params($conn, '
                INSERT INTO platos (nombre, descripcion, precio, tiempo, tipo_id, es_especial, activo)
                VALUES ($1, $2, $3, make_interval(mins => $4), $5, $6, $7)', $parametros);
        } else {
            $parametros[] = $plato_id;
            $res = @pg_query_params($conn, '
                UPDATE platos SET nombre = $1, descripcion = $2, precio = $3, tiempo = make_interval(mins => $4),
                                  tipo_id = $5, es_especial = $6, activo = $7
                WHERE id = $8', $parametros);
        }
        if ($res) {
            $_REQUEST = array();
            return fn_gestionar_menu($conn, mensaje_ok("Plato «" . $datos['nombre'] . "» guardado correctamente."));
        }
        $error = error_bd($conn);
        if (strpos($error, 'uq_platos_nombre_activo') !== false)
            $error = "Ya existe un plato disponible con el nombre «" . $datos['nombre'] . "».";
        $errores[] = $error;
    }

    $valores = $_REQUEST;
    $titulo = ($plato_id === null) ? "Agregar un ítem al menú" : "Modificar el plato";
    $mensaje = "";
    foreach ($errores as $error)
        $mensaje .= mensaje_error($error);
    return fn_gestionar_menu($conn, $mensaje, menu_formulario($conn, $valores, $titulo, "Guardar"));
}

/*------------------------------------------------------------------*/
/**
 * @brief Elimina un plato que nunca se ha pedido; si ya tiene pedidos,
 *        lo retira del menú para conservar el historial.
 */
function fn_eliminar_plato($conn)
/*--------------------------------------------------------------------*/
{
    if ($_SERVER['REQUEST_METHOD'] != 'POST')
        return fn_gestionar_menu($conn, mensaje_error("Use el botón Eliminar de la tabla."));
    $plato_id = mesa_validar_entero('plato_id', 1, 2147483647);
    $plato = ($plato_id === null) ? array() : reserva_consulta($conn, "
        SELECT nombre, (SELECT COUNT(*) FROM ordenes WHERE plato_id = platos.id) AS pedidos
        FROM platos WHERE id = $1", array($plato_id));
    if (!$plato)
        return fn_gestionar_menu($conn, mensaje_error("El plato indicado no existe."));
    $nombre = $plato[0]['nombre'];

    if ($plato[0]['pedidos'] > 0) {
        if (!@pg_query_params($conn, 'UPDATE platos SET activo = FALSE WHERE id = $1', array($plato_id)))
            return fn_gestionar_menu($conn, mensaje_error(error_bd($conn)));
        return fn_gestionar_menu($conn, mensaje_ok("«{$nombre}» tiene pedidos registrados: se retiró del menú y se conserva en el historial."));
    }

    pg_query($conn, "BEGIN");
    $ok = @pg_query_params($conn, 'DELETE FROM especialidades WHERE plato_id = $1', array($plato_id))
       && @pg_query_params($conn, 'DELETE FROM autorizaciones WHERE plato_id = $1', array($plato_id))
       && @pg_query_params($conn, 'DELETE FROM platos WHERE id = $1', array($plato_id));
    if (!$ok) {
        $error = error_bd($conn);
        pg_query($conn, "ROLLBACK");
        return fn_gestionar_menu($conn, mensaje_error("No se pudo eliminar: $error"));
    }
    pg_query($conn, "COMMIT");
    return fn_gestionar_menu($conn, mensaje_ok("«{$nombre}» se eliminó del menú."));
}

function fn_agregar_categoria($conn) {
    $categoria = isset($_REQUEST['categoria']) ? trim($_REQUEST['categoria']) : "";
    if ($_SERVER['REQUEST_METHOD'] != 'POST' || $categoria == "")
        return fn_gestionar_menu($conn, mensaje_error("Escriba el nombre de la categoría."));
    if (!@pg_query_params($conn, 'INSERT INTO tipos (nombre) VALUES ($1)', array($categoria)))
        return fn_gestionar_menu($conn, mensaje_error("No se pudo agregar la categoría (¿ya existe?)."));
    $_REQUEST = array();
    return fn_gestionar_menu($conn, mensaje_ok("Categoría «" . $categoria . "» agregada."));
}

?>
