#!/usr/bin/env bash
# =============================================================================
# HCnews Common Library
# =============================================================================
# This file contains shared functions used across all HCnews scripts.
# Source this file at the beginning of each script to avoid duplication.
# =============================================================================

# Prevent multiple sourcing
[[ -n "${_HCNEWS_COMMON_LOADED:-}" ]] && return 0
_HCNEWS_COMMON_LOADED=1

# =============================================================================
# Global Path Configuration
# =============================================================================

# Compute paths only once - reuse if already set by main script
if [[ -z "${HCNEWS_ROOT:-}" ]]; then
	# Determine root directory relative to this file's location (lib is inside scripts)
	HCNEWS_ROOT="$(dirname "$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")")"
fi
export HCNEWS_ROOT
export HCNEWS_COMMON_PATH="$(dirname "$(realpath "${BASH_SOURCE[0]}")")/"

# =============================================================================
# Load Secrets (fallback if direnv/.envrc not active)
# =============================================================================
[[ -f "${HCNEWS_ROOT}/.secrets" ]] && source "${HCNEWS_ROOT}/.secrets" 2>/dev/null

if [[ -z "${HCNEWS_DATA_DIR:-}" ]]; then
	HCNEWS_DATA_DIR="${HCNEWS_ROOT}/data"
fi
export HCNEWS_DATA_DIR

if [[ -z "${HCNEWS_NEWS_DIR:-}" ]]; then
	HCNEWS_NEWS_DIR="${HCNEWS_DATA_DIR}/news"
fi
export HCNEWS_NEWS_DIR

if [[ -z "${HCNEWS_CACHE_DIR:-}" ]]; then
	HCNEWS_CACHE_DIR="${HCNEWS_DATA_DIR}/cache"
fi
export HCNEWS_CACHE_DIR

if [[ -z "${HCNEWS_SCRIPTS_DIR:-}" ]]; then
	HCNEWS_SCRIPTS_DIR="${HCNEWS_ROOT}/scripts"
fi
export HCNEWS_SCRIPTS_DIR

# =============================================================================
# Heripoch Configuration - Edition numbering starts from this date
# =============================================================================
# Project start date: October 7, 2021 (07/10/2021) at 00:00:00 BRT (UTC-3)
_HERIPOCH_START_TIMESTAMP=1633579200
export _HERIPOCH_START_TIMESTAMP

# =============================================================================
# Centralized Cache TTL Configuration (seconds)
# =============================================================================
# Scripts can use: CACHE_TTL_SECONDS=${HCNEWS_CACHE_TTL["weather"]:-10800}
# Scripts can use: CACHE_TTL_SECONDS=${HCNEWS_CACHE_TTL["weather"]:-10800}
declare -gA HCNEWS_CACHE_TTL=(
	["header"]=86400     # 24 hours
	["weather"]=21600    # 6 hours - matches run schedule
	["exchange"]=43200   # 12 hours - BCB updates once/day
	["saints"]=82800     # 23 hours
	["musicchart"]=43200 # 12 hours
	["sports"]=1800      # 30 minutes - match schedules change fast
	["rss"]=7200         # 2 hours
	["quote"]=86400      # 24 hours
	["moonphase"]=86400  # 24 hours
	["bicho"]=86400      # 24 hours
	["didyouknow"]=86400 # 24 hours
	["futuro"]=86400     # 24 hours
	["ru"]=43200         # 12 hours
	["horoscopo"]=82800  # 23 hours
	["sanepar"]=21600    # 6 hours
	["holidays"]=86400   # 24 hours - changes daily based on date
	["states"]=86400     # 24 hours - changes daily based on date
	["airquality"]=10800 # 3 hours (same as weather)
	["earthquake"]=7200  # 2 hours
	["onthisday"]=86400  # 24 hours
)

# Helper to get script directory with fallback (avoids realpath if possible)
# Usage: local script_dir=$(hcnews_get_script_dir "${BASH_SOURCE[0]}")
hcnews_get_script_dir() {
	local source_file="$1"
	if [[ -n "${HCNEWS_SCRIPTS_DIR:-}" ]]; then
		echo "$HCNEWS_SCRIPTS_DIR"
	else
		# Fallback using dirname of the source file
		dirname "$(realpath "$source_file")"
	fi
}

# Ensure HCNEWS_CACHE_DIR is accessible/writable, otherwise fallback to /tmp
if [[ ! -w "${HCNEWS_CACHE_DIR}" && ! -w "$(dirname "${HCNEWS_CACHE_DIR}")" ]]; then
	HCNEWS_CACHE_DIR="/tmp/hcnews_cache_$(id -u)"
	export HCNEWS_CACHE_DIR
fi

# =============================================================================
# Date Caching - Avoid spawning date subprocess repeatedly
# =============================================================================

# Use pre-cached values from main script if available, otherwise compute once
hcnews_get_date_format() {
	if [[ -n "${date_format:-}" ]]; then
		echo "$date_format"
	elif [[ -n "${_HCNEWS_DATE_FORMAT:-}" ]]; then
		echo "$_HCNEWS_DATE_FORMAT"
	else
		_HCNEWS_DATE_FORMAT=$(date +"%Y%m%d")
		echo "$_HCNEWS_DATE_FORMAT"
	fi
}

hcnews_get_current_time() {
	if [[ -n "${start_time:-}" ]]; then
		echo "$start_time"
	elif [[ -n "${_HCNEWS_CURRENT_TIME:-}" ]]; then
		echo "$_HCNEWS_CURRENT_TIME"
	else
		_HCNEWS_CURRENT_TIME=$(date +%s)
		echo "$_HCNEWS_CURRENT_TIME"
	fi
}

hcnews_get_month() {
	if [[ -n "${month:-}" ]]; then
		echo "$month"
	elif [[ -n "${_HCNEWS_MONTH:-}" ]]; then
		echo "$_HCNEWS_MONTH"
	else
		_HCNEWS_MONTH=$(date +%m)
		echo "$_HCNEWS_MONTH"
	fi
}

hcnews_get_day() {
	if [[ -n "${day:-}" ]]; then
		echo "$day"
	elif [[ -n "${_HCNEWS_DAY:-}" ]]; then
		echo "$_HCNEWS_DAY"
	else
		_HCNEWS_DAY=$(date +%d)
		echo "$_HCNEWS_DAY"
	fi
}

# =============================================================================
# Cache Functions - Unified caching logic
# =============================================================================

# Check if cache file exists, is not forced to refresh, and is within TTL
# Usage: hcnews_check_cache "cache_file_path" "ttl_seconds" "force_refresh_flag"
# Check if cache file exists, is not forced to refresh, and is within TTL
# Usage: hcnews_check_cache "cache_file_path" "ttl_seconds" "force_refresh_flag"
hcnews_check_cache() {
	local cache_file_path="$1"
	local ttl_seconds="${2:-3600}" # Default 1 hour
	local force_refresh="${3:-false}"

	# If global _HCNEWS_USE_CACHE is false, force a "miss" (return 1) unless logic overrides it
	if [[ "${_HCNEWS_USE_CACHE:-true}" == "false" ]]; then
		return 1
	fi

	# Optimization: If cache is already verified by caller (e.g. via batch stat), skip stat
	if [[ "${_HCNEWS_CACHE_VERIFIED:-false}" == "true" ]]; then
		return 0
	fi

	# Use -s to check exists AND non-empty in one test
	if [[ -s "$cache_file_path" ]] && [[ "$force_refresh" != "true" ]]; then
		local file_mod_time
		file_mod_time=$(stat -c %Y "$cache_file_path" 2>/dev/null) || return 1

		local current_time
		current_time=$(hcnews_get_current_time)

		if (((current_time - file_mod_time) < ttl_seconds)); then
			return 0 # Cache is valid
		fi
	fi
	return 1 # Cache is invalid or doesn't exist
}

# Read content from cache file
# Usage: hcnews_read_cache "cache_file_path"
hcnews_read_cache() {
	local cache_file_path="$1"
	if [[ -s "$cache_file_path" ]]; then
		# Use bash built-in $(<file) to avoid spawning cat subprocess
		printf '%s' "$(<"$cache_file_path")"
		return 0
	fi
	return 1
}

# Write content to cache file, creating directory if needed
# Usage: hcnews_write_cache "cache_file_path" "content"
hcnews_write_cache() {
	local cache_file_path="$1"
	local content="$2"
	local cache_dir
	cache_dir="$(dirname "$cache_file_path")"

	# Ensure directory exists
	[[ -d "$cache_dir" ]] || mkdir -p "$cache_dir"

	# Write content
	# Use printf for safer writing of arbitrary strings (vs echo)
	# But if content contains % it might cause issues if not escaped properly in the format string.
	# Safe way: printf '%s' "$content"
	printf '%s' "$content" >"$cache_file_path"
}

# Get the standard cache path for a component and date
# Usage: path=$(hcnews_get_cache_path "component_name" ["date_string"] ["variant"])
hcnews_get_cache_path() {
	local component="$1"
	local date_str="$2"
	local variant="$3"
	local ret_path
	hcnews_set_cache_path ret_path "$component" "$date_str" "$variant"
	echo "$ret_path"
}

# Optimized version: Sets the variable named by the first argument to the path
# Usage: hcnews_set_cache_path var_name "component" ["date_string"] ["variant"]
hcnews_set_cache_path() {
	local -n _ret_var=$1
	local component="$2"
	local date_str="$3"
	local variant="$4"

	# Default date if not provided
	if [[ -z "$date_str" ]]; then
		date_str=$(hcnews_get_date_format)
	fi

	local base_dir="${HCNEWS_CACHE_DIR}/${component}"
	local filename

	# Handle specific exceptions or variants
	case "$component" in
	"header")
		# Legacy/Specific: header usually doesn't have a date in filename in some contexts?
		# Actually header.sh doesn't cache the *output* currently, it caches date calcs which are now in memory.
		# But if we were to cache output:
		filename="${date_str}_header.cache"
		;;
	"ru")
		# Variant is location (e.g., politecnico)
		if [[ -z "$variant" ]]; then variant="politecnico"; fi
		filename="${date_str}_${variant}.ru"
		;;
	"weather")
		# Variant is city (normalized)
		local city_norm="${variant// /_}"
		[[ -z "$city_norm" ]] && city_norm="Curitiba"
		city_norm="${city_norm,,}" # lowercase
		filename="${date_str}_${city_norm}.weather"
		;;
	"rss")
		# RSS uses subfolders for feeds, handled by rss.sh specifically usually.
		# But if centralized: variant could be portal_identifier
		if [[ -n "$variant" ]]; then
			base_dir="${HCNEWS_CACHE_DIR}/rss/rss_feeds/${variant}"
			filename="${date_str}.news"
		else
			# Fallback or base rss logic
			filename="${date_str}_rss.cache"
		fi
		;;
	"horoscopo")
		# Uses news dir? Let's standardize to cache dir.
		# Variant is sign (e.g., aries)
		# If variant is empty, it might be the full list?
		if [[ -n "$variant" ]]; then
			filename="${date_str}_${variant}.hrcp"
		else
			filename="${date_str}.hrcp"
		fi
		;;
	"sanepar")
		filename="${date_str}_sanepar.cache"
		;;
	"moonphase")
		# Legacy might have used 'header' dir? We standardize to 'moonphase' dir.
		filename="${date_str}_moon_phase.cache"
		;;
	"musicchart")
		filename="${date_str}.musicchart"
		;;
	*)
		# Default generic format: YYYYMMDD_component.cache
		if [[ -n "$variant" ]]; then
			filename="${date_str}_${component}_${variant}.cache"
		else
			filename="${date_str}_${component}.cache"
		fi
		;;
	esac

	_ret_var="${base_dir}/${filename}"
}

# =============================================================================
# HTML Entity Decoding - Pure Bash implementation
# =============================================================================

# Decode common HTML entities without spawning subprocesses
# Usage: decoded=$(hcnews_decode_html_entities "$raw_text")
hcnews_decode_html_entities() {
	local input="$1"

	# Use bash parameter expansion for common entities (faster, no subprocess)
	input="${input//&amp;/&}"
	input="${input//&quot;/\"}"
	input="${input//&lt;/<}"
	input="${input//&gt;/>}"
	input="${input//&#0*39;/\'}"
	input="${input//&apos;/\'}"
	input="${input//&nbsp;/ }"
	input="${input//&rsquo;/\'}"
	input="${input//&lsquo;/\'}"
	input="${input//&rdquo;/\"}"
	input="${input//&ldquo;/\"}"
	input="${input//&mdash;/—}"
	input="${input//&ndash;/–}"
	input="${input//&hellip;/…}"
	input="${input//$'\xe2\x80\x8b'/}"

	# Handle numeric hex entities (requires sed for patterns)
	printf '%s' "$input" | sed -e 's/&#x[0-9a-fA-F]\+;//g' -e 's/&#[0-9]\+;//g'
}

# =============================================================================
# Argument Parsing Helpers
# =============================================================================

# Parse common arguments from command line or sourcing
# Handles: --no-cache, --force, -h, --help
# Sets global variables: _HCNEWS_USE_CACHE, _HCNEWS_FORCE_REFRESH
# Remaining arguments are stored in _HCNEWS_REMAINING_ARGS array
# If help is requested, it calls show_help or help function if they exist.
# Usage: hcnews_parse_args "$@"
hcnews_parse_args() {
	# Initialize defaults if not already set by environment
	_HCNEWS_USE_CACHE=${_HCNEWS_USE_CACHE:-true}
	_HCNEWS_FORCE_REFRESH=${_HCNEWS_FORCE_REFRESH:-false}

	# Also check global flags from main script environment (backward compatibility)
	[[ "${hc_no_cache:-}" == "true" ]] && _HCNEWS_USE_CACHE=false
	[[ "${hc_force_refresh:-}" == "true" ]] && _HCNEWS_FORCE_REFRESH=true

	_HCNEWS_REMAINING_ARGS=()

	while [[ $# -gt 0 ]]; do
		case "$1" in
		-h | --help)
			if [[ "${_HCNEWS_ALLOW_HELP:-true}" == "true" ]]; then
				if declare -f show_help >/dev/null; then
					show_help
					exit 0
				elif declare -f help >/dev/null; then
					help
					exit 0
				fi
			fi
			# If no help function found, we just keep it in remaining args if we want,
			# but usually we want to stop if help is requested.
			_HCNEWS_REMAINING_ARGS+=("$1")
			;;
		--no-cache)
			_HCNEWS_USE_CACHE=false
			;;
		--force)
			_HCNEWS_FORCE_REFRESH=true
			;;
		*)
			_HCNEWS_REMAINING_ARGS+=("$1")
			;;
		esac
		shift
	done
}

# =============================================================================
# URL Encoding - Pure Bash (avoids jq subprocess)
# =============================================================================

# URL encode a string without spawning jq
# Usage: encoded=$(hcnews_url_encode "$url")
hcnews_url_encode() {
	local string="$1"
	local strlen=${#string}
	local encoded=""
	local pos c o

	for ((pos = 0; pos < strlen; pos++)); do
		c=${string:$pos:1}
		case "$c" in
		[-_.~a-zA-Z0-9])
			o="$c"
			;;
		*)
			printf -v o '%%%02X' "'$c"
			;;
		esac
		encoded+="$o"
	done
	echo "$encoded"
}

# =============================================================================
# Logging
# =============================================================================

# Log message to stderr with timestamp
# Usage: hcnews_log "LEVEL" "message"
hcnews_log() {
	local level="$1"
	local message="$2"
	echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" >&2
}

# =============================================================================
# Ensure Cache Directories Exist
# =============================================================================

# Create all cache directories upfront (called once from main script)
hcnews_init_cache_dirs() {
	local dirs=("weather" "exchange" "saints" "rss" "bicho" "didyouknow" "futuro" "header" "musicchart" "quote" "ru" "rss/rss_feeds" "rss/url_cache" "airquality" "earthquake" "onthisday" "sports")
	local full_paths=()
	for dir in "${dirs[@]}"; do
		full_paths+=("${HCNEWS_CACHE_DIR}/$dir")
	done
	mkdir -p "${full_paths[@]}"
}
