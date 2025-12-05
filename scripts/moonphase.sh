#!/usr/bin/env bash

MOONPHASE_DIR=$(dirname "$(realpath "${BASH_SOURCE[0]}")")
# Define cache directory relative to this script's location
_moonphase_CACHE_DIR="$(dirname "$MOONPHASE_DIR")/data/cache/header"

# this function returns the moon phase from https://www.invertexto.com/fase-lua-hoje
function moon_phase () {
    local use_cache=true
    local force_refresh=false

    # Check for global flags from hcnews.sh if this script is sourced
    # hc_no_cache and hc_force_refresh would be set by hcnews.sh
    if [[ -n "${hc_no_cache+x}" && "$hc_no_cache" == true ]]; then
        use_cache=false
    fi
    if [[ -n "${hc_force_refresh+x}" && "$hc_force_refresh" == true ]]; then
        force_refresh=true
    fi

    local date_format_local
    # Use cached date_format if available, otherwise fall back to date command
    if [[ -n "$date_format" ]]; then
        date_format_local="$date_format"
    else
        date_format_local=$(date +"%Y%m%d")
    fi
    
    # Ensure the cache directory exists
    [[ -d "$_moonphase_CACHE_DIR" ]] || mkdir -p "$_moonphase_CACHE_DIR"
    local cache_file="${_moonphase_CACHE_DIR}/${date_format_local}_moon_phase.cache"

    if [[ "$use_cache" == true && "$force_refresh" == false && -f "$cache_file" ]]; then
        cat "$cache_file"
        return 0
    fi

    local fetched_moon_phase
    # grep all the lines with <span> and </span>
    fetched_moon_phase=$(curl -s https://www.invertexto.com/fase-lua-hoje | grep -oP '(?<=<span>).*(?=</span>)')
    
    # keep only the text before the first number
    fetched_moon_phase=$(echo "$fetched_moon_phase" | sed 's/[0-9].*//')

    if [[ "$use_cache" == true ]]; then
        # Save to cache
        echo "🌔 $fetched_moon_phase" > "$cache_file"
    fi

    # return the moon phase
    echo "🌔 $fetched_moon_phase"
}

# -------------------------------- Running locally --------------------------------

# help function
# Usage: ./moonphase.sh [options]
# Options:
#   -h, --help: show the help
show_help() {
  echo "Usage: ./moonphase.sh [options]"
  echo "The moon phase will be printed to the console."
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
        echo "Invalid argument: $1"
        show_help
        exit 1
        ;;
    esac
  done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # run the script
  get_arguments "$@"
  moon_phase
fi