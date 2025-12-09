#!/usr/bin/env bash

_desculpa_SCRIPT_DIR=$(dirname "$(realpath "${BASH_SOURCE[0]}")")

function get_desculpa() {
    local desculpas_file="$(dirname "$_desculpa_SCRIPT_DIR")/data/desculpas.json"
    
    # Check if the file exists
    if [[ ! -f "$desculpas_file" ]]; then
        echo "Desculpa, não consegui encontrar minhas desculpas hoje."
        return 1
    fi

    local EXCUSE
    
    # Parse JSON and get random excuse
    if command -v jq &> /dev/null; then
        # Use jq if available for proper JSON parsing
        EXCUSE=$(jq -r '.[]' "$desculpas_file" | shuf -n 1)
    else
        # Fallback: extract excuses with sed and get random one
        EXCUSE=$(sed -n 's/^[[:space:]]*"\([^"]*\)",\?$/\1/p' "$desculpas_file" | shuf -n 1)
    fi

    # Check if we got a valid excuse
    if [[ -z "$EXCUSE" ]]; then
        EXCUSE="Desculpa, não consegui pensar em uma desculpa hoje."
    fi

    # Return the excuse
    echo "$EXCUSE"
}

function write_excuse() {
    # get the excuse
    EXCUSE=$(get_desculpa)

    # write the excuse to the console
    echo "🚫 *Desculpa do Dia:*"
    echo "_${EXCUSE}_"
    echo "_Fonte: programming-excuse-as-a-Service_"
    echo ""
}

# -------------------------------- Running locally --------------------------------

# help function
# Usage: ./desculpa.sh [options]
# Options:
#   -h, --help: show the help
show_help() {
  echo "Usage: ./desculpa.sh [options]"
  echo "The excuse will be printed to the console."
  echo "Options:"
  echo "  -h, --help: show the help"
}

# this function will receive the arguments
get_arguments() {
  # Get the arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        show_help
        exit 0
        ;;
      *)
        show_help
        exit 1
        ;;
    esac
    shift
  done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    get_arguments "$@"
    echo 
    write_excuse
fi