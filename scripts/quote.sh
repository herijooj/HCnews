#!/usr/bin/env bash
# =============================================================================
# Quote - Daily inspirational quote
# =============================================================================
# Source: https://www.pensador.com/rss.php
# Cache TTL: 86400 (24 hours)
# Output: Daily inspirational quote formatted for Telegram/terminal
# =============================================================================

# -----------------------------------------------------------------------------
# Source Common Library (ALWAYS FIRST)
# -----------------------------------------------------------------------------
# shellcheck source=/dev/null
[[ -n "${_HCNEWS_COMMON_LOADED:-}" ]] || source "${HCNEWS_COMMON_PATH}common.sh" 2>/dev/null || source "${BASH_SOURCE%/*}/lib/common.sh"

# -----------------------------------------------------------------------------
# Parse Arguments
# -----------------------------------------------------------------------------
hcnews_parse_args "$@"
_quote_USE_CACHE=$_HCNEWS_USE_CACHE
_quote_FORCE_REFRESH=$_HCNEWS_FORCE_REFRESH

# -----------------------------------------------------------------------------
# Configuration Constants
# -----------------------------------------------------------------------------
CACHE_TTL_SECONDS="${HCNEWS_CACHE_TTL["quote"]:-86400}"

# -----------------------------------------------------------------------------
# Data Fetching Function
# -----------------------------------------------------------------------------
get_quote_data() {
	local ttl="$CACHE_TTL_SECONDS"
	local date_str
	date_str=$(hcnews_get_date_format)
	local cache_file
	hcnews_set_cache_path cache_file "quote" "$date_str"

	# Check cache first
	if [[ "$_quote_USE_CACHE" == true ]] && hcnews_check_cache "$cache_file" "$ttl" "$_quote_FORCE_REFRESH"; then
		hcnews_read_cache "$cache_file"
		return 0
	fi

	# Fetch quote from RSS feed (Pensador)
	local response
	response=$(curl -s "https://www.pensador.com/rss.php")

	# Extract first item's description (fall back to title)
	local quote
	quote=$(echo "$response" | xmlstarlet sel -t -m "/rss/channel/item[1]" -v "description" 2>/dev/null)
	if [[ -z "$quote" ]]; then
		quote=$(echo "$response" | xmlstarlet sel -t -m "/rss/channel/item[1]" -v "title" 2>/dev/null)
	fi

	# Clean up and decode HTML entities using common library
	# Note: Pensador uses complex entities, so we use perl for full decoding
	local cleaned_quote
	cleaned_quote=$(printf '%s' "$quote" | perl -CS -Mutf8 -pe 's/\x{200B}//g; s/\x{00A0}/ /g; s/&amp;/&/g; s/&lt;/</g; s/&gt;/>/g; s/&quot;/"/g; s/&#0*39;/\x27/g; s/&rsquo;/\x27/g; s/&lsquo;/\x27/g; s/&rdquo;/"/g; s/&ldquo;/"/g; s/&#[0-9]+;//g; s/\s*Frase Minha.*//gi; s/^\s+|\s+$//g; s/\n{2,}/\n\n/g')

	# Build output using printf for better performance
	local output
	printf -v output '📝 *Frase do dia:*\n%s\n\n' "$cleaned_quote"

	# Save to cache if enabled
	if [[ "$_quote_USE_CACHE" == true && -n "$output" ]]; then
		hcnews_write_cache "$cache_file" "$output"
	fi

	printf '%b' "$output"
}

# -----------------------------------------------------------------------------
# Output Function
# -----------------------------------------------------------------------------
write_quote() {
	local data
	data=$(get_quote_data)
	[[ -z "$data" ]] && return 1
	echo "$data"
}

# -----------------------------------------------------------------------------
# Help Function
# -----------------------------------------------------------------------------
show_help() {
	echo "Usage: ./quote.sh [options]"
	echo "The quote of the day will be printed to the console."
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
	write_quote
fi
