#!/usr/bin/env bash

# Function to decode HTML entities
decode_html_entities() {
  local input="$1"
  if command -v python3 &> /dev/null; then
    # Use Python for reliable HTML entity decoding if available
    python3 -c "import html, sys; print(html.unescape('''$input'''))" 2>/dev/null || echo "$input"
  else
    # Fallback to sed for basic entity replacement
    echo "$input" | sed 's/&amp;/\&/g; s/&quot;/"/g; s/&lt;/</g; s/&gt;/>/g; s/&apos;/'\''/g'
  fi
}

# Get the saint(s) of the day from the Vatican website.
# https://www.vaticannews.va/pt/santo-do-dia/MONTH/DAY.html
# This function prints the name(s) and the description of the saint(s).
get_saints_of_the_day_verbose () {
    # Get the current month and day.
    local month
    local day
    month=$(date +%m)
    day=$(date +%d)

    # Get the URL
    local url="https://www.vaticannews.va/pt/santo-do-dia/$month/$day.html"

    # Only the names
    local names
    names=$(curl -s "$url" | pup '.section__head h2 text{}' | sed '/^$/d')
    
    # Check if we got any names
    if [[ -z "$names" ]]; then
        echo "⚠️ Não foi possível encontrar santos para hoje."
        return 1
    fi

    # The description
    local description
    description=$(curl -s "$url" | pup '.section__head h2 text{}, .section__content p text{}' | sed '/^$/d' | sed '1d'| sed '/^[[:space:]]*$/d')
    
    # Decode HTML entities in the description
    description=$(decode_html_entities "$description")

    # Iterate over each name and print the corresponding description.
    local name
    while read -r name; do
        echo "😇 $name"
        local saint_description
        saint_description=$(echo "$description" | head -n 1)
        echo "- $saint_description"
        description=$(echo "$description" | tail -n +2)
    done <<< "$names"
}

# Get the saint(s) of the day from the Vatican website.
# https://www.vaticannews.va/pt/santo-do-dia/MONTH/DAY.html
# This function only prints the name of the saint(s).
get_saints_of_the_day () {
    # Get the current month and day.
    local month
    local day
    month=$(date +%m)
    day=$(date +%d)

    # Get the URL
    local url="https://www.vaticannews.va/pt/santo-do-dia/$month/$day.html"

    # Only the names
    local names
    names=$(curl -s "$url" | pup '.section__head h2 text{}' | sed '/^$/d')
    
    # Check if we got any names
    if [[ -z "$names" ]]; then
        echo "⚠️ Não foi possível encontrar santos para hoje."
        return 1
    fi

    local name
    while read -r name; do
        echo "😇 $name"
    done <<< "$names"
}

write_saints () {
    local saints_verbose=$1

    echo "🙏 *Santos do dia* 💒"
    if [[ "$saints_verbose" == "true" ]]; then
        get_saints_of_the_day_verbose
    else
        get_saints_of_the_day
    fi
    echo ""
}

# -------------------------------- Running locally --------------------------------

# help function
# Usage: ./saints.sh [options]
# Options:
#   -h, --help: show the help
#   -v, --verbose: show the verbose description of the saints
show_help() {
    echo "Usage: ./saints.sh [options]"
    echo "Options:"
    echo "  -h, --help: show the help"
    echo "  -v, --verbose: show the verbose description of the saints"
}

# this function will receive the arguments
get_arguments() {
    # Define variables
    saints_verbose=false

    # Get the arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--verbose)
                saints_verbose=true
                shift
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
    write_saints "$saints_verbose"
fi