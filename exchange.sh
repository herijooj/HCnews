#!/usr/bin/env bash

source tokens.sh
# This function returns the exchange rates from the Brazilian Central Bank.
# we use the JSON API from the Brazilian Central Bank
# bc of this, we end up adding jq as a dependency
# https://github.com/stedolan/jq
# https://www.bcb.gov.br/api/servico/sitebcb/indicadorCambio
get_exchange_BC () {
  local JSON=https://www.bcb.gov.br/api/servico/sitebcb/indicadorCambio

  OUT=$(curl -s $JSON | jq -r '.conteudo[] | "💰 \(.moeda) \(.valorCompra) 🔄 \(.valorVenda) (\(.tipoCotacao))"')
  echo "$OUT"
}

# Function to fetch data from CoinMarketCap API
generate_exchange_CMC() {
  local API_KEY=$CoinMarketCap_API_KEY
  local API_URL="https://pro-api.coinmarketcap.com/v1/cryptocurrency/quotes/latest"

  # Array of precious metal codes and their corresponding CoinMarketCap IDs
  declare -A currencies=(
    [XAU]=3575  # Gold Troy Ounce
    [XAG]=3574  # Silver Troy Ounce
    #[XPT]=3577  # Platinum Ounce
    #[XPD]=3576  # Palladium Ounce
  )

  # Loop through all currencies and fetch their exchange data
  for currency_code in "${!currencies[@]}"; do
    local currency_id="${currencies[$currency_code]}"

    OUT=$(curl -s -G -H "X-CMC_PRO_API_KEY: $API_KEY" -H "Accept: application/json" \
      --data-urlencode "id=$currency_id" \
      --data-urlencode "convert=BRL" $API_URL |
      jq -r --arg code "$currency_code" \
      ".data[] | \"💰 \(.name) (\(.symbol)): R$ \(.quote.BRL.price | tostring | tonumber | (. * 100 | floor | . / 100)) BRL\"")

    echo "$OUT"
  done
}

write_exchange () {
  echo "📈 Cotação 🪙"
  get_exchange_BC
  echo ""
  generate_exchange_CMC
  echo ""
}

# -------------------------------- Running locally --------------------------------

# help function
# Usage: ./exchange.sh [options]
# Options:
#   -h, --help: show the help
show_help() {
  echo "Usage: ./exchange.sh [options]"
  echo "The exchange rates will be printed to the console."
  echo "Options:"
  echo "  -h, --help: show the help"
}

# this function will receive the arguments
get_arguments() {
  # Get the arguments
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

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  get_arguments "$@"
  write_exchange
fi