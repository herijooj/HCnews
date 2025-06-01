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
    local api_url="https://site.sanepar.com.br/sites/site.sanepar.com.br/themes/sanepar2012/webservice/nivel_reservatorios.php"
    
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

    # Extract reservoir levels using pup and the exact HTML structure
    local irai_level=$(echo "$content" | pup 'div:contains("Barragem Iraí") + div + div.views-field-body p text{}' | head -1)
    local passauna_level=$(echo "$content" | pup 'div:contains("Barragem Passaúna") + div + div.views-field-body p text{}' | head -1)
    local piraquara1_level=$(echo "$content" | pup 'div:contains("Barragem Piraquara 1") + div + div.views-field-body p text{}' | head -1)
    local piraquara2_level=$(echo "$content" | pup 'div:contains("Barragem Piraquara 2") + div + div.views-field-body p text{}' | head -1)
    local total_saic=$(echo "$content" | pup 'div:contains("Total SAIC") + div + div.views-field-body p text{}' | head -1)
    local update_time=$(echo "$content" | pup '.nivel-reserv-data text{}' | head -1)
    
    # Fallback extraction using grep if pup doesn't work properly
    if [[ -z "$irai_level" || -z "$passauna_level" || -z "$piraquara1_level" || -z "$piraquara2_level" || -z "$total_saic" ]]; then
        irai_level=$(echo "$content" | grep -A 3 "Barragem Iraí" | grep -o '[0-9]\+\.[0-9]\+%' | head -1)
        passauna_level=$(echo "$content" | grep -A 3 "Barragem Passaúna" | grep -o '[0-9]\+\.[0-9]\+%' | head -1)
        piraquara1_level=$(echo "$content" | grep -A 3 "Barragem Piraquara 1" | grep -o '[0-9]\+\.[0-9]\+%' | head -1)
        piraquara2_level=$(echo "$content" | grep -A 3 "Barragem Piraquara 2" | grep -o '[0-9]\+\.[0-9]\+%' | head -1)
        total_saic=$(echo "$content" | grep -A 3 "Total SAIC" | grep -o '[0-9]\+\.[0-9]\+%' | head -1)
        update_time=$(echo "$content" | grep -o "Atualizado em: [0-9]\+/[0-9]\+/[0-9]\+ [0-9]\+:[0-9]\+" | head -1)
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
            formatted_output+="\n📊 Total SAIC*: \`$total_saic\`"
        fi
        
        formatted_output+="\n"
        
        if [[ -n "$update_time" ]]; then
            formatted_output+="\n$update_time"
        else
            formatted_output+="\nAtualizado em: $(date '+%d/%m/%Y %H:%M')"
        fi
        
        formatted_output+="\n_Fonte: Sanepar/InfoHidro_"
        
        # Save to cache if enabled
        if [ "$_sanepar_USE_CACHE" = true ]; then
            write_cache "$cache_file" "$formatted_output"
        fi
        
        echo -e "$formatted_output"
        return 0
    else
        echo "💧 *Mananciais e nível dos reservatórios*"
        echo "⚠️ Dados não disponíveis no momento"
        echo "_Fonte: Sanepar/InfoHidro_"
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