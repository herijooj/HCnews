#!/usr/bin/env bash

# Return the guess of the jogo do bicho of the day.
# we retrieve the guess from the website https://www.ojogodobicho.com/palpite.htm
# Usage: bicho
# Example output: 
# Grupo: 1 7 15 18 24
# Dezena: 10 20 30 40 50
# Centena: 100 200 300 400 500
# Milhar: 1000 2000 3000 4000 5000
function get_bicho_data {
    # Download the webpage and extract the data
    curl -s "https://www.ojogodobicho.com/palpite.htm" |
    pup 'div.content ul.inline-list json{}' |
    jq -r '.[] | .children | map(.text) | join(" ")' |
    awk '{
        if (NR==1) print "Grupo: " $0
        if (NR==2) print "Dezena: " $0
        if (NR==3) print "Centena: " $0
        if (NR==4) print "Milhar: " $0
    }'
}

# this function converts an number to a bicho name
# the bicho name is the name of the animal that corresponds to the number
function number_to_bicho {
    local number=$1
    if [ $number -eq 1 ]; then
        echo "Bicho: "
    fi
}

function write_bicho {
    local bicho_data=$(get_bicho_data)
    
    echo "🎲 *Palpites do Jogo do Bicho* 🐾"
    echo "$bicho_data" | sed '
        s/Grupo:/🔢 Grupo:/
        s/Dezena:/🔟 Dezena:/
        s/Centena:/💯 Centena:/
        s/Milhar:/🏆 Milhar:/
    '
    echo ""
}

# -------------------------------- Running locally --------------------------------

# help function
# Usage: ./bicho.sh [options]
# Options:
#   -h, --help: show the help
show_help() {
  echo "Usage: ./bicho.sh [options]"
  echo "The guess of the jogo do bicho of the day will be printed to the console."
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
  write_bicho
fi