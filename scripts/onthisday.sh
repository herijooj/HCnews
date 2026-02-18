#!/usr/bin/env bash

# Source common library
[[ -n "${_HCNEWS_COMMON_LOADED:-}" ]] || source "${HCNEWS_COMMON_PATH}common.sh" 2>/dev/null || source "${BASH_SOURCE%/*}/lib/common.sh"

get_onthisday() {
	local use_cache="${_onthisday_USE_CACHE:-${_HCNEWS_USE_CACHE:-true}}"
	local force_refresh="${_onthisday_FORCE_REFRESH:-${_HCNEWS_FORCE_REFRESH:-false}}"
	local date_str
	date_str=$(hcnews_get_date_format)
	local cache_file
	hcnews_set_cache_path cache_file "onthisday" "$date_str"
	local ttl=${HCNEWS_CACHE_TTL["onthisday"]:-86400}

	# Cache check
	if [[ "$use_cache" = true ]] && hcnews_check_cache "$cache_file" "$ttl" "$force_refresh"; then
		hcnews_read_cache "$cache_file"
		return 0
	fi

	local month day
	month=$(hcnews_get_month)
	day=$(hcnews_get_day)
	local URL="https://api.wikimedia.org/feed/v1/wikipedia/pt/onthisday/events/${month}/${day}"

	local response
	response=$(curl -s -H "User-Agent: HCnews/1.0 (https://github.com/herijooj/HCnews)" --compressed --connect-timeout 5 --max-time 10 "$URL") || return 1

	# Process directly. If jq fails, items will be empty.
	# We handle newlines in text by replacing with space, then shuffle and sort.
	local items
	items=$(jq -r '.events[]? | "\(.year)|\(.text | gsub("\\n"; " ") | gsub("[[:space:]]+"; " ") | gsub("^[[:space:]]+|[[:space:]]+$"; ""))"' <<<"$response" 2>/dev/null | shuf -n 3 | sort -n -t '|' -k 1)

	# Fallback if empty (e.g. jq failed or no events)
	if [[ -z "$items" ]]; then
		return 1
	fi

	local output="📅 *Hoje na História* ($day/$month)"
	local year text
	while IFS='|' read -r year text; do
		# Decode HTML entities just in case (e.g. &nbsp;), though common.sh has a function
		if type hcnews_decode_html_entities &>/dev/null; then
			text=$(hcnews_decode_html_entities "$text")
		fi
		output+=$'\n'
		output+="- *${year}*: ${text}"
	done <<<"$items"

	output+=$'\n_Fonte: Wikipedia_'

	if [[ "$use_cache" == true ]]; then
		hcnews_write_cache "$cache_file" "$output"
	fi
	echo "$output"
}

hc_component_onthisday() {
	get_onthisday
}

# Standard help
show_help() {
	echo "Usage: ./onthisday.sh [--no-cache|--force]"
	echo "Fetches historical events for today from Wikipedia."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	hcnews_parse_args "$@"
	if [[ ${#_HCNEWS_REMAINING_ARGS[@]} -gt 0 ]]; then
		echo "Invalid argument: ${_HCNEWS_REMAINING_ARGS[0]}" >&2
		show_help
		exit 1
	fi
	_onthisday_USE_CACHE=$_HCNEWS_USE_CACHE
	_onthisday_FORCE_REFRESH=$_HCNEWS_FORCE_REFRESH
	hc_component_onthisday
fi
