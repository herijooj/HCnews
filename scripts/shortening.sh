#!/usr/bin/env bash

# Source common library if not already loaded
[[ -n "${_HCNEWS_COMMON_LOADED:-}" ]] || source "${HCNEWS_COMMON_PATH:-${BASH_SOURCE%/*}/lib/common.sh}" 2>/dev/null || source "${BASH_SOURCE%/*}/scripts/lib/common.sh"

# URL shortening function using is.gd service with timeout and retries
shorten_url_isgd() {
    local url="$1"
    local shortened
    local max_retries=2
    local retry_count=0
    local success=false
    
    # URL encode the input to ensure it works with special characters
    local encoded_url
    encoded_url=$(hcnews_url_encode "$url")
    
    while (( retry_count < max_retries )) && [[ "$success" == false ]]; do
        # Call the URL shortening service with strict timeouts
        shortened=$(curl -s -m 3 --connect-timeout 2 "https://is.gd/create.php?format=simple&url=${encoded_url}" 2>/dev/null)
        
        # Check if the shortening was successful
        if [[ -n "$shortened" && "$shortened" =~ ^https?:// ]]; then
            success=true
            break
        fi
        
        # Increment retry counter and wait before retrying
        (( retry_count++ ))
        if (( retry_count < max_retries )); then
            sleep 1
        fi
    done
    
    # Return shortened URL if successful, otherwise return original URL
    if [[ "$success" == true ]]; then
        echo "$shortened"
    else
        echo "$url"
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
