#!/usr/bin/env bash

# Function to decode HTML entities using pure Bash/sed (avoids spawning Python)
decode_html_entities() {
  local input="$1"
  # Handle common HTML entities and numeric/hex character references
  printf '%s' "$input" | sed "s/&amp;/\&/g; s/&quot;/\"/g; s/&lt;/</g; s/&gt;/>/g; s/&#39;/'/g; s/&apos;/'/g; s/&nbsp;/ /g; s/&rsquo;/'/g; s/&lsquo;/'/g; s/&rdquo;/\"/g; s/&ldquo;/\"/g; s/&mdash;/—/g; s/&ndash;/–/g; s/&hellip;/…/g; s/&#x[0-9a-fA-F]\\+;//g; s/&#[0-9]\\+;//g"
}

# Source common library if not already loaded
if [[ -z "${_HCNEWS_COMMON_LOADED:-}" ]]; then
    SCRIPT_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
    if [[ -f "$SCRIPT_DIR/lib/common.sh" ]]; then
        source "$SCRIPT_DIR/lib/common.sh"
    elif [[ -f "scripts/lib/common.sh" ]]; then
        source "scripts/lib/common.sh"
    fi
fi

function get_didyouknow() {
    local local_use_cache=true
    local local_force_refresh=false

    # Check for global flags via common helper
    hcnews_parse_cache_args "$@"
    local local_use_cache=$_HCNEWS_USE_CACHE
    local local_force_refresh=$_HCNEWS_FORCE_REFRESH
    local ttl=${HCNEWS_CACHE_TTL["didyouknow"]:-86400}

    local date_format_local
    # Use cached date_format if available, otherwise fall back to date command
    if [[ -n "$date_format" ]]; then
        date_format_local="$date_format"
    else
        date_format_local=$(date +"%Y%m%d")
    fi
    local cache_file
    cache_file=$(hcnews_get_cache_path "didyouknow" "$date_format_local")
    
    if [[ "$local_use_cache" == true ]] && hcnews_check_cache "$cache_file" "$ttl" "$local_force_refresh"; then
        hcnews_read_cache "$cache_file"
        return 0
    fi

    local URL="https://pt.wikipedia.org/wiki/Wikip%C3%A9dia:Sabia_que"
    local HTML FACT

    # get the HTML
    HTML=$(curl -s "$URL")

    # extract the second <p> tag
    FACT=$(echo "$HTML" | pup 'p:nth-of-type(2) text{}')

    # delete the break lines and multiple spaces
    FACT=$(echo "$FACT" | tr -s '\n' ' ' | tr -s ' ')

    # delete the spaces before and after punctuation (.,;:?!)
    FACT=$(echo "$FACT" | sed 's/\s\([.,;:?!]\)/\1/g')

    

    # decode HTML entities before handling encoding
    FACT=$(decode_html_entities "$FACT")

    if [[ "$local_use_cache" == true && -n "$FACT" ]]; then
        hcnews_write_cache "$cache_file" "$FACT"
    fi

    # return the fact
    echo "$FACT"
}

function write_did_you_know() {
    # get the fact
    FACT=$(get_didyouknow)

    # write the fact to the console
    echo "📚 *Você sabia?*"
    echo "- ${FACT}"
    echo "_Fonte: Wikipedia_"
    echo ""
}

# -------------------------------- Running locally --------------------------------

# help function
# Usage: ./didyouknow.sh [options]
# Options:
#   -h, --help: show the help
show_help() {
  echo "Usage: ./didyouknow.sh [options]"
  echo "The command will be printed to the console."
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
      --no-cache)
        _HCNEWS_USE_CACHE=false
        shift
        ;;
      --force)
        _HCNEWS_FORCE_REFRESH=true
        shift
        ;;
      *)
        echo "Invalid argument: $1"
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
    write_did_you_know
fi