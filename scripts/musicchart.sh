#!/usr/bin/env bash

# Source common library if not already loaded
[[ -n "${_HCNEWS_COMMON_LOADED:-}" ]] || source "${HCNEWS_COMMON_PATH}common.sh" 2>/dev/null || source "${BASH_SOURCE%/*}/lib/common.sh"

# Cache configuration
# Cache directory handled by common

# Settings
CACHE_TTL_SECONDS=${HCNEWS_CACHE_TTL["musicchart"]:-43200} # 12 hours
_musicchart_USE_CACHE=${_HCNEWS_USE_CACHE:-true}
_musicchart_FORCE_REFRESH=${_HCNEWS_FORCE_REFRESH:-false}

# Function to get today's date in YYYYMMDD format
get_music_date_format() {
	hcnews_get_date_format
}

# optimized get_music_chart using caching and faster requests
function get_music_chart() {
	local use_cache="${_musicchart_USE_CACHE:-${_HCNEWS_USE_CACHE:-true}}"
	local force_refresh="${_musicchart_FORCE_REFRESH:-${_HCNEWS_FORCE_REFRESH:-false}}"
	local date_string
	date_string=$(get_music_date_format)
	local cache_file
	hcnews_set_cache_path cache_file "musicchart" "$date_string"

	# Check if we have a recent output cache
	if [[ "$use_cache" == "true" ]] && hcnews_check_cache "$cache_file" "$CACHE_TTL_SECONDS" "$force_refresh"; then
		hcnews_read_cache "$cache_file"
		return 0
	fi

	# Fetch from Apple Music RSS (configurable)
	local json
	local chart_url="${HCNEWS_MUSIC_CHART_URL:-https://rss.applemarketingtools.com/api/v2/br/music/most-played/10/songs.json}"
	json=$(curl -sL -4 -A "Mozilla/5.0 (Script; HCnews)" --compressed --max-time 10 --connect-timeout 5 \
		"$chart_url")

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
	if [[ "$use_cache" == "true" ]]; then
		hcnews_write_cache "$cache_file" "$output_content"
	fi

	echo "$output_content"
}

# this function will write the music chart to the file
hc_component_musicchart() {
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
	hcnews_parse_args "$@"
	_musicchart_USE_CACHE=${_HCNEWS_USE_CACHE:-true}
	_musicchart_FORCE_REFRESH=${_HCNEWS_FORCE_REFRESH:-false}
	set -- "${_HCNEWS_REMAINING_ARGS[@]}"

	# argument parsing for direct execution
	while [[ $# -gt 0 ]]; do
		case "$1" in
		-h | --help)
			show_help
			exit 0
			;;
		-n | --no-cache)
			_musicchart_USE_CACHE=false
			;;
		-f | --force)
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

	hc_component_musicchart
fi
