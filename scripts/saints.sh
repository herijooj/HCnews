#!/usr/bin/env bash

# Source common library if not already loaded
[[ -n "${_HCNEWS_COMMON_LOADED:-}" ]] || source "${HCNEWS_COMMON_PATH}common.sh" 2>/dev/null || source "${BASH_SOURCE%/*}/lib/common.sh"

# Cache configuration - use centralized dir
if [[ -z "${HCNEWS_CACHE_DIR:-}" ]]; then
	HCNEWS_CACHE_DIR="$(dirname "$(dirname "${BASH_SOURCE[0]}")")/data/cache"
fi
_saints_CACHE_DIR="${HCNEWS_CACHE_DIR}/saints"
[[ -d "$_saints_CACHE_DIR" ]] || mkdir -p "$_saints_CACHE_DIR"

# Use centralized TTL
CACHE_TTL_SECONDS="${HCNEWS_CACHE_TTL["saints"]:-82800}"

# Function to get today's date in YYYYMMDD format (same as RU script)
get_date_format() {
	hcnews_get_date_format
}

_saints_get_url() {
	local month_local day_local
	month_local=$(hcnews_get_month)
	day_local=$(hcnews_get_day)
	echo "https://www.vaticannews.va/pt/santo-do-dia/${month_local}/${day_local}.html"
}

_saints_fetch_html() {
	local url="$1"
	curl -s -4 --compressed --connect-timeout 5 --max-time 10 "$url"
}

_saints_extract_names() {
	local html="$1"
	echo "$html" | pup '.section__head h2 text{}' | sed '/^$/d'
}

_saints_extract_descriptions() {
	local html="$1"
	local description
	description=$(echo "$html" | pup '.section__head h2 text{}, .section__content p text{}' | sed '/^$/d' | sed '1d' | sed '/^[[:space:]]*$/d')
	hcnews_decode_html_entities "$description"
}

_saints_format_regular_from_names() {
	local names="$1"
	local output=""
	local name
	while IFS= read -r name; do
		[[ -z "$name" ]] && continue
		output+="- 😇 ${name}"$'\n'
	done <<<"$names"
	printf "%s" "$output"
}

_saints_format_verbose() {
	local names="$1"
	local descriptions="$2"
	local output=""

	local -a names_arr descriptions_arr
	mapfile -t names_arr <<<"$names"
	mapfile -t descriptions_arr <<<"$descriptions"

	local i
	for i in "${!names_arr[@]}"; do
		[[ -z "${names_arr[$i]}" ]] && continue
		output+="😇 ${names_arr[$i]}"$'\n'
		output+="- ${descriptions_arr[$i]:-}"$'\n'
	done

	printf "%s" "$output"
}

# Get the saint(s) of the day from the Vatican website.
# https://www.vaticannews.va/pt/santo-do-dia/MONTH/DAY.html
# This function prints the name(s) and the description of the saint(s).
get_saints_of_the_day_verbose() {
	local use_cache="${_saints_USE_CACHE:-${_HCNEWS_USE_CACHE:-true}}"
	local force_refresh="${_saints_FORCE_REFRESH:-${_HCNEWS_FORCE_REFRESH:-false}}"
	local date_format
	date_format=$(get_date_format)
	local cache_file="${_saints_CACHE_DIR}/${date_format}_saints-verbose.txt"

	# Check if we have cached data
	if [[ "$use_cache" == true ]] && hcnews_check_cache "$cache_file" "$CACHE_TTL_SECONDS" "$force_refresh"; then
		hcnews_read_cache "$cache_file"
		return 0
	fi

	# Fetch once, parse twice (avoid duplicate API call)
	local url html names
	url=$(_saints_get_url)
	html=$(_saints_fetch_html "$url")
	names=$(_saints_extract_names "$html")

	# Check if we got any names
	if [[ -z "$names" ]]; then
		echo "⚠️ Não foi possível encontrar santos para hoje."
		return 1
	fi

	local descriptions output
	descriptions=$(_saints_extract_descriptions "$html")
	output=$(_saints_format_verbose "$names" "$descriptions")

	# Write to cache if cache is enabled
	if [[ "$use_cache" == true ]]; then
		hcnews_write_cache "$cache_file" "$output"
	fi

	# Output the result
	printf "%s" "$output"
}

# Get the saint(s) of the day from the Vatican website.
# https://www.vaticannews.va/pt/santo-do-dia/MONTH/DAY.html
# This function only prints the name of the saint(s).
get_saints_of_the_day() {
	local use_cache="${_saints_USE_CACHE:-${_HCNEWS_USE_CACHE:-true}}"
	local force_refresh="${_saints_FORCE_REFRESH:-${_HCNEWS_FORCE_REFRESH:-false}}"
	local date_format
	date_format=$(get_date_format)
	local cache_file="${_saints_CACHE_DIR}/${date_format}_saints-regular.txt"

	# Check if we have cached data
	if [[ "$use_cache" == true ]]; then
		if hcnews_check_cache "$cache_file" "$CACHE_TTL_SECONDS" "$force_refresh"; then
			hcnews_read_cache "$cache_file"
			return 0
		fi

		# Optimization: Check if verbose cache exists and is valid, use it to generate regular output
		local verbose_cache_file="${_saints_CACHE_DIR}/${date_format}_saints-verbose.txt"
		if hcnews_check_cache "$verbose_cache_file" "$CACHE_TTL_SECONDS" "$force_refresh"; then
			# Extract names from verbose cache (lines starting with 😇)
			local from_verbose
			from_verbose=$(hcnews_read_cache "$verbose_cache_file" | grep "^😇" | sed -E 's/^😇 ?/- 😇 /')

			if [[ -n "$from_verbose" ]]; then
				# Write to regular cache for future fast access
				hcnews_write_cache "$cache_file" "$from_verbose"
				echo "$from_verbose"
				return 0
			fi
		fi
	fi

	local url html names
	url=$(_saints_get_url)
	html=$(_saints_fetch_html "$url")
	names=$(_saints_extract_names "$html")

	# Check if we got any names
	if [[ -z "$names" ]]; then
		echo "⚠️ Não foi possível encontrar santos para hoje."
		return 1
	fi

	local output
	output=$(_saints_format_regular_from_names "$names")

	# Write to cache if cache is enabled
	if [[ "$use_cache" == true ]]; then
		hcnews_write_cache "$cache_file" "$output"
	fi

	# Output the result
	printf "%s" "$output"
}

hc_component_saints() {
	local saints_verbose=$1

	echo "🙏 *Santos do dia*:"
	if [[ "$saints_verbose" == "true" ]]; then
		get_saints_of_the_day_verbose
	else
		get_saints_of_the_day
	fi
	echo ""
}

# -------------------------------- Running locally --------------------------------

# help function
# Usage: ./saints.sh [options]
# Options:
#   -h, --help: show the help
#   -v, --verbose: show the verbose description of the saints
#   -n, --no-cache: do not use cached data
#   -f, --force: force refresh cache
show_help() {
	echo "Usage: ./saints.sh [options]"
	echo "Options:"
	echo "  -h, --help: show the help"
	echo "  -v, --verbose: show the verbose description of the saints"
	echo "  -n, --no-cache: do not use cached data"
	echo "  -f, --force: force refresh cache"
}

# this function will receive the arguments
get_arguments() {
	# Define variables
	saints_verbose=false

	# Use unified argument parser
	hcnews_parse_args "$@"

	# Process remaining arguments
	set -- "${_HCNEWS_REMAINING_ARGS[@]}"
	while [[ $# -gt 0 ]]; do
		case "$1" in
		-v | --verbose)
			saints_verbose=true
			;;
		*)
			echo "Invalid argument: $1"
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
	_saints_USE_CACHE=${_HCNEWS_USE_CACHE:-true}
	_saints_FORCE_REFRESH=${_HCNEWS_FORCE_REFRESH:-false}
	hc_component_saints "$saints_verbose"
fi
