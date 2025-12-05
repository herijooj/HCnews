#!/usr/bin/env bash
RSS_DIR=$(dirname "$(realpath "${BASH_SOURCE[0]}")")

# Source the shortening script with proper path
source "$RSS_DIR/shortening.sh"

# Cache directory for URL shortening and RSS content
_rss_CACHE_DIR_BASE="$(dirname "$(dirname "${BASH_SOURCE[0]}")")/data/cache/rss"
# Ensure the base cache directory exists
[[ -d "$_rss_CACHE_DIR_BASE" ]] || mkdir -p "$_rss_CACHE_DIR_BASE"
_rss_URL_CACHE_DIR="${_rss_CACHE_DIR_BASE}/url_cache"
URL_CACHE_FILE="${_rss_URL_CACHE_DIR}/url_shorten_cache.txt"
CACHE_TTL_SECONDS=$((2 * 60 * 60)) # 2 hours for general RSS feeds
# Default cache behavior is enabled
_rss_USE_CACHE=true
# Force refresh cache
_rss_FORCE_REFRESH=false

# If sourced, parse arguments like --no-cache and --force
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    # _sourced_args captures arguments passed when sourced
    # (e.g. from hcnews.sh: source rss.sh --no-cache --force)
    declare -a _sourced_args=("${@}") 
    for arg in "${_sourced_args[@]}"; do
        case "$arg" in
            --no-cache)
                _rss_USE_CACHE=false
                ;;
            --force)
                _rss_FORCE_REFRESH=true
                ;;
        esac
    done
fi

[[ -d "$_rss_CACHE_DIR_BASE" ]] || mkdir -p "$_rss_CACHE_DIR_BASE"
[[ -d "$_rss_URL_CACHE_DIR" ]] || mkdir -p "$_rss_URL_CACHE_DIR"
touch "$URL_CACHE_FILE"

# Limit cache file size to prevent performance degradation
trim_cache_file() {
    local max_lines=1000
    local current_lines=$(wc -l < "$URL_CACHE_FILE")
    
    if (( current_lines > max_lines )); then
        tail -n $max_lines "$URL_CACHE_FILE" > "${URL_CACHE_FILE}.tmp"
        mv "${URL_CACHE_FILE}.tmp" "$URL_CACHE_FILE"
    fi
}

# Run cache trimming in background once at startup
(trim_cache_file &) >/dev/null 2>&1

# Get timestamp for 24 hours ago once
UNIX_24H_AGO=$(date -d "24 hours ago" +%s)

# Cache for date to unix conversions
declare -A DATE_CACHE

# Optimized function to convert RSS date to unix timestamp using a faster approach
date_rss_to_unix() {
    local date_str="$1"
    
    # Return from cache if available
    if [[ -n "${DATE_CACHE[$date_str]}" ]]; then
        echo "${DATE_CACHE[$date_str]}"
        return
    fi
    
    # Quick format check - if it doesn't look like a date, return 0
    if [[ -z "$date_str" || ! $date_str =~ ^[A-Za-z]+ ]]; then
        DATE_CACHE[$date_str]="0"
        echo "0"
        return
    fi
    
    # Use a faster date conversion with predefined format
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
    
    # Check if URL is in cache - use grep with pattern file for faster lookup
    if [[ -s "$URL_CACHE_FILE" ]]; then
        short_url=$(grep -m 1 -F "$url|" "$URL_CACHE_FILE" | cut -d'|' -f2)
    else
        short_url=""
    fi
    
    if [[ -z "$short_url" ]]; then
        # Not in cache, get a new shortened URL
        short_url=$(shorten_url_isgd "$url")
        # Add to cache - use append to avoid reading the whole file
        echo "$url|$short_url" >> "$URL_CACHE_FILE"
    fi
    
    echo "$short_url"
}

# Function to get today's date in YYYYMMDD format
get_date_format() {
    date +"%Y%m%d"
}

# Function to check if cache exists and is from today and within TTL
check_cache() {
    local cache_file_path="$1"
    if [ -f "$cache_file_path" ] && [ "$_rss_FORCE_REFRESH" = false ]; then
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
    local cache_dir
    cache_dir="$(dirname "$cache_file_path")"
    [[ -d "$cache_dir" ]] || mkdir -p "$cache_dir"
    echo "$content" > "$cache_file_path"
}

# Optimized news retrieval function with improved performance
get_news_RSS_combined() {
    local RSS_FEED=$1
    local LINKED=$2
    local FULL_URL=$3
    local portal_identifier # Will be set based on RSS_FEED
    local result=()

    # Generate a safe filename for the portal from the RSS_FEED URL
    portal_identifier=$(echo "$RSS_FEED" | sed -e 's|https*://||g' -e 's|/|__|g' -e 's|[^a-zA-Z0-9_.-]||g')
    local date_format
    date_format=$(get_date_format)
    
    # Create individual folder for each RSS feed
    local rss_cache_dir="${_rss_CACHE_DIR_BASE}/rss_feeds/${portal_identifier}"
    [[ -d "$rss_cache_dir" ]] || mkdir -p "$rss_cache_dir"
    local cache_file="${rss_cache_dir}/${date_format}.news"
    
    # Separate cache file for links when LINKED=true
    local links_cache_file="${rss_cache_dir}/${date_format}.links"

    # Check cache based on whether we need links or not
    local target_cache_file="$cache_file"
    if [[ "$LINKED" == true ]]; then
        target_cache_file="$links_cache_file"
    fi

    if [ "$_rss_USE_CACHE" = true ] && check_cache "$target_cache_file"; then
        read_cache "$target_cache_file"
        return
    fi
    
    # Fetch feed content with optimized curl options and timeout
    local FEED_CONTENT
    FEED_CONTENT=$(timeout 8s curl -s --max-time 6 --connect-timeout 2 --retry 1 --retry-delay 0 \
        --compressed -H "User-Agent: HCNews/1.0" "$RSS_FEED" 2>/dev/null)
    
    # Quick validation check - fail fast if invalid
    if [[ -z "$FEED_CONTENT" || "$FEED_CONTENT" != *"<item>"* ]]; then
        return
    fi
    
    # Use optimized xmlstarlet with timeout and error suppression
    local ALL_DATA
    ALL_DATA=$(timeout 5s xmlstarlet sel -T -t \
        -m "/rss/channel/item[position()<=20]" \
        -v "concat(pubDate,'|',title,'|',link)" -n \
        <<< "$FEED_CONTENT" 2>/dev/null)
    
    # Exit early if no data
    [[ -z "$ALL_DATA" ]] && return
    
    # Process all items in a single loop with optimized date handling
    local line_count=0
    while IFS='|' read -r date title link && [[ $line_count -lt 15 ]]; do
        [[ -z "$date" || -z "$title" ]] && continue
        
        # Optimized date check - use faster regex first
        if [[ "$date" =~ ^[A-Za-z]{3},.*[0-9]{4} ]]; then
            local DATE_UNIX
            DATE_UNIX=$(date_rss_to_unix "$date")
            
            # Compare with our timestamp threshold
            if (( DATE_UNIX > UNIX_24H_AGO )); then
                result+=("- $title")
                if [[ "$LINKED" == true ]]; then
                    if [[ "$FULL_URL" == true ]]; then
                        result+=("  🔗 $link")
                    else
                        # Use async URL shortening for better performance
                        local short_url
                        short_url=$(cached_shorten_url "$link")
                        result+=("  🔗 $short_url")
                    fi
                fi
                ((line_count++))
            fi
        fi
    done <<< "$ALL_DATA"
    
    # Build output efficiently
    local news_output=""
    if [[ ${#result[@]} -gt 0 ]]; then
        news_output=$(printf "%s\n" "${result[@]}")
    fi

    # Cache write using the appropriate cache file
    if [ "$_rss_USE_CACHE" = true ] && [[ -n "$news_output" ]]; then
        (write_cache "$target_cache_file" "$news_output") &
    fi
    
    echo "$news_output"
}

# Process multiple feed URLs in parallel
process_multiple_feeds() {
    local feeds=("$@")
    local pids=()
    local temp_files=()
    
    # Create temp directory for output
    local temp_dir=$(mktemp -d)
    
    for i in "${!feeds[@]}"; do
        local feed="${feeds[$i]}"
        local temp_file="${temp_dir}/feed_${i}.txt"
        temp_files+=("$temp_file")
        
        # Process each feed in background
        (
            local portal=$(echo "$feed" | awk -F/ '{print $3}')
            local news_output=$(get_news_RSS_combined "$feed" "$LINKED" "$FULL_URL")
            
            if [[ -n "$news_output" ]]; then
                [[ "$SHOW_HEADER" == true ]] && echo "📰 $portal:" > "$temp_file"
                echo "$news_output" >> "$temp_file"
                echo "" >> "$temp_file"
            fi
        ) &
        pids+=($!)
    done
    
    # Wait for all background processes to complete
    for pid in "${pids[@]}"; do
        wait "$pid"
    done
    
    # Combine and display results
    for temp_file in "${temp_files[@]}"; do
        if [[ -s "$temp_file" ]]; then
            cat "$temp_file"
        fi
    done
    
    # Clean up temp files
    rm -rf "$temp_dir"
}

write_news() {
    local RSS_FEED=$1
    local LINKED=$2
    local SHOW_HEADER=$3
    local FULL_URL=$4
    
    # Check if multiple feeds are provided (comma separated)
    if [[ "$RSS_FEED" == *","* ]]; then
        IFS=',' read -ra FEEDS <<< "$RSS_FEED"
        # When processing multiple feeds, caching is handled within get_news_RSS_combined for each feed
        process_multiple_feeds "${FEEDS[@]}"
    else
        local PORTAL
        PORTAL=$(echo "$RSS_FEED" | awk -F/ '{print $3}')

        # Caching is handled inside get_news_RSS_combined
        local NEWS_OUTPUT
        NEWS_OUTPUT=$(get_news_RSS_combined "$RSS_FEED" "$LINKED" "$FULL_URL")

        if [[ -n "$NEWS_OUTPUT" ]]; then
            [[ "$SHOW_HEADER" == true ]] && echo "📰 $PORTAL:"
            echo "$NEWS_OUTPUT"
            echo ""
        fi
    fi
}

# Update help function with clearer instructions
help() {
    echo "Usage: ./rss.sh [options] <url>"
    echo "Options:"
    echo "  -h, --help      Show this help message and exit"
    echo "  -l, --linked    Show the news with URLs"
    echo "  -f, --full-url  Use full URLs instead of shortened ones (requires -l)"
    echo "  -n, --no-header Do not show the portal header"
    echo "  --no-cache      Do not use cached data for this run"
    echo "  --force         Force refresh cache for this run"
    echo ""
    echo "Examples:"
    echo "  ./rss.sh -l <url>          # Show news with shortened URLs"
    echo "  ./rss.sh -l -f <url>       # Show news with full URLs"
    echo "  ./rss.sh -l 'url1,url2,url3'  # Process multiple feeds in parallel"
}

get_arguments() {
    SHOW_HEADER=true
    FULL_URL=false
    LINKED=false
    # Reset cache flags for this run, global defaults remain unless overridden here
    _rss_USE_CACHE_RUN=$_rss_USE_CACHE 
    _rss_FORCE_REFRESH_RUN=$_rss_FORCE_REFRESH

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
            --no-cache)
                _rss_USE_CACHE_RUN=false
                ;;
            --force)
                _rss_FORCE_REFRESH_RUN=true
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

    # Apply run-specific cache settings
    _rss_USE_CACHE=$_rss_USE_CACHE_RUN
    _rss_FORCE_REFRESH=$_rss_FORCE_REFRESH_RUN
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    get_arguments "$@"
    write_news "$FEED_URL" "$LINKED" "$SHOW_HEADER" "$FULL_URL"
fi