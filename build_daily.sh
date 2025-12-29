#!/usr/bin/env bash

# Source the main CLI script to get libraries and functions
SCRIPT_DIR=$(dirname "$(realpath "${BASH_SOURCE[0]}")")
source "$SCRIPT_DIR/hcnews.sh"

# Fetch common data once
# Start main data fetch in background or parallel to horoscope?
# hcnews.sh functions use global variables, so running fetch_newspaper_data in background might be tricky if we need to access them here.
# But we can run the horoscope scripts in background!

# 1. Start Horoscope and Air Quality jobs (Backgrounded)
echo "🔮 Starting horoscope fetch (sequential)..." >&2
tmp_horoscopo_file="/tmp/horoscopo_all_$$.txt"
./scripts/horoscopo.sh > "$tmp_horoscopo_file" &
HOROSCOPO_PID=$!

echo "🌬️ Starting multi-city air quality fetch..." >&2
tmp_airquality_file="/tmp/airquality_all_$$.txt"
./scripts/airquality.sh > "$tmp_airquality_file" &
AIRQUALITY_PID=$!

# 2. Fetch main newspaper data (Orchestrates its own jobs, including Curitiba air quality)
echo "📰 Fetching main newspaper data..." >&2
fetch_newspaper_data

# 3. Generate News Content (RSS)
_hc_full_url_saved="$hc_full_url"
hc_full_url=true
echo "🗞️ Generating RSS content..." >&2
news_output=$(_rss_USE_CACHE=$_HCNEWS_USE_CACHE; _rss_FORCE_REFRESH=$_HCNEWS_FORCE_REFRESH; write_news "$all_feeds" true true ${hc_full_url})

# 4. Assemble 'Tudo' content
content_tudo_body=$(render_output)
footer_content=$(footer)
content_tudo="${content_tudo_body}\n\n${footer_content}"

# 5. Assemble 'Notícias' content
content_noticias="${news_output}\n\n${footer_content}"


# 6. Assemble 'Horóscopo' content
echo "🔮 Collecting horoscope results..." >&2
wait "$HOROSCOPO_PID"
if [[ -f "$tmp_horoscopo_file" ]]; then
    content_horoscopo_body=$(cat "$tmp_horoscopo_file")
    rm "$tmp_horoscopo_file"
else
    content_horoscopo_body="Erro ao buscar horóscopo."
fi
content_horoscopo="${content_horoscopo_body}\n\n${footer_content}"

# 7. Assemble 'Qualidade do Ar' content
echo "🌬️ Collecting air quality results..." >&2
wait "$AIRQUALITY_PID"
if [[ -f "$tmp_airquality_file" ]]; then
    content_airquality_body=$(cat "$tmp_airquality_file")
    rm "$tmp_airquality_file"
else
    content_airquality_body="Erro ao buscar qualidade do ar."
fi
content_airquality="${content_airquality_body}\n\n${footer_content}"

# Restore globals
hc_full_url="$_hc_full_url_saved"

reading_time_tudo=$(calculate_reading_time "$content_tudo")
reading_time_noticias=$(calculate_reading_time "$content_noticias")
reading_time_horoscopo=$(calculate_reading_time "$content_horoscopo")
reading_time_airquality=$(calculate_reading_time "$content_airquality")

# Write files
{
    write_header_with_reading_time "$reading_time_tudo"
    echo -e "$content_tudo" | sed '1,4d'
} > news_tudo.txt

{
    write_header_with_reading_time "$reading_time_noticias"
    echo ""
    echo -e "$content_noticias"
} > news_noticias.txt

{
    write_header_with_reading_time "$reading_time_horoscopo"
    echo ""
    echo -e "$content_horoscopo" 
} > news_horoscopo.txt

{
    write_header_with_reading_time "$reading_time_airquality"
    echo ""
    echo -e "$content_airquality"
} > news_airquality.txt

echo "✅ Build complete. Files: news_tudo.txt, news_noticias.txt, news_horoscopo.txt, news_airquality.txt" >&2
