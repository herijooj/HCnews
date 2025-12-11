#!/usr/bin/env bash

# Source common library if not already loaded and strict variable usage
if [[ -z "${_HCNEWS_COMMON_LOADED:-}" ]]; then
    SCRIPT_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
    if [[ -f "$SCRIPT_DIR/lib/common.sh" ]]; then
        source "$SCRIPT_DIR/lib/common.sh"
    elif [[ -f "scripts/lib/common.sh" ]]; then
        source "scripts/lib/common.sh"
    fi
fi

# Cache configuration
# Cache directory handled by common

# Settings
CACHE_TTL_SECONDS=${HCNEWS_CACHE_TTL["musicchart"]:-43200} # 12 hours
_musicchart_USE_CACHE=${_HCNEWS_USE_CACHE:-true}
_musicchart_FORCE_REFRESH=${_HCNEWS_FORCE_REFRESH:-false}

# Parse local arguments if sourced/executed with args
hcnews_parse_cache_args "$@"
# Update local variables based on global/parsed values
[[ "${_HCNEWS_USE_CACHE}" == "false" ]] && _musicchart_USE_CACHE=false
[[ "${_HCNEWS_FORCE_REFRESH}" == "true" ]] && _musicchart_FORCE_REFRESH=true

# Function to get today's date in YYYYMMDD format
get_music_date_format() {
  # Use cached date_format if available (from common.sh or global)
  if [[ -n "$date_format" ]]; then
    echo "$date_format"
  else
    date +"%Y%m%d"
  fi
}

# optimized get_music_chart using caching and faster requests
function get_music_chart () {
  local date_string
  date_string=$(get_music_date_format)
  local cache_file
  cache_file=$(hcnews_get_cache_path "musicchart" "$date_string")
  
  # Check if we have a recent output cache
  if [[ "${_HCNEWS_USE_CACHE:-true}" == "true" ]] && hcnews_check_cache "$cache_file" "$CACHE_TTL_SECONDS" "${_HCNEWS_FORCE_REFRESH:-false}"; then
    hcnews_read_cache "$cache_file"
    return 0
  fi
  
  # Fetch from Apple Music RSS (Brazil)
  local json
  json=$(curl -sL -4 --compressed --max-time 10 --connect-timeout 5 \
         "https://rss.applemarketingtools.com/api/v2/br/music/most-played/10/songs.json")
    
  if [[ -z "$json" ]]; then
    echo "Failed to retrieve chart data" >&2
    return 1
  fi

  # Parse JSON with jq
  local output_content=""
  if command -v jq >/dev/null 2>&1; then
      output_content=$(echo "$json" | jq -r '.feed.results | to_entries | .[] | "- \(.key + 1). `\(.value.name) - \(.value.artistName)`"')
  else
      # Fallback if jq is missing (though it should be in nix-shell)
      output_content="- Error: jq dependencies missing"
  fi
  
  if [[ -z "$output_content" ]]; then
    output_content="- Chart data temporarily unavailable"
  fi
  
  # Write to cache
  if [[ "$_musicchart_USE_CACHE" == "true" ]]; then
    hcnews_write_cache "$cache_file" "$output_content"
  fi
  
  echo "$output_content"
}

# this function will write the music chart to the file
function write_music_chart () {
  # get the formatted top 10 songs
  local TOP_10
  TOP_10=$(get_music_chart)

  # write the header
  echo "🎵 *Top 10 Músicas*:"
  # write the formatted list
  echo "$TOP_10"
  echo "_Fonte: Apple Music_"
  echo ""
}

# -------------------------------- Running locally --------------------------------
# help function
show_help() {
  echo "Usage: ./musicchart.sh [options]"
  echo "The top 10 songs from the music chart will be printed to the console."
  echo "Options:"
  echo "  -h, --help: show the help"
  echo "  -n, --no-cache: Do not use cached data"
  echo "  -f, --force: Force refresh cache"
}

# Only run main logic if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # argument parsing for direct execution
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        show_help
        exit 0
        ;;
      -n|--no-cache)
        _musicchart_USE_CACHE=false
        _HCNEWS_USE_CACHE=false
        ;;
      -f|--force)
        _musicchart_FORCE_REFRESH=true
        _HCNEWS_FORCE_REFRESH=true
        ;;
      *)
        echo "Invalid argument: $1"
        show_help
        exit 1
        ;;
    esac
    shift
  done
  
  write_music_chart
fi
