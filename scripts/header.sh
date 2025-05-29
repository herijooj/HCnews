#!/usr/bin/env bash
HEADER_DIR=$(dirname "$(realpath "${BASH_SOURCE[0]}")")
# Define cache directory relative to this script's location
# HEADER_DIR is .../scripts/, so $(dirname "$HEADER_DIR") is .../HCnews/
_header_CACHE_DIR="$(dirname "$HEADER_DIR")/data/cache/header"

source "$HEADER_DIR/quote.sh"

# Returns the current date in a pretty format.
# Usage: pretty_date [weekday] [day] [month] [year]
# If parameters are provided, uses them instead of calling date
function pretty_date {
  local date_arg="$1"
  local day_arg="$2" 
  local month_arg="$3"
  local year_arg="$4"
  
  local date day month year
  
  if [[ -n "$date_arg" && -n "$day_arg" && -n "$month_arg" && -n "$year_arg" ]]; then
    # Use provided cached values
    case $date_arg in
      1) date="segunda" ;;
      2) date="terça" ;;
      3) date="quarta" ;;
      4) date="quinta" ;;
      5) date="sexta" ;;
      6) date="sábado" ;;
      7) date="domingo" ;;
    esac
    day="$day_arg"
    
    case $month_arg in
      01) month="janeiro" ;;
      02) month="fevereiro" ;;
      03) month="março" ;;
      04) month="abril" ;;
      05) month="maio" ;;
      06) month="junho" ;;
      07) month="julho" ;;
      08) month="agosto" ;;
      09) month="setembro" ;;
      10) month="outubro" ;;
      11) month="novembro" ;;
      12) month="dezembro" ;;
    esac
    year="$year_arg"
  else
    # Fallback to date commands if no cached values provided
    date=$(date +%A)
    day=$(date +%d)
    month=$(date +%B)
    year=$(date +%Y)
  fi

  # Add "-feira" if it's not Saturday or Sunday
  if [[ $date != "sábado" && $date != "domingo" ]]; then
    date+="-feira"
  fi

  # Return the date in a pretty format
  echo "${date}, ${day} de ${month} de ${year}"
}

# calculates the HERIPOCH (the HCnews epoch)
# the start of the project was in 07/10/2021
# Usage: heripoch_date [current_timestamp]
function heripoch_date() {
    local current_timestamp="$1"
    local start_date="2021-10-07"
    
    if [[ -n "$current_timestamp" ]]; then
        # Use provided timestamp
        local current_date="$current_timestamp"
    else
        # Fallback to date command
        local current_date=$(date +%s)
    fi
    
    local difference=$((current_date - $(date -d "$start_date" +%s)))
    local days_since=$((difference / 86400))
    echo "$days_since"
}

# this function returns the moon phase from https://www.invertexto.com/fase-lua-hoje
function moon_phase () {
    local use_cache=true
    local force_refresh=false

    # Check for global flags from hcnews.sh if this script is sourced
    # hc_no_cache and hc_force_refresh would be set by hcnews.sh
    if [[ -n "${hc_no_cache+x}" && "$hc_no_cache" == true ]]; then
        use_cache=false
    fi
    if [[ -n "${hc_force_refresh+x}" && "$hc_force_refresh" == true ]]; then
        force_refresh=true
    fi

    local date_format
    date_format=$(date +"%Y%m%d")
    
    # Ensure the cache directory exists
    mkdir -p "$_header_CACHE_DIR"
    local cache_file="${_header_CACHE_DIR}/${date_format}_moon_phase.cache"

    if [[ "$use_cache" == true && "$force_refresh" == false && -f "$cache_file" ]]; then
        cat "$cache_file"
        return 0
    fi

    local fetched_moon_phase
    # grep all the lines with <span> and </span>
    fetched_moon_phase=$(curl -s https://www.invertexto.com/fase-lua-hoje | grep -oP '(?<=<span>).*(?=</span>)')
    
    # keep only the text before the first number
    fetched_moon_phase=$(echo "$fetched_moon_phase" | sed 's/[0-9].*//')

    if [[ "$use_cache" == true ]]; then
        # Save to cache
        echo "$fetched_moon_phase" > "$cache_file"
    fi

    # return the moon phase
    echo "$fetched_moon_phase"
}

# this function is used to write the header of the news file
function write_header () {
    # Use cached values if available (passed from main script)
    if [[ -n "$weekday" && -n "$day" && -n "$month" && -n "$year" && -n "$start_time" && -n "$days_since" ]]; then
        date=$(pretty_date "$weekday" "$day" "$month" "$year")
        edition=$(heripoch_date "$start_time")
        # Use cached days_since value instead of calculating it
        # days_since is already available from main script
    else
        # Fallback to original behavior
        date=$(pretty_date)
        edition=$(heripoch_date)
        days_since=$(date +%-j)
    fi
    
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

