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