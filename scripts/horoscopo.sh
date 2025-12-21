#!/usr/bin/env bash


# Source common library if not already loaded
[[ -n "${_HCNEWS_COMMON_LOADED:-}" ]] || source "${HCNEWS_COMMON_PATH:-${BASH_SOURCE%/*}/lib/common.sh}" 2>/dev/null || source "${BASH_SOURCE%/*}/scripts/lib/common.sh"

# Cache configuration via common
CACHE_TTL_SECONDS=${HCNEWS_CACHE_TTL["horoscopo"]:-82800} # 23 hours
hcnews_parse_cache_args "$@"
_horoscopo_USE_CACHE=$_HCNEWS_USE_CACHE
_horoscopo_FORCE_REFRESH=$_HCNEWS_FORCE_REFRESH

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
# Function to get today's date in YYYYMMDD format
get_date_format() {
    hcnews_get_date_format
}

# Removed custom check_cache, read_cache, write_cache in favor of common functions

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
    URL="https://joaobidu.com.br/horoscopo-do-dia/horoscopo-do-dia-para-$SIGN/"
    USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.3"
    
    HOROSCOPO=$(curl -s -A "$USER_AGENT" "$URL")
    # extract the horoscope using the correct selector for the current website structure
    RAW_TEXT=$(echo "$HOROSCOPO" | pup '.text-block text{}')

    # Format the text using awk
    # sed removes non-breaking spaces (U+00A0) which cause awk regex issues
    echo "$RAW_TEXT" | sed 's/\xc2\xa0/ /g' | awk '
    function print_buffer() {
        if (buffer != "") {
            print "- " buffer
            buffer = ""
        }
    }
    {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "");
    }
    length($0) == 0 { next }
    /:$/ {
        print_buffer()
        print "*" $0 "*"
        next
    }
    {
        if (buffer == "") {
            buffer = $0
        } else {
            buffer = buffer " " $0
        }
    }
    END {
        print_buffer()
    }
    '
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
    echo "🔸 $FORMATTED_SIGN $EMOJI"
    echo "_Fonte: joaobidu.com.br_"
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
    # Determine cache file path using standardized function
    # Note: If -s is provided, we might be writing to a specific file, but script logic below suggests
    # it uses the cache location?
    # Original used: cache_file_path="${_horoscopo_CACHE_DIR}/${cache_file_name}" in data/news
    # We will mostly rely on standard path unless specific override needed
    # But this script supports calculating for ALL signs if no sign provided.
    # If no sign provided, where do we cache?
    
    # Ah, it set "cache_file_name" to just DATE.hrcp.
    # So if SIGN is empty, variant is empty.
    
    cache_name="horoscopo"
    
    cache_file_path=$(hcnews_get_cache_path "$cache_name" "$date_format" "$SIGN")

    # If -s is not used, but we want to cache, set a default filename for caching
    effective_cache_file_path="$cache_file_path"

    # Check cache if _horoscopo_USE_CACHE is true (regardless of -s)
    if [[ "$_horoscopo_USE_CACHE" = true ]] && hcnews_check_cache "$effective_cache_file_path" "$CACHE_TTL_SECONDS" "$_horoscopo_FORCE_REFRESH"; then
        output=$(hcnews_read_cache "$effective_cache_file_path")
        if [[ "$SAVE_TO_FILE" = true ]]; then
             echo "✅ Output is already cached. Use -f to force refresh."
        fi
        printf "%b" "$output"
        exit 0
    fi

    output="🔮 *Horóscopo do dia*\n\n"
    
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
            
            output+="$EMOJI *$FORMATTED_SIGN*\n$HOROSCOPO\n\n"
            
            # Be polite to the server
            sleep 1
        done
    else
        HOROSCOPO=$(get_horoscopo "$SIGN")
        EMOJI=$(sign_to_emoji "$SIGN")
        FORMATTED_SIGN=$(format_sign_name "$SIGN")
        
        output+="$EMOJI *$FORMATTED_SIGN*\n$HOROSCOPO\n"
    fi

    # Trim trailing whitespace including literal \n sequences
    while [[ "$output" == *$'\n' ]] || [[ "$output" == *"\\n" ]] || [[ "$output" == *" " ]]; do
        if [[ "$output" == *"\\n" ]]; then
           output="${output%\\n}"
        else
           output="${output%?}"
        fi
    done
    
    # Add exactly one newline back (literal \n for printf %b)
    output+="\n"

    output+="_Fonte: joaobidu.com.br_\n"
    output+="\n"

    # Save to file if -s is used OR if _horoscopo_USE_CACHE is true and -s is not used (cache the output)
    if [[ "$SAVE_TO_FILE" = true || ("$_horoscopo_USE_CACHE" = true && "$SAVE_TO_FILE" = false) ]]; then
        hcnews_write_cache "$effective_cache_file_path" "$output"
        if [[ "$SAVE_TO_FILE" = true ]]; then
            echo "✅ Saved to $effective_cache_file_path"
        fi
    fi
    printf "%b" "$output"
fi