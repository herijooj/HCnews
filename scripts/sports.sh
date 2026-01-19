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
# Parse Arguments / Cache Flags
# -----------------------------------------------------------------------------
hcnews_parse_args "$@"
_sports_USE_CACHE=${_HCNEWS_USE_CACHE:-true}
_sports_FORCE_REFRESH=${_HCNEWS_FORCE_REFRESH:-false}
_sports_base_date=""

for _arg in "${_HCNEWS_REMAINING_ARGS[@]}"; do
    case "$_arg" in
        --date=*)
            _sports_base_date="${_arg#--date=}"
            ;;
    esac
done

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
CACHE_TTL_SECONDS="${HCNEWS_CACHE_TTL["sports"]:-1800}"
SOFASCORE_BASE_URL="https://api.sofascore.com/api/v1"
DISPLAY_TZ="${HCNEWS_TZ:-America/Sao_Paulo}"

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
        IFS=',' read -ra requested <<< "$filter"
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
        finished|afterextratime|penalties)
            return 0 ;;
    esac
    return 1
}

_sports_is_today_keep() {
    local status="$1"
    case "$status" in
        notstarted|inprogress|halftime|paused|delayed)
            return 0 ;; # keep
        *)
            return 1 ;; # exclude (finished, penalties, canceled, postponed, suspended, etc.)
    esac
}

_sports_collect_events() {
    local json="$1"
    jq -r '
        (.events // [])[]? | . as $e |
        [
            ($e.startTimestamp // ""),
            ($e.homeTeam.name // "Time A"),
            ($e.awayTeam.name // "Time B"),
            ($e.homeScore.display // $e.homeScore.current // ""),
            ($e.awayScore.display // $e.awayScore.current // ""),
            ($e.status.type // ""),
            ($e.status.description // "")
        ] | @tsv
    ' <<< "$json"
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
        finished|afterextratime|penalties)
            line="${home} \`${hscore:-0}\`x\`${ascore:-0}\` ${away}"
            ;;
        notstarted)
            time_str=$(_sports_format_time "$ts")
            line="${home} x ${away} (${time_str})"
            ;;
        inprogress|halftime|paused)
            line="${home} \`${hscore:-0}\`x\`${ascore:-0}\` ${away} (${status_desc:-Ao vivo})"
            ;;
        postponed|canceled|delayed|suspended)
            time_str=$(_sports_format_time "$ts")
            line="${home} x ${away} (${status_desc:-Adi}) ${time_str}"
            ;;
        *)
            # For same-day finished games (today) still show the score
            if [[ "$day_type" == "today" && -n "$hscore" && -n "$ascore" ]]; then
                line="${home} \`${hscore}\`x\`${ascore}\` ${away}"
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
    local failures=0

    for comp in "${ACTIVE_TOURNAMENT_ORDER[@]}"; do
        local tournament_id="${SOFASCORE_TOURNAMENTS[$comp]}"
        local url="${SOFASCORE_BASE_URL}/unique-tournament/${tournament_id}/scheduled-events/${iso_date}"
        local json

        json=$(curl -s -4 --compressed --connect-timeout 5 --max-time 12 -H "User-Agent: HCnews/1.0" "$url")
        if [[ -z "$json" ]]; then
            ((failures++))
            continue
        fi

        local error_code
        error_code=$(echo "$json" | jq -r '.error.code // empty' 2>/dev/null)
        if [[ -n "$error_code" ]]; then
            if [[ "$error_code" == "404" ]]; then
                continue
            else
                ((failures++))
            fi
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
            output_lines+=("🏆 *${comp}*")
            local m
            for m in "${matches[@]}"; do
                output_lines+=("  - ${m}")
            done
            output_lines+=("") # blank line between tournaments
        fi
    done

    if [[ ${#output_lines[@]} -eq 0 ]]; then
        if (( failures > 0 )); then
            echo "- ⚠️ Futebol: falha ao buscar jogos"
        else
            echo "- Nenhum jogo encontrado"
        fi
    else
        printf '%s\n' "${output_lines[@]}"
    fi
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
get_sports_block() {
    _sports_merge_custom_tournaments
    _sports_apply_filter

    local base_date cache_key cache_variant
    base_date="${_sports_base_date:-$(TZ="$DISPLAY_TZ" date +%F)}"
    if ! TZ="$DISPLAY_TZ" date -d "$base_date" >/dev/null 2>&1; then
        base_date="$(TZ="$DISPLAY_TZ" date +%F)"
    fi
    cache_key="${base_date//-/}"

    cache_variant=$(echo "${HCNEWS_SPORTS_FILTER:-all}" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '_')
    [[ -z "$cache_variant" ]] && cache_variant="all"

    local cache_file
    hcnews_set_cache_path cache_file "sports" "$cache_key" "$cache_variant"

    if [[ "$_sports_USE_CACHE" == true ]] && hcnews_check_cache "$cache_file" "$CACHE_TTL_SECONDS" "$_sports_FORCE_REFRESH"; then
        hcnews_read_cache "$cache_file"
        return 0
    fi

    local yesterday_iso today_iso
    yesterday_iso=$(TZ="$DISPLAY_TZ" date -d "$base_date -1 day" +%F)
    today_iso="$base_date"

    local block
    block="⚽ *Futebol*"
    block+=$'\n\n'"📅 Ontem ($(_sports_human_date "$yesterday_iso"))"
    block+=$'\n\n'"$(_sports_fetch_day "$yesterday_iso" "yesterday")"
    block+=$'\n\n'"📅 Hoje ($(_sports_human_date "$today_iso"))"
    block+=$'\n\n'"$(_sports_fetch_day "$today_iso" "today")"

    [[ "$_sports_USE_CACHE" == true ]] && hcnews_write_cache "$cache_file" "$block"
    printf '%s' "$block"
}

write_sports() {
    local out
    out=$(get_sports_block "$@")
    [[ -n "$out" ]] && echo "$out"
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
    write_sports "$@"
fi
