#!/usr/bin/env bash

function get_didyouknow() {
    local URL="https://pt.wikipedia.org/wiki/Wikip%C3%A9dia:Sabia_que"

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

    # remove or replace non-ASCII characters
    FACT=$(echo "$FACT" | iconv -f utf-8 -t ascii//TRANSLIT)

    # return the fact
    echo "$FACT"
}

function write_did_you_know() {
    # get the fact
    FACT=$(get_didyouknow)

    # write the fact to the console
    echo "📚 *Você sabia?* 🤔"
    echo "$FACT"
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