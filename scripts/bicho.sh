#!/usr/bin/env bash

# Source common library if not already loaded
[[ -n "${_HCNEWS_COMMON_LOADED:-}" ]] || source "${HCNEWS_COMMON_PATH:-${BASH_SOURCE%/*}/lib/common.sh}" 2>/dev/null || source "${BASH_SOURCE%/*}/scripts/lib/common.sh"

# Return the guess of the jogo do bicho of the day.
# we retrieve the guess from the website https://www.ojogodobicho.com/palpite.htm
function get_bicho_data {
  local use_cache=true
  local force_refresh=false

  # Check for global flags via common helper
  hcnews_parse_cache_args "$@"
  local use_cache=$_HCNEWS_USE_CACHE
  local force_refresh=$_HCNEWS_FORCE_REFRESH
  local ttl=${HCNEWS_CACHE_TTL["bicho"]:-86400}

  local date_format_local
  # Use cached date_format if available, otherwise fall back to date command
  if [[ -n "$date_format" ]]; then
    date_format_local="$date_format"
  else
    date_format_local=$(date +"%Y%m%d")
  fi
  
  local cache_file
  cache_file=$(hcnews_get_cache_path "bicho" "$date_format_local")
  
  # Check cache using common function
  if [[ "$use_cache" == true ]] && hcnews_check_cache "$cache_file" "$ttl" "$force_refresh"; then
    hcnews_read_cache "$cache_file"
    return 0
  fi

  # Download the webpage and extract the raw data
  local bicho_data
  bicho_data=$(curl -s "https://www.ojogodobicho.com/palpite.htm" |
    pup 'div.content ul.inline-list json{}' |
    jq -r '.[] | .children | map(.text) | join(" ")')

  # Save to cache if caching is enabled
  if [[ "$use_cache" == true && -n "$bicho_data" ]]; then
    hcnews_write_cache "$cache_file" "$bicho_data"
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


# Only run the main script if not being sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # run the script
  hcnews_parse_args "$@"
  write_bicho
fi
