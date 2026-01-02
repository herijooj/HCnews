#!/usr/bin/env bash
# =============================================================================
# Horoscopo - Daily horoscope for all zodiac signs
# =============================================================================
# Source: https://joaobidu.com.br/horoscopo-do-dia/
# Cache TTL: 82800 (23 hours)
# Output: Daily horoscope predictions formatted for Telegram/terminal
# =============================================================================

# -----------------------------------------------------------------------------
# Source Common Library (ALWAYS FIRST)
# -----------------------------------------------------------------------------
[[ -n "${_HCNEWS_COMMON_LOADED:-}" ]] || source "${HCNEWS_COMMON_PATH}common.sh" 2>/dev/null || source "${BASH_SOURCE%/*}/lib/common.sh"

# -----------------------------------------------------------------------------
# Parse Arguments
# -----------------------------------------------------------------------------
hcnews_parse_args "$@"
_horoscopo_USE_CACHE=$_HCNEWS_USE_CACHE
_horoscopo_FORCE_REFRESH=$_HCNEWS_FORCE_REFRESH

# Shift to remaining arguments for sign name
set -- "${_HCNEWS_REMAINING_ARGS[@]}"

# -----------------------------------------------------------------------------
# Configuration Constants
# -----------------------------------------------------------------------------
CACHE_TTL_SECONDS="${HCNEWS_CACHE_TTL["horoscopo"]:-82800}"

# -----------------------------------------------------------------------------
# Lookup Tables
# -----------------------------------------------------------------------------
declare -A SIGN_EMOJIS=(
    ["aries"]="♈" ["touro"]="♉" ["gemeos"]="♊" ["cancer"]="♋"
    ["leao"]="♌" ["virgem"]="♍" ["libra"]="♎" ["escorpiao"]="♏"
    ["sagitario"]="♐" ["capricornio"]="♑" ["aquario"]="♒" ["peixes"]="♓"
)

declare -A SIGN_NAMES=(
    ["aries"]="Áries" ["touro"]="Touro" ["gemeos"]="Gêmeos" ["cancer"]="Câncer"
    ["leao"]="Leão" ["virgem"]="Virgem" ["libra"]="Libra" ["escorpiao"]="Escorpião"
    ["sagitario"]="Sagitário" ["capricornio"]="Capricórnio" ["aquario"]="Aquário" ["peixes"]="Peixes"
)

# -----------------------------------------------------------------------------
# Data Fetching Function
# -----------------------------------------------------------------------------
get_horoscopo_data() {
    local sign="$1"
    local ttl="$CACHE_TTL_SECONDS"
    local date_str; date_str=$(hcnews_get_date_format)
    local cache_file; hcnews_set_cache_path cache_file "horoscopo" "$date_str" "$sign"

    # Check cache first
    if [[ "$_horoscopo_USE_CACHE" == true ]] && hcnews_check_cache "$cache_file" "$ttl" "$_horoscopo_FORCE_REFRESH"; then
        hcnews_read_cache "$cache_file"
        return 0
    fi

    # Fetch horoscope from website
    local url="https://joaobidu.com.br/horoscopo-do-dia/horoscopo-do-dia-para-${sign}/"
    local response
    response=$(curl -s -A "Mozilla/5.0" "$url")

    # Extract the horoscope text
    local raw_text
    raw_text=$(echo "$response" | pup '.text-block text{}')

    # Format the text
    local formatted
    formatted=$(echo "$raw_text" | sed 's/\xc2\xa0/ /g' | awk '
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
    ')

    # Save to cache if enabled
    if [[ "$_horoscopo_USE_CACHE" == true && -n "$formatted" ]]; then
        hcnews_write_cache "$cache_file" "$formatted"
    fi

    echo "$formatted"
}

# -----------------------------------------------------------------------------
# Output Function
# -----------------------------------------------------------------------------
write_horoscopo() {
    local sign="${1:-}"
    local emoji="🔮"
    local sign_name="Sign"

    # Get emoji and name from lookup tables
    if [[ -n "$sign" ]]; then
        emoji="${SIGN_EMOJIS[$sign]:-🔮}"
        sign_name="${SIGN_NAMES[$sign]:-}"
    fi

    # If no sign provided, fetch all signs
    if [[ -z "$sign" ]]; then
        echo "🔮 *Horóscopo do dia*"
        echo ""
        local all_signs=("aries" "touro" "gemeos" "cancer" "leao" "virgem" "libra" "escorpiao" "sagitario" "capricornio" "aquario" "peixes")

        # Create temp directory for parallel outputs
        local tmp_dir="/tmp/hcnews_horoscopo_$$"
        mkdir -p "$tmp_dir"

        # Fetch all signs in parallel
        for s in "${all_signs[@]}"; do
            (
                local text; text=$(get_horoscopo_data "$s")
                echo "$text" > "$tmp_dir/$s.txt"
            ) &
        done
        wait

        # Read and output results in order
        for s in "${all_signs[@]}"; do
            local text; text=$(cat "$tmp_dir/$s.txt" 2>/dev/null || echo "Erro ao obter horóscopo de $s")
            local s_emoji="${SIGN_EMOJIS[$s]:-🔮}"
            local s_name="${SIGN_NAMES[$s]:-}"
            echo "$s_emoji *$s_name*"
            echo "$text"
            echo ""
        done

        # Cleanup
        rm -rf "$tmp_dir"
    else
        local text; text=$(get_horoscopo_data "$sign")
        [[ -z "$text" ]] && return 1

        echo "$text"
        echo ""
        echo "🔸 $sign_name $emoji"
        echo "_Fonte: joaobidu.com.br_"
        echo ""
    fi
}

# -----------------------------------------------------------------------------
# Help Function
# -----------------------------------------------------------------------------
show_help() {
    echo "Usage: ./horoscopo.sh [options] [sign]"
    echo "The horoscope will be printed to the console."
    echo "If no sign is provided, all signs will be fetched."
    echo ""
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  --all          Fetch all signs (default for build script)"
    echo "  --no-cache     Bypass cache for this run"
    echo "  --force        Force refresh cached data"
    echo ""
    echo "Signs:"
    echo "  aries, touro, gemeos, cancer, leao, virgem, libra"
    echo "  escorpiao, sagitario, capricornio, aquario, peixes"
}

# -----------------------------------------------------------------------------
# Main Entry Point
# -----------------------------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    hcnews_parse_args "$@"
    # Shift remaining args for the sign
    set -- "${_HCNEWS_REMAINING_ARGS[@]}"

    if [[ "$1" == "--all" ]]; then
        write_horoscopo ""  # Empty = all signs
    else
        write_horoscopo "${1:-}"  # Empty = all signs
    fi
fi
