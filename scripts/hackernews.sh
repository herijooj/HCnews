#!/usr/bin/env bash

# Source common library if not already loaded
[[ -n "${_HCNEWS_COMMON_LOADED:-}" ]] || source "${HCNEWS_COMMON_PATH}common.sh" 2>/dev/null || source "${BASH_SOURCE%/*}/lib/common.sh"

get_hackernews() {
	local use_cache="${_hackernews_USE_CACHE:-${_HCNEWS_USE_CACHE:-true}}"
	local force_refresh="${_hackernews_FORCE_REFRESH:-${_HCNEWS_FORCE_REFRESH:-false}}"
	local date_str
	date_str=$(hcnews_get_date_format)
	local cache_file
	hcnews_set_cache_path cache_file "hackernews" "$date_str"
	local ttl=${HCNEWS_CACHE_TTL["hackernews"]:-1800}
	local hn_count="${HCNEWS_HN_COUNT:-30}"
	local hn_api_url="https://hn.algolia.com/api/v1/search_by_date?tags=story&hitsPerPage=${hn_count}"

	# Cache check
	if [[ "$use_cache" = true ]] && hcnews_check_cache "$cache_file" "$ttl" "$force_refresh"; then
		hcnews_read_cache "$cache_file"
		return 0
	fi

	local response
	response=$(curl -fsS --connect-timeout 4 --max-time 10 --retry 1 "$hn_api_url" 2>/dev/null || true)

	if [[ -z "$response" ]]; then
		if [[ -s "$cache_file" ]]; then
			hcnews_read_cache "$cache_file"
			return 0
		fi
		echo "🧑‍💻 *Hacker News*"
		echo "🚫 Nao foi possivel buscar noticias agora."
		return 0
	fi

	local items
	items=$(jq -r '
	.hits[]?
	| (.title // .story_title // "Sem titulo") as $title
	| (.url // .story_url // ("https://news.ycombinator.com/item?id=" + (.objectID | tostring))) as $url
	| "- \($title)\n    \($url)"
' <<<"$response" 2>/dev/null || true)

	local output="🧑‍💻 *Hacker News*"
	if [[ -n "$items" ]]; then
		output+=$'\n'
		output+="$items"
	else
		output+=$'\n'
		output+="🚫 Nenhuma noticia encontrada."
	fi

	if [[ "$use_cache" == true ]]; then
		hcnews_write_cache "$cache_file" "$output"
	fi
	echo "$output"
}

hc_component_hackernews() {
	get_hackernews
}

# Standard help
show_help() {
	echo "Usage: ./hackernews.sh [--no-cache|--force]"
	echo "Fetches latest stories from Hacker News."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	hcnews_parse_args "$@"
	if [[ ${#_HCNEWS_REMAINING_ARGS[@]} -gt 0 ]]; then
		echo "Invalid argument: ${_HCNEWS_REMAINING_ARGS[0]}" >&2
		show_help
		exit 1
	fi
	_hackernews_USE_CACHE=$_HCNEWS_USE_CACHE
	_hackernews_FORCE_REFRESH=$_HCNEWS_FORCE_REFRESH
	hc_component_hackernews
fi
