#!/bin/bash

function sign_to_emoji {
    declare -A EMOJIS=(
        ["aries"]="♈" ["peixes"]="♓" ["aquario"]="♒" ["capricornio"]="♑"
        ["sagitario"]="♐" ["escorpiao"]="♏" ["libra"]="♎" ["virgem"]="♍"
        ["leao"]="♌" ["cancer"]="♋" ["gemeos"]="♊" ["touro"]="♉"
    )
    echo "${EMOJIS[$1]}"
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
    # extract the horoscope
    HOROSCOPO=$(echo "$HOROSCOPO" | pup '.theiaPostSlider_preloadedSlide > div:nth-child(3) > p:nth-child(1) text{}')

    # return the horoscope
    echo "$HOROSCOPO"
}

function write_horoscopo {
    # get the arguments
    SIGN="$1"
    EMOJI=$(sign_to_emoji "$SIGN")
    # get the horoscope
    HOROSCOPO=$(get_horoscopo "$SIGN")
    # write the horoscope to the console
    echo "$HOROSCOPO"
    echo "📌 $SIGN $EMOJI"
    echo ""
}
# -------------------------------- Running locally --------------------------------

# help function
# Usage: ./horoscopo.sh [options] <sign>
# The command will be printed to the console.
# Options:
#   -h, --help: show the help
#   -s, --save: save the output to a file (YYYYMMDD.hrcp)
help () {
    echo "Usage: ./horoscopo.sh [options] <sign>"
    echo "The command will be printed to the console."
    echo "Options:"
    echo "  -h, --help: show the help"
    echo "  -s, --save: save the output to a file (YYYYMMDD.hrcp)"
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
            *)
                SIGN="$1"
                shift
                ;;
        esac
    done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    get_arguments "$@"
    output="🔮 *Horóscopo do dia* 🔮\\n\\n"
    
    # Set default directory to news if -s flag is used
    if [[ "$SAVE_TO_FILE" = true ]]; then
        mkdir -p "news"
        filename="news/$(date +%Y%m%d).hrcp"
    fi

    if [[ -z "$SIGN" ]]; then
        SIGNS=("aries" "peixes" "aquario" "capricornio" "sagitario" "escorpiao" "libra" "virgem" "leao" "cancer" "gemeos" "touro")
        for SIGN in "${SIGNS[@]}"; do
            HOROSCOPO=$(get_horoscopo "$SIGN")
            EMOJI=$(sign_to_emoji "$SIGN")
            output+="$HOROSCOPO\\n📌 $SIGN $EMOJI\\n\\n"
        done
    else
        HOROSCOPO=$(get_horoscopo "$SIGN")
        EMOJI=$(sign_to_emoji "$SIGN")
        output+="$HOROSCOPO\\n📌 $SIGN $EMOJI\\n\\n"
    fi

    if [[ "$SAVE_TO_FILE" = true ]]; then
        save_to_file "$output" "$filename"
    fi
    printf "%b" "$output"
fi