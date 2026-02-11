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

# Parse cache args
hcnews_parse_args "$@"
_saints_USE_CACHE=$_HCNEWS_USE_CACHE
_saints_FORCE_REFRESH=$_HCNEWS_FORCE_REFRESH

# Function to get today's date in YYYYMMDD format (same as RU script)
get_date_format() {
	hcnews_get_date_format
}

# Get the saint(s) of the day from the Vatican website.
# https://www.vaticannews.va/pt/santo-do-dia/MONTH/DAY.html
# This function prints the name(s) and the description of the saint(s).
get_saints_of_the_day_verbose() {
	local date_format
	date_format=$(get_date_format)
	local cache_file="${_saints_CACHE_DIR}/${date_format}_saints-verbose.txt"

	# Check if we have cached data
	if [ "$_saints_USE_CACHE" = true ] && hcnews_check_cache "$cache_file" "$CACHE_TTL_SECONDS" "$_saints_FORCE_REFRESH"; then
		hcnews_read_cache "$cache_file"
		return 0
	fi

	# Get the current month and day using cached values
	local month_local
	local day_local
	month_local=$(hcnews_get_month)
	day_local=$(hcnews_get_day)

	# Get the URL
	local url="https://www.vaticannews.va/pt/santo-do-dia/$month_local/$day_local.html"

	# Fetch once, parse twice (avoid duplicate API call)
	local html
	html=$(curl -s -4 --compressed --connect-timeout 5 --max-time 10 "$url")

	# Only the names
	local names
	names=$(echo "$html" | pup '.section__head h2 text{}' | sed '/^$/d')

	# Check if we got any names
	if [[ -z "$names" ]]; then
		echo "⚠️ Não foi possível encontrar santos para hoje."
		return 1
	fi

	# The description (from same HTML)
	local description
	description=$(echo "$html" | pup '.section__head h2 text{}, .section__content p text{}' | sed '/^$/d' | sed '1d' | sed '/^[[:space:]]*$/d')

	# Decode HTML entities in the description
	description=$(hcnews_decode_html_entities "$description")

	# Prepare the output to be both displayed and cached
	local output=""

	# Iterate over each name and print the corresponding description.
	local name
	while read -r name; do
		output+="😇 ${name}"$'\n'
		local saint_description
		saint_description=$(echo "$description" | head -n 1)
		output+="- ${saint_description}"$'\n'
		description=$(echo "$description" | tail -n +2)
	done <<<"$names"

	# Write to cache if cache is enabled
	if [ "$_saints_USE_CACHE" = true ]; then
		hcnews_write_cache "$cache_file" "$output"
	fi

	# Output the result
	printf "%s" "$output"
}

# Get the saint(s) of the day from the Vatican website.
# https://www.vaticannews.va/pt/santo-do-dia/MONTH/DAY.html
# This function only prints the name of the saint(s).
get_saints_of_the_day() {
	local date_format
	date_format=$(get_date_format)
	local cache_file="${_saints_CACHE_DIR}/${date_format}_saints-regular.txt"

	# Check if we have cached data
	# Check if we have cached data
	if [ "$_saints_USE_CACHE" = true ]; then
		if hcnews_check_cache "$cache_file" "$CACHE_TTL_SECONDS" "$_saints_FORCE_REFRESH"; then
			hcnews_read_cache "$cache_file"
			return 0
		fi

		# Optimization: Check if verbose cache exists and is valid, use it to generate regular output
		local verbose_cache_file="${_saints_CACHE_DIR}/${date_format}_saints-verbose.txt"
		if hcnews_check_cache "$verbose_cache_file" "$CACHE_TTL_SECONDS" "$_saints_FORCE_REFRESH"; then
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

	# Get the current month and day using cached values
	local month_local
	local day_local
	month_local=$(hcnews_get_month)
	day_local=$(hcnews_get_day)

	# Get the URL
	local url="https://www.vaticannews.va/pt/santo-do-dia/$month_local/$day_local.html"

	# Only the names
	local names
	names=$(curl -s -4 --compressed --connect-timeout 5 --max-time 10 "$url" | pup '.section__head h2 text{}' | sed '/^$/d')

	# Check if we got any names
	if [[ -z "$names" ]]; then
		echo "⚠️ Não foi possível encontrar santos para hoje."
		return 1
	fi

	local output=""
	local name
	while read -r name; do
		output+="- 😇 ${name}"$'\n'
	done <<<"$names"

	# Write to cache if cache is enabled
	if [ "$_saints_USE_CACHE" = true ]; then
		hcnews_write_cache "$cache_file" "$output"
	fi

	# Output the result
	printf "%s" "$output"
}

write_saints() {
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
	write_saints "$saints_verbose"
fi
