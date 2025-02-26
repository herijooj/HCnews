#!/usr/bin/env bash
SCRIPT_DIR=$(dirname "$0")
STATES_FILE="$SCRIPT_DIR/data/states.csv"
function get_states() {
    # get the date from arguments
    local month=$1
    local day=$2
    # get the states
    local states=$(awk -v month="$month" -v day="$day" '$1 == month && $2 == day { $1=$2=""; print $0 }' "$STATES_FILE")
    echo "$states"
}

# write the states
function write_states_birthdays() {
    # get the states
    local states=$(get_states "$1" "$2")
    
    # if there are no states, print a message
    if [[ -z $states ]]; then
        echo "📅 Sem estados com aniversário hoje..."
        echo ""
        return
    fi
    
    # write the states
    echo "📅 *Estados com aniversário hoje:*"
    echo "$states"
    echo ""
}

# -------------------------------- Running locally --------------------------------

# help function
show_help() {
    echo "Usage: ./states.sh [month] [day]"
    echo "The states will be printed to the console."
    echo "If no arguments are passed, the current date will be used."
    echo "Options:"
    echo "  -h, --help: show the help"
}

# this function will receive the arguments
get_arguments() {
    # current date
    local month=$(date +%m)
    local day=$(date +%d)

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

    # Return the month and day
    echo "$month" "$day"
}

# run the script
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # get the arguments
    read month day < <(get_arguments "$@")
    write_states_birthdays "$month" "$day"
fi
