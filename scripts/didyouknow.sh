#!/usr/bin/env bash

# Function to decode HTML entities
decode_html_entities() {
  local input="$1"
  if command -v python3 &> /dev/null; then
    # Use Python for reliable HTML entity decoding if available
    python3 -c "import html, sys; print(html.unescape('''$input'''))" 2>/dev/null || echo "$input"
  else
    # Fallback to sed for basic entity replacement
    echo "$input" | sed 's/&amp;/\&/g; s/&quot;/"/g; s/&lt;/</g; s/&gt;/>/g; s/&apos;/'\''/g'
  fi
}

_didyouknow_SCRIPT_DIR=$(dirname "$(realpath "${BASH_SOURCE[0]}")")
_didyouknow_CACHE_DIR="$(dirname "$_didyouknow_SCRIPT_DIR")/data/cache/didyouknow"

function get_didyouknow() {
    local local_use_cache=true
    local local_force_refresh=false

    # Check for global flags from hcnews.sh if this script is sourced
    if [[ -n "${hc_no_cache+x}" && "$hc_no_cache" == true ]]; then
        local_use_cache=false
    fi
    if [[ -n "${hc_force_refresh+x}" && "$hc_force_refresh" == true ]]; then
        local_force_refresh=true
    fi

    local date_format
    # Use cached date_format if available, otherwise fall back to date command
    if [[ -n "$date_format" ]]; then
        date_format="$date_format"
    else
        date_format=$(date +"%Y%m%d")
    fi
    mkdir -p "$_didyouknow_CACHE_DIR" # Ensure cache directory exists
    local cache_file="${_didyouknow_CACHE_DIR}/${date_format}_didyouknow.cache"

    if [[ "$local_use_cache" == true && "$local_force_refresh" == false && -f "$cache_file" ]]; then
        cat "$cache_file"
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

    # delete everything after the second …
    FACT=$(echo "$FACT" | sed 's/\(.*…\).*/\1/')

    # decode HTML entities before handling encoding
    FACT=$(decode_html_entities "$FACT")

    # remove or replace non-ASCII characters
    FACT=$(echo "$FACT" | iconv -f utf-8 -t ascii//TRANSLIT)

    if [[ "$local_use_cache" == true && -n "$FACT" ]]; then
        echo "$FACT" > "$cache_file"
    fi

    # return the fact
    echo "$FACT"
}

function write_did_you_know() {
    # get the fact
    FACT=$(get_didyouknow)

    # write the fact to the console
    echo "📚 *Você sabia?*"
    echo "_${FACT}_"
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
    write_did_you_know
fi