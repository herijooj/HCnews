#!/usr/bin/env bash
# Source common library if not already loaded
# shellcheck source=/dev/null
[[ -n "${_HCNEWS_COMMON_LOADED:-}" ]] || source "${HCNEWS_COMMON_PATH:-${BASH_SOURCE%/*}/lib/common.sh}" 2>/dev/null || source "${BASH_SOURCE%/*}/scripts/lib/common.sh"

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

	# Define cache file path
	# Use global cache dir if available, otherwise relative to script
	if [[ -n "${HCNEWS_CACHE_DIR:-}" ]]; then
		EMOJI_CACHE_FILE="${HCNEWS_CACHE_DIR}/emoji_list.cache"
	else
		EMOJI_CACHE_FILE="$(dirname "$EMOJI_TEST_FILE")/emoji_list.cache"
	fi

	# Create cache if it doesn't exist or if source is newer
	if [[ ! -f "$EMOJI_CACHE_FILE" ]] || [[ "$EMOJI_TEST_FILE" -nt "$EMOJI_CACHE_FILE" ]]; then
		# Filter valid emojis and save to cache
		awk '!/^#/ && NF {split($0,a,"#"); if(a[2]) print substr(a[2],2)}' "$EMOJI_TEST_FILE" >"$EMOJI_CACHE_FILE"
	fi

	# Select random line from cache (much faster than shuf on pipe)
	shuf -n 1 "$EMOJI_CACHE_FILE"
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
