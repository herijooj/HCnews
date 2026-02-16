#!/usr/bin/env bash
# this project is licensed under the GPL. See the LICENSE file for more information

# Includes ========================================================================
SCRIPT_DIR=$(dirname "$(realpath "${BASH_SOURCE[0]}")")
export HCNEWS_HOME="$SCRIPT_DIR"
_HCNEWS_ALLOW_HELP=false

# Source configuration (defaults)
# config.local.sh will override these settings if it exists
source "$SCRIPT_DIR/config.sh" 2>/dev/null || true
# Source local overrides if they exist
[[ -f "$SCRIPT_DIR/config.local.sh" ]] && source "$SCRIPT_DIR/config.local.sh"

# Source all the required scripts
source "$SCRIPT_DIR/scripts/lib/common.sh"
export HCNEWS_COMMON_PATH="$SCRIPT_DIR/scripts/lib/"
source "$SCRIPT_DIR/scripts/lib/components.sh"
source "$SCRIPT_DIR/scripts/header.sh"
source "$SCRIPT_DIR/scripts/moonphase.sh"
source "$SCRIPT_DIR/scripts/saints.sh"
source "$SCRIPT_DIR/scripts/rss.sh"
source "$SCRIPT_DIR/scripts/exchange.sh"
source "$SCRIPT_DIR/scripts/weather.sh"
source "$SCRIPT_DIR/scripts/sports.sh"
source "$SCRIPT_DIR/scripts/didyouknow.sh"
source "$SCRIPT_DIR/scripts/holidays.sh"
source "$SCRIPT_DIR/scripts/bicho.sh"
source "$SCRIPT_DIR/scripts/states.sh"
source "$SCRIPT_DIR/scripts/emoji.sh"
source "$SCRIPT_DIR/scripts/UFPR/ru.sh"
# Source timing utilities last
source "$SCRIPT_DIR/scripts/timing.sh"
source "$SCRIPT_DIR/scripts/onthisday.sh"

# ==================================================================================

HOSTNAME=$(hostname)

# Global outputs populated by orchestrator
header_core_output=""
moon_phase_output=""
holidays_output=""
states_output=""
weather_output=""
news_output=""
exchange_output=""
sports_output=""
onthisday_output=""
didyouknow_output=""
bicho_output=""
saints_output=""
ru_output=""
emoji_output=""

# Runtime defaults (safe when sourced)
saints_verbose=true
news_shortened=false
timing=false
hc_no_cache=false
hc_force_refresh=false
hc_full_url=false
city="${HCNEWS_CITY:-Curitiba}"
ru_location="${HCNEWS_RU_LOCATION:-politecnico}"

_HCNEWS_RUNTIME_INITIALIZED=false

hc_trim_var() {
	local -n s_ref="$1"
	# shellcheck disable=SC2034
	s_ref="${s_ref#"${s_ref%%[![:space:]]*}"}"
	# shellcheck disable=SC2034
	s_ref="${s_ref%"${s_ref##*[![:space:]]}"}"
}

# Functions ========================================================================

# Background job management
source "$SCRIPT_DIR/scripts/lib/jobs.sh"
source "$SCRIPT_DIR/scripts/lib/orchestrator.sh"

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
hcnews_show_help() {
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
}

# this function will receive the arguments
parse_main_arguments() {
	# Define variables
	# shellcheck disable=SC2034
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
		-h | --help)
			hcnews_show_help
			exit 0
			;;
		-s | --silent)
			# shellcheck disable=SC2034
			silent=true
			shift
			;;
		-sa | --saints)
			saints_verbose=true
			shift
			;;
		-n | --news)
			news_shortened=true
			shift
			;;
		-t | --timing)
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
			hcnews_show_help
			exit 1
			;;
		esac
	done
}

# Função para imprimir o footer
function footer {
	# Get end time in nanoseconds using the same format as start
	local end_date
	end_date=$(date +"%s %N")
	read -r end_time_seconds end_time_nanos <<<"$end_date"
	local end_time_precise=$((end_time_seconds * 1000000000 + 10#$end_time_nanos))

	# Calculate F1-style elapsed time
	elapsed_f1_time=$(format_f1_time "$start_time_precise" "$end_time_precise")

	echo "🔔 *HCNews:* Seu Jornal Automático Diário"
	echo "- 📡 Stack: RSS • Bash • Python • Nix"
	echo "- 🔗 https://github.com/herijooj/HCnews"
	echo "🙌 *Que Deus abençoe a todos!*"
	echo ""
	echo "🤖 ${current_time} (BRT) ⏱️ ${elapsed_f1_time} on ${HOSTNAME}"

	# Add timing summary if enabled
	if [[ $timing == true ]]; then
		echo ""
		# Load timing entries from shared file (for cross-subshell persistence)
		load_timing_entries
		print_timing_summary
	fi
}

# Master orchestration function to fetch all data needed for the newspaper
# Populates global variables with content
fetch_newspaper_data() {
	hcnews_init_runtime
	hc_orch_fetch_main_data "$city" "$saints_verbose" "$ru_location" "$month" "$day"
}

render_output() {
	# This function strictly outputs the global variables populated by fetch_newspaper_data.
	# It assumes data is already fetched.
	# For news, it checks if news_output is set (by CLI/build script).

	# 1. Header Core
	echo "$header_core_output"

	# 2. Moon Phase
	echo "$moon_phase_output"
	echo ""

	# 3. Holidays
	echo "$holidays_output"

	# 4. States & Birthdays
	echo "$states_output"

	# 5. Weather
	if [[ -n "$weather_output" ]]; then
		echo "$weather_output"
		echo ""
	fi

	# 6. News
	if [[ -n "$news_output" ]]; then
		echo "$news_output"
		echo ""
	fi

	# 7. Exchange
	if [[ -n "$exchange_output" ]]; then
		echo "$exchange_output"
		echo ""
	fi

	# 8. Sports
	if [[ -n "$sports_output" ]]; then
		echo "$sports_output"
		echo ""
	fi

	# 9. On This Day
	if [[ -n "$onthisday_output" ]]; then
		echo "$onthisday_output"
		echo ""
	fi

	# 10. Did You Know?
	if [[ -n "$didyouknow_output" ]]; then
		echo "$didyouknow_output"
		echo ""
	fi

	# 11. Bicho
	if [[ -n "$bicho_output" ]]; then
		echo "$bicho_output"
		echo ""
	fi

	# 12. Saints
	if [[ -n "$saints_output" ]]; then
		echo "$saints_output"
		echo ""
	fi

	# 13. RU (weekdays only)
	if [[ "$weekday" -ge 1 && "$weekday" -le 5 && -n "$ru_output" ]]; then
		echo "$ru_output"
		echo ""
	fi

	# 14. Emoji
	echo "$emoji_output"
	echo ""
}

function output {
	hcnews_init_runtime
	start_timing "output"

	# Define variables
	saints_verbose=$1
	news_shortened=$2

	# Explicitly start news generation for CLI mode FIRST (heaviest task)
	start_background_job "all_news" "(_rss_USE_CACHE=\$_HCNEWS_USE_CACHE; _rss_FORCE_REFRESH=\$_HCNEWS_FORCE_REFRESH; hc_component_rss '$all_feeds' '$news_shortened' true ${hc_full_url})"

	# Fetch all other data
	fetch_newspaper_data

	# Wait for news content
	news_output=$(wait_for_job "all_news")
	if [[ $? -ne 0 || -z "$news_output" ]]; then
		# Fallback if job failed (shouldn't happen in normal CLI flow)
		news_output=$(
			_rss_USE_CACHE=$_HCNEWS_USE_CACHE
			_rss_FORCE_REFRESH=$_HCNEWS_FORCE_REFRESH
			hc_component_rss "$all_feeds" "$news_shortened" true ${hc_full_url}
		)
	fi

	# Render everything
	render_output

	# Restore footer for CLI output
	footer

	end_timing "output"
}

hcnews_init_runtime() {
	if [[ "$_HCNEWS_RUNTIME_INITIALIZED" == true ]]; then
		return 0
	fi

	# Ensure cache flags are always initialized for internal function calls
	: "${_HCNEWS_USE_CACHE:=true}"
	: "${_HCNEWS_FORCE_REFRESH:=false}"
	export _HCNEWS_USE_CACHE _HCNEWS_FORCE_REFRESH

	# Initialize cache directories once runtime starts
	hcnews_init_cache_dirs

	# Initialize background jobs once
	init_jobs

	# Cache all date operations at once to avoid multiple subprocess calls
	current_date=$(date +"%s %N %m %d %u %H:%M:%S %Y %-j %Y%m%d")
	read -r start_time_seconds start_time_nanos month day weekday current_time year days_since date_format <<<"$current_date"

	start_time_precise=$((start_time_seconds * 1000000000 + 10#$start_time_nanos))
	start_time=$start_time_seconds
	unix_24h_ago=$((start_time - 86400))

	export weekday month day year days_since start_time current_time start_time_precise date_format unix_24h_ago

	# Reset timing data and initialize timing file for cross-subshell persistence
	reset_timing_data
	init_timing_file

	# Apply run-specific cache flags
	if [[ "$hc_no_cache" == true ]]; then
		export _HCNEWS_USE_CACHE=false
	fi
	if [[ "$hc_force_refresh" == true ]]; then
		export _HCNEWS_FORCE_REFRESH=true
	fi

	# RSS feed globals (can be overridden via config.sh)
	if [[ -v HCNEWS_FEEDS[@] ]]; then
		unset 'HCNEWS_FEEDS[xvcuritiba]'
		o_popular="${HCNEWS_FEEDS[opopular]:-https://opopularpr.com.br/feed/}"
		plantao190="${HCNEWS_FEEDS[plantao190]:-https://plantao190.com.br/feed/}"
		bandab="${HCNEWS_FEEDS[bandab]:-https://www.bandab.com.br/web-stories/feed/}"
		newyorker="${HCNEWS_FEEDS[newyorker]:-https://www.newyorker.com/feed/magazine/rss}"
		folha="${HCNEWS_FEEDS[folha]:-https://feeds.folha.uol.com.br/mundo/rss091.xml}"
		formula1="${HCNEWS_FEEDS[formula1]:-https://www.formula1.com/content/fom-website/en/latest/all.xml}"
	else
		o_popular="https://opopularpr.com.br/feed/"
		plantao190="https://plantao190.com.br/feed/"
		bandab="https://www.bandab.com.br/web-stories/feed/"
		newyorker="https://www.newyorker.com/feed/magazine/rss"
		folha="https://feeds.folha.uol.com.br/mundo/rss091.xml"
		formula1="https://www.formula1.com/content/fom-website/en/latest/all.xml"
	fi

	# Build all_feeds from comma-separated feed keys
	if [[ -n "${HCNEWS_FEEDS_PRIMARY:-}" ]]; then
		local -a feed_keys
		local key local_feed_url
		all_feeds=""
		IFS=',' read -ra feed_keys <<<"$HCNEWS_FEEDS_PRIMARY"
		for key in "${feed_keys[@]}"; do
			hc_trim_var key
			[[ -z "$key" || "$key" == "xvcuritiba" ]] && continue
			local_feed_url="${HCNEWS_FEEDS[$key]:-}"
			[[ -z "$local_feed_url" ]] && continue
			[[ -n "$all_feeds" ]] && all_feeds+=","
			all_feeds+="$local_feed_url"
		done
		[[ -z "$all_feeds" ]] && all_feeds="${o_popular},${plantao190}"
	else
		all_feeds="${o_popular},${plantao190}"
	fi

	_HCNEWS_RUNTIME_INITIALIZED=true
}

# Function to calculate reading time based on word count
calculate_reading_time() {
	local content="$1"
	local words_per_minute=220 # Average reading speed in Portuguese

	# Count words (remove emojis and special characters for more accurate count)
	local word_count
	word_count=$(echo "$content" | sed 's/[🔗📰⏳🇧🇷📅🌙💭🎵☀️🌧️❄️🌈⚡🔥💧🌪️🌡️📊💰📈📉🙏✨🎯📢💬🤖🔔🙌🤝📡💎🎭🎨🎪🎊🎉]//' | wc -w)

	# Calculate reading time in minutes
	local reading_time_minutes=$((word_count / words_per_minute))

	# Ensure minimum of 1 minute
	if [[ $reading_time_minutes -lt 1 ]]; then
		reading_time_minutes=1
	fi

	echo "$reading_time_minutes"
}

# Modified function to add reading time to existing header
function hc_render_header_with_reading_time() {
	local reading_time="$1"

	# Get the existing header output
	hc_component_header

	# Add the reading time line after the header
	echo "📖 Tempo total de leitura: ~${reading_time} min"
}
# If running directly, execute the output generation
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	parse_main_arguments "$@"
	hcnews_init_runtime

	# Capture all output to calculate reading time, then output with reading time in header
	content_output=$(output "$saints_verbose" "$news_shortened")

	# Calculate reading time based on the complete content
	reading_time=$(calculate_reading_time "$content_output")

	# Output header with reading time first
	hc_render_header_with_reading_time "$reading_time"

	# Extract and output everything after the header core (moon phase onwards)
	echo "$content_output" | sed '1,4d' # Skip the first 4 lines (header core)

	exit 0
fi
