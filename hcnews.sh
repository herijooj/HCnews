#!/usr/bin/env bash
# this project is licensed under the GPL. See the LICENSE file for more information

# Includes ========================================================================
SCRIPT_DIR=$(dirname "$(realpath "${BASH_SOURCE[0]}")")

# Source all the required scripts
source "$SCRIPT_DIR/scripts/file.sh"
source "$SCRIPT_DIR/scripts/header.sh"
source "$SCRIPT_DIR/scripts/saints.sh"
source "$SCRIPT_DIR/scripts/rss.sh"
source "$SCRIPT_DIR/scripts/exchange.sh"
source "$SCRIPT_DIR/scripts/UFPR/ferias.sh"
source "$SCRIPT_DIR/scripts/UFPR/ru.sh"
source "$SCRIPT_DIR/scripts/musicchart.sh"
source "$SCRIPT_DIR/scripts/weather.sh"
source "$SCRIPT_DIR/scripts/didyouknow.sh"
source "$SCRIPT_DIR/scripts/holidays.sh"
source "$SCRIPT_DIR/scripts/bicho.sh"
source "$SCRIPT_DIR/scripts/states.sh"
source "$SCRIPT_DIR/scripts/emoji.sh"
source "$SCRIPT_DIR/scripts/futuro.sh"
# Source timing utilities last
source "$SCRIPT_DIR/scripts/timing.sh"

# ==================================================================================

# Functions ========================================================================

# Format elapsed time like F1 lap times (MM:SS.mmm or SS.mmm)
format_f1_time() {
    local start_time_ns=$1
    local end_time_ns=$2
    
    # Calculate elapsed time in seconds (with decimal precision)
    local elapsed_seconds=$(echo "$end_time_ns - $start_time_ns" | bc -l)
    
    # Convert to total milliseconds (as integer to avoid floating point issues)
    local total_ms=$(echo "scale=0; ($elapsed_seconds * 1000 + 0.5)/1" | bc -l)
    
    # Extract minutes, seconds, and milliseconds using only integer arithmetic
    local minutes=$((total_ms / 60000))
    local remaining_ms=$((total_ms % 60000))
    local seconds=$((remaining_ms / 1000))
    local milliseconds=$((remaining_ms % 1000))
    
    # Format like F1 times
    if [[ $minutes -gt 0 ]]; then
        printf "%d:%02d.%03d" $minutes $seconds $milliseconds
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
#   -n, --news: show the news with the shortened link
#   -t, --timing: show function execution timing information"
#   --no-cache: disable caching for this run
#   --force: force refresh cache for this run
show_help() {
    echo "Usage: ./hcnews.sh [options]"
    echo "Options:"
    echo "  -h, --help: show the help"
    echo "  -s, --silent: the script will run silently"
    echo "  -sa, --saints: show the saints of the day with the verbose description"
    echo "  -n, --news: show the news with the shortened link"
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
    start_timing "help_hcnews"
    echo "🤝 *Quer contribuir com o HCNEWS?*"
    echo "- ✨ https://github.com/herijooj/HCnews"
    echo ""
    end_timing "help_hcnews"
}

# Função para imprimir o footer
function footer {
    start_timing "footer"
    end_time_precise=$(date +%s.%N)
    
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
        print_timing_summary
    fi
    
    end_timing "footer"
}

function hcseguidor {
    start_timing "hcseguidor"
    echo "🤖 *Quer ser um HCseguidor?*"
    echo "- 📢 https://whatsapp.com/channel/0029VaCRDb6FSAszqoID6k2Y"
    echo "- 💬 https://bit.ly/m/HCNews"
    echo ""
    end_timing "hcseguidor"
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
    newyorker=https://www.newyorker.com/feed/magazine/rss
    folha=https://feeds.folha.uol.com.br/mundo/rss091.xml
    g1=https://g1.globo.com/rss/g1/parana/
    formula1=https://www.formula1.com/content/fom-website/en/latest/all.xml
    bcc=http://feeds.bbci.co.uk/news/world/latin_america/rss.xml
    g1cinema=https://g1.globo.com/rss/g1/pop-arte/cinema/
    plantao190=https://plantao190.com.br/feed/

    # Combine feeds for parallel processing
    all_feeds="${o_popular},${plantao190},${g1}"

    # Write the header
    start_timing "write_header"
    write_header
    end_timing "write_header"

    # Write the holidays
    start_timing "write_holidays"
    write_holidays "$month" "$day"
    end_timing "write_holidays"

    # Write the states birthdays
    start_timing "write_states_birthdays"
    write_states_birthdays "$month" "$day"
    end_timing "write_states_birthdays"

    # Write the saint(s) of the day
    start_timing "write_saints"
    (source "$SCRIPT_DIR/scripts/saints.sh" $cache_options && write_saints "$saints_verbose")
    end_timing "write_saints"

    # Write the AI Fortune
    start_timing "write_ai_fortune"
    write_ai_fortune
    end_timing "write_ai_fortune"

    # Write the exchange rates
    start_timing "write_exchange"
    (source "$SCRIPT_DIR/scripts/exchange.sh" $cache_options && write_exchange)
    end_timing "write_exchange"

    # Ask to enter the Whatsapp Channel
    help_hcnews

    # Write the music chart
    start_timing "write_music_chart"
    (source "$SCRIPT_DIR/scripts/musicchart.sh" $cache_options && write_music_chart)
    end_timing "write_music_chart"

    # Write the weather
    start_timing "write_weather"
    (source "$SCRIPT_DIR/scripts/weather.sh" $cache_options && write_weather "$city" "false")
    end_timing "write_weather"

    # Write "Did you know?"
    start_timing "write_did_you_know"
    write_did_you_know
    end_timing "write_did_you_know"

    # Write the palpite of the day
    start_timing "write_bicho"
    write_bicho
    end_timing "write_bicho"

    # UFPR 

    # time to vacation
    #write_ferias
    
    # Help HCNEWS
    hcseguidor

    # menu of the day (use cached weekday instead of calling date)
    if [[ $weekday -lt 6 ]]; then
        start_timing "write_menu"
        SHOW_ONLY_TODAY=true
        (source "$SCRIPT_DIR/scripts/UFPR/ru.sh" $cache_options && write_menu) 
        end_timing "write_menu"
    fi

    # emoji of the day
    start_timing "write_emoji"
    write_emoji
    end_timing "write_emoji"

    # Write all news in parallel (major performance improvement)
    start_timing "write_all_news"
    (source "$SCRIPT_DIR/scripts/rss.sh" $cache_options && write_news "$all_feeds" "$news_shortened" true)
    end_timing "write_all_news"

    # # cinema
    # echo "🎬 G1 Cinema 🎬"
    # write_news "$g1cinema" "$news_shortened" "-n"

    # Write the F1 news
    # start_timing "write_f1_news"
    # f1_news=$(write_news "$formula1" "$news_shortened")
    # if [[ -n "$f1_news" ]]; then
    #     echo "🏎️ F1 🏎️"
    #     echo "$f1_news"
    # fi
    # end_timing "write_f1_news"

    # Write the footer
    footer
    
    end_timing "output"
}

# Main =============================================================================

# Get the arguments
get_arguments "$@"

# Cache all date operations at once to avoid multiple subprocess calls
# Use nanosecond precision for F1-style timing
current_date=$(date +"%s.%N %m %d %u %H:%M:%S %Y %-j")
read start_time_precise month day weekday current_time year days_since <<< "$current_date"
start_time=${start_time_precise%.*}  # Keep integer seconds for compatibility

# Export cached values so they're available to sourced scripts
export weekday month day year days_since start_time current_time start_time_precise

city="Curitiba"

# Reset timing data
reset_timing_data

# The script will now always output to standard output.
output "$saints_verbose" "$news_shortened" "$hc_no_cache" "$hc_force_refresh"
exit 0