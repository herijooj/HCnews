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

# this function will get the top 10 songs from the music chart
# https://genius.com/#top-songs
function get_music_chart () {
  # get the html
  HTML=$(curl -s https://genius.com/#top-songs)
  
  # extract components using pup with updated selectors
  # Using partial class names for more resilient matching
  TITLES=$(echo "$HTML" | pup 'div[class*="ChartSong-desktop__Title"] text{}')
  # Updated selector to find artists correctly
  ARTISTS=$(echo "$HTML" | pup 'h4[class*="ChartSong-desktop"] text{}' | head -10)

  # format the top 10 songs
  for i in {0..9}; do
    # get the title and artist
    TITLE=$(echo "$TITLES" | sed -n "$((i+1))p")
    ARTIST=$(echo "$ARTISTS" | sed -n "$((i+1))p")
    
    # decode HTML entities in both title and artist
    TITLE=$(decode_html_entities "$TITLE")
    ARTIST=$(decode_html_entities "$ARTIST")
    
    # print the formatted song
    echo "- $((i+1)). \`$TITLE - $ARTIST\`"
  done
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
show_help() {
  echo "Usage: ./musicchart.sh [options]"
  echo "The top 10 songs from the music chart will be printed to the console."
  echo "Options:"
  echo "  -h, --help: show the help"
}

# this function will receive the arguments
get_arguments() {
  # Get the arguments
  while [ "$1" != "" ]; do
  case $1 in
    -h | --help)
    show_help
    exit
    ;;
    *)
    echo "Invalid argument"
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
