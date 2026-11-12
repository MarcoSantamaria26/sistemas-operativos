#!/usr/bin/env bash

declare -r DB_FILE="data.sq3"          # Archivo de la base de datos SQLite3
declare -r LOG_SYS="system.log"        # Archivo de auditoría de acciones
declare -r LOG_ERR="error.log"         # Archivo de registro de errores

# Variables globales para control de sesión activa
declare GLOBAL_USER_ID=""
declare GLOBAL_USER_NAME=""

declare -r -i OPCION_ALTA=1
declare -r -i OPCION_EDITAR=2
declare -r -i OPCION_BAJA=3
declare -r -i OPCION_MOSTRAR=4
declare -r -i OPCION_REPORTE=5
declare -r -i OPCION_SALIR=6

registrar_log_sistema() {
    local accion=$1
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S') # Obtiene fecha y hora actual
    printf "%s\t%s\t%s\t%s\n" "$timestamp" "$GLOBAL_USER_ID" "$GLOBAL_USER_NAME" "$accion" >> "$LOG_SYS"
}

registrar_log_error() {
    local mensaje_error=$1
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    printf "%s\tERROR:\t%s\n" "$timestamp" "$mensaje_error" >> "$LOG_ERR"
}

# Muestra una ventana de mensaje simple (Aceptar)
tui_msg() {
    local titulo=$1
    local mensaje=$2
    whiptail --title "$titulo" --msgbox "$mensaje" 10 50
}

# Muestra una caja de entrada de texto y captura el resultado
tui_input() {
    local mensaje=$1
    # Whiptail devuelve el texto por el canal de errores (2), 
    # por eso usamos el intercambio de descriptores (3>&1 1>&2 2>&3) para capturarlo en la variable.
    whiptail --title "Sistema de Inventario TUI" --inputbox "$mensaje" 8 50 3>&1 1>&2 2>&3
}

# Muestra una caja de entrada segura para contraseñas (oculta los caracteres con asteriscos)
tui_password() {
    local mensaje=$1
    whiptail --title "Seguridad" --passwordbox "$mensaje" 8 50 3>&1 1>&2 2>&3
}

inicializar_base_datos() {
    if [[ ! -f "$DB_FILE" ]]; then
        sqlite3 "$DB_FILE" <<EOF
        CREATE TABLE usuarios (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            usuario TEXT UNIQUE NOT NULL,
            password_hash TEXT NOT NULL
        );

        CREATE TABLE productos (
            id INTEGER PRIMARY KEY,
            nombre TEXT NOT NULL,
            precio REAL NOT NULL,
            activo INTEGER NOT NULL DEFAULT 1
        );
EOF
        registrar_log_sistema "Base de datos creada e inicializada."
    fi
}

cifrar_sha256() {
    local texto=$1
    printf "%s" "$texto" | sha256sum | awk '{print $1}'
}

registrar_usuario() {
    local nuevo_usuario=""
    local nueva_clave=""
    local pass_hash=""
    local resultado_sql=""

    nuevo_usuario=$(tui_input "Ingrese nombre de nuevo usuario:")
    
    # Si el usuario cancela o deja vacío, retorna
    [[ -z "$nuevo_usuario" ]] && return

    nueva_clave=$(tui_password "Ingrese contraseña para '$nuevo_usuario':")
    [[ -z "$nueva_clave" ]] && return

    pass_hash=$(cifrar_sha256 "$nueva_clave")

    resultado_sql=$(sqlite3 "$DB_FILE" "INSERT INTO usuarios (usuario, password_hash) VALUES ('$nuevo_usuario', '$pass_hash');" 2>&1)

    if [[ -n "$resultado_sql" ]]; then
        tui_msg "Error" "El usuario '$nuevo_usuario' ya existe o hubo un fallo."
        registrar_log_error "Fallo al registrar usuario '$nuevo_usuario': $resultado_sql"
    else
        tui_msg "Éxito" "Usuario registrado correctamente."
        registrar_log_sistema "Registro exitoso del usuario: $nuevo_usuario"
    fi
}

iniciar_sesion() {
    local user_ingresado=""
    local pass_ingresada=""
    local pass_hash_ingresado=""
    local query_res=""

    user_ingresado=$(tui_input "Ingrese su usuario:")
    [[ -z "$user_ingresado" ]] && return 1

    pass_ingresada=$(tui_password "Ingrese su contraseña:")
    [[ -z "$pass_ingresada" ]] && return 1

    pass_hash_ingresado=$(cifrar_sha256 "$pass_ingresada")

    query_res=$(sqlite3 "$DB_FILE" "SELECT id FROM usuarios WHERE usuario = '$user_ingresado' AND password_hash = '$pass_hash_ingresado';")

    if [[ -n "$query_res" ]]; then
        GLOBAL_USER_ID="$query_res"
        GLOBAL_USER_NAME="$user_ingresado"
        registrar_log_sistema "Inicio de sesión exitoso."
        return 0
    else
        tui_msg "Acceso Denegado" "Usuario o contraseña incorrectos."
        registrar_log_error "Intento de inicio de sesión fallido para: $user_ingresado"
        return 1
    fi
}

menu_autenticacion() {
    local opcion_auth=""

    while true; do
        # Menú visual con whiptail donde el usuario se mueve con flechitas
        opcion_auth=$(whiptail --title "Autenticación del Sistema" --menu "Seleccione una opción:" 12 50 2 \
            "1" "Iniciar sesión" \
            "2" "Registrar usuario" 3>&1 1>&2 2>&3)

        # Si el usuario presiona Cancelar (Esc), sale del script
        [[ $? -ne 0 ]] && exit 0

        case $opcion_auth in
            1)
                if iniciar_sesion; then
                    break # Rompe el ciclo y entra al sistema si el login es correcto
                fi
                ;;
            2)
                registrar_usuario
                ;;
        esac
    done
}

alta() {
    local id_str=""
    local nombre=""
    local precio_str=""
    local existe_id=""
    local resultado_sql=""

    id_str=$(tui_input "Ingrese el ID del nuevo producto:")
    [[ -z "$id_str" ]] && return

    nombre=$(tui_input "Ingrese el Nombre del producto:")
    [[ -z "$nombre" ]] && return

    precio_str=$(tui_input "Ingrese el Precio del producto:")
    [[ -z "$precio_str" ]] && return

    existe_id=$(sqlite3 "$DB_FILE" "SELECT id FROM productos WHERE id = $id_str AND activo = 1;")

    if [[ -n "$existe_id" ]]; then
        tui_msg "Error" "El producto con ID $id_str ya existe."
        registrar_log_error "Intento de alta duplicada para ID: $id_str"
        return
    fi

    resultado_sql=$(sqlite3 "$DB_FILE" "INSERT OR REPLACE INTO productos (id, nombre, precio, activo) VALUES ($id_str, '$nombre', $precio_str, 1);" 2>&1)

    if [[ -n "$resultado_sql" ]]; then
        tui_msg "Error" "Fallo al guardar en la base de datos."
        registrar_log_error "SQL Error en alta ID $id_str: $resultado_sql"
    else
        tui_msg "Éxito" "Producto guardado correctamente."
        registrar_log_sistema "Alta exitosa de producto ID $id_str ($nombre)"
    fi
}

editar() {
    local id_str=""
    local consulta=""
    local nombre_prod=""
    local activo_prod=""
    local nuevo_precio=""
    local resultado_sql=""

    id_str=$(tui_input "Ingrese el ID del producto a EDITAR:")
    [[ -z "$id_str" ]] && return

    consulta=$(sqlite3 "$DB_FILE" "SELECT nombre, activo FROM productos WHERE id = $id_str;")

    if [[ -z "$consulta" ]]; then
        tui_msg "Error" "El producto no existe."
        registrar_log_error "Edición sobre producto inexistente ID $id_str"
        return
    fi

    nombre_prod=$(echo "$consulta" | cut -d'|' -f1)
    activo_prod=$(echo "$consulta" | cut -d'|' -f2)

    if [[ "$activo_prod" != "1" ]]; then
        tui_msg "Error" "El producto está inactivo y no se puede editar."
        return
    fi

    nuevo_precio=$(tui_input "Ingrese nuevo Precio para '$nombre_prod':")
    [[ -z "$nuevo_precio" ]] && return

    resultado_sql=$(sqlite3 "$DB_FILE" "UPDATE productos SET precio = $nuevo_precio WHERE id = $id_str;" 2>&1)

    if [[ -n "$resultado_sql" ]]; then
        tui_msg "Error" "Fallo al actualizar el producto."
        registrar_log_error "SQL Error en edición ID $id_str: $resultado_sql"
    else
        tui_msg "Éxito" "Producto actualizado correctamente."
        registrar_log_sistema "Edición exitosa de producto ID $id_str"
    fi
}

baja() {
    local id_str=""
    local activo_prod=""
    local resultado_sql=""

    id_str=$(tui_input "Ingrese el ID del producto a ELIMINAR:")
    [[ -z "$id_str" ]] && return

    activo_prod=$(sqlite3 "$DB_FILE" "SELECT activo FROM productos WHERE id = $id_str;")

    if [[ -z "$activo_prod" ]]; then
        tui_msg "Error" "El producto no existe."
        return
    elif [[ "$activo_prod" == "0" ]]; then
        tui_msg "Aviso" "El producto ya se encontraba inactivo."
        return
    fi

    resultado_sql=$(sqlite3 "$DB_FILE" "UPDATE productos SET activo = 0 WHERE id = $id_str;" 2>&1)

    if [[ -n "$resultado_sql" ]]; then
        tui_msg "Error" "Fallo al eliminar el producto."
        registrar_log_error "SQL Error en baja ID $id_str: $resultado_sql"
    else
        tui_msg "Éxito" "Producto eliminado correctamente."
        registrar_log_sistema "Baja lógica exitosa del producto ID $id_str"
    fi
}

mostrar() {
    local listado=""
    
    # Preparamos el texto formateado para mostrar dentro de una ventana de texto (textbox / msgbox)
    listado=$(sqlite3 "$DB_FILE" "SELECT id || ' | ' || nombre || ' | $' || precio FROM productos WHERE activo = 1;")

    if [[ -z "$listado" ]]; then
        tui_msg "Inventario" "El inventario está vacío."
    else
        whiptail --title "Listado de Inventario" --msgbox "$listado" 15 50
    fi
    registrar_log_sistema "Consulta de inventario (Mostrar TUI)."
}

generar_html() {
    declare archivo_html="productos.html"
    
    cat << EOF > "$archivo_html"
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <title>Reporte de Productos</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; background-color: #f4f4f9; }
        h1 { color: #333; }
        table { width: 100%; border-collapse: collapse; background: #fff; }
        th, td { padding: 12px; border: 1px solid #ddd; text-align: left; }
        th { background-color: #007bff; color: white; }
    </style>
</head>
<body>
    <h1>Listado de Inventario</h1>
    <table>
        <tr>
            <th>ID</th>
            <th>Nombre</th>
            <th>Precio</th>
        </tr>
EOF

    sqlite3 "$DB_FILE" "SELECT id, nombre, precio FROM productos WHERE activo = 1;" | while IFS='|' read -r id nombre precio; do
        printf "        <tr>\n            <td>%s</td>\n            <td>%s</td>\n            <td>$%s</td>\n        </tr>\n" "$id" "$nombre" "$precio" >> "$archivo_html"
    done

    cat << EOF >> "$archivo_html"
    </table>
</body>
</html>
EOF

    tui_msg "Reporte" "Reporte 'productos.html' generado exitosamente."
    registrar_log_sistema "Generación de reporte HTML."
}

main() {
    inicializar_base_datos
    menu_autenticacion

    local opcion=""

    while true; do
        # Menú principal visual con whiptail
        opcion=$(whiptail --title "Menú Principal - Inventario" --menu "Seleccione una acción:" 16 50 6 \
            "1" "Alta producto" \
            "2" "Editar producto existente" \
            "3" "Baja producto" \
            "4" "Mostrar inventario" \
            "5" "Generar reporte HTML" \
            "6" "Salir" 3>&1 1>&2 2>&3)

        # Si presiona cancelar o sale, interrumpe el bucle y cierra
        [[ $? -ne 0 ]] && break

        case $opcion in
            $OPCION_ALTA)
                alta
                ;;
            $OPCION_EDITAR)
                editar
                ;;
            $OPCION_BAJA)
                baja
                ;;
            $OPCION_MOSTRAR)
                mostrar
                ;;
            $OPCION_REPORTE)
                generar_html
                ;;
            $OPCION_SALIR)
                registrar_log_sistema "Salida del sistema."
                break
                ;;
        esac
    done

    clear
    printf "Saliendo del programa...\n"
    return 0
}

main