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
_musicchart_CACHE_BASE_DIR="$(dirname "$(dirname "${BASH_SOURCE[0]}")")/data/cache/musicchart"
# Ensure the cache directory exists
mkdir -p "$_musicchart_CACHE_BASE_DIR"
CACHE_TTL_SECONDS=$((12 * 60 * 60)) # 12 hours
_musicchart_USE_CACHE=true
_musicchart_FORCE_REFRESH=false

# Override defaults if --no-cache or --force is passed during sourcing
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    _current_sourcing_args_for_musicchart=("${@}")
    for arg in "${_current_sourcing_args_for_musicchart[@]}"; do
      case "$arg" in
        --no-cache)
          _musicchart_USE_CACHE=false
          ;;
        --force)
          _musicchart_FORCE_REFRESH=true
          ;;
      esac
    done
fi

# Function to get today's date in YYYYMMDD format
get_date_format() {
  date +"%Y%m%d"
}

# Function to check if cache exists and is from today and within TTL
check_cache() {
  local cache_file_path="$1"
  if [ -f "$cache_file_path" ] && [ "$_musicchart_FORCE_REFRESH" = false ]; then
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
  mkdir -p "$(dirname "$cache_file_path")"
  echo "$content" > "$cache_file_path"
}

# optimized get_music_chart using caching and faster requests
function get_music_chart () {
  local html title artist i
  local date_format
  date_format=$(get_date_format)
  local cache_file="${_musicchart_CACHE_BASE_DIR}/${date_format}.musicchart"
  
  # Check if we have a recent output cache
  if [ "$_musicchart_USE_CACHE" = true ] && check_cache "$cache_file"; then
    read_cache "$cache_file"
    return
  fi
  
  # Optimized curl with timeout and compression
  html=$(curl -s --compressed --max-time 5 --connect-timeout 3 \
         --user-agent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" \
         https://genius.com/#top-songs)
    
  # Save HTML to temp file for processing if successful
  local temp_html_file
  if [[ -n "$html" ]]; then
    temp_html_file=$(mktemp)
    echo "$html" > "$temp_html_file"
  else
    echo "Failed to retrieve chart data" >&2
    return 1
  fi

  # Process HTML and generate output
  local output_content=""
  mapfile -t titles < <(pup 'div[class*="ChartSong-desktop__Title"] text{}' < "$temp_html_file" | head -10)
  mapfile -t artists < <(pup 'h4[class*="ChartSong-desktop"] text{}' < "$temp_html_file" | head -10)
  rm -f "$temp_html_file" # Clean up temp file
    
  for i in "${!titles[@]}"; do
    title=$(decode_html_entities "${titles[i]}")
    artist=$(decode_html_entities "${artists[i]}")
    output_content+="- $((i+1)). \`$title - $artist\`"$'\n'
  done
  
  # Write to cache if cache is enabled
  if [ "$_musicchart_USE_CACHE" = true ]; then
    write_cache "$cache_file" "$output_content"
  fi
  
  echo "$output_content"
}

# this function will write the music chart to the file
function write_music_chart () {
  # get the formatted top 10 songs
  TOP_10=$(get_music_chart)

  # write the header
  echo "🎵 *Top 10*:"
  # write the formatted list
  echo "$TOP_10"
  echo "📌 De Genius.com/#top-songs"
  echo ""
}

# -------------------------------- Running locally --------------------------------
# help function
# Usage: ./musicchart.sh [options]
# Options:
#   -h, --help: show the help
#   -n, --no-cache: Do not use cached data
#   -f, --force: Force refresh cache
show_help() {
  echo "Usage: ./musicchart.sh [options]"
  echo "The top 10 songs from the music chart will be printed to the console."
  echo "Options:"
  echo "  -h, --help: show the help"
  echo "  -n, --no-cache: Do not use cached data"
  echo "  -f, --force: Force refresh cache"
}

# optimized argument parsing with getopts
get_arguments() {
  while getopts ":hnf" opt; do # Added n and f for no-cache and force
    case $opt in
      h) show_help; exit ;;
      n) _musicchart_USE_CACHE=false ;; # Set _musicchart_USE_CACHE to false
      f) _musicchart_FORCE_REFRESH=true ;; # Set _musicchart_FORCE_REFRESH to true
      *) show_help; exit 1 ;;
    esac
  done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # run the script
  get_arguments "$@"
  write_music_chart
fi
