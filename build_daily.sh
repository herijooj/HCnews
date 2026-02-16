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
"$SCRIPT_DIR/scripts/horoscopo.sh" --all >"$tmp_horoscopo_file" &
HOROSCOPO_PID=$!

echo "🌦️ Starting multi-city weather fetch..." >&2
tmp_weather_file="/tmp/weather_all_$$.txt"
"$SCRIPT_DIR/scripts/weather.sh" --all >"$tmp_weather_file" &
WEATHER_PID=$!

# 2. Fetch main newspaper data (Orchestrates its own jobs)
echo "📰 Fetching main newspaper data..." >&2
fetch_newspaper_data

# 3. Generate News Content (RSS)
_hc_full_url_saved="$hc_full_url"
hc_full_url=true
echo "🗞️ Generating RSS content..." >&2
news_output=$(
	_rss_USE_CACHE=$_HCNEWS_USE_CACHE
	_rss_FORCE_REFRESH=$_HCNEWS_FORCE_REFRESH
	hc_component_rss "$all_feeds" true true ${hc_full_url}
)

# 4. Assemble 'Tudo' content
content_tudo_body=$(render_output)
footer_content=$(footer)
content_tudo="${content_tudo_body}\n\n${footer_content}"

# 5. Assemble 'Notícias' content
content_noticias="${news_output}\n\n${footer_content}"

# 5b. Assemble 'Futebol' content (sports only, full list)
content_sports="$(HCNEWS_SPORTS_FILTER=ALL hc_component_sports)\n\n${footer_content}"

# 5c. Assemble 'Hacker News' content (latest 10 stories)
content_hackernews_body=$("$SCRIPT_DIR/scripts/hackernews.sh")
content_hackernews="${content_hackernews_body}\n\n${footer_content}"

# 5d. Assemble 'RU' content (today only)
content_ru_body="$ru_output"
if [[ -z "$content_ru_body" ]]; then
	content_ru_body="🍽️ *Cardápio RU*\n\nNão foi possível carregar o cardápio do RU agora."
fi
content_ru="${content_ru_body}\n\n${footer_content}"

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
reading_time_esportes=$(calculate_reading_time "$content_sports")
reading_time_hackernews=$(calculate_reading_time "$content_hackernews")
reading_time_ru=$(calculate_reading_time "$content_ru")
reading_time_horoscopo=$(calculate_reading_time "$content_horoscopo")
reading_time_weather=$(calculate_reading_time "$content_weather")

# Write files
mkdir -p public

{
	hc_render_header_with_reading_time "$reading_time_tudo"
	echo -e "$content_tudo" | sed '1,4d'
} >public/news_tudo.out

{
	hc_render_header_with_reading_time "$reading_time_noticias"
	echo ""
	echo -e "$content_noticias"
} >public/news_noticias.out

{
	hc_render_header_with_reading_time "$reading_time_esportes"
	echo ""
	echo -e "$content_sports"
} >public/news_esportes.out

{
	hc_render_header_with_reading_time "$reading_time_hackernews"
	echo ""
	echo -e "$content_hackernews"
} >public/news_hackernews.out

{
	hc_render_header_with_reading_time "$reading_time_ru"
	echo ""
	echo -e "$content_ru"
} >public/news_ru.out

{
	hc_render_header_with_reading_time "$reading_time_horoscopo"
	echo ""
	echo -e "$content_horoscopo"
} >public/news_horoscopo.out

{
	hc_render_header_with_reading_time "$reading_time_weather"
	echo ""
	echo -e "$content_weather"
} >public/news_weather.out

echo "✅ Build complete. Files: public/news_tudo.out, public/news_noticias.out, public/news_esportes.out, public/news_hackernews.out, public/news_ru.out, public/news_horoscopo.out, public/news_weather.out" >&2
