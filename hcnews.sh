#!/usr/bin/env bash
# this project is licensed under the GPL. See the LICENSE file for more information

# Includes ========================================================================
SCRIPT_DIR=$(dirname "$(realpath "${BASH_SOURCE[0]}")")

# Source all the required scripts
source "$SCRIPT_DIR/scripts/lib/common.sh"
export HCNEWS_COMMON_PATH="$SCRIPT_DIR/scripts/lib/common.sh"
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
# source "$SCRIPT_DIR/scripts/sanepar.sh"  # Temporarily disabled - API offline
# Source timing utilities last
source "$SCRIPT_DIR/scripts/timing.sh"

# Initialize cache directories (from common.sh)
hcnews_init_cache_dirs

# ==================================================================================

# Global date caching for performance optimization
start_time_precise=$(date +%s.%N)
start_time=${start_time_precise%.*} # Integer epoch
current_time=$(date '+%d/%m/%Y %H:%M:%S')
weekday=$(date +%u)  # 1=Monday, 7=Sunday
month=$(date +%m)
day=$(date +%d)
year=$(date +%Y)
days_since=$(date +%-j)
date_format=$(date +"%Y%m%d")

# Functions ========================================================================

# Background job management for parallel network operations
# Background job management
source "$SCRIPT_DIR/scripts/lib/jobs.sh"

# Initialize background jobs system
init_jobs

# help function
# usage: ./hcnews.sh [options]
# options:
#   -h, --help: show the help
#   -s, --silent: the script will run silently"
#   -sa, --saints: show the saints of the day with the verbose description
#   -n, --news: show the news with links (🔗 format with shortened URLs)
#   -t, --timing: show function execution timing information"
#   --no-cache: disable caching for this run
#   --force: force refresh cache for this run
show_help() {
    echo "Usage: ./hcnews.sh [options]"
    echo "Options:"
    echo "  -h, --help: show the help"
    echo "  -s, --silent: the script will run silently"
    echo "  -sa, --saints: show the saints of the day with the verbose description"
    echo "  -n, --news: show the news with links (🔗 format with shortened URLs)"
    echo "  -t, --timing: show function execution timing information"
    echo "  --no-cache: disable caching for this run"
    echo "  --force: force refresh cache for this run"
    echo "  --full-url: use full URLs in output instead of shortened links (used for web builds)"
    echo "  --full-url: use full URLs in output instead of shortened links (used for web builds)"
}

# this function will receive the arguments
parse_main_arguments() {
    # Define variables
    silent=false
    saints_verbose=true
    news_shortened=false
    timing=false
    hc_no_cache=false
    hc_force_refresh=false
    hc_full_url=false

    # Get the arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -s|--silent)
                silent=true
                shift
                ;;
            -sa|--saints)
                saints_verbose=true
                shift
                ;;
            -n|--news)
                news_shortened=true
                shift
                ;;
            -t|--timing)
                timing=true
                shift
                ;;
            --no-cache)
                hc_no_cache=true
                shift
                ;;
            --force)
                hc_force_refresh=true
                shift
                ;;
            --full-url)
                hc_full_url=true
                shift
                ;;

            *)
                echo "Invalid argument: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# this function will ask for help
function help_hcnews {
    echo "🤝 *Quer contribuir com o HCNEWS?*"
    echo "- ✨ https://github.com/herijooj/HCnews"
    echo ""
}

# Função para imprimir o footer
function footer {
    # Get end time in nanoseconds using the same format as start
    local end_date=$(date +"%s %N")
    read end_time_seconds end_time_nanos <<< "$end_date"
    local end_time_precise=$((end_time_seconds * 1000000000 + 10#$end_time_nanos))
    
    # Calculate F1-style elapsed time
    elapsed_f1_time=$(format_f1_time "$start_time_precise" "$end_time_precise")
    
    echo "🔔 *HCNews:* Seu Jornal Automático Diário"
    echo "- 📡 Stack: RSS • Bash • Python • Nix"
    echo "- 🔗 https://github.com/herijooj/HCnews"
    echo "🙌 *Que Deus abençoe a todos!*"
    echo ""
    echo "🤖 ${current_time} (BRT) ⏱️ ${elapsed_f1_time}" 
    
    # Add timing summary if enabled
    if [[ $timing == true ]]; then
        echo ""
        # Load timing entries from shared file (for cross-subshell persistence)
        load_timing_entries
        print_timing_summary
    fi
}

function hcseguidor {
    echo "🤖 *Quer ser um HCseguidor?*"
    echo "- 🌐 https://herijooj.github.io/HCnews/"
    echo "- 📢 https://whatsapp.com/channel/0029VaCRDb6FSAszqoID6k2Y"
    echo "- 💬 https://bit.ly/m/HCNews"
    echo ""
}

# Prepare network-heavy jobs in background (excluding RSS news)
# Start network background jobs (excluding news which is handled separately)
start_network_jobs() {
    start_timing "network_parallel_start"

    # Pre-calculate paths
    local ru_cache music_cache futuro_cache weather_cache saints_cache_file exchange_cache dyk_cache bicho_cache moon_cache quote_cache
    
    if [[ $weekday -lt 6 ]]; then
        ru_cache="${HCNEWS_CACHE_DIR}/ru/${date_format}_politecnico.ru"
    fi
    music_cache="${HCNEWS_CACHE_DIR}/musicchart/${date_format}.musicchart"
    futuro_cache="${HCNEWS_CACHE_DIR}/futuro/${date_format}_futuro.cache"
    
    local city_norm="${city,,}"
    city_norm="${city_norm// /_}"
    weather_cache="${HCNEWS_CACHE_DIR}/weather/${date_format}_${city_norm}.weather"

    if [[ "$saints_verbose" == "true" ]]; then
        saints_cache_file="${HCNEWS_CACHE_DIR}/saints/${date_format}_saints-verbose.txt"
    else
        saints_cache_file="${HCNEWS_CACHE_DIR}/saints/${date_format}_saints-regular.txt"
    fi

    exchange_cache="${HCNEWS_CACHE_DIR}/exchange/${date_format}_exchange.cache"
    dyk_cache="${HCNEWS_CACHE_DIR}/didyouknow/${date_format}_didyouknow.cache"
    bicho_cache="${HCNEWS_CACHE_DIR}/bicho/${date_format}_bicho.cache"
    moon_cache="${HCNEWS_CACHE_DIR}/moonphase/${date_format}_moon_phase.cache"
    quote_cache="${HCNEWS_CACHE_DIR}/quote/${date_format}_quote.cache"

    # Batch Stat: Check existence and mod time for ALL caches in one fork
    # Only if cache use is enabled and not force refresh
    local -A CACHE_MOD_TIMES
    if [[ "$_HCNEWS_USE_CACHE" == "true" && "$_HCNEWS_FORCE_REFRESH" != "true" ]]; then
        local paths_to_check=("$music_cache" "$futuro_cache" "$weather_cache" "$saints_cache_file" "$exchange_cache" "$dyk_cache" "$bicho_cache" "$moon_cache" "$quote_cache")
        [[ -n "$ru_cache" ]] && paths_to_check+=("$ru_cache")
        
        # Stat format: size timestamp filename
        local stat_output
        stat_output=$(stat -c "%s %Y %n" "${paths_to_check[@]}" 2>/dev/null)
        
        while read -r size time path; do
             # Check if file is not empty
             if (( size > 0 )); then
                 CACHE_MOD_TIMES["$path"]=$time
             fi
        done <<< "$stat_output"
    fi

    # Helper function to check validity using the associative array
    # Usage: check_cache_inline path ttl
    function check_cache_inline() {
        local path="$1"
        local ttl="$2"
        # Immediate fail if global cache disabled or forced
        [[ "$_HCNEWS_USE_CACHE" == "false" || "$_HCNEWS_FORCE_REFRESH" == "true" ]] && return 1
        
        local mod_time=${CACHE_MOD_TIMES["$path"]}
        [[ -n "$mod_time" ]] || return 1
        
        if (( (start_time - mod_time) < ttl )); then
            return 0
        fi
        return 1
    }

    # 1. Menu (RU)
    if [[ -n "$ru_cache" ]]; then
        if check_cache_inline "$ru_cache" "${HCNEWS_CACHE_TTL["ru"]:-43200}"; then
            # Cache HIT: Run synchronously, skipping internal checks
            menu_output=$(export SHOW_ONLY_TODAY=true; _ru_USE_CACHE=$_HCNEWS_USE_CACHE; _HCNEWS_CACHE_VERIFIED=true; write_menu)
        else
            start_background_job "menu" "(export SHOW_ONLY_TODAY=true; _ru_USE_CACHE=\$_HCNEWS_USE_CACHE; _ru_FORCE_REFRESH=\$_HCNEWS_FORCE_REFRESH; write_menu)"
        fi
    fi

    # 2. Music Chart
    if check_cache_inline "$music_cache" "${HCNEWS_CACHE_TTL["musicchart"]:-43200}"; then
        music_chart_output=$(_HCNEWS_CACHE_VERIFIED=true; write_music_chart)
    else
        start_background_job "music_chart" "(_musicchart_USE_CACHE=\$_HCNEWS_USE_CACHE; _musicchart_FORCE_REFRESH=\$_HCNEWS_FORCE_REFRESH; write_music_chart)"
    fi

    # 3. AI Fortune
    if check_cache_inline "$futuro_cache" "${HCNEWS_CACHE_TTL["futuro"]:-86400}"; then
        ai_fortune_output=$(_HCNEWS_CACHE_VERIFIED=true; write_ai_fortune)
    else
        start_background_job "ai_fortune" "(_futuro_USE_CACHE=\$_HCNEWS_USE_CACHE; _futuro_FORCE_REFRESH=\$_HCNEWS_FORCE_REFRESH; write_ai_fortune)"
    fi

    # 4. Weather
    if check_cache_inline "$weather_cache" "${HCNEWS_CACHE_TTL["weather"]:-10800}"; then
        weather_output=$(_HCNEWS_CACHE_VERIFIED=true; write_weather "$city")
    else
        start_background_job "weather" "(_weather_USE_CACHE=\$_HCNEWS_USE_CACHE; _weather_FORCE_REFRESH=\$_HCNEWS_FORCE_REFRESH; write_weather '$city')"
    fi

    # 5. Saints
    if check_cache_inline "$saints_cache_file" "${HCNEWS_CACHE_TTL["saints"]:-82800}"; then
        saints_output=$(_HCNEWS_CACHE_VERIFIED=true; write_saints "$saints_verbose")
    else
        start_background_job "saints" "(_saints_USE_CACHE=\$_HCNEWS_USE_CACHE; _saints_FORCE_REFRESH=\$_HCNEWS_FORCE_REFRESH; write_saints '$saints_verbose')"
    fi

    # 6. Exchange
    if check_cache_inline "$exchange_cache" "${HCNEWS_CACHE_TTL["exchange"]:-14400}"; then
        exchange_output=$(_HCNEWS_CACHE_VERIFIED=true; write_exchange)
    else
        start_background_job "exchange" "(_exchange_USE_CACHE=\$_HCNEWS_USE_CACHE; _exchange_FORCE_REFRESH=\$_HCNEWS_FORCE_REFRESH; write_exchange)"
    fi

    # 7. Did You Know
    if check_cache_inline "$dyk_cache" "${HCNEWS_CACHE_TTL["didyouknow"]:-86400}"; then
         didyouknow_output=$(_HCNEWS_CACHE_VERIFIED=true; write_did_you_know)
    else
        start_background_job "did_you_know" "(_didyouknow_USE_CACHE=\$_HCNEWS_USE_CACHE; _didyouknow_FORCE_REFRESH=\$_HCNEWS_FORCE_REFRESH; write_did_you_know)"
    fi

    # 8. Bicho
    if check_cache_inline "$bicho_cache" "${HCNEWS_CACHE_TTL["bicho"]:-86400}"; then
         bicho_output=$(_HCNEWS_CACHE_VERIFIED=true; write_bicho)
    else
        start_background_job "bicho" "(_bicho_USE_CACHE=\$_HCNEWS_USE_CACHE; _bicho_FORCE_REFRESH=\$_HCNEWS_FORCE_REFRESH; write_bicho)"
    fi

    # 9. Moon Phase
    if check_cache_inline "$moon_cache" "${HCNEWS_CACHE_TTL["moonphase"]:-86400}"; then
         moon_phase_output=$(_HCNEWS_CACHE_VERIFIED=true; moon_phase)
    else
        start_background_job "header_moon" "(_moonphase_USE_CACHE=\$_HCNEWS_USE_CACHE; _moonphase_FORCE_REFRESH=\$_HCNEWS_FORCE_REFRESH; moon_phase)"
    fi

    # 10. Quote
    if check_cache_inline "$quote_cache" "${HCNEWS_CACHE_TTL["quote"]:-86400}"; then
         quote_output=$(_HCNEWS_CACHE_VERIFIED=true; quote)
    else
        start_background_job "header_quote" "(_quote_USE_CACHE=\$_HCNEWS_USE_CACHE; _quote_FORCE_REFRESH=\$_HCNEWS_FORCE_REFRESH; quote)"
    fi

    end_timing "network_parallel_start"
}

# Collect results from network background jobs
collect_network_data() {
    [[ -z "$moon_phase_output" ]] && { moon_phase_output=$(wait_for_job "header_moon") || moon_phase_output=""; }
    [[ -z "$quote_output" ]] && { quote_output=$(wait_for_job "header_quote") || quote_output=""; }
    [[ -z "$saints_output" ]] && { saints_output=$(wait_for_job "saints") || saints_output=""; }
    [[ -z "$ai_fortune_output" ]] && { ai_fortune_output=$(wait_for_job "ai_fortune") || ai_fortune_output=""; }
    [[ -z "$exchange_output" ]] && { exchange_output=$(wait_for_job "exchange") || exchange_output=""; }
    [[ -z "$music_chart_output" ]] && { music_chart_output=$(wait_for_job "music_chart") || music_chart_output=""; }
    [[ -z "$weather_output" ]] && { weather_output=$(wait_for_job "weather") || weather_output=""; }
    [[ -z "$didyouknow_output" ]] && { didyouknow_output=$(wait_for_job "did_you_know") || didyouknow_output=""; }
    [[ -z "$bicho_output" ]] && { bicho_output=$(wait_for_job "bicho") || bicho_output=""; }
    
    if [[ $weekday -lt 6 ]]; then
        [[ -z "$menu_output" ]] && { menu_output=$(wait_for_job "menu") || menu_output=""; }
    fi
}

# Run local synchronous jobs and capture output in global variables
run_local_jobs() {
    start_timing "local_header"
    header_core_output=$(write_header_core)
    end_timing "local_header"

    start_timing "local_holidays"
    holidays_output=$(write_holidays "$month" "$day")
    end_timing "local_holidays"

    start_timing "local_states"
    states_output=$(write_states_birthdays "$month" "$day")
    end_timing "local_states"
    
    start_timing "local_emoji"
    emoji_output=$(write_emoji)
    end_timing "local_emoji"

    start_timing "local_desculpa"
    desculpa_output=$(write_excuse)
    end_timing "local_desculpa"
}

# Master orchestration function to fetch all data needed for the newspaper
# Populates global variables with content
fetch_newspaper_data() {
    # 1. Start network jobs (parallel)
    start_network_jobs
    
    # 2. Run local jobs (synchronous, while network waits)
    run_local_jobs
    
    # 3. Collect network results (blocks until done)
    collect_network_data
}

render_output() {
    # This function strictly outputs the global variables populated by fetch_newspaper_data.
    # It assumes data is already fetched.
    # For news, it checks if news_output is set (by CLI/build script).
    
    # 1. Header Core
    echo "$header_core_output"
    
    # 2. Moon Phase & Quote
    echo "$moon_phase_output"
    echo ""
    echo "$quote_output"
    echo ""
    
    # 3. Holidays
    echo "$holidays_output"
    
    # 4. States & Birthdays
    echo "$states_output"

    # 5. Saints
    if [[ -n "$saints_output" ]]; then
        echo "$saints_output"
        echo ""
    fi

    # 6. AI Fortune
    if [[ -n "$ai_fortune_output" ]]; then
        echo "$ai_fortune_output"
        echo ""
    fi

    # 7. Exchange
    if [[ -n "$exchange_output" ]]; then
        echo "$exchange_output"
        echo ""
    fi

    # 8. Help HCNEWS interlude
    help_hcnews

    # 9. Music Chart
    if [[ -n "$music_chart_output" ]]; then
        echo "$music_chart_output"
        echo ""
    fi

    # 10. Weather
    if [[ -n "$weather_output" ]]; then
        echo "$weather_output"
        echo ""
    fi

    # 11. Did You Know?
    if [[ -n "$didyouknow_output" ]]; then
        echo "$didyouknow_output"
        echo ""
    fi

    # 12. Bicho
    if [[ -n "$bicho_output" ]]; then
        echo "$bicho_output"
        echo ""
    fi
    
    # 13. HC Follower interlude
    hcseguidor

    # 14. Menu
    if [[ $weekday -lt 6 ]] && [[ -n "$menu_output" ]]; then
        echo "$menu_output"
        echo ""
    fi

    # 15. Emoji
    echo "$emoji_output"
    echo ""

    # 16. News
    if [[ -n "$news_output" ]]; then
        echo "$news_output"
        echo ""
    fi

    # 17. Desculpa
    if [[ -n "$desculpa_output" ]]; then
        echo "$desculpa_output"
        echo ""
    fi
}

function output {
    start_timing "output"

    # Define variables
    saints_verbose=$1
    news_shortened=$2
    # $3 and $4 are no cache/force flags already handled globally
    
    # Explicitly start news generation for CLI mode FIRST (heaviest task)
    start_background_job "all_news" "(_rss_USE_CACHE=\$_HCNEWS_USE_CACHE; _rss_FORCE_REFRESH=\$_HCNEWS_FORCE_REFRESH; write_news '$all_feeds' '$news_shortened' true ${hc_full_url})"

    # Fetch all other data
    fetch_newspaper_data
    
    # Wait for news content
    news_output=$(wait_for_job "all_news")
    if [[ $? -ne 0 || -z "$news_output" ]]; then
        # Fallback if job failed (shouldn't happen in normal CLI flow)
        news_output=$(_rss_USE_CACHE=$_HCNEWS_USE_CACHE; _rss_FORCE_REFRESH=$_HCNEWS_FORCE_REFRESH; write_news "$all_feeds" "$news_shortened" true ${hc_full_url})
    fi

    # Render everything
    render_output
    
    # Restore footer for CLI output
    footer
    
    end_timing "output"
}

# Function to calculate reading time based on word count
calculate_reading_time() {
    local content="$1"
    local words_per_minute=220  # Average reading speed in Portuguese
    
    # Count words (remove emojis and special characters for more accurate count)
    local word_count=$(echo "$content" | sed 's/[🔗📰⏳🇧🇷📅🌙💭🎵☀️🌧️❄️🌈⚡🔥💧🌪️🌡️📊💰📈📉🙏✨🎯📢💬🤖🔔🙌🤝📡💎🎭🎨🎪🎊🎉]//' | wc -w)
    
    # Calculate reading time in minutes
    local reading_time_minutes=$((word_count / words_per_minute))
    
    # Ensure minimum of 1 minute
    if [[ $reading_time_minutes -lt 1 ]]; then
        reading_time_minutes=1
    fi
    
    echo "$reading_time_minutes"
}

# Modified function to add reading time to existing header
function write_header_with_reading_time() {
    local reading_time="$1"
    
    # Get the existing header output
    write_header_core
    
    # Add the reading time line after the header
    echo "📖 Tempo total de leitura: ~${reading_time} min"
}
# Main =============================================================================


# Get the arguments
parse_main_arguments "$@"

# Cache all date operations at once to avoid multiple subprocess calls
# Use nanosecond precision for F1-style timing
# Format: seconds nanoseconds month day weekday time year day_of_year YYYYMMDD
current_date=$(date +"%s %N %m %d %u %H:%M:%S %Y %-j %Y%m%d")
read start_time_seconds start_time_nanos month day weekday current_time year days_since date_format <<< "$current_date"

# Combine seconds and nanoseconds into a single nanosecond timestamp for F1 timing
start_time_precise=$((start_time_seconds * 1000000000 + 10#$start_time_nanos))
start_time=$start_time_seconds  # Keep integer seconds for compatibility

# Pre-compute commonly used date values to avoid subprocess spawning in child scripts
# These values are used by caching functions across all scripts
unix_24h_ago=$((start_time - 86400))  # 24 hours = 86400 seconds

# Export cached values so they're available to sourced scripts
# Scripts should check for these variables before calling date commands
export weekday month day year days_since start_time current_time start_time_precise date_format unix_24h_ago

city="Curitiba"

# Reset timing data and initialize timing file for cross-subshell persistence
reset_timing_data
# Reset timing data and initialize timing file for cross-subshell persistence
init_timing_file

# Compute run-specific cache options
cache_options=""
if [[ "$hc_no_cache" == true ]]; then
    cache_options+=" --no-cache"
    export _HCNEWS_USE_CACHE=false
fi
if [[ "$hc_force_refresh" == true ]]; then
    cache_options+=" --force"
    export _HCNEWS_FORCE_REFRESH=true
fi

# RSS feed globals
o_popular=https://opopularpr.com.br/feed/
plantao190=https://plantao190.com.br/feed/
xvcuritiba=https://xvcuritiba.com.br/feed/
bandab=https://www.bandab.com.br/web-stories/feed/
g1=https://g1.globo.com/rss/g1/pr/parana/
g1cinema=https://g1.globo.com/rss/g1/pop-arte/cinema/
newyorker=https://www.newyorker.com/feed/magazine/rss
folha=https://feeds.folha.uol.com.br/mundo/rss091.xml
formula1=https://www.formula1.com/content/fom-website/en/latest/all.xml
bcc=http://feeds.bbci.co.uk/news/world/latin_america/rss.xml
all_feeds="${o_popular},${plantao190},${xvcuritiba}"

# If running directly, execute the output generation
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    
    # Capture all output to calculate reading time, then output with reading time in header
    content_output=$(output "$saints_verbose" "$news_shortened" "$hc_no_cache" "$hc_force_refresh")

    # Calculate reading time based on the complete content
    reading_time=$(calculate_reading_time "$content_output")

    # Output header with reading time first
    write_header_with_reading_time "$reading_time"

    # Extract and output everything after the header core (moon phase onwards)
    echo "$content_output" | sed '1,4d'  # Skip the first 4 lines (header core)

    exit 0
fi