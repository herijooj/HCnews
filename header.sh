#!/usr/bin/env bash

# this function returns the date in a pretty format
# example: Segunda-feira, 10 de Abril de 2023
pretty_date () {
    # adds "-feira" if it's not Saturday or Sunday
    if [ $(date +%A) != "Sábado" ] && [ $(date +%A) != "Domingo" ]; then
        DATE=$(date +%A) 
        DATE+="-feira, "
    else
        DATE=$(date +%A)
        DATE+=", "
    fi

    DATE+=$(date +%d)
    DATE+=" de " # add "de"
    DATE+=$(date +%B) # get the month
    DATE+=" de " # add "de"
    DATE+=$(date +%Y) # get the year

    # return the date
    echo $DATE
}

# calculates the HERIPOCH (the HCnews epoch)
# the start of the project was in 07/10/2021
heripoch_date () {

    START_DATE=$(date -d "2021-10-07" +%s)
    CURRENT_DATE=$(date +%s)
    DIFFERENCE=$(($CURRENT_DATE - $START_DATE))
    DAYS_SINCE=$(($DIFFERENCE / 86400))

    # return the number of days since the start of the project
    echo $DAYS_SINCE
}

# this function returns the moon phase from https://www.invertexto.com/fase-lua-hoje
moon_phase () {

    # grep all the lines with <span> and </span>
    MOON_PHASE=$(curl -s https://www.invertexto.com/fase-lua-hoje | grep -oP '(?<=<span>).*(?=</span>)')
    
    MOON_PHASE=$(echo $MOON_PHASE | sed 's/%/% de Visibilidade/')
    MOON_PHASE=$(echo $MOON_PHASE | sed 's/km/km de Distância/')
    MOON_PHASE=$(echo $MOON_PHASE | sed 's/$/ de Idade/')

    # return the moon phase
    echo $MOON_PHASE
}

# this function returns the day quote from "motivate"
day_quote () {

    DAY_QUOTE=$(motivate | sed 's/\[[0-9;]*m//g')

    # return the quote
    echo $DAY_QUOTE
}

# this function is used to write the header of the news file
write_header () {

    FILE_PATH=$1

    DATE=$(pretty_date)
    EDITION=$(heripoch_date)
    DAYS_SINCE=$(date +%j)
    MOON_PHASE=$(moon_phase)
    DAY_QUOTE=$(day_quote)

    # write the header
    echo "📰 HCNews, Edição $EDITION 🗞" > $FILE_PATH
    echo "📌 De Araucária Paraná 🇧🇷" >> $FILE_PATH
    echo "🗺 Notícias do Brasil e do Mundo 🌎" >> $FILE_PATH
    echo "📅 $DATE" >> $FILE_PATH
    echo "⏳ $DAYS_SINCEº dia do ano" >> $FILE_PATH
    echo "🌔 Lua: $MOON_PHASE" >> $FILE_PATH
    echo "" >> $FILE_PATH
    echo "📝 Frase do dia:" >> $FILE_PATH
    echo "$DAY_QUOTE" >> $FILE_PATH
    echo "" >> $FILE_PATH
    
}