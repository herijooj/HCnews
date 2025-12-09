#!/usr/bin/env bash

BICHO_DIR=$(dirname "$(realpath "${BASH_SOURCE[0]}")")
# Define cache directory relative to this script's location
_bicho_CACHE_DIR="$(dirname "$BICHO_DIR")/data/cache/bicho"

# Return the guess of the jogo do bicho of the day.
# we retrieve the guess from the website https://www.ojogodobicho.com/palpite.htm
function get_bicho_data {
  local use_cache=true
  local force_refresh=false

  # Check for global flags from hcnews.sh if this script is sourced
  if [[ -n "${hc_no_cache+x}" && "$hc_no_cache" == true ]]; then
    use_cache=false
  fi
  if [[ -n "${hc_force_refresh+x}" && "$hc_force_refresh" == true ]]; then
    force_refresh=true
  fi

  local date_format_local
  # Use cached date_format if available, otherwise fall back to date command
  if [[ -n "$date_format" ]]; then
    date_format_local="$date_format"
  else
    date_format_local=$(date +"%Y%m%d")
  fi
  
  # Ensure the cache directory exists
  [[ -d "$_bicho_CACHE_DIR" ]] || mkdir -p "$_bicho_CACHE_DIR"
  local cache_file="${_bicho_CACHE_DIR}/${date_format_local}_bicho.cache"

  # Check cache first (unless force refresh is requested)
  if [[ "$use_cache" == true && "$force_refresh" == false && -f "$cache_file" ]]; then
    cat "$cache_file"
    return 0
  fi

  # Download the webpage and extract the raw data
  local bicho_data
  bicho_data=$(curl -s "https://www.ojogodobicho.com/palpite.htm" |
    pup 'div.content ul.inline-list json{}' |
    jq -r '.[] | .children | map(.text) | join(" ")')

  # Save to cache if caching is enabled
  if [[ "$use_cache" == true && -n "$bicho_data" ]]; then
    echo "$bicho_data" > "$cache_file"
  fi

  echo "$bicho_data"
}

function format_bicho_data {
  local raw_data="$1"
  
  echo "$raw_data" | awk '
  function number_to_bicho_with_emoji(number) {
    stripped = number
    sub(/^0*/, "", stripped)
    if (stripped == "") stripped = 100
    D = stripped
    group = int((D - 1) / 4 + 1)
    
    emojis = "🦩 🦅 🐴 🦋 🐶 🐐 🐑 🐫 🐍 🐇 🐎 🐘 🐓 🐈 🐊 🦁 🐒 🐖 🦚 🦃 🐂 🐅 🐻 🦌 🐄"
    names = "Avestruz Águia Burro Borboleta Cachorro Cabra Carneiro Camelo Cobra Coelho Cavalo Elefante Galo Gato Jacaré Leão Macaco Porco Pavão Peru Touro Tigre Urso Veado Vaca"
    
    split(emojis, emoji_array, " ")
    split(names, name_array, " ")
    
    return emoji_array[group] " " stripped " " name_array[group]
  }
  
  function format_grupo(items) {
    line = "- "
    line_length = 2  # Start with "- "
    split(items, arr, " ")
    
    for (i = 1; i <= length(arr); i++) {
      item = number_to_bicho_with_emoji(arr[i])
      
      # Check if adding this item will exceed the limit
      item_with_separator = (i > 1 ? "| " : "") item
      new_length = line_length + length(item_with_separator) + 1
      
      if (new_length > 38 && line_length > 2) {
        # Print current line and start a new one
        print line
        line = "- " item
        line_length = 2 + length(item)
      } else {
        # Add to current line
        if (i > 1) line = line " | "
        line = line item
        line_length = line_length + length(item_with_separator)
      }
    }
    
    # Print the last line if not empty
    if (line_length > 2) {
      print line
    }
    
    # Add a blank line after section
    print ""
  }
  
  function format_simple_category(items, emoji, category_name) {
    line = emoji " " category_name ": "
    split(items, arr, " ")
    
    for (i = 1; i <= length(arr); i++) {
      if (i > 1) line = line ", "
      line = line arr[i]
    }
    
    print line
  }
  
  BEGIN {
    FS = "\n"
  }
  {
    lines[NR] = $0
  }
  END {
    # Format Grupo with bicho names and emojis
    format_grupo(lines[1])
    
    # Format Dezena, Centena and Milhar with simple format
    format_simple_category(lines[2], "🔟", "Dezena")
    format_simple_category(lines[3], "💯", "Centena")
    format_simple_category(lines[4], "🏆", "Milhar")
  }'
}

function write_bicho {
  local raw_bicho_data=$(get_bicho_data)
  
  echo "🎲 *Palpites do Jogo do Bicho:*"
  format_bicho_data "$raw_bicho_data"
  echo "🍀 *Boa sorte!*"
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

# Only run the main script if not being sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # run the script
  get_arguments "$@"
  write_bicho
fi
