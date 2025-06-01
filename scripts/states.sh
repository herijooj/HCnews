#!/usr/bin/env bash
STATES_SCRIPT_DIR=$(dirname "$(realpath "${BASH_SOURCE[0]}")")
PROJECT_ROOT=$(realpath "$STATES_SCRIPT_DIR/..")
# Only set STATES_FILE if it's not already set (allows for testing)
if [[ -z "${STATES_FILE}" ]]; then
    STATES_FILE="$PROJECT_ROOT/data/states.csv"
fi

function get_states() {
    # get the date from arguments
    local month=$1
    local day=$2
    # get the states - improved to avoid extra whitespace
    local states=$(awk -v month="$month" -v day="$day" -F, '$1 == month && $2 == day { 
        # Join fields 3 onwards with commas to preserve CSV structure if needed
        result = $3
        for(i=4; i<=NF; i++) result = result "," $i
        print result 
    }' "$STATES_FILE")
    echo "$states"
}

# write the states
function write_states_birthdays() {
    # get the states
    local states=$(get_states "$1" "$2")
    
    # if there are no states, print a message
    if [[ -z $states ]]; then
        # echo "📅 Sem estados com aniversário hoje..."
        # echo ""
        return
    fi
    
    # write the states
    echo "📅 *Estados com aniversário hoje:*"
    
    # Process each state and format as markdown list with emoji
    echo "$states" | while IFS= read -r state; do
        if [[ ! -z "$state" ]]; then
            echo "- 🏛️  $state"
        fi
    done
    
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
    # Use cached values if available, otherwise fall back to date commands
    local month day
    if [[ -n "$month" && -n "$day" ]]; then
        month="$month"
        day="$day"
    else
        month=$(date +%m)
        day=$(date +%d)
    fi

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
