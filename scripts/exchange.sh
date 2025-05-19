#!/usr/bin/env bash

source tokens.sh

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

# Function to get exchange rates from the Brazilian Central Bank
get_exchange_BC() {
  local JSON=https://www.bcb.gov.br/api/servico/sitebcb/indicadorCambio
  local retry_count=0
  local response=""

  # Add retry mechanism
  while [[ $retry_count -lt $MAX_RETRIES ]]; do
    response=$(curl -s -m 10 $JSON)
    
    # Check if we got a valid JSON response
    if echo "$response" | jq -e . > /dev/null 2>&1; then
      # First get output without backticks
      OUT=$(echo "$response" | jq -r '.conteudo[] | select(.tipoCotacao == "Fechamento") | "- *\(.moeda)*: Compra R$ \(.valorCompra | tostring | tonumber | (. * 100 | floor | . / 100)) · Venda R$ \(.valorVenda | tostring | tonumber | (. * 100 | floor | . / 100))"')
      
      # Then add backticks around the numeric values using sed
      OUT=$(echo "$OUT" | sed -E 's/Compra R\$ ([0-9.]+)/Compra R$ `\1`/g; s/Venda R\$ ([0-9.]+)/Venda R$ `\1`/g')
      
      # Verify we have actual data
      if [[ ! -z "$OUT" ]]; then
        echo "$OUT"
        return 0
      fi
    fi
    
    # Retry after delay
    log_message "WARNING" "Failed to fetch BC exchange rates (attempt $((retry_count+1))). Retrying in $RETRY_DELAY seconds..."
    sleep $RETRY_DELAY
    ((retry_count++))
  done
  
  log_message "ERROR" "Failed to fetch BC exchange rates after $MAX_RETRIES attempts."
  echo "  - *Dados não disponíveis no momento. Tente novamente mais tarde.*"
  return 1
}

# Function to fetch cryptocurrency data from CoinMarketCap API
generate_exchange_CMC() {
  local API_KEY=$CoinMarketCap_API_KEY
  local API_URL="https://pro-api.coinmarketcap.com/v1/cryptocurrency/quotes/latest"
  
  echo ""
  echo "💎 *Criptomoedas*"

  # Define groups of currencies
  local crypto_currencies=("BTC:1:Bitcoin" "ETH:1027:Ethereum" "SOL:5426:Solana" "DOGE:74:Dogecoin" "BCH:1831:Bitcoin Cash" "LTC:2:Litecoin" "XMR:328:Monero")
  local precious_metals=("XAU:3575:Ouro" "XAG:3574:Prata")
  
  # Collect all IDs for a batch request
  local crypto_ids=""
  local crypto_map=()
  for crypto in "${crypto_currencies[@]}"; do
    IFS=':' read -r symbol id name <<< "$crypto"
    [[ -n "$crypto_ids" ]] && crypto_ids+=","
    crypto_ids+="$id"
    crypto_map+=("$id:$symbol:$name")
  done
  
  # Make a single batch request for cryptocurrencies
  if ! fetch_and_display_batch "$crypto_ids" "${crypto_map[@]}"; then
    echo "  - *Dados de criptomoedas não disponíveis no momento.*"
  fi
  
  echo ""
  echo "🪙 *Metais Preciosos*"
  
  # Collect all IDs for metals batch request
  local metals_ids=""
  local metals_map=()
  for metal in "${precious_metals[@]}"; do
    IFS=':' read -r symbol id name <<< "$metal"
    [[ -n "$metals_ids" ]] && metals_ids+=","
    metals_ids+="$id"
    metals_map+=("$id:$symbol:$name")
  done
  
  # Make a single batch request for metals
  if ! fetch_and_display_batch "$metals_ids" "${metals_map[@]}"; then
    echo "  - *Dados de metais preciosos não disponíveis no momento.*"
  fi
}

# Function to fetch and process batch data from CoinMarketCap API
fetch_and_display_batch() {
  local ids=$1
  shift
  local currency_map=("$@")
  local API_KEY=$CoinMarketCap_API_KEY
  local API_URL="https://pro-api.coinmarketcap.com/v1/cryptocurrency/quotes/latest"
  local retry_count=0
  local data=""
  local success=false
  
  while [[ $retry_count -lt $MAX_RETRIES ]]; do
    data=$(curl -s -m 15 -G -H "X-CMC_PRO_API_KEY: $API_KEY" -H "Accept: application/json" \
      --data-urlencode "id=$ids" \
      --data-urlencode "convert=BRL" $API_URL)
      
    # Validate the response data
    if echo "$data" | jq -e '.data' > /dev/null 2>&1; then
      # Process each item in the batch response
      for item_info in "${currency_map[@]}"; do
        IFS=':' read -r id symbol name <<< "$item_info"
        
        # Extract data for this specific currency
        if echo "$data" | jq -e ".data[\"$id\"]" > /dev/null 2>&1; then
          local price=$(echo "$data" | jq -r ".data[\"$id\"].quote.BRL.price")
          local change_24h=$(echo "$data" | jq -r ".data[\"$id\"].quote.BRL.percent_change_24h")
          
          # Validate the extracted data
          if [[ "$price" =~ ^[0-9]*\.?[0-9]+$ ]]; then
            # Format the price with K for thousands and two decimal places
            local formatted_price
            if (( $(echo "$price >= 1000" | bc -l) )); then
              formatted_price=$(echo "scale=2; $price / 1000" | bc | awk '{printf "%.2fK", $0}')
            else
              formatted_price=$(echo "scale=2; $price" | bc | awk '{printf "%.2f", $0}')
            fi
            
            # Format the change percentage and add standardized arrow
            local change_symbol="↔️"
            local formatted_change="0.00"
            
            if [[ "$change_24h" =~ ^[+-]?[0-9]*\.?[0-9]+$ ]]; then
              formatted_change=$(echo "scale=2; $change_24h" | bc | awk '{printf "%.2f", $0}')
              
              # Use emojis based on the change value
              if (( $(echo "$change_24h > 0.001" | bc -l) )); then
                change_symbol="⬆️"
              elif (( $(echo "$change_24h < -0.001" | bc -l) )); then
                change_symbol="⬇️"
              else
                change_symbol="↔️"
              fi
            fi
            
            # Align output for better readability
            printf "%s %-5s: R$ %-8s %s %6s%%\n" "-" "$symbol" "\`$formatted_price\`" "$change_symbol" "\`$formatted_change\`"
            success=true
          fi
        fi
      done
      
      [[ "$success" == "true" ]] && return 0
    fi
    
    # Retry after delay
    log_message "WARNING" "Failed to fetch batch data (attempt $((retry_count+1))). Retrying in $RETRY_DELAY seconds..."
    sleep $RETRY_DELAY
    ((retry_count++))
  done
  
  log_message "ERROR" "Failed to fetch batch data after $MAX_RETRIES attempts."
  return 1
}

# Function to verify that required dependencies are installed
check_dependencies() {
  local missing_deps=()
  
  # Check for required tools
  for cmd in curl jq bc awk sed; do
    if ! command -v "$cmd" &> /dev/null; then
      missing_deps+=("$cmd")
    fi
  done
  
  # Check for API key
  if [[ -z "$CoinMarketCap_API_KEY" ]]; then
    log_message "ERROR" "CoinMarketCap API key is missing. Please set it in tokens.sh."
    return 1
  fi
  
  # If there are missing dependencies, report and exit
  if [[ ${#missing_deps[@]} -gt 0 ]]; then
    log_message "ERROR" "Missing required dependencies: ${missing_deps[*]}"
    log_message "INFO" "Please install the missing dependencies and try again."
    return 1
  fi
  
  return 0
}

# Write complete exchange rate information
write_exchange() {
  echo "📈 *Cotação do Dia:*"
  
  # Check dependencies first
  if ! check_dependencies; then
    echo "- *Erro na configuração. Verifique os logs para mais detalhes.*"
    return 1
  fi
  
  # Attempt to get exchange rates
  get_exchange_BC
  generate_exchange_CMC
  
  echo ""
  if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "_(Atualizado em $(date "+%d/%m/%Y às %H:%M"))_"
  fi
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
}

# Process command line arguments
get_arguments() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        show_help
        exit 0
        ;;
      *)
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