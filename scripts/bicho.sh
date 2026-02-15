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
[[ -n "${_HCNEWS_COMMON_LOADED:-}" ]] || source "${HCNEWS_COMMON_PATH}common.sh" 2>/dev/null || source "${BASH_SOURCE%/*}/lib/common.sh"

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

_number_to_bicho_var() {
	local -n out_ref="$1"
	local number="$2"
	local stripped="${number#0}"
	[[ -z "$stripped" ]] && stripped="100"
	local group=$(((stripped - 1) / 4 + 1))
	# shellcheck disable=SC2034
	out_ref="${BICHO_EMOJIS[$group]:-🎲} ${stripped} ${BICHO_NAMES[$group]:-}"
}

_format_bicho_output() {
	local raw_data="$1"
	local output="🎲 *Palpites do Jogo do Bicho:*"

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
			_number_to_bicho_var formatted "$item"
			local new_length=$((line_length + ${#formatted} + 1))
			if [[ $new_length -gt 38 && $line_length -gt 2 ]]; then
				output+=$'\n'
				output+="$line"
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
		if [[ $line_length -gt 2 ]]; then
			output+=$'\n'
			output+="$line"
		fi
	fi

	# Format Dezena, Centena, Milhar (just show the numbers)
	if [[ -n "${groups[1]}" ]]; then
		output+=$'\n'
		output+="🔟 Dezena: ${groups[1]}"
	fi
	if [[ -n "${groups[2]}" ]]; then
		output+=$'\n'
		output+="💯 Centena: ${groups[2]}"
	fi
	if [[ -n "${groups[3]}" ]]; then
		output+=$'\n'
		output+="🏆 Milhar: ${groups[3]}"
	fi

	output+=$'\n\n'
	printf '%s' "$output"
}

# -----------------------------------------------------------------------------
# Data Fetching Function
# -----------------------------------------------------------------------------
get_bicho_data() {
	local ttl="$CACHE_TTL_SECONDS"
	local use_cache="${_bicho_USE_CACHE:-${_HCNEWS_USE_CACHE:-true}}"
	local force_refresh="${_bicho_FORCE_REFRESH:-${_HCNEWS_FORCE_REFRESH:-false}}"
	local date_str
	date_str=$(hcnews_get_date_format)
	local cache_file
	hcnews_set_cache_path cache_file "bicho" "$date_str"

	# Check cache first
	if [[ "$use_cache" == true ]] && hcnews_check_cache "$cache_file" "$ttl" "$force_refresh"; then
		local cached_data
		cached_data=$(hcnews_read_cache "$cache_file")
		# Cache migration path: old format stored raw data only.
		if [[ "$cached_data" == "🎲 *Palpites do Jogo do Bicho:*"* ]]; then
			echo "$cached_data"
		else
			local formatted_cached
			formatted_cached=$(_format_bicho_output "$cached_data")
			[[ -n "$formatted_cached" ]] && hcnews_write_cache "$cache_file" "$formatted_cached"
			echo "$formatted_cached"
		fi
		return 0
	fi

	# Fetch data from website - new structure uses <li> tags inside <ul>
	local raw_data
	raw_data=$(curl -s "https://www.ojogodobicho.com/palpite.htm" |
		pup 'div.content ul.inline-list json{}' |
		jq -r '.[] | .children | map(.text) | join(" ")')

	# Format output once and cache final rendered block
	local formatted_output
	formatted_output=$(_format_bicho_output "$raw_data")
	if [[ "$use_cache" == true && -n "$formatted_output" ]]; then
		hcnews_write_cache "$cache_file" "$formatted_output"
	fi

	echo "$formatted_output"
}

# -----------------------------------------------------------------------------
# Output Function
# -----------------------------------------------------------------------------
hc_component_bicho() {
	local output
	output=$(get_bicho_data)
	[[ -z "$output" ]] && return 1
	echo "$output"
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
	if [[ ${#_HCNEWS_REMAINING_ARGS[@]} -gt 0 ]]; then
		echo "Invalid argument: ${_HCNEWS_REMAINING_ARGS[0]}" >&2
		show_help
		exit 1
	fi
	_bicho_USE_CACHE=$_HCNEWS_USE_CACHE
	_bicho_FORCE_REFRESH=$_HCNEWS_FORCE_REFRESH
	hc_component_bicho
fi
