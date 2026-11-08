<?php
/*------------------------------------------------------------------*/
// Gestión de empleados y usuarios (Administrador).
// Un usuario puede tener varios roles (tabla actuaciones). Los empleados
// tienen login y clave; los clientes solo nombre y documento.
// El maitre y el mesero pueden registrar clientes nuevos.
/*------------------------------------------------------------------*/

function empleado_roles($conn) {
    return procesar_query("SELECT id, nombre FROM roles ORDER BY nombre", $conn)->datos;
}

/**
 * @brief Lee y valida el formulario de usuario.
 * @param bool $nuevo true al crear (la clave es obligatoria para empleados).
 */
function empleado_leer_formulario($conn, $nuevo, &$errores)
{
    $errores = array();
    $datos = array();
    $datos['nombre'] = isset($_REQUEST['nombre']) ? trim($_REQUEST['nombre']) : "";
    if ($datos['nombre'] == "" || preg_match_all("/./us", $datos['nombre']) > 100)
        $errores[] = "El nombre es obligatorio (máximo 100 caracteres).";

    $datos['documento'] = isset($_REQUEST['documento']) ? trim($_REQUEST['documento']) : "";
    $datos['telefono'] = isset($_REQUEST['telefono']) ? trim($_REQUEST['telefono']) : "";
    $datos['login'] = isset($_REQUEST['login']) ? strtolower(trim($_REQUEST['login'])) : "";
    $datos['clave'] = isset($_REQUEST['clave']) ? $_REQUEST['clave'] : "";
    $datos['activo'] = isset($_REQUEST['activo']) ? 't' : 'f';

    $validos = array();
    foreach (empleado_roles($conn) as $rol)
        $validos[$rol['id']] = $rol['nombre'];
    $datos['roles'] = array();
    $pedidos = (isset($_REQUEST['roles']) && is_array($_REQUEST['roles'])) ? $_REQUEST['roles'] : array();
    foreach ($pedidos as $rol_id)
        if (isset($validos[intval($rol_id)]))
            $datos['roles'][] = intval($rol_id);
    if (count($datos['roles']) == 0)
        $errores[] = "Seleccione al menos un rol.";

    $nombres_roles = array_map(function ($id) use ($validos) { return $validos[$id]; }, $datos['roles']);
    $es_empleado = count(array_diff($nombres_roles, array('Cliente'))) > 0;
    if ($es_empleado) {
        if (!preg_match('/^[a-z0-9._-]{3,30}$/', $datos['login']))
            $errores[] = "Los empleados necesitan un usuario de 3 a 30 caracteres (letras, números, punto, guion).";
        if ($nuevo && $datos['clave'] == "")
            $errores[] = "Asigne una clave inicial al empleado.";
    }
    if ($datos['clave'] != "" && strlen($datos['clave']) < 6)
        $errores[] = "La clave debe tener al menos 6 caracteres.";
    if (in_array('Chef', $nombres_roles) && !in_array('Cocinero', $nombres_roles))
        $errores[] = "El rol Chef solo puede asignarse a un Cocinero.";

    return $datos;
}

/**
 * @brief Guarda el usuario, sus roles y su clave en una transacción.
 * @param int $usuario_id 0 para crear; recibe el id del usuario creado.
 * @return string Mensaje de error, o "" si se guardó.
 */
function empleado_guardar($conn, $datos, &$usuario_id)
{
    $nulo = function ($texto) { return ($texto === "") ? null : $texto; };
    pg_query($conn, "BEGIN");
    $parametros = array($datos['nombre'], $nulo($datos['documento']), $nulo($datos['telefono']),
                        $nulo($datos['login']), $datos['activo']);
    if ($usuario_id == 0) {
        $res = @pg_query_params($conn, 'INSERT INTO usuarios (nombre, documento, telefono, login, activo)
                                        VALUES ($1, $2, $3, $4, $5) RETURNING id', $parametros);
        if ($res)
            $usuario_id = intval(pg_fetch_result($res, 0, 0));
    } else {
        $parametros[] = $usuario_id;
        $res = @pg_query_params($conn, 'UPDATE usuarios SET nombre = $1, documento = $2, telefono = $3, login = $4, activo = $5
                                        WHERE id = $6', $parametros);
    }

    $roles = '{' . implode(',', $datos['roles']) . '}';
    $ok = $res
       && @pg_query_params($conn, 'DELETE FROM actuaciones WHERE usuario_id = $1 AND NOT (rol_id = ANY ($2::int[]))', array($usuario_id, $roles))
       && @pg_query_params($conn, 'INSERT INTO actuaciones (usuario_id, rol_id)
                                   SELECT $1, unnest($2::int[]) ON CONFLICT DO NOTHING', array($usuario_id, $roles));
    if ($ok && $datos['clave'] != "")
        $ok = (bool) @pg_query_params($conn, 'SELECT fn_establecer_clave($1, $2)', array($usuario_id, $datos['clave']));

    if (!$ok) {
        $error = error_bd($conn);
        pg_query($conn, "ROLLBACK");
        if (strpos($error, 'uq_usuarios_login') !== false)
            return "El usuario «" . $datos['login'] . "» ya está en uso.";
        if (strpos($error, 'uq_usuarios_documento') !== false)
            return "Ya existe un usuario con el documento «" . $datos['documento'] . "».";
        return "No se pudo guardar: $error";
    }
    pg_query($conn, "COMMIT");
    return "";
}

/**
 * @brief Formulario de creación / modificación de usuarios.
 */
function empleado_formulario($conn, $valores, $titulo, $boton)
{
    $valor = function ($campo) use ($valores) {
        return isset($valores[$campo]) ? htmlspecialchars($valores[$campo], ENT_QUOTES) : "";
    };
    $roles_actuales = isset($valores['roles']) && is_array($valores['roles']) ? array_map('intval', $valores['roles']) : array();
    $activo = !isset($valores['activo']) || in_array($valores['activo'], array('t', 'on'), true);

    $html = "<h2>$titulo</h2>"
          . "<form method='post' action='./'>"
          . "<input type='hidden' name='opcion' value='guardar_empleado'>";
    if (isset($valores['usuario_id']) && $valores['usuario_id'] != "")
        $html .= "<input type='hidden' name='usuario_id' value='" . $valor('usuario_id') . "'>";
    $html .= "<label>Nombre completo:</label> <input type='text' name='nombre' maxlength='100' value='" . $valor('nombre') . "' required>"
           . "<label>Documento:</label> <input type='text' name='documento' maxlength='50' value='" . $valor('documento') . "'>"
           . "<label>Teléfono:</label> <input type='text' name='telefono' maxlength='30' value='" . $valor('telefono') . "'>"
           . "<label>Usuario (login):</label> <input type='text' name='login' maxlength='30' value='" . $valor('login') . "' autocomplete='off'>"
           . "<label>Clave" . (isset($valores['usuario_id']) ? " (dejar vacía para no cambiarla)" : "") . ":</label> "
           . "<input type='password' name='clave' minlength='6' autocomplete='new-password'>"
           . "<fieldset><legend>Roles</legend>";
    foreach (empleado_roles($conn) as $rol) {
        $marca = in_array(intval($rol['id']), $roles_actuales) ? " checked" : "";
        $html .= "<label><input type='checkbox' name='roles[]' value='" . $rol['id'] . "'$marca> " . htmlspecialchars($rol['nombre']) . "</label> ";
    }
    $html .= "</fieldset>"
           . "<label><input type='checkbox' name='activo'" . ($activo ? " checked" : "") . "> Activo</label>"
           . "<button type='submit'>$boton</button>"
           . "</form>"
           . "<p><small>Los empleados (maitre, mesero, cocinero...) necesitan usuario y clave. "
           . "Los clientes no inician sesión. El rol Chef habilita la autorización de platos especiales.</small></p>";
    return $html;
}

/*------------------------------------------------------------------*/
/**
 * @brief Página de gestión de empleados y usuarios.
 */
function fn_empleados($conn, $mensaje = "", $formulario = null)
/*--------------------------------------------------------------------*/
{
    $filtro = isset($_REQUEST['filtro']) ? $_REQUEST['filtro'] : 'empleados';
    $condicion = "";
    if ($filtro == 'empleados')
        $condicion = "HAVING bool_or(r.nombre <> 'Cliente')";
    elseif ($filtro == 'clientes')
        $condicion = "HAVING bool_and(r.nombre = 'Cliente')";

    $usuarios = procesar_query("
        SELECT u.id, u.nombre, u.login, u.documento, u.telefono, u.activo,
               to_char(u.fecha_clave, 'YYYY-MM-DD') AS fecha_clave,
               string_agg(r.nombre, ', ' ORDER BY r.nombre) AS roles
        FROM usuarios u
        LEFT JOIN actuaciones a ON a.usuario_id = u.id
        LEFT JOIN roles r ON r.id = a.rol_id
        GROUP BY u.id
        $condicion
        ORDER BY u.activo DESC, u.nombre", $conn);

    $html = fn_boton_menu_principal()
          . "<button onClick=\"window.open('?opcion=autorizaciones_cocina', '_top');\">Autorizaciones de cocina</button>"
          . "<h2>Empleados y usuarios</h2>"
          . $mensaje;

    $html .= "<p>";
    foreach (array('empleados' => 'Empleados', 'clientes' => 'Clientes', 'todos' => 'Todos') as $clave => $texto)
        $html .= ($clave == $filtro) ? "<strong>$texto</strong> " : "<a class='FILTRO' href='?opcion=empleados&filtro=$clave'>$texto</a> ";
    $html .= "</p>";

    $html .= "<table><tr><th>Nombre</th><th>Usuario</th><th>Documento</th><th>Teléfono</th><th>Roles</th><th>Clave desde</th><th>Estado</th><th></th></tr>";
    foreach ($usuarios->datos as $u) {
        $scr_editar = "window.open('?opcion=editar_empleado&usuario_id=" . $u['id'] . "', '_top');";
        $html .= "<tr" . ($u['activo'] == 't' ? "" : " class='INACTIVO'") . ">"
               . "<td>" . htmlspecialchars($u['nombre']) . "</td>"
               . "<td>" . htmlspecialchars($u['login']) . "</td>"
               . "<td>" . htmlspecialchars($u['documento']) . "</td>"
               . "<td>" . htmlspecialchars($u['telefono']) . "</td>"
               . "<td>" . htmlspecialchars($u['roles']) . "</td>"
               . "<td>" . $u['fecha_clave'] . "</td>"
               . "<td>" . ($u['activo'] == 't' ? "Activo" : "Inactivo") . "</td>"
               . "<td><button onClick=\"$scr_editar\">Modificar</button></td></tr>";
    }
    $html .= "</table>";

    if ($formulario === null)
        $formulario = empleado_formulario($conn, array(), "Registrar un usuario", "Guardar usuario");
    return $html . $formulario;
}

function fn_editar_empleado($conn) {
    $usuario_id = mesa_validar_entero('usuario_id', 1, 2147483647);
    $actual = ($usuario_id === null) ? array() : reserva_consulta($conn, "
        SELECT u.id AS usuario_id, u.nombre, u.documento, u.telefono, u.login, u.activo,
               array_to_json(array_remove(array_agg(a.rol_id), NULL)) AS roles
        FROM usuarios u LEFT JOIN actuaciones a ON a.usuario_id = u.id
        WHERE u.id = $1 GROUP BY u.id", array($usuario_id));
    if (!$actual)
        return fn_empleados($conn, mensaje_error("El usuario indicado no existe."));
    $valores = $actual[0];
    $valores['roles'] = json_decode($valores['roles'], true);
    $formulario = empleado_formulario($conn, $valores, "Modificar a " . htmlspecialchars($valores['nombre']), "Guardar cambios")
                . "<a href='?opcion=empleados'>No modificar</a>";
    return fn_empleados($conn, "", $formulario);
}

/*------------------------------------------------------------------*/
/**
 * @brief Crea o modifica un usuario con sus roles.
 */
function fn_guardar_empleado($conn)
/*--------------------------------------------------------------------*/
{
    if ($_SERVER['REQUEST_METHOD'] != 'POST')
        return fn_empleados($conn);
    $usuario_id = mesa_validar_entero('usuario_id', 1, 2147483647);
    $nuevo = ($usuario_id === null);
    $datos = empleado_leer_formulario($conn, $nuevo, $errores);

    // El administrador no puede quitarse a sí mismo el acceso
    if (!$nuevo && $usuario_id == sesion_id()) {
        $admin = reserva_consulta($conn, "SELECT id FROM roles WHERE nombre = 'Administrador'");
        if ($datos['activo'] != 't' || !in_array(intval($admin[0]['id']), $datos['roles']))
            $errores[] = "No puede desactivarse ni quitarse el rol Administrador a sí mismo.";
    }

    if (count($errores) == 0) {
        $id = $nuevo ? 0 : $usuario_id;
        $error = empleado_guardar($conn, $datos, $id);
        if ($error == "") {
            $_REQUEST = array();
            return fn_empleados($conn, mensaje_ok("Usuario «" . $datos['nombre'] . "» guardado correctamente."));
        }
        $errores[] = $error;
    }

    $mensaje = "";
    foreach ($errores as $error)
        $mensaje .= mensaje_error($error);
    $valores = $_REQUEST;
    $valores['roles'] = $datos['roles'];
    $titulo = $nuevo ? "Registrar un usuario" : "Modificar el usuario";
    return fn_empleados($conn, $mensaje, empleado_formulario($conn, $valores, $titulo, "Guardar"));
}

/*------------------------------------------------------------------*/
/**
 * @brief Registro rápido de clientes (maitre y mesero).
 *        Parámetro volver: opción a la que se regresa después.
 */
function fn_registrar_cliente($conn)
/*--------------------------------------------------------------------*/
{
    $volver = (isset($_REQUEST['volver']) && in_array($_REQUEST['volver'], array('reservaciones', 'realizar_pedidos')))
            ? $_REQUEST['volver'] : '';
    $mensaje = "";
    if ($_SERVER['REQUEST_METHOD'] == 'POST') {
        $nombre = isset($_REQUEST['nombre']) ? trim($_REQUEST['nombre']) : "";
        $documento = isset($_REQUEST['documento']) ? trim($_REQUEST['documento']) : "";
        $telefono = isset($_REQUEST['telefono']) ? trim($_REQUEST['telefono']) : "";
        if ($nombre == "") {
            $mensaje = mensaje_error("El nombre del cliente es obligatorio.");
        } else {
            pg_query($conn, "BEGIN");
            $res = @pg_query_params($conn, 'INSERT INTO usuarios (nombre, documento, telefono) VALUES ($1, $2, $3) RETURNING id',
                                    array($nombre, $documento === "" ? null : $documento, $telefono === "" ? null : $telefono));
            $ok = $res && @pg_query_params($conn, "INSERT INTO actuaciones (usuario_id, rol_id)
                                                   SELECT $1, id FROM roles WHERE nombre = 'Cliente'",
                                           array(pg_fetch_result($res, 0, 0)));
            if ($ok) {
                pg_query($conn, "COMMIT");
                $cliente_id = intval(pg_fetch_result($res, 0, 0));
                $texto = "Cliente «" . $nombre . "» registrado.";
                $_REQUEST = array('cliente_id' => $cliente_id);
                if ($volver == 'reservaciones')
                    return fn_reservaciones($conn, mensaje_ok($texto . " Ya puede registrar su reservación."));
                if ($volver == 'realizar_pedidos')
                    return fn_realizar_pedidos($conn, mensaje_ok($texto . " Seleccione la mesa del pedido."));
                $mensaje = mensaje_ok($texto);
            } else {
                $error = error_bd($conn);
                pg_query($conn, "ROLLBACK");
                $mensaje = mensaje_error(strpos($error, 'uq_usuarios_documento') !== false
                                         ? "Ya existe un cliente con ese documento." : "No se pudo registrar: $error");
            }
        }
    }

    return fn_boton_menu_principal()
         . "<h2>Registrar un cliente</h2>"
         . $mensaje
         . "<form method='post' action='./'>"
         . "<input type='hidden' name='opcion' value='registrar_cliente'>"
         . "<input type='hidden' name='volver' value='$volver'>"
         . "<label>Nombre completo:</label> <input type='text' name='nombre' maxlength='100' required>"
         . "<label>Documento:</label> <input type='text' name='documento' maxlength='50'>"
         . "<label>Teléfono:</label> <input type='text' name='telefono' maxlength='30'>"
         . "<button type='submit'>Registrar cliente</button>"
         . "</form>";
}

?>
