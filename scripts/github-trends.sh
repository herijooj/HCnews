#!/usr/bin/env bash

# Shared utilities
_local_dir="${BASH_SOURCE[0]%/*}"
[[ -n "${_HCNEWS_COMMON_LOADED:-}" ]] || source "${HCNEWS_COMMON_PATH:-${_local_dir}/lib/common.sh}" 2>/dev/null || source "${_local_dir}/scripts/lib/common.sh"

# TTL (add your key to HCNEWS_CACHE_TTL in common.sh)
CACHE_TTL_SECONDS="${HCNEWS_CACHE_TTL["github-trends"]:-10800}"

get_block() {
	local LANGUAGE="${1:-}"
	local use_cache="${_githubtrends_USE_CACHE:-${_HCNEWS_USE_CACHE:-true}}"
	local force_refresh="${_githubtrends_FORCE_REFRESH:-${_HCNEWS_FORCE_REFRESH:-false}}"
	local date_str
	date_str=$(hcnews_get_date_format)
	local cache_file
	hcnews_set_cache_path cache_file "github-trends" "$date_str" "$LANGUAGE"

	if [[ "$use_cache" == true ]] &&
		hcnews_check_cache "$cache_file" "$CACHE_TTL_SECONDS" "$force_refresh"; then
		hcnews_read_cache "$cache_file"
		return
	fi

	# Optional: parallel network calls using curl
	local tmp_dir="/dev/shm"
	[[ -d "$tmp_dir" && -w "$tmp_dir" ]] || tmp_dir="/tmp"
	local t1="$tmp_dir/.githubtrends_1_$$"

	# Fetch GitHub trending repos
	local api_url
	api_url="https://api.github.com/search/repositories?q=created:>$(date -d "7 days ago" +%Y-%m-%d)&sort=stars&order=desc&per_page=5"

	if [[ -n "$LANGUAGE" ]]; then
		api_url="https://api.github.com/search/repositories?q=language:$LANGUAGE+created:>$(date -d "7 days ago" +%Y-%m-%d)&sort=stars&order=desc&per_page=5"
	fi

	# Add GitHub token to headers if available to avoid rate limiting
	if [[ -n "$GITHUB_TOKEN" ]]; then
		curl -s -H "Authorization: token $GITHUB_TOKEN" -H "Accept: application/json" --compressed "$api_url" >"$t1"
	else
		curl -s -H "Accept: application/json" --compressed "$api_url" >"$t1"
	fi

	# Parse JSON responses with jq (adjust to your payloads)
	local repo_data
	repo_data=$(cat "$t1")

	# Check if response is valid
	if [[ $(echo "$repo_data" | jq -r 'has("items")' 2>/dev/null) == "false" || -z "$repo_data" ]]; then
		rm -f "$t1"
		local now="${current_time:-$(date +"%H:%M:%S")}"
		local OUTPUT
		printf -v OUTPUT '🐙 *GitHub Trending (Erro):*\n- Falha ao obter dados\n_Fonte: GitHub API · Atualizado: %s_' \
			"$now"

		[[ "$use_cache" == true ]] && hcnews_write_cache "$cache_file" "$OUTPUT"
		echo "$OUTPUT"
		rm -f "$t1"
		return 1
	fi

	# Count the number of items
	local item_count
	item_count=$(echo "$repo_data" | jq -r '.items | length' 2>/dev/null)

	if [[ "$item_count" -eq 0 ]]; then
		rm -f "$t1"
		local now="${current_time:-$(date +"%H:%M:%S")}"
		local OUTPUT
		printf -v OUTPUT '🐙 *GitHub Trending (Última Semana):*\n- Nenhum repositório encontrado\n_Fonte: GitHub API · Atualizado: %s_' \
			"$now"

		[[ "$use_cache" == true ]] && hcnews_write_cache "$cache_file" "$OUTPUT"
		echo "$OUTPUT"
		return 1
	fi

	local now="${current_time:-$(date +"%H:%M:%S")}"
	local OUTPUT

	if [[ -n "$LANGUAGE" ]]; then
		printf -v OUTPUT '🐙 *Trending em %s:*\n' "$LANGUAGE"
	else
		printf -v OUTPUT '🐙 *GitHub Trending (Última Semana):*\n'
	fi

	# Process each repo using a single jq operation
	local repos_formatted
	repos_formatted=$(echo "$repo_data" | jq -r '.items[0:5] | .[] | "\(.name)|\(.owner.login)|\(.description // "N/A")|\(.stargazers_count)|\(.html_url)"' 2>/dev/null)

	# Process each repo - using a temporary array to avoid command execution issues
	local temp_repos=()
	while IFS='|' read -r repo_name owner description stars url; do
		if [[ -n "$repo_name" && "$repo_name" != "null" ]]; then
			temp_repos+=("$repo_name|$owner|$description|$stars|$url")
		fi
	done <<<"$repos_formatted"

	# Now process each repo and build output
	for repo_data in "${temp_repos[@]}"; do
		IFS='|' read -r repo_name owner description stars url <<<"$repo_data"

		# Truncate description if too long
		if [[ ${#description} -gt 60 ]]; then
			description="${description:0:57}..."
		fi

		# Escape special characters in description for safe output
		description="${description//\\/\\\\}"
		description="${description//|/\\|}"
		description="${description//\*/\\*}"
		description="${description//\`/\\\`}"

		# Use printf to append properly to output, using -- to prevent option interpretation
		local repo_line
		# shellcheck disable=SC2016
		printf -v repo_line -- '- [%s](<%s>) por *%s* ⭐ `%s`\n- _«%s»_\n\n' "$repo_name" "$url" "$owner" "$stars" "$description"
		OUTPUT="${OUTPUT}${repo_line}"
	done

	# Use cached time if available, otherwise get current time
	local update_time
	if [[ -n "${current_time:-}" ]]; then
		update_time="$current_time"
	else
		update_time=$(date +"%H:%M:%S")
	fi
	local final_time="$update_time"
	# Properly format the footer with time
	OUTPUT="${OUTPUT}_Fonte: GitHub API · Atualizado: ${final_time}_"

	rm -f "$t1"

	[[ "$use_cache" == true ]] && hcnews_write_cache "$cache_file" "$OUTPUT"
	echo "$OUTPUT"
}

hc_component_github_trends() {
	local LANGUAGE="${1:-}"
	if ! get_block "$LANGUAGE"; then
		return 1
	fi
	echo
}

show_help() {
	echo "Usage: ./github-trends.sh [Language] [--no-cache|--force]"
	echo "Examples:"
	echo "  ./github-trends.sh                    # Show trending repos across all languages"
	echo "  ./github-trends.sh python            # Show trending Python repos"
	echo "  ./github-trends.sh javascript        # Show trending JavaScript repos"
}

parse_args() {
	LANGUAGE_ARG=""

	while [[ $# -gt 0 ]]; do
		case "$1" in
		-h | --help)
			show_help
			exit 0
			;;
		-*)
			echo "Invalid argument: $1" >&2
			show_help
			exit 1
			;;
		*)
			if [[ -z "$LANGUAGE_ARG" ]]; then
				LANGUAGE_ARG="$1"
			else
				echo "Invalid argument: $1" >&2
				show_help
				exit 1
			fi
			;;
		esac
		shift
	done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	hcnews_parse_args "$@"
	_githubtrends_USE_CACHE=$_HCNEWS_USE_CACHE
	_githubtrends_FORCE_REFRESH=$_HCNEWS_FORCE_REFRESH
	set -- "${_HCNEWS_REMAINING_ARGS[@]}"
	parse_args "$@"
	hc_component_github_trends "$LANGUAGE_ARG"
fi
