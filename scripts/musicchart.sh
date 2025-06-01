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
  # Use cached date_format if available, otherwise fall back to date command
  if [[ -n "$date_format" ]]; then
    echo "$date_format"
  else
    date +"%Y%m%d"
  fi
}

# Function to check if cache exists and is from today and within TTL
check_cache() {
  local cache_file_path="$1"
  if [ -f "$cache_file_path" ] && [ "$_musicchart_FORCE_REFRESH" = false ]; then
    # Check TTL
    local file_mod_time
    file_mod_time=$(stat -c %Y "$cache_file_path")
    local current_time
    # Use cached start_time if available, otherwise fall back to date command
    if [[ -n "$start_time" ]]; then
      current_time="$start_time"
    else
      current_time=$(date +%s)
    fi
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
  local date_format
  date_format=$(get_date_format)
  local cache_file="${_musicchart_CACHE_BASE_DIR}/${date_format}.musicchart"
  
  # Check if we have a recent output cache
  if [ "$_musicchart_USE_CACHE" = true ] && check_cache "$cache_file"; then
    read_cache "$cache_file"
    return
  fi
  
  # Optimized curl with aggressive timeouts and better headers
  local html
  html=$(timeout 8s curl -s --compressed --max-time 6 --connect-timeout 2 \
         --retry 1 --retry-delay 0 --fail \
         -H "User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36" \
         -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" \
         -H "Accept-Language: en-US,en;q=0.5" \
         -H "Accept-Encoding: gzip, deflate" \
         "https://genius.com/#top-songs" 2>/dev/null)
    
  # Quick validation - fail fast if no data
  if [[ -z "$html" || ${#html} -lt 1000 ]]; then
    echo "Failed to retrieve chart data" >&2
    return 1
  fi

  # Single-pass HTML processing - extract both titles and artists in one go
  local combined_data
  combined_data=$(echo "$html" | timeout 5s pup 'div[class*="ChartSong-desktop"] json{}' 2>/dev/null | \
    timeout 3s jq -r '.[] | 
      select(.children and (.children | length > 0)) |
      .children[] | 
      select(.tag == "div" and (.class // "" | contains("ChartSongDesktop__Right"))) |
      (.children[] | select(.tag == "div" and (.class // "" | contains("ChartSong-desktop__Title"))) | .text // empty),
      (.children[] | select(.tag == "h4") | .text // empty)' 2>/dev/null | \
    head -20)
  
  # Build output efficiently
  local output_content=""
  local count=0
  local title=""
  local expecting_artist=false
  
  while IFS= read -r line && [[ $count -lt 10 ]]; do
    [[ -z "$line" ]] && continue
    
    if [[ "$expecting_artist" == false ]]; then
      # This should be a title
      title=$(decode_html_entities "$line")
      expecting_artist=true
    else
      # This should be an artist
      local artist
      artist=$(decode_html_entities "$line")
      ((count++))
      output_content+="- $count. \`$title - $artist\`"$'\n'
      expecting_artist=false
    fi
  done <<< "$combined_data"
  
  # Fallback method if the above doesn't work
  if [[ $count -eq 0 ]]; then
    # Simple fallback extraction
    local titles artists
    titles=$(echo "$html" | timeout 3s pup 'div[class*="ChartSong-desktop__Title"] text{}' 2>/dev/null | head -10)
    artists=$(echo "$html" | timeout 3s pup 'h4[class*="ChartSong-desktop"] text{}' 2>/dev/null | head -10)
    
    if [[ -n "$titles" && -n "$artists" ]]; then
      local title_array=()
      local artist_array=()
      
      while IFS= read -r line; do
        [[ -n "$line" ]] && title_array+=("$(decode_html_entities "$line")")
      done <<< "$titles"
      
      while IFS= read -r line; do
        [[ -n "$line" ]] && artist_array+=("$(decode_html_entities "$line")")
      done <<< "$artists"
      
      for i in "${!title_array[@]}"; do
        if [[ $i -lt ${#artist_array[@]} ]]; then
          ((count++))
          output_content+="- $count. \`${title_array[i]} - ${artist_array[i]}\`"$'\n'
          [[ $count -ge 10 ]] && break
        fi
      done
    fi
  fi
  
  # Final fallback if still no data
  if [[ $count -eq 0 ]]; then
    output_content="- Chart data temporarily unavailable"$'\n'
  fi
  
  # Async cache write for better performance
  if [ "$_musicchart_USE_CACHE" = true ]; then
    (write_cache "$cache_file" "$output_content") &
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

# optimized argument parsing
get_arguments() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        show_help
        exit 0
        ;;
      -n|--no-cache)
        _musicchart_USE_CACHE=false
        ;;
      -f|--force)
        _musicchart_FORCE_REFRESH=true
        ;;
      *)
        echo "Invalid argument: $1"
        show_help
        exit 1
        ;;
    esac
    shift
  done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # run the script
  get_arguments "$@"
  write_music_chart
fi
