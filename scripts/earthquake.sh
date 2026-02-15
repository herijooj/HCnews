#!/usr/bin/env bash

_local_dir="${BASH_SOURCE[0]%/*}"
[[ -n "${_HCNEWS_COMMON_LOADED:-}" ]] || source "${HCNEWS_COMMON_PATH:-${_local_dir}/lib/common.sh}" 2>/dev/null || source "${_local_dir}/scripts/lib/common.sh"

CACHE_TTL_SECONDS="${HCNEWS_CACHE_TTL["earthquake"]:-7200}"

build_block() {
	local use_cache="${_earthquake_USE_CACHE:-${_HCNEWS_USE_CACHE:-true}}"
	local force_refresh="${_earthquake_FORCE_REFRESH:-${_HCNEWS_FORCE_REFRESH:-false}}"
	local feed_url="https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/4.5_day.geojson"
	local date_str
	date_str=$(hcnews_get_date_format)
	local cache_file
	hcnews_set_cache_path cache_file "earthquake" "$date_str"

	if [[ "$use_cache" == true ]] &&
		hcnews_check_cache "$cache_file" "$CACHE_TTL_SECONDS" "$force_refresh"; then
		hcnews_read_cache "$cache_file"
		return
	fi

	local tmp_dir="/dev/shm"
	[[ -d "$tmp_dir" && -w "$tmp_dir" ]] || tmp_dir="/tmp"
	local tmp_file="$tmp_dir/.hc_quakes_${$}.json"

	if ! curl -s --compressed "$feed_url" -o "$tmp_file"; then
		rm -f "$tmp_file"
		printf '%s\n%s\n' "🌎 *Sismos 4.5+ (últimas 24h)*" "- Não foi possível obter os dados agora."
		return 1
	fi

	local lines
	lines=$(jq -r '
    .features
    | map({mag: (.properties.mag // 0), place: (.properties.place // "Local desconhecido"), ts: ((.properties.time // 0) / 1000 | floor)})
    | sort_by(-.mag)
    | .[:5]
    | map([(.mag|tostring), .place, (.ts|tostring)] | @tsv)
    | .[]
  ' "$tmp_file" 2>/dev/null)

	rm -f "$tmp_file"

	if [[ -z "$lines" ]]; then
		printf '%s\n%s\n' "🌎 *Sismos 4.5+ (últimas 24h)*" "- Nenhum evento encontrado."
		return 0
	fi

	local entries=()
	while IFS=$'\t' read -r mag place ts; do
		[[ -z "$mag" || -z "$ts" ]] && continue
		local tstr
		tstr=$(date -u -d "@$ts" +"%H:%M UTC")
		entries+=("M${mag} — ${place} (${tstr})")
	done <<<"$lines"

	if [[ ${#entries[@]} -eq 0 ]]; then
		printf '%s\n%s\n' "🌎 *Sismos 4.5+ (últimas 24h)*" "- Nenhum evento encontrado."
		return 0
	fi

	local now
	now=$(date +"%H:%M:%S")
	local output="🌎 *Sismos 4.5+ (últimas 24h)*"
	for item in "${entries[@]}"; do
		output+=$'\n- '
		output+="$item"
	done
	output+=$'\n'
	output+="_Fonte: USGS · Atualizado: ${now}_"

	[[ "$use_cache" == true ]] && hcnews_write_cache "$cache_file" "$output"
	echo "$output"
}

hc_component_earthquake() {
	if ! build_block; then
		return 1
	fi
	echo
}

show_help() {
	echo "Usage: ./earthquake.sh [--no-cache|--force]"
}

parse_args() {
	if [[ $# -eq 0 ]]; then
		return 0
	fi

	case "$1" in
	-h | --help)
		show_help
		exit 0
		;;
	*)
		echo "Invalid argument: $1" >&2
		show_help
		exit 1
		;;
	esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	hcnews_parse_args "$@"
	_earthquake_USE_CACHE=$_HCNEWS_USE_CACHE
	_earthquake_FORCE_REFRESH=$_HCNEWS_FORCE_REFRESH
	set -- "${_HCNEWS_REMAINING_ARGS[@]}"
	parse_args "$@"
	hc_component_earthquake
fi
