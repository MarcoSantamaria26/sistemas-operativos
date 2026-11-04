#!/usr/bin/env bash

declare -r DB_FILE="data.sq3"
declare -r LOG_SYS="system.log"
declare -r LOG_ERR="error.log"

# Variables globales para control de sesión activa
declare GLOBAL_USER_ID=""
declare GLOBAL_USER_NAME=""

declare -r -i OPCION_ALTA=1
declare -r -i OPCION_EDITAR=2
declare -r -i OPCION_BAJA=3
declare -r -i OPCION_MOSTRAR=4
declare -r -i OPCION_REPORTE=5
declare -r -i OPCION_SALIR=6

# Registra las acciones exitosas en system.log en formato TSV
registrar_log_sistema() {
    local accion=$1
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S') # Obtiene fecha y hora actual del sistema
    
    # Formato TSV: FechaHora \t ID_Usuario \t Nombre_Usuario \t Acción
    printf "%s\t%s\t%s\t%s\n" "$timestamp" "$GLOBAL_USER_ID" "$GLOBAL_USER_NAME" "$accion" >> "$LOG_SYS"
}

# Registra los errores en error.log con timestamp
registrar_log_error() {
    local mensaje_error=$1
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    printf "%s\tERROR:\t%s\n" "$timestamp" "$mensaje_error" >> "$LOG_ERR"
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

bienvenida() {
    printf "\n\nBienvenido/a al sistema de inventario con SQLite3\n\n"
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

    printf "\n--- REGISTRO DE NUEVO USUARIO ---\n"
    read -rp "Ingrese nombre de usuario: " nuevo_usuario

    if [[ -z "$nuevo_usuario" ]]; then
        printf "Error: El nombre de usuario no puede estar vacío.\n"
        registrar_log_error "Intento de registro con usuario vacío."
        return
    fi

    read -rs -p "Ingrese contraseña: " nueva_clave
    printf "\n"

    pass_hash=$(cifrar_sha256 "$nueva_clave")

    # Intentamos insertar en la base de datos. SQLite arroja error si el usuario ya existe por el UNIQUE.
    resultado_sql=$(sqlite3 "$DB_FILE" "INSERT INTO usuarios (usuario, password_hash) VALUES ('$nuevo_usuario', '$pass_hash');" 2>&1)

    if [[ -n "$resultado_sql" ]]; then
        printf "Error: El usuario '%s' ya existe o hubo un fallo en la DB.\n" "$nuevo_usuario"
        registrar_log_error "Fallo al registrar usuario '$nuevo_usuario': $resultado_sql"
    else
        printf "Usuario registrado exitosamente.\n"
        registrar_log_sistema "Registro exitoso del usuario: $nuevo_usuario"
    fi
}

iniciar_sesion() {
    local user_ingresado=""
    local pass_ingresada=""
    local pass_hash_ingresado=""
    local query_res=""

    printf "\n--- INICIO DE SESIÓN ---\n"
    read -rp "Usuario: " user_ingresado
    read -rs -p "Contraseña: " pass_ingresada
    printf "\n"

    pass_hash_ingresado=$(cifrar_sha256 "$pass_ingresada")

    # Consultamos en SQLite si coincide el usuario y el hash de la contraseña
    query_res=$(sqlite3 "$DB_FILE" "SELECT id FROM usuarios WHERE usuario = '$user_ingresado' AND password_hash = '$pass_hash_ingresado';")

    if [[ -n "$query_res" ]]; then
        # Guardamos las credenciales globales del usuario autenticado para los logs
        GLOBAL_USER_ID="$query_res"
        GLOBAL_USER_NAME="$user_ingresado"
        
        printf "Acceso concedido. ¡Bienvenido/a %s!\n" "$user_ingresado"
        registrar_log_sistema "Inicio de sesión exitoso."
        return 0
    else
        printf "Error: Usuario o contraseña incorrectos.\n"
        registrar_log_error "Intento de inicio de sesión fallido para el usuario: $user_ingresado"
        return 1
    fi
}

menu_autenticacion() {
    local opcion_auth=0

    while (( opcion_auth != 1 && opcion_auth != 2 )); do
        printf "\n--- AUTENTICACIÓN ---\n"
        printf "1. Iniciar sesión\n"
        printf "2. Registrar usuario\n"
        read -rp "Seleccione una opción (1-2): " opcion_auth

        case $opcion_auth in
            1)
                if ! iniciar_sesion; then
                    opcion_auth=0
                fi
                ;;
            2)
                registrar_usuario
                opcion_auth=0
                ;;
            *)
                printf "Opción inválida.\n"
                registrar_log_error "Opción de autenticación inválida seleccionada."
                opcion_auth=0
                ;;
        esac
    done
}

alta() {
    declare -i id=$1
    declare nombre=$2
    declare precio=$3
    local existe_id=""
    local resultado_sql=""

    # Verificamos si ya existe un producto activo con ese ID en SQLite
    existe_id=$(sqlite3 "$DB_FILE" "SELECT id FROM productos WHERE id = $id AND activo = 1;")

    if [[ -n "$existe_id" ]]; then
        printf "Error: El producto con ID %d ya existe.\n" "$id"
        registrar_log_error "Intento de alta duplicada para ID de producto: $id"
        return
    fi

    resultado_sql=$(sqlite3 "$DB_FILE" "INSERT OR REPLACE INTO productos (id, nombre, precio, activo) VALUES ($id, '$nombre', $precio, 1);" 2>&1)

    if [[ -n "$resultado_sql" ]]; then
        printf "Error al guardar el producto en la base de datos.\n"
        registrar_log_error "SQL Error en alta ID $id: $resultado_sql"
    else
        printf "Producto %d (%s) guardado con precio $%s.\n" "$id" "$nombre" "$precio"
        registrar_log_sistema "Alta exitosa de producto ID $id ($nombre)"
    fi
}

editar() {
    declare -i id_editar=$1
    local nombre_prod=""
    local activo_prod=""
    local nuevo_precio=""
    local consulta=""
    local resultado_sql=""

    # Consultamos nombre y estado del producto en SQL
    consulta=$(sqlite3 "$DB_FILE" "SELECT nombre, activo FROM productos WHERE id = $id_editar;")

    if [[ -z "$consulta" ]]; then
        printf "El producto no existe.\n"
        registrar_log_error "Intento de edición sobre producto inexistente ID $id_editar"
        return
    fi

    # Extraemos los campos separados por el pipe '|' que devuelve sqlite3 por defecto
    nombre_prod=$(echo "$consulta" | cut -d'|' -f1)
    activo_prod=$(echo "$consulta" | cut -d'|' -f2)

    if [[ "$activo_prod" != "1" ]]; then
        printf "El producto está inactivo y no se puede editar.\n"
        registrar_log_error "Intento de edición sobre producto inactivo ID $id_editar"
        return
    fi

    read -rp "Ingrese nuevo Precio para '$nombre_prod': " nuevo_precio

    if [[ -z "$nuevo_precio" ]]; then
        printf "Error: El precio no puede estar vacío.\n"
        return
    fi

    resultado_sql=$(sqlite3 "$DB_FILE" "UPDATE productos SET precio = $nuevo_precio WHERE id = $id_editar;" 2>&1)

    if [[ -n "$resultado_sql" ]]; then
        printf "Error al actualizar el producto.\n"
        registrar_log_error "SQL Error en edición ID $id_editar: $resultado_sql"
    else
        printf "Producto %d actualizado con el nuevo precio $%s.\n" "$id_editar" "$nuevo_precio"
        registrar_log_sistema "Edición exitosa de producto ID $id_editar (Nuevo precio: $$nuevo_precio)"
    fi
}

baja() {
    declare -i id_baja=$1
    local activo_prod=""
    local resultado_sql=""

    # Verificamos estado actual del producto
    activo_prod=$(sqlite3 "$DB_FILE" "SELECT activo FROM productos WHERE id = $id_baja;")

    if [[ -z "$activo_prod" ]]; then
        printf "El producto no existe.\n"
        registrar_log_error "Intento de baja sobre producto inexistente ID $id_baja"
        return
    elif [[ "$activo_prod" == "0" ]]; then
        printf "El producto ya se encontraba inactivo.\n"
        registrar_log_error "Intento de baja redundante sobre producto ya inactivo ID $id_baja"
        return
    fi

    resultado_sql=$(sqlite3 "$DB_FILE" "UPDATE productos SET activo = 0 WHERE id = $id_baja;" 2>&1)

    if [[ -n "$resultado_sql" ]]; then
        printf "Error al dar de baja el producto.\n"
        registrar_log_error "SQL Error en baja ID $id_baja: $resultado_sql"
    else
        printf "Producto %d eliminado.\n" "$id_baja"
        registrar_log_sistema "Baja lógica exitosa del producto ID $id_baja"
    fi
}

mostrar() {
    printf "\nLISTADO:\n"
    sqlite3 "$DB_FILE" "SELECT id, nombre, precio FROM productos WHERE activo = 1;" | while IFS='|' read -r id nombre precio; do
        printf "ID %s : %s - $%s\n" "$id" "$nombre" "$precio"
    done
    registrar_log_sistema "Consulta de inventario (Mostrar)."
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

    printf "\nReporte 'productos.html' generado exitosamente.\n"
    registrar_log_sistema "Generación de reporte HTML."
}

main() {

    inicializar_base_datos
    bienvenida

    menu_autenticacion

    declare opcion=0
    declare -i id=0
    declare nombre=""
    declare precio=""

    while [[ "$opcion" != "$OPCION_SALIR" ]]; do
        printf "\nACCIONES:\n"
        printf "1. Alta producto\n"
        printf "2. Editar producto existente\n"
        printf "3. Baja producto\n"
        printf "4. Mostrar inventario\n"
        printf "5. Generar reporte HTML\n"
        printf "6. Salir\n"
        read -rp "Opcion: " opcion
        printf "\n"

        case $opcion in
            $OPCION_ALTA)
                read -rp "Ingrese ID: " id
                read -rp "Ingrese Nombre: " nombre
                read -rp "Ingrese Precio: " precio
                alta "$id" "$nombre" "$precio"
                ;;
            $OPCION_EDITAR)
                read -rp "Ingrese ID a editar: " id
                editar "$id"
                ;;
            $OPCION_BAJA)
                read -rp "Ingrese ID a eliminar: " id
                baja "$id"
                ;;
            $OPCION_MOSTRAR)
                mostrar
                ;;
            $OPCION_REPORTE)
                generar_html
                ;;
            $OPCION_SALIR)
                printf "\nSaliendo del programa...\n"
                registrar_log_sistema "Salida del sistema."
                ;;
            *)
                printf "\nOpcion invalida.\n"
                registrar_log_error "Opción de menú principal inválida seleccionada."
                ;;
        esac
    done

    return 0
}

main