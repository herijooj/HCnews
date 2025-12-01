#!/usr/bin/env bash

# Source tokens.sh if it exists, to load API keys locally.
# In CI/CD, secrets are passed as environment variables.
if [ -f "tokens.sh" ]; then
    source tokens.sh
elif [ -f "$(dirname "${BASH_SOURCE[0]}")/../tokens.sh" ]; then
    source "$(dirname "${BASH_SOURCE[0]}")/../tokens.sh"
fi

# Cache configuration
_exchange_CACHE_DIR="$(dirname "$(dirname "${BASH_SOURCE[0]}")")/data/cache/exchange"
# Ensure the cache directory exists
mkdir -p "$_exchange_CACHE_DIR"
CACHE_TTL_SECONDS=$((4 * 60 * 60)) # 4 hours
# Default cache behavior is enabled
_exchange_USE_CACHE=true
# Force refresh cache
_exchange_FORCE_REFRESH=false

# Override defaults if --no-cache or --force is passed during sourcing
# This allows the main hcnews.sh script to control caching for sourced scripts.
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    _current_sourcing_args_for_exchange=("${@}")
    for arg in "${_current_sourcing_args_for_exchange[@]}"; do
      case "$arg" in
        --no-cache)
          _exchange_USE_CACHE=false
          ;;
        --force)
          _exchange_FORCE_REFRESH=true
          ;;
      esac
    done
fi

# Maximum number of retries for API calls
MAX_RETRIES=3
# Delay between retries in seconds
RETRY_DELAY=2

# Logger function
log_message() {
  local level=$1
  local message=$2
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" >&2
}

# Function to get today's date in YYYYMMDD format
get_date_format() {
  date +"%Y%m%d"
}

# Function to check if cache exists and is from today and within TTL
check_cache() {
  local cache_file_path="$1"
  if [ -f "$cache_file_path" ] && [ "$_exchange_FORCE_REFRESH" = false ]; then
    # Check TTL
    local file_mod_time
    file_mod_time=$(stat -c %Y "$cache_file_path")
    local current_time
    current_time=$(date +%s)
    if (( (current_time - file_mod_time) < CACHE_TTL_SECONDS )); then
      # Cache exists, not forced, and within TTL
      return 0
    fi
  fi
  return 1
}

# Function to read from cache
read_cache() {
  local cache_file_path="$1"
  cat "$cache_file_path"
}

# Function to write to cache
write_cache() {
  local cache_file_path="$1"
  local content="$2"
  
  # Ensure the directory exists
  mkdir -p "$(dirname "$cache_file_path")"
  
  # Write content to cache file
  echo "$content" > "$cache_file_path"
}

# Function to get exchange rates from the Brazilian Central Bank
get_exchange_BC() {
  local JSON_URL="https://www.bcb.gov.br/api/servico/sitebcb/indicadorCambio" # Renamed for clarity
  local retry_count=0
  local response=""
  local out=""

  while [[ $retry_count -lt $MAX_RETRIES ]]; do
    response=$(curl -s -m 10 "$JSON_URL")
    
    # Attempt to process with jq. If successful, $out will be non-empty.
    # jq handles JSON validation implicitly.
    # Formatting (including backticks and two decimal places) is done in jq.
    out=$(echo "$response" | jq -r '
      .conteudo[]
      | select(.tipoCotacao == "Fechamento")
      | "- *\(.moeda)*: Compra `R$ \( ( (.valorCompra * 100 | floor) / 100 ) )` · Venda `R$ \( ( (.valorVenda * 100 | floor) / 100 ) )`"
    ')
      
    if [[ -n "$out" ]]; then
      echo "$out"
      return 0
    fi
    
    log_message "WARNING" "Failed to fetch BC exchange rates (attempt $((retry_count+1))). Retrying in $RETRY_DELAY seconds..."
    sleep "$RETRY_DELAY"
    ((retry_count++))
  done
  
  log_message "ERROR" "Failed to fetch BC exchange rates after $MAX_RETRIES attempts."
  echo "  - *Dados não disponíveis no momento. Tente novamente mais tarde.*"
  return 1
}

# Function to fetch cryptocurrency data from CoinMarketCap API
generate_exchange_CMC() {
  # API_KEY is sourced from tokens.sh, already available
  # API_URL is defined in fetch_and_display_batch

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
  local raw_data="" # Renamed from 'data' to avoid confusion
  local success=false
  
  while [[ $retry_count -lt $MAX_RETRIES ]]; do
    raw_data=$(curl -s -m 15 -G \
      -H "X-CMC_PRO_API_KEY: $CoinMarketCap_API_KEY" \
      -H "Accept: application/json" \
      --data-urlencode "id=$ids" \
      --data-urlencode "convert=BRL" \
      "$API_URL")
      
    # Single jq call to extract ID, price, and change_24h for all relevant items
    # Output format: id\tprice\tchange_24h\n...
    # Using // "null" to handle cases where price or change might be missing for an ID
    local extracted_data
    extracted_data=$(echo "$raw_data" | jq -r '
      if .data then
        .data | to_entries[] |
        select(.value.quote.BRL) | # Ensure BRL quote exists
        "\(.key)\t\(.value.quote.BRL.price // "null")\t\(.value.quote.BRL.percent_change_24h // "null")"
      else
        empty
      end
    ')

    if [[ -n "$extracted_data" ]]; then
      # Process each line from jq output
      while IFS=$'\t' read -r id price change_24h; do
        if [[ "$price" == "null" || "$change_24h" == "null" || -z "$price" || -z "$change_24h" ]]; then
          log_message "WARNING" "Incomplete data for ID $id (Price: $price, Change: $change_24h). Skipping."
          continue
        fi

        # Retrieve symbol and name using the ID from the map
        local symbol_name_pair="${currency_map_ref[$id]}"
        local symbol="${symbol_name_pair%%:*}"
        # local name="${symbol_name_pair#*:}" # Name not used in output, but available

        # Format price (with K for thousands) and change percentage using a single bc call each
        local price_formatting_result
        price_formatting_result=$(echo "
            scale=10; p = $price; is_k = 0;
            if (p >= 1000) { p /= 1000; is_k = 1; }
            scale=2; p_fmt = p / 1;
            print p_fmt, \" \", is_k;
        " | bc -l)
        read -r formatted_price_num is_k_val <<< "$price_formatting_result"
        
        local formatted_price="$formatted_price_num"
        if [[ "$is_k_val" -eq 1 ]]; then
            formatted_price="${formatted_price_num}K"
        fi

        local change_formatting_result
        change_formatting_result=$(echo "
            scale=10; c = $change_24h;
            up = 0; down = 0;
            if (c > 0.001) { up = 1; }
            else if (c < -0.001) { down = 1; }
            scale=2; c_fmt = c / 1;
            print c_fmt, \" \", up, \" \", down;
        " | bc -l)
        read -r formatted_change up_val down_val <<< "$change_formatting_result"

        local change_symbol="↔️"
        if [[ "$up_val" -eq 1 ]]; then change_symbol="⬆️";
        elif [[ "$down_val" -eq 1 ]]; then change_symbol="⬇️"; fi
        
        printf "%s %-5s: R$ %-8s %s %6s%%\n" "-" "$symbol" "\`$formatted_price\`" "$change_symbol" "\`$formatted_change\`"
        success=true
      done
      
      [[ "$success" == "true" ]] && return 0 # If any item was successfully processed
    fi
    
    log_message "WARNING" "Failed to fetch/process batch data (attempt $((retry_count+1))). Raw response: ${raw_data:0:200}..." # Log snippet of raw data
    sleep "$RETRY_DELAY"
    ((retry_count++))
  done
  
  log_message "ERROR" "Failed to fetch batch data after $MAX_RETRIES attempts."
  return 1
}

# Function to verify that required dependencies are installed
check_dependencies() {
  local missing_deps=()
  
  for cmd in curl jq bc; do # awk and sed are no longer direct dependencies of the core logic
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
  local cache_file="${_exchange_CACHE_DIR}/${date_format}.exchange"

  if [ "$_exchange_USE_CACHE" = true ] && check_cache "$cache_file"; then
    read_cache "$cache_file"
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
  # cmc_output=$(generate_exchange_CMC) # This function prints directly, adjust if needed
  # output+="$cmc_output\\n" 

  output+="_Fonte: Banco Central do Brasil · Atualizado: $(date +%H:%M:%S)_\\n"

  if [ "$_exchange_USE_CACHE" = true ]; then
    write_cache "$cache_file" "$(echo -e "$output")"
  fi
  
  # Print output without adding an extra newline
  # Remove trailing backslash and rely on echo -e to handle newlines in $output
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