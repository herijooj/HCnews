#!/bin/bash

source tokens.sh # Assumes openweathermap_API_KEY is defined here

# Check for telegram flag
FOR_TELEGRAM=false
if [[ "$@" == *"--telegram"* ]]; then
    FOR_TELEGRAM=true
    # Remove the --telegram flag from arguments
    set -- "${@/--telegram/}"
fi

# Function to get proper emoji based on OpenWeatherMap condition ID
function get_weather_emoji() {
    local id="$1"
    
    case $id in
        # Thunderstorm (200-232)
        200|201|202|210|211|212|221|230|231|232) echo "⛈️" ;;
        # Drizzle (300-321)
        300|301|302|310|311|312|313|314|321) echo "🌦️" ;;
        # Rain (500-531)
        500|501|502|503|504|511|520|521|522|531) echo "🌧️" ;;
        # Snow (600-622)
        600|601|602|611|612|613|615|616|620|621|622) echo "❄️" ;;
        # Atmosphere (701-781)
        701|711|721|731|741|751|761|762|771|781) echo "🌫️" ;;
        # Clear (800)
        800) echo "☀️" ;;
        # Clouds (801-804)
        801) echo "🌤️" ;;  # few clouds
        802) echo "⛅" ;;  # scattered clouds
        803|804) echo "☁️" ;;  # broken/overcast clouds
        *) echo "🌡️" ;;  # default fallback
    esac
}

# Function to get weather from OpenWeatherMap with formatted output
function get_weather() {
    local CITY="$1"
    local LANG="pt_br"
    local UNITS="metric"
    
    # Get current weather data
    local CURRENT_WEATHER_URL="https://api.openweathermap.org/data/2.5/weather?q=${CITY}&appid=${openweathermap_API_KEY}&lang=${LANG}&units=${UNITS}"
    local CURRENT_WEATHER=$(curl -s "$CURRENT_WEATHER_URL")
    
    # Check if request was successful
    if [[ $(echo "$CURRENT_WEATHER" | jq -r '.cod') != "200" ]]; then
        echo "Error: $(echo "$CURRENT_WEATHER" | jq -r '.message')"
        return 1
    fi
    
    # Extract current weather data
    local CONDITION=$(echo "$CURRENT_WEATHER" | jq -r '.weather[0].description')
    local CONDITION_ID=$(echo "$CURRENT_WEATHER" | jq -r '.weather[0].id')
    # Round up temperatures using ceiling function
    local TEMP=$(echo "$CURRENT_WEATHER" | jq -r '.main.temp' | awk '{print ($1%1==0)?$1:int($1+1)}')
    local FEELS_LIKE=$(echo "$CURRENT_WEATHER" | jq -r '.main.feels_like' | awk '{print ($1%1==0)?$1:int($1+1)}')
    local TEMP_MIN=$(echo "$CURRENT_WEATHER" | jq -r '.main.temp_min' | awk '{print ($1%1==0)?$1:int($1+1)}')
    local TEMP_MAX=$(echo "$CURRENT_WEATHER" | jq -r '.main.temp_max' | awk '{print ($1%1==0)?$1:int($1+1)}')
    local HUMIDITY=$(echo "$CURRENT_WEATHER" | jq -r '.main.humidity')
    local SUNRISE=$(echo "$CURRENT_WEATHER" | jq -r '.sys.sunrise')
    local SUNSET=$(echo "$CURRENT_WEATHER" | jq -r '.sys.sunset')
    
    # Format sunrise and sunset times
    local SUNRISE_TIME=$(date -d "@${SUNRISE}" +"%H:%M")
    local SUNSET_TIME=$(date -d "@${SUNSET}" +"%H:%M")
    
    # Get condition emoji using ID
    local CONDITION_EMOJI=$(get_weather_emoji "$CONDITION_ID")
    
    # Get forecast data (5 days, 3 hour intervals)
    local FORECAST_URL="https://api.openweathermap.org/data/2.5/forecast?q=${CITY}&appid=${openweathermap_API_KEY}&lang=${LANG}&units=${UNITS}"
    local FORECAST_DATA=$(curl -s "$FORECAST_URL")
    
    # Process forecast data for the next 3 days
    # We'll get data for tomorrow, day after tomorrow, and the third day
    local DAYS=()
    local DAY_CONDITIONS=()
    local DAY_EMOJIS=()
    local DAY_TEMP_MIN=()
    local DAY_TEMP_MAX=()
    local DAY_HUMIDITY=()
    
    # Get current date (YYYY-MM-DD)
    local CURRENT_DATE=$(date +"%Y-%m-%d")
    
    # Parse forecast data
    for i in {1..3}; do
        local NEXT_DATE=$(date -d "${CURRENT_DATE} + ${i} day" +"%Y-%m-%d")
        local DAY_NAME=$(date -d "${NEXT_DATE}" +"%A")
        
        # Translate day names to Portuguese
        case "${DAY_NAME,,}" in
            "monday") DAY_NAME="Segunda-feira" ;;
            "tuesday") DAY_NAME="Terça-feira" ;;
            "wednesday") DAY_NAME="Quarta-feira" ;;
            "thursday") DAY_NAME="Quinta-feira" ;;
            "friday") DAY_NAME="Sexta-feira" ;;
            "saturday") DAY_NAME="Sábado" ;;
            "sunday") DAY_NAME="Domingo" ;;
        esac
        
        DAYS+=("$DAY_NAME")
        
        # Filter forecast entries for this day
        local DAY_DATA=$(echo "$FORECAST_DATA" | jq -c ".list[] | select(.dt_txt | startswith(\"${NEXT_DATE}\"))")
        
        # Find most common condition for the day
        local CONDITIONS=$(echo "$DAY_DATA" | jq -r '.weather[0].description' | sort | uniq -c | sort -nr | head -1 | awk '{$1=""; print $0}' | xargs)
        DAY_CONDITIONS+=("$CONDITIONS")
        
        # Find min/max temperatures and average humidity
        local MIN_TEMP=100
        local MAX_TEMP=-100
        local TOTAL_HUMIDITY=0
        local COUNT=0
        
        while IFS= read -r entry; do
            if [[ -n "$entry" ]]; then
                local TEMP=$(echo "$entry" | jq -r '.main.temp')
                local HUM=$(echo "$entry" | jq -r '.main.humidity')
                local CONDITION_ID=$(echo "$entry" | jq -r '.weather[0].id')
                DAY_EMOJIS+=("$(get_weather_emoji "$CONDITION_ID")")
                
                if (( $(echo "$TEMP < $MIN_TEMP" | bc -l) )); then
                    MIN_TEMP=$TEMP
                fi
                if (( $(echo "$TEMP > $MAX_TEMP" | bc -l) )); then
                    MAX_TEMP=$TEMP
                fi
                
                TOTAL_HUMIDITY=$((TOTAL_HUMIDITY + HUM))
                COUNT=$((COUNT + 1))
            fi
        done < <(echo "$DAY_DATA")
        
        # Calculate averages and format numbers with rounding up
        MIN_TEMP=$(echo "$MIN_TEMP" | awk '{print ($1%1==0)?$1:int($1+1)}')
        MAX_TEMP=$(echo "$MAX_TEMP" | awk '{print ($1%1==0)?$1:int($1+1)}')
        local AVG_HUMIDITY=0
        if [[ $COUNT -gt 0 ]]; then
            AVG_HUMIDITY=$((TOTAL_HUMIDITY / COUNT))
        fi
        
        DAY_TEMP_MIN+=("$MIN_TEMP")
        DAY_TEMP_MAX+=("$MAX_TEMP")
        DAY_HUMIDITY+=("$AVG_HUMIDITY")
    done
    
    # Build the output with proper newlines
    local OUTPUT=""
    OUTPUT+="🌦️ *Clima:*"$'\n'
    OUTPUT+="- ${CONDITION_EMOJI} _${CONDITION^}_"$'\n'
    OUTPUT+="- 🌡️ \`$(echo "$TEMP" | awk '{print ($1%1==0)?$1:int($1+1)}')\` °C"$'\n'
    OUTPUT+="- ↗️ Máx: \`${TEMP_MAX}\` °C  ↘️ Mín: \`${TEMP_MIN}\` °C"$'\n'
    OUTPUT+="- Sensação: \`${FEELS_LIKE}\` °C  💧 \`${HUMIDITY}\` %"$'\n'
    OUTPUT+="- 🌅 \`${SUNRISE_TIME}\`  🌇 \`${SUNSET_TIME}\`"$'\n'
    OUTPUT+=$'\n'
    OUTPUT+="🗓️ *Próximos Dias:*"$'\n'
    
    for i in {0..2}; do
        OUTPUT+="- *${DAYS[$i]:0:3}:* ${DAY_EMOJIS[$i]} \`${DAY_TEMP_MIN[$i]}\` °→ \`${DAY_TEMP_MAX[$i]}\` °C  💧 \`${DAY_HUMIDITY[$i]}\` %"$'\n'
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