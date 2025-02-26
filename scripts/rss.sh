#!/usr/bin/env bash
SCRIPT_DIR=$(dirname "$0")

source "$SCRIPT_DIR/scripts/shortening.sh"

# Add this new function to validate RSS dates
is_valid_rss_date() {
    local date_str="$1"
    # Check if the date string matches RFC 2822 format
    [[ $date_str =~ ^[A-Za-z]{3},\ [0-9]{2}\ [A-Za-z]{3}\ [0-9]{4}\ [0-9]{2}:[0-9]{2}:[0-9]{2} ]] || return 1
    return 0
}

# this function converts a date in RSS format to unix
# RFC 2822 example: Fri, 03 Feb 2023 16:00:00 +0000
date_rss_to_unix () {

    local DATE_RSS="$1"
    
    # Validate date format first
    if ! is_valid_rss_date "$DATE_RSS"; then
        echo "0"
        return
    fi

    # change the locale to en_US
    export LC_ALL=en_US.UTF-8

    # get the date in RSS format
    DATE_RSS=$1

    # convert the date to unix
    DATE_UNIX=$(date -d "$DATE_RSS" +%s 2>/dev/null || echo "0")

    # change the locale back to normal
    export LC_ALL=C


    # return the date in unix
    echo "$DATE_UNIX"
}

# this function returns the date from 24 hours ago in RFC 2822
# example: Fri, 03 Feb 2023 16:00:00 +0000
get_date_24_hours_rss () {
    export LC_ALL=en_US.UTF-8

    # get the date in RFC 2822
    DATE_RSS=$(date -R -d "24 hours ago")
    export LC_ALL=C

    # return the date in RFC 2822
    echo "$DATE_RSS"
}

# this function compares two dates in RSS format
# returns 1 if the first date is greater than the second
# returns 0 if the first date is less than the second
compare_dates_rss () {

    local DATE_1="$1"
    local DATE_2="$2"

    local DATE_1_UNIX
    local DATE_2_UNIX
    
    DATE_1_UNIX=$(date_rss_to_unix "$DATE_1")
    DATE_2_UNIX=$(date_rss_to_unix "$DATE_2")

    # If either date is invalid (returns 0), treat as older
    if [ "$DATE_1_UNIX" -eq 0 ] || [ "$DATE_2_UNIX" -eq 0 ]; then
        echo 0
        return
    fi

    # compare the dates
    if [ "$DATE_1_UNIX" -gt "$DATE_2_UNIX" ]; then
        echo 1
    else
        echo 0
    fi
}

# Replace both get_news_RSS and get_news_RSS_linked with a single function
get_news_RSS_combined() {
    local RSS_FEED=$1
    local LINKED=$2

    export LC_ALL=en_US.UTF-8
    local TIMESTAMP
    TIMESTAMP=$(get_date_24_hours_rss)
    export LC_ALL=C

    local FEED_CONTENT
    FEED_CONTENT=$(curl -s "$RSS_FEED")
    if ! echo "$FEED_CONTENT" | xmlstarlet val - >/dev/null 2>&1; then
        return
    fi

    local NEWS
    NEWS=$(echo "$FEED_CONTENT" | xmlstarlet sel -t -m "/rss/channel/item" -v "pubDate" -o "|" -v "title" -o "|" -v "link" -n)
    [ -z "$NEWS" ] && return

    while read -r line; do
        local DATE
        local TITLE
        local LINK
        DATE=$(echo "$line" | cut -d "|" -f 1)
        TITLE=$(echo "$line" | cut -d "|" -f 2)
        LINK=$(echo "$line" | cut -d "|" -f 3)

        if [ "$(compare_dates_rss "$DATE" "$TIMESTAMP")" -eq 1 ]; then
            echo "📰 $TITLE"
            if [ "$LINKED" = true ]; then
                echo "$(shorten_url_isgd "$LINK")"
            fi
        fi
    done <<< "$NEWS"
}

write_news() {
    local RSS_FEED=$1
    local LINKED=$2
    local SHOW_HEADER=$3
    local PORTAL
    PORTAL=$(echo "$RSS_FEED" | cut -d "/" -f 3)

    local NEWS_OUTPUT
    NEWS_OUTPUT=$(get_news_RSS_combined "$RSS_FEED" "$LINKED")

    if [ -n "$NEWS_OUTPUT" ]; then
        if [ "$SHOW_HEADER" = true ]; then
            echo "📰 $PORTAL 📰"
        fi
        echo "$NEWS_OUTPUT"
        echo ""
    fi
}

# -------------------------------- Running locally --------------------------------

# help function
# Usage: ./rss.sh [options]
# Options:
#   -h, --help      Show this help message and exit
#   -l, --linked    Show the news with the shortened URL
#   -n, --no-header Do not show the portal header
help () {
    echo "Usage: ./rss.sh [options] [url]"
    echo "Options:"
    echo "  -h, --help      Show this help message and exit"
    echo "  -l, --linked    Show the news with the shortened URL"
    echo "  -n, --no-header Do not show the portal header"
}

# this function will receive the arguments, and throw an error if the URL is not valid
get_arguments () {
    SHOW_HEADER=true
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                help
                exit 0
                ;;
            -l|--linked)
                LINKED=true
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

    # Check if FEED_URL is empty
    if [ -z "$FEED_URL" ]; then
        echo "The feed URL was not specified"
        help
        exit 1
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # run the script
    get_arguments "$@"
    write_news "$FEED_URL" "$LINKED" "$SHOW_HEADER"
fi