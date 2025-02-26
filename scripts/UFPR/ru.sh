#!/usr/bin/env bash
# not implemented yet
# Function to convert menu image URLs to emojis
function menu_to_emoji () {
    URL="$1"

    # Mapping of image URLs to emojis
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
        echo "$URL" # Return the original URL if no match is found
    fi
}

# Function to identify meal times
function is_meal () {
    LINE="$1"

    # Check if the line indicates a meal time
    if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
        if [[ "$LINE" == *"Café da manhã"* ]]; then
            echo "🥪 CAFÉ DA MANHÃ 🥪"
        elif [[ "$LINE" == *"Almoço"* ]]; then
            echo "🍝 ALMOÇO 🍝"
        elif [[ "$LINE" == *"Jantar"* ]]; then
            echo "🍛 JANTAR 🍛"
        else
            echo ""
        fi
    else
        if [[ "$LINE" == *"Café da manhã"* ]]; then
            echo "🥪 *CAFÉ DA MANHÃ* 🥪"
        elif [[ "$LINE" == *"Almoço"* ]]; then
            echo "🍝 *ALMOÇO* 🍝"
        elif [[ "$LINE" == *"Jantar"* ]]; then
            echo "🍛 *JANTAR* 🍛"
        else
            echo ""
        fi
    fi
}

# Function to extract text content within HTML tags
function get_inside_tags () {
    LINE="$1"
    echo "$LINE" | sed 's/<[^>]*>//g' # Remove HTML tags using sed
}

# Define available RU locations
declare -A RU_LOCATIONS=(
    ["politecnico"]="https://pra.ufpr.br/ru/ru-centro-politecnico/"
    ["agrarias"]="https://pra.ufpr.br/ru/cardapio-ru-agrarias/"
    ["botanico"]="https://pra.ufpr.br/ru/cardapio-ru-jardim-botanico/"
    ["central"]="https://pra.ufpr.br/ru/ru-central/"
    ["toledo"]="https://pra.ufpr.br/ru/6751-2/"
    ["mirassol"]="https://pra.ufpr.br/ru/cardapio-ru-mirassol/"
    ["jandaia"]="https://pra.ufpr.br/ru/cardapio-ru-jandaia-do-sul/"
    ["palotina"]="https://pra.ufpr.br/ru/cardapio-ru-palotina/"
    ["cem"]="https://pra.ufpr.br/ru/cardapio-ru-cem/"
    ["matinhos"]="https://pra.ufpr.br/ru/cardapio-ru-matinhos/"
)

# Default location
SELECTED_LOCATION="politecnico"

function list_locations() {
    echo "Available RU locations:"
    for loc in "${!RU_LOCATIONS[@]}"; do
        echo "  - $loc"
    done
}

# Function to retrieve the menu from the website
function get_menu () {
    URL="${RU_LOCATIONS[$SELECTED_LOCATION]}"

    # Fetch the webpage content and extract the relevant section
    CONTENT=$(curl -s "$URL" | pup 'div#conteudo')

    # Check if the content is empty (RU closed or special menu)
    if [[ -z "$CONTENT" ]]; then
        if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
            echo "O RU está fechado ou o cardápio é especial."
        else
            echo "O RU está *fechado* ou o cardápio é *especial*."
        fi
        return
    fi

    # Process the content: remove unnecessary lines, convert images to emojis, and clean up HTML
    MENU=$(echo "$CONTENT" | 
        sed '/<hr>/d' | 
        sed '/class="wp-block-table"/d' |
        sed '/class="has-fixed-layout"/d' |
        sed '/<tbody>/d' |
        sed '/<\/tbody>/d' |
        sed '/<figure>/d' |
        sed '/<\/figure>/d' |
        sed 's/<img[^>]*src="\\([^"]*\\)"[^>]*>/\\n\\1/g' |
        while read -r line; do
          if [[ "$line" == http* ]]; then
            echo "$(menu_to_emoji "$line")"
          else
            echo "$line"
          fi
        done |
        sed 's/<br \/>//g' |
        while read -r line; do
            echo "$(get_inside_tags "$line")"
        done |
        sed '/^$/d')
    
    # delete everthing afer "SENHOR USUÁRIO"
    MENU=$(echo "$MENU" | sed -n '/SENHOR USUÁRIO/q;p')
    # if the line has only ")" it should go to the previous line
    MENU=$(echo "$MENU" | sed ':a;N;$!ba;s/\n)/)/g')
    # add emojis to the start and end of the first line
    MENU=$(echo "$MENU" | sed '1s/^/🍽️  /')
    # Format the menu output
    OUTPUT=""
    PREVIOUS_LINE=""
    while read -r line; do
        if [[ "$(is_meal "$line")" != "" ]]; then
            OUTPUT+=$'\n'"$(is_meal "$line")"$'\n'
        elif [[ "$line" == *"feira"* ]]; then
            OUTPUT+=$'\n'"📅 *$line*"$'\n'
        elif [[ ! -z "$line" ]]; then
            # Check if this line is a continuation of the previous line
            if [[ "$line" == "e "* || "$line" == "("* ]]; then
                OUTPUT="${OUTPUT%$'\n'} $line"$'\n'
            else
                OUTPUT+="- $line"$'\n'
            fi
        fi
        PREVIOUS_LINE="$line"
    done <<< "$MENU"

    echo -e "$OUTPUT"
}

# Function to display the menu
function write_menu () {
    MENU=$(get_menu)

    echo "$MENU"
    echo ""
}

# Help function
help () {
    echo "Usage: $0 [options]"
    echo "Prints the RU menu to the console."
    echo "Options:"
    echo "  -h, --help: show this help message"
    echo "  -l, --list: list available RU locations"
    echo "  -r, --ru LOCATION: select RU location (default: politecnico)"
}

# Argument parsing function
get_arguments () {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                help
                exit 0
                ;;
            -l|--list)
                list_locations
                exit 0
                ;;
            -r|--ru)
                if [ -z "$2" ]; then
                    echo "Error: RU location not specified"
                    exit 1
                fi
                if [[ -v "RU_LOCATIONS[$2]" ]]; then
                    SELECTED_LOCATION="$2"
                else
                    echo "Error: Invalid RU location '$2'"
                    list_locations
                    exit 1
                fi
                shift
                ;;
            *)
                echo "Invalid argument: $1"
                help
                exit 1
                ;;
        esac
        shift
    done
}

# Main script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    get_arguments "$@"
    write_menu
fi