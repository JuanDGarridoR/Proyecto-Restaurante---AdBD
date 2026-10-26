<?php

function fn_agregar_plato($conn) {
    $html = fn_boton_menu_principal();
    $html .= "<h2>Agregar un plato nuevo al menú</h2>";

    if (!isset($_REQUEST['nombre'])) {
        $html .= "<form method='post'>";
        $html .= "<input type='hidden' name='opcion' value='agregar_plato'>";
        $html .= "<label>Nombre:</label> <input type='text' name='nombre' required>";
        $html .= "<label>Descripción:</label> <input type='text' name='descripcion'>";
        $html .= "<label>Precio:</label> <input type='number' name='precio' required>";
        $html .= "<label>Tipo:</label> <select name='tipo_id'>";
        $sentencia = "SELECT id, nombre FROM tipos ORDER BY id";
        $resultado = procesar_query($sentencia, $conn);
        foreach ($resultado->datos as $tipo) {
            $html .= "<option value='" . $tipo['id'] . "'>" . $tipo['nombre'] . "</option>";
        }
        $html .= "</select>";
        $html .= "<button type='submit'>Guardar plato</button>";
        $html .= "</form>";
    } else {
        $res = pg_query_params($conn, 'INSERT INTO platos (nombre, descripcion, precio, tipo_id) VALUES ($1, $2, $3, $4)', array($_REQUEST['nombre'], $_REQUEST['descripcion'], intval($_REQUEST['precio']), intval($_REQUEST['tipo_id'])));
        if ($res) {
            $html .= "<p>Plato agregado correctamente</p>";
            $html .= "<a href='?opcion=desplegar_menu'>Ver el menú</a>";
        } else {
            $html .= "<p>Error al guardar: </p>";
            $html .= pg_last_error($conn);
        }
    }

    return $html;
}

?>
