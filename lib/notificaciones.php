<?php
/*------------------------------------------------------------------*/
// Sistema de Notificaciones
// Gestiona avisos para:
// 1. Mesero: PEDIDO_LISTO cuando todos los platos de su pedido están
//    preparados (trigger trg_check_pedido_listo). Puede registrar la
//    entrega directamente desde la notificación.
// 2. Maitre: RESERVA_PROXIMA para reservas que empiezan en los próximos
//    30 minutos (fn_notificar_reservas_proximas).
// El widget se actualiza solo cada 20 segundos (fetch / JSON).
/*------------------------------------------------------------------*/

/**
 * @brief Obtiene empleados activos según su rol (Mesero o Maitre/Recepcionista).
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
            WHERE r.nombre IN ($roles_sql) AND u.activo
            ORDER BY u.nombre";
    return procesar_query($sql, $conn);
}

/**
 * @brief Empleado cuyas notificaciones se consultan: cada usuario ve las
 *        suyas; el administrador puede consultar las de cualquiera.
 */
function notif_empleado_permitido($empleado_id) {
    return sesion_es_admin() ? intval($empleado_id) : sesion_id();
}

/**
 * @brief Genera los avisos de reservaciones que empiezan en los próximos
 *        30 minutos. Es idempotente (no duplica avisos), así que se invoca
 *        al consultar las notificaciones del maitre en lugar de depender
 *        de una tarea programada (cron).
 */
function notif_generar_reservas_proximas($conn) {
    @pg_query($conn, "SELECT fn_notificar_reservas_proximas(30)");
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
 * @brief Genera el HTML de la lista de notificaciones de un widget.
 * @param string $uid Identificador del widget ('mesero' o 'maitre').
 */
function notif_render_lista_html($notificaciones, $uid)
{
    if ($notificaciones->cantidad == 0) {
        return "<p class='NOTIF_VACIA'>No tienes notificaciones pendientes.</p>";
    }

    $html = "<div class='NOTIF_LISTA'>";
    foreach ($notificaciones->datos as $n) {
        $es_pedido = ($n['tipo'] == 'PEDIDO_LISTO');
        $clase = $es_pedido ? "PEDIDO" : "RESERVA";
        $titulo = $es_pedido ? "🔔 <strong>Pedido listo</strong>" : "📅 <strong>Reserva próxima</strong>";

        $html .= "<div class='NOTIF $clase'>";
        $html .= "<div class='NOTIF_CABECERA'><span>$titulo <small>" . $n['hora'] . "</small></span><span>";
        if ($es_pedido) {
            $html .= "<button type='button' onclick=\"notifEntregarPedido('$uid', " . intval($n['referencia_id']) . ")\">📦 Entregar</button>";
        }
        $html .= "<button type='button' onclick=\"notifMarcarLeida('$uid', " . intval($n['notificacion_id']) . ")\">✓ Leída</button>";
        $html .= "</span></div>";
        $html .= "<div>" . htmlspecialchars($n['mensaje']) . "</div>";
        $html .= "</div>";
    }
    $html .= "</div>";

    return $html;
}

/**
 * @brief Widget de notificaciones para las páginas del Mesero o del Maitre.
 *        Puede haber varios en la misma página (uno por rol).
 */
function notificaciones_widget($conn, $rol_filtro = 'Mesero', $empleado_id = null)
{
    $empleados = notif_listar_empleados($conn, $rol_filtro);
    if ($empleados->cantidad == 0) {
        return "";
    }

    if (!sesion_es_admin()) {
        // Cada empleado ve solo sus notificaciones, si tiene el rol del widget
        $empleado_id = sesion_id();
        if (!in_array($empleado_id, array_map('intval', array_column($empleados->datos, 'id'))))
            return "";
    } elseif ($empleado_id === null || $empleado_id <= 0) {
        if (in_array(sesion_id(), array_map('intval', array_column($empleados->datos, 'id'))))
            $empleado_id = sesion_id();
        else
            $empleado_id = intval($empleados->datos[0]['id']);
    }

    if ($rol_filtro == 'Maitre')
        notif_generar_reservas_proximas($conn);
    $notifs = notif_consultar_no_leidas($conn, $empleado_id);
    $uid = ($rol_filtro == 'Maitre') ? 'maitre' : 'mesero';
    $cantidad = $notifs->cantidad;
    $badge_display = ($cantidad > 0) ? "inline-block" : "none";

    $html = "<div class='NOTIF_WIDGET' id='notif-widget-$uid'>";
    $html .= "<div class='NOTIF_ENCABEZADO'>";
    $html .= "<strong>🔔 Notificaciones " . ($uid == 'maitre' ? "de reservas" : "de pedidos") . "</strong> ";
    $html .= "<span class='NOTIF_CONTADOR' id='notif-badge-$uid' style='display:$badge_display;'>"
           . "<span id='notif-badge-count-$uid'>$cantidad</span> sin leer</span>";

    // Solo el administrador puede consultar las notificaciones de otro empleado
    if (sesion_es_admin()) {
        $html .= " <label>$rol_filtro: <select onchange=\"notifCambiarEmpleado('$uid', this.value)\">";
        foreach ($empleados->datos as $emp) {
            $sel = ($emp['id'] == $empleado_id) ? " selected" : "";
            $html .= "<option value='" . $emp['id'] . "'$sel>" . htmlspecialchars($emp['nombre']) . "</option>";
        }
        $html .= "</select></label>";
    }
    $html .= "</div>";

    $html .= "<div id='notif-lista-$uid'>" . notif_render_lista_html($notifs, $uid) . "</div>";
    $html .= "<div class='NOTIF_PIE'>Se actualiza cada 20 segundos · "
           . "<a href='javascript:void(0)' onclick=\"notifActualizar('$uid')\">Actualizar ahora</a></div>";
    $html .= "</div>";

    $html .= "<script>
    window.notifWidgets = window.notifWidgets || {};
    notifWidgets['$uid'] = { empleado: $empleado_id, rol: '$rol_filtro' };

    function notifActualizar(uid) {
        var w = notifWidgets[uid];
        fetch('?opcion=ajax_notificaciones&rol=' + encodeURIComponent(w.rol) + '&empleado_id=' + encodeURIComponent(w.empleado))
            .then(function (r) { return r.json(); })
            .then(function (data) {
                if (!data.ok) return;
                document.getElementById('notif-badge-count-' + uid).innerText = data.count;
                document.getElementById('notif-badge-' + uid).style.display = data.count > 0 ? 'inline-block' : 'none';
                document.getElementById('notif-lista-' + uid).innerHTML = data.html;
            })
            .catch(function (err) { console.error('Error al consultar notificaciones:', err); });
    }

    function notifCambiarEmpleado(uid, id) {
        notifWidgets[uid].empleado = id;
        notifActualizar(uid);
    }

    function notifMarcarLeida(uid, notifId) {
        fetch('?opcion=ajax_marcar_leida&notificacion_id=' + encodeURIComponent(notifId) + '&empleado_id=' + encodeURIComponent(notifWidgets[uid].empleado), { method: 'POST' })
            .then(function (r) { return r.json(); })
            .then(function (data) { if (data.ok) notifActualizar(uid); });
    }

    function notifEntregarPedido(uid, pedidoId) {
        if (!confirm('¿Confirmar la entrega del pedido #' + pedidoId + '?')) return;
        fetch('?opcion=ajax_entregar_pedido&pedido_id=' + encodeURIComponent(pedidoId), { method: 'POST' })
            .then(function (r) { return r.json(); })
            .then(function (data) {
                if (!data.ok) { alert('Error: ' + data.error); return; }
                if (window.location.search.indexOf('opcion=pedidos') !== -1) window.location.reload();
                else notifActualizar(uid);
            });
    }

    setInterval(function () { notifActualizar('$uid'); }, 20000);
    </script>";

    return $html;
}

function notif_responder_json($datos) {
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode($datos);
    exit;
}

/*------------------------------------------------------------------*/
/**
 * @brief Endpoint AJAX: notificaciones no leídas de un empleado (JSON).
 */
function fn_ajax_notificaciones($conn)
/*--------------------------------------------------------------------*/
{
    $empleado_id = notif_empleado_permitido(isset($_REQUEST['empleado_id']) ? $_REQUEST['empleado_id'] : 0);
    if ($empleado_id <= 0)
        notif_responder_json(array('ok' => false, 'count' => 0, 'error' => 'Empleado no especificado'));

    $rol = (isset($_REQUEST['rol']) && $_REQUEST['rol'] == 'Maitre') ? 'Maitre' : 'Mesero';
    // Cada usuario solo consulta las notificaciones de los roles que tiene
    $roles_rol = ($rol == 'Maitre') ? array('Maitre', 'Recepcionista') : array('Mesero');
    if (!sesion_es_admin() && !sesion_tiene_rol(...$roles_rol))
        notif_responder_json(array('ok' => false, 'count' => 0, 'error' => 'Su rol no tiene acceso a estas notificaciones'));
    if ($rol == 'Maitre')
        notif_generar_reservas_proximas($conn);
    $notifs = notif_consultar_no_leidas($conn, $empleado_id);
    notif_responder_json(array(
        'ok' => true,
        'count' => $notifs->cantidad,
        'html' => notif_render_lista_html($notifs, $rol == 'Maitre' ? 'maitre' : 'mesero'),
    ));
}

/*------------------------------------------------------------------*/
/**
 * @brief Endpoint AJAX: marca como leída una notificación propia.
 */
function fn_ajax_marcar_leida($conn)
/*--------------------------------------------------------------------*/
{
    $notif_id = isset($_REQUEST['notificacion_id']) ? intval($_REQUEST['notificacion_id']) : 0;
    $empleado_id = notif_empleado_permitido(isset($_REQUEST['empleado_id']) ? $_REQUEST['empleado_id'] : 0);
    $res = @pg_query_params($conn, "UPDATE notificaciones SET leida = TRUE, fecha_lectura = CURRENT_TIMESTAMP
                                    WHERE id = $1 AND destinatario_id = $2 AND NOT leida",
                            array($notif_id, $empleado_id));
    notif_responder_json(array('ok' => (bool) $res));
}

/*------------------------------------------------------------------*/
/**
 * @brief Endpoint AJAX: registra la entrega de los platos preparados de
 *        un pedido. El trigger trg_check_pedido_entregado marca como
 *        leída la notificación cuando todo el pedido queda entregado.
 */
function fn_ajax_entregar_pedido($conn)
/*--------------------------------------------------------------------*/
{
    $pedido_id = isset($_REQUEST['pedido_id']) ? intval($_REQUEST['pedido_id']) : 0;
    if ($_SERVER['REQUEST_METHOD'] != 'POST' || $pedido_id <= 0)
        notif_responder_json(array('ok' => false, 'error' => 'Solicitud inválida'));

    $res = @pg_query_params($conn, "UPDATE ordenes SET estado = 3 WHERE pedido_id = $1 AND estado = 2", array($pedido_id));
    if (!$res)
        notif_responder_json(array('ok' => false, 'error' => error_bd($conn)));
    if (pg_affected_rows($res) == 0)
        notif_responder_json(array('ok' => false, 'error' => "El pedido #$pedido_id no tiene platos preparados por entregar."));
    notif_responder_json(array('ok' => true));
}

/*------------------------------------------------------------------*/
/**
 * @brief Centro de notificaciones: muestra el widget de cada rol del usuario.
 */
function fn_notificaciones($conn, $mensaje = "")
/*--------------------------------------------------------------------*/
{
    $html = fn_boton_menu_principal();
    if (sesion_puede('pedidos'))
        $html .= "<button onClick=\"window.open('?opcion=pedidos', '_top');\">Ver pedidos</button>";
    if (sesion_puede('reservaciones'))
        $html .= "<button onClick=\"window.open('?opcion=reservaciones', '_top');\">Ver reservaciones</button>";
    $html .= "<h2>Centro de notificaciones</h2>";
    $html .= $mensaje;

    if (sesion_es_admin() || sesion_tiene_rol('Mesero'))
        $html .= "<h3>Pedidos listos para entregar</h3>" . notificaciones_widget($conn, 'Mesero');
    if (sesion_es_admin() || sesion_tiene_rol('Maitre', 'Recepcionista'))
        $html .= "<h3>Reservaciones próximas (30 minutos)</h3>" . notificaciones_widget($conn, 'Maitre');

    return $html;
}

/**
 * @brief Ejecuta manualmente la detección de reservas próximas.
 *        (También se ejecuta sola al consultar las notificaciones del
 *        maitre; ver sql/cron_notificar_reservas.sh para hacerlo con cron.)
 */
function fn_ejecutar_cron_reservas($conn)
{
    $res = procesar_query("SELECT fn_notificar_reservas_proximas(30) AS cant", $conn);
    $cant = ($res->cantidad > 0) ? intval($res->datos[0]['cant']) : 0;
    return fn_notificaciones($conn, mensaje_ok("Se generaron $cant notificación(es) nuevas de reservas próximas."));
}
?>
