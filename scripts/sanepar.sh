#!/usr/bin/env bash
# =============================================================================
# Sanepar - Reservoir water levels monitoring
# =============================================================================
# Source: https://site.sanepar.com.br/nivel-dos-reservatorios
# Cache TTL: 21600 (6 hours)
# Output: Sanepar reservoir water levels for Curitiba metropolitan area
# =============================================================================

# -----------------------------------------------------------------------------
# Source Common Library (ALWAYS FIRST)
# -----------------------------------------------------------------------------
[[ -n "${_HCNEWS_COMMON_LOADED:-}" ]] || source "${HCNEWS_COMMON_PATH}common.sh" 2>/dev/null || source "${BASH_SOURCE%/*}/lib/common.sh"

# -----------------------------------------------------------------------------
# Parse Arguments
# -----------------------------------------------------------------------------
hcnews_parse_args "$@"
_sanepar_USE_CACHE=$_HCNEWS_USE_CACHE
_sanepar_FORCE_REFRESH=$_HCNEWS_FORCE_REFRESH

# -----------------------------------------------------------------------------
# Configuration Constants
# -----------------------------------------------------------------------------
CACHE_TTL_SECONDS="${HCNEWS_CACHE_TTL["sanepar"]:-21600}"

# -----------------------------------------------------------------------------
# Data Fetching Function
# -----------------------------------------------------------------------------
get_sanepar_data() {
	local ttl="$CACHE_TTL_SECONDS"
	local date_str
	date_str=$(hcnews_get_date_format)
	local cache_file
	hcnews_set_cache_path cache_file "sanepar" "$date_str"

	# Check cache first
	if [[ "$_sanepar_USE_CACHE" == true ]] && hcnews_check_cache "$cache_file" "$ttl" "$_sanepar_FORCE_REFRESH"; then
		hcnews_read_cache "$cache_file"
		return 0
	fi

	# Fetch dam levels data from Sanepar API
	local api_url="https://site.sanepar.com.br/sites/site.sanepar.com.br/themes/sanepar2012/webservice/nivel_reservatorios.php"
	local content
	content=$(curl -s --max-time 15 --connect-timeout 8 --retry 2 \
		-H "User-Agent: Mozilla/5.0" \
		-H "Accept-Language: pt-BR" \
		"$api_url" 2>/dev/null)

	# Check if we got valid content
	if [[ -z "$content" ]]; then
		local error_output="💧 *Mananciais e nível dos reservatórios*"
		error_output+="\n⚠️ Dados não disponíveis no momento"
		error_output+="\n_Fonte: SANEPAR/INFOHIDRO_"
		echo -e "$error_output"
		return 1
	fi

	# Extract reservoir levels using pup
	local irai_level passauna_level piraquara1_level piraquara2_level total_saic update_time
	irai_level=$(echo "$content" | pup 'div:contains("Barragem Iraí") + div + div.views-field-body p text{}' | head -1)
	passauna_level=$(echo "$content" | pup 'div:contains("Barragem Passaúna") + div + div.views-field-body p text{}' | head -1)
	piraquara1_level=$(echo "$content" | pup 'div:contains("Barragem Piraquara 1") + div + div.views-field-body p text{}' | head -1)
	piraquara2_level=$(echo "$content" | pup 'div:contains("Barragem Piraquara 2") + div + div.views-field-body p text{}' | head -1)
	total_saic=$(echo "$content" | pup 'div:contains("Total SAIC") + div + div.views-field-body p text{}' | head -1)
	update_time=$(echo "$content" | pup '.nivel-reserv-data text{}' | head -1)

	# Fallback extraction using grep if pup doesn't work
	if [[ -z "$irai_level" || -z "$passauna_level" ]]; then
		irai_level=$(echo "$content" | grep -A 3 "Barragem Iraí" | grep -o '[0-9]\+\.[0-9]\+%' | head -1)
		passauna_level=$(echo "$content" | grep -A 3 "Barragem Passaúna" | grep -o '[0-9]\+\.[0-9]\+%' | head -1)
		piraquara1_level=$(echo "$content" | grep -A 3 "Barragem Piraquara 1" | grep -o '[0-9]\+\.[0-9]\+%' | head -1)
		piraquara2_level=$(echo "$content" | grep -A 3 "Barragem Piraquara 2" | grep -o '[0-9]\+\.[0-9]\+%' | head -1)
		total_saic=$(echo "$content" | grep -A 3 "Total SAIC" | grep -o '[0-9]\+\.[0-9]\+%' | head -1)
		update_time=$(echo "$content" | grep -o "Atualizado em: [0-9]\+/[0-9]\+/[0-9]\+ [0-9]\+:[0-9]\+" | sed 's/.*\([0-9]\+:[0-9]\+\)/Atualizado às \1/' | head -1)
	fi

	# Build output
	local output="💧 *Mananciais e nível dos reservatórios*"

	[[ -n "$irai_level" ]] && output+="\n🏔️ Barragem Iraí: \`$irai_level\`"
	[[ -n "$passauna_level" ]] && output+="\n🌊 Barragem Passaúna: \`$passauna_level\`"
	[[ -n "$piraquara1_level" ]] && output+="\n💦 Barragem Piraquara 1: \`$piraquara1_level\`"
	[[ -n "$piraquara2_level" ]] && output+="\n🌿 Barragem Piraquara 2: \`$piraquara2_level\`"
	[[ -n "$total_saic" ]] && output+="\n📊 Total: \`$total_saic\`"

	output+="\n_Fonte: Sanepar/InfoHidro${update_time:+ · $update_time}_"

	# Save to cache if enabled
	if [[ "$_sanepar_USE_CACHE" == true && -n "$output" ]]; then
		hcnews_write_cache "$cache_file" "$output"
	fi

	echo -e "$output"
}

# -----------------------------------------------------------------------------
# Output Function
# -----------------------------------------------------------------------------
write_sanepar() {
	local data
	data=$(get_sanepar_data)
	[[ -z "$data" ]] && return 1
	echo "$data"
	echo ""
}

# -----------------------------------------------------------------------------
# Help Function
# -----------------------------------------------------------------------------
show_help() {
	echo "Usage: ./sanepar.sh [options]"
	echo "Retrieves and displays Sanepar dam levels."
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
	write_sanepar
fi
