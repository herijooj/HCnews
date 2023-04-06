#!/usr/bin/env bash

# Returns the quote of the day.
# we retrieve the quote from the RSS feed from theysaidso.com
# http://feeds.feedburner.com/theysaidso/qod
# Usage: quote
# Example output: "The best way to predict the future is to invent it." - Alan Kay
function quote {
    # get the quote from the RSS feed
    URL="http://feeds.feedburner.com/theysaidso/qod"

    # pick the first <quote and <author
    QUOTE=$(curl -s "$URL" | xmlstarlet sel -t -m "/rss/channel/item" -v "quote" -n | head -n 1)
    AUTHOR=$(curl -s "$URL" | xmlstarlet sel -t -m "/rss/channel/item" -v "author" -n | head -n 1)

    # return the quote
    echo "$QUOTE - $AUTHOR"

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