#!/usr/bin/env bash

# Cache configuration
_sanepar_CACHE_DIR="$(dirname "$(dirname "${BASH_SOURCE[0]}")")/data/cache/sanepar"
CACHE_TTL_SECONDS=$((6 * 60 * 60)) # 6 hours - dam levels don't change frequently
# Default cache behavior is enabled
_sanepar_USE_CACHE=true
# Force refresh cache
_sanepar_FORCE_REFRESH=false

# Override defaults if --no-cache or --force is passed during sourcing
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then # Check if sourced
    _current_sourcing_args_for_sanepar=("${@}") 
    for arg in "${_current_sourcing_args_for_sanepar[@]}"; do
      case "$arg" in
        --no-cache)
          _sanepar_USE_CACHE=false
          ;;
        --force)
          _sanepar_FORCE_REFRESH=true
          ;;
      esac
    done
fi

# Ensure cache directory exists
mkdir -p "$_sanepar_CACHE_DIR"

# Function to get date in YYYYMMDD format
function get_date_format() {
    date +"%Y%m%d"
}

# Function to check if cache exists and is within TTL
function check_cache() {
    local cache_file_path="$1"
    if [ -f "$cache_file_path" ] && [ "$_sanepar_FORCE_REFRESH" = false ]; then
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
function read_cache() {
    local cache_file_path="$1"
    cat "$cache_file_path"
}

# Function to write to cache
function write_cache() {
    local cache_file_path="$1"
    local content="$2"
    
    # Ensure the directory exists
    mkdir -p "$(dirname "$cache_file_path")"
    
    # Write content to cache file with proper newline interpretation
    echo -e "$content" > "$cache_file_path"
}

# Function to get dam levels from Sanepar
function get_sanepar_levels() {
    local date_format
    date_format=$(get_date_format)
    local cache_file="${_sanepar_CACHE_DIR}/${date_format}_sanepar.cache"

    # Check cache first
    if [ "$_sanepar_USE_CACHE" = true ] && check_cache "$cache_file"; then
        read_cache "$cache_file"
        return
    fi

    # Use the real Sanepar API endpoint
    local api_url="https://ri.sanepar.com.br/"
    
    # Fetch dam levels data with proper headers
    local content
    content=$(curl -s --max-time 15 --connect-timeout 8 --retry 2 \
        -H "User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36" \
        -H "Referer: https://site.sanepar.com.br/" \
        -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" \
        -H "Accept-Language: pt-BR,pt;q=0.9,en;q=0.8" \
        "$api_url" 2>/dev/null)
    
    if [[ -z "$content" ]]; then
        echo "💧 *MANANCIAIS E NÍVEL DOS RESERVATÓRIOS*"
        echo "⚠️ Dados não disponíveis no momento"
        echo "_Fonte: SANEPAR/INFOHIDRO_"
        return 1
    fi
    # Use the Python script to extract and format data
    local python_output
    python_output=$(echo "$content" | python3 scripts/parse_sanepar.py)

    if [[ -z "$python_output" ]]; then
        echo "💧 *MANANCIAIS E NÍVEL DOS RESERVATÓRIOS*"
        echo "⚠️ Não foi possível extrair os dados da página."
        echo "_Fonte: SANEPAR/RI_"
        return 1
    fi

    # Read the output from the python script line by line
    read -r irai_level_raw <<< "$(echo "$python_output" | sed -n '1p')"
    read -r passauna_level_raw <<< "$(echo "$python_output" | sed -n '2p')"
    read -r piraquara1_level_raw <<< "$(echo "$python_output" | sed -n '3p')"
    read -r piraquara2_level_raw <<< "$(echo "$python_output" | sed -n '4p')"
    read -r total_saic_raw <<< "$(echo "$python_output" | sed -n '5p')"
    read -r update_time_raw <<< "$(echo "$python_output" | sed -n '6p')"

    # Function to format decimal to percentage string (e.g., 0.753 -> 75,30%)
    format_percentage() {
        local raw_value="$1"
        if [[ -n "$raw_value" && "$raw_value" != "null" ]]; then
            # Use awk for floating point multiplication and printf for formatting
            awk -v val="$raw_value" 'BEGIN { printf "%.2f%%", val * 100 }' | sed 's/\./,/'
        fi
    }

    local irai_level=$(format_percentage "$irai_level_raw")
    local passauna_level=$(format_percentage "$passauna_level_raw")
    local piraquara1_level=$(format_percentage "$piraquara1_level_raw")
    local piraquara2_level=$(format_percentage "$piraquara2_level_raw")
    local total_saic=$(format_percentage "$total_saic_raw")

    # Format update time
    local update_time
    if [[ -n "$update_time_raw" && "$update_time_raw" != "null" ]]; then
        update_time_raw_no_z="${update_time_raw//Z/ UTC}"
        update_time=$(TZ=UTC date -d "$update_time_raw_no_z" +"Atualizado em %d/%m/%Y às %H:%M")
    fi
    
    # Check if we found at least some data
    if [[ -n "$irai_level" || -n "$passauna_level" || -n "$piraquara1_level" || -n "$piraquara2_level" || -n "$total_saic" ]]; then
        local formatted_output="💧 *Mananciais e nível dos reservatórios*"
        
        if [[ -n "$irai_level" ]]; then
            formatted_output+="\n🏔️ Barragem Iraí: \`$irai_level\`"
        fi
        if [[ -n "$passauna_level" ]]; then
            formatted_output+="\n🌊 Barragem Passaúna: \`$passauna_level\`"
        fi
        if [[ -n "$piraquara1_level" ]]; then
            formatted_output+="\n💦 Barragem Piraquara 1: \`$piraquara1_level\`"
        fi
        if [[ -n "$piraquara2_level" ]]; then
            formatted_output+="\n🌿 Barragem Piraquara 2: \`$piraquara2_level\`"
        fi
        if [[ -n "$total_saic" ]]; then
            formatted_output+="\n📊 Total: \`$total_saic\`"
        fi
        
        formatted_output+="\n_Fonte: Sanepar/RI · ${update_time}_"
        
        # Save to cache if enabled
        if [ "$_sanepar_USE_CACHE" = true ]; then
            write_cache "$cache_file" "$formatted_output"
        fi
        
        echo -e "$formatted_output"
        return 0
    else
        echo "💧 *Mananciais e nível dos reservatórios*"
        echo "⚠️ Dados não disponíveis no momento"
        echo "_Fonte: Sanepar/InfoHidro · ${update_time}_"
        return 1
    fi
}

# Main function to write Sanepar dam levels
function write_sanepar() {
    get_sanepar_levels
    echo ""
}

# Help function
function help() {
    echo "Usage: ./sanepar.sh [options]"
    echo "Retrieves and displays Sanepar dam levels."
    echo "Options:"
    echo "  -h, --help: show this help message"
    echo "  --no-cache: do not use cached data"
    echo "  --force: force refresh cache"
}

# Argument parsing function
function get_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                help
                exit 0
                ;;
            --no-cache)
                _sanepar_USE_CACHE=false
                ;;
            --force)
                _sanepar_FORCE_REFRESH=true
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
    write_sanepar
fi