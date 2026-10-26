<?php

function fn_ver_mesas($conn) {
    $sentencia = "SELECT id, sillas FROM mesas ORDER BY id";
    $resultado = procesar_query($sentencia, $conn);
    
    $html = fn_boton_menu_principal();
    $html .= "<h2>Platos con precio máximo</h2>";
    $html .= "<p>Muestra los platos que cuestan igual o menos que: $</p>";
    
    $html .= "<form method='get'>";
    $html .= "<input type='hidden' name='opcion' value='buscar_platos'>";
    $html .= "<label>Muestra los platos que cuestan igual o menos que: $</label>";
    $html .= "<input type='number' name='precio_max'>";
    $html .= "<button type='submit'>Ver platos</button>";
    $html .= "</form>";
    
    if (!isset($_REQUEST['precio_max'])) {
        return $html;
    }
    
    $precio = intval($_REQUEST['precio_max']);
    $sentencia = "SELECT nombre, descripcion, precio FROM platos WHERE precio <= $precio ORDER BY precio";
    $resultado = procesar_query($sentencia, $conn);
    
    if ($resultado->cantidad == 0) {
        $html .= "<p>No hay platos con ese precio o menos</p>";
    } else {
        $html .= "<table><tr><th>Nombre</th><th>Descripción</th><th>Precio</th></tr>";
        
        foreach ($resultado->datos as $plato) {
            $html .= "<tr><td>" . $plato['nombre'] . "</td><td>" . $plato['descripcion'] . "</td><td>$" . $plato['precio'] . "</td></tr>";
        }
        
        $html .= "</table>";
    }
    
    return $html;
}

?>
