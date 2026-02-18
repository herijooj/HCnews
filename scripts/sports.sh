#!/usr/bin/env bash
# =============================================================================
# Sports - Football fixtures/results focused on Brazil
# =============================================================================
# Source: SofaScore public API (no token required)
# Competitions: Brasileirão Série A, Copa do Brasil, CONMEBOL Libertadores
# Output: Yesterday's results + today's games (including live)
# =============================================================================

# -----------------------------------------------------------------------------
# Source Common Library
# -----------------------------------------------------------------------------
[[ -n "${_HCNEWS_COMMON_LOADED:-}" ]] || source "${HCNEWS_COMMON_PATH}common.sh" 2>/dev/null || source "${BASH_SOURCE%/*}/lib/common.sh"

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
CACHE_TTL_SECONDS="${HCNEWS_CACHE_TTL["sports"]:-1800}"
SOFASCORE_BASE_URL="https://api.sofascore.com/api/v1"
DISPLAY_TZ="${HCNEWS_TZ:-America/Sao_Paulo}"
SPORTS_USER_AGENT="${HCNEWS_SPORTS_UA:-Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36}"
CURL_CONNECT_TIMEOUT="${HCNEWS_SPORTS_CONNECT_TIMEOUT:-6}"
CURL_MAX_TIME="${HCNEWS_SPORTS_MAX_TIME:-12}"
TSDB_API_KEY="${HCNEWS_TSDB_KEY:-3}" # default public key

# Competitions to display (name -> unique tournament id)
declare -A SOFASCORE_TOURNAMENTS=(
	["Brasileirão Série A"]="325"
	["Brasileirão Série B"]="390"
	["Brasileirão Série C"]="1281"
	["Brasileirão Série D"]="10326"
	["Copa do Brasil"]="373"
	["Copa do Nordeste"]="1596"
	["Copa Verde"]="10158"
	["Libertadores"]="384"
	["Paulista"]="372"
	["Carioca"]="92"
	["Mineiro"]="379"
	["Gaúcho"]="377"
	["Paranaense"]="382"
	["Catarinense"]="376"
	["Goiano"]="381"
	["Pernambucano"]="380"
)
SOFASCORE_TOURNAMENT_ORDER=(
	"Brasileirão Série A"
	"Brasileirão Série B"
	"Brasileirão Série C"
	"Brasileirão Série D"
	"Libertadores"
	"Copa do Brasil"
	"Copa do Nordeste"
	"Copa Verde"
	"Paulista"
	"Carioca"
	"Mineiro"
	"Gaúcho"
	"Paranaense"
	"Catarinense"
	"Goiano"
	"Pernambucano"
)

SLIM_TOURNAMENTS=(
	"Brasileirão Série A"
	"Brasileirão Série B"
	"Libertadores"
	"Copa do Brasil"
	"Copa do Nordeste"
	"Copa Verde"
)

# Active order (filtered per run)
ACTIVE_TOURNAMENT_ORDER=("${SOFASCORE_TOURNAMENT_ORDER[@]}")

# Allow user-defined tournaments via env var HCNEWS_SPORTS_EXTRA="Name:ID,Name2:ID"
_sports_merge_custom_tournaments() {
	local extra="${HCNEWS_SPORTS_EXTRA:-}"
	[[ -z "$extra" ]] && return
	local IFS=',' part name id
	for part in $extra; do
		name="${part%%:*}"
		id="${part#*:}"
		if [[ -n "$name" && -n "$id" && "$id" =~ ^[0-9]+$ ]]; then
			SOFASCORE_TOURNAMENTS["$name"]="$id"
			SOFASCORE_TOURNAMENT_ORDER+=("$name")
		fi
	done
}

_sports_apply_filter() {
	local filter="${HCNEWS_SPORTS_FILTER:-}"

	if [[ -z "$filter" || "${filter^^}" == "ALL" ]]; then
		ACTIVE_TOURNAMENT_ORDER=("${SOFASCORE_TOURNAMENT_ORDER[@]}")
		return
	fi

	local -a requested=()
	if [[ "${filter^^}" == "SLIM" ]]; then
		requested=("${SLIM_TOURNAMENTS[@]}")
	else
		IFS=',' read -ra requested <<<"$filter"
	fi

	local -a filtered=()
	local name trimmed
	for name in "${requested[@]}"; do
		trimmed="${name#"${name%%[![:space:]]*}"}"
		trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
		[[ -z "$trimmed" ]] && continue
		if [[ -n "${SOFASCORE_TOURNAMENTS[$trimmed]:-}" ]]; then
			filtered+=("$trimmed")
		fi
	done

	if [[ ${#filtered[@]} -gt 0 ]]; then
		ACTIVE_TOURNAMENT_ORDER=("${filtered[@]}")
	else
		ACTIVE_TOURNAMENT_ORDER=("${SOFASCORE_TOURNAMENT_ORDER[@]}")
	fi
}

_sports_cache_variant() {
	local filter="${HCNEWS_SPORTS_FILTER:-all}"
	local variant="${filter,,}"
	variant="${variant//[^a-z0-9]/_}"
	while [[ "$variant" == *"__"* ]]; do
		variant="${variant//__/_}"
	done
	variant="${variant#_}"
	variant="${variant%_}"
	[[ -z "$variant" ]] && variant="all"
	echo "$variant"
}

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
_sports_format_time() {
	local ts="$1"
	if [[ -z "$ts" || "$ts" == "null" ]]; then
		echo "--:--"
		return
	fi
	TZ="$DISPLAY_TZ" date -d "@$ts" +"%H:%M"
}

_sports_human_date() {
	local iso="$1"
	TZ="$DISPLAY_TZ" date -d "$iso" +"%d/%m"
}

_sports_is_result_status() {
	local status="$1"
	case "$status" in
	finished | afterextratime | penalties)
		return 0
		;;
	esac
	return 1
}

_sports_is_today_keep() {
	local status="$1"
	case "$status" in
	notstarted | inprogress | halftime | paused | delayed)
		return 0
		;; # keep
	*)
		return 1
		;; # exclude (finished, penalties, canceled, postponed, suspended, etc.)
	esac
}

_sports_collect_events() {
	local json="$1"
	local tournament_id="${2:-}"
	jq -r '
        (.events // [])[]? | . as $e |
        select(
            ($tid == "") or
            ((($e.uniqueTournament.id // $e.tournament.uniqueTournament.id // $e.tournament.id // 0) | tostring) == $tid)
        ) |
        [
            ($e.startTimestamp // ""),
            ($e.homeTeam.name // "Time A"),
            ($e.awayTeam.name // "Time B"),
            ($e.homeScore.display // $e.homeScore.current // ""),
            ($e.awayScore.display // $e.awayScore.current // ""),
            ($e.status.type // ""),
            ($e.status.description // "")
        ] | @tsv
    ' --arg tid "$tournament_id" <<<"$json"
}

_sports_format_line() {
	local day_type="$1"
	local ts="$2"
	local home="$3"
	local away="$4"
	local hscore="$5"
	local ascore="$6"
	local status="$7"
	local status_desc="$8"

	local line time_str
	case "$status" in
	finished | afterextratime | penalties)
		line="${home} \`${hscore:-0}x${ascore:-0}\` ${away}"
		;;
	notstarted)
		time_str=$(_sports_format_time "$ts")
		line="${home} x ${away} (${time_str})"
		;;
	inprogress | halftime | paused)
		line="${home} \`${hscore:-0}x${ascore:-0}\` ${away} (${status_desc:-Ao vivo})"
		;;
	postponed | canceled | delayed | suspended)
		time_str=$(_sports_format_time "$ts")
		line="${home} x ${away} (${status_desc:-Adi}) ${time_str}"
		;;
	*)
		# For same-day finished games (today) still show the score
		if [[ "$day_type" == "today" && -n "$hscore" && -n "$ascore" ]]; then
			line="${home} \`${hscore}x${ascore}\` ${away}"
		else
			time_str=$(_sports_format_time "$ts")
			line="${home} x ${away} (${time_str})"
		fi
		;;
	esac
	echo "$line"
}

_sports_fetch_day() {
	local iso_date="$1"
	local day_type="$2" # yesterday|today
	local output_lines=()
	local -a curl_opts=(-s -L -4 --compressed --connect-timeout "$CURL_CONNECT_TIMEOUT" --max-time "$CURL_MAX_TIME" -A "$SPORTS_USER_AGENT")
	local tmp_dir
	tmp_dir=$(mktemp -d "/tmp/hcnews_sports_${iso_date//-/}_XXXXXX") || {
		echo "- Nenhum jogo encontrado"
		return 0
	}

	local -a fetch_jobs=()
	local i=0
	local comp tournament_id url out_file
	for comp in "${ACTIVE_TOURNAMENT_ORDER[@]}"; do
		tournament_id="${SOFASCORE_TOURNAMENTS[$comp]}"
		url="${SOFASCORE_BASE_URL}/unique-tournament/${tournament_id}/scheduled-events/${iso_date}"
		out_file="${tmp_dir}/${i}.json"
		((i++))

		curl "${curl_opts[@]}" "$url" >"$out_file" &
		fetch_jobs+=("$!|$comp|$out_file")
	done

	local job_info pid json error_code
	for job_info in "${fetch_jobs[@]}"; do
		IFS='|' read -r pid comp out_file <<<"$job_info"

		if ! wait "$pid" 2>/dev/null || [[ ! -s "$out_file" ]]; then
			continue
		fi

		json=$(<"$out_file")
		error_code=$(jq -r '.error.code // empty' <<<"$json" 2>/dev/null)
		if [[ -n "$error_code" ]]; then
			continue
		fi

		local has_event=false
		local -a matches=()
		while IFS=$'\t' read -r ts home away hscore ascore status status_desc; do
			# Filter by day type
			if [[ "$day_type" == "yesterday" ]]; then
				_sports_is_result_status "$status" || continue
			elif [[ "$day_type" == "today" ]]; then
				_sports_is_today_keep "$status" || continue
			fi

			has_event=true
			matches+=("$(_sports_format_line "$day_type" "$ts" "$home" "$away" "$hscore" "$ascore" "$status" "$status_desc")")
		done < <(_sports_collect_events "$json")

		if [[ "$has_event" == true ]]; then
			output_lines+=("*${comp}*")
			local m
			for m in "${matches[@]}"; do
				output_lines+=("- ${m}")
			done
		fi
	done

	rm -rf "$tmp_dir"

	if [[ ${#output_lines[@]} -eq 0 ]]; then
		# Fallback to TheSportsDB (public key) if SofaScore blocked
		local tsdb
		tsdb=$(_sports_fetch_day_tsdb "$iso_date" "$day_type")
		if [[ -n "$tsdb" ]]; then
			printf '%s\n' "$tsdb"
		else
			echo "- Nenhum jogo encontrado"
		fi
	else
		printf '%s\n' "${output_lines[@]}"
	fi
}

# Fallback using TheSportsDB daily endpoint (public demo key by default)
_sports_fetch_day_tsdb() {
	local iso_date="$1"
	local day_type="$2"
	local url="https://www.thesportsdb.com/api/v1/json/${TSDB_API_KEY}/eventsday.php?d=${iso_date}&s=Soccer&c=Brazil"
	local json
	json=$(curl -s -L -4 --connect-timeout "$CURL_CONNECT_TIMEOUT" --max-time "$CURL_MAX_TIME" -A "$SPORTS_USER_AGENT" "$url")
	[[ -z "$json" ]] && return 0

	local grouped
	grouped=$(echo "$json" | jq -r '
      (.events // [])
      | map(select((.strCountry // "") == "Brazil"))
      | group_by(.strLeague)[] |
      {
        league: (.[0].strLeague // "Futebol"),
        games: [
          .[] |
          {
            home: (.strHomeTeam // "Time A"),
            away: (.strAwayTeam // "Time B"),
            h: (.intHomeScore // ""),
            a: (.intAwayScore // ""),
            time: (.strTime // ""),
            ts: (.intTimestamp // null)
          }
        ]
      } |
      "*\(.league)*\n" +
      ( .games | map(
          if (.h|tostring) != "" and (.a|tostring) != "" then
            "- \(.home) `\(.h)x\(.a)` \(.away)"
          else
            "- \(.home) x \(.away) (\(.time // "--:--"))"
          end
      ) | join("\n") )
    ')
	printf '%s' "$grouped"
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
get_sports_block() {
	local use_cache="${_sports_USE_CACHE:-${_HCNEWS_USE_CACHE:-true}}"
	local force_refresh="${_sports_FORCE_REFRESH:-${_HCNEWS_FORCE_REFRESH:-false}}"

	local base_date cache_key cache_variant today_iso
	if [[ -n "${_sports_base_date:-}" ]]; then
		base_date="$_sports_base_date"
		if ! TZ="$DISPLAY_TZ" date -d "$base_date" >/dev/null 2>&1; then
			base_date="$(TZ="$DISPLAY_TZ" date +%F)"
		fi
		cache_key="${base_date//-/}"
		today_iso="$base_date"
	else
		cache_key="$(hcnews_get_date_format)"
		today_iso="${cache_key:0:4}-${cache_key:4:2}-${cache_key:6:2}"
	fi

	cache_variant=$(_sports_cache_variant)

	local cache_file
	hcnews_set_cache_path cache_file "sports" "$cache_key" "$cache_variant"

	if [[ "$use_cache" == true ]] && hcnews_check_cache "$cache_file" "$CACHE_TTL_SECONDS" "$force_refresh"; then
		hcnews_read_cache "$cache_file"
		return 0
	fi

	_sports_merge_custom_tournaments
	_sports_apply_filter

	local yesterday_iso
	yesterday_iso=$(TZ="$DISPLAY_TZ" date -d "$today_iso -1 day" +%F)

	local base_tmp_dir="${_HCNEWS_TEMP_DIR:-/tmp}"
	[[ -d "$base_tmp_dir" ]] || base_tmp_dir="/tmp"
	local today_tmp_file="${base_tmp_dir}/sports_today_$$.txt"
	local yesterday_tmp_file="${base_tmp_dir}/sports_yesterday_$$.txt"

	(_sports_fetch_day "$today_iso" "today") >"$today_tmp_file" &
	local today_pid=$!
	(_sports_fetch_day "$yesterday_iso" "yesterday") >"$yesterday_tmp_file" &
	local yesterday_pid=$!

	wait "$today_pid" 2>/dev/null || true
	wait "$yesterday_pid" 2>/dev/null || true

	local today_games=""
	local yesterday_games=""
	[[ -f "$today_tmp_file" ]] && today_games=$(<"$today_tmp_file")
	[[ -f "$yesterday_tmp_file" ]] && yesterday_games=$(<"$yesterday_tmp_file")
	rm -f "$today_tmp_file" "$yesterday_tmp_file"

	local block
	if [[ "$today_games" == *"- Nenhum jogo encontrado"* ]]; then
		block="⚽ *Futebol*"
		block+=$'\n'"🥅 *Ontem*"
		block+=$'\n'"$yesterday_games"
	else
		block="⚽ *Futebol - Hoje*"
		block+=$'\n'"$today_games"
		block+=$'\n'"🥅 *Ontem*"
		block+=$'\n'"$yesterday_games"
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
Fetches Brazilian football scores (yesterday) and today's fixtures from SofaScore.
--date=YYYY-MM-DD  Override base date (mainly for debugging)
Env:
  HCNEWS_SPORTS_FILTER=SLIM|ALL|Name1,Name2   # Limit tournaments (default: ALL)
  HCNEWS_SPORTS_EXTRA='Name:ID,Name2:ID'      # Append more tournaments
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
