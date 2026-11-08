<?php
/*------------------------------------------------------------------*/
// Sistema de Notificaciones en Tiempo Real
// Gestiona avisos para:
// 1. Mesero: Notificación de PEDIDO_LISTO cuando todos los ítems están preparados.
//    Permite marcar el pedido como "Entregado" directamente desde la notificación.
// 2. Maitre: Notificación de RESERVA_PROXIMA para reservas dentro de los próximos N min.
// Soporta sondeo automático cada 20 segundos vía fetch/AJAX con JSON.
/*------------------------------------------------------------------*/

/**
 * @brief Obtiene empleados según su rol (Mesero o Maitre/Recepcionista).
 */
function notif_listar_empleados($conn, $rol_filtro = 'Mesero')
{
    $roles_sql = ($rol_filtro == 'Maitre') 
        ? "'Maitre', 'Recepcionista'" 
        : "'Mesero'";

    $sql = "SELECT DISTINCT u.id, u.nombre
            FROM usuarios u
            JOIN actuaciones a ON a.usuario_id = u.id
            JOIN roles r ON r.id = a.rol_id
            WHERE r.nombre IN ($roles_sql)
            ORDER BY u.nombre";
    return procesar_query($sql, $conn);
}

/**
 * @brief Lista las notificaciones no leídas de un empleado.
 */
function notif_consultar_no_leidas($conn, $empleado_id)
{
    $sql = "SELECT notificacion_id, tipo, referencia_id, mensaje,
                   to_char(fecha_creacion, 'HH24:MI:SS') AS hora,
                   to_char(fecha_creacion, 'YYYY-MM-DD HH24:MI') AS fecha_completa,
                   leida
            FROM listar_notificaciones_no_leidas(" . intval($empleado_id) . ")";
    return procesar_query($sql, $conn);
}

/**
 * @brief Genera el HTML de la lista de notificaciones para un empleado.
 */
function notif_render_lista_html($notificaciones, $empleado_id)
{
    if ($notificaciones->cantidad == 0) {
        return "<p style='color:#555;font-style:italic;margin:10px 0;'>No tienes notificaciones pendientes.</p>";
    }

    $html = "<div style='display:flex;flex-direction:column;gap:10px;margin-top:10px;'>";
    foreach ($notificaciones->datos as $n) {
        $es_pedido = ($n['tipo'] == 'PEDIDO_LISTO');
        $color_borde = $es_pedido ? "#28a745" : "#17a2b8";
        $icono = $es_pedido ? "🔔 <strong>[Pedido Listo]</strong>" : "📅 <strong>[Reserva Próxima]</strong>";

        $html .= "<div style='border-left: 5px solid $color_borde; background: #fdfdfd; padding: 10px 15px; border-radius: 4px; box-shadow: 0 1px 3px rgba(0,0,0,0.1); text-align: left;'>";
        $html .= "<div style='display:flex; justify-content:space-between; align-items:center;'>";
        $html .= "<span>$icono <span style='color:#666; font-size:0.85em; margin-left:8px;'>" . $n['hora'] . "</span></span>";

        // Botones de acción
        $html .= "<div style='display:flex; gap:6px;'>";
        if ($es_pedido) {
            $html .= "<button type='button' onclick=\"notifEntregarPedido(" . $n['referencia_id'] . ", $empleado_id)\" "
                   . "style='background:#28a745; color:white; font-size:0.85em; padding:5px 10px; border:none; border-radius:4px; cursor:pointer;'>📦 Marcar como Entregado</button>";
        }
        $html .= "<button type='button' onclick=\"notifMarcarLeida(" . $n['notificacion_id'] . ", $empleado_id)\" "
               . "style='background:#6c757d; color:white; font-size:0.85em; padding:5px 10px; border:none; border-radius:4px; cursor:pointer;'>✓ Leída</button>";
        $html .= "</div>";

        $html .= "</div>";
        $html .= "<div style='margin-top: 6px; font-size:1em; color:#222;'>" . htmlspecialchars($n['mensaje']) . "</div>";
        $html .= "</div>";
    }
    $html .= "</div>";

    return $html;
}

/**
 * @brief Widget integrado de notificaciones para insertar en las páginas de Mesero o Maitre.
 */
function notificaciones_widget($conn, $rol_filtro = 'Mesero', $empleado_id = null)
{
    $empleados = notif_listar_empleados($conn, $rol_filtro);
    if ($empleados->cantidad == 0) {
        return "";
    }

    if ($empleado_id === null || $empleado_id <= 0) {
        if (isset($_REQUEST['notif_empleado_id']) && intval($_REQUEST['notif_empleado_id']) > 0) {
            $empleado_id = intval($_REQUEST['notif_empleado_id']);
        } else {
            $empleado_id = intval($empleados->datos[0]['id']);
        }
    }

    $notifs = notif_consultar_no_leidas($conn, $empleado_id);
    $cantidad = $notifs->cantidad;
    $badge_display = ($cantidad > 0) ? "inline-block" : "none";

    $html = "<div id='notif-widget' style='background:#fff; border:2px solid #ddd; border-radius:8px; padding:15px; margin:15px auto; max-width:850px;'>";
    $html .= "<div style='display:flex; justify-content:space-between; align-items:center; border-bottom:1px solid #eee; padding-bottom:10px;'>";
    
    // Encabezado con Indicador de no leídas
    $html .= "<div style='font-size:1.2em; font-weight:bold; color:#1a237e;'>";
    $html .= "🔔 Notificaciones ";
    $html .= "<span id='notif-badge' style='background:#dc3545; color:#fff; font-size:0.75em; padding:2px 8px; border-radius:12px; display:$badge_display;'>";
    $html .= "<span id='notif-badge-count'>$cantidad</span> no leída(s)";
    $html .= "</span>";
    $html .= "</div>";

    // Selector de empleado
    $html .= "<div>";
    $html .= "<label style='font-size:0.9em; margin-right:5px;'><strong>$rol_filtro:</strong></label>";
    $html .= "<select id='notif_empleado_select' onchange='notifCambiarEmpleado(this.value)' style='padding:4px 8px;'>";
    foreach ($empleados->datos as $emp) {
        $sel = ($emp['id'] == $empleado_id) ? " selected" : "";
        $html .= "<option value='" . $emp['id'] . "'$sel>" . htmlspecialchars($emp['nombre']) . "</option>";
    }
    $html .= "</select>";
    $html .= "</div>";

    $html .= "</div>"; // fin cabecera

    // Contenedor de la lista dinámica
    $html .= "<div id='notif-lista-container'>";
    $html .= notif_render_lista_html($notifs, $empleado_id);
    $html .= "</div>";

    $html .= "<div style='margin-top:10px; font-size:0.8em; color:#777; text-align:right;'>";
    $html .= "Sondeo automático cada 20 segundos • <a href='javascript:void(0)' onclick='notifPollActualizar()' style='color:#007bff; text-decoration:none;'>Actualizar ahora</a>";
    $html .= "</div>";

    $html .= "</div>"; // fin widget

    // Script JavaScript para auto-actualización cada 20 segundos y acciones sin recarga
    $html .= "<script>
    var currentNotifEmpleadoId = $empleado_id;

    function notifPollActualizar() {
        if (!currentNotifEmpleadoId) return;
        fetch('?opcion=ajax_notificaciones&empleado_id=' + encodeURIComponent(currentNotifEmpleadoId))
            .then(function(response) { return response.json(); })
            .then(function(data) {
                var badge = document.getElementById('notif-badge');
                var countSpan = document.getElementById('notif-badge-count');
                var container = document.getElementById('notif-lista-container');
                if (countSpan) countSpan.innerText = data.count;
                if (badge) badge.style.display = (data.count > 0) ? 'inline-block' : 'none';
                if (container && data.html) container.innerHTML = data.html;
            })
            .catch(function(err) { console.error('Error al consultar notificaciones:', err); });
    }

    function notifCambiarEmpleado(nuevoId) {
        currentNotifEmpleadoId = nuevoId;
        notifPollActualizar();
    }

    function notifMarcarLeida(notifId, empleadoId) {
        fetch('?opcion=ajax_marcar_leida&notificacion_id=' + encodeURIComponent(notifId) + '&empleado_id=' + encodeURIComponent(empleadoId))
            .then(function(response) { return response.json(); })
            .then(function(data) {
                if (data.ok) notifPollActualizar();
            });
    }

    function notifEntregarPedido(pedidoId, empleadoId) {
        if (!confirm('¿Confirmar la entrega del pedido #' + pedidoId + '?')) return;
        fetch('?opcion=ajax_entregar_pedido&pedido_id=' + encodeURIComponent(pedidoId) + '&empleado_id=' + encodeURIComponent(empleadoId))
            .then(function(response) { return response.json(); })
            .then(function(data) {
                if (data.ok) {
                    alert('Pedido #' + pedidoId + ' marcado como Entregado.');
                    notifPollActualizar();
                    // Si estamos en la página de pedidos, recargar tabla de pedidos
                    if (window.location.search.indexOf('opcion=pedidos') !== -1) {
                        window.location.reload();
                    }
                } else {
                    alert('Error: ' + data.error);
                }
            });
    }

    // Intervalo de auto-actualización: 20 segundos (dentro del rango 15-30s)
    setInterval(notifPollActualizar, 20000);
    </script>";

    return $html;
}

/*------------------------------------------------------------------*/
/**
 * @brief Endpoint AJAX: Devuelve en JSON las notificaciones de un empleado y su HTML.
 */
function fn_ajax_notificaciones($conn)
/*--------------------------------------------------------------------*/
{
    header('Content-Type: application/json; charset=utf-8');
    $empleado_id = isset($_REQUEST['empleado_id']) ? intval($_REQUEST['empleado_id']) : 0;
    
    if ($empleado_id <= 0) {
        echo json_encode(array('ok' => false, 'count' => 0, 'error' => 'Empleado no especificado'));
        exit;
    }

    $notifs = notif_consultar_no_leidas($conn, $empleado_id);
    $html = notif_render_lista_html($notifs, $empleado_id);

    echo json_encode(array(
        'ok' => true,
        'count' => $notifs->cantidad,
        'html' => $html,
        'datos' => $notifs->datos
    ));
    exit;
}

/*------------------------------------------------------------------*/
/**
 * @brief Endpoint AJAX / POST: Marca una notificación como leída.
 */
function fn_ajax_marcar_leida($conn)
/*--------------------------------------------------------------------*/
{
    $notif_id = isset($_REQUEST['notificacion_id']) ? intval($_REQUEST['notificacion_id']) : 0;
    if ($notif_id > 0) {
        @pg_query_params($conn, "SELECT marcar_notificacion_leida($1)", array($notif_id));
    }

    if (isset($_REQUEST['ajax']) || (isset($_SERVER['HTTP_ACCEPT']) && strpos($_SERVER['HTTP_ACCEPT'], 'application/json') !== false) || isset($_REQUEST['opcion']) && $_REQUEST['opcion'] == 'ajax_marcar_leida') {
        header('Content-Type: application/json; charset=utf-8');
        echo json_encode(array('ok' => true));
        exit;
    }

    return fn_notificaciones($conn, "<p style='color:green;'>Notificación marcada como leída.</p>");
}

/*------------------------------------------------------------------*/
/**
 * @brief Endpoint AJAX / POST: Entrega un pedido desde la notificación.
 */
function fn_ajax_entregar_pedido($conn)
/*--------------------------------------------------------------------*/
{
    $pedido_id = isset($_REQUEST['pedido_id']) ? intval($_REQUEST['pedido_id']) : 0;
    $res = false;
    $error = "";

    if ($pedido_id > 0) {
        pg_query($conn, "BEGIN");
        // Actualiza las órdenes a estado = 3 (Entregado)
        $res = @pg_query_params($conn, "UPDATE ordenes SET estado = 3 WHERE pedido_id = $1", array($pedido_id));
        if ($res) {
            // El trigger trg_check_pedido_entregado ya marcó la notificación como leída,
            // pero nos aseguramos por redundancia
            @pg_query_params($conn, 
                "UPDATE notificaciones SET leida = TRUE, fecha_lectura = CURRENT_TIMESTAMP WHERE tipo = 'PEDIDO_LISTO' AND referencia_id = $1",
                array($pedido_id)
            );
            pg_query($conn, "COMMIT");
        } else {
            $error = pg_last_error($conn);
            pg_query($conn, "ROLLBACK");
        }
    }

    if (isset($_REQUEST['ajax']) || (isset($_SERVER['HTTP_ACCEPT']) && strpos($_SERVER['HTTP_ACCEPT'], 'application/json') !== false) || isset($_REQUEST['opcion']) && $_REQUEST['opcion'] == 'ajax_entregar_pedido') {
        header('Content-Type: application/json; charset=utf-8');
        echo json_encode(array('ok' => (bool)$res, 'error' => $error));
        exit;
    }

    if ($res) {
        return fn_notificaciones($conn, "<p style='color:green;'>Pedido #$pedido_id marcado como Entregado correctamente.</p>");
    } else {
        return fn_notificaciones($conn, "<p style='color:red;'>Error al entregar pedido: " . htmlspecialchars($error) . "</p>");
    }
}

/*------------------------------------------------------------------*/
/**
 * @brief Página completa del Centro de Notificaciones (accesible desde el menú).
 */
function fn_notificaciones($conn, $mensaje = "")
/*--------------------------------------------------------------------*/
{
    $html = fn_boton_menu_principal();
    $scr_pedidos = "window.open('?opcion=pedidos', '_top');";
    $scr_reservas = "window.open('?opcion=reservaciones', '_top');";
    $html .= "<button onClick=\"$scr_pedidos\">Ver Pedidos</button>";
    $html .= "<button onClick=\"$scr_reservas\">Ver Reservaciones</button>";
    $html .= "<h2>Centro de Notificaciones</h2>";
    $html .= $mensaje;

    // Botón para ejecutar manualmente la verificación de reservas próximas
    $html .= "<form method='post' action='./' style='margin:10px auto;'>";
    $html .= "<input type='hidden' name='opcion' value='ejecutar_cron_reservas'>";
    $html .= "<button type='submit' style='background:#e2e3e5;'>⏱ Verificar reservas próximas ahora (Simular Cron)</button>";
    $html .= "</form>";

    // Notificaciones para Meseros
    $html .= "<h3>Notificaciones para Meseros (Pedidos Listos)</h3>";
    $html .= notificaciones_widget($conn, 'Mesero');

    // Notificaciones para Maitre
    $html .= "<h3>Notificaciones para Maitre / Recepción (Reservas Próximas)</h3>";
    $html .= notificaciones_widget($conn, 'Maitre');

    return $html;
}

/**
 * @brief Ejecuta la función de detección de reservas próximas manualmente.
 */
function fn_ejecutar_cron_reservas($conn)
{
    $res = procesar_query("SELECT fn_notificar_reservas_proximas(30) AS cant", $conn);
    $cant = ($res->cantidad > 0) ? intval($res->datos[0]['cant']) : 0;
    return fn_notificaciones($conn, "<p style='color:green;'>Proceso ejecutado: se generaron $cant nueva(s) notificación(es) de reservas próximas.</p>");
}
?>