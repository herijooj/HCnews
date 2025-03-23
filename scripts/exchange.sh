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
  
  echo ""
  
  # Add retry mechanism
  while [[ $retry_count -lt $MAX_RETRIES ]]; do
    response=$(curl -s -m 10 $JSON)
    
    # Check if we got a valid JSON response
    if echo "$response" | jq -e . > /dev/null 2>&1; then
      # Filter by tipoCotacao=Fechamento and format each currency with proper alignment and decimal places
      OUT=$(echo "$response" | jq -r '.conteudo[] | select(.tipoCotacao == "Fechamento") | "  🔹 *\(.moeda)*: Compra R$ \(.valorCompra | tostring | tonumber | (. * 100 | floor | . / 100)) · Venda R$ \(.valorVenda | tostring | tonumber | (. * 100 | floor | . / 100))"')
      
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
  echo "  🔹 *Dados não disponíveis no momento. Tente novamente mais tarde.*"
  return 1
}

# Function to fetch cryptocurrency data from CoinMarketCap API
generate_exchange_CMC() {
  local API_KEY=$CoinMarketCap_API_KEY
  local API_URL="https://pro-api.coinmarketcap.com/v1/cryptocurrency/quotes/latest"
  local timestamp=$(date "+%d/%m/%Y %H:%M")
  
  echo ""
  echo "💎 *Criptomoedas*"
  echo ""

  # Define groups of currencies
  local crypto_currencies=("BTC:1:Bitcoin" "ETH:1027:Ethereum" "SOL:5426:Solana" "DOGE:74:Dogecoin" "BCH:1831:Bitcoin Cash" "LTC:2:Litecoin" "XMR:328:Monero")
  local precious_metals=("XAU:3575:Ouro" "XAG:3574:Prata")
  
  # Process cryptocurrencies
  local crypto_success=false
  for crypto in "${crypto_currencies[@]}"; do
    IFS=':' read -r symbol id name <<< "$crypto"
    if get_currency_data "$symbol" "$id" "$name" "₿"; then
      crypto_success=true
    fi
  done
  
  # If all crypto data retrieval failed, show an error message
  if [[ "$crypto_success" == "false" ]]; then
    echo "  ₿ *Dados de criptomoedas não disponíveis no momento.*"
  fi
  
  echo ""
  echo "🪙 *Metais Preciosos*"
  echo ""
  
  # Process precious metals
  local metals_success=false
  for metal in "${precious_metals[@]}"; do
    IFS=':' read -r symbol id name <<< "$metal"
    if get_currency_data "$symbol" "$id" "$name" "🔶"; then
      metals_success=true
    fi
  done
  
  # If all precious metals data retrieval failed, show an error message
  if [[ "$metals_success" == "false" ]]; then
    echo "  🔶 *Dados de metais preciosos não disponíveis no momento.*"
  fi
}

# Helper function to get and format currency data
get_currency_data() {
  local symbol=$1
  local id=$2
  local name=$3
  local icon=$4
  local API_KEY=$CoinMarketCap_API_KEY
  local API_URL="https://pro-api.coinmarketcap.com/v1/cryptocurrency/quotes/latest"
  local retry_count=0
  local data=""
  
  while [[ $retry_count -lt $MAX_RETRIES ]]; do
    data=$(curl -s -m 10 -G -H "X-CMC_PRO_API_KEY: $API_KEY" -H "Accept: application/json" \
      --data-urlencode "id=$id" \
      --data-urlencode "convert=BRL" $API_URL)
      
    # Validate the response data
    if echo "$data" | jq -e ".data[\"$id\"].quote.BRL.price" > /dev/null 2>&1; then
      local price=$(echo "$data" | jq -r ".data[\"$id\"].quote.BRL.price")
      local change_24h=$(echo "$data" | jq -r ".data[\"$id\"].quote.BRL.percent_change_24h")
      
      # Further validate the extracted data
      if [[ "$price" =~ ^[0-9]*\.?[0-9]+$ ]]; then
        # Format the price with thousands separator and two decimal places
        local formatted_price=$(echo "scale=2; $price" | bc | awk '{printf "%.2f", $0}' | sed ':a;s/\B[0-9]\{3\}\>/,&/;ta')
        
        # Format the change percentage and add arrow
        local change_symbol="➡️"
        local formatted_change="0.00"
        
        if [[ "$change_24h" =~ ^[+-]?[0-9]*\.?[0-9]+$ ]]; then
          if (( $(echo "$change_24h > 0" | bc -l) )); then
            change_symbol="⬆️"
          elif (( $(echo "$change_24h < 0" | bc -l) )); then
            change_symbol="⬇️"
          fi
          formatted_change=$(echo "scale=2; $change_24h" | bc | awk '{printf "%.2f", $0}')
        fi
        
        echo "  $icon *${symbol}* (${name}): R$ ${formatted_price} ${change_symbol} ${formatted_change}%"
        return 0
      fi
    fi
    
    # Retry after delay
    log_message "WARNING" "Failed to fetch data for $symbol (attempt $((retry_count+1))). Retrying in $RETRY_DELAY seconds..."
    sleep $RETRY_DELAY
    ((retry_count++))
  done
  
  log_message "ERROR" "Failed to fetch data for $symbol after $MAX_RETRIES attempts."
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
  echo "📊 *COTAÇÕES DIÁRIAS* 📊"
  
  # Check dependencies first
  if ! check_dependencies; then
    echo "❌ *Erro na configuração. Verifique os logs para mais detalhes.*"
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
  echo "📋 *Exchange Rate Information Tool*"
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