#!/usr/bin/env bash
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
            echo "🥪 *CAFÉ DA MANHÃ* 🥪"
        elif [[ "$LINE" == *"Almoço"* ]]; then
            echo "🍝 *ALMOÇO* 🍝"
        elif [[ "$LINE" == *"Jantar"* ]]; then
            echo "🍛 *JANTAR* 🍛"
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
# Default is to show the full menu, allow override from sourcing script
SHOW_ONLY_TODAY=${SHOW_ONLY_TODAY:-false}
# Default cache behavior is enabled
_ru_USE_CACHE=true
# Force refresh cache
_ru_FORCE_REFRESH=false

# Override defaults if --no-cache or --force is passed during sourcing
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then # Check if sourced
    _current_sourcing_args_for_ru=("${@}") 
    for arg in "${_current_sourcing_args_for_ru[@]}"; do
      case "$arg" in
        --no-cache)
          _ru_USE_CACHE=false
          ;;
        --force)
          _ru_FORCE_REFRESH=true
          ;;
      esac
    done
fi

# Cache directory path
_ru_CACHE_DIR="$(dirname "$(dirname "$(dirname "$0")")")/data/news"

function list_locations() {
    echo "Available RU locations:"
    for loc in "${!RU_LOCATIONS[@]}"; do
        echo "  - $loc"
    done
}

# Function to get today's day of the week in Portuguese
function get_today_weekday() {
    # Get day of week (0-6, Sunday is 0)
    local DOW=$(date +%w)
    
    case "$DOW" in
        0) echo "Domingo" ;;
        1) echo "Segunda-feira" ;;
        2) echo "Terça-feira" ;;
        3) echo "Quarta-feira" ;;
        4) echo "Quinta-feira" ;;
        5) echo "Sexta-feira" ;;
        6) echo "Sábado" ;;
    esac
}

# Function to get date in YYYYMMDD format
function get_date_format() {
    date +"%Y%m%d"
}

# Function to check if cache exists and is from today
function check_cache() {
    local location="$1"
    local date_format=$(get_date_format)
    local cache_file="${_ru_CACHE_DIR}/${date_format}_${location}.ru"
    
    if [ -f "$cache_file" ] && [ "$_ru_FORCE_REFRESH" = false ]; then
        # Cache exists and force refresh is not enabled
        return 0
    else
        return 1
    fi
}

# Function to read menu from cache
function read_cache() {
    local location="$1"
    local date_format=$(get_date_format)
    local cache_file="${_ru_CACHE_DIR}/${date_format}_${location}.ru"
    
    cat "$cache_file"
}

# Function to write menu to cache
function write_cache() {
    local location="$1"
    local menu="$2"
    local date_format=$(get_date_format)
    local cache_file="${_ru_CACHE_DIR}/${date_format}_${location}.ru"
    
    # Ensure the directory exists
    mkdir -p "$(dirname "$cache_file")"
    
    # Write menu to cache file
    echo "$menu" > "$cache_file"
}

# Function to retrieve the menu from the website
function get_menu () {
    # If cache is enabled and exists, use it
    if [ "$_ru_USE_CACHE" = true ] && check_cache "$SELECTED_LOCATION"; then
        read_cache "$SELECTED_LOCATION"
        return
    fi

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
        sed '/<style>/,/<\/style>/d' |  # Remove style tags and their content 
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
        elif [[ "$line" =~ (Segunda|Terça|Quarta|Quinta|Sexta|Sábado|Domingo)[-]?[Ff]eira ]]; then
            # Extract the day name (everything before the first digit)
            DAY_NAME=$(echo "$line" | sed -E 's/^([^0-9]+)[0-9].*/\1/' | xargs)
            # Extract the date (everything from the first digit onwards)
            DATE=$(echo "$line" | sed -E 's/^[^0-9]+([0-9].+)/\1/' | xargs)
            # Use just one newline before each date
            OUTPUT+=$'\n'"📅 *$DAY_NAME* $DATE"
        elif [[ ! -z "$line" ]]; then
            # Replace "Molho para salada:" with "+"
            if [[ "$line" == *"Molho para salada:"* ]]; then
                line="${line/Molho para salada:/+}"
            fi
            # Replace "2ª Opção:" with "ou"
            if [[ "$line" == *"2ª Opção:"* ]]; then
                line="${line/2ª Opção:/ou}"
            fi
            # Check if this line is a continuation of the previous line
            if [[ "$line" == "e "* || "$line" == "("* || "$line" == "+"* ]]; then
                OUTPUT="${OUTPUT%$'\n'} $line"$'\n'
            else
                OUTPUT+="- $line"$'\n'
            fi
        fi
        PREVIOUS_LINE="$line"
    done <<< "$MENU"
    
    # Write to cache if cache is enabled
    if [ "$_ru_USE_CACHE" = true ]; then
        write_cache "$SELECTED_LOCATION" "$OUTPUT"
    fi

    echo -e "$OUTPUT"
}

# Function to display the menu
function write_menu () {
    MENU=$(get_menu)

    # Extract header (first line) separately
    HEADER=$(echo "$MENU" | head -n1)
    # Remove any existing dash prefix from the header
    HEADER=$(echo "$HEADER" | sed 's/^- //')

    if [ "$SHOW_ONLY_TODAY" = true ]; then
        TODAY=$(get_today_weekday)
        # Extract only sections for today
        FILTERED=""
        CURRENT_DAY=""
        INCLUDE_SECTION=false

        # Process the menu for filtering, skipping the header line
        MENU_WITHOUT_HEADER=$(echo "$MENU" | tail -n +2)

        while IFS= read -r line; do
            # Check if this is a day header line
            if [[ "$line" == *"📅"* ]]; then
                CURRENT_DAY="$line"
                # Convert both strings to lowercase for comparison
                DAY_LOWER=$(echo "$CURRENT_DAY" | tr '[:upper:]' '[:lower:]')
                TODAY_LOWER=$(echo "$TODAY" | tr '[:upper:]' '[:lower:]')
                
                # Check if the day header contains today's day name
                if [[ "$DAY_LOWER" == *"${TODAY_LOWER%%-*}"* ]]; then
                    INCLUDE_SECTION=true
                    FILTERED+="$line"$'\n' # Add the day header itself
                else
                    INCLUDE_SECTION=false
                fi
            elif [ "$INCLUDE_SECTION" = true ]; then
                # Only add non-empty lines for the included section
                if [[ -n "$line" ]]; then
                     FILTERED+="$line"$'\n'
                fi
            fi
        done <<< "$MENU_WITHOUT_HEADER"

        echo -e "$HEADER" # Print header with single dash
        echo "" # Add a blank line

        if [ -z "$FILTERED" ]; then
            echo "Não há cardápio disponível para hoje ($TODAY)."
        else
            # Trim potential trailing newline from FILTERED before printing
            echo -e "${FILTERED%$'\n'}"
        fi
    else
        # Original behavior: print the whole menu with a single dash for the header
        echo -e "$HEADER"
        # Print the rest of the menu as is
        echo -e "$(echo "$MENU" | tail -n +2)"
    fi
    echo "" # Add a blank line at the end
}

# Help function
help () {
    echo "Usage: $0 [options]"
    echo "Prints the RU menu to the console."
    echo "Options:"
    echo "  -h, --help: show this help message"
    echo "  -l, --list: list available RU locations"
    echo "  -r, --ru LOCATION: select RU location (default: politecnico)"
    echo "  -t, --today: show only today's menu"
    echo "  -n, --no-cache: do not use cached data"
    echo "  -f, --force: force refresh cache"
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
            -t|--today)
                SHOW_ONLY_TODAY=true
                ;;
            -n|--no-cache)
                _ru_USE_CACHE=false
                ;;
            -f|--force)
                _ru_FORCE_REFRESH=true
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