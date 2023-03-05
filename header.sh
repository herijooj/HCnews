#!/usr/bin/env bash

# Returns the current date in a pretty format.
# Usage: pretty_date
# Example output: "Segunda-feira, 10 de Abril de 2023"

function pretty_date {
  local date=$(date +%A)
  local day=$(date +%d)
  local month=$(date +%B)
  local year=$(date +%Y)

  # Add "-feira" if it's not Saturday or Sunday
  if [[ $date != "sábado" && $date != "domingo" ]]; then
    date+="feira"
  fi

  # Return the date in a pretty format
  echo "${date}, ${day} ${month} ${year}"
}

# calculates the HERIPOCH (the HCnews epoch)
# the start of the project was in 07/10/2021
function heripoch_date() {
    local start_date="2021-10-07"
    local current_date=$(date +%s)
    local difference=$((current_date - $(date -d "$start_date" +%s)))
    local days_since=$((difference / 86400))
    echo "$days_since"
}

# this function returns the moon phase from https://www.invertexto.com/fase-lua-hoje
function moon_phase () {

    # grep all the lines with <span> and </span>
    moon_phase=$(curl -s https://www.invertexto.com/fase-lua-hoje | grep -oP '(?<=<span>).*(?=</span>)')
    
    moon_phase=$(echo $moon_phase | sed 's/%/% de Visibilidade/')
    # moon_phase=$(echo $moon_phase | sed 's/km/km de Distância/')
    # moon_phase=$(echo $moon_phase | sed 's/$/ de Idade/')

    # return the moon phase
    echo $moon_phase
}

# this function returns the day quote from "motivate"
function day_quote () {

    day_quote=$(motivate | sed 's/\[[0-9;]*m//g')

    # return the quote
    echo $day_quote
}

# this function is used to write the header of the news file
function write_header () {

    file_path=$1
    file_name=$2

    date=$(pretty_date)
    edition=$(heripoch_date)
    days_since=$(date +%j)
    moon_phase=$(moon_phase)
    day_quote=$(day_quote)

    # write the header
    echo "📰 HCNews, Edição $edition 🗞" > $file_path
    echo "📌 De Araucária Paraná 🇧🇷" >> $file_path
    echo "🗺 Notícias do Brasil e do Mundo 🌎" >> $file_path
    echo "📅 $date" >> $file_path
    echo "⏳ $days_sinceº dia do ano" >> $file_path
    echo "🌔 Lua: $moon_phase" >> $file_path
    echo "" >> $file_path
    echo "📝 Frase do dia:" >> $file_path
    echo "$day_quote" >> $file_path
    echo "" >> $file_path
    
}