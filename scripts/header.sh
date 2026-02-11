#!/usr/bin/env bash
# Optimized directory resolution
# shellcheck disable=SC2034
HEADER_DIR="${BASH_SOURCE[0]%/*}"
HEADER_DIR="${BASH_SOURCE[0]%/*}"

# Source common library if not already loaded
[[ -n "${_HCNEWS_COMMON_LOADED:-}" ]] || source "${HCNEWS_COMMON_PATH}common.sh" 2>/dev/null || source "${BASH_SOURCE%/*}/lib/common.sh"

# Returns the current date in a pretty format.
# Usage: pretty_date [weekday] [day] [month] [year]
# If parameters are provided, uses them instead of calling date
# Returns the current date in a pretty format via variable assignment.
# Usage: pretty_date_var <output_var_name> [weekday] [day] [month] [year]
function pretty_date_var {
	local -n ret_var=$1
	local date_arg="$2"
	local day_arg="$3"
	local month_arg="$4"
	local year_arg="$5"

	local pretty_weekday pretty_month

	if [[ -n "$date_arg" && -n "$day_arg" && -n "$month_arg" && -n "$year_arg" ]]; then
		# Use provided cached values
		case $date_arg in
		1) pretty_weekday="Segunda" ;;
		2) pretty_weekday="Terça" ;;
		3) pretty_weekday="Quarta" ;;
		4) pretty_weekday="Quinta" ;;
		5) pretty_weekday="Sexta" ;;
		6) pretty_weekday="Sábado" ;;
		7) pretty_weekday="Domingo" ;;
		esac

		case $month_arg in
		01) pretty_month="janeiro" ;;
		02) pretty_month="fevereiro" ;;
		03) pretty_month="março" ;;
		04) pretty_month="abril" ;;
		05) pretty_month="maio" ;;
		06) pretty_month="junho" ;;
		07) pretty_month="julho" ;;
		08) pretty_month="agosto" ;;
		09) pretty_month="setembro" ;;
		10) pretty_month="outubro" ;;
		11) pretty_month="novembro" ;;
		12) pretty_month="dezembro" ;;
		esac
	else
		# Fallback to date commands if no cached values provided
		pretty_weekday=$(date +%A)
		day_arg=$(date +%d)
		pretty_month=$(date +%B)
		year_arg=$(date +%Y)
	fi

	# Add "-feira" if it's not Saturday or Sunday
	if [[ $pretty_weekday != "Sábado" && $pretty_weekday != "Domingo" ]]; then
		pretty_weekday+="-feira"
	fi

	# Return result via variable
	# shellcheck disable=SC2034
	ret_var="${pretty_weekday}, ${day_arg} de ${pretty_month} de ${year_arg}"
}

# Wrapper for backward compatibility
function pretty_date {
	local res
	pretty_date_var res "$@"
	echo "$res"
}

# Usage: heripoch_date_var <output_var_name> [current_timestamp]
function heripoch_date_var() {
	local -n ret_var_h=$1
	local current_timestamp="$2"

	local current_date
	if [[ -n "$current_timestamp" ]]; then
		current_date="$current_timestamp"
	else
		current_date=$(date +%s)
	fi

	local difference
	difference=$((current_date - _HERIPOCH_START_TIMESTAMP))
	# shellcheck disable=SC2034
	ret_var_h=$((difference / 86400))
}

# Wrapper for backward compatibility
function heripoch_date {
	local res
	heripoch_date_var res "$@"
	echo "$res"
}

# this function is used to write the core header of the news file (without moon phase and quote)
function write_header_core() {
	local date_str edition_str

	# Use cached values if available (passed from main script)
	if [[ -n "$weekday" && -n "$day" && -n "$month" && -n "$year" && -n "$start_time" && -n "$days_since" ]]; then
		pretty_date_var date_str "$weekday" "$day" "$month" "$year"
		heripoch_date_var edition_str "$start_time"
		# Use cached days_since value instead of calculating it
	else
		# Fallback to original behavior
		pretty_date_var date_str
		heripoch_date_var edition_str
		days_since=$(date +%-j)
	fi

	# Calculate the percentage of the year passed
	year_percentage=$((days_since * 100 / 365))

	# Create the progress bar string with Unicode blocks (fixed approach)
	progress_bar_length=16 # Keep same length to avoid breaking lines in WhatsApp
	filled_blocks=$((year_percentage * progress_bar_length / 100))
	empty_blocks=$((progress_bar_length - filled_blocks))

	# Use printf with Unicode characters directly instead of tr
	filled_string=""
	empty_string=""

	# Build filled portion
	for ((i = 0; i < filled_blocks; i++)); do
		filled_string+="█"
	done

	# Build empty portion
	for ((i = 0; i < empty_blocks; i++)); do
		empty_string+="░"
	done

	progress_bar="$filled_string$empty_string"

	# write the core header (without moon phase and quote)
	echo "📰 *HCNews* Edição $edition_str 🗞"
	echo "🇧🇷 De Araucária Paraná "
	echo "📅 $date_str"
	echo "⏳ Dia $days_since/365 $progress_bar ${year_percentage}%"
}

# Legacy function for backward compatibility - now just calls core header
function write_header() {
	write_header_core
}

# -------------------------------- Running locally --------------------------------

# help function
# Usage: ./header.sh [options]
# Options:
#   -h, --help: show the help
show_help() {
	echo "Usage: ./header.sh [options]"
	echo "The core header of the news file will be printed to the console."
	echo "Options:"
	echo "  -h, --help: show the help"
}

# this function will receive the arguments
get_arguments() {
	# Get the arguments
	while [[ $# -gt 0 ]]; do
		case "$1" in
		-h | --help)
			show_help
			exit 0
			;;
		*)
			echo "Invalid argument: $1"
			show_help
			exit 1
			;;
		esac
	done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	# run the script
	get_arguments "$@"
	write_header_core
fi
