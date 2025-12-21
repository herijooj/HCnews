#!/usr/bin/env bash

# Source common library if not already loaded
[[ -n "${_HCNEWS_COMMON_LOADED:-}" ]] || source "${HCNEWS_COMMON_PATH:-${BASH_SOURCE%/*}/lib/common.sh}" 2>/dev/null || source "${BASH_SOURCE%/*}/scripts/lib/common.sh"

# this function returns the moon phase from https://www.invertexto.com/fase-lua-hoje
function moon_phase () {
    # Check for global flags via common helper
    hcnews_parse_cache_args "$@"
    local use_cache=$_HCNEWS_USE_CACHE
    local force_refresh=$_HCNEWS_FORCE_REFRESH
    local ttl=${HCNEWS_CACHE_TTL["moonphase"]:-86400}

    local date_format_local
    # Use cached date_format if available, otherwise fall back to date command
    if [[ -n "$date_format" ]]; then
        date_format_local="$date_format"
    else
        date_format_local=$(date +"%Y%m%d")
    fi
    
    local cache_file
    hcnews_set_cache_path cache_file "moonphase" "$date_format_local"

    if [[ "$use_cache" == true ]] && hcnews_check_cache "$cache_file" "$ttl" "$force_refresh"; then
        hcnews_read_cache "$cache_file"
        return 0
    fi

    local fetched_moon_phase
    # grep all the lines with <span> and </span>
    fetched_moon_phase=$(curl -s https://www.invertexto.com/fase-lua-hoje | grep -oP '(?<=<span>).*(?=</span>)')
    
    # keep only the text before the first number
    fetched_moon_phase=$(echo "$fetched_moon_phase" | sed 's/[0-9].*//')

    if [[ "$use_cache" == true ]]; then
        # Save to cache
        hcnews_write_cache "$cache_file" "🌔 $fetched_moon_phase"
    fi

    # return the moon phase
    echo "🌔 $fetched_moon_phase"
}

# -------------------------------- Running locally --------------------------------

# help function
# Usage: ./moonphase.sh [options]
show_help() {
  echo "Usage: ./moonphase.sh [options]"
  echo "The moon phase will be printed to the console."
  echo "Options:"
  echo "  -h, --help: show the help"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # run the script
  hcnews_parse_args "$@"
  moon_phase
fi