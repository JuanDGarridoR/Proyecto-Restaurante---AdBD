<?php
/*------------------------------------------------------------------*/
// Reportes del Administrador e Historial de Clientes
// Incluye:
// 1. Reporte de Reservaciones y % de ocupación por periodo (día/semana/mes).
// 2. Reporte de Ítems más solicitados (Top N con funciones de ventana RANK).
// 3. Reporte de Ventas por periodo con ticket promedio y variación porcentual (LAG).
// 4. Historial completo de clientes (búsqueda por nombre o documento, resumen y timeline).
// 5. Gráficas con Chart.js (CDN) y Exportación a CSV en todos los reportes.
// 6. Consulta y refresco de la vista materializada vm_ventas_diarias.
/*------------------------------------------------------------------*/

function reporte_dinero($valor)
{
    return "$" . number_format(floatval($valor), 0, ',', '.');
}

/**
 * @brief Función para descargar datos en formato CSV.
 */
function reporte_descargar_csv($nombre_base, $cabeceras, $datos)
{
    header('Content-Type: text/csv; charset=utf-8');
    header('Content-Disposition: attachment; filename="' . $nombre_base . '_' . date('Ymd_His') . '.csv"');
    $out = fopen('php://output', 'w');
    // BOM UTF-8 para apertura correcta en Excel
    fprintf($out, chr(0xEF).chr(0xBB).chr(0xBF));
    fputcsv($out, $cabeceras, ';');
    foreach ($datos as $fila) {
        fputcsv($out, array_values($fila), ';');
    }
    fclose($out);
    exit;
}

/*------------------------------------------------------------------*/
/**
 * @brief Página principal de Reportes del Administrador.
 */
function fn_reportes($conn, $mensaje = "")
/*--------------------------------------------------------------------*/
{
    // Parámetros de filtrado
    // Los parámetros se validan contra listas y formatos fijos porque se
    // insertan en las sentencias SQL de los reportes
    $tipo_reporte = isset($_REQUEST['tipo_reporte']) ? $_REQUEST['tipo_reporte'] : 'ventas';
    if (!in_array($tipo_reporte, array('ventas', 'items', 'reservas', 'materializada'), true))
        $tipo_reporte = 'ventas';
    $granularidad = isset($_REQUEST['granularidad']) ? $_REQUEST['granularidad'] : 'semana';
    if (!in_array($granularidad, array('dia', 'semana', 'mes'), true))
        $granularidad = 'semana';
    $fecha_valida = function ($campo, $omision) {
        $valor = isset($_REQUEST[$campo]) ? $_REQUEST[$campo] : "";
        $fecha = DateTime::createFromFormat('!Y-m-d', $valor);
        return ($fecha && $fecha->format('Y-m-d') === $valor) ? $valor : $omision;
    };
    $fecha_inicio = $fecha_valida('fecha_inicio', date('Y-m-d', strtotime('-60 days')));
    $fecha_fin = $fecha_valida('fecha_fin', date('Y-m-d'));
    $top_n = isset($_REQUEST['top_n']) ? intval($_REQUEST['top_n']) : 10;
    if ($top_n <= 0 || $top_n > 100) $top_n = 10;

    // Manejo de refresco de vista materializada
    if (isset($_REQUEST['accion']) && $_REQUEST['accion'] == 'refrescar_vm') {
        pg_query($conn, "SELECT refrescar_ventas_diarias()");
        $mensaje = "<p style='color:green;'>Vista materializada de ventas diarias refrescada exitosamente.</p>";
    }

    // Exportación a CSV si fue solicitada
    if (isset($_REQUEST['exportar_csv']) && $_REQUEST['exportar_csv'] == '1') {
        if ($tipo_reporte == 'ventas') {
            $sql = "SELECT periodo, fecha_inicio_periodo, total_vendido, numero_pedidos, ticket_promedio, 
                           COALESCE(ventas_periodo_anterior, 0) AS ventas_periodo_anterior, 
                           COALESCE(variacion_porcentual, 0) AS variacion_porcentual
                    FROM reporte_ventas_periodo('$granularidad', '$fecha_inicio'::date, '$fecha_fin'::date)";
            $res = procesar_query($sql, $conn);
            reporte_descargar_csv("reporte_ventas_$granularidad", 
                array('Periodo', 'Fecha Inicio', 'Total Vendido', 'Num Pedidos', 'Ticket Promedio', 'Ventas Anterior', 'Variacion %'), 
                $res->datos);
        } elseif ($tipo_reporte == 'items') {
            $sql = "SELECT ranking_general, plato_nombre, categoria, cantidad_vendida, ingresos_generados, ranking_categoria
                    FROM reporte_items_mas_solicitados('$fecha_inicio'::date, '$fecha_fin'::date, $top_n)";
            $res = procesar_query($sql, $conn);
            reporte_descargar_csv("reporte_top_items", 
                array('Ranking General', 'Plato', 'Categoria', 'Cantidad Vendida', 'Ingresos Generados', 'Ranking en Categoria'), 
                $res->datos);
        } elseif ($tipo_reporte == 'reservas') {
            $sql = "SELECT periodo, fecha_inicio_periodo, numero_reservaciones, numero_personas, cancelaciones, cupo_total_disponible, porcentaje_ocupacion
                    FROM reporte_reservaciones('$granularidad', '$fecha_inicio'::date, '$fecha_fin'::date)";
            $res = procesar_query($sql, $conn);
            reporte_descargar_csv("reporte_reservaciones_$granularidad", 
                array('Periodo', 'Fecha Inicio', 'Num Reservaciones', 'Num Personas', 'Cancelaciones', 'Cupo Disponible', 'Ocupacion %'), 
                $res->datos);
        } elseif ($tipo_reporte == 'materializada') {
            $sql = "SELECT fecha, numero_pedidos, total_items, total_vendido, ticket_promedio
                    FROM vm_ventas_diarias
                    WHERE fecha BETWEEN '$fecha_inicio'::date AND '$fecha_fin'::date
                    ORDER BY fecha DESC";
            $res = procesar_query($sql, $conn);
            reporte_descargar_csv("vista_materializada_ventas_diarias", 
                array('Fecha', 'Num Pedidos', 'Total Platos', 'Total Vendido', 'Ticket Promedio'), 
                $res->datos);
        }
    }

    $html = fn_boton_menu_principal();
    $scr_hist = "window.open('?opcion=historial_clientes', '_top');";
    $html .= "<button onClick=\"$scr_hist\">Historial de Clientes</button>";
    $html .= "<h2>Reportes del Administrador y Estadísticas</h2>";
    $html .= $mensaje;

    // Barra de navegación entre reportes
    $btn_ventas = ($tipo_reporte == 'ventas') ? "style='background:#007bff;color:white;font-weight:bold;'" : "";
    $btn_items  = ($tipo_reporte == 'items') ? "style='background:#007bff;color:white;font-weight:bold;'" : "";
    $btn_res    = ($tipo_reporte == 'reservas') ? "style='background:#007bff;color:white;font-weight:bold;'" : "";
    $btn_mat    = ($tipo_reporte == 'materializada') ? "style='background:#007bff;color:white;font-weight:bold;'" : "";

    $html .= "<div style='margin-bottom: 20px; display:flex; gap:10px; justify-content:center; flex-wrap:wrap;'>";
    $html .= "<button $btn_ventas onClick=\"window.open('?opcion=reportes&tipo_reporte=ventas', '_top');\">📊 Ventas por Periodo</button>";
    $html .= "<button $btn_items onClick=\"window.open('?opcion=reportes&tipo_reporte=items', '_top');\">🏆 Ítems Más Solicitados</button>";
    $html .= "<button $btn_res onClick=\"window.open('?opcion=reportes&tipo_reporte=reservas', '_top');\">📅 Reservaciones y Ocupación</button>";
    $html .= "<button $btn_mat onClick=\"window.open('?opcion=reportes&tipo_reporte=materializada', '_top');\">⚡ Vista Materializada Diaria</button>";
    $html .= "</div>";

    // Formulario de Filtros
    $html .= "<form method='get' action='./' style='background:#f8f9fa; border:1px solid #ddd; border-radius:8px; padding:15px; margin:0 auto 25px auto; max-width:850px;'>";
    $html .= "<input type='hidden' name='opcion' value='reportes'>";
    $html .= "<input type='hidden' name='tipo_reporte' value='$tipo_reporte'>";
    
    $html .= "<div style='display:flex; gap:15px; flex-wrap:wrap; justify-content:center; align-items:center;'>";
    $html .= "<div><label><strong>Desde:</strong></label> <input type='date' name='fecha_inicio' value='$fecha_inicio' required></div>";
    $html .= "<div><label><strong>Hasta:</strong></label> <input type='date' name='fecha_fin' value='$fecha_fin' required></div>";

    if ($tipo_reporte == 'ventas' || $tipo_reporte == 'reservas') {
        $html .= "<div><label><strong>Granularidad:</strong></label> ";
        $html .= "<select name='granularidad'>";
        $html .= "<option value='dia'" . ($granularidad == 'dia' ? " selected" : "") . ">Día</option>";
        $html .= "<option value='semana'" . ($granularidad == 'semana' ? " selected" : "") . ">Semana</option>";
        $html .= "<option value='mes'" . ($granularidad == 'mes' ? " selected" : "") . ">Mes</option>";
        $html .= "</select></div>";
    }

    if ($tipo_reporte == 'items') {
        $html .= "<div><label><strong>Top N:</strong></label> ";
        $html .= "<select name='top_n'>";
        foreach (array(5, 10, 15, 20) as $n) {
            $sel = ($top_n == $n) ? " selected" : "";
            $html .= "<option value='$n'$sel>Top $n</option>";
        }
        $html .= "</select></div>";
    }

    $html .= "<div><button type='submit' style='background:#28a745; color:white;'>🔍 Filtrar</button></div>";
    
    // Botón CSV
    $csv_url = "?opcion=reportes&tipo_reporte=$tipo_reporte&fecha_inicio=$fecha_inicio&fecha_fin=$fecha_fin&granularidad=$granularidad&top_n=$top_n&exportar_csv=1";
    $html .= "<div><a href='$csv_url' style='background:#17a2b8; color:white; padding:8px 12px; font-size:1em; margin:0;'>📥 Exportar a CSV</a></div>";

    if ($tipo_reporte == 'materializada') {
        $ref_url = "?opcion=reportes&tipo_reporte=materializada&accion=refrescar_vm";
        $html .= "<div><a href='$ref_url' style='background:#ffc107; color:#222; padding:8px 12px; font-size:1em; margin:0;'>⚡ Refrescar Vista</a></div>";
    }

    $html .= "</div>";
    $html .= "</form>";

    // Inclusión de Chart.js desde CDN
    $html .= "<script src='https://cdn.jsdelivr.net/npm/chart.js@4.4.1/dist/chart.umd.min.js'></script>";

    // -------------------------------------------------------------
    // REPORTE 1: VENTAS TOTALES POR PERIODO
    // -------------------------------------------------------------
    if ($tipo_reporte == 'ventas') {
        $sql = "SELECT periodo, fecha_inicio_periodo, total_vendido, numero_pedidos, ticket_promedio, 
                       ventas_periodo_anterior, variacion_porcentual
                FROM reporte_ventas_periodo('$granularidad', '$fecha_inicio'::date, '$fecha_fin'::date)";
        $res = procesar_query($sql, $conn);

        $html .= "<h3>Ventas por Periodo (" . ucfirst($granularidad) . ")</h3>";

        if ($res->cantidad == 0) {
            $html .= "<p>No hay datos de ventas en el rango seleccionado.</p>";
        } else {
            // Contenedor de gráfica
            $html .= "<div style='max-width:850px; margin:0 auto 25px auto; background:#fff; padding:15px; border:1px solid #ddd; border-radius:8px;'>";
            $html .= "<canvas id='graficaVentas' height='100'></canvas>";
            $html .= "</div>";

            // Datos para Chart.js
            $labels = array();
            $valores_ventas = array();
            $valores_ticket = array();
            foreach ($res->datos as $fila) {
                $labels[] = $fila['periodo'];
                $valores_ventas[] = floatval($fila['total_vendido']);
                $valores_ticket[] = floatval($fila['ticket_promedio']);
            }

            $html .= "<script>
            document.addEventListener('DOMContentLoaded', function() {
                var ctx = document.getElementById('graficaVentas');
                if (ctx && typeof Chart !== 'undefined') {
                    new Chart(ctx, {
                        type: 'bar',
                        data: {
                            labels: " . json_encode($labels) . ",
                            datasets: [{
                                label: 'Total Vendido ($)',
                                data: " . json_encode($valores_ventas) . ",
                                backgroundColor: 'rgba(54, 162, 235, 0.6)',
                                borderColor: 'rgba(54, 162, 235, 1)',
                                borderWidth: 1,
                                yAxisID: 'y'
                            }, {
                                label: 'Ticket Promedio ($)',
                                data: " . json_encode($valores_ticket) . ",
                                type: 'line',
                                borderColor: 'rgba(255, 99, 132, 1)',
                                backgroundColor: 'rgba(255, 99, 132, 0.2)',
                                borderWidth: 2,
                                tension: 0.3,
                                yAxisID: 'y1'
                            }]
                        },
                        options: {
                            responsive: true,
                            scales: {
                                y: { type: 'linear', position: 'left', beginAtZero: true, title: { display: true, text: 'Ventas ($)' } },
                                y1: { type: 'linear', position: 'right', beginAtZero: true, grid: { drawOnChartArea: false }, title: { display: true, text: 'Ticket Promedio ($)' } }
                            }
                        }
                    });
                }
            });
            </script>";

            // Tabla de resultados
            $html .= "<table style='margin:0 auto 20px auto;'>";
            $html .= "<tr><th>Periodo</th><th>Total Vendido</th><th># Pedidos</th><th>Ticket Promedio</th><th>Ventas Periodo Anterior</th><th>Variación % (LAG)</th></tr>";
            foreach ($res->datos as $f) {
                $var_val = ($f['variacion_porcentual'] !== null) ? floatval($f['variacion_porcentual']) : null;
                $var_txt = "N/A";
                $var_color = "#333";
                if ($var_val !== null) {
                    $signo = ($var_val > 0) ? "+" : "";
                    $var_txt = $signo . number_format($var_val, 2) . "%";
                    $var_color = ($var_val >= 0) ? "#28a745" : "#dc3545";
                }
                $ant_txt = ($f['ventas_periodo_anterior'] !== null) ? reporte_dinero($f['ventas_periodo_anterior']) : "N/A";

                $html .= "<tr>"
                       . "<td><strong>" . htmlspecialchars($f['periodo']) . "</strong></td>"
                       . "<td>" . reporte_dinero($f['total_vendido']) . "</td>"
                       . "<td>" . $f['numero_pedidos'] . "</td>"
                       . "<td>" . reporte_dinero($f['ticket_promedio']) . "</td>"
                       . "<td>" . $ant_txt . "</td>"
                       . "<td style='color:$var_color; font-weight:bold;'>" . $var_txt . "</td>"
                       . "</tr>";
            }
            $html .= "</table>";
        }
    }

    // -------------------------------------------------------------
    // REPORTE 2: ÍTEMS MÁS SOLICITADOS (TOP N)
    // -------------------------------------------------------------
    elseif ($tipo_reporte == 'items') {
        $sql = "SELECT plato_id, plato_nombre, categoria, cantidad_vendida, ingresos_generados, 
                       ranking_categoria, ranking_general
                FROM reporte_items_mas_solicitados('$fecha_inicio'::date, '$fecha_fin'::date, $top_n)";
        $res = procesar_query($sql, $conn);

        $html .= "<h3>Top $top_n Ítems del Menú Más Solicitados</h3>";

        if ($res->cantidad == 0) {
            $html .= "<p>No hay órdenes registradas en el rango seleccionado.</p>";
        } else {
            // Contenedor de gráfica de barras horizontales
            $html .= "<div style='max-width:850px; margin:0 auto 25px auto; background:#fff; padding:15px; border:1px solid #ddd; border-radius:8px;'>";
            $html .= "<canvas id='graficaItems' height='100'></canvas>";
            $html .= "</div>";

            $nombres = array();
            $cantidades = array();
            foreach ($res->datos as $fila) {
                $nombres[] = $fila['plato_nombre'];
                $cantidades[] = intval($fila['cantidad_vendida']);
            }

            $html .= "<script>
            document.addEventListener('DOMContentLoaded', function() {
                var ctx = document.getElementById('graficaItems');
                if (ctx && typeof Chart !== 'undefined') {
                    new Chart(ctx, {
                        type: 'bar',
                        data: {
                            labels: " . json_encode($nombres) . ",
                            datasets: [{
                                label: 'Cantidad Vendida (unidades)',
                                data: " . json_encode($cantidades) . ",
                                backgroundColor: 'rgba(75, 192, 192, 0.7)',
                                borderColor: 'rgba(75, 192, 192, 1)',
                                borderWidth: 1
                            }]
                        },
                        options: {
                            indexAxis: 'y',
                            responsive: true,
                            scales: { x: { beginAtZero: true, title: { display: true, text: 'Unidades Vendidas' } } }
                        }
                    });
                }
            });
            </script>";

            $html .= "<table style='margin:0 auto 20px auto;'>";
            $html .= "<tr><th>Pos. General</th><th>Plato</th><th>Categoría</th><th>Cantidad Vendida</th><th>Ingresos Generados</th><th>Pos. en su Categoría (RANK)</th></tr>";
            foreach ($res->datos as $f) {
                $medalla = "";
                if ($f['ranking_general'] == 1) $medalla = "🥇 ";
                elseif ($f['ranking_general'] == 2) $medalla = "🥈 ";
                elseif ($f['ranking_general'] == 3) $medalla = "🥉 ";

                $html .= "<tr>"
                       . "<td><strong>$medalla#" . $f['ranking_general'] . "</strong></td>"
                       . "<td>" . htmlspecialchars($f['plato_nombre']) . "</td>"
                       . "<td>" . htmlspecialchars($f['categoria']) . "</td>"
                       . "<td><strong>" . $f['cantidad_vendida'] . "</strong></td>"
                       . "<td>" . reporte_dinero($f['ingresos_generados']) . "</td>"
                       . "<td>#" . $f['ranking_categoria'] . " en " . htmlspecialchars($f['categoria']) . "</td>"
                       . "</tr>";
            }
            $html .= "</table>";
        }
    }

    // -------------------------------------------------------------
    // REPORTE 3: RESERVACIONES Y OCUPACIÓN
    // -------------------------------------------------------------
    elseif ($tipo_reporte == 'reservas') {
        $sql = "SELECT periodo, fecha_inicio_periodo, numero_reservaciones, numero_personas, 
                       cancelaciones, cupo_total_disponible, porcentaje_ocupacion
                FROM reporte_reservaciones('$granularidad', '$fecha_inicio'::date, '$fecha_fin'::date)";
        $res = procesar_query($sql, $conn);

        $html .= "<h3>Reservaciones y Porcentaje de Ocupación (" . ucfirst($granularidad) . ")</h3>";

        if ($res->cantidad == 0) {
            $html .= "<p>No hay reservaciones registradas en el rango seleccionado.</p>";
        } else {
            // Contenedor de gráfica
            $html .= "<div style='max-width:850px; margin:0 auto 25px auto; background:#fff; padding:15px; border:1px solid #ddd; border-radius:8px;'>";
            $html .= "<canvas id='graficaReservas' height='100'></canvas>";
            $html .= "</div>";

            $labels_res = array();
            $personas = array();
            $ocupaciones = array();
            foreach ($res->datos as $fila) {
                $labels_res[] = $fila['periodo'];
                $personas[] = intval($fila['numero_personas']);
                $ocupaciones[] = floatval($fila['porcentaje_ocupacion']);
            }

            $html .= "<script>
            document.addEventListener('DOMContentLoaded', function() {
                var ctx = document.getElementById('graficaReservas');
                if (ctx && typeof Chart !== 'undefined') {
                    new Chart(ctx, {
                        type: 'bar',
                        data: {
                            labels: " . json_encode($labels_res) . ",
                            datasets: [{
                                label: 'Personas Reservadas',
                                data: " . json_encode($personas) . ",
                                backgroundColor: 'rgba(153, 102, 255, 0.6)',
                                borderColor: 'rgba(153, 102, 255, 1)',
                                borderWidth: 1,
                                yAxisID: 'y'
                            }, {
                                label: '% Ocupación del Cupo',
                                data: " . json_encode($ocupaciones) . ",
                                type: 'line',
                                borderColor: 'rgba(255, 159, 64, 1)',
                                backgroundColor: 'rgba(255, 159, 64, 0.2)',
                                borderWidth: 2,
                                tension: 0.3,
                                yAxisID: 'y1'
                            }]
                        },
                        options: {
                            responsive: true,
                            scales: {
                                y: { type: 'linear', position: 'left', beginAtZero: true, title: { display: true, text: 'Personas' } },
                                y1: { type: 'linear', position: 'right', beginAtZero: true, max: 100, grid: { drawOnChartArea: false }, title: { display: true, text: '% Ocupación' } }
                            }
                        }
                    });
                }
            });
            </script>";

            $html .= "<table style='margin:0 auto 20px auto;'>";
            $html .= "<tr><th>Periodo</th><th># Reservas</th><th># Personas</th><th>Cancelaciones</th><th>Cupo Disponible</th><th>% Ocupación</th></tr>";
            foreach ($res->datos as $f) {
                $html .= "<tr>"
                       . "<td><strong>" . htmlspecialchars($f['periodo']) . "</strong></td>"
                       . "<td>" . $f['numero_reservaciones'] . "</td>"
                       . "<td>" . $f['numero_personas'] . "</td>"
                       . "<td>" . $f['cancelaciones'] . "</td>"
                       . "<td>" . $f['cupo_total_disponible'] . " sillas</td>"
                       . "<td><strong>" . $f['porcentaje_ocupacion'] . "%</strong></td>"
                       . "</tr>";
            }
            $html .= "</table>";
        }
    }

    // -------------------------------------------------------------
    // REPORTE 4: VISTA MATERIALIZADA DE VENTAS DIARIAS
    // -------------------------------------------------------------
    elseif ($tipo_reporte == 'materializada') {
        $sql = "SELECT fecha, numero_pedidos, total_items, total_vendido, ticket_promedio
                FROM vm_ventas_diarias
                WHERE fecha BETWEEN '$fecha_inicio'::date AND '$fecha_fin'::date
                ORDER BY fecha DESC";
        $res = procesar_query($sql, $conn);

        $html .= "<h3>Vista Materializada (vm_ventas_diarias)</h3>";
        $html .= "<p><em>Vista optimizada pre-calculada en la base de datos para alta velocidad de consulta.</em></p>";

        if ($res->cantidad == 0) {
            $html .= "<p>No hay datos en la vista materializada para el rango seleccionado.</p>";
        } else {
            $html .= "<table style='margin:0 auto 20px auto;'>";
            $html .= "<tr><th>Fecha</th><th># Pedidos</th><th>Total Platos</th><th>Total Vendido</th><th>Ticket Promedio</th></tr>";
            foreach ($res->datos as $f) {
                $html .= "<tr>"
                       . "<td>" . $f['fecha'] . "</td>"
                       . "<td>" . $f['numero_pedidos'] . "</td>"
                       . "<td>" . $f['total_items'] . "</td>"
                       . "<td>" . reporte_dinero($f['total_vendido']) . "</td>"
                       . "<td>" . reporte_dinero($f['ticket_promedio']) . "</td>"
                       . "</tr>";
            }
            $html .= "</table>";
        }
    }

    return $html;
}

/*------------------------------------------------------------------*/
/**
 * @brief Página del Historial de Clientes (búsqueda y cronología).
 */
function fn_historial_clientes($conn)
/*--------------------------------------------------------------------*/
{
    $criterio = isset($_REQUEST['criterio']) ? trim($_REQUEST['criterio']) : "";
    $cliente_id = isset($_REQUEST['cliente_id']) ? intval($_REQUEST['cliente_id']) : 0;

    // Exportación de historial a CSV
    if (isset($_REQUEST['exportar_csv']) && $_REQUEST['exportar_csv'] == '1' && $cliente_id > 0) {
        $sql_tl = "SELECT to_char(fecha, 'YYYY-MM-DD HH24:MI') AS fecha, tipo_evento, referencia_id, detalle, monto, estado_texto
                   FROM historial_cliente_timeline($cliente_id)";
        $res = procesar_query($sql_tl, $conn);
        reporte_descargar_csv("historial_cliente_$cliente_id",
            array('Fecha', 'Tipo Evento', 'Referencia ID', 'Detalle', 'Monto ($)', 'Estado'),
            $res->datos);
    }

    $html = fn_boton_menu_principal();
    $scr_rep = "window.open('?opcion=reportes', '_top');";
    $html .= "<button onClick=\"$scr_rep\">Reportes del Administrador</button>";
    $html .= "<h2>Historial de Clientes</h2>";

    // Formulario de Búsqueda
    $html .= "<form method='get' action='./' style='margin-bottom: 25px;'>";
    $html .= "<input type='hidden' name='opcion' value='historial_clientes'>";
    $html .= "<label><strong>Buscar Cliente (Nombre o Documento):</strong></label> ";
    $html .= "<input type='text' name='criterio' value='" . htmlspecialchars($criterio) . "' placeholder='Ej: Ana Torres o CC-10000001' style='padding:5px; width:260px;'> ";
    $html .= "<button type='submit'>Buscar</button>";
    $html .= "</form>";

    // Consultar clientes que coincidan con el criterio o lista completa si no hay filtro
    $where = "";
    if ($criterio != "") {
        $crit_esc = pg_escape_string($conn, $criterio);
        $where = "WHERE u.nombre ILIKE '%$crit_esc%' OR u.documento ILIKE '%$crit_esc%'";
    }

    $sql_usuarios = "SELECT u.id, u.nombre, COALESCE(u.documento, 'Sin documento') AS documento
                     FROM usuarios u
                     $where
                     ORDER BY u.nombre
                     LIMIT 20";
    $usuarios = procesar_query($sql_usuarios, $conn);

    if ($usuarios->cantidad == 0) {
        $html .= "<p>No se encontraron clientes que coincidan con la búsqueda.</p>";
    } else {
        if ($cliente_id == 0 && $usuarios->cantidad > 0) {
            $cliente_id = intval($usuarios->datos[0]['id']);
        }

        // Selector rápido entre los clientes encontrados
        $html .= "<form method='get' action='./' style='margin-bottom: 20px;'>";
        $html .= "<input type='hidden' name='opcion' value='historial_clientes'>";
        $html .= "<input type='hidden' name='criterio' value='" . htmlspecialchars($criterio) . "'>";
        $html .= "<label>Seleccionar cliente:</label> ";
        $html .= "<select name='cliente_id' onchange='this.form.submit()'>";
        foreach ($usuarios->datos as $usr) {
            $sel = ($usr['id'] == $cliente_id) ? " selected" : "";
            $html .= "<option value='" . $usr['id'] . "'$sel>" . htmlspecialchars($usr['nombre']) . " (" . htmlspecialchars($usr['documento']) . ")</option>";
        }
        $html .= "</select> ";
        $html .= "<button type='submit'>Ver Historial</button>";
        $html .= "</form>";

        if ($cliente_id > 0) {
            // 1. Resumen General del Cliente
            $sql_resumen = "SELECT cliente_id, nombre, documento, total_gastado, numero_visitas, 
                                   plato_favorito, cantidad_plato_favorito
                            FROM historial_cliente_resumen($cliente_id)";
            $res_info = procesar_query($sql_resumen, $conn);

            if ($res_info->cantidad > 0) {
                $info = $res_info->datos[0];

                $html .= "<div style='background:#f4f6f9; border:2px solid #007bff; border-radius:10px; padding:20px; max-width:800px; margin:0 auto 25px auto; text-align:left;'>";
                $html .= "<h3 style='margin-top:0; color:#0056b3; border-bottom:1px solid #ccc; padding-bottom:5px;'>" . htmlspecialchars($info['nombre']) . "</h3>";
                $html .= "<p><strong>Documento:</strong> " . htmlspecialchars($info['documento']) . " | <strong>ID Cliente:</strong> #" . $info['cliente_id'] . "</p>";

                $html .= "<div style='display:flex; justify-content:space-around; flex-wrap:wrap; margin-top:15px; text-align:center;'>";
                $html .= "<div style='background:white; border-radius:8px; padding:12px; margin:5px; flex:1; min-width:180px; box-shadow:0 1px 3px rgba(0,0,0,0.1);'>";
                $html .= "<div style='color:#666; font-size:0.9em;'>Total Gastado</div>";
                $html .= "<div style='font-size:1.4em; font-weight:bold; color:#28a745;'>" . reporte_dinero($info['total_gastado']) . "</div>";
                $html .= "</div>";

                $html .= "<div style='background:white; border-radius:8px; padding:12px; margin:5px; flex:1; min-width:180px; box-shadow:0 1px 3px rgba(0,0,0,0.1);'>";
                $html .= "<div style='color:#666; font-size:0.9em;'>Número de Visitas</div>";
                $html .= "<div style='font-size:1.4em; font-weight:bold; color:#17a2b8;'>" . $info['numero_visitas'] . "</div>";
                $html .= "</div>";

                $html .= "<div style='background:white; border-radius:8px; padding:12px; margin:5px; flex:1; min-width:180px; box-shadow:0 1px 3px rgba(0,0,0,0.1);'>";
                $html .= "<div style='color:#666; font-size:0.9em;'>Plato Favorito</div>";
                $html .= "<div style='font-size:1.1em; font-weight:bold; color:#e83e8c;'>" . htmlspecialchars($info['plato_favorito']) . "</div>";
                $html .= "<div style='font-size:0.8em; color:#888;'>" . $info['cantidad_plato_favorito'] . " veces pedido</div>";
                $html .= "</div>";
                $html .= "</div>"; // fin grid

                $csv_cliente_url = "?opcion=historial_clientes&criterio=" . urlencode($criterio) . "&cliente_id=$cliente_id&exportar_csv=1";
                $html .= "<div style='text-align:right; margin-top:15px;'><a href='$csv_cliente_url' style='background:#17a2b8; color:white; padding:6px 10px; font-size:0.9em;'>📥 Exportar Historial a CSV</a></div>";
                $html .= "</div>"; // fin tarjeta

                // 2. Cronología Detallada
                $sql_timeline = "SELECT to_char(fecha, 'YYYY-MM-DD HH24:MI') AS fecha, tipo_evento, referencia_id, detalle, monto, estado_texto
                                 FROM historial_cliente_timeline($cliente_id)
                                 LIMIT 50";
                $tl = procesar_query($sql_timeline, $conn);

                $html .= "<h3>Historial de Actividad (Cronológico)</h3>";
                if ($tl->cantidad == 0) {
                    $html .= "<p>Este cliente aún no tiene actividad registrada.</p>";
                } else {
                    $html .= "<table style='margin:0 auto 25px auto;'>";
                    $html .= "<tr><th>Fecha y Hora</th><th>Tipo</th><th>Ref #</th><th>Detalle</th><th>Monto</th><th>Estado</th></tr>";
                    foreach ($tl->datos as $evento) {
                        $badge_tipo = ($evento['tipo_evento'] == 'Pedido') 
                            ? "<span style='background:#e2e3e5; color:#383d41; padding:2px 6px; border-radius:4px;'>🍽️ Pedido</span>"
                            : "<span style='background:#d1ecf1; color:#0c5460; padding:2px 6px; border-radius:4px;'>📅 Reservación</span>";

                        $monto_txt = ($evento['monto'] > 0) ? reporte_dinero($evento['monto']) : "-";

                        $html .= "<tr>"
                               . "<td>" . $evento['fecha'] . "</td>"
                               . "<td>$badge_tipo</td>"
                               . "<td>#" . $evento['referencia_id'] . "</td>"
                               . "<td>" . htmlspecialchars($evento['detalle']) . "</td>"
                               . "<td>" . $monto_txt . "</td>"
                               . "<td>" . htmlspecialchars($evento['estado_texto']) . "</td>"
                               . "</tr>";
                    }
                    $html .= "</table>";
                }
            }
        }
    }

    return $html;
}
?>