#!/usr/bin/env bash

# HCnews Comprehensive Benchmark Suite
# Tests all components (Synchronous, Cached, Forced)

SCRIPT_DIR=$(dirname "$(realpath "$0")")
# Mock common variables
export HCNEWS_ROOT="$SCRIPT_DIR"

# Source dependencies
source "$SCRIPT_DIR/scripts/lib/common.sh"
source "$SCRIPT_DIR/scripts/file.sh"
source "$SCRIPT_DIR/scripts/header.sh"
source "$SCRIPT_DIR/scripts/moonphase.sh"
source "$SCRIPT_DIR/scripts/quote.sh"
source "$SCRIPT_DIR/scripts/saints.sh"
source "$SCRIPT_DIR/scripts/rss.sh"
source "$SCRIPT_DIR/scripts/exchange.sh"
source "$SCRIPT_DIR/scripts/UFPR/ferias.sh"
source "$SCRIPT_DIR/scripts/UFPR/ru.sh"
source "$SCRIPT_DIR/scripts/musicchart.sh"
source "$SCRIPT_DIR/scripts/weather.sh"
source "$SCRIPT_DIR/scripts/didyouknow.sh"
source "$SCRIPT_DIR/scripts/desculpa.sh"
source "$SCRIPT_DIR/scripts/holidays.sh"
source "$SCRIPT_DIR/scripts/bicho.sh"
source "$SCRIPT_DIR/scripts/states.sh"
source "$SCRIPT_DIR/scripts/emoji.sh"
source "$SCRIPT_DIR/scripts/futuro.sh"

# Initialize cache
hcnews_init_cache_dirs

# Mock context
current_date=$(date +"%s %N %m %d %u %H:%M:%S %Y %-j %Y%m%d")
read start_time_seconds start_time_nanos month day weekday current_time year days_since date_format <<< "$current_date"
start_time_precise=$((start_time_seconds * 1000000000 + 10#$start_time_nanos))
start_time=$start_time_seconds
unix_24h_ago=$((start_time - 86400))
export weekday month day year days_since start_time current_time start_time_precise date_format unix_24h_ago
city="Curitiba"

ITERATIONS=5
# Define components: "Name|Command|UseCacheVar|ForceRefreshVar"
# If Cache/Fresh vars are empty, it's considered synchronous/un-cachable for this context (or handles it internally differently)
COMPONENTS=(
    "Header Core|write_header_core||"
    "Holidays|write_holidays \"$month\" \"$day\"||"
    "States|write_states_birthdays \"$month\" \"$day\"||"
    "Saints|write_saints|_saints_USE_CACHE|_saints_FORCE_REFRESH"
    "RSS (All News)|write_news \"$all_feeds\" false true false|_rss_USE_CACHE|_rss_FORCE_REFRESH"
    "Quotes|quote||"
    "Moon Phase|moon_phase||"
    "Weather|write_weather \"$city\"|_weather_USE_CACHE|_weather_FORCE_REFRESH"
    "RU Menu|export SHOW_ONLY_TODAY=true; write_menu|_ru_USE_CACHE|_ru_FORCE_REFRESH"
    "Exchange|write_exchange|_exchange_USE_CACHE|_exchange_FORCE_REFRESH"
    "Music Chart|write_music_chart|_musicchart_USE_CACHE|_musicchart_FORCE_REFRESH"
    "Did You Know|write_did_you_know|_didyouknow_USE_CACHE|_didyouknow_FORCE_REFRESH"
    "Bicho|write_bicho|_bicho_USE_CACHE|_bicho_FORCE_REFRESH"
    "Emoji|write_emoji||"
    "Desculpa|write_excuse||"
    "AI Fortune|write_ai_fortune|_futuro_USE_CACHE|_futuro_FORCE_REFRESH"
)

# Setup feeds for RSS
o_popular=https://opopularpr.com.br/feed/
plantao190=https://plantao190.com.br/feed/
xvcuritiba=https://xvcuritiba.com.br/feed/
all_feeds="${o_popular},${plantao190},${xvcuritiba}"

echo "=========================================================="
echo "HCnews Benchmark Suite (Runs: $ITERATIONS Cached, 1 Forced)"
echo "=========================================================="
printf "%-20s | %-15s | %-15s | %-15s | %-10s\n" "Component" "Avg (Cached)" "Min (Cached)" "Max (Cached)" "Forced"
echo "--------------------------------------------------------------------------------------"

run_test() {
    local cmd="$1"
    local ts=$(date +%s%N)
    eval "$cmd" > /dev/null 2>&1
    local te=$(date +%s%N)
    echo $(( (te - ts) / 1000000 ))
}

for item in "${COMPONENTS[@]}"; do
    IFS='|' read -r name cmd cache_var force_refresh_var <<< "$item"
    
    # --- Cached Runs ---
    total_time=0
    min_time=99999
    max_time=0
    
    # Set cache flags
    if [[ -n "$cache_var" ]]; then
        export $cache_var=true
        export $force_refresh_var=false
    fi
    # Ensure global overrides for generic logic
    export _HCNEWS_USE_CACHE=true
    export _HCNEWS_FORCE_REFRESH=false

    # Warmup run (ignore)
    run_test "$cmd" > /dev/null

    for ((i=1; i<=ITERATIONS; i++)); do
        dur=$(run_test "$cmd")
        total_time=$((total_time + dur))
        [[ $dur -lt $min_time ]] && min_time=$dur
        [[ $dur -gt $max_time ]] && max_time=$dur
    done
    
    avg_time=$((total_time / ITERATIONS))
    
    # --- Forced Run ---
    forced_time="N/A"
    if [[ -n "$force_refresh_var" ]]; then
        export $cache_var=true # Still use cache logic, but force refresh
        export $force_refresh_var=true
        export _HCNEWS_FORCE_REFRESH=true
        
        # Only 1 run to avoid rate limits
        forced_time="$(run_test "$cmd")ms"
    else
        # For sync components, forced is same as cached (conceptually)
        forced_time="-" 
    fi
    
    printf "%-20s | %-12sms | %-12sms | %-12sms | %-10s\n" "$name" "$avg_time" "$min_time" "$max_time" "$forced_time"
done
echo "=========================================================="
exit 0
