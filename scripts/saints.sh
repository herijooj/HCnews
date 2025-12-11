#!/usr/bin/env bash

# Source common library if not already loaded
if [[ -z "$(type -t hcnews_log)" ]]; then
    _local_script_dir=$(dirname "$(realpath "${BASH_SOURCE[0]}")")
    source "$_local_script_dir/lib/common.sh"
fi

# Cache configuration - use centralized dir
if [[ -z "${HCNEWS_CACHE_DIR:-}" ]]; then
    HCNEWS_CACHE_DIR="$(dirname "$(dirname "${BASH_SOURCE[0]}")")/data/cache"
fi
_saints_CACHE_DIR="${HCNEWS_CACHE_DIR}/saints"
[[ -d "$_saints_CACHE_DIR" ]] || mkdir -p "$_saints_CACHE_DIR"

# Use centralized TTL
CACHE_TTL_SECONDS="${HCNEWS_CACHE_TTL["saints"]:-82800}"

# Parse cache args
hcnews_parse_cache_args "$@"
_saints_USE_CACHE=$_HCNEWS_USE_CACHE
_saints_FORCE_REFRESH=$_HCNEWS_FORCE_REFRESH

# Function to get today's date in YYYYMMDD format (same as RU script)
get_date_format() {
  hcnews_get_date_format
}

# Get the saint(s) of the day from the Vatican website.
# https://www.vaticannews.va/pt/santo-do-dia/MONTH/DAY.html
# This function handles both verbose and regular output.
get_saints_data () {
    local verbose=$1
    local date_format
    date_format=$(get_date_format)
    local cache_suffix="regular"
    if [[ "$verbose" == "true" ]]; then cache_suffix="verbose"; fi
    local cache_file="${_saints_CACHE_DIR}/${date_format}_saints-${cache_suffix}.txt"

    # Check if we have cached data
    if [ "$_saints_USE_CACHE" = true ]; then
        if hcnews_check_cache "$cache_file" "$CACHE_TTL_SECONDS" "$_saints_FORCE_REFRESH"; then
            hcnews_read_cache "$cache_file"
            return 0
        fi

        # Optimization: If requesting regular, check if verbose cache exists
        if [[ "$verbose" != "true" ]]; then
            local verbose_cache_file="${_saints_CACHE_DIR}/${date_format}_saints-verbose.txt"
            if hcnews_check_cache "$verbose_cache_file" "$CACHE_TTL_SECONDS" "$_saints_FORCE_REFRESH"; then
                # Extract names from verbose cache (lines starting with 😇)
                local from_verbose
                from_verbose=$(hcnews_read_cache "$verbose_cache_file" | grep "^😇" | sed 's/😇 /😇/')

                if [[ -n "$from_verbose" ]]; then
                    # Write to regular cache for future fast access
                    hcnews_write_cache "$cache_file" "$from_verbose"
                    echo "$from_verbose"
                    return 0
                fi
            fi
        fi
    fi
    
    # Get the current month and day using cached values
    local month_local
    local day_local
    month_local=$(hcnews_get_month)
    day_local=$(hcnews_get_day)

    # Get the URL
    local url="https://www.vaticannews.va/pt/santo-do-dia/$month_local/$day_local.html"
    local curl_output
    curl_output=$(curl -s -4 --compressed --connect-timeout 5 --max-time 10 "$url")

    # Only the names
    local names
    names=$(printf "%s" "$curl_output" | pup '.section__head h2 text{}' | sed '/^$/d')
    
    # Check if we got any names
    if [[ -z "$names" ]]; then
        echo "⚠️ Não foi possível encontrar santos para hoje."
        return 1
    fi

    local output=""
    if [[ "$verbose" == "true" ]]; then
        # The description
        local description
        description=$(printf "%s" "$curl_output" | pup '.section__head h2 text{}, .section__content p text{}' | sed '/^$/d' | sed '1d'| sed '/^[[:space:]]*$/d')

        # Decode HTML entities in the description
        description=$(hcnews_decode_html_entities "$description")

        # Iterate over each name and print the corresponding description.
        local name
        while read -r name; do
            output+="😇 ${name}"$'\n'
            local saint_description
            saint_description=$(echo "$description" | head -n 1)
            output+="- ${saint_description}"$'\n'
            description=$(echo "$description" | tail -n +2)
        done <<< "$names"
    else
        local name
        while read -r name; do
            output+="😇${name}"$'\n'
        done <<< "$names"
    fi
    
    # Write to cache if cache is enabled
    if [ "$_saints_USE_CACHE" = true ]; then
      hcnews_write_cache "$cache_file" "$output"
    fi
    
    # Output the result
    printf "%s" "$output"
}

write_saints () {
    local saints_verbose=$1

    echo "🙏 *Santos do dia*:"
    get_saints_data "$saints_verbose"
    echo ""
}

# -------------------------------- Running locally --------------------------------

# help function
# Usage: ./saints.sh [options]
# Options:
#   -h, --help: show the help
#   -v, --verbose: show the verbose description of the saints
#   -n, --no-cache: do not use cached data
#   -f, --force: force refresh cache
show_help() {
    echo "Usage: ./saints.sh [options]"
    echo "Options:"
    echo "  -h, --help: show the help"
    echo "  -v, --verbose: show the verbose description of the saints"
    echo "  -n, --no-cache: do not use cached data"
    echo "  -f, --force: force refresh cache"
}

# this function will receive the arguments
get_arguments() {
    # Define variables
    saints_verbose=false

    # Get the arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--verbose)
                saints_verbose=true
                shift
                ;;
            -n|--no-cache)
                _saints_USE_CACHE=false
                shift
                ;;
            -f|--force)
                _saints_FORCE_REFRESH=true
                shift
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
    write_saints "$saints_verbose"
fi