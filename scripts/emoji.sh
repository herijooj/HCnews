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

    # Use shuf to select a random line from the file, ignoring comment and empty lines
    selected_line=$(grep -v '^#' "$EMOJI_TEST_FILE" | grep -v '^\s*$' | shuf -n 1)

    # Extract the emoji info after the '#' character.
    emoji_info=$(echo "$selected_line" | awk -F'#' '{print $2}' | sed 's/^[ \t]*//')
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

