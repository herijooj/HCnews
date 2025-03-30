#!/usr/bin/env bash
HEADER_DIR=$(dirname "$(realpath "${BASH_SOURCE[0]}")")

source "$HEADER_DIR/quote.sh"

# Returns the current date in a pretty format.
# Usage: pretty_date
# Example output: "Segunda-feira, 10 de Abril de 2023"
function pretty_date {
  # set the locale to pt_BR
  local date=$(date +%A)
  local day=$(date +%d)
  local month=$(date +%B)
  local year=$(date +%Y)

  # Add "-feira" if it's not Saturday or Sunday
  if [[ $date != "sábado" && $date != "domingo" ]]; then
    date+="-feira"
  fi

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
    
    # keep only the text before the first number
    moon_phase=$(echo $moon_phase | sed 's/[0-9].*//')

    # moon_phase=$(echo $moon_phase | sed 's/%/% de Visibilidade/')
    # moon_phase=$(echo $moon_phase | sed 's/km/km de Distância/')
    # moon_phase=$(echo $moon_phase | sed 's/$/ de Idade/')

    # return the moon phase
    echo $moon_phase
}

# this function is used to write the header of the news file
function write_header () {

    date=$(pretty_date)
    edition=$(heripoch_date)
    days_since=$(date +%-j)
    moon_phase=$(moon_phase)
    day_quote=$(quote)

    # Calculate the percentage of the year passed
    year_percentage=$((days_since * 100 / 365))

    # Create the progress bar string
    progress_bar_length=20 # Adjust for total length
    filled_blocks=$((year_percentage * progress_bar_length / 100))
    empty_blocks=$((progress_bar_length - filled_blocks))
    filled_string=$(printf "%${filled_blocks}s" | tr ' ' '#')
    empty_string=$(printf "%${empty_blocks}s" | tr ' ' '.')
    progress_bar="[$filled_string$empty_string]"

    # write the header
    echo "📰 *HCNews* Edição $edition 🗞"
    echo "🇧🇷 De Araucária Paraná " 
    # echo "🗺 Notícias do Brasil e do Mundo 🌎" 
    echo "📅 $date" 
    # echo "⏳ $days_sinceº dia do ano"
    echo "⏳ Dia $days_since/365 $progress_bar ${year_percentage}%"
    echo "🌔 $moon_phase" 
    echo "" 
    echo "📝 *Frase do dia:*" 
    echo "_${day_quote}_"
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

