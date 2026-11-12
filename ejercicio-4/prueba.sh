#!/usr/bin/env bash

tui_input() {
    local mensaje=$1
    # Whiptail devuelve el texto por el canal de errores (2),
    # por eso usamos el intercambio de descriptores (3>&1 1>&2 2>&3) para capturarlo en la variable.
    whiptail --title "Pruebas TUI" --inputbox "$mensaje" 8 50 3>&1 1>&2 2>&3
}

main ()
    {
        local mensaje=""
        mensaje= $(tui_input "Hola")

    }

main