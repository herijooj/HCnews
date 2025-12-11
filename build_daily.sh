#!/usr/bin/env bash

# Source the main CLI script to get libraries and functions
SCRIPT_DIR=$(dirname "$(realpath "${BASH_SOURCE[0]}")")
source "$SCRIPT_DIR/hcnews.sh"

# Fetch common data once
# Start main data fetch in background or parallel to horoscope?
# hcnews.sh functions use global variables, so running fetch_newspaper_data in background might be tricky if we need to access them here.
# But we can run the horoscope scripts in background!

# 1. Start Horoscope job (Sequential internally, but backgrounded)
# We use the new --marked flag to get the full formatted list in one go
# This is slower than parallel but safer against rate limits (403 Forbidden)
echo "🔮 Starting horoscope fetch (sequential)..." >&2
tmp_horoscopo_file="/tmp/horoscopo_all_$$.txt"
./scripts/horoscopo.sh > "$tmp_horoscopo_file" &
HOROSCOPO_PID=$!

# 2. Fetch main newspaper data (Synchronously for now, as it orchestrates its own jobs)
echo "📰 Fetching main newspaper data..." >&2
fetch_newspaper_data

# 3. Generate News Content (RSS)
# Full URLs (show links and use full urls)
_hc_full_url_saved="$hc_full_url"
hc_full_url=true

# Generate RSS news content
# We need this for 'Tudo' and 'Notícias'
echo "🗞️ Generating RSS content..." >&2
news_output=$(_rss_USE_CACHE=$_HCNEWS_USE_CACHE; _rss_FORCE_REFRESH=$_HCNEWS_FORCE_REFRESH; write_news "$all_feeds" true true ${hc_full_url})

# 4. Assemble 'Tudo' content (Everything EXCEPT the detailed horoscope list we just fetched)
# The 'render_output' function in hcnews.sh includes everything in global vars.
# We need to ensure 'news_output' is set.
content_tudo_body=$(render_output)

# Footer
footer_content=$(footer)

# Combine for 'Tudo'
content_tudo="${content_tudo_body}

${footer_content}"

# 5. Assemble 'Notícias' content
content_noticias="${news_output}

${footer_content}"


# 6. Assemble 'Horóscopo' content
echo "🔮 Collecting horoscope results..." >&2
wait "$HOROSCOPO_PID"

if [[ -f "$tmp_horoscopo_file" ]]; then
    content_horoscopo_body=$(cat "$tmp_horoscopo_file")
    rm "$tmp_horoscopo_file"
else
    content_horoscopo_body="Erro ao buscar horóscopo."
fi

content_horoscopo="${content_horoscopo_body}

${footer_content}"

# Restore globals
hc_full_url="$_hc_full_url_saved"

reading_time_tudo=$(calculate_reading_time "$content_tudo")
reading_time_noticias=$(calculate_reading_time "$content_noticias")
# Reading time for horoscope is tricky, sum of all? Or average?
# Let's just calculate total text.
reading_time_horoscopo=$(calculate_reading_time "$content_horoscopo")

# Write files
{
    write_header_with_reading_time "$reading_time_tudo"
    echo "$content_tudo" | sed '1,4d'
} > news_tudo.txt

{
    write_header_with_reading_time "$reading_time_noticias"
    echo ""
    echo "$content_noticias"
} > news_noticias.txt

{
    # Custom header for horoscope? Or standard?
    # Standard header is fine.
    write_header_with_reading_time "$reading_time_horoscopo"
    echo ""
    echo "$content_horoscopo" 
} > news_horoscopo.txt

echo "✅ Build complete. Files: news_tudo.txt, news_noticias.txt, news_horoscopo.txt" >&2
