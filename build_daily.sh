#!/usr/bin/env bash

# Source the main CLI script to get libraries and functions
SCRIPT_DIR=$(dirname "$(realpath "${BASH_SOURCE[0]}")")
source "$SCRIPT_DIR/hcnews.sh"

# Fetch common data once
# Start main data fetch in background or parallel to horoscope?
# hcnews.sh functions use global variables, so running fetch_newspaper_data in background might be tricky if we need to access them here.
# But we can run the horoscope scripts in background!

# 1. Start Horoscope and Weather jobs (Backgrounded)
echo "🔮 Starting horoscope fetch (sequential)..." >&2
tmp_horoscopo_file="/tmp/horoscopo_all_$$.txt"
./scripts/horoscopo.sh --all > "$tmp_horoscopo_file" &
HOROSCOPO_PID=$!

echo "🌦️ Starting multi-city weather fetch..." >&2
tmp_weather_file="/tmp/weather_all_$$.txt"
./scripts/weather.sh --all > "$tmp_weather_file" &
WEATHER_PID=$!

# 2. Fetch main newspaper data (Orchestrates its own jobs)
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

# 7. Assemble 'Previsão do Tempo' content (weather + air quality)
echo "🌦️ Collecting weather results..." >&2
wait "$WEATHER_PID"
if [[ -f "$tmp_weather_file" ]]; then
    content_weather_body=$(cat "$tmp_weather_file")
    rm "$tmp_weather_file"
else
    content_weather_body="Erro ao buscar previsão do tempo."
fi
content_weather="${content_weather_body}\n\n${footer_content}"

# Restore globals
hc_full_url="$_hc_full_url_saved"

reading_time_tudo=$(calculate_reading_time "$content_tudo")
reading_time_noticias=$(calculate_reading_time "$content_noticias")
reading_time_horoscopo=$(calculate_reading_time "$content_horoscopo")
reading_time_weather=$(calculate_reading_time "$content_weather")

# Write files
{
    write_header_with_reading_time "$reading_time_tudo"
    echo -e "$content_tudo" | sed '1,4d'
} > news_tudo.out

{
    write_header_with_reading_time "$reading_time_noticias"
    echo ""
    echo -e "$content_noticias"
} > news_noticias.out

{
    write_header_with_reading_time "$reading_time_horoscopo"
    echo ""
    echo -e "$content_horoscopo"
} > news_horoscopo.out

{
    write_header_with_reading_time "$reading_time_weather"
    echo ""
    echo -e "$content_weather"
} > news_weather.out

echo "✅ Build complete. Files: news_tudo.out, news_noticias.out, news_horoscopo.out, news_weather.out" >&2

