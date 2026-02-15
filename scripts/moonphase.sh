#!/usr/bin/env bash
# =============================================================================
# Moon Phase - Current moon phase display
# =============================================================================
# Source: https://www.invertexto.com/fase-lua-hoje
# Cache TTL: 86400 (24 hours)
# Output: Current moon phase with emoji
# =============================================================================

# -----------------------------------------------------------------------------
# Source Common Library (ALWAYS FIRST)
# -----------------------------------------------------------------------------
[[ -n "${_HCNEWS_COMMON_LOADED:-}" ]] || source "${HCNEWS_COMMON_PATH}common.sh" 2>/dev/null || source "${BASH_SOURCE%/*}/lib/common.sh"

# -----------------------------------------------------------------------------
# Parse Arguments
# -----------------------------------------------------------------------------
hcnews_parse_args "$@"
_moonphase_USE_CACHE=$_HCNEWS_USE_CACHE
_moonphase_FORCE_REFRESH=$_HCNEWS_FORCE_REFRESH

# -----------------------------------------------------------------------------
# Configuration Constants
# -----------------------------------------------------------------------------
CACHE_TTL_SECONDS="${HCNEWS_CACHE_TTL["moonphase"]:-86400}"

# -----------------------------------------------------------------------------
# Data Fetching Function
# -----------------------------------------------------------------------------
get_moonphase_data() {
	local ttl="$CACHE_TTL_SECONDS"
	local date_str
	date_str=$(hcnews_get_date_format)
	local cache_file
	hcnews_set_cache_path cache_file "moonphase" "$date_str"

	# Check cache first
	if [[ "$_moonphase_USE_CACHE" == true ]] && hcnews_check_cache "$cache_file" "$ttl" "$_moonphase_FORCE_REFRESH"; then
		hcnews_read_cache "$cache_file"
		return 0
	fi

	# Fetch moon phase from website
	local fetched_moon_phase
	fetched_moon_phase=$(curl -s "https://www.invertexto.com/fase-lua-hoje" | grep -oP '(?<=<span>).*(?=</span>)')

	# Keep only the text before the first number
	fetched_moon_phase="${fetched_moon_phase%%[0-9]*}"

	local output="🌔 $fetched_moon_phase"

	# Save to cache if enabled
	if [[ "$_moonphase_USE_CACHE" == true && -n "$output" ]]; then
		hcnews_write_cache "$cache_file" "$output"
	fi

	echo "$output"
}

# -----------------------------------------------------------------------------
# Output Function
# -----------------------------------------------------------------------------
write_moon_phase() {
	local data
	data=$(get_moonphase_data)
	[[ -z "$data" ]] && return 1
	echo "$data"
}

# -----------------------------------------------------------------------------
# Help Function
# -----------------------------------------------------------------------------
show_help() {
	echo "Usage: ./moonphase.sh [options]"
	echo "The moon phase will be printed to the console."
	echo ""
	echo "Options:"
	echo "  -h, --help     Show this help message"
	echo "  --no-cache     Bypass cache for this run"
	echo "  --force        Force refresh cached data"
}

# -----------------------------------------------------------------------------
# Main Entry Point
# -----------------------------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	hcnews_parse_args "$@"
	write_moon_phase
fi
