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
    ["politecnico"]="https://proad.ufpr.br/ru/ru-centro-politecnico/"
    ["agrarias"]="https://proad.ufpr.br/ru/cardapio-ru-agrarias/"
    ["botanico"]="https://proad.ufpr.br/ru/cardapio-ru-jardim-botanico/"
    ["central"]="https://proad.ufpr.br/ru/ru-central/"
    ["toledo"]="https://proad.ufpr.br/ru/6751-2/"
    ["mirassol"]="https://proad.ufpr.br/ru/cardapio-ru-mirassol/"
    ["jandaia"]="https://proad.ufpr.br/ru/cardapio-ru-jandaia-do-sul/"
    ["palotina"]="https://proad.ufpr.br/ru/cardapio-ru-palotina/"
    ["cem"]="https://proad.ufpr.br/ru/cardapio-ru-cem/"
    ["matinhos"]="https://proad.ufpr.br/ru/cardapio-ru-matinhos/"
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
_ru_CACHE_DIR="$(dirname "$(dirname "$(dirname "$0")")")/data/cache/ru"
# Ensure cache directory exists
[[ -d "$_ru_CACHE_DIR" ]] || mkdir -p "$_ru_CACHE_DIR"

function list_locations() {
    echo "Available RU locations:"
    for loc in "${!RU_LOCATIONS[@]}"; do
        echo "  - $loc"
    done
}

# Function to get today's day of the week in Portuguese
function get_today_weekday() {
    # Use cached weekday if available, otherwise fall back to date command
    if [[ -n "$weekday" ]]; then
        case "$weekday" in
            1) echo "Segunda-feira" ;;
            2) echo "Terça-feira" ;;
            3) echo "Quarta-feira" ;;
            4) echo "Quinta-feira" ;;
            5) echo "Sexta-feira" ;;
            6) echo "Sábado" ;;
            7) echo "Domingo" ;;
        esac
    else
        # Fallback to date command
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
    fi
}

# Function to get date in YYYYMMDD format
function get_date_format() {
    # Use cached date_format if available, otherwise fall back to date command
    if [[ -n "$date_format" ]]; then
        echo "$date_format"
    else
        date +"%Y%m%d"
    fi
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
    local cache_dir
    cache_dir="$(dirname "$cache_file")"
    
    # Ensure the directory exists
    [[ -d "$cache_dir" ]] || mkdir -p "$cache_dir"
    
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

    # Ultra-optimized single-pass processing
    OUTPUT=$(curl -s --compressed --connect-timeout 5 --max-time 10 "$URL" | \
        pup 'div#conteudo' | \
        sed -e '/<style>/,/<\/style>/d' -e 's/<[^>]*>//g' | \
        awk '
        BEGIN { 
            print "🍽️  Cardápio RU Politecnico"
            skip = 0
            current_line = ""
        }
        /SENHOR USUÁRIO/ { skip = 1; next }
        /LEGENDA/ { skip = 1; next }
        /Cardápio sujeito/ { skip = 1; next }
        skip { next }
        /^[[:space:]]*$/ { next }
        /Cardápio RU/ { next }
        /:/ && (/table|background|border|padding|margin|color|font|width|height|display|overflow/) { next }
        /\{|\}/ { next }
        /\.wp-block/ { next }
        /Café da manhã/ { 
            if (current_line != "") { print current_line; current_line = "" }
            print "\n🥪 *CAFÉ DA MANHÃ* 🥪"
            next 
        }
        /Almoço/ { 
            if (current_line != "") { print current_line; current_line = "" }
            print "\n🍝 *ALMOÇO* 🍝"
            next 
        }
        /Jantar/ { 
            if (current_line != "") { print current_line; current_line = "" }
            print "\n🍛 *JANTAR* 🍛"
            next 
        }
        /(Segunda|Terça|Quarta|Quinta|Sexta|Sábado|Domingo)[-]?[Ff]eira.*[0-9]/ {
            if (current_line != "") { print current_line; current_line = "" }
            gsub(/^[[:space:]]+|[[:space:]]+$/, "")
            # Split day and date using mawk-compatible approach
            pos = match($0, /[0-9]/)
            if (pos > 0) {
                day = substr($0, 1, pos-1)
                date = substr($0, pos)
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", day)
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", date)
                print "\n📅 *" day "* " date
            }
            next
        }
        /^(Contêm|Contém|Indicado)/ { next }
        {
            # Check for connectives BEFORE trimming whitespace
            if (/^[[:space:]]*e / || /^[[:space:]]*\+/ || /^[[:space:]]*Molho para salada:/) {
                # This is a connective line - trim and process
                gsub(/^[[:space:]]+|[[:space:]]+$/, "")
                gsub(/Molho para salada:/, "+")
                
                # Append to current line if one exists
                if (current_line != "") {
                    current_line = current_line " " $0
                } else {
                    # No previous line, treat as new item
                    current_line = "- " $0
                }
                next
            }
            
            # Regular line processing
            gsub(/^[[:space:]]+|[[:space:]]+$/, "")
            if (length($0) == 0) next
            gsub(/2ª [Oo]pção:/, "ou")
            
            # Print any pending line first
            if (current_line != "") {
                print current_line
            }
            # Start a new line
            current_line = "- " $0
        }
        END {
            # Print any remaining line
            if (current_line != "") {
                print current_line
            }
        }')

    # Check if the content is empty (RU closed or special menu)
    if [[ -z "$OUTPUT" || "$OUTPUT" == "🍽️  Cardápio RU Politecnico" ]]; then
        if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
            echo "O RU está fechado ou o cardápio é especial."
        else
            echo "O RU está *fechado* ou o cardápio é *especial*."
        fi
        return
    fi
    
    # Write to cache if cache is enabled
    if [ "$_ru_USE_CACHE" = true ]; then
        write_cache "$SELECTED_LOCATION" "$OUTPUT"
    fi

    echo "$OUTPUT"
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
            elif [[ "$line" == *"🥪"* || "$line" == *"🍝"* || "$line" == *"🍛"* ]]; then
                # This is a meal section header
                if [ "$INCLUDE_SECTION" = true ]; then
                    FILTERED+="$line"$'\n'
                fi
            elif [ "$INCLUDE_SECTION" = true ]; then
                # Only add non-empty lines for the included section
                if [[ -n "$line" ]]; then
                     FILTERED+="$line"$'\n'
                fi
            fi
        done <<< "$MENU_WITHOUT_HEADER"

        echo -e "$HEADER" # Print header
        echo "" # Add a blank line

        if [ -z "$FILTERED" ]; then
            echo "Não há cardápio disponível para hoje ($TODAY)."
        else
            # Print the filtered content with proper formatting
            echo -e "${FILTERED%$'\n'}"
        fi
    else
        # Original behavior: print the whole menu
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