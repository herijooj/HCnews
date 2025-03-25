#!/bin/bash

source tokens.sh # Assumes openweathermap_API_KEY is defined here

# Check for telegram flag
FOR_TELEGRAM=false
if [[ "$@" == *"--telegram"* ]]; then
    FOR_TELEGRAM=true
    # Remove the --telegram flag from arguments
    set -- "${@/--telegram/}"
fi

# Function to get proper emoji based on weather condition
function get_weather_emoji() {
    CONDITION="$1"
    case "$CONDITION" in
        *"chuva"*|*"chuvisco"*|*"garoa"*)
            echo "🌧️"
            ;;
        *"nublado"*|*"nuvens"*)
            echo "☁️"
            ;;
        *"céu limpo"*|*"limpo"*)
            echo "☀️"
            ;;
        *"trovoada"*|*"tempestade"*)
            echo "⛈️"
            ;;
        *"neve"*)
            echo "❄️"
            ;;
        *"névoa"*|*"neblina"*)
            echo "🌫️"
            ;;
        *"nuvens dispersas"*)
            echo "🌤️"
            ;;
        *"poucas nuvens"*)
            echo "⛅"
            ;;
        *)
            echo "🌡️"
            ;;
    esac
}

# Function to get weather from OpenWeatherMap with formatted output
function get_weather_openweathermap () {
    CITY="$1"
    if [[ -z "$CITY" ]]; then
        echo "Erro: Nome da cidade não fornecido"
        return 1
    fi
    JSON=$(curl -s "http://api.openweathermap.org/data/2.5/weather?q=$CITY&appid=$openweathermap_API_KEY&units=metric&lang=pt_br")
    COD=$(echo "$JSON" | jq '.cod')
    if [ "$COD" != "200" ]; then
        echo "Erro: $(echo "$JSON" | jq -r '.message')"
        return 1
    fi
    DESCRIPTION=$(echo "$JSON" | jq -r '.weather[0].description')
    TEMP=$(echo "$JSON" | jq -r '.main.temp')
    TEMP_ROUNDED=$(LC_NUMERIC=C printf "%.0f" "$TEMP")
    WIND_SPEED=$(echo "$JSON" | jq -r '.wind.speed')
    
    # Check if bc is installed, otherwise use awk
    if command -v bc &> /dev/null; then
        WIND_SPEED_KMH=$(echo "scale=1; $WIND_SPEED * 3.6" | bc)
    else
        WIND_SPEED_KMH=$(awk "BEGIN {printf \"%.1f\", $WIND_SPEED * 3.6}")
    fi
    
    HUMIDITY=$(echo "$JSON" | jq -r '.main.humidity')
    
    # Get appropriate emoji for the weather condition
    WEATHER_EMOJI=$(get_weather_emoji "$DESCRIPTION")

    # Use emojis instead of ASCII art
    echo "  $WEATHER_EMOJI  $DESCRIPTION"
    echo "  🌡️  $TEMP_ROUNDED °C"
    echo "  💨  $WIND_SPEED_KMH km/h"
    echo "  💧  Umidade: $HUMIDITY%"
}

# Function to get weather, with fallback to OpenWeatherMap
function get_weather () {
    CITY="$1"
    
    # Validate city parameter
    if [[ -z "$CITY" || "$CITY" == "--telegram" ]]; then
        CITY="Curitiba"  # Default if empty or only contains the flag
    fi
    
    # Handle spaces and special characters in city name for curl
    ENCODED_CITY=$(echo "$CITY" | sed 's/ /%20/g')
    
    WEATHER=$(curl -s "wttr.in/$ENCODED_CITY?0q&lang=pt-br")
    
    # Check if we got a valid response from wttr.in
    if [[ "$WEATHER" == *"nothing to geocode"* || "$WEATHER" == *"Unknown location"* || -z "$WEATHER" ]]; then
        # echo "Tentando com OpenWeatherMap..." >&2
        OWM_RESULT=$(get_weather_openweathermap "$CITY")
        if [[ $? -ne 0 ]]; then
            echo "❌ Não foi possível encontrar a cidade: $CITY"
            echo "❌ Erro: Cidade não encontrada"
            exit 1
        fi
        echo "$OWM_RESULT"
        echo "OpenWeatherMap" # Return the provider name on the last line
    else
        # Clean up wttr.in output (remove first two lines that contain header info)
        CLEANED_WEATHER=$(echo "$WEATHER" | sed '1,2d')
        echo "$CLEANED_WEATHER"
        echo "wttr.in" # Return the provider name on the last line
    fi
}

# Function to write weather information
function write_weather() {
    CITY="$1"
    TERMINAL="${2:-true}"  # Default to true for terminal output
    
    # Get weather data and extract provider from the last line
    WEATHER_DATA=$(get_weather "$CITY")
    
    # Check if there was an error
    if [[ "$WEATHER_DATA" == *"❌ Erro:"* ]]; then
        echo "$WEATHER_DATA"
        return 1
    fi
    
    WEATHER_PROVIDER=$(echo "$WEATHER_DATA" | tail -n 1)
    WEATHER=$(echo "$WEATHER_DATA" | sed '$d') # Remove the last line (provider)
    
    if [[ "$TERMINAL" == "false" ]]; then
        WEATHER=$(echo "$WEATHER" | sed "s/\x1B\[[0-9;]*[a-zA-Z]//g")
    fi
    
    # Ensure we have a city name, using Curitiba as default if empty
    if [[ -z "$CITY" ]]; then
        CITY="Curitiba"
    fi
    
    echo "🌧️ *Previsão do tempo* ⛅"
    echo "$WEATHER"
    echo "📌 Em ${CITY} as $(date +'%H:%M')"
    echo "🔍 $WEATHER_PROVIDER"
    echo ""
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