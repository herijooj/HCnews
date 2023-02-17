#!/usr/bin/env bash

# this function shortens a URL using the is.gd service
# it receives the URL as an argument
# it returns the shortened URL
shorten_url_isgd () {
    URL=$1
    SHORTENED_URL=$(curl -s "https://is.gd/create.php?format=simple&url=$URL")
    echo "$SHORTENED_URL"
}
