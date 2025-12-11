#!/usr/bin/env bash

# Source the main CLI script to get libraries and functions
SCRIPT_DIR=$(dirname "$(realpath "${BASH_SOURCE[0]}")")
source "$SCRIPT_DIR/hcnews.sh"

# Fetch common data once
fetch_newspaper_data

# Full URLs (show links and use full urls)
_hc_full_url_saved="$hc_full_url"
hc_full_url=true
# Generate news content for full variant
news_output=$(_rss_USE_CACHE=$_HCNEWS_USE_CACHE; _rss_FORCE_REFRESH=$_HCNEWS_FORCE_REFRESH; write_news "$all_feeds" true true ${hc_full_url})
content_full=$(render_output)

# Generate footer once for consistency
footer_content=$(footer)
content_full="${content_full}
${footer_content}"

hc_full_url="$_hc_full_url_saved"

# Short URLs (show links and use shortened urls)
hc_full_url=false
# Generate news content for short variant
news_output=$(_rss_USE_CACHE=$_HCNEWS_USE_CACHE; _rss_FORCE_REFRESH=$_HCNEWS_FORCE_REFRESH; write_news "$all_feeds" true true ${hc_full_url})
content_short=$(render_output)
content_short="${content_short}
${footer_content}"
hc_full_url="$_hc_full_url_saved"

reading_time_full=$(calculate_reading_time "$content_full")
reading_time_short=$(calculate_reading_time "$content_short")

# Write files
{
    write_header_with_reading_time "$reading_time_full"
    echo "$content_full" | sed '1,4d'
} > news_full.txt

{
    write_header_with_reading_time "$reading_time_short"
    echo "$content_short" | sed '1,4d'
} > news_short.txt
