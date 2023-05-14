#!/usr/bin/env bash

# this function will get the top 10 songs from the music chart
# https://genius.com/#top-songs
function get_music_chart () {
    # get the html
    HTML=$(curl -s https://genius.com/#top-songs)

    # get only <div class="PageGriddesktop-hg04e9-0 bvLPlx">...</div>
    TOP_10=$(echo "$HTML" | grep -oP '(?<=<div class="PageGriddesktop-hg04e9-0 bvLPlx">).*(?=</div>)')

    # save the title of the songs, <h3 class="ChartSongdesktop__TitleAndLyrics-sc-18658hh-2 dCmTwE" ...>...</h3>
    TITLE=$(echo "$TOP_10" | pup 'h3[class="ChartSongdesktop__TitleAndLyrics-sc-18658hh-2 dCmTwE"] text{}')
    # delete every line with "Lyrics"
    TITLE=$(echo "$TITLE" | grep -v "Lyrics")
    # add an dash to the beginning of each line
    TITLE=$(echo "$TITLE" | while read -r line; do
        echo " - $line"
    done)

    # print the top 10 songs
    echo "$TITLE"
}

# this function will write the music chart to the file
function write_music_chart () {
    # get the top 10 songs
    TOP_10=$(get_music_chart)

    # write the header
    echo "🎵 Top 10 Músicas 🎵"
    # write the top 10 songs
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