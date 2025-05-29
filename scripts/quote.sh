#!/usr/bin/env bash

QUOTE_DIR=$(dirname "$(realpath "${BASH_SOURCE[0]}")")
# Define cache directory relative to this script's location
_quote_CACHE_DIR="$(dirname "$QUOTE_DIR")/data/cache/quote"

# Returns the quote of the day.
# we retrieve the quote from the RSS feed from theysaidso.com
# http://feeds.feedburner.com/theysaidso/qod
# Usage: quote
# Example output: "The best way to predict the future is to invent it." - Alan Kay
function quote {
    local use_cache=true
    local force_refresh=false

    # Check for global flags from hcnews.sh if this script is sourced
    if [[ -n "${hc_no_cache+x}" && "$hc_no_cache" == true ]]; then
        use_cache=false
    fi
    if [[ -n "${hc_force_refresh+x}" && "$hc_force_refresh" == true ]]; then
        force_refresh=true
    fi

    local date_format
    date_format=$(date +"%Y%m%d")
    
    # Ensure the cache directory exists
    mkdir -p "$_quote_CACHE_DIR"
    local cache_file="${_quote_CACHE_DIR}/${date_format}_quote.cache"

    # Check cache first (unless force refresh is requested)
    if [[ "$use_cache" == true && "$force_refresh" == false && -f "$cache_file" ]]; then
        cat "$cache_file"
        return 0
    fi

    # get the quote from the RSS feed
    URL="http://feeds.feedburner.com/theysaidso/qod"

    # pick the second description tag
    QUOTE=$(curl -s "$URL" | xmlstarlet sel -t -m "/rss/channel/item" -v "description" -n | sed -n 2p)

    # convert the quote to ASCII and decode HTML entities
    QUOTE=$(echo "$QUOTE" | iconv -f utf-8 -t ascii//TRANSLIT | sed -e "s/&amp;/\&/g; s/&lt;/</g; s/&gt;/>/g; s/&quot;/\"/g; s/&#039;/'/g; s/&rsquo;/'/g; s/&lsquo;/'/g; s/&rdquo;/\"/g; s/&ldquo;/\"/g; s/&#[0-9]\+;//g")

    # Save to cache if caching is enabled
    if [[ "$use_cache" == true ]]; then
        echo "$QUOTE" > "$cache_file"
    fi

    # return the quote
    echo "$QUOTE"
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
  quote
fi