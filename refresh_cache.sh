#!/usr/bin/env bash
# Background cache refresh script for HCNews components
# This script runs periodically to ensure caches are always fresh
# It respects TTL settings and doesn't force refresh - just triggers the scripts

SCRIPT_DIR=$(dirname "$(realpath "${BASH_SOURCE[0]}")")

# Source configuration (defaults + local overrides)
source "$SCRIPT_DIR/config.sh" 2>/dev/null || true
[[ -f "$SCRIPT_DIR/config.local.sh" ]] && source "$SCRIPT_DIR/config.local.sh"

# Source required scripts
source "$SCRIPT_DIR/scripts/timing.sh"
source "$SCRIPT_DIR/scripts/lib/common.sh"
source "$SCRIPT_DIR/scripts/lib/components.sh"

# Configuration
REFRESH_LOG="$SCRIPT_DIR/data/cache/refresh.log"
MAX_LOG_LINES=500

# Components to refresh (in order of importance/slowness)
declare -A COMPONENTS=(
	["ru"]="$SCRIPT_DIR/scripts/UFPR/ru.sh"
	["weather"]="$SCRIPT_DIR/scripts/weather.sh"
	["musicchart"]="$SCRIPT_DIR/scripts/musicchart.sh"
	["sanepar"]="$SCRIPT_DIR/scripts/sanepar.sh"
	["exchange"]="$SCRIPT_DIR/scripts/exchange.sh"
	["rss"]="$SCRIPT_DIR/scripts/rss.sh"
	["saints"]="$SCRIPT_DIR/scripts/saints.sh"
	["bicho"]="$SCRIPT_DIR/scripts/bicho.sh"
	["moonphase"]="$SCRIPT_DIR/scripts/moonphase.sh"
	["quote"]="$SCRIPT_DIR/scripts/quote.sh"
	["didyouknow"]="$SCRIPT_DIR/scripts/didyouknow.sh"
	["futuro"]="$SCRIPT_DIR/scripts/futuro.sh"
)

validate_component_map() {
	local name
	for name in "${!COMPONENTS[@]}"; do
		if ! hc_component_raw "$name" >/dev/null 2>&1; then
			log_message "WARN" "SYSTEM" "Component '$name' not found in registry"
		fi
	done
}

# Logging function
log_message() {
	local level="$1"
	local component="$2"
	local message="$3"
	local timestamp
	timestamp=$(date '+%Y-%m-%d %H:%M:%S')
	echo "[$timestamp] [$level] [$component] $message" >>"$REFRESH_LOG"
}

# Trim log file to prevent it from growing too large
trim_log() {
	if [[ -f "$REFRESH_LOG" && $(wc -l <"$REFRESH_LOG") -gt $MAX_LOG_LINES ]]; then
		tail -n $MAX_LOG_LINES "$REFRESH_LOG" >"${REFRESH_LOG}.tmp"
		mv "${REFRESH_LOG}.tmp" "$REFRESH_LOG"
	fi
}

# Build RSS feed list from config
build_rss_feed_list() {
	local feeds=""
	local have_feeds=false
	declare -p HCNEWS_FEEDS &>/dev/null && have_feeds=true

	if [[ -n "${HCNEWS_FEEDS_PRIMARY:-}" && "$have_feeds" == true ]]; then
		IFS=',' read -ra feed_keys <<<"$HCNEWS_FEEDS_PRIMARY"
		for key in "${feed_keys[@]}"; do
			key=$(echo "$key" | xargs)
			# Disabled: xvcuritiba feed failing DNS resolution
			[[ -z "$key" || "$key" == "xvcuritiba" ]] && continue
			local url="${HCNEWS_FEEDS[$key]:-}"
			[[ -z "$url" ]] && continue
			[[ -n "$feeds" ]] && feeds+=","
			feeds+="$url"
		done
	fi

	if [[ -z "$feeds" ]]; then
		feeds="https://opopularpr.com.br/feed/,https://plantao190.com.br/feed/"
	fi

	echo "$feeds"
}

# Refresh a single component
refresh_component() {
	local name="$1"
	local script="$2"
	local timeout=30 # 30 second timeout per component

	if [[ ! -f "$script" ]]; then
		log_message "ERROR" "$name" "Script not found: $script"
		return 1
	fi

	log_message "INFO" "$name" "Starting refresh"
	local start_time
	start_time=$(date +%s%N)

	# Run component with timeout
	case "$name" in
	"ru")
		timeout $timeout bash -c "source '$script' && SELECTED_LOCATION='politecnico' && SHOW_ONLY_TODAY=true && hc_component_ru" >/dev/null 2>&1
		;;
	"weather")
		timeout $timeout bash -c "source '$script' && hc_component_weather 'Curitiba'" >/dev/null 2>&1
		;;
	"musicchart")
		timeout $timeout bash -c "source '$script' && hc_component_musicchart" >/dev/null 2>&1
		;;
	"sanepar")
		timeout $timeout bash -c "source '$script' && hc_component_sanepar" >/dev/null 2>&1
		;;
	"exchange")
		timeout $timeout bash -c "source '$script' && hc_component_exchange" >/dev/null 2>&1
		;;
	"rss")
		# Refresh main RSS feeds
		local feeds
		feeds=$(build_rss_feed_list)
		timeout $timeout bash -c "source '$script' && hc_component_rss '$feeds' false true" >/dev/null 2>&1
		;;
	"saints")
		timeout $timeout bash -c "source '$script' && hc_component_saints true" >/dev/null 2>&1
		;;
	"bicho")
		timeout $timeout bash -c "source '$script' && hc_component_bicho" >/dev/null 2>&1
		;;
	"moonphase")
		timeout $timeout bash -c "source '$script' && hc_component_moonphase" >/dev/null 2>&1
		;;
	"quote")
		timeout $timeout bash -c "source '$script' && hc_component_quote" >/dev/null 2>&1
		;;
	"didyouknow")
		timeout $timeout bash -c "source '$script' && hc_component_didyouknow" >/dev/null 2>&1
		;;
	"futuro")
		timeout $timeout bash -c "source '$script' && hc_component_futuro" >/dev/null 2>&1
		;;
	*)
		log_message "ERROR" "$name" "Unknown component"
		return 1
		;;
	esac

	local exit_code=$?
	local end_time
	end_time=$(date +%s%N)
	local elapsed_ms=$(((end_time - start_time) / 1000000))

	if [[ $exit_code -eq 0 ]]; then
		log_message "INFO" "$name" "Refresh completed in ${elapsed_ms}ms"
	elif [[ $exit_code -eq 124 ]]; then
		log_message "WARN" "$name" "Refresh timed out after ${timeout}s"
	else
		log_message "ERROR" "$name" "Refresh failed with exit code $exit_code"
	fi

	return $exit_code
}

# Main refresh function
refresh_all() {
	local start_time
	start_time=$(date +%s%N)
	local success_count=0
	local total_count=${#COMPONENTS[@]}

	log_message "INFO" "SYSTEM" "Starting background refresh cycle"
	validate_component_map

	# Ensure cache directories exist
	mkdir -p "$SCRIPT_DIR/data/cache"

	# Refresh components in parallel for better performance
	declare -A pids

	for name in "${!COMPONENTS[@]}"; do
		refresh_component "$name" "${COMPONENTS[$name]}" &
		pids["$name"]=$!
	done

	# Wait for all background jobs and collect results
	for name in "${!pids[@]}"; do
		if wait "${pids[$name]}"; then
			((success_count++))
		fi
	done

	local end_time
	end_time=$(date +%s%N)
	local elapsed_ms=$(((end_time - start_time) / 1000000))

	log_message "INFO" "SYSTEM" "Refresh cycle completed: $success_count/$total_count successful in ${elapsed_ms}ms"

	# Trim log file
	trim_log
}

# Show current cache status
show_status() {
	echo "🔄 HCNews Cache Refresh Status"
	echo "=============================="
	echo

	if [[ -f "$REFRESH_LOG" ]]; then
		echo "📊 Recent Activity (last 10 entries):"
		tail -n 10 "$REFRESH_LOG" | while IFS= read -r line; do
			echo "  $line"
		done
		echo

		echo "📈 Success Rate (last 50 operations):"
		local total
		total=$(tail -n 50 "$REFRESH_LOG" | grep -c "INFO.*Refresh completed")
		local errors
		errors=$(tail -n 50 "$REFRESH_LOG" | grep -c "ERROR\|WARN")
		local success_rate=0
		if [[ $total -gt 0 ]]; then
			success_rate=$(((total * 100) / (total + errors)))
		fi
		echo "  Success: $total operations"
		echo "  Errors/Warnings: $errors operations"
		echo "  Success Rate: ${success_rate}%"
	else
		echo "📝 No refresh log found. Run 'refresh_cache.sh' to start."
	fi
	echo

	echo "🗂️  Cache Directories:"
	if [[ -d "$SCRIPT_DIR/data/cache" ]]; then
		find "$SCRIPT_DIR/data/cache" -name "*.cache" -o -name "*.ru" -o -name "*.exchange" -o -name "*.musicchart" |
			while read -r file; do
				local age_seconds=$(($(date +%s) - $(stat -c %Y "$file")))
				local age_hours=$((age_seconds / 3600))
				local age_minutes=$(((age_seconds % 3600) / 60))
				echo "  $(basename "$file"): ${age_hours}h ${age_minutes}m old"
			done | sort
	else
		echo "  Cache directory not found"
	fi
}

# Help function
show_help() {
	echo "HCNews Background Cache Refresh Tool"
	echo "===================================="
	echo
	echo "Usage: $0 [command] [options]"
	echo
	echo "Commands:"
	echo "  refresh, -r     Run a single refresh cycle"
	echo "  status, -s      Show current cache status and recent activity"
	echo "  setup-cron      Show commands to setup automated refresh"
	echo "  help, -h        Show this help message"
	echo
	echo "Options:"
	echo "  --component NAME  Refresh only specific component"
	echo "                   Available: ${!COMPONENTS[*]}"
	echo
	echo "Examples:"
	echo "  $0 refresh                    # Refresh all components once"
	echo "  $0 refresh --component ru     # Refresh only RU component"
	echo "  $0 status                     # Show cache status"
	echo "  $0 setup-cron                # Show cron setup commands"
}

# Show cron setup instructions
show_cron_setup() {
	echo "🕒 Setting up Automated Refresh"
	echo "==============================="
	echo
	echo "To automatically refresh caches every 30 minutes, add this to your crontab:"
	echo
	echo "# HCNews cache refresh every 30 minutes"
	echo "*/30 * * * * $SCRIPT_DIR/refresh_cache.sh refresh >/dev/null 2>&1"
	echo
	echo "To add it automatically, run:"
	echo "  (crontab -l 2>/dev/null; echo '*/30 * * * * $SCRIPT_DIR/refresh_cache.sh refresh >/dev/null 2>&1') | crontab -"
	echo
	echo "To check current crontab:"
	echo "  crontab -l"
	echo
	echo "To remove it later:"
	echo "  crontab -l | grep -v 'refresh_cache.sh' | crontab -"
	echo
	echo "Alternative: Systemd Timer (for systemd-based systems)"
	echo "Create /etc/systemd/system/hcnews-refresh.service:"
	echo "[Unit]"
	echo "Description=HCNews Cache Refresh"
	echo
	echo "[Service]"
	echo "Type=oneshot"
	echo "User=$(whoami)"
	echo "ExecStart=$SCRIPT_DIR/refresh_cache.sh refresh"
	echo "WorkingDirectory=$SCRIPT_DIR"
	echo
	echo "Create /etc/systemd/system/hcnews-refresh.timer:"
	echo "[Unit]"
	echo "Description=Run HCNews Cache Refresh every 30 minutes"
	echo "Requires=hcnews-refresh.service"
	echo
	echo "[Timer]"
	echo "OnCalendar=*:0/30"
	echo "Persistent=true"
	echo
	echo "[Install]"
	echo "WantedBy=timers.target"
	echo
	echo "Then enable with:"
	echo "  sudo systemctl enable hcnews-refresh.timer"
	echo "  sudo systemctl start hcnews-refresh.timer"
}

# Parse arguments
case "${1:-help}" in
"refresh" | "-r")
	validate_component_map
	if [[ "$2" == "--component" && -n "$3" ]]; then
		component="$3"
		if [[ -n "${COMPONENTS[$component]}" ]]; then
			echo "🔄 Refreshing component: $component"
			refresh_component "$component" "${COMPONENTS[$component]}"
			exit $?
		else
			echo "❌ Unknown component: $component"
			echo "Available components: ${!COMPONENTS[*]}"
			exit 1
		fi
	else
		echo "🔄 Starting background refresh cycle..."
		refresh_all
	fi
	;;
"status" | "-s")
	show_status
	;;
"setup-cron")
	show_cron_setup
	;;
"help" | "-h" | "--help")
	show_help
	;;
*)
	echo "❌ Unknown command: $1"
	echo "Use '$0 help' for usage information."
	exit 1
	;;
esac
