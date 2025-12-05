#!/usr/bin/env bash
# this project is licensed under the GPL. See the LICENSE file for more information

# Includes ========================================================================
SCRIPT_DIR=$(dirname "$(realpath "${BASH_SOURCE[0]}")")

# Source all the required scripts
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

# ==================================================================================

# Global date caching for performance optimization
start_time_precise=$(date +%s.%N)
current_time=$(date '+%d/%m/%Y %H:%M:%S')
weekday=$(date +%u)  # 1=Monday, 7=Sunday
month=$(date +%m)
day=$(date +%d)
date_format=$(date +"%Y%m%d")

# Functions ========================================================================

# Background job management for parallel network operations
declare -A background_jobs
declare -A job_outputs
declare -A job_timings

# Temp directory for background job files (created once, cleaned up at exit)
_HCNEWS_TEMP_DIR="/tmp/hcnews_$$"
mkdir -p "$_HCNEWS_TEMP_DIR"
trap 'rm -rf "$_HCNEWS_TEMP_DIR"' EXIT

# Start a network operation in background with timing
start_background_job() {
    local job_name="$1"
    local command="$2"
    # Use predictable temp file names instead of spawning mktemp
    local temp_file="${_HCNEWS_TEMP_DIR}/${job_name}.out"
    local timing_file="${_HCNEWS_TEMP_DIR}/${job_name}.time"
    
    # Run command in background - use bash -c instead of eval for better performance
    if [[ "$timing" == true ]]; then
        # Wrap command with timing
        bash -c "start_time=\$(date +%s%N); $command; end_time=\$(date +%s%N); echo \$(((\$end_time - \$start_time) / 1000000)) > '$timing_file'" > "$temp_file" 2>&1 &
    else
        bash -c "$command" > "$temp_file" 2>&1 &
    fi
    local pid=$!
    
    background_jobs["$job_name"]="$pid:$temp_file:$timing_file"
}

# Wait for a background job and get its output
wait_for_job() {
    local job_name="$1"
    local job_info="${background_jobs[$job_name]}"
    
    if [[ -n "$job_info" ]]; then
        local pid="${job_info%%:*}"
        local temp_file="${job_info#*:}"
        temp_file="${temp_file%%:*}"
        local timing_file="${job_info##*:}"
        
        # Use bash's wait with timeout instead of polling loop
        # This is more efficient than sleep 0.1 polling
        local timeout=30
        if ! wait "$pid" 2>/dev/null; then
            # Check if process is still running (wait returns non-zero for various reasons)
            if kill -0 "$pid" 2>/dev/null; then
                # Process still running, fall back to polling with longer intervals
                local elapsed=0
                while kill -0 "$pid" 2>/dev/null; do
                    sleep 0.5  # Longer interval reduces CPU usage
                    elapsed=$((elapsed + 1))
                    if [[ $elapsed -gt $((timeout * 2)) ]]; then
                        kill "$pid" 2>/dev/null
                        echo "⚠️ Background job '$job_name' timed out after ${timeout}s"
                        rm -f "$temp_file" "$timing_file"
                        return 1
                    fi
                done
            fi
        fi
        
        # Store timing data if available
        if [[ "$timing" == true && -f "$timing_file" ]]; then
            local job_time=$(cat "$timing_file" 2>/dev/null)
            if [[ -n "$job_time" && "$job_time" =~ ^[0-9]+$ ]]; then
                TIMING_DATA["${job_name}_elapsed"]=$job_time
                TIMING_DATA["timed_functions"]="${TIMING_DATA["timed_functions"]} $job_name"
                # Save to shared file for cross-subshell persistence
                save_timing_entry "$job_name" "$job_time"
            fi
        fi
        
        # Get the output and clean up
        if [[ -f "$temp_file" ]]; then
            cat "$temp_file"
            rm -f "$temp_file"
        fi
        rm -f "$timing_file"
        
        unset background_jobs["$job_name"]
        return 0
    fi
    return 1
}

# Format elapsed time like F1 lap times (MM:SS.mmm or SS.mmm)
format_f1_time() {
    local start_time_ns=$1
    local end_time_ns=$2
    
    # Calculate elapsed time in nanoseconds and convert to seconds with decimal precision
    local elapsed_ns=$((10#$end_time_ns - 10#$start_time_ns))
    
    # Convert nanoseconds to milliseconds (integer division)
    local total_ms=$((elapsed_ns / 1000000))
    
    # Extract minutes, seconds, and milliseconds using only integer arithmetic
    local minutes=$((total_ms / 60000))
    local remaining_ms=$((total_ms % 60000))
    local seconds=$((remaining_ms / 1000))
    local milliseconds=$((remaining_ms % 1000))
    
    # Format like F1 times
    if [[ $minutes -gt 0 ]]; then
        printf "%d:%02d.%03ds" $minutes $seconds $milliseconds
    else
        printf "%d.%03ds" $seconds $milliseconds
    fi
}

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
}

# this function will receive the arguments
get_arguments() {
    # Define variables
    silent=false
    saints_verbose=true
    news_shortened=false
    timing=false
    hc_no_cache=false 
    hc_force_refresh=false

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
    echo "- 📢 https://whatsapp.com/channel/0029VaCRDb6FSAszqoID6k2Y"
    echo "- 💬 https://bit.ly/m/HCNews"
    echo ""
}

function output {
    start_timing "output"

    # Define variables
    saints_verbose=$1
    news_shortened=$2
    local cache_options="" # Variable to hold cache flags

    if [[ "$hc_no_cache" == true ]]; then
        cache_options+=" --no-cache"
    fi
    if [[ "$hc_force_refresh" == true ]]; then
        cache_options+=" --force"
    fi
    
    # RSS feeds
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


    # Combine feeds for parallel processing
    all_feeds="${o_popular},${plantao190},${xvcuritiba}"

    # ======= PHASE 1: Start all heavy network operations in parallel =======
    start_timing "network_parallel_start"
    
    # Start the slowest operations first (based on timing data: RU 1308ms, futuro 984ms, weather 620ms)
    # RU menu is the slowest - start it first (only on weekdays)
    if [[ $weekday -lt 6 ]]; then
        start_background_job "menu" "(export SHOW_ONLY_TODAY=true; source '$SCRIPT_DIR/scripts/UFPR/ru.sh' $cache_options && write_menu)"
    fi
    start_background_job "music_chart" "cd '$SCRIPT_DIR' && bash scripts/musicchart.sh $cache_options"
    start_background_job "ai_fortune" "(source '$SCRIPT_DIR/scripts/futuro.sh' $cache_options && write_ai_fortune)"
    start_background_job "weather" "(source '$SCRIPT_DIR/scripts/weather.sh' $cache_options && write_weather '$city')"
    start_background_job "all_news" "(source '$SCRIPT_DIR/scripts/rss.sh' $cache_options && write_news '$all_feeds' '$news_shortened' true)"
    start_background_job "saints" "(source '$SCRIPT_DIR/scripts/saints.sh' $cache_options && write_saints '$saints_verbose')"
    start_background_job "exchange" "(source '$SCRIPT_DIR/scripts/exchange.sh' $cache_options && write_exchange)"
    # start_background_job "sanepar" "(source '$SCRIPT_DIR/scripts/sanepar.sh' $cache_options && write_sanepar)"  # Temporarily disabled - API offline
    start_background_job "did_you_know" "(source '$SCRIPT_DIR/scripts/didyouknow.sh' $cache_options && write_did_you_know)"
    start_background_job "desculpa" "(source '$SCRIPT_DIR/scripts/desculpa.sh' $cache_options && write_excuse)"
    start_background_job "bicho" "(source '$SCRIPT_DIR/scripts/bicho.sh' $cache_options && write_bicho)"
    start_background_job "header_moon" "(source '$SCRIPT_DIR/scripts/moonphase.sh' $cache_options && moon_phase)"
    start_background_job "header_quote" "(source '$SCRIPT_DIR/scripts/quote.sh' $cache_options && quote)"
    
    end_timing "network_parallel_start"

    # ======= PHASE 2: Process fast local operations while network jobs run =======
    
    # Write the header core (fast, no network calls)
    start_timing "write_header_core"
    write_header_core
    end_timing "write_header_core"

    # Add moon phase to complete the header (async - timing tracked by background job)
    moon_phase_output=$(wait_for_job "header_moon")
    if [[ $? -eq 0 && -n "$moon_phase_output" ]]; then
        echo "$moon_phase_output"
    else
        # Fallback to synchronous if background job failed
        start_timing "header_moon_fallback"
        moon_phase
        end_timing "header_moon_fallback"
    fi
    echo ""

    # Add quote of the day to complete the header section (async - timing tracked by background job)
    quote_output=$(wait_for_job "header_quote")
    if [[ $? -eq 0 && -n "$quote_output" ]]; then
        echo "$quote_output"
    else
        # Fallback to synchronous if background job failed
        start_timing "header_quote_fallback"
        quote
        end_timing "header_quote_fallback"
    fi
    echo ""

    # Write the holidays
    start_timing "write_holidays"
    write_holidays "$month" "$day"
    end_timing "write_holidays"

    # Write the states birthdays
    start_timing "write_states_birthdays"
    write_states_birthdays "$month" "$day"
    end_timing "write_states_birthdays"

    # ======= PHASE 3: Collect network results and display in logical order =======

    # Write the saint(s) of the day
    saints_output=$(wait_for_job "saints")
    if [[ $? -eq 0 && -n "$saints_output" ]]; then
        echo "$saints_output"
        echo ""
    else
        # Fallback to synchronous if background job failed
        start_timing "write_saints"
        (source "$SCRIPT_DIR/scripts/saints.sh" $cache_options && write_saints "$saints_verbose")
        end_timing "write_saints"
    fi

    # Write the AI Fortune
    ai_fortune_output=$(wait_for_job "ai_fortune")
    if [[ $? -eq 0 && -n "$ai_fortune_output" ]]; then
        echo "$ai_fortune_output"
        echo ""
    else
        # Fallback to synchronous if background job failed
        start_timing "write_ai_fortune"
        write_ai_fortune
        end_timing "write_ai_fortune"
    fi

    # Write the exchange rates (now async)
    exchange_output=$(wait_for_job "exchange")
    if [[ $? -eq 0 && -n "$exchange_output" ]]; then
        echo "$exchange_output"
        echo ""
    else
        # Fallback to synchronous if background job failed
        start_timing "write_exchange"
        (source "$SCRIPT_DIR/scripts/exchange.sh" $cache_options && write_exchange)
        end_timing "write_exchange"
    fi

    # Ask to enter the Whatsapp Channel
    help_hcnews

    # Write the music chart
    music_chart_output=$(wait_for_job "music_chart")
    if [[ $? -eq 0 && -n "$music_chart_output" ]]; then
        echo "$music_chart_output"
        echo ""
    else
        # Fallback to synchronous if background job failed
        start_timing "write_music_chart"
        write_music_chart
        end_timing "write_music_chart"
    fi

    # Write the weather
    weather_output=$(wait_for_job "weather")
    if [[ $? -eq 0 && -n "$weather_output" ]]; then
        echo "$weather_output"
        echo ""
    else
        # Fallback to synchronous if background job failed
        start_timing "write_weather"
        write_weather "$city"
        end_timing "write_weather"
    fi

    # Write "Did you know?"
    didyouknow_output=$(wait_for_job "did_you_know")
    if [[ $? -eq 0 && -n "$didyouknow_output" ]]; then
        echo "$didyouknow_output"
        echo ""
    else
        # Fallback to synchronous if background job failed
        start_timing "write_did_you_know"
        write_did_you_know
        end_timing "write_did_you_know"
    fi

    # Write Sanepar dam levels - Temporarily disabled (API offline)
    # sanepar_output=$(wait_for_job "sanepar")
    # if [[ $? -eq 0 && -n "$sanepar_output" ]]; then
    #     echo "$sanepar_output"
    #     echo ""
    # else
    #     # Fallback to synchronous if background job failed
    #     start_timing "write_sanepar"
    #     write_sanepar
    #     end_timing "write_sanepar"
    # fi

    # Write the palpite of the day
    bicho_output=$(wait_for_job "bicho")
    if [[ $? -eq 0 && -n "$bicho_output" ]]; then
        echo "$bicho_output"
        echo ""
    else
        # Fallback to synchronous if background job failed
        start_timing "write_bicho"
        write_bicho
        end_timing "write_bicho"
    fi

    # Help HCNEWS
    hcseguidor

    # menu of the day (now async - wait for background job)
    if [[ $weekday -lt 6 ]]; then
        menu_output=$(wait_for_job "menu")
        if [[ $? -eq 0 && -n "$menu_output" ]]; then
            echo "$menu_output"
        else
            # Fallback to synchronous if background job failed
            start_timing "write_menu"
            SHOW_ONLY_TODAY=true
            (source "$SCRIPT_DIR/scripts/UFPR/ru.sh" $cache_options && write_menu)
            end_timing "write_menu"
        fi
    fi

    # emoji of the day
    start_timing "write_emoji"
    write_emoji
    end_timing "write_emoji"

    # Write all news (this was the longest single operation)
    news_output=$(wait_for_job "all_news")
    if [[ $? -eq 0 && -n "$news_output" ]]; then
        echo "$news_output"
        echo ""
    else
        # Fallback to synchronous if background job failed
        start_timing "write_all_news"
        (source "$SCRIPT_DIR/scripts/rss.sh" $cache_options && write_news "$all_feeds" "$news_shortened" true)
        end_timing "write_all_news"
    fi

    # Write the excuse of the day
    desculpa_output=$(wait_for_job "desculpa")
    if [[ $? -eq 0 && -n "$desculpa_output" ]]; then
        echo "$desculpa_output"
        echo ""
    else
        # Fallback to synchronous if background job failed
        start_timing "write_excuse"
        write_excuse
        end_timing "write_excuse"
    fi

    # Write the footer
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
get_arguments "$@"

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
init_timing_file

# Capture all output to calculate reading time, then output with reading time in header
content_output=$(output "$saints_verbose" "$news_shortened" "$hc_no_cache" "$hc_force_refresh")

# Calculate reading time based on the complete content
reading_time=$(calculate_reading_time "$content_output")

# Output header with reading time first
write_header_with_reading_time "$reading_time"

# Extract and output everything after the header core (moon phase onwards)
echo "$content_output" | sed '1,4d'  # Skip the first 4 lines (header core)

exit 0