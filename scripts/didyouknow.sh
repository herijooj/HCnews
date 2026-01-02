#!/usr/bin/env bash

# Source common library if not already loaded
[[ -n "${_HCNEWS_COMMON_LOADED:-}" ]] || source "${HCNEWS_COMMON_PATH:-${BASH_SOURCE%/*}/lib/common.sh}" 2>/dev/null || source "${BASH_SOURCE%/*}/scripts/lib/common.sh"

get_didyouknow() {
    hcnews_parse_args "$@"
    local date_str=$(hcnews_get_date_format)
    local cache_file; hcnews_set_cache_path cache_file "didyouknow" "$date_str"
    local ttl=${HCNEWS_CACHE_TTL["didyouknow"]:-86400}

    # Cache check
    if [[ "$_HCNEWS_USE_CACHE" = true ]] && hcnews_check_cache "$cache_file" "$ttl" "$_HCNEWS_FORCE_REFRESH"; then
        hcnews_read_cache "$cache_file"
        return 0
    fi

    local URL="https://pt.wikipedia.org/w/api.php?action=query&prop=extracts&explaintext=1&titles=Predefini%C3%A7%C3%A3o:Sabia_que&format=json"
    
    # Use temporary file
    local tmp_file="/tmp/didyouknow_$$.json"
    
    # Simple curl with retry
    if curl -s -H "User-Agent: HCnews/1.0 (https://github.com/herijooj/HCnews)" --compressed "$URL" > "$tmp_file"; then
        
        # Process directly. Extract lines starting with … or ...
        local items
        items=$(jq -r '.query.pages[]?.extract' "$tmp_file" | grep -E '^[….]' | sed 's/^… //;s/^\.\.\. //;s/\\n/ /g' | shuf -n 1)
        
        # Fallback if empty
        if [[ -z "$items" ]]; then
            rm -f "$tmp_file"
            return 1
        fi
        rm -f "$tmp_file"

        # Clean text
        items=$(echo "$items" | tr -s ' ' | sed 's/^ *//;s/ *$//')
        if type hcnews_decode_html_entities &>/dev/null; then
            items=$(hcnews_decode_html_entities "$items")
        fi

        local output="📚 *Você sabia?*"
        output+=$'\n'
        output+="- ${items}"
        output+=$'\n_Fonte: Wikipedia_'

        if [[ "$_HCNEWS_USE_CACHE" == true ]]; then
            hcnews_write_cache "$cache_file" "$output"
        fi
        echo "$output"
    else
        rm -f "$tmp_file"
        return 1
    fi
}

write_did_you_know() {
    local block
    block=$(get_didyouknow "$@")
    if [[ -n "$block" ]]; then
        echo "$block"
    fi
}

# -------------------------------- Running locally --------------------------------

# Standard help
show_help() {
  echo "Usage: ./didyouknow.sh [--no-cache|--force|--telegram]"
  echo "Fetches a random 'Did You Know' fact from Wikipedia."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    write_did_you_know "$@"
fi