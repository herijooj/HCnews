#!/bin/bash

source tokens.sh # Assumes openweathermap_API_KEY is defined here

# Check for telegram flag
FOR_TELEGRAM=false
if [[ "$@" == *"--telegram"* ]]; then
    FOR_TELEGRAM=true
    # Remove the --telegram flag from arguments
    set -- "${@/--telegram/}"
fi

# Cache directory - create if it doesn't exist
CACHE_DIR="/tmp/weather_cache"
mkdir -p "$CACHE_DIR"
CACHE_DURATION=3600 # Cache duration in seconds (1 hour)

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

# Weather emoji lookup table (faster than function calls)
declare -A WEATHER_EMOJIS=(
    [200]="⛈️" [201]="⛈️" [202]="⛈️" [210]="⛈️" [211]="⛈️" [212]="⛈️" [221]="⛈️" [230]="⛈️" [231]="⛈️" [232]="⛈️"
    [300]="🌦️" [301]="🌦️" [302]="🌦️" [310]="🌦️" [311]="🌦️" [312]="🌦️" [313]="🌦️" [314]="🌦️" [321]="🌦️"
    [500]="🌧️" [501]="🌧️" [502]="🌧️" [503]="🌧️" [504]="🌧️" [511]="🌧️" [520]="🌧️" [521]="🌧️" [522]="🌧️" [531]="🌧️"
    [600]="❄️" [601]="❄️" [602]="❄️" [611]="❄️" [612]="❄️" [613]="❄️" [615]="❄️" [616]="❄️" [620]="❄️" [621]="❄️" [622]="❄️"
    [701]="🌫️" [711]="🌫️" [721]="🌫️" [731]="🌫️" [741]="🌫️" [751]="🌫️" [761]="🌫️" [762]="🌫️" [771]="🌫️" [781]="🌫️"
    [800]="☀️"
    [801]="🌤️" [802]="⛅" [803]="☁️" [804]="☁️"
)

# Get weather emoji (faster lookup from array)
function get_weather_emoji() {
    local id="$1"
    echo "${WEATHER_EMOJIS[$id]:-🌡️}"
}

# Round up function (avoid spawning awk process each time)
function round_up() {
    local num="$1"
    if (( $(echo "$num % 1 == 0" | bc -l) )); then
        echo "$num"
    else
        echo "$(echo "($num+0.5)/1" | bc)"
    fi
}

# Function to get weather from OpenWeatherMap with formatted output
function get_weather() {
    local CITY="$1"
    local LANG="pt_br"
    local UNITS="metric"
    
    # Create cache filenames based on city
    local CACHE_FILE="${CACHE_DIR}/$(echo "$CITY" | tr '[:upper:]' '[:lower:]' | tr ' ' '_')"
    local CURRENT_CACHE="${CACHE_FILE}_current.json"
    local FORECAST_CACHE="${CACHE_FILE}_forecast.json"
    local CURRENT_TIME=$(date +%s)

    # Check if cache exists and is still valid
    local USE_CACHE=false
    if [[ -f "$CURRENT_CACHE" && -f "$FORECAST_CACHE" ]]; then
        local CACHE_TIME=$(stat -c %Y "$CURRENT_CACHE")
        if (( CURRENT_TIME - CACHE_TIME < CACHE_DURATION )); then
            USE_CACHE=true
        fi
    fi
    
    # Fetch or use cached weather data
    if [[ "$USE_CACHE" == "true" ]]; then
        local CURRENT_WEATHER=$(cat "$CURRENT_CACHE")
        local FORECAST_DATA=$(cat "$FORECAST_CACHE")
    else
        # Get current weather data
        local CURRENT_WEATHER_URL="https://api.openweathermap.org/data/2.5/weather?q=${CITY}&appid=${openweathermap_API_KEY}&lang=${LANG}&units=${UNITS}"
        local CURRENT_WEATHER=$(curl -s "$CURRENT_WEATHER_URL")
        
        # Check if request was successful
        if [[ $(echo "$CURRENT_WEATHER" | jq -r '.cod') != "200" ]]; then
            echo "Error: $(echo "$CURRENT_WEATHER" | jq -r '.message')"
            return 1
        fi
        
        # Get forecast data (5 days, 3 hour intervals)
        local FORECAST_URL="https://api.openweathermap.org/data/2.5/forecast?q=${CITY}&appid=${openweathermap_API_KEY}&lang=${LANG}&units=${UNITS}"
        local FORECAST_DATA=$(curl -s "$FORECAST_URL")
        
        # Save to cache
        echo "$CURRENT_WEATHER" > "$CURRENT_CACHE"
        echo "$FORECAST_DATA" > "$FORECAST_CACHE"
    fi
    
    # Extract all current weather data in one go to minimize jq calls
    local CURRENT_INFO=$(echo "$CURRENT_WEATHER" | jq -r '[
        .weather[0].description,
        .weather[0].id,
        .main.temp,
        .main.feels_like,
        .main.temp_min,
        .main.temp_max,
        .main.humidity,
        .sys.sunrise,
        .sys.sunset
    ] | @tsv')
    
    # Read extracted data into variables
    read -r CONDITION CONDITION_ID TEMP FEELS_LIKE TEMP_MIN TEMP_MAX HUMIDITY SUNRISE SUNSET <<< "$CURRENT_INFO"
    
    # Round up temperatures
    TEMP=$(round_up "$TEMP")
    FEELS_LIKE=$(round_up "$FEELS_LIKE")
    TEMP_MIN=$(round_up "$TEMP_MIN")
    TEMP_MAX=$(round_up "$TEMP_MAX")
    
    # Format sunrise and sunset times (do this once, not in a loop)
    local SUNRISE_TIME=$(date -d "@${SUNRISE}" +"%H:%M")
    local SUNSET_TIME=$(date -d "@${SUNSET}" +"%H:%M")
    
    # Get condition emoji using ID
    local CONDITION_EMOJI=$(get_weather_emoji "$CONDITION_ID")
    
    # Get current date and pre-compute next 3 days (avoid calling date in loops)
    local CURRENT_DATE=$(date +"%Y-%m-%d")
    local NEXT_DATES=()
    local DAY_NAMES_SHORT=()
    
    for i in {1..3}; do
        local NEXT_DATE=$(date -d "${CURRENT_DATE} + ${i} day" +"%Y-%m-%d")
        NEXT_DATES+=("$NEXT_DATE")
        
        # Get day name and translate
        local DAY_NAME=$(date -d "${NEXT_DATE}" +"%A" | tr '[:upper:]' '[:lower:]')
        local TRANSLATED_DAY=${DAY_NAMES[$DAY_NAME]}
        DAY_NAMES_SHORT+=("${TRANSLATED_DAY:0:3}")
    done
    
    # Process forecast data for all 3 days at once (much faster)
    local FORECAST_PROCESSED=$(echo "$FORECAST_DATA" | jq -c --arg date1 "${NEXT_DATES[0]}" --arg date2 "${NEXT_DATES[1]}" --arg date3 "${NEXT_DATES[2]}" '
    {
      day1: [.list[] | select(.dt_txt | startswith($date1)) | {temp: .main.temp, humidity: .main.humidity, condition_id: .weather[0].id}],
      day2: [.list[] | select(.dt_txt | startswith($date2)) | {temp: .main.temp, humidity: .main.humidity, condition_id: .weather[0].id}],
      day3: [.list[] | select(.dt_txt | startswith($date3)) | {temp: .main.temp, humidity: .main.humidity, condition_id: .weather[0].id}]
    }')
    
    # Process each day's data
    local DAY_EMOJIS=()
    local DAY_TEMP_MIN=()
    local DAY_TEMP_MAX=()
    local DAY_HUMIDITY=()
    
    for day_num in {1..3}; do
        local day_key="day${day_num}"
        
        # Extract data for this day
        local day_data=$(echo "$FORECAST_PROCESSED" | jq -r --arg key "$day_key" '.[$key]')
        
        # Process temperature and humidity in one go
        local stats=$(echo "$day_data" | jq -r '
        [
          ([.[].temp] | min),
          ([.[].temp] | max),
          ([.[].humidity] | add / length),
          ([.[].condition_id] | .[] | tostring) | join(",")
        ] | @tsv')
        
        read -r min_temp max_temp avg_humidity condition_ids <<< "$stats"
        
        # Find most common condition ID
        local most_common_id=$(echo "$condition_ids" | tr ',' '\n' | sort | uniq -c | sort -nr | head -1 | awk '{print $2}')
        
        # Round numbers and add to arrays
        DAY_TEMP_MIN+=("$(round_up "$min_temp")")
        DAY_TEMP_MAX+=("$(round_up "$max_temp")")
        DAY_HUMIDITY+=("$(echo "$avg_humidity" | awk '{print int($1+0.5)}')")
        DAY_EMOJIS+=("$(get_weather_emoji "$most_common_id")")
    done
    
    # Build the output with proper newlines
    local OUTPUT=""
    OUTPUT+="🌦️ *Clima:*"$'\n'
    OUTPUT+="- ${CONDITION_EMOJI} _${CONDITION^}_"$'\n'
    OUTPUT+="- 🌡️ \`${TEMP}\` °C"$'\n'
    OUTPUT+="- ↗️ Máx: \`${TEMP_MAX}\` °C  ↘️ Mín: \`${TEMP_MIN}\` °C"$'\n'
    OUTPUT+="- Sensação: \`${FEELS_LIKE}\` °C  💧 \`${HUMIDITY}\` %"$'\n'
    OUTPUT+="- 🌅 \`${SUNRISE_TIME}\`  🌇 \`${SUNSET_TIME}\`"$'\n'
    OUTPUT+=$'\n'
    OUTPUT+="🗓️ *Próximos Dias:*"$'\n'
    
    for i in {0..2}; do
        OUTPUT+="- *${DAY_NAMES_SHORT[$i]}:* ${DAY_EMOJIS[$i]} \`${DAY_TEMP_MIN[$i]}\` °→ \`${DAY_TEMP_MAX[$i]}\` °C  💧 \`${DAY_HUMIDITY[$i]}\` %"$'\n'
    done
    
    OUTPUT+="_Fonte: OpenWeatherMap_"
    
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