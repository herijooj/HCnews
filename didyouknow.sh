#!/usr/bin/env bash

# this function returns a random fact from "https://pt.wikipedia.org/wiki/Wikip%C3%A9dia:Sabia_que"
function get_didyouknow () {
    local URL="https://pt.wikipedia.org/wiki/Wikip%C3%A9dia:Sabia_que"

    # get the HTML
    HTML=$(curl -s "$URL")

    # extract the <tbody><tr>...</tr></tbody> section
    HTML=$(echo "$HTML" | pup 'tbody tr')

    # <li>...</li> section
    HTML=$(echo "$HTML" | pup 'li')

    # keep everthing inside the first <li>...</li> section
    HTML=$(echo "$HTML" | pup 'li:first-child')

    # remove tags
    HTML=$(echo "$HTML" | pup 'text{}')

    # remove break lines and tabs
    HTML=$(echo "$HTML" | tr -d '\n\t')

    # all spaces will be replaced by a single space
    HTML=$(echo "$HTML" | tr -s ' ')

    # return the result
    echo "$HTML"
}

function write_did_you_know () {

    # get the fact
    FACT=$(get_didyouknow)

    # write the fact to the console
    echo "📚 Você sabia? 🤔"
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