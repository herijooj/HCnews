#!/usr/bin/env bash

# this function returns the date in a pretty format
# example: Segunda-feira, 10 de Abril de 2023
pretty_date () {
    # adds "-feira" if it's not Saturday or Sunday
    if [ $(date +%A) != "Sábado" ] && [ $(date +%A) != "Domingo" ]; then
        date=$(date +%A) 
        date+="-feira, "
    else
        date=$(date +%A)
        date+=", "
    fi

    date+=$(date +%d)
    date+=" de " # add "de"
    date+=$(date +%B) # get the month
    date+=" de " # add "de"
    date+=$(date +%Y) # get the year

    # return the date
    echo $date
}

# calculates the HERIPOCH (the HCnews epoch)
# the HCnews epoch is the number of days since the start of the project
# the start of the project was in 07/10/2021
heripoch_date () {

    start_date=$(date -d "2021-10-07" +%s)
    current_date=$(date +%s)
    difference=$(($current_date - $start_date))
    days_since=$(($difference / 86400))

    # return the number of days since the start of the project
    echo $days_since
}

# this function returns the moon phase from https://www.invertexto.com/fase-lua-hoje
moon_phase () {

    # grep all the lines with <span> and </span>
    moon_phase=$(curl -s https://www.invertexto.com/fase-lua-hoje | grep -oP '(?<=<span>).*(?=</span>)')
    
    moon_phase=$(echo $moon_phase | sed 's/%/% de Visibilidade/')
    moon_phase=$(echo $moon_phase | sed 's/km/km de Distância/')
    moon_phase=$(echo $moon_phase | sed 's/$/ de Idade/')

    # return the moon phase
    echo $moon_phase
}

# this function returns the day quote from frasedodia.net
day_quote () {

    # the quote is inside the first "body:"
    day_quote=$(curl -s https://frasedodia.net/ | grep -oP '(?<=body: ").*(?=")')

    echo $day_quote
}

# this function is used to write the header of the news file
write_header () {

    file_path=$1

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
    
}