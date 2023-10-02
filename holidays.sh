#!/usr/bin/env bash

# get holidays
# the holidays are in the holidays.csv file
# the file is in the format: "month,day,holiday"
# example: "1,1,Ano Novo"
function get_holidays() {
    # get the date from arguments
    local month=$1
    local day=$2

    # if the date is not passed, use the current date
    if [[ -z $month ]]; then
        month=$(date +%m)
    fi
    if [[ -z $day ]]; then
        day=$(date +%d)
    fi

    # get the holidays
    local holidays=$(cat holidays.csv | grep "$month,$day" | cut -d "," -f 3)
    echo "$holidays"
}

# write the holidays
function write_holidays() {
    # get the holidays
    local holidays=$(get_holidays "$@")

    # if there are no holidays, exit
    if [[ -z $holidays ]]; then
        exit 0
    fi

    # write the holidays
    echo "📅 Hoje é dia de:"
    echo "$holidays"
}

# -------------------------------- Running locally --------------------------------

# help function
# Usage: ./holidays.sh [month] [day]
# Options:
#   -h, --help: show the help
show_help() {
  echo "Usage: ./holidays.sh [month] [day]"
  echo "The holidays will be printed to the console."
  echo "If no arguments are passed, the current date will be used."
  echo "Options:"
  echo "  -h, --help: show the help"
}

# this function will receive the arguments
# Usage: get_arguments [month] [day]
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
  write_holidays "$@"
fi
