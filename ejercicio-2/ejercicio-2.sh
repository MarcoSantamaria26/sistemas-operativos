#!/usr/bin/env bash

declare -r ARCHIVO_PROD="productos.tsv"
declare -r ARCHIVO_USER="usuarios.tsv"

declare -r -i OPCION_ALTA=1
declare -r -i OPCION_EDITAR=2
declare -r -i OPCION_BAJA=3
declare -r -i OPCION_MOSTRAR=4
declare -r -i OPCION_REPORTE=5
declare -r -i OPCION_SALIR=6

bienvenida() {
    printf "\n\nBienvenido/a al sistema\n\n"
}

inicializar_archivos() {
    if [[ ! -f "$ARCHIVO_PROD" ]]; then
        touch "$ARCHIVO_PROD"
    fi
    if [[ ! -f "$ARCHIVO_USER" ]]; then
        touch "$ARCHIVO_USER"
    fi
}

# Función para cifrar texto con sha256sum (sacando saltos de línea y el guión del comando)
cifrar_sha256() {
    local texto=$1
    printf "%s" "$texto" | sha256sum | awk '{print $1}'
}

registrar_usuario() {
    local nuevo_usuario=""
    local nueva_clave=""
    local pass_hash=""
    local existe=0

    printf "\n--- REGISTRO DE NUEVO USUARIO ---\n"
    read -rp "Ingrese nombre de usuario: " nuevo_usuario

    # Validar si el usuario ya existe en usuarios.tsv
    if [[ -s "$ARCHIVO_USER" ]]; then
        while IFS=$'\t' read -r u_user u_pass; do
            u_user=$(echo "$u_user" | tr -d '\r')
            if [[ "$u_user" == "$nuevo_usuario" ]]; then
                existe=1
                break
            fi
        done < "$ARCHIVO_USER"
    fi

    if (( existe == 1 )); then
        printf "Error: El usuario '%s' ya existe.\n" "$nuevo_usuario"
        return
    fi

    read -rs -p "Ingrese contraseña: " nueva_clave
    printf "\n"

    # Ciframos la contraseña usando sha256sum
    pass_hash=$(cifrar_sha256 "$nueva_clave")

    # Guardamos en usuarios.tsv (Usuario \t HashSHA256)
    printf "%s\t%s\n" "$nuevo_usuario" "$pass_hash" >> "$ARCHIVO_USER"
    printf "Usuario registrado exitosamente.\n"
}

iniciar_sesion() {
    local user_ingresado=""
    local pass_ingresada=""
    local pass_hash_ingresado=""
    local login_exitoso=0

    printf "\n--- INICIO DE SESIÓN ---\n"
    read -rp "Usuario: " user_ingresado
    read -rs -p "Contraseña: " pass_ingresada
    printf "\n"

    pass_hash_ingresado=$(cifrar_sha256 "$pass_ingresada")

    if [[ -s "$ARCHIVO_USER" ]]; then
        while IFS=$'\t' read -r u_user u_pass; do
            u_user=$(echo "$u_user" | tr -d '\r')
            u_pass=$(echo "$u_pass" | tr -d '\r')

            if [[ "$u_user" == "$user_ingresado" && "$u_pass" == "$pass_hash_ingresado" ]]; then
                login_exitoso=1
                break
            fi
        done < "$ARCHIVO_USER"
    fi

    if (( login_exitoso == 1 )); then
        printf "Acceso concedido. ¡Bienvenido/a %s!\n" "$user_ingresado"
        return 0
    else
        printf "Error: Usuario o contraseña incorrectos.\n"
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
                    opcion_auth=0 # Si falla, vuelve a mostrar el menú
                fi
                ;;
            2)
                registrar_usuario
                opcion_auth=0 # Vuelve a mostrar el menú para que pueda iniciar sesión despues de registrarse
                ;;
            *)
                printf "Opción inválida.\n"
                opcion_auth=0
                ;;
        esac
    done
}

alta() {
    declare -i id=$1
    declare nombre=$2
    declare precio=$3
    declare existe=0

    if [[ -s "$ARCHIVO_PROD" ]]; then
        while IFS=$'\t' read -r p_id p_nombre p_precio p_activo; do
            p_id=$(echo "$p_id" | tr -d '\r')
            p_activo=$(echo "$p_activo" | tr -d '\r')
            if [[ -n "$p_id" ]] && (( p_id == id )) && [[ "$p_activo" == "1" ]]; then
                existe=1
                break
            fi
        done < "$ARCHIVO_PROD"
    fi

    if (( existe == 1 )); then
        printf "Error: El producto con ID %d ya existe.\n" "$id"
        return
    fi

    printf "%d\t%s\t%s\t1\n" "$id" "$nombre" "$precio" >> "$ARCHIVO_PROD"
    printf "Producto %d (%s) guardado con precio $%s.\n" "$id" "$nombre" "$precio"
}

editar() {
    declare -i id_editar=$1
    declare nuevo_precio=""
    declare encontrado=0
    declare archivo_temp="productos.tmp"
    declare nombre_antiguo=""
    declare activo_actual=0

    if [[ -s "$ARCHIVO_PROD" ]]; then
        while IFS=$'\t' read -r id nombre precio activo; do
            id=$(echo "$id" | tr -d '\r')
            activo=$(echo "$activo" | tr -d '\r')
            if [[ -n "$id" ]] && (( id == id_editar )); then
                nombre_antiguo="$nombre"
                activo_actual="$activo"
                break
            fi
        done < "$ARCHIVO_PROD"
    fi

    if [[ -z "$nombre_antiguo" ]]; then
        printf "El producto no existe.\n"
        return
    elif [[ "$activo_actual" != "1" ]]; then
        printf "El producto está inactivo y no se puede editar.\n"
        return
    fi

    read -rp "Ingrese nuevo Precio para '$nombre_antiguo': " nuevo_precio

    > "$archivo_temp"
    while IFS=$'\t' read -r id nombre precio activo <&3; do
        id=$(echo "$id" | tr -d '\r')
        activo=$(echo "$activo" | tr -d '\r')

        if [[ -n "$id" ]]; then
            if (( id == id_editar )); then
                precio="$nuevo_precio"
                encontrado=1
            fi
            printf "%s\t%s\t%s\t%s\n" "$id" "$nombre" "$precio" "$activo" >> "$archivo_temp"
        fi
    done 3< "$ARCHIVO_PROD"

    mv "$archivo_temp" "$ARCHIVO_PROD"

    if (( encontrado == 1 )); then
        printf "Producto %d actualizado con el nuevo precio $%s.\n" "$id_editar" "$nuevo_precio"
    fi
}

baja() {
    declare -i id_baja=$1
    declare encontrado=0
    declare archivo_temp="productos.tmp"

    > "$archivo_temp"

    while IFS=$'\t' read -r id nombre precio activo; do
        id=$(echo "$id" | tr -d '\r')
        activo=$(echo "$activo" | tr -d '\r')

        if [[ -n "$id" ]]; then
            if (( id == id_baja )); then
                if [[ "$activo" == "1" ]]; then
                    activo=0
                    encontrado=1
                    printf "Producto %d eliminado.\n" "$id"
                else
                    encontrado=2
                fi
            fi
            printf "%s\t%s\t%s\t%s\n" "$id" "$nombre" "$precio" "$activo" >> "$archivo_temp"
        fi
    done < "$ARCHIVO_PROD"

    mv "$archivo_temp" "$ARCHIVO_PROD"

    if (( encontrado == 0 )); then
        printf "El producto no existe.\n"
    elif (( encontrado == 2 )); then
        printf "El producto ya se encontraba inactivo.\n"
    fi
}

mostrar() {
    printf "\nLISTADO:\n"
    if [[ -s "$ARCHIVO_PROD" ]]; then
        while IFS=$'\t' read -r id nombre precio activo; do
            id=$(echo "$id" | tr -d '\r')
            activo=$(echo "$activo" | tr -d '\r')
            if [[ -n "$id" ]] && [[ "$activo" == "1" ]]; then
                printf "ID %s : %s - $%s\n" "$id" "$nombre" "$precio"
            fi
        done < "$ARCHIVO_PROD"
    fi
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

    if [[ -s "$ARCHIVO_PROD" ]]; then
        while IFS=$'\t' read -r id nombre precio activo; do
            id=$(echo "$id" | tr -d '\r')
            activo=$(echo "$activo" | tr -d '\r')
            if [[ -n "$id" ]] && [[ "$activo" == "1" ]]; then
                printf "        <tr>\n            <td>%s</td>\n            <td>%s</td>\n            <td>$%s</td>\n        </tr>\n" "$id" "$nombre" "$precio" >> "$archivo_html"
            fi
        done < "$ARCHIVO_PROD"
    fi

    cat << EOF >> "$archivo_html"
    </table>
</body>
</html>
EOF

    printf "\nReporte 'productos.html' generado exitosamente.\n"
}

main() {
    inicializar_archivos
    bienvenida

    # Reemplazamos el login viejo por el nuevo menú de autenticación con usuarios.tsv
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
                ;;
            *)
                printf "\nOpcion invalida.\n"
                ;;
        esac
    done

    return 0
}

main