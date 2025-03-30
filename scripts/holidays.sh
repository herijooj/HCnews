#!/usr/bin/env bash

HOLIDAYS_SCRIPT_DIR=$(dirname "$(realpath "${BASH_SOURCE[0]}")")
PROJECT_ROOT=$(realpath "$HOLIDAYS_SCRIPT_DIR/..")
HOLIDAY_FILE="$PROJECT_ROOT/data/holidays.csv"

# get holidays
# the holidays are in the holidays.csv file
# the file is in the format: "month,day,emoji,holiday"
# example: 01,01,🎉,Ano Novo
function get_holidays() {
    # get the date from arguments
    local month=$1
    local day=$2
    # get the holidays
    local holidays=$(awk -F, -v month="$month" -v day="$day" '$1 == month && $2 == day { print $3 " " $4 }' "$HOLIDAY_FILE")
    echo "$holidays"
}

# write the holidays
function write_holidays() {
    # Check if file exists
    if [[ ! -f "$HOLIDAY_FILE" ]]; then
        echo "Error: Holiday file not found at $HOLIDAY_FILE"
        exit 1
    fi

    # get the holidays
    local holidays=$(get_holidays "$1" "$2")

    # if there are no holidays, print a message
    if [[ -z $holidays ]]; then
        # echo "📅 Sem feriados hoje..."
        # echo ""
        return
    fi

    # write the holidays
    echo "📅 *Hoje é:*"
    echo "$holidays" | while read -r line; do
        echo "- $line"
    done
    echo ""
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
get_arguments() {
  # current date
  month=$(date +%m)
  day=$(date +%d)

  # get the arguments
  while [[ $# -gt 0 ]]; do
    case $1 in
      -h | --help)
        show_help
        exit
        ;;
      *)
        # get the month and day from the arguments
        month=$1
        day=$2
        break
        ;;
    esac
    shift
  done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # run the script
  get_arguments "$@"
  write_holidays "$month" "$day"
fi
