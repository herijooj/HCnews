#!/usr/bin/env bash
# =============================================================================
# Sports - Brazilian Football (Brasileirão, Copa do Brasil, Libertadores)
# =============================================================================
# Source: ESPN public API (free, no auth required)
# Output: Yesterday's results + today's games
# =============================================================================

# -----------------------------------------------------------------------------
# Source Common Library
# -----------------------------------------------------------------------------
[[ -n "${_HCNEWS_COMMON_LOADED:-}" ]] || source "${HCNEWS_COMMON_PATH}common.sh" 2>/dev/null || source "${BASH_SOURCE%/*}/lib/common.sh"

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
CACHE_TTL_SECONDS="${HCNEWS_CACHE_TTL["sports"]:-1800}"
BASE_URL="https://site.api.espn.com/apis/site/v2/sports/soccer"
DISPLAY_TZ="${HCNEWS_TZ:-America/Sao_Paulo}"
CURL_CONNECT_TIMEOUT="${HCNEWS_SPORTS_CONNECT_TIMEOUT:-6}"
CURL_MAX_TIME="${HCNEWS_SPORTS_MAX_TIME:-12}"
CURL_RETRY="${HCNEWS_SPORTS_RETRY:-5}"

# Competition definitions: slug|display_name|emoji
COMPETITIONS=(
	"bra.1|Brasileirão Série A|⚽"
	"bra.copa_do_brazil|Copa do Brasil|🏆"
	"conmebol.libertadores|Libertadores|🏆"
)

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
_sports_format_time() {
	local ts="$1"
	if [[ -z "$ts" || "$ts" == "null" ]]; then
		echo "--:--"
		return
	fi
	TZ="$DISPLAY_TZ" date -d "$ts" +"%H:%M" 2>/dev/null || echo "${ts:11:5}"
}

_sports_format_line() {
	local state="$1" home="$2" away="$3" hscore="$4" ascore="$5" datetime="$6"
	if [[ "$state" == "pre" ]]; then
		echo "${home} x ${away} ($(_sports_format_time "$datetime"))"
	elif [[ "$state" == "in" ]]; then
		echo "${home} ${hscore}x${ascore} ${away} (ao vivo)"
	else
		echo "${home} ${hscore}x${ascore} ${away}"
	fi
}

# -----------------------------------------------------------------------------
# ESPN API - Fetch games for a specific league and date
# -----------------------------------------------------------------------------
_sports_fetch_league_day() {
	local slug="$1" iso_date="$2" day_type="$3"
	local curl_opts=(-s -L -4 --compressed --connect-timeout "$CURL_CONNECT_TIMEOUT" --max-time "$CURL_MAX_TIME" --retry "$CURL_RETRY" --retry-delay 5 --retry-all-errors)

	local response
	response=$(curl "${curl_opts[@]}" "${BASE_URL}/${slug}/scoreboard?dates=${iso_date//-/}") || return 0

	local events
	events=$(echo "$response" | jq -r '
		.events[] | [
			(.competitions[0].competitors[] | select(.homeAway == "home") | .team.shortDisplayName),
			(.competitions[0].competitors[] | select(.homeAway == "away") | .team.shortDisplayName),
			(.competitions[0].competitors[] | select(.homeAway == "home") | .score // ""),
			(.competitions[0].competitors[] | select(.homeAway == "away") | .score // ""),
			.date,
			.competitions[0].status.type.state,
			(.competitions[0].status.type.completed | tostring)
		] | join("|")
	' 2>/dev/null)

	[[ -z "$events" ]] && return 0

	local output_lines=()
	local home away hscore ascore datetime state
	while IFS='|' read -r home away hscore ascore datetime state _; do
		if [[ "$day_type" == "yesterday" ]] && [[ "$state" != "post" ]]; then continue; fi

		local line
		line=$(_sports_format_line "$state" "$home" "$away" "$hscore" "$ascore" "$datetime")
		output_lines+=("- ${line}")
	done <<<"$events"

	printf '%s\n' "${output_lines[@]}"
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
get_sports_block() {
	local use_cache="${_sports_USE_CACHE:-${_HCNEWS_USE_CACHE:-true}}"
	local force_refresh="${_sports_FORCE_REFRESH:-${_HCNEWS_FORCE_REFRESH:-false}}"

	local base_date cache_key today_iso
	if [[ -n "${_sports_base_date:-}" ]]; then
		base_date="$_sports_base_date"
		if ! TZ="$DISPLAY_TZ" date -d "$base_date" >/dev/null 2>&1; then
			base_date="$(TZ="$DISPLAY_TZ" date +%F)"
		fi
		today_iso="$base_date"
	else
		today_iso="$(TZ="$DISPLAY_TZ" date +%F)"
	fi

	cache_key="${today_iso//-/}"

	local cache_file
	hcnews_set_cache_path cache_file "sports" "$cache_key"

	if [[ "$use_cache" == true ]] && hcnews_check_cache "$cache_file" "$CACHE_TTL_SECONDS" "$force_refresh"; then
		hcnews_read_cache "$cache_file"
		return 0
	fi

	local yesterday_iso
	yesterday_iso=$(TZ="$DISPLAY_TZ" date -d "$today_iso -1 day" +%F)

	local base_tmp_dir="${_HCNEWS_TEMP_DIR:-/tmp}"
	[[ -d "$base_tmp_dir" ]] || base_tmp_dir="/tmp"

	local block=""
	local has_content=false

	for comp in "${COMPETITIONS[@]}"; do
		local slug="${comp%%|*}"
		local rest="${comp#*|}"
		local comp_name="${rest%%|*}"
		local comp_emoji="${rest##*|}"

		local today_file="${base_tmp_dir}/sports_${slug}_today_$$.txt"
		local yesterday_file="${base_tmp_dir}/sports_${slug}_yesterday_$$.txt"

		(_sports_fetch_league_day "$slug" "$today_iso" "today") >"$today_file" &
		local today_pid=$!
		(_sports_fetch_league_day "$slug" "$yesterday_iso" "yesterday") >"$yesterday_file" &
		local yesterday_pid=$!

		wait "$today_pid" 2>/dev/null || true
		wait "$yesterday_pid" 2>/dev/null || true

		local today_games yesterday_games
		today_games=$(<"$today_file")
		yesterday_games=$(<"$yesterday_file")
		rm -f "$today_file" "$yesterday_file"

		[[ -z "$today_games" && -z "$yesterday_games" ]] && continue

		has_content=true
		block+="${comp_emoji} *${comp_name}*"

		if [[ -n "$today_games" ]]; then
			block+=$'\n'"📅 Hoje:"
			block+=$'\n'"$today_games"
		fi

		if [[ -n "$yesterday_games" ]]; then
			block+=$'\n'"🥅 Ontem:"
			block+=$'\n'"$yesterday_games"
		fi

		block+=$'\n\n'
	done

	if [[ "$has_content" == false ]]; then
		block="- Nenhum jogo encontrado"
	fi

	[[ "$use_cache" == true ]] && hcnews_write_cache "$cache_file" "$block"
	printf '%s' "$block"
}

hc_component_sports() {
	get_sports_block
}

# Standalone execution
show_help() {
	cat <<EOF
Usage: ./sports.sh [--no-cache|--force]
Fetches Brazilian football scores (yesterday) and today's fixtures from ESPN.
--date=YYYY-MM-DD  Override base date (mainly for debugging)
EOF
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	hcnews_parse_args "$@"
	_sports_USE_CACHE=${_HCNEWS_USE_CACHE:-true}
	_sports_FORCE_REFRESH=${_HCNEWS_FORCE_REFRESH:-false}
	_sports_base_date=""

	for _arg in "${_HCNEWS_REMAINING_ARGS[@]}"; do
		case "$_arg" in
		--date=*)
			_sports_base_date="${_arg#--date=}"
			;;
		*)
			echo "Invalid argument: $_arg" >&2
			show_help
			exit 1
			;;
		esac
	done

	hc_component_sports
fi
