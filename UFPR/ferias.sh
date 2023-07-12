#!/usr/bin/env bash

# this function returns the first title from the RSS feed
# https://nitter.net/feriasufpr/rss
function write_ferias () {

    # get the title from the RSS feed
    URL="https://nitter.net/feriasufpr/rss"

    # pick the first <title
    TITLE=$(curl -s "$URL" | xmlstarlet sel -t -m "/rss/channel/item" -v "title" -n | head -n 1)

    # if the title is empty, we are in vacation
    if [[ -z "$TITLE" ]]; then
        echo "🏝️  Estamos de férias!"
        exit 1
    fi

    # return the title and add the emoji
    echo "🏖️  $TITLE"
    echo ""

}


# -------------------------------- Running locally --------------------------------

# help function
# Usage: ./ferias.sh [options]
# the command will be printed to the console.
# Options:
#   -h, --help: show the help

help () {
    echo "Usage: ./ferias.sh [options]"
    echo "The command will be printed to the console."
    echo "Options:"
    echo "  -h, --help: show the help"
}

# this function will receive the arguments, and trown an error if the url is not valid
get_arguments () {
    # Get the arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                help
                exit 0
                ;;
            *)
                echo "Invalid argument: $1"
                help
                exit 1
                ;;
        esac
    done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # run the script
    get_arguments "$@"

    write_ferias
fi