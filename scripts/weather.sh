#!/bin/bash

# Source tokens.sh if it exists, to load API keys locally.
# In CI/CD, secrets are passed as environment variables.
if [ -f "tokens.sh" ]; then
    source tokens.sh
elif [ -f "$(dirname "${BASH_SOURCE[0]}")/../tokens.sh" ]; then
    source "$(dirname "${BASH_SOURCE[0]}")/../tokens.sh"
fi

# Check for telegram flag
FOR_TELEGRAM=false
if [[ "$@" == *"--telegram"* ]]; then
    FOR_TELEGRAM=true
    # Remove the --telegram flag from arguments
    set -- "${@/--telegram/}"
fi

# Cache directory - use the same directory as ru.sh
CACHE_DIR="$(dirname "$(dirname "${BASH_SOURCE[0]}")")/data/cache/weather"
# Ensure the cache directory exists
[[ -d "$CACHE_DIR" ]] || mkdir -p "$CACHE_DIR"
CACHE_TTL_SECONDS=$((3 * 60 * 60)) # 3 hours

# Default cache behavior is enabled
_weather_USE_CACHE=true
# Force refresh cache
_weather_FORCE_REFRESH=false

# Override defaults if --no-cache or --force is passed during sourcing
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then # Check if sourced
    _current_sourcing_args_for_weather=("${@}") 
    for arg in "${_current_sourcing_args_for_weather[@]}"; do
      case "$arg" in
        --no-cache)
          _weather_USE_CACHE=false
          ;;
        --force)
          _weather_FORCE_REFRESH=true
          ;;
      esac
    done
fi

# Weather emoji lookup table (faster than case statement)
declare -A WEATHER_EMOJIS=(
    # Thunderstorm (200-232)
    ["200"]="⛈️" ["201"]="⛈️" ["202"]="⛈️" ["210"]="⛈️" ["211"]="⛈️" ["212"]="⛈️" 
    ["221"]="⛈️" ["230"]="⛈️" ["231"]="⛈️" ["232"]="⛈️"
    # Drizzle (300-321)
    ["300"]="🌦️" ["301"]="🌦️" ["302"]="🌦️" ["310"]="🌦️" ["311"]="🌦️" ["312"]="🌦️" 
    ["313"]="🌦️" ["314"]="🌦️" ["321"]="🌦️"
    # Rain (500-531)
    ["500"]="🌧️" ["501"]="🌧️" ["502"]="🌧️" ["503"]="🌧️" ["504"]="🌧️" ["511"]="🌧️" 
    ["520"]="🌧️" ["521"]="🌧️" ["522"]="🌧️" ["531"]="🌧️"
    # Snow (600-622)
    ["600"]="❄️" ["601"]="❄️" ["602"]="❄️" ["611"]="❄️" ["612"]="❄️" ["613"]="❄️" 
    ["615"]="❄️" ["616"]="❄️" ["620"]="❄️" ["621"]="❄️" ["622"]="❄️"
    # Atmosphere (701-781)
    ["701"]="🌫️" ["711"]="🌫️" ["721"]="🌫️" ["731"]="🌫️" ["741"]="🌫️" ["751"]="🌫️" 
    ["761"]="🌫️" ["762"]="🌫️" ["771"]="🌫️" ["781"]="🌫️"
    # Clear (800)
    ["800"]="☀️"
    # Clouds (801-804)
    ["801"]="🌤️" ["802"]="⛅" ["803"]="☁️" ["804"]="☁️"
)

# Day name translation lookup table (faster than case statement in loops)
declare -A DAY_NAMES=(
    ["monday"]="Segunda-feira"
    ["tuesday"]="Terça-feira"
    ["wednesday"]="Quarta-feira"
    ["thursday"]="Quinta-feira"
    ["friday"]="Sexta-feira"
    ["saturday"]="Sábado"
    ["sunday"]="Domingo"
)

# Use cached date from main script if available, otherwise compute
function get_date_format() {
    if [[ -n "$date_format" ]]; then
        echo "$date_format"
    else
        date +"%Y%m%d"
    fi
}

# Function to check if cache exists and is from today and within TTL
function check_cache() {
    local cache_file_path="$1"
    
    if [ -f "$cache_file_path" ] && [ "$_weather_FORCE_REFRESH" = false ]; then
        # Check TTL
        local file_mod_time
        file_mod_time=$(stat -c %Y "$cache_file_path")
        local current_time
        # Use cached start_time if available, otherwise fall back to date command
        if [[ -n "$start_time" ]]; then
            current_time="$start_time"
        else
            current_time=$(date +%s)
        fi
        if (( (current_time - file_mod_time) < CACHE_TTL_SECONDS )); then
            # Cache exists, not forced, and within TTL
            return 0
        fi
    fi
    return 1
}

# Function to read weather from cache
function read_cache() {
    local cache_file_path="$1"
    cat "$cache_file_path"
}

# Function to write weather to cache
function write_cache() {
    local cache_file_path="$1"
    local weather_data="$2"
    local cache_dir
    cache_dir="$(dirname "$cache_file_path")"
    
    # Ensure the directory exists
    [[ -d "$cache_dir" ]] || mkdir -p "$cache_dir"
    
    # Write weather to cache file
    echo "$weather_data" > "$cache_file_path"
}

# Get weather emoji (faster lookup from array)
function get_weather_emoji() {
    local id="$1"
    echo "${WEATHER_EMOJIS[$id]:-🌡️}"
}

# Round up function (avoid spawning awk process repeatedly)
function round_up() {
    local num="$1"
    # Handle empty or non-numeric values
    if [[ -z "$num" || ! "$num" =~ ^[0-9]*(\.)?[0-9]+$ ]]; then
        echo "0"
        return
    fi
    
    # Force use of C locale to ensure decimal point is handled correctly
    LC_ALL=C printf "%.0f" "$num"
}

# Function to get weather from OpenWeatherMap with formatted output
function get_weather() {
    local CITY="$1"
    local LANG="pt_br"
    local UNITS="metric"
    local NORMALIZED_CITY
    NORMALIZED_CITY=$(echo "$CITY" | tr '[:upper:]' '[:lower:]' | tr ' ' '_') # Normalize city name for cache key
    local date_format
    date_format=$(get_date_format)
    local cache_file="${CACHE_DIR}/${date_format}_${NORMALIZED_CITY}.weather"
    
    # Check if cache exists and should be used
    if [ "$_weather_USE_CACHE" = true ] && check_cache "$cache_file"; then
        read_cache "$cache_file"
        return
    fi
    
    # TWO parallel API calls (free tier doesn't have a single endpoint with all data)
    # But we optimize by: using /dev/shm, parallel requests, and single jq parse each
    local CURRENT_WEATHER_URL="https://api.openweathermap.org/data/2.5/weather?q=${CITY}&appid=${openweathermap_API_KEY}&lang=${LANG}&units=${UNITS}"
    local FORECAST_URL="https://api.openweathermap.org/data/2.5/forecast?q=${CITY}&appid=${openweathermap_API_KEY}&lang=${LANG}&units=${UNITS}"
    
    # Use /dev/shm (RAM-backed tmpfs) for faster temp file I/O
    local tmp_dir="/dev/shm"
    [[ -d "$tmp_dir" && -w "$tmp_dir" ]] || tmp_dir="/tmp"
    local current_temp="${tmp_dir}/.weather_cur_$$"
    local forecast_temp="${tmp_dir}/.weather_fc_$$"
    
    # Parallel curl requests
    curl -s "$CURRENT_WEATHER_URL" > "$current_temp" &
    curl -s "$FORECAST_URL" > "$forecast_temp" &
    wait
    
    local CURRENT_WEATHER FORECAST_DATA
    CURRENT_WEATHER=$(<"$current_temp")
    FORECAST_DATA=$(<"$forecast_temp")
    rm -f "$current_temp" "$forecast_temp"
    
    # Check if current weather request was successful
    if [[ $(echo "$CURRENT_WEATHER" | jq -r '.cod' 2>/dev/null) != "200" ]]; then
        echo "Error: $(echo "$CURRENT_WEATHER" | jq -r '.message' 2>/dev/null || echo "Failed to get weather data")"
        return 1
    fi
    
    # Get current timestamp for day calculations
    local CURRENT_DATE_TS
    if [[ -n "$start_time" ]]; then
        CURRENT_DATE_TS="$start_time"
    else
        CURRENT_DATE_TS=$(date +%s)
    fi
    
    # Compute the 3 future dates once
    local D1_DATE D2_DATE D3_DATE
    D1_DATE=$(LC_ALL=C date -d "@$((CURRENT_DATE_TS + 86400))" +"%Y-%m-%d")
    D2_DATE=$(LC_ALL=C date -d "@$((CURRENT_DATE_TS + 172800))" +"%Y-%m-%d")
    D3_DATE=$(LC_ALL=C date -d "@$((CURRENT_DATE_TS + 259200))" +"%Y-%m-%d")
    
    # SINGLE jq call to extract current weather + process all 3 days of forecast
    # The forecast API returns 3-hour intervals; we find min/max per day
    local ALL_DATA
    ALL_DATA=$(jq -r -n --argjson cur "$CURRENT_WEATHER" --argjson fc "$FORECAST_DATA" --arg d1 "$D1_DATE" --arg d2 "$D2_DATE" --arg d3 "$D3_DATE" '
        # Helper to get day stats
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
            # Current weather
            $cur.weather[0].description,
            $cur.weather[0].id,
            ($cur.main.temp | floor),
            ($cur.main.feels_like | floor),
            ($cur.main.temp_min | floor),
            ($cur.main.temp_max | floor),
            ($cur.main.humidity | floor),
            $cur.sys.sunrise,
            $cur.sys.sunset,
            # Day 1
            $day1.min, $day1.max, $day1.hum, $day1.cond,
            # Day 2
            $day2.min, $day2.max, $day2.hum, $day2.cond,
            # Day 3
            $day3.min, $day3.max, $day3.hum, $day3.cond
        ] | map(tostring) | join("|")
    ')
    
    # Parse all data at once
    IFS='|' read -r CONDITION CONDITION_ID TEMP FEELS_LIKE TEMP_MIN TEMP_MAX HUMIDITY SUNRISE SUNSET \
        D1_MIN D1_MAX D1_HUM D1_COND \
        D2_MIN D2_MAX D2_HUM D2_COND \
        D3_MIN D3_MAX D3_HUM D3_COND <<< "$ALL_DATA"
    
    # Format sunrise/sunset times
    local SUNRISE_TIME="N/A"
    local SUNSET_TIME="N/A"
    [[ "$SUNRISE" =~ ^[0-9]+$ ]] && SUNRISE_TIME=$(LC_ALL=C date -d "@$SUNRISE" +"%H:%M" 2>/dev/null || echo "N/A")
    [[ "$SUNSET" =~ ^[0-9]+$ ]] && SUNSET_TIME=$(LC_ALL=C date -d "@$SUNSET" +"%H:%M" 2>/dev/null || echo "N/A")
    
    # Get emojis using lookup table (no subshells)
    local CONDITION_EMOJI="${WEATHER_EMOJIS[$CONDITION_ID]:-🌡️}"
    local D1_EMOJI="${WEATHER_EMOJIS[$D1_COND]:-🌡️}"
    local D2_EMOJI="${WEATHER_EMOJIS[$D2_COND]:-🌡️}"
    local D3_EMOJI="${WEATHER_EMOJIS[$D3_COND]:-🌡️}"
    
    # Compute day names using modular arithmetic (single date call for base)
    local DAY_NAMES_SHORT=("Dom" "Seg" "Ter" "Qua" "Qui" "Sex" "Sáb")
    local base_dow
    base_dow=$(LC_ALL=C date -d "@$CURRENT_DATE_TS" +"%w")
    local D1_NAME="${DAY_NAMES_SHORT[$(( (base_dow + 1) % 7 ))]}"
    local D2_NAME="${DAY_NAMES_SHORT[$(( (base_dow + 2) % 7 ))]}"
    local D3_NAME="${DAY_NAMES_SHORT[$(( (base_dow + 3) % 7 ))]}"
    
    # Timestamp
    local CURRENT_TIME="${current_time:-$(date +"%H:%M:%S")}"
    
    # Build output with single printf
    local OUTPUT
    printf -v OUTPUT '🌦️ *Clima em %s:*
- %s _%s_
- 🌡️ `%s` °C
- ↗️ Máx: `%s` °C  ↘️ Mín: `%s` °C
- Sensação: `%s` °C  💧 `%s` %%
- 🌅 `%s`  🌇 `%s`

🗓️ *Próximos Dias:*
- *%s:* %s `%s` °→ `%s` °C  💧 `%s` %%
- *%s:* %s `%s` °→ `%s` °C  💧 `%s` %%
- *%s:* %s `%s` °→ `%s` °C  💧 `%s` %%
_Fonte: OpenWeatherMap · Atualizado: %s_' \
        "$CITY" "$CONDITION_EMOJI" "${CONDITION^}" "$TEMP" "$TEMP_MAX" "$TEMP_MIN" \
        "$FEELS_LIKE" "$HUMIDITY" "$SUNRISE_TIME" "$SUNSET_TIME" \
        "$D1_NAME" "$D1_EMOJI" "$D1_MIN" "$D1_MAX" "$D1_HUM" \
        "$D2_NAME" "$D2_EMOJI" "$D2_MIN" "$D2_MAX" "$D2_HUM" \
        "$D3_NAME" "$D3_EMOJI" "$D3_MIN" "$D3_MAX" "$D3_HUM" \
        "$CURRENT_TIME"
    
    # Save to cache if enabled
    if [ "$_weather_USE_CACHE" = true ]; then
        write_cache "$cache_file" "$OUTPUT"
    fi
    
    echo "$OUTPUT"
}

# Function to write weather information
function write_weather() {
    CITY="$1"
    TERMINAL="${2:-true}"  # Default to true for terminal output
    
    # Ensure we have a city name, using Curitiba as default if empty
    if [[ -z "$CITY" ]]; then
        CITY="Curitiba"
    fi
    
    # Get weather data
    WEATHER=$(get_weather "$CITY")
    exit_code=$?
    
    if [[ $exit_code -ne 0 ]]; then
        echo "Error getting weather data: $WEATHER"
        return $exit_code
    fi
    
    # Output based on format
    if [[ "$FOR_TELEGRAM" == "true" ]]; then
        # For Telegram, we keep the markdown formatting
        echo "$WEATHER"
    else
        # For terminal output, display correctly with newlines
        echo -e "$WEATHER"
        echo ""
    fi
}

# Help function
function help () {
    echo "Usage: ./weather.sh [City] [options]"
    echo "The command will be printed to the console."
    echo "If the city is empty, it will be set to Curitiba."
    echo "Options:"
    echo "  -h, --help: show the help"
    echo "  --telegram: format output for Telegram"
    echo "  --no-cache: do not use cached data"
    echo "  --force: force refresh cache"
}

# Function to get arguments
function get_arguments() {
    CITY=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                help
                exit 0
                ;;
            --telegram)
                FOR_TELEGRAM=true
                shift
                ;;
            --no-cache)
                _weather_USE_CACHE=false
                shift
                ;;
            --force)
                _weather_FORCE_REFRESH=true
                shift
                ;;
            *)
                CITY="$1"
                shift
                ;;
        esac
    done
    
    # Set default city if not specified
    if [[ -z "$CITY" ]]; then
        CITY="Curitiba"
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    get_arguments "$@"
    write_weather "$CITY" "true"  # Assuming terminal output
    exit_code=$?
    exit $exit_code
fi