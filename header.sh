#!/usr/bin/env bash
SCRIPT_DIR=$(dirname "$0")

source "$SCRIPT_DIR/quote.sh"

# Returns the current date in a pretty format.
# Usage: pretty_date
# Example output: "Segunda-feira, 10 de Abril de 2023"
function pretty_date {
  # set the locale to pt_BR
  export LC_TIME=pt_BR.UTF-8

  local date=$(date +%A)
  local day=$(date +%d)
  local month=$(date +%B)
  local year=$(date +%Y)

  # Add "-feira" if it's not Saturday or Sunday
  if [[ $date != "sábado" && $date != "domingo" ]]; then
    date+="-feira"
  fi

  # revert the locale to the default
  export LC_TIME=C

  # Return the date in a pretty format
  echo "${date}, ${day} de ${month} de ${year}"
}

# calculates the HERIPOCH (the HCnews epoch)
# the start of the project was in 07/10/2021
function heripoch_date() {
    local start_date="2021-10-07"
    local current_date=$(date +%s)
    local difference=$((current_date - $(date -d "$start_date" +%s)))
    local days_since=$((difference / 86400))
    echo "$days_since"
}

# this function returns the moon phase from https://www.invertexto.com/fase-lua-hoje
function moon_phase () {

    # grep all the lines with <span> and </span>
    moon_phase=$(curl -s https://www.invertexto.com/fase-lua-hoje | grep -oP '(?<=<span>).*(?=</span>)')
    
    moon_phase=$(echo $moon_phase | sed 's/%/% de Visibilidade/')
    # moon_phase=$(echo $moon_phase | sed 's/km/km de Distância/')
    # moon_phase=$(echo $moon_phase | sed 's/$/ de Idade/')

    # return the moon phase
    echo $moon_phase
}

# this function is used to write the header of the news file
function write_header () {

    date=$(pretty_date)
    edition=$(heripoch_date)
    days_since=$(date +%j)
    moon_phase=$(moon_phase)
    day_quote=$(quote)

    # write the header
    echo "📰 *HCNews*, Edição $edition 🗞"
    echo "📌 De Araucária Paraná 🇧🇷" 
    echo "🗺 Notícias do Brasil e do Mundo 🌎" 
    echo "📅 $date" 
    echo "⏳ $days_sinceº dia do ano" 
    echo "🌔 $moon_phase" 
    echo "" 
    echo "📝 *Frase do dia:*" 
    echo "$day_quote" 
    echo ""
    
}

# -------------------------------- Running locally --------------------------------

# help function
# Usage: ./header.sh [options]
# Options:
#   -h, --help: show the help
show_help() {
  echo "Usage: ./header.sh [options]"
  echo "The header of the news file will be printed to the console."
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
  write_header
fi

