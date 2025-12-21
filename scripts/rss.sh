#!/usr/bin/env bash
RSS_DIR=$(dirname "$(realpath "${BASH_SOURCE[0]}")")

# Source the shortening script with proper path (but check if it's already sourced)
if [[ -z "$(type -t shorten_url_isgd)" ]]; then
    source "$RSS_DIR/shortening.sh"
fi

# Source common library
source "$RSS_DIR/lib/common.sh"

# Use centralized cache directory from common.sh if available, otherwise fallback
if [[ -z "${HCNEWS_CACHE_DIR:-}" ]]; then
    HCNEWS_CACHE_DIR="$(dirname "$(dirname "${BASH_SOURCE[0]}")")/data/cache"
fi

_rss_CACHE_DIR_BASE="${HCNEWS_CACHE_DIR}/rss"
_rss_URL_CACHE_DIR="${_rss_CACHE_DIR_BASE}/url_cache"
URL_CACHE_FILE="${_rss_URL_CACHE_DIR}/url_shorten_cache.txt"

# Use centralized TTL if available
CACHE_TTL_SECONDS="${HCNEWS_CACHE_TTL["rss"]:-7200}"

# Parse cache arguments using common helper
hcnews_parse_cache_args "$@"
_rss_USE_CACHE=$_HCNEWS_USE_CACHE
_rss_FORCE_REFRESH=$_HCNEWS_FORCE_REFRESH

# Ensure cache directories exist (handled by hcnews_init_cache_dirs in main, but good for standalone)
[[ -d "$_rss_CACHE_DIR_BASE" ]] || mkdir -p "$_rss_CACHE_DIR_BASE"
[[ -d "$_rss_URL_CACHE_DIR" ]] || mkdir -p "$_rss_URL_CACHE_DIR"
touch "$URL_CACHE_FILE"

# Limit cache file size to prevent performance degradation
trim_cache_file() {
    local max_lines=1000
    if [[ -f "$URL_CACHE_FILE" ]]; then
        local current_lines=$(wc -l < "$URL_CACHE_FILE")
        if (( current_lines > max_lines )); then
            tail -n $max_lines "$URL_CACHE_FILE" > "${URL_CACHE_FILE}.tmp"
            mv "${URL_CACHE_FILE}.tmp" "$URL_CACHE_FILE"
        fi
    fi
}

# Run cache trimming in background once at startup
(trim_cache_file &) >/dev/null 2>&1

# Get timestamp for 24 hours ago - use cached value from hcnews.sh if available
if [[ -n "$unix_24h_ago" ]]; then
    UNIX_24H_AGO="$unix_24h_ago"
else
    UNIX_24H_AGO=$(date -d "24 hours ago" +%s)
fi

# Cache for date to unix conversions
declare -A DATE_CACHE

# Optimized function to convert RSS date to unix timestamp using pure Bash
date_rss_to_unix() {
    local date_str="$1"
    
    # Return from cache if available
    [[ -n "${DATE_CACHE[$date_str]:-}" ]] && { echo "${DATE_CACHE[$date_str]}"; return; }
    
    # Quick format check - if it doesn't look like a date, return 0
    if [[ -z "$date_str" || ! $date_str =~ ^[A-Za-z,0-9\ ] ]]; then
        DATE_CACHE[$date_str]="0"
        echo "0"
        return
    fi
    
    # Pure Bash parsing for RFC 822/2822
    local day mon_name year hour min sec tz hms
    local temp_date="${date_str#*, }" # Remove day of week if present
    
    # Read components
    read -r day mon_name year hms tz <<< "$temp_date"
    
    # Split HH:MM:SS
    IFS=':' read -r hour min sec <<< "$hms"
    
    # Convert month name to number
    local mon
    case "${mon_name,,}" in
        jan) mon=1 ;; feb) mon=2 ;; mar) mon=3 ;; apr) mon=4 ;;
        may) mon=5 ;; jun) mon=6 ;; jul) mon=7 ;; aug) mon=8 ;;
        sep) mon=9 ;; oct) mon=10 ;; nov) mon=11 ;; dec) mon=12 ;;
        *) DATE_CACHE[$date_str]="0"; echo "0"; return ;;
    esac
    
    # Calculate days since epoch (1970-01-01)
    # This is a simplified Julian Day calculation approach
    local y=$((10#$year))
    local m=$((10#$mon))
    local d=$((10#$day))
    
    local years_since_epoch=$((y - 1970))
    local leap_days=$(((y - 1969) / 4 - (y - 1901) / 100 + (y - 1601) / 400))
    local total_days=$((years_since_epoch * 365 + leap_days))
    
    local month_days=(0 31 28 31 30 31 30 31 31 30 31 30 31)
    if (( (y % 4 == 0 && y % 100 != 0) || (y % 400 == 0) )); then
        month_days[2]=29
    fi
    for ((i=1; i<m; i++)); do
        total_days=$((total_days + month_days[i]))
    done
    total_days=$((total_days + d - 1))
    
    # Seconds
    hour=$((10#$hour))
    min=$((10#$min))
    sec=$((10#$sec))
    local timestamp=$((total_days * 86400 + hour * 3600 + min * 60 + sec))
    
    # Timezone adjustment
    if [[ -n "$tz" ]]; then
        if [[ "$tz" =~ ^[+-][0-9]{4}$ ]]; then
            local sign="${tz:0:1}"
            local tz_h=$((10#${tz:1:2}))
            local tz_m=$((10#${tz:3:2}))
            local offset=$((tz_h * 3600 + tz_m * 60))
            if [[ "$sign" == "+" ]]; then timestamp=$((timestamp - offset)); else timestamp=$((timestamp + offset)); fi
        elif [[ "$tz" != "GMT" && "$tz" != "UTC" && "$tz" != "Z" ]]; then
            # If unknown timezone name, fallback to date command just in case
            timestamp=$(date -d "$date_str" +%s 2>/dev/null || echo "0")
        fi
    fi
    
    DATE_CACHE[$date_str]="$timestamp"
    echo "$timestamp"
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
        if [[ -n "$short_url" ]]; then
            echo "$url|$short_url" >> "$URL_CACHE_FILE"
        fi
    fi
    
    echo "$short_url"
}

# Function to get today's date in YYYYMMDD format
get_date_format() {
    hcnews_get_date_format
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
    
    # Separate cache files for links
    local links_cache_file="${rss_cache_dir}/${date_format}.links"
    local links_full_cache_file="${rss_cache_dir}/${date_format}.links_full"

    # Check cache based on whether we need links or not
    local target_cache_file="$cache_file"
    if [[ "$LINKED" == true ]]; then
        if [[ "$FULL_URL" == true ]]; then
            target_cache_file="$links_full_cache_file"
        else
            target_cache_file="$links_cache_file"
        fi
    fi

    # Use centralized cache check
    if [ "$_rss_USE_CACHE" = true ] && hcnews_check_cache "$target_cache_file" "$CACHE_TTL_SECONDS" "$_rss_FORCE_REFRESH"; then
        hcnews_read_cache "$target_cache_file"
        return
    fi
    
    # Fetch feed content with optimized curl options and timeout
    local FEED_CONTENT
    FEED_CONTENT=$(timeout 8s curl -s -4 --connect-timeout 2 --max-time 6 --retry 1 --retry-delay 0 \
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
                # Title line
                result+=("- $title")
                if [[ "$LINKED" == true ]]; then
                    if [[ "$FULL_URL" == true ]]; then
                        result+=("    $link")
                    else
                        # Use async URL shortening for better performance
                        local short_url
                        short_url=$(cached_shorten_url "$link")
                        result+=("    $short_url")
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

    # Cache write using the appropriate cache file (using centralized function)
    if [ "$_rss_USE_CACHE" = true ] && [[ -n "$news_output" ]]; then
        (hcnews_write_cache "$target_cache_file" "$news_output") &
    fi
    
    echo "$news_output"
}

# Process multiple feed URLs in parallel (optimized for cached reads)
process_multiple_feeds() {
    # Expect: process_multiple_feeds <LINKED> <FULL_URL> <feed1> <feed2> ...
    local LOCAL_LINKED=$1
    local LOCAL_FULL_URL=$2
    shift 2
    local feeds=("$@")
    local pids=()
    # Store results in a map-like structure (using associative array if bash 4+, or just indexed array matching feeds)
    # Since bash 3 is common on some old systems, we'll use indexed array "results" corresponding to "feeds" indices.
    # We initialize results with empty strings.
    local results=()
    local cache_miss_indices=()
    local temp_dir="" # created only if needed

    local date_format
    date_format=$(get_date_format)
    
    # First pass: Check cache for all feeds
    for i in "${!feeds[@]}"; do
        local feed="${feeds[$i]}"
        # bash string manipulation instead of awk/sed
        local portal="${feed#*://}"
        portal="${portal%%/*}"
        
        # --- CACHE PRE-CHECK ---
        local portal_identifier="${feed#*://}"
        portal_identifier="${portal_identifier//\//__}"
        # Simple bash sanitization (remove purely invalid chars if needed, but for known feeds this is safe enough or we accept a tiny bit of noise)
        # To strictly match the sed 's|[^a-zA-Z0-9_.-]||g', we can use bash pattern replacement if extglob is on, 
        # but standard bash replacement //pattern/replacement only does literal string or simple glob.
        # For performance, we'll assume standard URL chars are fine as directory names or just keep it simple.
        # If strict sanitization is required, we can use tr (subshell) or keep sed but cache it? 
        # Actually, let's just stick to minimizing subshells.
        # But wait, checking the sed command: s|[^a-zA-Z0-9_.-]||g
        # We can implement a pure bash filter if we really want, but maybe just removing commonly problematic chars is enough.
        portal_identifier="${portal_identifier//:/}" 
        
        local rss_cache_dir="${_rss_CACHE_DIR_BASE}/rss_feeds/${portal_identifier}"
        local cache_file="${rss_cache_dir}/${date_format}.news"
        local links_cache_file="${rss_cache_dir}/${date_format}.links"
        local links_full_cache_file="${rss_cache_dir}/${date_format}.links_full"

        local target_cache_file="$cache_file"
        if [[ "$LOCAL_LINKED" == true ]]; then
            if [[ "$LOCAL_FULL_URL" == true ]]; then
                target_cache_file="$links_full_cache_file"
            else
                target_cache_file="$links_cache_file"
            fi
        fi
        
        # Try to read from cache
        if [ "$_rss_USE_CACHE" = true ] && hcnews_check_cache "$target_cache_file" "$CACHE_TTL_SECONDS" "$_rss_FORCE_REFRESH"; then
            # Cache HIT: Read into memory
            local cached_content
            cached_content=$(hcnews_read_cache "$target_cache_file" 2>/dev/null)
            if [[ -n "$cached_content" ]]; then
                results[$i]="$cached_content"
            fi
        else
            # Cache MISS
            cache_miss_indices+=("$i")
        fi
    done
    
    # Second pass: Launch background jobs ONLY for cache misses
    if [[ ${#cache_miss_indices[@]} -gt 0 ]]; then
        temp_dir=$(mktemp -d)
        
        for i in "${cache_miss_indices[@]}"; do
            local feed="${feeds[$i]}"
            local temp_file="${temp_dir}/feed_${i}.txt"
            
            (
                local news_output=$(get_news_RSS_combined "$feed" "$LOCAL_LINKED" "$LOCAL_FULL_URL")
                if [[ -n "$news_output" ]]; then
                    echo "$news_output" > "$temp_file"
                fi
            ) &
            pids+=($!)
        done
        
        # Wait for jobs
        for pid in "${pids[@]}"; do
            wait "$pid"
        done
        
        # Collect results from temp files
        for i in "${cache_miss_indices[@]}"; do
            local temp_file="${temp_dir}/feed_${i}.txt"
            if [[ -s "$temp_file" ]]; then
                results[$i]=$(<"$temp_file")
            fi
        done
        
        rm -rf "$temp_dir"
    fi
    
    # Output logic
    for i in "${!feeds[@]}"; do
        local feed="${feeds[$i]}"
        local content="${results[$i]}"
        
        if [[ -n "$content" ]]; then
            if [[ "$SHOW_HEADER" == true ]]; then
                local portal=$(echo "$feed" | awk -F/ '{print $3}')
                echo "📰 $portal:"
            fi
            echo "$content"
            echo ""
        fi
    done
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
        process_multiple_feeds "$LINKED" "$FULL_URL" "${FEEDS[@]}"
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