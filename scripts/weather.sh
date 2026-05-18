#!/usr/bin/env bash
# =============================================================================
# Weather - OpenWeatherMap weather data fetcher
# =============================================================================
# Source: https://openweathermap.org/api
# Cache TTL: 10800 (3 hours)
# Output: Current weather and 3-day forecast with air quality data
# =============================================================================

# -----------------------------------------------------------------------------
# Source Common Library (ALWAYS FIRST after tokens)
# -----------------------------------------------------------------------------
[[ -n "${_HCNEWS_COMMON_LOADED:-}" ]] || source "${HCNEWS_COMMON_PATH}common.sh" 2>/dev/null || source "${BASH_SOURCE%/*}/lib/common.sh"

# -----------------------------------------------------------------------------
# Configuration Constants
# -----------------------------------------------------------------------------
CACHE_TTL_SECONDS="${HCNEWS_CACHE_TTL["weather"]:-10800}"

# -----------------------------------------------------------------------------
# Lookup Tables
# -----------------------------------------------------------------------------
declare -A WEATHER_EMOJIS=(
	["200"]="⛈️" ["201"]="⛈️" ["202"]="⛈️" ["210"]="⛈️" ["211"]="⛈️" ["212"]="⛈️"
	["221"]="⛈️" ["230"]="⛈️" ["231"]="⛈️" ["232"]="⛈️"
	["300"]="🌦️" ["301"]="🌦️" ["302"]="🌦️" ["310"]="🌦️" ["311"]="🌦️" ["312"]="🌦️"
	["313"]="🌦️" ["314"]="🌦️" ["321"]="🌦️"
	["500"]="🌧️" ["501"]="🌧️" ["502"]="🌧️" ["503"]="🌧️" ["504"]="🌧️" ["511"]="🌧️"
	["520"]="🌧️" ["521"]="🌧️" ["522"]="🌧️" ["531"]="🌧️"
	["600"]="❄️" ["601"]="❄️" ["602"]="❄️" ["611"]="❄️" ["612"]="❄️" ["613"]="❄️"
	["615"]="❄️" ["616"]="❄️" ["620"]="❄️" ["621"]="❄️" ["622"]="❄️"
	["701"]="🌫️" ["711"]="🌫️" ["721"]="🌫️" ["731"]="🌫️" ["741"]="🌫️" ["751"]="🌫️"
	["761"]="🌫️" ["762"]="🌫️" ["771"]="🌫️" ["781"]="🌫️"
	["800"]="☀️"
	["801"]="🌤️" ["802"]="⛅" ["803"]="☁️" ["804"]="☁️"
)

declare -A AQI_LEVELS=(
	["1"]="🟢 Bom"
	["2"]="🟡 Razoável"
	["3"]="🟠 Moderado"
	["4"]="🔴 Ruim"
	["5"]="🟣 Muito Ruim"
)

declare -A CITY_COORDS=(
	["curitiba"]="-25.4284,-49.2733"
	["sao_paulo"]="-23.5505,-46.6333"
	["rio_de_janeiro"]="-22.9068,-43.1729"
	["brasilia"]="-15.7942,-47.8825"
	["londrina"]="-23.3045,-51.1696"
	["florianopolis"]="-27.5969,-48.5495"
)

# -----------------------------------------------------------------------------
# Helper Functions
# -----------------------------------------------------------------------------
_round_up() {
	local num="$1"
	if [[ -z "$num" || ! "$num" =~ ^[0-9]*(\.)?[0-9]+$ ]]; then
		echo "0"
		return
	fi
	LC_ALL=C printf "%.0f" "$num"
}

# -----------------------------------------------------------------------------
# Data Fetching Function
# -----------------------------------------------------------------------------
get_weather_data() {
	local city="$1"
	local ttl="$CACHE_TTL_SECONDS"
	local use_cache="${_weather_USE_CACHE:-${_HCNEWS_USE_CACHE:-true}}"
	local force_refresh="${_weather_FORCE_REFRESH:-${_HCNEWS_FORCE_REFRESH:-false}}"
	local date_str
	date_str=$(hcnews_get_date_format)
	local cache_file
	hcnews_set_cache_path cache_file "weather" "$date_str" "$city"

	# Check cache first
	if [[ "$use_cache" == true ]] && hcnews_check_cache "$cache_file" "$ttl" "$force_refresh"; then
		hcnews_read_cache "$cache_file"
		return 0
	fi

	# Validate API key
	if [[ -z "${openweathermap_API_KEY:-}" ]]; then
		echo "🌦️ *Clima em $city:*"
		echo "- ⚠️ API key não configurada"
		return 1
	fi

	# Normalize city name
	local city_lower="${city,,}"
	local city_normalized="${city_lower// /_}"

	# Get city coordinates for air quality
	local coords="${CITY_COORDS[$city_lower]:-}"
	local lat lon
	if [[ -n "$coords" ]]; then
		IFS=',' read -r lat lon <<<"$coords"
	else
		lat="-25.4284"
		lon="-49.2733"
	fi

	# Build URLs
	local city_encoded
	city_encoded=$(printf '%s' "$city" | jq -sRr @uri 2>/dev/null || printf '%s' "${city// /%20}")
	local current_url="https://api.openweathermap.org/data/2.5/weather?q=${city_encoded}&appid=${openweathermap_API_KEY}&lang=pt_br&units=metric"
	local forecast_url="https://api.openweathermap.org/data/2.5/forecast?q=${city_encoded}&appid=${openweathermap_API_KEY}&lang=pt_br&units=metric"
	local air_url="https://api.openweathermap.org/data/2.5/air_pollution?lat=${lat}&lon=${lon}&appid=${openweathermap_API_KEY}"

	# Parallel API calls
	local tmp_dir="/dev/shm"
	[[ -d "$tmp_dir" && -w "$tmp_dir" ]] || tmp_dir="/tmp"
	local pid="${BASHPID:-$$}"
	local cur_file="${tmp_dir}/.weather_cur_${pid}_${city_normalized}"
	local fc_file="${tmp_dir}/.weather_fc_${pid}_${city_normalized}"
	local air_file="${tmp_dir}/.weather_air_${pid}_${city_normalized}"

	curl -s -4 -A "Mozilla/5.0" --compressed --connect-timeout 5 --max-time 10 "$current_url" >"$cur_file" &
	curl -s -4 -A "Mozilla/5.0" --compressed --connect-timeout 5 --max-time 10 "$forecast_url" >"$fc_file" &
	curl -s -4 -A "Mozilla/5.0" --compressed --connect-timeout 5 --max-time 10 "$air_url" >"$air_file" &
	wait

	local current_weather forecast_data air_data
	current_weather=$(<"$cur_file")
	forecast_data=$(<"$fc_file")
	air_data=$(<"$air_file")
	rm -f "$cur_file" "$fc_file" "$air_file"

	# Check if current weather request was successful
	if [[ $(echo "$current_weather" | jq -r '.cod' 2>/dev/null) != "200" ]]; then
		echo "🌦️ *Clima em $city:*"
		echo "- ⚠️ $(echo "$current_weather" | jq -r '.message' 2>/dev/null || echo 'Falha ao obter dados')"
		return 1
	fi

	# Get timestamp for day calculations
	local current_ts="${start_time:-$(date +%s)}"
	local d1_date d2_date d3_date
	d1_date=$(LC_ALL=C date -d "@$((current_ts + 86400))" +"%Y-%m-%d")
	d2_date=$(LC_ALL=C date -d "@$((current_ts + 172800))" +"%Y-%m-%d")
	d3_date=$(LC_ALL=C date -d "@$((current_ts + 259200))" +"%Y-%m-%d")

	# Parse all data with single jq call
	local all_data
	all_data=$(jq -r -n --argjson cur "$current_weather" --argjson fc "$forecast_data" \
		--arg d1 "$d1_date" --arg d2 "$d2_date" --arg d3 "$d3_date" '
        def day_stats($date):
            [$fc.list[] | select(.dt_txt | startswith($date))] |
            if length > 0 then
                [(.[].main.temp | floor)] as $temps |
                {
                    min: ($temps | min),
                    max: ($temps | max),
                    hum: (([.[].main.humidity] | add / length) | floor),
                    cond: ([.[].weather[0].id] | group_by(.) | max_by(length) | .[0])
                }
            else
                {min: "N/A", max: "N/A", hum: "N/A", cond: ""}
            end;
        day_stats($d1) as $day1 |
        day_stats($d2) as $day2 |
        day_stats($d3) as $day3 |
        [
            $cur.weather[0].description,
            $cur.weather[0].id,
            ($cur.main.temp | floor),
            ($cur.main.feels_like | floor),
            ($cur.main.temp_min | floor),
            ($cur.main.temp_max | floor),
            ($cur.main.humidity | floor),
            $cur.sys.sunrise,
            $cur.sys.sunset,
            $day1.min, $day1.max, $day1.hum, $day1.cond,
            $day2.min, $day2.max, $day2.hum, $day2.cond,
            $day3.min, $day3.max, $day3.hum, $day3.cond
        ] | map(tostring) | join("|")
    ')

	# Parse extracted data
	IFS='|' read -r condition condition_id temp feels_like temp_min temp_max humidity sunrise sunset \
		d1_min d1_max d1_hum d1_cond \
		d2_min d2_max d2_hum d2_cond \
		d3_min d3_max d3_hum d3_cond <<<"$all_data"

	# Format sunrise/sunset times
	local sunrise_time="N/A" sunset_time="N/A"
	[[ "$sunrise" =~ ^[0-9]+$ ]] && sunrise_time=$(LC_ALL=C date -d "@$sunrise" +"%H:%M" 2>/dev/null)
	[[ "$sunset" =~ ^[0-9]+$ ]] && sunset_time=$(LC_ALL=C date -d "@$sunset" +"%H:%M" 2>/dev/null)

	# Get weather emojis
	local cond_emoji="${WEATHER_EMOJIS[$condition_id]:-🌡️}"
	local d1_emoji="${WEATHER_EMOJIS[$d1_cond]:-🌡️}"
	local d2_emoji="${WEATHER_EMOJIS[$d2_cond]:-🌡️}"
	local d3_emoji="${WEATHER_EMOJIS[$d3_cond]:-🌡️}"

	# Day names
	local day_names=("Dom" "Seg" "Ter" "Qua" "Qui" "Sex" "Sáb")
	local base_dow
	base_dow=$(LC_ALL=C date -d "@$current_ts" +"%w")
	local d1_name="${day_names[$(((base_dow + 1) % 7))]}"
	local d2_name="${day_names[$(((base_dow + 2) % 7))]}"
	local d3_name="${day_names[$(((base_dow + 3) % 7))]}"

	# Parse air quality data
	local aqi aqi_level pm25
	aqi=$(echo "$air_data" | jq -r '.list[0].main.aqi // empty' 2>/dev/null)
	pm25=$(echo "$air_data" | jq -r '.list[0].components.pm2_5 // empty' 2>/dev/null)

	if [[ -n "$aqi" && "$aqi" =~ ^[1-5]$ ]]; then
		aqi_level="${AQI_LEVELS[$aqi]:-🔵 N/A}"
		if [[ -n "$pm25" && "$pm25" != "null" ]]; then
			pm25=$(LC_ALL=C printf "%.1f" "$pm25")
		else
			pm25="N/A"
		fi
	else
		aqi_level="🔵 N/A"
		pm25="N/A"
	fi

	# Build output
	local current_time="${current_time:-$(date +"%H:%M:%S")}"
	local output
	# shellcheck disable=SC2016
	printf -v output '🌦️ *Clima em %s:*
- %s %s
- 🌡️ `%s` °C
- ↗️ Máx: `%s` °C  ↘️ Mín: `%s` °C
- Sensação: `%s` °C  💧 `%s` %%
- 🌅 `%s`  🌇 `%s`
- 🌬️ Ar: %s (PM2.5: `%s` μg/m³)

🗓️ *Próximos Dias:*
- *%s:* %s `%s` °→ `%s` °C  💧 `%s` %%
- *%s:* %s `%s` °→ `%s` °C  💧 `%s` %%
- *%s:* %s `%s` °→ `%s` °C  💧 `%s` %%
_Fonte: OpenWeatherMap · Atualizado: %s_' \
		"$city" "$cond_emoji" "${condition^}" "$temp" "$temp_max" "$temp_min" \
		"$feels_like" "$humidity" "$sunrise_time" "$sunset_time" \
		"$aqi_level" "$pm25" \
		"$d1_name" "$d1_emoji" "$d1_min" "$d1_max" "$d1_hum" \
		"$d2_name" "$d2_emoji" "$d2_min" "$d2_max" "$d2_hum" \
		"$d3_name" "$d3_emoji" "$d3_min" "$d3_max" "$d3_hum" \
		"$current_time"

	# Save to cache if enabled
	if [[ "$use_cache" == true && -n "$output" ]]; then
		hcnews_write_cache "$cache_file" "$output"
	fi

	echo "$output"
}

# -----------------------------------------------------------------------------
# Output Function
# -----------------------------------------------------------------------------
hc_component_weather() {
	local city="${1:-Curitiba}"
	if ! get_weather_data "$city"; then
		return 1
	fi
}

# -----------------------------------------------------------------------------
# Multi-City Weather Output
# -----------------------------------------------------------------------------
hc_standalone_weather_all() {
	# Use configured cities or fallback to defaults
	local -a cities=()
	local weather_cities_decl
	weather_cities_decl="$(declare -p HCNEWS_WEATHER_CITIES 2>/dev/null || true)"

	if [[ "$weather_cities_decl" == declare\ -a* ]]; then
		cities=("${HCNEWS_WEATHER_CITIES[@]}")
	elif [[ -n "${HCNEWS_WEATHER_CITIES:-}" ]]; then
		cities=("${HCNEWS_WEATHER_CITIES}")
	else
		cities=("Curitiba" "São Paulo" "Rio de Janeiro" "Londrina" "Florianópolis")
	fi

	# Fetch all cities in parallel (OpenWeatherMap allows 60 calls/min on free tier)
	local tmp_dir="/tmp/hcnews_weather_$$"
	mkdir -p "$tmp_dir"

	for city in "${cities[@]}"; do
		(
			local data
			data=$(get_weather_data "$city")
			if [[ -n "$data" ]]; then
				echo "$data"
				echo ""
			fi
		) >"$tmp_dir/$city.txt" &
	done
	wait

	# Output in order
	for city in "${cities[@]}"; do
		cat "$tmp_dir/$city.txt" 2>/dev/null || true
	done

	rm -rf "$tmp_dir"
}

# -----------------------------------------------------------------------------
# Help Function
# -----------------------------------------------------------------------------
show_help() {
	echo "Usage: ./weather.sh [city] [options]"
	echo "The weather forecast will be printed to the console."
	echo "If city is empty, defaults to Curitiba."
	echo "Use --all for multiple cities."
	echo ""
	echo "Options:"
	echo "  -h, --help     Show this help message"
	echo "  --all          Fetch weather for all major cities"
	echo "  --no-cache     Bypass cache for this run"
	echo "  --force        Force refresh cached data"
}

# -----------------------------------------------------------------------------
# Main Entry Point
# -----------------------------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	hcnews_parse_args "$@"
	set -- "${_HCNEWS_REMAINING_ARGS[@]}"
	_weather_USE_CACHE=$_HCNEWS_USE_CACHE
	_weather_FORCE_REFRESH=$_HCNEWS_FORCE_REFRESH

	if [[ $# -gt 1 ]]; then
		echo "Invalid arguments: $*" >&2
		show_help
		exit 1
	fi

	if [[ "${1:-}" == "--all" ]]; then
		hc_standalone_weather_all
	else
		hc_component_weather "${1:-Curitiba}"
	fi
fi
