#!/usr/bin/env bash

# This function returns the exchange rates from the Brazilian Central Bank.
# we use the JSON API from the Brazilian Central Bank
# bc of this, we end up adding jq as a dependency
# https://github.com/stedolan/jq
# https://www.bcb.gov.br/api/servico/sitebcb/indicadorCambio
get_exchange_JSON () {
    local JSON=https://www.bcb.gov.br/api/servico/sitebcb/indicadorCambio

    OUT=$(curl -s $JSON | jq -r '.conteudo[] | "💰 \(.moeda) \(.valorCompra) 🔄 \(.valorVenda) (\(.tipoCotacao))"')
    echo "$OUT"

}

write_exchange () {
    OUT=$(get_exchange_JSON)
    
    echo "📈 Cotação 🪙"
    echo ""
    echo "$OUT"
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