#!/usr/bin/env bash
# =============================================================================
# Exchange - Currency and cryptocurrency exchange rates
# =============================================================================
# Source: https://www.bcb.gov.br (Brazilian Central Bank)
# Cache TTL: 14400 (4 hours)
# Output: Daily exchange rates for major currencies
# =============================================================================

# -----------------------------------------------------------------------------
# Source Common Library (ALWAYS FIRST after tokens)
# -----------------------------------------------------------------------------
[[ -n "${_HCNEWS_COMMON_LOADED:-}" ]] || source "${HCNEWS_COMMON_PATH:-${BASH_SOURCE%/*}/lib/common.sh}" 2>/dev/null || source "${BASH_SOURCE%/*}/scripts/lib/common.sh"

# -----------------------------------------------------------------------------
# Configuration Constants
# -----------------------------------------------------------------------------
CACHE_TTL_SECONDS="${HCNEWS_CACHE_TTL["exchange"]:-14400}"
MAX_RETRIES=3
RETRY_DELAY=2

# -----------------------------------------------------------------------------
# Helper Functions
# -----------------------------------------------------------------------------
_log_message() {
	local level="$1"
	local message="$2"
	hcnews_log "$level" "$message"
}

# -----------------------------------------------------------------------------
# Data Fetching Function - Brazilian Central Bank
# -----------------------------------------------------------------------------
get_exchange_bc() {
	local json_url="https://www.bcb.gov.br/api/servico/sitebcb/indicadorCambio"
	local retry_count=0
	local response=""
	local out=""

	while [[ $retry_count -lt $MAX_RETRIES ]]; do
		response=$(curl -s -4 --compressed -m 10 "$json_url")

		out=$(echo "$response" | jq -r '
            .conteudo[]
            | select(.tipoCotacao == "Fechamento")
            | "- *\(.moeda)*: Compra `R$ \(.valorCompra | . * 100 | floor | . / 100)` · Venda `R$ \(.valorVenda | . * 100 | floor | . / 100)`"
        ' 2>/dev/null)

		if [[ -n "$out" ]]; then
			echo "$out"
			return 0
		fi

		_log_message "WARNING" "Failed to fetch BC exchange rates (attempt $((retry_count + 1))). Retrying..."
		sleep "$RETRY_DELAY"
		((retry_count++))
	done

	_log_message "ERROR" "Failed to fetch BC exchange rates after $MAX_RETRIES attempts."
	echo "  - *Dados não disponíveis no momento. Tente novamente mais tarde.*"
	return 1
}

# -----------------------------------------------------------------------------
# Data Fetching Function - CoinMarketCap
# -----------------------------------------------------------------------------
fetch_cmc_batch() {
	local ids="$1"
	local -n currency_map_ref="$2"
	local api_url="https://pro-api.coinmarketcap.com/v1/cryptocurrency/quotes/latest"
	local retry_count=0
	local raw_data=""

	while [[ $retry_count -lt $MAX_RETRIES ]]; do
		raw_data=$(curl -s -4 --compressed -m 15 -G \
			-H "X-CMC_PRO_API_KEY: $CoinMarketCap_API_KEY" \
			-H "Accept: application/json" \
			--data-urlencode "id=$ids" \
			--data-urlencode "convert=BRL" \
			"$api_url")

		# Build symbol map as JSON
		local symbol_map_json="{"
		local first=true
		for id in "${!currency_map_ref[@]}"; do
			local symbol="${currency_map_ref[$id]%%:*}"
			[[ "$first" == "true" ]] && first=false || symbol_map_json+=","
			symbol_map_json+="\"$id\":\"$symbol\""
		done
		symbol_map_json+="}"

		local formatted_output
		formatted_output=$(echo "$raw_data" | jq -r --argjson symbols "$symbol_map_json" '
            if .data then
                .data | to_entries[] |
                select(.value.quote.BRL.price != null and .value.quote.BRL.percent_change_24h != null) |
                .key as $id |
                ($symbols[$id] // "???") as $sym |
                .value.quote.BRL.price as $price |
                .value.quote.BRL.percent_change_24h as $change |
                (if $price >= 1000 then
                    (($price / 1000 * 100 | floor) / 100 | tostring) + "K"
                else
                    (($price * 100 | floor) / 100 | tostring)
                end) as $price_fmt |
                (if $change > 0.001 then "⬆️"
                 elif $change < -0.001 then "⬇️"
                 else "↔️" end) as $arrow |
                (($change * 100 | floor) / 100) as $change_fmt |
                "- \($sym | . + "     "[0:(5 - length)]): R$ `\($price_fmt)` \($arrow) `\($change_fmt)`%"
            else
                empty
            end
        ')

		if [[ -n "$formatted_output" ]]; then
			echo "$formatted_output"
			return 0
		fi

		_log_message "WARNING" "Failed to fetch CMC batch data (attempt $((retry_count + 1)))."
		sleep "$RETRY_DELAY"
		((retry_count++))
	done

	_log_message "ERROR" "Failed to fetch CMC batch data after $MAX_RETRIES attempts."
	return 1
}

# -----------------------------------------------------------------------------
# Main Data Fetching Function
# -----------------------------------------------------------------------------
get_exchange_data() {
	local ttl="$CACHE_TTL_SECONDS"
	local use_cache="${_exchange_USE_CACHE:-${_HCNEWS_USE_CACHE:-true}}"
	local force_refresh="${_exchange_FORCE_REFRESH:-${_HCNEWS_FORCE_REFRESH:-false}}"
	local date_str
	date_str=$(hcnews_get_date_format)
	local cache_file
	hcnews_set_cache_path cache_file "exchange" "$date_str"

	# Check cache first
	if [[ "$use_cache" == true ]] && hcnews_check_cache "$cache_file" "$ttl" "$force_refresh"; then
		hcnews_read_cache "$cache_file"
		return 0
	fi

	# Check dependencies
	if ! command -v curl jq &>/dev/null; then
		echo "📈 *Cotação do Dia:*"
		echo "- *Erro: dependências ausentes (curl, jq).*"
		return 1
	fi

	local output="📈 *Cotação do Dia:*"

	# Get BC exchange rates
	local bc_output
	bc_output=$(get_exchange_bc)
	output+=$'\n'"$bc_output"

	# Get cryptocurrency data if API key available
	if [[ -n "${CoinMarketCap_API_KEY:-}" ]]; then
		local crypto_currencies=("BTC:1:Bitcoin" "ETH:1027:Ethereum" "SOL:5426:Solana" "DOGE:74:Dogecoin")
		local crypto_ids=""
		# shellcheck disable=SC2034
		declare -A crypto_map
		for crypto in "${crypto_currencies[@]}"; do
			IFS=':' read -r symbol id name <<<"$crypto"
			[[ -n "$crypto_ids" ]] && crypto_ids+=","
			crypto_ids+="$id"
			crypto_map["$id"]="$symbol:$name"
		done
		: "${crypto_map[@]}"

		local crypto_output
		crypto_output=$(fetch_cmc_batch "$crypto_ids" crypto_map)
		if [[ -n "$crypto_output" ]]; then
			output+=$'\n'$'\n'"💎 *Criptomoedas*"
			output+=$'\n'"$crypto_output"
		fi
	fi

	# Update time
	local update_time="${current_time:-$(date +%H:%M:%S)}"
	output+=$'\n'"_Fonte: Banco Central do Brasil · Atualizado: ${update_time}_"

	# Save to cache if enabled
	if [[ "$use_cache" == true && -n "$output" ]]; then
		hcnews_write_cache "$cache_file" "$output"
	fi

	echo "$output"
}

# -----------------------------------------------------------------------------
# Output Function
# -----------------------------------------------------------------------------
hc_component_exchange() {
	local data
	data=$(get_exchange_data)
	[[ -z "$data" ]] && return 1
	echo "$data"
	echo ""
}

# -----------------------------------------------------------------------------
# Help Function
# -----------------------------------------------------------------------------
show_help() {
	echo "Usage: ./exchange.sh [options]"
	echo "The exchange rates will be formatted and printed to the console."
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
	_exchange_USE_CACHE=$_HCNEWS_USE_CACHE
	_exchange_FORCE_REFRESH=$_HCNEWS_FORCE_REFRESH
	hc_component_exchange
fi
