#!/usr/bin/env bash
# =============================================================================
# Bicho - Jogo do Bicho daily predictions
# =============================================================================
# Source: https://www.ojogodobicho.com/palpite.htm
# Cache TTL: 86400 (24 hours)
# Output: Daily Jogo do Bicho predictions with animal emojis
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
_bicho_USE_CACHE=$_HCNEWS_USE_CACHE
_bicho_FORCE_REFRESH=$_HCNEWS_FORCE_REFRESH

# -----------------------------------------------------------------------------
# Configuration Constants
# -----------------------------------------------------------------------------
CACHE_TTL_SECONDS="${HCNEWS_CACHE_TTL["bicho"]:-86400}"

# -----------------------------------------------------------------------------
# Lookup Tables
# -----------------------------------------------------------------------------
declare -A BICHO_EMOJIS=(
	["1"]="🦩" ["2"]="🦅" ["3"]="🐴" ["4"]="🦋" ["5"]="🐶" ["6"]="🐐"
	["7"]="🐑" ["8"]="🐫" ["9"]="🐍" ["10"]="🐇" ["11"]="🐎" ["12"]="🐘"
	["13"]="🐓" ["14"]="🐈" ["15"]="🐊" ["16"]="🦁" ["17"]="🐒" ["18"]="🐖"
	["19"]="🦚" ["20"]="🦃" ["21"]="🐂" ["22"]="🐅" ["23"]="🐻" ["24"]="🦌"
	["25"]="🐄"
)

declare -A BICHO_NAMES=(
	["1"]="Avestruz" ["2"]="Águia" ["3"]="Burro" ["4"]="Borboleta" ["5"]="Cachorro" ["6"]="Cabra"
	["7"]="Carneiro" ["8"]="Camelo" ["9"]="Cobra" ["10"]="Coelho" ["11"]="Cavalo" ["12"]="Elefante"
	["13"]="Galo" ["14"]="Gato" ["15"]="Jacaré" ["16"]="Leão" ["17"]="Macaco" ["18"]="Porco"
	["19"]="Pavão" ["20"]="Peru" ["21"]="Touro" ["22"]="Tigre" ["23"]="Urso" ["24"]="Veado"
	["25"]="Vaca"
)

# -----------------------------------------------------------------------------
# Helper Functions
# -----------------------------------------------------------------------------
_number_to_bicho() {
	local number="$1"
	local stripped="${number#0}"
	[[ -z "$stripped" ]] && stripped="100"
	local group
	group=$(((stripped - 1) / 4 + 1))
	echo "${BICHO_EMOJIS[$group]:-🎲} ${stripped} ${BICHO_NAMES[$group]:-}"
}

# -----------------------------------------------------------------------------
# Data Fetching Function
# -----------------------------------------------------------------------------
get_bicho_data() {
	local ttl="$CACHE_TTL_SECONDS"
	local date_str
	date_str=$(hcnews_get_date_format)
	local cache_file
	hcnews_set_cache_path cache_file "bicho" "$date_str"

	# Check cache first
	if [[ "$_bicho_USE_CACHE" == true ]] && hcnews_check_cache "$cache_file" "$ttl" "$_bicho_FORCE_REFRESH"; then
		hcnews_read_cache "$cache_file"
		return 0
	fi

	# Fetch data from website - new structure uses <li> tags inside <ul>
	local raw_data
	raw_data=$(curl -s "https://www.ojogodobicho.com/palpite.htm" |
		pup 'div.content ul.inline-list json{}' |
		jq -r '.[] | .children | map(.text) | join(" ")')

	# Save to cache if enabled
	if [[ "$_bicho_USE_CACHE" == true && -n "$raw_data" ]]; then
		hcnews_write_cache "$cache_file" "$raw_data"
	fi

	echo "$raw_data"
}

# -----------------------------------------------------------------------------
# Output Function
# -----------------------------------------------------------------------------
write_bicho() {
	local raw_data
	raw_data=$(get_bicho_data)
	[[ -z "$raw_data" ]] && return 1

	echo "🎲 *Palpites do Jogo do Bicho:*"

	# Parse each group (space-separated numbers): Grupo, Dezena, Centena, Milhar
	local -a groups=()
	while IFS= read -r group; do
		[[ -n "$group" ]] && groups+=("$group")
	done <<<"$raw_data"

	# Format Grupo (animals) - convert numbers to bicho format
	if [[ -n "${groups[0]}" ]]; then
		local line="- "
		local line_length=2
		local first=true
		for item in ${groups[0]}; do
			[[ -z "$item" ]] && continue
			local formatted
			formatted=$(_number_to_bicho "$item")
			local new_length
			new_length=$((line_length + ${#formatted} + 1))
			if [[ $new_length -gt 38 && $line_length -gt 2 ]]; then
				echo "$line"
				line="- $formatted"
				line_length=$((2 + ${#formatted}))
			else
				if [[ "$first" == "true" ]]; then
					line+="$formatted"
					first=false
				else
					line+=" | $formatted"
				fi
				line_length=$((line_length + ${#formatted} + 3))
			fi
		done
		[[ $line_length -gt 2 ]] && echo "$line"
	fi

	# Format Dezena, Centena, Milhar (just show the numbers)
	if [[ -n "${groups[1]}" ]]; then
		echo "🔟 Dezena: ${groups[1]}"
	fi
	if [[ -n "${groups[2]}" ]]; then
		echo "💯 Centena: ${groups[2]}"
	fi
	if [[ -n "${groups[3]}" ]]; then
		echo "🏆 Milhar: ${groups[3]}"
	fi

	echo ""
	echo ""
}

# -----------------------------------------------------------------------------
# Help Function
# -----------------------------------------------------------------------------
show_help() {
	echo "Usage: ./bicho.sh [options]"
	echo "The Jogo do Bicho predictions will be printed to the console."
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
	write_bicho
fi
