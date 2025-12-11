#!/usr/bin/env bash

# Optimized directory resolution
_desculpa_SCRIPT_DIR="${BASH_SOURCE[0]%/*}"

function get_desculpa() {
    local desculpas_file
    # Handle relative path resolution if sourcing
    if [[ "$_desculpa_SCRIPT_DIR" == "." ]]; then
         desculpas_file="data/desculpas.json"
    else
         # Try to resolve relative to root if possible, or relative to script
         # Assuming data is sibling to scripts dir or grandparent/data
         # Based on original: "$(dirname "$_desculpa_SCRIPT_DIR")/data/desculpas.json"
         # scripts/desculpa.sh -> dirname is scripts -> scripts/../data -> data
         desculpas_file="$_desculpa_SCRIPT_DIR/../data/desculpas.json"
    fi
    
    # Define cache file (similar to emoji.sh)
    local desculpa_cache_dir="$_desculpa_SCRIPT_DIR/../data/cache/desculpa"
    [[ -d "$desculpa_cache_dir" ]] || mkdir -p "$desculpa_cache_dir"
    local desculpa_cache_file="${desculpa_cache_dir}/desculpas.cache"

    # Create/update cache if needed or if empty
    if [[ ! -f "$desculpa_cache_file" ]] || [[ ! -s "$desculpa_cache_file" ]] || [[ "$desculpas_file" -nt "$desculpa_cache_file" ]]; then
        # Parse JSON and extract strings to cache file (one per line)
        # sed: extract content between quotes, ignore trailing comma and whitespace (handling CRLF)
        sed -n 's/^[[:space:]]*"\([^"]*\)"[[:space:],]*$/\1/p' "$desculpas_file" > "$desculpa_cache_file"
    fi

    # Select random line from cache
    if [[ -s "$desculpa_cache_file" ]]; then
        local excuses=()
        mapfile -t excuses < "$desculpa_cache_file" 2>/dev/null || IFS=$'\n' read -d '' -r -a excuses < "$desculpa_cache_file"
        
        local count=${#excuses[@]}
        if (( count > 0 )); then
            EXCUSE="${excuses[$(( RANDOM % count ))]}"
        else
            EXCUSE="Desculpa, não consegui encontrar minhas desculpas hoje."
        fi
    else
        EXCUSE="Desculpa, não consegui encontrar minhas desculpas hoje."
    fi
    
    # Return the excuse
    echo "$EXCUSE"
}

function write_excuse() {
    # get the excuse
    EXCUSE=$(get_desculpa)

    # write the excuse to the console
    echo "🚫 *Desculpa do Dia:*"
    echo "- ${EXCUSE}"
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