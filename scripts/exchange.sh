#!/usr/bin/env bash

# Source tokens.sh if it exists, to load API keys locally.
# In CI/CD, secrets are passed as environment variables.
if [ -f "tokens.sh" ]; then
    source tokens.sh
elif [ -f "$(dirname "${BASH_SOURCE[0]}")/../tokens.sh" ]; then
    source "$(dirname "${BASH_SOURCE[0]}")/../tokens.sh"
fi

# Source common library if not already loaded
if [[ -z "$(type -t hcnews_log)" ]]; then
    _local_script_dir=$(dirname "$(realpath "${BASH_SOURCE[0]}")")
    source "$_local_script_dir/lib/common.sh"
fi

# Cache configuration - use centralized dir
if [[ -z "${HCNEWS_CACHE_DIR:-}" ]]; then
    HCNEWS_CACHE_DIR="$(dirname "$(dirname "${BASH_SOURCE[0]}")")/data/cache"
fi
# Cache configuration - handled by common.sh

# Use centralized TTL
CACHE_TTL_SECONDS="${HCNEWS_CACHE_TTL["exchange"]:-14400}"

# Parse cache args
hcnews_parse_cache_args "$@"
_exchange_USE_CACHE=$_HCNEWS_USE_CACHE
_exchange_FORCE_REFRESH=$_HCNEWS_FORCE_REFRESH

# Maximum number of retries for API calls
MAX_RETRIES=3
# Delay between retries in seconds
RETRY_DELAY=2

# Use centralized logger
log_message() {
  hcnews_log "$1" "$2"
}

# Function to get today's date in YYYYMMDD format
get_date_format() {
  hcnews_get_date_format
}

# Function to get exchange rates from the Brazilian Central Bank
get_exchange_BC() {
  local JSON_URL="https://www.bcb.gov.br/api/servico/sitebcb/indicadorCambio"
  local retry_count=0
  local response=""
  local out=""

  while [[ $retry_count -lt $MAX_RETRIES ]]; do
    response=$(curl -s -4 --compressed -m 10 "$JSON_URL")
    
    out=$(echo "$response" | jq -r '
      .conteudo[]
      | select(.tipoCotacao == "Fechamento")
      | "- *\(.moeda)*: Compra `R$ \(.valorCompra | . * 100 | floor | . / 100)` · Venda `R$ \(.valorVenda | . * 100 | floor | . / 100)`"
    ' 2>/dev/null)
      
    if [[ -n "$out" ]]; then
      echo "$out"
      return 0
    fi
    
    log_message "WARNING" "Failed to fetch BC exchange rates (attempt $((retry_count+1))). Retrying..."
    sleep "$RETRY_DELAY"
    ((retry_count++))
  done
  
  log_message "ERROR" "Failed to fetch BC exchange rates after $MAX_RETRIES attempts."
  echo "  - *Dados não disponíveis no momento. Tente novamente mais tarde.*"
  return 1
}

# Function to fetch cryptocurrency data from CoinMarketCap API
generate_exchange_CMC() {
  echo ""
  echo "💎 *Criptomoedas*"

  local crypto_currencies=("BTC:1:Bitcoin" "ETH:1027:Ethereum" "SOL:5426:Solana" "DOGE:74:Dogecoin" "BCH:1831:Bitcoin Cash" "LTC:2:Litecoin" "XMR:328:Monero")
  local precious_metals=("XAU:3575:Ouro" "XAG:3574:Prata") # CMC uses ticker symbols like PAXG for Gold, not XAU directly for API IDs.
                                                          # Assuming current IDs 3575, 3574 are placeholders or specific CMC IDs for tokenized versions.
                                                          # For actual spot price, you'd use a different API or different CMC IDs if they exist.
                                                          # E.g., PAX Gold (PAXG) ID: 4705, Silver (SLV etf often used as proxy or specific silver tokens)

  # Collect all IDs for a batch request for cryptocurrencies
  local crypto_ids=""
  declare -A crypto_map_id_to_info # Use associative array for efficient lookup
  for crypto in "${crypto_currencies[@]}"; do
    IFS=':' read -r symbol id name <<< "$crypto"
    [[ -n "$crypto_ids" ]] && crypto_ids+=","
    crypto_ids+="$id"
    crypto_map_id_to_info["$id"]="$symbol:$name"
  done
  
  if ! fetch_and_display_batch "$crypto_ids" crypto_map_id_to_info; then
    echo "  - *Dados de criptomoedas não disponíveis no momento.*"
  fi
  
  echo ""
  echo "🪙 *Metais Preciosos*"
  
  local metals_ids=""
  declare -A metals_map_id_to_info
  for metal in "${precious_metals[@]}"; do
    IFS=':' read -r symbol id name <<< "$metal"
    [[ -n "$metals_ids" ]] && metals_ids+=","
    metals_ids+="$id"
    metals_map_id_to_info["$id"]="$symbol:$name"
  done
  
  if ! fetch_and_display_batch "$metals_ids" metals_map_id_to_info; then
    echo "  - *Dados de metais preciosos não disponíveis no momento.*"
  fi
}

# Function to fetch and process batch data from CoinMarketCap API
fetch_and_display_batch() {
  local ids="$1"
  local -n currency_map_ref="$2" # Pass associative array by reference (Bash 4.3+)
  
  local API_URL="https://pro-api.coinmarketcap.com/v1/cryptocurrency/quotes/latest"
  local retry_count=0
  local raw_data=""
  
  while [[ $retry_count -lt $MAX_RETRIES ]]; do
    raw_data=$(curl -s -4 --compressed -m 15 -G \
      -H "X-CMC_PRO_API_KEY: $CoinMarketCap_API_KEY" \
      -H "Accept: application/json" \
      --data-urlencode "id=$ids" \
      --data-urlencode "convert=BRL" \
      "$API_URL")
    
    # Build symbol map as JSON for jq (id -> symbol)
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
        
        # Format price: divide by 1000 if >= 1000, add K suffix
        (if $price >= 1000 then
          (($price / 1000 * 100 | floor) / 100 | tostring) + "K"
        else
          (($price * 100 | floor) / 100 | tostring)
        end) as $price_fmt |
        
        # Format change with arrow
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
    
    log_message "WARNING" "Failed to fetch/process batch data (attempt $((retry_count+1)))."
    sleep "$RETRY_DELAY"
    ((retry_count++))
  done
  
  log_message "ERROR" "Failed to fetch batch data after $MAX_RETRIES attempts."
  return 1
}

# Function to verify that required dependencies are installed
check_dependencies() {
  local missing_deps=()
  
  for cmd in curl jq; do # bc no longer needed - all math done in jq
    if ! command -v "$cmd" &> /dev/null; then
      missing_deps+=("$cmd")
    fi
  done
  
  if [[ -z "$CoinMarketCap_API_KEY" ]]; then
    log_message "ERROR" "CoinMarketCap API key is missing. Please set it in environment or tokens.sh."
    # No need to add to missing_deps, just return error
    return 1
  fi
  
  if [[ ${#missing_deps[@]} -gt 0 ]]; then
    log_message "ERROR" "Missing required dependencies: ${missing_deps[*]}"
    log_message "INFO" "Please install them and try again."
    return 1
  fi
  
  return 0
}

# Write complete exchange rate information
write_exchange() {
  local date_format
  date_format=$(get_date_format)
  local cache_file
  cache_file=$(hcnews_get_cache_path "exchange" "$date_format")

  if [ "${_HCNEWS_USE_CACHE:-true}" = true ] && hcnews_check_cache "$cache_file" "$CACHE_TTL_SECONDS" "${_HCNEWS_FORCE_REFRESH:-false}"; then
    hcnews_read_cache "$cache_file"
    return
  fi

  local output=""
  output+="📈 *Cotação do Dia:*\\n"
  
  if ! check_dependencies; then
    output+="- *Erro na configuração ou dependências ausentes. Verifique os logs.*"
    echo -e "$output"
    return 1
  fi
  
  # Capture BC output
  bc_output=$(get_exchange_BC)
  output+="$bc_output\\n"
  
  # Capture CMC output (if you re-enable it)
  # cmc_output=$(generate_exchange_CMC)
  # output+="$cmc_output\\n" 

  # Use cached current_time if available (format: HH:MM:SS), otherwise fall back to date
  local update_time
  if [[ -n "$current_time" ]]; then
    update_time="$current_time"
  else
    update_time=$(date +%H:%M:%S)
  fi
  output+="_Fonte: Banco Central do Brasil · Atualizado: ${update_time}_\\n"

  if [ "${_HCNEWS_USE_CACHE:-true}" = true ]; then
    hcnews_write_cache "$cache_file" "$(echo -e "$output")"
  fi
  
  output="${output%\\}"
  echo -e "$output"
}

# Help function
show_help() {
  echo "- *Exchange Rate Information Tool*"
  echo ""
  echo "Usage: ./exchange.sh [options]"
  echo "The exchange rates will be formatted and printed to the console."
  echo ""
  echo "Options:"
  echo "  -h, --help: Show this help message"
  echo "  -n, --no-cache: Do not use cached data"
  echo "  -f, --force: Force refresh cache"
}

# Process command line arguments
get_arguments() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        show_help
        exit 0
        ;;
      -n|--no-cache)
        _exchange_USE_CACHE=false
        shift
        ;;
      -f|--force)
        _exchange_FORCE_REFRESH=true
        shift
        ;;
      *)
        log_message "ERROR" "Unknown option: $1"
        show_help
        exit 1
        ;;
    esac
    shift
  done
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  get_arguments "$@"
  write_exchange
fi