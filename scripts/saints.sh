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

# Cache configuration
_saints_CACHE_DIR="$(dirname "$(dirname "${BASH_SOURCE[0]}")")/data/cache/saints"
# Ensure the cache directory exists
mkdir -p "$_saints_CACHE_DIR"
CACHE_TTL_SECONDS=$((23 * 60 * 60)) # 23 hours
# Default cache behavior is enabled
_saints_USE_CACHE=true
# Force refresh cache
_saints_FORCE_REFRESH=false

# Override defaults if --no-cache or --force is passed during sourcing
# This allows the main hcnews.sh script to control caching for sourced scripts.
_current_sourcing_args_for_saints=("${@}")
for arg in "${_current_sourcing_args_for_saints[@]}"; do
  case "$arg" in
    --no-cache)
      _saints_USE_CACHE=false
      ;;
    --force)
      _saints_FORCE_REFRESH=true
      ;;
  esac
done

# Function to get today's date in YYYYMMDD format (same as RU script)
get_date_format() {
  date +"%Y%m%d"
}

# Function to check if cache exists and is valid and within TTL
check_cache() {
  local cache_file_path="$1"
  if [ -f "$cache_file_path" ] && [ "$_saints_FORCE_REFRESH" = false ]; then
    # Check TTL
    local file_mod_time
    file_mod_time=$(stat -c %Y "$cache_file_path")
    local current_time
    current_time=$(date +%s)
    if (( (current_time - file_mod_time) < CACHE_TTL_SECONDS )); then
      # Cache exists, not forced, and within TTL
      return 0
    fi
  fi
  return 1
}

# Function to read from cache
read_cache() {
  local cache_file_path="$1"
  cat "$cache_file_path"
}

# Function to write to cache
write_cache() {
  local cache_file_path="$1"
  local content="$2"
  
  # Ensure the directory exists
  mkdir -p "$(dirname "$cache_file_path")"
  
  # Write the content to the cache file
  printf "%s" "$content" > "$cache_file_path"
}

# Get the saint(s) of the day from the Vatican website.
# https://www.vaticannews.va/pt/santo-do-dia/MONTH/DAY.html
# This function prints the name(s) and the description of the saint(s).
get_saints_of_the_day_verbose () {
    local date_format
    date_format=$(get_date_format)
    local cache_file="${_saints_CACHE_DIR}/${date_format}_saints-verbose.txt"

    # Check if we have cached data
    if [ "$_saints_USE_CACHE" = true ] && check_cache "$cache_file"; then
      read_cache "$cache_file"
      return 0
    fi
    
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

    # Prepare the output to be both displayed and cached
    local output=""
    
    # Iterate over each name and print the corresponding description.
    local name
    while read -r name; do
        output+="😇 ${name}"$'\n'
        local saint_description
        saint_description=$(echo "$description" | head -n 1)
        output+="- ${saint_description}"$'\n'
        description=$(echo "$description" | tail -n +2)
    done <<< "$names"
    
    # Write to cache if cache is enabled
    if [ "$_saints_USE_CACHE" = true ]; then
      write_cache "$cache_file" "$output"
    fi
    
    # Output the result
    printf "%s" "$output"
}

# Get the saint(s) of the day from the Vatican website.
# https://www.vaticannews.va/pt/santo-do-dia/MONTH/DAY.html
# This function only prints the name of the saint(s).
get_saints_of_the_day () {
    local date_format
    date_format=$(get_date_format)
    local cache_file="${_saints_CACHE_DIR}/${date_format}_saints-regular.txt"

    # Check if we have cached data
    if [ "$_saints_USE_CACHE" = true ] && check_cache "$cache_file"; then
      read_cache "$cache_file"
      return 0
    fi
    
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

    local output=""
    local name
    while read -r name; do
        output+="😇${name}"$'\n'
    done <<< "$names"
    
    # Write to cache if cache is enabled
    if [ "$_saints_USE_CACHE" = true ]; then
      write_cache "$cache_file" "$output"
    fi
    
    # Output the result
    printf "%s" "$output"
}

write_saints () {
    local saints_verbose=$1

    echo "🙏 *Santos do dia*:"
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
#   -n, --no-cache: do not use cached data
#   -f, --force: force refresh cache
show_help() {
    echo "Usage: ./saints.sh [options]"
    echo "Options:"
    echo "  -h, --help: show the help"
    echo "  -v, --verbose: show the verbose description of the saints"
    echo "  -n, --no-cache: do not use cached data"
    echo "  -f, --force: force refresh cache"
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
            -n|--no-cache)
                _saints_USE_CACHE=false
                shift
                ;;
            -f|--force)
                _saints_FORCE_REFRESH=true
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