#!/usr/bin/env bash

# Define the path to the emoji test file (adjust as needed)
EMOJI_TEST_FILE="$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../data/emoji-test.txt"

# Function: get_emoji
# Reads the emoji-test.txt file, filters out comments and blank lines, then selects a random emoji.
function get_emoji() {
    # Check if the emoji file exists
    if [[ ! -f "$EMOJI_TEST_FILE" ]]; then
        echo "Error: Emoji file not found at $EMOJI_TEST_FILE" >&2
        exit 1
    fi

    # Much faster: use awk to filter and shuf to randomize in one pipeline
    emoji_info=$(awk '!/^#/ && NF {split($0,a,"#"); if(a[2]) print substr(a[2],2)}' "$EMOJI_TEST_FILE" | shuf -n 1)
    echo "$emoji_info"
}

# Function: write_emoji
# Calls get_emoji and prints the result in a formatted way.
function write_emoji() {
    emoji=$(get_emoji)
    echo "🎉 *Emoji do dia:*"
    echo "- $emoji"
    echo ""
}

# -------------------------------- Running the script --------------------------------

# If the script is run directly, call the write_emoji function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    write_emoji
fi

