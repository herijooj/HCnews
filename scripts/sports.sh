#!/usr/bin/env bash
# =============================================================================
# Sports - FIFA World Cup 2026 fixtures/results
# =============================================================================
# Source: wheniskickoff.com (free public API, no auth required)
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
BASE_URL="https://wheniskickoff.com/data/v1"
DISPLAY_TZ="${HCNEWS_TZ:-America/Sao_Paulo}"
CURL_CONNECT_TIMEOUT="${HCNEWS_SPORTS_CONNECT_TIMEOUT:-6}"
CURL_MAX_TIME="${HCNEWS_SPORTS_MAX_TIME:-12}"
CURL_RETRY="${HCNEWS_SPORTS_RETRY:-5}"

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

_sports_is_result_status() {
	[[ "${1:-}" == "FINISHED" ]] && return 0
	return 1
}

_sports_is_today_keep() {
	local s="${1:-}"
	case "$s" in FINISHED|LIVE|IN_PROGRESS|HALFTIME|"") return 0 ;; esac
	return 1
}

_sports_format_line() {
	local day_type="$1" datetime="$2" home="$3" away="$4"
	local hscore="$5" ascore="$6" status="$7"
	if [[ "$status" == "FINISHED" ]]; then
		echo "${home} \`${hscore:-0}x${ascore:-0}\` ${away}"
	else
		echo "${home} x ${away} ($(_sports_format_time "$datetime"))"
	fi
}

declare -A _SPORTS_PT=(
	[ARG]=Argentina [AUS]=Austrália [AUT]=Áustria
	[BEL]=Bélgica [BIH]="Bósnia e Herzegovina" [BRA]=Brasil
	[CAN]=Canadá [CIV]="Costa do Marfim" [COD]="Congo (RD)"
	[COL]=Colômbia [CPV]="Cabo Verde" [CRO]=Croácia [CUW]=Curaçau
	[CZE]=Tchéquia [DZA]=Argélia [ECU]=Equador [EGY]=Egito
	[ENG]=Inglaterra [ESP]=Espanha [FRA]=França [GER]=Alemanha
	[GHA]=Gana [HAI]=Haiti [IRN]=Irã [IRQ]=Iraque [JOR]=Jordânia
	[JPN]=Japão [KOR]="Coreia do Sul" [KSA]="Arábia Saudita"
	[MAR]=Marrocos [MEX]=México [NED]="Países Baixos" [NOR]=Noruega
	[NZL]="Nova Zelândia" [PAN]=Panamá [PAR]=Paraguai [POR]=Portugal
	[QAT]=Catar [RSA]="África do Sul" [SCO]=Escócia [SEN]=Senegal
	[SUI]=Suíça [SWE]=Suécia [TUN]=Tunísia [TUR]=Turquia
	[URY]=Uruguai [URU]=Uruguai [USA]="Estados Unidos" [UZB]=Uzbequistão
)

_sports_ptname() {
	local code="$1" fallback="$2"
	echo "${_SPORTS_PT[$code]:-$fallback}"
}

_sports_fetch_day() {
	local iso_date="$1" day_type="$2"
	local curl_opts=(-s -L -4 --compressed --connect-timeout "$CURL_CONNECT_TIMEOUT" --max-time "$CURL_MAX_TIME" --retry "$CURL_RETRY" --retry-delay 5 --retry-all-errors)

	local matches_json teams_json
	matches_json=$(curl "${curl_opts[@]}" "${BASE_URL}/matches.json") || { echo "- Nenhum jogo encontrado"; return 0; }
	teams_json=$(curl "${curl_opts[@]}" "${BASE_URL}/teams.json")

	local matches
	matches=$(echo "$matches_json" | jq -r --arg date "$iso_date" '
		[.data[] | select(.date == $date)] |
		sort_by(.datetime_utc // "") |
		.[] |
		[.datetime_utc // "", .home // "", .away // "", .home_name // "", .away_name // "", (.score_home // ""), (.score_away // ""), (.status // "")] |
		@tsv
	')

	[[ -z "$matches" ]] && { echo "- Nenhum jogo encontrado"; return 0; }

	declare -A flags
	if [[ -n "$teams_json" ]]; then
		while IFS=$'\t' read -r code _ flag; do
			flags["$code"]="$flag"
		done < <(echo "$teams_json" | jq -r '.data[] | [.code, .name, .flag] | @tsv' 2>/dev/null)
	fi

	local output_lines=()
	output_lines+=("*FIFA World Cup*")

	local datetime home_code away_code home_name away_name hscore ascore status
	local flag_home flag_away home_display away_display line
	while IFS=$'\t' read -r datetime home_code away_code home_name away_name hscore ascore status; do
		if [[ "$day_type" == "yesterday" ]] && [[ "$status" != "FINISHED" ]]; then continue; fi

		flag_home="${flags[$home_code]:-}"
		flag_away="${flags[$away_code]:-}"

		home_display="${flag_home}$(_sports_ptname "$home_code" "$home_name")"
		away_display="${flag_away}$(_sports_ptname "$away_code" "$away_name")"

		line=$(_sports_format_line "$day_type" "$datetime" "$home_display" "$away_display" "$hscore" "$ascore" "$status")
		output_lines+=("- ${line}")
	done <<<"$matches"

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
		block="🏆 *Copa do Mundo 2026 - Hoje*"
		block+=$'\n'"- Nenhum jogo encontrado"
	else
		block="🏆 *Copa do Mundo 2026 - Hoje*"
		block+=$'\n'"$today_games"
	fi
	if [[ "$yesterday_games" != *"- Nenhum jogo encontrado"* && -n "$yesterday_games" ]]; then
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
Fetches FIFA World Cup 2026 scores (yesterday) and today's fixtures from wheniskickoff.com.
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
