#!/usr/bin/env bash

# Return the guess of the jogo do bicho of the day.
# we retrieve the guess from the website https://www.ojogodobicho.com/palpite.htm
function get_bicho_data {
  # Download the webpage and extract the data
  curl -s "https://www.ojogodobicho.com/palpite.htm" |
  pup 'div.content ul.inline-list json{}' |
  jq -r '.[] | .children | map(.text) | join(" ")' |
  awk '
  function number_to_bicho(number) {
    stripped = number
    sub(/^0*/, "", stripped)
    if (stripped == "") stripped = 100
    D = stripped
    group = int((D - 1) / 4 + 1)
    
    animals = "Avestruz 🦃 Águia 🦅 Burro 🐀 Borboleta 🦋 Cachorro 🐶 Cabra 🐐 Carneiro 🐑 Camelo 🐫 Cobra 🐍 Coelho 🐇 Cavalo 🐎 Elefante 🐘 Galo 🐓 Gato 🐈 Jacaré 🐊 Leão 🦁 Macaco 🐒 Porco 🐖 Pavão 🦚 Peru 🦃 Touro 🐂 Tigre 🐅 Urso 🐻 Veado 🦌 Vaca 🐄"
    split(animals, animal_array, " ")
    return animal_array[(group - 1) * 2 + 1] " " animal_array[(group - 1) * 2 + 2]
  }
  BEGIN {
    FS = " "
  }
  {
    if (NR==1) {
      printf "Grupo: "
      for (i = 1; i <= NF; i++) {
        printf "%s (%s) ", $i, number_to_bicho($i)
      }
      printf "\n"
    }
    if (NR==2) print "Dezena: " $0
    if (NR==3) print "Centena: " $0
    if (NR==4) print "Milhar: " $0
  }'
}

function write_bicho {
  local bicho_data=$(get_bicho_data)
  
  echo "🎲 *Palpites do Jogo do Bicho* 🐾"
  echo "$bicho_data" | sed '
    s/Grupo:/🔢 Grupo:/
    s/Dezena:/🔟 Dezena:/
    s/Centena:/💯 Centena:/
    s/Milhar:/🏆 Milhar:/
  '
  echo ""
}

# -------------------------------- Running locally --------------------------------

# help function
# Usage: ./bicho.sh [options]
# Options:
#   -h, --help: show the help
show_help() {
  echo "Usage: ./bicho.sh [options]"
  echo "The guess of the jogo do bicho of the day will be printed to the console."
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
    echo "Invalid argument: $1"
    show_help
    exit 1
    ;;
  esac
  done
}

# Only run the main script if not being sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # run the script
  get_arguments "$@"
  write_bicho
fi
