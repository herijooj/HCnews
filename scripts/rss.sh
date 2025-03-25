#!/usr/bin/env bash
RSS_DIR=$(dirname "$(realpath "${BASH_SOURCE[0]}")")

# Source the shortening script with proper path
source "$RSS_DIR/shortening.sh"

# Cache directory for URL shortening
CACHE_DIR="${HOME}/.cache/hcnews"
mkdir -p "$CACHE_DIR"
URL_CACHE_FILE="${CACHE_DIR}/url_cache.txt"
touch "$URL_CACHE_FILE"

# Set locale once at the beginning
#export LC_ALL=en_US.UTF-8

# Get timestamp for 24 hours ago once
UNIX_24H_AGO=$(date -d "24 hours ago" +%s)

# Cache for date to unix conversions
declare -A DATE_CACHE

# Optimized function to convert RSS date to unix timestamp
date_rss_to_unix() {
    local date_str="$1"
    
    # Return from cache if available
    if [[ -n "${DATE_CACHE[$date_str]}" ]]; then
        echo "${DATE_CACHE[$date_str]}"
        return
    fi
    
    # Quick format validation using regex
    if [[ ! $date_str =~ ^[A-Z][a-z]{2},\ [0-9]{2}\ [A-Z][a-z]{2}\ [0-9]{4}\ [0-9]{2}:[0-9]{2}:[0-9]{2} ]]; then
        DATE_CACHE[$date_str]="0"
        echo "0"
        return
    fi
    
    # Convert the date to unix
    local unix_time
    unix_time=$(date -d "$date_str" +%s 2>/dev/null || echo "0")
    
    # Store in cache
    DATE_CACHE[$date_str]="$unix_time"
    
    echo "$unix_time"
}

# Improved URL shortening with caching
cached_shorten_url() {
    local url="$1"
    local short_url
    
    # Check if URL is in cache
    short_url=$(grep -F "$url|" "$URL_CACHE_FILE" | cut -d'|' -f2)
    
    if [[ -z "$short_url" ]]; then
        # Not in cache, get a new shortened URL
        short_url=$(shorten_url_isgd "$url")
        # Add to cache
        echo "$url|$short_url" >> "$URL_CACHE_FILE"
    fi
    
    echo "$short_url"
}

# Optimized news retrieval function
get_news_RSS_combined() {
    local RSS_FEED=$1
    local LINKED=$2
    local FULL_URL=$3
    local result=()
    
    # Fetch feed content once
    local FEED_CONTENT
    FEED_CONTENT=$(curl -s --max-time 10 "$RSS_FEED")
    
    # Quick validation check
    if [[ "$FEED_CONTENT" != *"<item>"* ]]; then
        return
    fi
    
    # Use a more optimized approach to extract items
    while read -r date && read -r title && read -r link; do
        # Convert publication date to unix timestamp
        local DATE_UNIX
        DATE_UNIX=$(date_rss_to_unix "$date")
        
        # Compare with our timestamp threshold
        if (( DATE_UNIX > UNIX_24H_AGO )); then
            result+=("- 📰 $title")
            if [[ "$LINKED" == true ]]; then
                if [[ "$FULL_URL" == true ]]; then
                    result+=("$link")
                else
                    result+=("$(cached_shorten_url "$link")")
                fi
            fi
        fi
    done < <(xmlstarlet sel -T -t -m "/rss/channel/item" \
              -v "pubDate" -n \
              -v "title" -n \
              -v "link" -n \
              <<< "$FEED_CONTENT" 2>/dev/null)
    
    # Output all results at once
    if [[ ${#result[@]} -gt 0 ]]; then
        printf "%s\n" "${result[@]}"
    fi
}

write_news() {
    local RSS_FEED=$1
    local LINKED=$2
    local SHOW_HEADER=$3
    local FULL_URL=$4
    local PORTAL
    PORTAL=$(echo "$RSS_FEED" | awk -F/ '{print $3}')

    local NEWS_OUTPUT
    NEWS_OUTPUT=$(get_news_RSS_combined "$RSS_FEED" "$LINKED" "$FULL_URL")

    if [[ -n "$NEWS_OUTPUT" ]]; then
        [[ "$SHOW_HEADER" == true ]] && echo "📰 $PORTAL 📰"
        echo "$NEWS_OUTPUT"
        echo ""
    fi
}

# Update help function with clearer instructions
help() {
    echo "Usage: ./rss.sh [options] [url]"
    echo "Options:"
    echo "  -h, --help      Show this help message and exit"
    echo "  -l, --linked    Show the news with URLs"
    echo "  -f, --full-url  Use full URLs instead of shortened ones (requires -l)"
    echo "  -n, --no-header Do not show the portal header"
    echo ""
    echo "Examples:"
    echo "  ./rss.sh -l <url>          # Show news with shortened URLs"
    echo "  ./rss.sh -l -f <url>       # Show news with full URLs"
}

get_arguments() {
    SHOW_HEADER=true
    FULL_URL=false
    LINKED=false
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                help
                exit 0
                ;;
            -l|--linked)
                LINKED=true
                ;;
            -f|--full-url)
                FULL_URL=true
                ;;
            -n|--no-header)
                SHOW_HEADER=false
                ;;
            *)
                FEED_URL="$1"
                ;;
        esac
        shift
    done

    # Check if -f is used without -l
    if [[ "$FULL_URL" == true && "$LINKED" == false ]]; then
        echo "Warning: -f/--full-url requires -l/--linked to show URLs"
        echo "Use -h or --help for usage examples"
        FULL_URL=false
    fi

    # Check if FEED_URL is empty
    if [[ -z "$FEED_URL" ]]; then
        echo "The feed URL was not specified"
        help
        exit 1
    fi
}

# Clean up function to reset locale when done
cleanup() {
    export LC_ALL=C
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Set trap to ensure cleanup
    trap EXIT
    
    get_arguments "$@"
    write_news "$FEED_URL" "$LINKED" "$SHOW_HEADER" "$FULL_URL"
fi