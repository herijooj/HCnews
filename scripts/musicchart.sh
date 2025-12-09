#!/usr/bin/env bash

# Cache configuration
_musicchart_CACHE_BASE_DIR="$(dirname "$(dirname "${BASH_SOURCE[0]}")")/data/cache/musicchart"
# Ensure the cache directory exists
[[ -d "$_musicchart_CACHE_BASE_DIR" ]] || mkdir -p "$_musicchart_CACHE_BASE_DIR"
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
  local cache_dir
  cache_dir="$(dirname "$cache_file_path")"
  [[ -d "$cache_dir" ]] || mkdir -p "$cache_dir"
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
  
  # Fetch from Apple Music RSS (Brazil)
  local json
  json=$(curl -sL --max-time 10 --connect-timeout 5 \
         "https://rss.applemarketingtools.com/api/v2/br/music/most-played/10/songs.json")
    
  if [[ -z "$json" ]]; then
    echo "Failed to retrieve chart data" >&2
    return 1
  fi

  # Parse JSON with jq
  local output_content=""
  output_content=$(echo "$json" | jq -r '.feed.results | to_entries | .[] | "- \(.key + 1). `\(.value.name) - \(.value.artistName)`"')
  
  if [[ -z "$output_content" ]]; then
    output_content="- Chart data temporarily unavailable"
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
  echo "🎵 *Top 10 (Apple Music BR)*:"
  # write the formatted list
  echo "$TOP_10"
  echo "_Fonte: Apple Music_"
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
