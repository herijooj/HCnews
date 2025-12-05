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
    
    # Make both API calls in parallel for speed
    local CURRENT_WEATHER_URL="https://api.openweathermap.org/data/2.5/weather?q=${CITY}&appid=${openweathermap_API_KEY}&lang=${LANG}&units=${UNITS}"
    local FORECAST_URL="https://api.openweathermap.org/data/2.5/forecast?q=${CITY}&appid=${openweathermap_API_KEY}&lang=${LANG}&units=${UNITS}"
    
    # Use background processes for parallel requests
    local current_temp=$(mktemp)
    local forecast_temp=$(mktemp)
    
    curl -s "$CURRENT_WEATHER_URL" > "$current_temp" &
    local current_pid=$!
    curl -s "$FORECAST_URL" > "$forecast_temp" &
    local forecast_pid=$!
    
    # Wait for both requests to complete
    wait $current_pid
    wait $forecast_pid
    
    local CURRENT_WEATHER=$(cat "$current_temp")
    local FORECAST_DATA=$(cat "$forecast_temp")
    
    # Clean up temp files
    rm -f "$current_temp" "$forecast_temp"
    
    # Check if current weather request was successful
    if [[ $(echo "$CURRENT_WEATHER" | jq -r '.cod' 2>/dev/null) != "200" ]]; then
        echo "Error: $(echo "$CURRENT_WEATHER" | jq -r '.message' 2>/dev/null || echo "Failed to get weather data")"
        return 1
    fi
    
    # Pre-compute all dates once
    local CURRENT_DATE_TS
    if [[ -n "$start_time" ]]; then
        CURRENT_DATE_TS="$start_time"
    else
        CURRENT_DATE_TS=$(date +%s)
    fi
    
    # Pre-compute next 3 days and day names
    local NEXT_DATES=()
    local DAY_NAMES_SHORT=("Seg" "Ter" "Qua" "Qui" "Sex" "Sáb" "Dom")
    local COMPUTED_DAY_NAMES=()
    
    for i in {1..3}; do
        local NEXT_TS=$((CURRENT_DATE_TS + (i * 86400)))
        local NEXT_DATE=$(LC_ALL=C date -d "@$NEXT_TS" +"%Y-%m-%d")
        NEXT_DATES+=("$NEXT_DATE")
        
        local day_num=$(LC_ALL=C date -d "@$NEXT_TS" +"%u")
        day_num=$((day_num - 1))
        COMPUTED_DAY_NAMES+=("${DAY_NAMES_SHORT[$day_num]}")
    done
    
    # Extract ALL current weather data in a single jq call
    local CURRENT_DATA=$(echo "$CURRENT_WEATHER" | jq -r '
        [
            .weather[0].description,
            .weather[0].id,
            (.main.temp | floor),
            (.main.feels_like | floor),
            (.main.temp_min | floor),
            (.main.temp_max | floor),
            (.main.humidity | floor),
            .sys.sunrise,
            .sys.sunset
        ] | join("|")')
    
    # Parse current data
    IFS='|' read -r CONDITION CONDITION_ID TEMP FEELS_LIKE TEMP_MIN TEMP_MAX HUMIDITY SUNRISE SUNSET <<< "$CURRENT_DATA"
    
    # Format sunrise/sunset times
    local SUNRISE_TIME="N/A"
    local SUNSET_TIME="N/A"
    if [[ "$SUNRISE" =~ ^[0-9]+$ ]]; then
        SUNRISE_TIME=$(LC_ALL=C date -d "@$SUNRISE" +"%H:%M" 2>/dev/null || echo "N/A")
    fi
    if [[ "$SUNSET" =~ ^[0-9]+$ ]]; then
        SUNSET_TIME=$(LC_ALL=C date -d "@$SUNSET" +"%H:%M" 2>/dev/null || echo "N/A")
    fi
    
    # Get condition emoji
    local CONDITION_EMOJI=$(get_weather_emoji "$CONDITION_ID")
    
    # Process ALL forecast data in a single jq call
    local FORECAST_PROCESSED=$(echo "$FORECAST_DATA" | jq -r --argjson dates '["'"${NEXT_DATES[0]}"'","'"${NEXT_DATES[1]}"'","'"${NEXT_DATES[2]}"'"]' '
        [
            $dates[] as $date |
            (
                [.list[] | select(.dt_txt | startswith($date))] as $day_data |
                if ($day_data | length) > 0 then
                    {
                        date: $date,
                        min_temp: ([$day_data[].main.temp] | min | floor),
                        max_temp: ([$day_data[].main.temp] | max | floor),
                        avg_humidity: ([$day_data[].main.humidity] | add / length | floor),
                        most_common_condition: ([$day_data[].weather[0].id] | group_by(.) | max_by(length) | .[0])
                    }
                else
                    {
                        date: $date,
                        min_temp: null,
                        max_temp: null,
                        avg_humidity: null,
                        most_common_condition: null
                    }
                end
            )
        ] | .[] | [.min_temp, .max_temp, .avg_humidity, .most_common_condition] | join("|")')
    
    # Parse forecast data
    local DAY_EMOJIS=()
    local DAY_TEMP_MIN=()
    local DAY_TEMP_MAX=()
    local DAY_HUMIDITY=()
    
    local day_index=0
    while IFS= read -r line; do
        if [[ -n "$line" && "$line" != "null" ]]; then
            IFS='|' read -r min_temp max_temp avg_humidity condition_id <<< "$line"
            
            # Handle null values from jq
            [[ "$min_temp" == "null" ]] && min_temp="N/A"
            [[ "$max_temp" == "null" ]] && max_temp="N/A"
            [[ "$avg_humidity" == "null" ]] && avg_humidity="N/A"
            [[ "$condition_id" == "null" ]] && condition_id=""
            
            DAY_TEMP_MIN+=("${min_temp}")
            DAY_TEMP_MAX+=("${max_temp}")
            DAY_HUMIDITY+=("${avg_humidity}")
            
            # Only try to get emoji if we have a valid condition_id
            if [[ -n "$condition_id" && "$condition_id" != "null" ]]; then
                DAY_EMOJIS+=("$(get_weather_emoji "$condition_id")")
            else
                DAY_EMOJIS+=("🌡️")
            fi
        else
            DAY_TEMP_MIN+=("N/A")
            DAY_TEMP_MAX+=("N/A")
            DAY_HUMIDITY+=("N/A")
            DAY_EMOJIS+=("🌡️")
        fi
        ((day_index++))
        [[ $day_index -ge 3 ]] && break
    done <<< "$FORECAST_PROCESSED"
    
    # Build output string efficiently
    local OUTPUT="🌦️ *Clima em ${CITY}:*
- ${CONDITION_EMOJI} _${CONDITION^}_
- 🌡️ \`${TEMP}\` °C
- ↗️ Máx: \`${TEMP_MAX}\` °C  ↘️ Mín: \`${TEMP_MIN}\` °C
- Sensação: \`${FEELS_LIKE}\` °C  💧 \`${HUMIDITY}\` %
- 🌅 \`${SUNRISE_TIME}\`  🌇 \`${SUNSET_TIME}\`"

    OUTPUT+="

🗓️ *Próximos Dias:*"
    
    for i in {0..2}; do
        OUTPUT+="
- *${COMPUTED_DAY_NAMES[$i]}:* ${DAY_EMOJIS[$i]} \`${DAY_TEMP_MIN[$i]}\` °→ \`${DAY_TEMP_MAX[$i]}\` °C  💧 \`${DAY_HUMIDITY[$i]}\` %"
    done

    # Add timestamp
    local CURRENT_TIME
    # Use cached current_time if available, otherwise fall back to date command
    # Note: current_time from hcnews.sh is in %H:%M:%S format
    if [[ -n "$current_time" ]]; then
        CURRENT_TIME="$current_time"
    else
        CURRENT_TIME=$(date +"%H:%M:%S")
    fi
    OUTPUT+="\\n_Fonte: OpenWeatherMap · Atualizado: ${CURRENT_TIME}_"
    
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