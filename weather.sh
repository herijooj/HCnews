#!/bin/bash

# this function retrieves the weather from curl wttr.in/$CITY
# it will receive an String and return an String
# get the weather from the website
# ?0q: remove the header and the footer
# lang=pt-br: set the language to portuguese
function get_weather () {
    CITY="$1"
    # get the weather
    WEATHER=$(curl -s "wttr.in/$CITY?0q&lang=pt-br" | sed '1,2d')

    # return the weather
    echo "$WEATHER"
}

function write_weather () {
    # get the arguments
    CITY="$1"
    TERMINAL="$2"

    # get the weather
    WEATHER=$(get_weather "$CITY")

    if [[ "$TERMINAL" == "false" ]]; then
        # clean up the string
        # remove all ANSI escape sequences from the string
        WEATHER=$(echo "$WEATHER" | sed "s/\x1B\[[0-9;]*[a-zA-Z]//g")
    fi

    # write the weather to the console
    echo "🌧️ *Previsão do tempo* ⛅"
    echo "$WEATHER"
    echo "📌 $CITY"
    echo ""
}

# -------------------------------- Running locally --------------------------------

# help function
# Usage: ./weather.sh [City] [options]
# the command will be printed to the console.
# Options:
#   -h, --help: show the help
help () {
    echo "Usage: ./weather.sh [City] [options]"
    echo "The command will be printed to the console."
    echo "If the city is empty, it will be set to Curitiba."
    echo "Options:"
    echo "  -h, --help: show the help"
}

# this function will receive the arguments
# if the city is empty, set it to curitiba
get_arguments () {
    # Define variables
    CITY="Curitiba"

    # Get the arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                help
                exit 0
                ;;
            *)
                CITY="$1"
                shift
                ;;
        esac
    done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # run the script
  get_arguments "$@"
  write_weather "$CITY"
fi