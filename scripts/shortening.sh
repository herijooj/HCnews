#!/usr/bin/env bash

# this function shortens a URL using the is.gd service
# it receives the URL as an argument
# it returns the shortened URL

function shorten_url_isgd {
  local url=$1
  if [[ $url =~ ^https?:// ]]; then
    local shortened_url=$(curl -s "https://is.gd/create.php?format=simple&url=$url")
    echo "$shortened_url"
  else
    echo "Invalid URL format: $url"
    return 1
  fi
}

# -------------------------------- Running locally --------------------------------

# help function
# Usage: ./shortening.sh [options]
# Options:
#   -h, --help: show the help
#   -u, --url: the URL to shorten
show_help() {
  echo "Usage: ./shortening.sh [options]"
  echo "Options:"
  echo "  -h, --help: show the help"
  echo "  -u, --url: the URL to shorten"
}

# this function will receive the arguments
get_arguments() {
  # Define variables
  url=""

  # Get the arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        show_help
        exit 0
        ;;
      -u|--url)
        url=$2
        shift
        shift
        ;;
      *)
        echo "Invalid argument: $1"
        show_help
        exit 1
        ;;
    esac
  done

  # Check if the URL was provided
  if [[ -z "$url" ]]; then
    echo "The URL was not provided"
    show_help
    exit 1
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # run the script
  get_arguments "$@"
  shorten_url_isgd "$url"
fi
