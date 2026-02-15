#!/usr/bin/env bash
# =============================================================================
# RSS - RSS feed news fetcher with URL shortening
# =============================================================================
# Source: Various RSS feeds (configurable)
# Cache TTL: 7200 (2 hours)
# Output: News headlines from RSS feeds with optional shortened URLs
# =============================================================================

# -----------------------------------------------------------------------------
# Source Shortening Library
# -----------------------------------------------------------------------------
_rss_script_dir="${BASH_SOURCE%/*}"
[[ -n "${_HCNEWS_COMMON_LOADED:-}" ]] || source "${HCNEWS_COMMON_PATH:-${_rss_script_dir}/lib/common.sh}" 2>/dev/null || source "${_rss_script_dir}/scripts/lib/common.sh"
[[ -z "$(type -t shorten_url_isgd)" ]] && source "${_rss_script_dir}/shortening.sh"

# -----------------------------------------------------------------------------
# Configuration Constants
# -----------------------------------------------------------------------------
CACHE_TTL_SECONDS="${HCNEWS_CACHE_TTL["rss"]:-7200}"
_rss_cache_base="${HCNEWS_CACHE_DIR}/rss"
_rss_url_cache="${_rss_cache_base}/url_cache"
URL_CACHE_FILE="${_rss_url_cache}/url_shorten_cache.txt"
RSS_EMPTY_SENTINEL="__HCNEWS_RSS_EMPTY__"
RSS_FAIL_TTL_SECONDS="${HCNEWS_RSS_FAIL_TTL_SECONDS:-1800}"

# -----------------------------------------------------------------------------
# Cache Directory Setup
# -----------------------------------------------------------------------------
_rss_cache_ready=false

# -----------------------------------------------------------------------------
# Cache Management
# -----------------------------------------------------------------------------
_trim_url_cache() {
	local max_lines=1000
	if [[ -f "$URL_CACHE_FILE" ]]; then
		local current_lines
		current_lines=$(wc -l <"$URL_CACHE_FILE")
		if ((current_lines > max_lines)); then
			tail -n "$max_lines" "$URL_CACHE_FILE" >"${URL_CACHE_FILE}.tmp"
			mv "${URL_CACHE_FILE}.tmp" "$URL_CACHE_FILE"
		fi
	fi
}

_rss_ensure_cache_setup() {
	if [[ "$_rss_cache_ready" == "true" ]]; then
		return 0
	fi

	[[ -d "$_rss_cache_base" ]] || mkdir -p "$_rss_cache_base"
	[[ -d "$_rss_url_cache" ]] || mkdir -p "$_rss_url_cache"
	touch "$URL_CACHE_FILE"
	(_trim_url_cache &) >/dev/null 2>&1
	_rss_cache_ready=true
}

# -----------------------------------------------------------------------------
# Helper Functions
# -----------------------------------------------------------------------------
# URL shortening with caching
_rss_shorten_url() {
	local url="$1"
	local short_url
	_rss_ensure_cache_setup

	# Check cache first
	if [[ -s "$URL_CACHE_FILE" ]]; then
		short_url=$(grep -m 1 -F "$url|" "$URL_CACHE_FILE" | cut -d'|' -f2)
	fi

	if [[ -z "$short_url" ]]; then
		short_url=$(shorten_url_isgd "$url")
		if [[ -n "$short_url" ]]; then
			echo "$url|$short_url" >>"$URL_CACHE_FILE"
		fi
	fi

	echo "$short_url"
}

# Date conversion cache
declare -A DATE_CACHE

# Pure Bash RSS date to Unix timestamp
_rss_date_to_unix() {
	local date_str="$1"

	# Return from cache if available
	[[ -n "${DATE_CACHE[$date_str]:-}" ]] && {
		echo "${DATE_CACHE[$date_str]}"
		return
	}

	# Quick format check
	if [[ -z "$date_str" || ! $date_str =~ ^[A-Za-z,0-9\ ] ]]; then
		DATE_CACHE[$date_str]="0"
		echo "0"
		return
	fi

	# Parse RFC 2822 date
	local temp_date="${date_str#*, }"
	local day mon_name year hms _tz
	read -r day mon_name year hms _tz <<<"$temp_date"

	local hour min sec
	IFS=':' read -r hour min sec <<<"$hms"

	# Convert month name to number
	local mon
	case "${mon_name,,}" in
	jan) mon=1 ;; feb) mon=2 ;; mar) mon=3 ;; apr) mon=4 ;;
	may) mon=5 ;; jun) mon=6 ;; jul) mon=7 ;; aug) mon=8 ;;
	sep) mon=9 ;; oct) mon=10 ;; nov) mon=11 ;; dec) mon=12 ;;
	*)
		DATE_CACHE[$date_str]="0"
		echo "0"
		return
		;;
	esac

	# Calculate timestamp
	local y=$((10#$year)) m=$((10#$mon)) d=$((10#$day))
	local years_since_epoch=$((y - 1970))
	local leap_days=$(((y - 1969) / 4 - (y - 1901) / 100 + (y - 1601) / 400))
	local total_days=$((years_since_epoch * 365 + leap_days))
	local month_days=(0 31 28 31 30 31 30 31 31 30 31 30 31)

	if (((y % 4 == 0 && y % 100 != 0) || (y % 400 == 0))); then
		month_days[2]=29
	fi
	for ((i = 1; i < m; i++)); do
		total_days=$((total_days + month_days[i]))
	done
	total_days=$((total_days + d - 1))

	hour=$((10#$hour))
	min=$((10#$min))
	sec=$((10#$sec))
	local timestamp=$((total_days * 86400 + hour * 3600 + min * 60 + sec))

	DATE_CACHE[$date_str]="$timestamp"
	echo "$timestamp"
}

# -----------------------------------------------------------------------------
# Data Fetching Function
# -----------------------------------------------------------------------------
get_rss_data() {
	local feed_url="$1"
	local use_links="$2"
	local use_full_url="$3"
	_rss_ensure_cache_setup
	local use_cache="${_rss_USE_CACHE:-${_HCNEWS_USE_CACHE:-true}}"
	local force_refresh="${_rss_FORCE_REFRESH:-${_HCNEWS_FORCE_REFRESH:-false}}"

	# Generate portal identifier for cache using pure bash
	local portal_id="${feed_url#http*://}"
	portal_id="${portal_id//\//__}"
	portal_id="${portal_id//[^a-zA-Z0-9_.-]/}"

	local date_str
	date_str=$(hcnews_get_date_format)
	local rss_cache_dir="${_rss_cache_base}/rss_feeds/${portal_id}"
	[[ -d "$rss_cache_dir" ]] || mkdir -p "$rss_cache_dir"
	local fail_cache_file="${rss_cache_dir}/fail.cache"

	local target_cache_file="${rss_cache_dir}/${date_str}.news"
	if [[ "$use_links" == "true" ]]; then
		if [[ "$use_full_url" == "true" ]]; then
			target_cache_file="${rss_cache_dir}/${date_str}.links_full"
		else
			target_cache_file="${rss_cache_dir}/${date_str}.links"
		fi
	fi

	# Check cache first
	if [[ "$use_cache" == true ]] && hcnews_check_cache "$target_cache_file" "$CACHE_TTL_SECONDS" "$force_refresh"; then
		local cached
		cached=$(hcnews_read_cache "$target_cache_file") || return 0
		if [[ "$cached" == "$RSS_EMPTY_SENTINEL" ]]; then
			return 0
		fi
		printf '%s' "$cached"
		return 0
	fi

	# Skip fetch if recent failure backoff is active (unless forced)
	if [[ "$use_cache" == true && "$force_refresh" != "true" ]]; then
		if hcnews_check_cache "$fail_cache_file" "$RSS_FAIL_TTL_SECONDS" "false"; then
			return 0
		fi
	fi

	# Fetch feed content
	local feed_content
	feed_content=$(timeout 8s curl -s -4 --connect-timeout 2 --max-time 6 --retry 1 \
		--compressed -H "User-Agent: HCNews/1.0" "$feed_url" 2>/dev/null)

	# Exit if invalid content
	if [[ -z "$feed_content" || "$feed_content" != *"<item>"* ]]; then
		if [[ "$use_cache" == true ]]; then
			hcnews_write_cache "$fail_cache_file" "fetch_failed"
		fi
		return 1
	fi

	# Parse RSS items
	local all_data
	all_data=$(timeout 5s xmlstarlet sel -T -t \
		-m "/rss/channel/item[position()<=20]" \
		-v "concat(pubDate,'|',title,'|',link)" -n \
		<<<"$feed_content" 2>/dev/null)

	if [[ -z "$all_data" ]]; then
		if [[ "$use_cache" == true ]]; then
			hcnews_write_cache "$fail_cache_file" "parse_failed"
		fi
		return 1
	fi
	[[ -f "$fail_cache_file" ]] && rm -f "$fail_cache_file"

	# Get 24h timestamp
	local unix_24h_ago="${unix_24h_ago:-$(date -d "24 hours ago" +%s)}"

	# Process items
	local result=()
	local line_count=0
	while IFS='|' read -r date title link && [[ $line_count -lt 15 ]]; do
		[[ -z "$date" || -z "$title" ]] && continue

		if [[ "$date" =~ ^[A-Za-z]{3},.*[0-9]{4} ]]; then
			local date_unix
			date_unix=$(_rss_date_to_unix "$date")

			if ((date_unix > unix_24h_ago)); then
				result+=("- $title")
				if [[ "$use_links" == "true" ]]; then
					if [[ "$use_full_url" == "true" ]]; then
						result+=("    $link")
					else
						local short_url
						short_url=$(_rss_shorten_url "$link")
						result+=("    $short_url")
					fi
				fi
				((line_count++))
			fi
		fi
	done <<<"$all_data"

	if [[ ${#result[@]} -gt 0 ]]; then
		local news_output
		news_output=$(printf "%s\n" "${result[@]}")
		if [[ "$use_cache" == true ]]; then
			hcnews_write_cache "$target_cache_file" "$news_output"
		fi
		echo "$news_output"
		return 0
	fi

	# Cache empty results to avoid re-fetching feeds with no recent items.
	if [[ "$use_cache" == true ]]; then
		hcnews_write_cache "$target_cache_file" "$RSS_EMPTY_SENTINEL"
	fi
	return 0
}

# -----------------------------------------------------------------------------
# Output Function
# -----------------------------------------------------------------------------
hc_component_rss() {
	local feed_url="$1"
	local show_links="${2:-false}" # news_shortened
	local show_header="${3:-true}" # show header before each feed
	local full_url="${4:-false}"

	# Handle multiple feeds (comma-separated) in parallel
	local feeds=()
	if [[ "$feed_url" == *","* ]]; then
		IFS=',' read -ra feeds <<<"$feed_url"
	else
		feeds=("$feed_url")
	fi

	local tmp_dir=""
	local cleanup_tmp=false
	if [[ -n "${_HCNEWS_TEMP_DIR:-}" ]]; then
		tmp_dir="$_HCNEWS_TEMP_DIR"
	else
		tmp_dir="/tmp/hcnews_rss_$$"
		mkdir -p "$tmp_dir"
		cleanup_tmp=true
	fi

	local -a pids
	local -a out_files
	local -a portals
	local idx=0

	for feed in "${feeds[@]}"; do
		feed=$(echo "$feed" | xargs) # Trim whitespace
		[[ -z "$feed" ]] && continue

		local portal="${feed#http*://}"
		portal="${portal%%/*}"

		local out_file="${tmp_dir}/rss_${idx}.out"
		portals[idx]="$portal"
		out_files[idx]="$out_file"

		(get_rss_data "$feed" "$show_links" "$full_url" >"$out_file") &
		pids[idx]=$!
		((idx++))
	done

	for ((i = 0; i < idx; i++)); do
		[[ -n "${pids[$i]:-}" ]] && wait "${pids[$i]}" 2>/dev/null
		if [[ -f "${out_files[$i]}" ]]; then
			local content
			content=$(<"${out_files[$i]}")
			if [[ -n "$content" ]]; then
				[[ "$show_header" == "true" ]] && echo "📰 ${portals[$i]}:"
				echo "$content"
				echo ""
			fi
		fi
	done

	[[ "$cleanup_tmp" == true ]] && rm -rf "$tmp_dir"
}

# -----------------------------------------------------------------------------
# Help Function
# -----------------------------------------------------------------------------
show_help() {
	echo "Usage: ./rss.sh [options] <url>"
	echo "Fetches and displays news from RSS feeds."
	echo ""
	echo "Options:"
	echo "  -h, --help      Show this help message"
	echo "  -l, --linked    Show news with shortened URLs"
	echo "  -f, --full-url  Use full URLs instead of shortened (requires -l)"
	echo "  -n, --no-header Do not show the portal header"
	echo "  --no-cache      Bypass cache for this run"
	echo "  --force         Force refresh cached data"
	echo ""
	echo "Examples:"
	echo "  ./rss.sh -l <url>                    # Show news with shortened URLs"
	echo "  ./rss.sh -l -f <url>                 # Show news with full URLs"
	echo "  ./rss.sh -l 'url1,url2,url3'         # Process multiple feeds"
}

# -----------------------------------------------------------------------------
# Main Entry Point
# -----------------------------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	hcnews_parse_args "$@"
	_rss_USE_CACHE=$_HCNEWS_USE_CACHE
	_rss_FORCE_REFRESH=$_HCNEWS_FORCE_REFRESH
	set -- "${_HCNEWS_REMAINING_ARGS[@]}"

	show_header=true
	full_url=false
	show_links=false
	feed_url=""

	while [[ $# -gt 0 ]]; do
		case "$1" in
		-h | --help)
			show_help
			exit 0
			;;
		-l | --linked)
			show_links=true
			;;
		-f | --full-url)
			full_url=true
			;;
		-n | --no-header)
			show_header=false
			;;
		--no-cache)
			_rss_USE_CACHE=false
			;;
		--force)
			_rss_FORCE_REFRESH=true
			;;
		*)
			feed_url="$1"
			;;
		esac
		shift
	done

	if [[ -z "$feed_url" ]]; then
		echo "Error: Feed URL is required"
		show_help
		exit 1
	fi

	if [[ "$full_url" == "true" && "$show_links" == "false" ]]; then
		echo "Warning: -f/--full-url requires -l/--linked"
		full_url=false
	fi

	hc_component_rss "$feed_url" "$show_links" "$show_header" "$full_url"
fi
