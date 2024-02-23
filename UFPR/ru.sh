#!/usr/bin/env bash

# not implemented yet
function menu_to_emoji () {
    URL="$1"

    # https://pra.ufpr.br/ru/files/2022/02/Simbolo-vegano.jpg          -> 🌱
    # https://pra.ufpr.br/ru/files/2022/01/Origem-animal-site.png      -> 🐄
    # https://pra.ufpr.br/ru/files/2022/01/Gluten-site.png             -> 🌾
    # https://pra.ufpr.br/ru/files/2022/01/Leite-e-derivados-site.png  -> 🥛
    # https://pra.ufpr.br/ru/files/2022/01/Ovo-site.jpg                -> 🥚
    # https://pra.ufpr.br/ru/files/2022/01/Alergenicos-site.png        -> 🥜
    # https://pra.ufpr.br/ru/files/2022/02/Simbolo-mel-1.jpg           -> 🍯
    # https://pra.ufpr.br/ru/files/2022/02/Simbolo-pimenta.png         -> 🌶️
    if [[ "$URL" == *"Simbolo-vegano.jpg"* ]]; then
        echo "🌱"
    elif [[ "$URL" == *"Origem-animal-site.png"* ]]; then
        echo "🐄"
    elif [[ "$URL" == *"Gluten-site.png"* ]]; then
        echo "🌾"
    elif [[ "$URL" == *"Leite-e-derivados-site.png"* ]]; then
        echo "🥛"
    elif [[ "$URL" == *"Ovo-site.jpg"* ]]; then
        echo "🥚"
    elif [[ "$URL" == *"Alergenicos-site.png"* ]]; then
        echo "🥜"
    elif [[ "$URL" == *"Simbolo-mel-1.jpg"* ]]; then
        echo "🍯"
    elif [[ "$URL" == *"Simbolo-pimenta.png"* ]]; then
        echo "🌶️"
    else
        # dont change the line
        echo "$URL"
    fi
}

# this function checks if the line is a meal
# it will receive an String and return an String
# if the line is a meal, it will return the meal
# if the line is not a meal, it will return nothing
function is_meal () {
    LINE="$1"

    # check if the line is a meal
    # 🥪CAFÉ DA MANHÃ🥪
    # 🍝ALMOÇO🍝
    # 🍛JANTAR🍛
    if [[ "$LINE" == *"CAFÉ DA MANHÃ"* ]]; then
        echo "🥪 CAFÉ DA MANHÃ 🥪"
    elif [[ "$LINE" == *"ALMOÇO"* ]]; then
        echo "🍝 ALMOÇO 🍝"
    elif [[ "$LINE" == *"JANTAR"* ]]; then
        echo "🍛 JANTAR 🍛"
    else
        echo ""
    fi
}

# this function receives a line and returns everthing inside the the tags
# it will receive an String and return an String
function get_inside_tags () {
    LINE="$1"

    # check if the line contains any tag
    if [[ "$LINE" == *"<"* ]]; then
        # get the content inside the tags
        LINE=$(echo "$LINE" | sed 's/<[^>]*>//g')
    fi

    echo "$LINE"
}

# this function returns the menu from https://pra.ufpr.br/ru/ru-centro-politecnico/
function get_menu () {

    # get the menu from the website
    URL="https://pra.ufpr.br/ru/ru-centro-politecnico/"

    # delete all the lines until "<p><strong>" and all the lines after "<p></p>"
    URL=$(curl -s "$URL" | sed -n '/<p><strong>/,$p' | sed -n '/<p><\/p>/q;p')

    # if the URL is empty, the RU is closed or the menu is special
    if [[ "$URL" == "" ]]; then
        echo "O RU está fechado ou o cardápio é especial."
        break
    else
        # only keep the contents inside the tags and break lines after each tag, then delete the empty lines
        URL=$(echo "$URL" | sed 's/<[^>]*>/\n&/g')

        # change the images to emojis
        # URL=$(echo "$URL" | while read -r line; do
        #     echo "$(menu_to_emoji "$line")"
        # done)

        #clean the lines deleting the tags
        URL=$(echo "$URL" | while read -r line; do
            echo "$(get_inside_tags "$line")"
        done)

        # delete the empty lines
        URL=$(echo "$URL" | sed '/^$/d')

        URL=$(echo "$URL" | while read -r line; do
            if [[ "$(is_meal "$line")" != "" ]]; then
                echo ""
                echo "$(is_meal "$line")"
            elif [[ "$line" =~ [0-9] ]]; then
                echo ""
                echo "📅 $line"
            else
                echo "$line"
            fi
        done)

        echo "$URL"
        echo ""
    fi
}

# this function will write the menu to the console
function write_menu () {
    # get the menu
    MENU=$(get_menu)

    echo "🍽️ Cardápio do dia 🍽️"
    echo "$MENU"
    echo ""
}

# -------------------------------- Running locally --------------------------------

# help function
# Usage: ./ferias.sh [options]
# the command will be printed to the console.
# Options:
#   -h, --help: show the help

help () {
    echo "Usage: ./ferias.sh [options]"
    echo "The command will be printed to the console."
    echo "Options:"
    echo "  -h, --help: show the help"
}

# this function will receive the arguments
get_arguments () {
    # Get the arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                help
                exit 0
                ;;
            *)
                echo "Invalid argument: $1"
                help
                exit 1
                ;;
        esac
    done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # run the script
    get_arguments "$@"
    
    write_menu
fi