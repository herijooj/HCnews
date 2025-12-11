#!/usr/bin/env bash

# Source common library if not already loaded
if [[ -z "${_HCNEWS_COMMON_LOADED:-}" ]]; then
    SCRIPT_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
    if [[ -f "$SCRIPT_DIR/lib/common.sh" ]]; then
        source "$SCRIPT_DIR/lib/common.sh"
    elif [[ -f "scripts/lib/common.sh" ]]; then
        source "scripts/lib/common.sh"
    fi
fi

# Returns the quote of the day.
# we retrieve the quote from the Pensador RSS feed
# https://www.pensador.com/rss.php
# Usage: quote
# Example output: "The best way to predict the future is to invent it." - Alan Kay
function quote {
    # Check for global flags via common helper
    hcnews_parse_cache_args "$@"
    local use_cache=$_HCNEWS_USE_CACHE
    local force_refresh=$_HCNEWS_FORCE_REFRESH
    local ttl=${HCNEWS_CACHE_TTL["quote"]:-86400}

    local date_format_local
    # Use cached date_format if available, otherwise fall back to date command
    if [[ -n "$date_format" ]]; then
        date_format_local="$date_format"
    else
        date_format_local=$(date +"%Y%m%d")
    fi
    
    local cache_file
    cache_file=$(hcnews_get_cache_path "quote" "$date_format_local")

    # Check cache first
    if [[ "$use_cache" == true ]] && hcnews_check_cache "$cache_file" "$ttl" "$force_refresh"; then
        hcnews_read_cache "$cache_file"
        return 0
    fi

    # get the quote from the RSS feed (Pensador)
    local URL="https://www.pensador.com/rss.php"
    local response
    response=$(curl -s "$URL")

    # Use xmlstarlet with inline text processing to avoid multiple subshells
    # Extract the first item's description (fall back to title when it's empty), then decode HTML entities in one pass
    local QUOTE
    # extract description (first item) — Pensador uses <description> with CDATA
    QUOTE=$(echo "$response" | xmlstarlet sel -t -m "/rss/channel/item[1]" -v "description" 2>/dev/null)
    if [[ -z "$QUOTE" ]]; then
      QUOTE=$(echo "$response" | xmlstarlet sel -t -m "/rss/channel/item[1]" -v "title" 2>/dev/null)
    fi

    # Clean up and decode entities while preserving UTF-8 using perl for robust unicode handling
    QUOTE=$(printf '%s' "$QUOTE" | perl -CS -Mutf8 -pe 's/\x{200B}//g; s/\x{00A0}/ /g; s/&amp;/&/g; s/&lt;/</g; s/&gt;/>/g; s/&quot;/"/g; s/&#0*39;/\x27/g; s/&rsquo;/\x27/g; s/&lsquo;/\x27/g; s/&rdquo;/"/g; s/&ldquo;/"/g; s/&#[0-9]+;//g; s/\s*Frase Minha.*//gi; s/^\s+|\s+$//g; s/\n{2,}/\n\n/g')
    
    # Build output
    local output="📝 *Frase do dia:*\n${QUOTE}\n\n"

    # Save to cache if caching is enabled
    if [[ "$use_cache" == true ]]; then
        hcnews_write_cache "$cache_file" "$(echo -e "$output")"
    fi

    # return the quote
    echo -e "$output"
}

# -------------------------------- Running locally --------------------------------

# help function
# Usage: ./quote.sh [options]
# Options:
#   -h, --help: show the help
show_help() {
  echo "Usage: ./quote.sh [options]"
  echo "The quote of the day will be printed to the console."
  echo "Options:"
  echo "  -h, --help: show the help"
  echo "  --no-cache: do not use cached data"
  echo "  --force: force refresh cache"
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
  done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # run the script
  get_arguments "$@"
  quote
fi