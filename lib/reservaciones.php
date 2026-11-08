<?php
/*------------------------------------------------------------------*/
// Gestión de reservaciones.
// Una reservación (tabla reservaciones) ocupa una mesa durante el
// intervalo semiabierto [inicio, inicio + duracion) registrado en la
// tabla horarios: una reserva que termina a las 14:00 no se cruza con
// otra que empieza a las 14:00 en la misma mesa.
/*------------------------------------------------------------------*/

define('RESERVA_DURACION', '2 hours');
define('RESERVA_ACTIVA', 1);
define('RESERVA_CANCELADA', 0);

/*------------------------------------------------------------------*/
/**
 * @brief Ejecuta una sentencia SQL con parámetros y devuelve sus filas.
 * @return array|null Filas resultantes, o null si la sentencia falló.
 */
function reserva_consulta($conn, $sentencia, $parametros = array())
/*--------------------------------------------------------------------*/
{
    $respuesta = @pg_query_params($conn, $sentencia, $parametros);
    if (!$respuesta)
        return null;
    $datos = pg_fetch_all($respuesta);
    return ($datos === false) ? array() : $datos;
}

/*------------------------------------------------------------------*/
/**
 * @brief Inicia una transacción, o un punto de guardado si ya hay una abierta.
 * @return bool true si se usó un punto de guardado.
 */
function reserva_transaccion_iniciar($conn)
/*--------------------------------------------------------------------*/
{
    $anidada = pg_transaction_status($conn) != PGSQL_TRANSACTION_IDLE;
    pg_query($conn, $anidada ? "SAVEPOINT reserva" : "BEGIN");
    return $anidada;
}

function reserva_transaccion_terminar($conn, $anidada, $confirmar) {
    if ($anidada)
        pg_query($conn, $confirmar ? "RELEASE SAVEPOINT reserva" : "ROLLBACK TO SAVEPOINT reserva");
    else
        pg_query($conn, $confirmar ? "COMMIT" : "ROLLBACK");
}

/*------------------------------------------------------------------*/
/**
 * @brief Lee y valida los datos del formulario de reservación.
 * @param array $errores Recibe los mensajes de los datos inválidos.
 * @return array Datos validados (cliente_id, mesa_id, sillas, cantidad, inicio).
 */
function reserva_leer_formulario($conn, &$errores)
/*--------------------------------------------------------------------*/
{
    $errores = array();
    $datos = array();

    $datos['cliente_id'] = mesa_validar_entero('cliente_id', 1, 2147483647);
    if ($datos['cliente_id'] === null
        || count(reserva_consulta($conn, 'SELECT id FROM usuarios WHERE id = $1', array($datos['cliente_id']))) == 0)
        $errores[] = "Seleccione un cliente válido.";

    $datos['mesa_id'] = mesa_validar_entero('mesa_id', 1, 2147483647);
    $mesa = ($datos['mesa_id'] === null) ? array()
          : reserva_consulta($conn, 'SELECT sillas FROM mesas WHERE id = $1', array($datos['mesa_id']));
    if (count($mesa) == 0)
        $errores[] = "Seleccione una mesa válida.";
    else
        $datos['sillas'] = intval($mesa[0]['sillas']);

    $datos['cantidad'] = mesa_validar_entero('cantidad', 1, MESAS_MAX_SILLAS);
    if ($datos['cantidad'] === null)
        $errores[] = "El número de personas debe ser un entero entre 1 y " . MESAS_MAX_SILLAS . ".";
    elseif (isset($datos['sillas']) && $datos['cantidad'] > $datos['sillas'])
        $errores[] = "La mesa " . $datos['mesa_id'] . " solo tiene " . $datos['sillas'] . " sillas y la reservación es para " . $datos['cantidad'] . " personas.";

    $fecha = isset($_REQUEST['fecha']) ? trim($_REQUEST['fecha']) : "";
    $hora = isset($_REQUEST['hora']) ? trim($_REQUEST['hora']) : "";
    $inicio = DateTime::createFromFormat('!Y-m-d H:i', "$fecha $hora");
    if (!$inicio || $inicio->format('Y-m-d H:i') !== "$fecha $hora") {
        $errores[] = "Indique una fecha y una hora válidas.";
    } else {
        $datos['inicio'] = "$fecha $hora:00";
        $futuro = reserva_consulta($conn, 'SELECT $1::timestamp > LOCALTIMESTAMP AS futuro', array($datos['inicio']));
        if ($futuro[0]['futuro'] != 't')
            $errores[] = "La reservación debe ser para una fecha y hora futuras.";
    }

    return $datos;
}

/*------------------------------------------------------------------*/
/**
 * @brief Verifica que la mesa esté libre y que no se supere el cupo del
 *        restaurante en el intervalo [inicio, inicio + 2 horas).
 * @param int $excluir_id Reservación que se está modificando (0 si es nueva).
 * @return string Mensaje del conflicto, o "" si la reservación es posible.
 * @pre Debe llamarse dentro de la transacción que guarda la reservación.
 */
function reserva_verificar_disponibilidad($conn, $datos, $excluir_id)
/*--------------------------------------------------------------------*/
{
    $parametros = array($datos['mesa_id'], $datos['inicio'], RESERVA_DURACION, $excluir_id, RESERVA_CANCELADA);

    // Horarios de reservaciones activas que se cruzan con el intervalo solicitado
    $activos = 'SELECT HOR.mesa_id, HOR.reservacion_id, HOR.inicio
                     , HOR.inicio + COALESCE(HOR.duracion, $3::interval) AS fin
                     , MES.sillas
                FROM horarios AS HOR
                JOIN reservaciones AS RES ON RES.id = HOR.reservacion_id
                JOIN mesas AS MES ON MES.id = HOR.mesa_id
                WHERE RES.estado IS DISTINCT FROM $5
                  AND HOR.reservacion_id <> $4
                  AND HOR.inicio < $2::timestamp + $3::interval
                  AND HOR.inicio + COALESCE(HOR.duracion, $3::interval) > $2::timestamp';

    $cruces = reserva_consulta($conn, "
        WITH activos AS ($activos)
        SELECT reservacion_id
             , to_char(inicio, 'YYYY-MM-DD HH24:MI') AS inicio
             , to_char(fin, 'YYYY-MM-DD HH24:MI') AS fin
        FROM activos
        WHERE mesa_id = $1
        ORDER BY inicio", $parametros);
    if ($cruces === null)
        return "Error al verificar la disponibilidad: " . pg_last_error($conn);
    if (count($cruces) > 0) {
        $cruce = $cruces[0];
        return "Conflicto de horario: la mesa " . $datos['mesa_id'] . " ya está reservada del "
             . $cruce['inicio'] . " al " . $cruce['fin'] . " (reservación " . $cruce['reservacion_id'] . ").";
    }

    // La ocupación solo aumenta cuando empieza una reserva, así que basta
    // con revisar el inicio solicitado y los inicios dentro del intervalo
    $ocupacion = reserva_consulta($conn, "
        WITH activos AS ($activos)
           , momentos AS (SELECT $2::timestamp AS momento
                          UNION SELECT inicio FROM activos WHERE inicio > $2::timestamp)
        SELECT to_char(MOM.momento, 'YYYY-MM-DD HH24:MI') AS momento
             , (SELECT COALESCE(SUM(ACT.sillas), 0) FROM activos AS ACT
                WHERE ACT.inicio <= MOM.momento AND ACT.fin > MOM.momento)
               + (SELECT sillas FROM mesas WHERE id = $1) AS ocupadas
             , (SELECT SUM(sillas) FROM mesas) AS cupo
        FROM momentos AS MOM
        ORDER BY ocupadas DESC, MOM.momento
        LIMIT 1", $parametros);
    if ($ocupacion === null)
        return "Error al verificar la capacidad: " . pg_last_error($conn);
    if (intval($ocupacion[0]['ocupadas']) > intval($ocupacion[0]['cupo']))
        return "Conflicto de capacidad: el " . $ocupacion[0]['momento'] . " habría " . $ocupacion[0]['ocupadas']
             . " sillas reservadas y el cupo del restaurante es de " . $ocupacion[0]['cupo'] . ".";

    return "";
}

/*------------------------------------------------------------------*/
/**
 * @brief Guarda una reservación nueva o modificada verificando la
 *        disponibilidad dentro de la misma transacción.
 * @param int $reservacion_id 0 para crear; al crear recibe el id nuevo.
 * @return string Mensaje de error, o "" si se guardó.
 */
function reserva_guardar($conn, $datos, &$reservacion_id)
/*--------------------------------------------------------------------*/
{
    $anidada = reserva_transaccion_iniciar($conn);
    // Serializa las reservaciones simultáneas para que no ocupen la misma mesa
    pg_query($conn, "LOCK TABLE horarios IN SHARE ROW EXCLUSIVE MODE");

    $error = "";
    if ($reservacion_id != 0) {
        $actual = reserva_consulta($conn, 'SELECT estado FROM reservaciones WHERE id = $1 FOR UPDATE', array($reservacion_id));
        if ($actual === null)
            $error = "Error al consultar la reservación: " . pg_last_error($conn);
        elseif (count($actual) == 0 || $actual[0]['estado'] == RESERVA_CANCELADA)
            $error = "La reservación $reservacion_id no existe o está cancelada.";
    }
    if ($error == "")
        $error = reserva_verificar_disponibilidad($conn, $datos, $reservacion_id);

    if ($error == "") {
        if ($reservacion_id == 0) {
            $nueva = reserva_consulta($conn, 'INSERT INTO reservaciones (cliente_id, cantidad, estado) VALUES ($1, $2, $3) RETURNING id',
                                      array($datos['cliente_id'], $datos['cantidad'], RESERVA_ACTIVA));
            $ok = ($nueva !== null);
            if ($ok) {
                $reservacion_id = intval($nueva[0]['id']);
                $ok = (bool) @pg_query_params($conn, 'INSERT INTO horarios (mesa_id, reservacion_id, inicio, duracion) VALUES ($1, $2, $3, $4)',
                                              array($datos['mesa_id'], $reservacion_id, $datos['inicio'], RESERVA_DURACION));
            }
        } else {
            $ok = (bool) @pg_query_params($conn, 'UPDATE reservaciones SET cliente_id = $1, cantidad = $2 WHERE id = $3',
                                          array($datos['cliente_id'], $datos['cantidad'], $reservacion_id));
            if ($ok) {
                $res = @pg_query_params($conn, 'UPDATE horarios SET mesa_id = $1, inicio = $2, duracion = $3 WHERE reservacion_id = $4',
                                        array($datos['mesa_id'], $datos['inicio'], RESERVA_DURACION, $reservacion_id));
                $ok = (bool) $res;
                if ($ok && pg_affected_rows($res) == 0)
                    $ok = (bool) @pg_query_params($conn, 'INSERT INTO horarios (mesa_id, reservacion_id, inicio, duracion) VALUES ($1, $2, $3, $4)',
                                                  array($datos['mesa_id'], $reservacion_id, $datos['inicio'], RESERVA_DURACION));
            }
        }
        if (!$ok)
            $error = "Error al guardar la reservación: " . pg_last_error($conn);
    }

    reserva_transaccion_terminar($conn, $anidada, $error == "");
    return $error;
}

/*------------------------------------------------------------------*/
/**
 * @brief Genera el formulario de reservación (usado al crear y al modificar).
 */
function reserva_formulario($conn, $opcion, $valores, $boton)
/*--------------------------------------------------------------------*/
{
    $valor = function ($campo) use ($valores) {
        return isset($valores[$campo]) ? htmlspecialchars($valores[$campo], ENT_QUOTES) : "";
    };

    $html = "<form method='post' action='./'>"
          . "<input type='hidden' name='opcion' value='$opcion'>";
    if (isset($valores['reservacion_id']))
        $html .= "<input type='hidden' name='reservacion_id' value='" . $valor('reservacion_id') . "'>";

    $html .= "<label>Cliente:</label> <select name='cliente_id' required><option value=''></option>";
    $clientes = procesar_query("SELECT id, nombre FROM usuarios ORDER BY nombre", $conn);
    foreach ($clientes->datos as $cliente) {
        $marcado = ($valor('cliente_id') == $cliente['id']) ? " selected" : "";
        $html .= "<option value='" . $cliente['id'] . "'$marcado>" . htmlspecialchars($cliente['nombre']) . "</option>";
    }
    $html .= "</select>";

    $html .= "<label>Mesa:</label> <select name='mesa_id' required><option value=''></option>";
    $mesas = procesar_query("SELECT id, sillas FROM mesas ORDER BY id", $conn);
    foreach ($mesas->datos as $mesa) {
        $marcado = ($valor('mesa_id') == $mesa['id']) ? " selected" : "";
        $html .= "<option value='" . $mesa['id'] . "'$marcado>Mesa " . $mesa['id'] . " (" . $mesa['sillas'] . " sillas)</option>";
    }
    $html .= "</select>";

    $html .= "<label>Personas:</label> <input type='number' name='cantidad' min='1' max='" . MESAS_MAX_SILLAS . "' value='" . $valor('cantidad') . "' required>"
           . "<label>Fecha:</label> <input type='date' name='fecha' value='" . $valor('fecha') . "' required>"
           . "<label>Hora:</label> <input type='time' name='hora' value='" . $valor('hora') . "' required>"
           . "<button type='submit'>$boton</button>"
           . "</form>"
           . "<p>Cada reservación ocupa la mesa durante 2 horas.</p>";

    return $html;
}

function reserva_mensajes($mensajes) {
    $html = "";
    foreach ($mensajes as $mensaje)
        $html .= "<p>" . htmlspecialchars($mensaje) . "</p>";
    return $html;
}

/*------------------------------------------------------------------*/
/**
 * @brief Muestra la página de gestión de reservaciones.
 * @param string $formulario Formulario a mostrar; por omisión, el de registro.
 */
function fn_reservaciones($conn, $mensaje = "", $formulario = null)
/*--------------------------------------------------------------------*/
{
    $scr_mesas = "window.open('?opcion=ver_mesas', '_top');";
    return fn_boton_menu_principal()
         . "<button onClick=\"$scr_mesas\">Gestión de mesas</button>"
         . notificaciones_widget($conn, 'Maitre')
         . reserva_seccion($conn, $mensaje, $formulario);
}

/*------------------------------------------------------------------*/
/**
 * @brief Lista las reservaciones y muestra el formulario indicado.
 */
function reserva_seccion($conn, $mensaje, $formulario)
/*--------------------------------------------------------------------*/
{
    $sentencia = "
        SELECT RES.id
             , USR.nombre AS cliente
             , RES.cantidad
             , RES.estado
             , HOR.mesa_id
             , to_char(HOR.inicio, 'YYYY-MM-DD HH24:MI') AS inicio
             , to_char(HOR.inicio + HOR.duracion, 'YYYY-MM-DD HH24:MI') AS fin
        FROM reservaciones AS RES
        LEFT JOIN usuarios AS USR ON USR.id = RES.cliente_id
        JOIN horarios AS HOR ON HOR.reservacion_id = RES.id
        ORDER BY HOR.inicio DESC, RES.id
        ";
    $reservas = reserva_consulta($conn, $sentencia);

    $html = "<h2>Gestión de reservaciones</h2>";
    $html .= $mensaje;
    if ($reservas === null)
        return $html . reserva_mensajes(array("No se pudieron consultar las reservaciones: " . pg_last_error($conn)));

    // Solo se listan las reservaciones con mesa y horario asignados
    $sin_horario = reserva_consulta($conn, "SELECT COUNT(*) AS cantidad FROM reservaciones AS RES
                                            WHERE NOT EXISTS (SELECT 1 FROM horarios AS HOR WHERE HOR.reservacion_id = RES.id)");
    if ($sin_horario !== null && $sin_horario[0]['cantidad'] > 0)
        $html .= reserva_mensajes(array("Hay " . $sin_horario[0]['cantidad'] . " reservaciones registradas sin mesa ni horario; no se muestran en esta tabla."));

    $html .= "<table><tr><th>Reservación</th><th>Cliente</th><th>Mesa</th><th>Personas</th><th>Inicio</th><th>Fin</th><th>Estado</th><th>Acciones</th></tr>";
    foreach ($reservas as $reserva) {
        $activa = ($reserva['estado'] != RESERVA_CANCELADA);
        $acciones = "";
        if ($activa) {
            $scr_editar = "window.open('?opcion=editar_reservacion&reservacion_id=" . $reserva['id'] . "', '_top');";
            $acciones = "<button onClick=\"$scr_editar\">Modificar</button>"
                      . "<form method='post' action='./' style='display:inline' onSubmit=\"return confirm('¿Cancelar la reservación " . $reserva['id'] . "?');\">"
                      . "<input type='hidden' name='opcion' value='cancelar_reservacion'>"
                      . "<input type='hidden' name='reservacion_id' value='" . $reserva['id'] . "'>"
                      . "<button type='submit'>Cancelar</button>"
                      . "</form>";
        }
        $html .= "<tr><td>" . $reserva['id'] . "</td><td>" . htmlspecialchars($reserva['cliente']) . "</td><td>" . $reserva['mesa_id']
               . "</td><td>" . $reserva['cantidad'] . "</td><td>" . $reserva['inicio'] . "</td><td>" . $reserva['fin']
               . "</td><td>" . ($activa ? "Activa" : "Cancelada") . "</td><td>$acciones</td></tr>";
    }
    $html .= "</table>";

    if ($formulario === null)
        $formulario = "<h2>Registrar una reservación</h2>"
                    . reserva_formulario($conn, 'agregar_reservacion', $_REQUEST, 'Guardar reservación');
    $html .= $formulario;

    return $html;
}

function fn_agregar_reservacion($conn) {
    if ($_SERVER['REQUEST_METHOD'] != 'POST')
        return fn_reservaciones($conn);

    $datos = reserva_leer_formulario($conn, $errores);
    if (count($errores) > 0)
        return fn_reservaciones($conn, reserva_mensajes($errores));

    $reservacion_id = 0;
    $error = reserva_guardar($conn, $datos, $reservacion_id);
    if ($error != "")
        return fn_reservaciones($conn, reserva_mensajes(array($error)));

    $_REQUEST = array();
    return fn_reservaciones($conn, reserva_mensajes(array(
        "Reservación $reservacion_id registrada correctamente: mesa " . $datos['mesa_id'] . " desde el " . substr($datos['inicio'], 0, 16) . " durante 2 horas.")));
}

function fn_editar_reservacion($conn) {
    $reservacion_id = mesa_validar_entero('reservacion_id', 1, 2147483647);
    $actual = ($reservacion_id === null) ? array() : reserva_consulta($conn, "
        SELECT RES.id AS reservacion_id, RES.cliente_id, RES.cantidad, RES.estado, HOR.mesa_id
             , to_char(HOR.inicio, 'YYYY-MM-DD') AS fecha
             , to_char(HOR.inicio, 'HH24:MI') AS hora
        FROM reservaciones AS RES
        LEFT JOIN horarios AS HOR ON HOR.reservacion_id = RES.id
        WHERE RES.id = $1", array($reservacion_id));
    if ($actual === null || count($actual) == 0)
        return fn_reservaciones($conn, reserva_mensajes(array("Error: la reservación indicada no existe.")));
    if ($actual[0]['estado'] == RESERVA_CANCELADA)
        return fn_reservaciones($conn, reserva_mensajes(array("Error: la reservación $reservacion_id está cancelada y no se puede modificar.")));

    $valores = $actual[0];
    $mensaje = "";
    if ($_SERVER['REQUEST_METHOD'] == 'POST') {
        $valores = $_REQUEST;
        $datos = reserva_leer_formulario($conn, $errores);
        if (count($errores) == 0) {
            $error = reserva_guardar($conn, $datos, $reservacion_id);
            if ($error == "") {
                $_REQUEST = array();
                return fn_reservaciones($conn, reserva_mensajes(array(
                    "Reservación $reservacion_id modificada correctamente: mesa " . $datos['mesa_id'] . " desde el " . substr($datos['inicio'], 0, 16) . " durante 2 horas.")));
            }
            $errores[] = $error;
        }
        $mensaje = reserva_mensajes($errores);
    }

    $formulario = "<h2>Modificar la reservación $reservacion_id</h2>"
                . reserva_formulario($conn, 'editar_reservacion', $valores, 'Guardar cambios')
                . "<a href='?opcion=reservaciones'>No modificar</a>";

    return fn_reservaciones($conn, $mensaje, $formulario);
}

function fn_cancelar_reservacion($conn) {
    if ($_SERVER['REQUEST_METHOD'] != 'POST')
        return fn_reservaciones($conn, reserva_mensajes(array("Error: use el botón Cancelar de la tabla para cancelar una reservación.")));

    $reservacion_id = mesa_validar_entero('reservacion_id', 1, 2147483647);
    $_REQUEST = array();
    if ($reservacion_id === null)
        return fn_reservaciones($conn, reserva_mensajes(array("Error: la reservación indicada no existe.")));

    $res = @pg_query_params($conn, 'UPDATE reservaciones SET estado = $1 WHERE id = $2 AND estado IS DISTINCT FROM $1',
                            array(RESERVA_CANCELADA, $reservacion_id));
    if (!$res)
        return fn_reservaciones($conn, reserva_mensajes(array("Error al cancelar la reservación: " . pg_last_error($conn))));
    if (pg_affected_rows($res) == 0)
        return fn_reservaciones($conn, reserva_mensajes(array("Error: la reservación $reservacion_id no existe o ya estaba cancelada.")));

    return fn_reservaciones($conn, reserva_mensajes(array("Reservación $reservacion_id cancelada correctamente. La mesa queda libre en ese horario.")));
}

?>
