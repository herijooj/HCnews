#!/usr/bin/env bash

# Source common library if not already loaded
[[ -n "${_HCNEWS_COMMON_LOADED:-}" ]] || source "${HCNEWS_COMMON_PATH}common.sh" 2>/dev/null || source "${BASH_SOURCE%/*}/lib/common.sh"

get_didyouknow() {
	local use_cache="${_didyouknow_USE_CACHE:-${_HCNEWS_USE_CACHE:-true}}"
	local force_refresh="${_didyouknow_FORCE_REFRESH:-${_HCNEWS_FORCE_REFRESH:-false}}"
	local date_str
	date_str=$(hcnews_get_date_format)
	local cache_file
	hcnews_set_cache_path cache_file "didyouknow" "$date_str"
	local ttl=${HCNEWS_CACHE_TTL["didyouknow"]:-86400}

	# Cache check
	if [[ "$use_cache" = true ]] && hcnews_check_cache "$cache_file" "$ttl" "$force_refresh"; then
		hcnews_read_cache "$cache_file"
		return 0
	fi

	local URL="https://pt.wikipedia.org/w/api.php?action=query&prop=extracts&explaintext=1&titles=Predefini%C3%A7%C3%A3o:Sabia_que&format=json"

	# Use temporary file
	local tmp_file="/tmp/didyouknow_$$.json"

	# Simple curl with retry
	if curl -s -H "User-Agent: HCnews/1.0 (https://github.com/herijooj/HCnews)" --compressed "$URL" >"$tmp_file"; then

		# Process directly. Extract lines starting with … or ...
		local items
		items=$(jq -r '.query.pages[]?.extract' "$tmp_file" | grep -E '^[….]' | sed 's/^… //;s/^\.\.\. //;s/\\n/ /g' | shuf -n 1)

		# Fallback if empty
		if [[ -z "$items" ]]; then
			rm -f "$tmp_file"
			return 1
		fi
		rm -f "$tmp_file"

		# Clean text
		items=$(echo "$items" | tr -s ' ' | sed 's/^ *//;s/ *$//')
		if type hcnews_decode_html_entities &>/dev/null; then
			items=$(hcnews_decode_html_entities "$items")
		fi

		local output="📚 *Você sabia?*"
		output+=$'\n'
		output+="- ${items}"
		output+=$'\n_Fonte: Wikipedia_'

		if [[ "$use_cache" == true ]]; then
			hcnews_write_cache "$cache_file" "$output"
		fi
		echo "$output"
	else
		rm -f "$tmp_file"
		return 1
	fi
}

hc_component_didyouknow() {
	get_didyouknow
}

# -------------------------------- Running locally --------------------------------

# Standard help
show_help() {
	echo "Usage: ./didyouknow.sh [--no-cache|--force]"
	echo "Fetches a random 'Did You Know' fact from Wikipedia."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	hcnews_parse_args "$@"
	if [[ ${#_HCNEWS_REMAINING_ARGS[@]} -gt 0 ]]; then
		echo "Invalid argument: ${_HCNEWS_REMAINING_ARGS[0]}" >&2
		show_help
		exit 1
	fi
	_didyouknow_USE_CACHE=$_HCNEWS_USE_CACHE
	_didyouknow_FORCE_REFRESH=$_HCNEWS_FORCE_REFRESH
	hc_component_didyouknow
fi
