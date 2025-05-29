#!/bin/bash

# Cache configuration
_horoscopo_CACHE_DIR="$(dirname "$(dirname "${BASH_SOURCE[0]}")")/data/news"
CACHE_TTL_SECONDS=$((23 * 60 * 60)) # 23 hours
# Default cache behavior is enabled
_horoscopo_USE_CACHE=true
# Force refresh cache
_horoscopo_FORCE_REFRESH=false

function sign_to_emoji {
    declare -A EMOJIS=(
        ["aries"]="♈" ["peixes"]="♓" ["aquario"]="♒" ["capricornio"]="♑"
        ["sagitario"]="♐" ["escorpiao"]="♏" ["libra"]="♎" ["virgem"]="♍"
        ["leao"]="♌" ["cancer"]="♋" ["gemeos"]="♊" ["touro"]="♉"
    )
    echo "${EMOJIS[$1]}"
}

# Add new function to format sign names properly
function format_sign_name {
    declare -A SIGN_NAMES=(
        ["aries"]="Áries" ["peixes"]="Peixes" ["aquario"]="Aquário" ["capricornio"]="Capricórnio"
        ["sagitario"]="Sagitário" ["escorpiao"]="Escorpião" ["libra"]="Libra" ["virgem"]="Virgem"
        ["leao"]="Leão" ["cancer"]="Câncer" ["gemeos"]="Gêmeos" ["touro"]="Touro"
    )
    echo "${SIGN_NAMES[$1]}"
}

# Function to get today's date in YYYYMMDD format
get_date_format() {
    date +"%Y%m%d"
}

# Function to check if cache exists and is from today and within TTL
check_cache() {
    local cache_file_path="$1"
    if [ -f "$cache_file_path" ] && [ "$_horoscopo_FORCE_REFRESH" = false ]; then
        # Check TTL
        local file_mod_time
        file_mod_time=$(stat -c %Y "$cache_file_path")
        local current_time
        current_time=$(date +%s)
        if (( (current_time - file_mod_time) < CACHE_TTL_SECONDS )); then
            # Cache exists, not forced, and within TTL
            return 0
        fi
    fi
    return 1
}

# Function to read from cache
read_cache() {
    local cache_file_path="$1"
    cat "$cache_file_path"
}

# Function to write to cache
write_cache() {
    local cache_file_path="$1"
    local content="$2"
    
    # Ensure the directory exists
    mkdir -p "$(dirname "$cache_file_path")"
    
    # Write content to cache file
    printf "%b" "$content" > "$cache_file_path"
}

# this function retrieves the horoscope from the website
#https://joaobidu.com.br/horoscopo-do-dia/horoscopo-do-dia-para-aries/
#https://joaobidu.com.br/horoscopo-do-dia/horoscopo-do-dia-para-peixes/
#https://joaobidu.com.br/horoscopo-do-dia/horoscopo-do-dia-para-aquario/
#https://joaobidu.com.br/horoscopo-do-dia/horoscopo-do-dia-para-capricornio/
#https://joaobidu.com.br/horoscopo-do-dia/horoscopo-do-dia-para-sagitario/
#https://joaobidu.com.br/horoscopo-do-dia/horoscopo-do-dia-para-escorpiao/
#https://joaobidu.com.br/horoscopo-do-dia/horoscopo-do-dia-para-libra/
#https://joaobidu.com.br/horoscopo-do-dia/horoscopo-do-dia-para-virgem/
#https://joaobidu.com.br/horoscopo-do-dia/horoscopo-do-dia-para-leao/
#https://joaobidu.com.br/horoscopo-do-dia/horoscopo-do-dia-para-cancer/
#https://joaobidu.com.br/horoscopo-do-dia/horoscopo-do-dia-para-gemeos/
#https://joaobidu.com.br/horoscopo-do-dia/horoscopo-do-dia-para-touro/
function get_horoscopo {
    SIGN="$1"
    # get the horoscope
    HOROSCOPO=$(curl -s -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.3" "https://joaobidu.com.br/horoscopo-do-dia/horoscopo-do-dia-para-$SIGN/")
    # extract the horoscope using the correct selector for the current website structure
    HOROSCOPO=$(echo "$HOROSCOPO" | pup 'p.MsoNormal text{}')

    # return the horoscope
    echo "$HOROSCOPO"
}

function write_horoscopo {
    # get the arguments
    SIGN="$1"
    EMOJI=$(sign_to_emoji "$SIGN")
    FORMATTED_SIGN=$(format_sign_name "$SIGN")
    # get the horoscope
    HOROSCOPO=$(get_horoscopo "$SIGN")
    # write the horoscope to the console
    echo "$HOROSCOPO"
    echo ""
    echo "🔸 *$FORMATTED_SIGN* $EMOJI"
    echo ""
}
# -------------------------------- Running locally --------------------------------

# help function
# Usage: ./horoscopo.sh [options] <sign>
# The command will be printed to the console.
# Options:
#   -h, --help: show the help
#   -s, --save: save the output to a file (YYYYMMDD.hrcp)
#   -n, --no-cache: Do not use cached data
#   -f, --force: Force refresh cache
help () {
    echo "Usage: ./horoscopo.sh [options] <sign>"
    echo "The command will be printed to the console."
    echo "Options:"
    echo "  -h, --help: show the help"
    echo "  -s, --save: save the output to a file (YYYYMMDD.hrcp)"
    echo "  -n, --no-cache: Do not use cached data"
    echo "  -f, --force: Force refresh cache"
}

save_to_file() {
    local content="$1"
    local filename="$2"
    printf "%b" "$content" > "$filename"
    echo "✅ Saved to $filename"
}

# this function will receive the arguments
get_arguments () {
    SAVE_TO_FILE=false
    # Get the arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                help
                exit 0
                ;;
            -s|--save)
                SAVE_TO_FILE=true
                shift
                ;;
            -n|--no-cache)
                _horoscopo_USE_CACHE=false
                shift
                ;;
            -f|--force)
                _horoscopo_FORCE_REFRESH=true
                shift
                ;;
            *)
                SIGN="$1"
                shift
                ;;
        esac
    done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    get_arguments "$@"
    
    date_format=$(get_date_format)
    cache_file_name="${date_format}.hrcp"
    cache_file_path="${_horoscopo_CACHE_DIR}/${cache_file_name}"

    # If -s is not used, but we want to cache, set a default filename for caching
    effective_cache_file_path="$cache_file_path"

    # Check cache if _horoscopo_USE_CACHE is true (regardless of -s)
    if [[ "$_horoscopo_USE_CACHE" = true ]] && check_cache "$effective_cache_file_path"; then
        output=$(read_cache "$effective_cache_file_path")
        if [[ "$SAVE_TO_FILE" = true ]]; then
             echo "✅ Output is already cached. Use -f to force refresh."
        fi
        printf "%b" "$output"
        exit 0
    fi

    output="🔮 *Horóscopo do dia* 🔮\\n\\n"
    
    # Set default directory to data/news if -s flag is used or if caching is enabled without -s
    filename_to_save=""
    if [[ "$SAVE_TO_FILE" = true ]]; then
        filename_to_save="$cache_file_path"
    fi

    if [[ -z "$SIGN" ]]; then
        SIGNS=("aries" "peixes" "aquario" "capricornio" "sagitario" "escorpiao" "libra" "virgem" "leao" "cancer" "gemeos" "touro")
        for SIGN in "${SIGNS[@]}"; do
            HOROSCOPO=$(get_horoscopo "$SIGN")
            EMOJI=$(sign_to_emoji "$SIGN")
            FORMATTED_SIGN=$(format_sign_name "$SIGN")
            output+="$HOROSCOPO\\n\\n🔸 *$FORMATTED_SIGN* $EMOJI\\n\\n"
        done
    else
        HOROSCOPO=$(get_horoscopo "$SIGN")
        EMOJI=$(sign_to_emoji "$SIGN")
        FORMATTED_SIGN=$(format_sign_name "$SIGN")
        output+="$HOROSCOPO\\n\\n🔸 *$FORMATTED_SIGN* $EMOJI\\n\\n"
    fi

    # Save to file if -s is used OR if _horoscopo_USE_CACHE is true and -s is not used (cache the output)
    if [[ "$SAVE_TO_FILE" = true || ("$_horoscopo_USE_CACHE" = true && "$SAVE_TO_FILE" = false) ]]; then
        write_cache "$effective_cache_file_path" "$output"
        if [[ "$SAVE_TO_FILE" = true ]]; then
            echo "✅ Saved to $effective_cache_file_path"
        fi
    fi
    printf "%b" "$output"
fi