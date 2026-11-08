<?php
/*------------------------------------------------------------------*/
// Preparación de platos con autorización de cocineros.
// Permite que:
// 1. El Administrador gestione (ver, autorizar, revocar) los platos
//    que cada cocinero está capacitado para preparar.
// 2. El Cocinero consulte su cola de preparación filtrada y ordenada
//    por tiempo de preparación (los más demorados primero) y luego
//    por hora del pedido, tome ítems disponibles y los marque como preparados.
/*------------------------------------------------------------------*/

/**
 * @brief Limpia el mensaje de error retornado por PostgreSQL.
 * @param string $error_pg Mensaje de pg_last_error().
 * @return string Mensaje limpio para el usuario.
 */
function cocina_limpiar_error($error_pg)
{
    if (preg_match('/ERROR:\s*(.*?)(?:\n|CONTEXT:|$)/s', $error_pg, $matches)) {
        return trim($matches[1]);
    }
    return trim($error_pg);
}

/**
 * @brief Obtiene el listado de usuarios con rol de Cocinero.
 */
function cocina_listar_cocineros($conn)
{
    $sql = "SELECT u.id, u.nombre
            FROM usuarios u
            JOIN actuaciones a ON a.usuario_id = u.id
            JOIN roles r ON r.id = a.rol_id
            WHERE r.nombre = 'Cocinero' AND u.activo
            ORDER BY u.nombre";
    return procesar_query($sql, $conn);
}

/**
 * @brief Cocinero con el que se trabaja: un cocinero solo ve y prepara
 *        su propia cola; el administrador puede elegir cualquiera.
 */
function cocina_cocinero_actual($cocineros)
{
    if (!sesion_es_admin())
        return sesion_id();
    $cocinero_id = isset($_REQUEST['cocinero_id']) ? intval($_REQUEST['cocinero_id']) : 0;
    if ($cocinero_id == 0 && sesion_tiene_rol('Cocinero'))
        $cocinero_id = sesion_id();
    if ($cocinero_id == 0 && $cocineros->cantidad > 0)
        $cocinero_id = intval($cocineros->datos[0]['id']);
    return $cocinero_id;
}

/*------------------------------------------------------------------*/
/**
 * @brief Página del Administrador: Gestión de autorizaciones de cocineros.
 */
function fn_autorizaciones_cocina($conn, $mensaje = "")
/*--------------------------------------------------------------------*/
{
    $cocineros = cocina_listar_cocineros($conn);
    $cocinero_id = isset($_REQUEST['cocinero_id']) ? intval($_REQUEST['cocinero_id']) : 0;
    if ($cocinero_id == 0 && $cocineros->cantidad > 0) {
        $cocinero_id = intval($cocineros->datos[0]['id']);
    }

    $html = fn_boton_menu_principal();
    $scr_cocina = "window.open('?opcion=cocina&cocinero_id=" . $cocinero_id . "', '_top');";
    $html .= "<button onClick=\"$scr_cocina\">Ver cocina</button>";
    $html .= "<h2>Gestión de autorizaciones de cocina (Administrador)</h2>";
    $html .= $mensaje;

    // Selector de cocinero
    $html .= "<form method='get' action='./' style='margin-bottom: 20px;'>";
    $html .= "<input type='hidden' name='opcion' value='autorizaciones_cocina'>";
    $html .= "<label><strong>Seleccione el Cocinero:</strong></label> ";
    $html .= "<select name='cocinero_id' onchange='this.form.submit()'>";
    foreach ($cocineros->datos as $c) {
        $sel = ($c['id'] == $cocinero_id) ? " selected" : "";
        $html .= "<option value='" . $c['id'] . "'$sel>" . htmlspecialchars($c['nombre']) . "</option>";
    }
    $html .= "</select> ";
    $html .= "<button type='submit'>Consultar</button>";
    $html .= "</form>";

    if ($cocinero_id > 0) {
        // Nombre del cocinero actual
        $nombre_cocinero = "";
        foreach ($cocineros->datos as $c) {
            if ($c['id'] == $cocinero_id) {
                $nombre_cocinero = $c['nombre'];
                break;
            }
        }

        // Consultar platos actualmente autorizados
        $sql_auth = "SELECT a.id AS auth_id, p.id AS plato_id, p.nombre, p.tiempo, p.precio, 
                            COALESCE(p.es_especial, FALSE) AS es_especial,
                            t.nombre AS tipo,
                            to_char(a.fecha_autorizacion, 'YYYY-MM-DD HH24:MI') AS fecha_autorizacion
                     FROM autorizaciones a
                     JOIN platos p ON p.id = a.plato_id
                     LEFT JOIN tipos t ON t.id = p.tipo_id
                     WHERE a.cocinero_id = $cocinero_id
                     ORDER BY p.nombre";
        $autorizados = procesar_query($sql_auth, $conn);

        $html .= "<h3>Platos autorizados para: " . htmlspecialchars($nombre_cocinero) . " (" . $autorizados->cantidad . ")</h3>";

        if ($autorizados->cantidad == 0) {
            $html .= "<p>Este cocinero aún no tiene platos autorizados.</p>";
        } else {
            $html .= "<table style='margin: 0 auto 25px auto;'>";
            $html .= "<tr><th>Plato</th><th>Tipo</th><th>Tiempo</th><th>Especial</th><th>Fecha Autorización</th><th>Acción</th></tr>";
            foreach ($autorizados->datos as $fila) {
                $tiempo = !empty($fila['tiempo']) ? $fila['tiempo'] : "N/D";
                $especial = ($fila['es_especial'] == 't' || $fila['es_especial'] === true) ? "<strong style='color:red;'>⭐ Especial</strong>" : "Normal";
                
                $form_revocar = "<form method='post' action='./' style='display:inline;' onSubmit=\"return confirm('¿Revocar autorización para " . htmlspecialchars($fila['nombre']) . "?');\">"
                              . "<input type='hidden' name='opcion' value='revocar_autorizacion'>"
                              . "<input type='hidden' name='cocinero_id' value='$cocinero_id'>"
                              . "<input type='hidden' name='plato_id' value='" . $fila['plato_id'] . "'>"
                              . "<button type='submit'>Revocar</button>"
                              . "</form>";

                $html .= "<tr>"
                       . "<td>" . htmlspecialchars($fila['nombre']) . "</td>"
                       . "<td>" . htmlspecialchars($fila['tipo']) . "</td>"
                       . "<td>" . htmlspecialchars($tiempo) . "</td>"
                       . "<td>$especial</td>"
                       . "<td>" . htmlspecialchars($fila['fecha_autorizacion']) . "</td>"
                       . "<td>$form_revocar</td>"
                       . "</tr>";
            }
            $html .= "</table>";
        }

        // Formulario para autorizar un nuevo plato
        $sql_disponibles = "SELECT p.id, p.nombre, COALESCE(p.es_especial, FALSE) AS es_especial, t.nombre AS tipo
                            FROM platos p
                            LEFT JOIN tipos t ON t.id = p.tipo_id
                            WHERE p.id NOT IN (
                                SELECT plato_id FROM autorizaciones WHERE cocinero_id = $cocinero_id
                            )
                            ORDER BY p.es_especial DESC, p.nombre";
        $disponibles = procesar_query($sql_disponibles, $conn);

        $html .= "<h3>Autorizar nuevo plato a " . htmlspecialchars($nombre_cocinero) . "</h3>";
        if ($disponibles->cantidad == 0) {
            $html .= "<p>El cocinero ya tiene autorizados todos los platos del menú.</p>";
        } else {
            $html .= "<form method='post' action='./' style='margin: 15px auto;'>";
            $html .= "<input type='hidden' name='opcion' value='autorizar_plato'>";
            $html .= "<input type='hidden' name='cocinero_id' value='$cocinero_id'>";
            $html .= "<label>Plato a autorizar:</label> ";
            $html .= "<select name='plato_id' required>";
            $html .= "<option value=''>-- Seleccione un plato --</option>";
            foreach ($disponibles->datos as $d) {
                $marca_especial = ($d['es_especial'] == 't' || $d['es_especial'] === true) ? " ⭐ [PLATO ESPECIAL]" : "";
                $html .= "<option value='" . $d['id'] . "'>" . htmlspecialchars($d['nombre']) . " (" . htmlspecialchars($d['tipo']) . ")" . $marca_especial . "</option>";
            }
            $html .= "</select> ";
            $html .= "<button type='submit'>Autorizar plato</button>";
            $html .= "</form>";
        }
    }

    return $html;
}

/**
 * @brief Procesa la autorización de un plato para un cocinero.
 */
function fn_autorizar_plato($conn)
{
    $cocinero_id = isset($_REQUEST['cocinero_id']) ? intval($_REQUEST['cocinero_id']) : 0;
    $plato_id = isset($_REQUEST['plato_id']) ? intval($_REQUEST['plato_id']) : 0;

    if ($cocinero_id <= 0 || $plato_id <= 0) {
        return fn_autorizaciones_cocina($conn, "<p>Error: Debe seleccionar un cocinero y un plato válidos.</p>");
    }

    $res = @pg_query_params($conn, 
        "INSERT INTO autorizaciones (cocinero_id, plato_id, fecha_autorizacion) VALUES ($1, $2, CURRENT_TIMESTAMP)",
        array($cocinero_id, $plato_id)
    );

    if ($res) {
        $p_info = procesar_query("SELECT nombre FROM platos WHERE id = $plato_id", $conn);
        $nom_plato = ($p_info->cantidad > 0) ? $p_info->datos[0]['nombre'] : "Plato $plato_id";
        return fn_autorizaciones_cocina($conn, "<p style='color:green;'>Plato «" . htmlspecialchars($nom_plato) . "» autorizado correctamente.</p>");
    } else {
        $error = cocina_limpiar_error(pg_last_error($conn));
        return fn_autorizaciones_cocina($conn, "<p style='color:red;'>Error al autorizar plato: " . htmlspecialchars($error) . "</p>");
    }
}

/**
 * @brief Revoca la autorización de un plato a un cocinero.
 */
function fn_revocar_autorizacion($conn)
{
    $cocinero_id = isset($_REQUEST['cocinero_id']) ? intval($_REQUEST['cocinero_id']) : 0;
    $plato_id = isset($_REQUEST['plato_id']) ? intval($_REQUEST['plato_id']) : 0;

    if ($cocinero_id <= 0 || $plato_id <= 0) {
        return fn_autorizaciones_cocina($conn, "<p>Error: Parámetros inválidos para revocar autorización.</p>");
    }

    // Verificar si tiene ítems en preparación de ese plato actualmente
    $en_proc = procesar_query("SELECT COUNT(*) AS cant FROM ordenes WHERE cocinero_id = $cocinero_id AND plato_id = $plato_id AND estado = 1", $conn);
    if ($en_proc->cantidad > 0 && intval($en_proc->datos[0]['cant']) > 0) {
        return fn_autorizaciones_cocina($conn, "<p style='color:red;'>No se puede revocar: el cocinero tiene actualmente " . $en_proc->datos[0]['cant'] . " orden(es) en preparación de este plato.</p>");
    }

    $res = @pg_query_params($conn,
        "DELETE FROM autorizaciones WHERE cocinero_id = $1 AND plato_id = $2",
        array($cocinero_id, $plato_id)
    );

    if ($res) {
        return fn_autorizaciones_cocina($conn, "<p style='color:green;'>Autorización revocada correctamente.</p>");
    } else {
        $error = cocina_limpiar_error(pg_last_error($conn));
        return fn_autorizaciones_cocina($conn, "<p style='color:red;'>Error al revocar autorización: " . htmlspecialchars($error) . "</p>");
    }
}

/*------------------------------------------------------------------*/
/**
 * @brief Página del Cocinero: Cola de preparación y despacho de platos.
 */
function fn_cocina($conn, $mensaje = "")
/*--------------------------------------------------------------------*/
{
    $cocineros = cocina_listar_cocineros($conn);
    $cocinero_id = cocina_cocinero_actual($cocineros);

    $nombre_cocinero = "";
    foreach ($cocineros->datos as $c) {
        if ($c['id'] == $cocinero_id) {
            $nombre_cocinero = $c['nombre'];
            break;
        }
    }

    $html = fn_boton_menu_principal();
    if (sesion_es_admin()) {
        $scr_auth = "window.open('?opcion=autorizaciones_cocina&cocinero_id=" . $cocinero_id . "', '_top');";
        $html .= "<button onClick=\"$scr_auth\">Gestionar autorizaciones</button>";
    }
    $html .= "<h2>Cocina - Preparación de platos</h2>";
    $html .= $mensaje;
    // Se actualiza sola cada 30 s para mostrar los pedidos nuevos
    $html .= "<script>setTimeout(function () { if (!document.querySelector('form:focus-within')) window.location.href = '?opcion=cocina&cocinero_id=$cocinero_id'; }, 30000);</script>";

    // Selector de cocinero activo (solo el administrador cambia de cocinero)
    if (sesion_es_admin()) {
    $html .= "<form method='get' action='./' style='margin-bottom: 20px;'>";
    $html .= "<input type='hidden' name='opcion' value='cocina'>";
    $html .= "<label><strong>Cocinero activo:</strong></label> ";
    $html .= "<select name='cocinero_id' onchange='this.form.submit()'>";
    foreach ($cocineros->datos as $c) {
        $sel = ($c['id'] == $cocinero_id) ? " selected" : "";
        $html .= "<option value='" . $c['id'] . "'$sel>" . htmlspecialchars($c['nombre']) . "</option>";
    }
    $html .= "</select> ";
    $html .= "<button type='submit'>Cambiar</button>";
    $html .= "</form>";
    }

    if ($cocinero_id > 0) {
        // Consultar la cola del cocinero usando la función de BD cola_cocinero()
        $sentencia = "SELECT orden_id, pedido_id, plato_id, plato_nombre, es_especial, 
                             tiempo_preparacion, to_char(solicitado, 'YYYY-MM-DD HH24:MI:SS') AS solicitado,
                             cantidad, estado, cocinero_id, cocinero_nombre,
                             to_char(hora_tomado, 'HH24:MI:SS') AS hora_tomado
                      FROM cola_cocinero($cocinero_id)";
        $cola = procesar_query($sentencia, $conn);

        // Separar entre ítems libres para tomar e ítems que ya fueron tomados por este cocinero
        $pendientes_libres = array();
        $en_preparacion_mios = array();

        foreach ($cola->datos as $item) {
            if (empty($item['cocinero_id'])) {
                $pendientes_libres[] = $item;
            } elseif ($item['cocinero_id'] == $cocinero_id && $item['estado'] == 1) {
                $en_preparacion_mios[] = $item;
            }
        }

        // 1. SECCIÓN: Ítems que tomé y estoy preparando
        $html .= "<h3>Mis platos en preparación (tomados por " . htmlspecialchars($nombre_cocinero) . ")</h3>";
        if (count($en_preparacion_mios) == 0) {
            $html .= "<p>No tienes platos en preparación en este momento. Toma uno de la cola de abajo.</p>";
        } else {
            $html .= "<table style='margin: 0 auto 25px auto;'>";
            $html .= "<tr><th>Orden #</th><th>Pedido #</th><th>Plato</th><th>Cantidad</th><th>Hora de Toma</th><th>Acción</th></tr>";
            foreach ($en_preparacion_mios as $m) {
                $marca_esp = ($m['es_especial'] == 't' || $m['es_especial'] === true) ? " ⭐" : "";
                $form_preparar = "<form method='post' action='./' style='display:inline;'>"
                               . "<input type='hidden' name='opcion' value='marcar_preparada'>"
                               . "<input type='hidden' name='cocinero_id' value='$cocinero_id'>"
                               . "<input type='hidden' name='orden_id' value='" . $m['orden_id'] . "'>"
                               . "<button type='submit' style='background-color:#d4edda;font-weight:bold;'>✓ Marcar como Preparado</button>"
                               . "</form>";
                $html .= "<tr>"
                       . "<td>" . $m['orden_id'] . "</td>"
                       . "<td>" . $m['pedido_id'] . "</td>"
                       . "<td>" . htmlspecialchars($m['plato_nombre']) . $marca_esp . "</td>"
                       . "<td>" . $m['cantidad'] . "</td>"
                       . "<td>" . $m['hora_tomado'] . "</td>"
                       . "<td>$form_preparar</td>"
                       . "</tr>";
            }
            $html .= "</table>";
        }

        // 2. SECCIÓN: Cola de platos pendientes autorizados (ordenados: más demorados primero, luego hora pedido)
        $html .= "<h3>Cola de platos disponibles para preparar</h3>";
        $html .= "<p><em>Ordenados por tiempo de preparación descendente (los más demorados primero) y luego por hora del pedido.</em></p>";
        if (count($pendientes_libres) == 0) {
            $html .= "<p>No hay platos pendientes en la cola que estés autorizado a preparar.</p>";
        } else {
            $html .= "<table style='margin: 0 auto 25px auto;'>";
            $html .= "<tr><th>Orden #</th><th>Pedido #</th><th>Plato</th><th>Tiempo Prep.</th><th>Hora Pedido</th><th>Cant.</th><th>Acción</th></tr>";
            foreach ($pendientes_libres as $p) {
                $marca_esp = ($p['es_especial'] == 't' || $p['es_especial'] === true) ? " <span style='color:red;'>⭐ Especial</span>" : "";
                $form_tomar = "<form method='post' action='./' style='display:inline;'>"
                            . "<input type='hidden' name='opcion' value='tomar_orden'>"
                            . "<input type='hidden' name='cocinero_id' value='$cocinero_id'>"
                            . "<input type='hidden' name='orden_id' value='" . $p['orden_id'] . "'>"
                            . "<button type='submit' style='background-color:#cfe2ff;font-weight:bold;'>🍳 Tomar ítem</button>"
                            . "</form>";
                $html .= "<tr>"
                       . "<td>" . $p['orden_id'] . "</td>"
                       . "<td>" . $p['pedido_id'] . "</td>"
                       . "<td>" . htmlspecialchars($p['plato_nombre']) . $marca_esp . "</td>"
                       . "<td>" . $p['tiempo_preparacion'] . "</td>"
                       . "<td>" . $p['solicitado'] . "</td>"
                       . "<td>" . $p['cantidad'] . "</td>"
                       . "<td>$form_tomar</td>"
                       . "</tr>";
            }
            $html .= "</table>";
        }

        // 3. SECCIÓN: Historial reciente de platos preparados por este cocinero
        $sql_hist = "SELECT o.id AS orden_id, o.pedido_id, p.nombre AS plato_nombre, o.cantidad,
                            to_char(o.hora_tomado, 'HH24:MI:SS') AS hora_tomado,
                            to_char(o.hora_terminado, 'HH24:MI:SS') AS hora_terminado
                     FROM ordenes o
                     JOIN platos p ON p.id = o.plato_id
                     WHERE o.cocinero_id = $cocinero_id AND o.estado IN (2, 3)
                     ORDER BY o.hora_terminado DESC NULLS LAST
                     LIMIT 5";
        $hist = procesar_query($sql_hist, $conn);
        if ($hist->cantidad > 0) {
            $html .= "<h3>Últimos platos preparados por ti</h3>";
            $html .= "<table style='margin: 0 auto;'>";
            $html .= "<tr><th>Orden #</th><th>Pedido #</th><th>Plato</th><th>Cantidad</th><th>Tomado</th><th>Terminado</th></tr>";
            foreach ($hist->datos as $h) {
                $html .= "<tr>"
                       . "<td>" . $h['orden_id'] . "</td>"
                       . "<td>" . $h['pedido_id'] . "</td>"
                       . "<td>" . htmlspecialchars($h['plato_nombre']) . "</td>"
                       . "<td>" . $h['cantidad'] . "</td>"
                       . "<td>" . $h['hora_tomado'] . "</td>"
                       . "<td>" . $h['hora_terminado'] . "</td>"
                       . "</tr>";
            }
            $html .= "</table>";
        }
    }

    return $html;
}

/**
 * @brief Procesa la toma de una orden por parte de un cocinero.
 */
function fn_tomar_orden($conn)
{
    $cocinero_id = cocina_cocinero_actual(cocina_listar_cocineros($conn));
    $orden_id = isset($_REQUEST['orden_id']) ? intval($_REQUEST['orden_id']) : 0;

    if ($cocinero_id <= 0 || $orden_id <= 0) {
        return fn_cocina($conn, "<p style='color:red;'>Error: Datos inválidos para tomar la orden.</p>");
    }

    // Iniciar transacción para el bloqueo de fila y ejecución de función
    pg_query($conn, "BEGIN");
    $res = @pg_query_params($conn, "SELECT tomar_orden($1, $2)", array($orden_id, $cocinero_id));

    if ($res) {
        pg_query($conn, "COMMIT");
        return fn_cocina($conn, "<p style='color:green;'>¡Has tomado la orden #$orden_id con éxito! Aparece ahora en tu lista de platos en preparación.</p>");
    } else {
        $error = cocina_limpiar_error(pg_last_error($conn));
        pg_query($conn, "ROLLBACK");
        return fn_cocina($conn, "<p style='color:red;'><strong>No se pudo tomar la orden:</strong> " . htmlspecialchars($error) . "</p>");
    }
}

/**
 * @brief Procesa el marcado de una orden como Preparado.
 */
function fn_marcar_preparada($conn)
{
    $cocinero_id = cocina_cocinero_actual(cocina_listar_cocineros($conn));
    $orden_id = isset($_REQUEST['orden_id']) ? intval($_REQUEST['orden_id']) : 0;

    if ($cocinero_id <= 0 || $orden_id <= 0) {
        return fn_cocina($conn, "<p style='color:red;'>Error: Datos inválidos para marcar la orden.</p>");
    }

    pg_query($conn, "BEGIN");
    $res = @pg_query_params($conn, "SELECT marcar_orden_preparada($1, $2)", array($orden_id, $cocinero_id));

    if ($res) {
        pg_query($conn, "COMMIT");
        return fn_cocina($conn, "<p style='color:green;'>Orden #$orden_id marcada como «Preparado» exitosamente.</p>");
    } else {
        $error = cocina_limpiar_error(pg_last_error($conn));
        pg_query($conn, "ROLLBACK");
        return fn_cocina($conn, "<p style='color:red;'><strong>Error al marcar la orden:</strong> " . htmlspecialchars($error) . "</p>");
    }
}
?>