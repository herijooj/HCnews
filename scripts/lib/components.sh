#!/usr/bin/env bash

# HCNews component registry (v1)
#
# Runtime metadata consumed by orchestration and tooling.

[[ -n "${_HCNEWS_COMPONENTS_LOADED:-}" ]] && return 0
_HCNEWS_COMPONENTS_LOADED=true

# Shell compatibility: bash 4+
declare -gA HCNEWS_COMPONENT_REGISTRY

# Record format:
# producer_fn|cache_key|ttl_key|profiles|enabled|required|parallel_group|timeout_sec|retries|render_order
#
# profiles: comma-separated values among: main,refresh,daily_build
# enabled/required: true|false
# parallel_group: local|network|serial

HCNEWS_COMPONENT_REGISTRY["header"]="hc_component_header|header|header|main,daily_build|true|true|local|5|0|10"
HCNEWS_COMPONENT_REGISTRY["moonphase"]="hc_component_moonphase|moonphase|moonphase|main,refresh,daily_build|true|false|network|15|1|20"
HCNEWS_COMPONENT_REGISTRY["holidays"]="hc_component_holidays|holidays|holidays|main,daily_build|true|false|local|5|0|30"
HCNEWS_COMPONENT_REGISTRY["states"]="hc_component_states|states|states|main,daily_build|true|false|local|5|0|40"
HCNEWS_COMPONENT_REGISTRY["weather"]="hc_component_weather|weather|weather|main,refresh,daily_build|true|false|network|20|1|50"
HCNEWS_COMPONENT_REGISTRY["rss"]="hc_component_rss|rss|rss|main,refresh,daily_build|true|false|network|30|1|60"
HCNEWS_COMPONENT_REGISTRY["exchange"]="hc_component_exchange|exchange|exchange|main,refresh,daily_build|true|false|network|20|1|70"
HCNEWS_COMPONENT_REGISTRY["sports"]="hc_component_sports|sports|sports|main,daily_build|true|false|network|20|1|80"
HCNEWS_COMPONENT_REGISTRY["onthisday"]="hc_component_onthisday|onthisday|onthisday|main,refresh,daily_build|true|false|network|20|1|90"
HCNEWS_COMPONENT_REGISTRY["didyouknow"]="hc_component_didyouknow|didyouknow|didyouknow|main,refresh,daily_build|true|false|network|20|1|100"
HCNEWS_COMPONENT_REGISTRY["bicho"]="hc_component_bicho|bicho|bicho|main,refresh,daily_build|true|false|network|20|1|110"
HCNEWS_COMPONENT_REGISTRY["saints"]="hc_component_saints|saints|saints|main,refresh,daily_build|true|false|network|20|1|120"
HCNEWS_COMPONENT_REGISTRY["ru"]="hc_component_ru|ru|ru|main,refresh,daily_build|true|false|network|20|1|125"
HCNEWS_COMPONENT_REGISTRY["emoji"]="hc_component_emoji|emoji|emoji|main,daily_build|true|false|local|5|0|130"

# Currently disabled/optional components
HCNEWS_COMPONENT_REGISTRY["musicchart"]="hc_component_musicchart|musicchart|musicchart|refresh,daily_build|false|false|network|25|1|200"
HCNEWS_COMPONENT_REGISTRY["earthquake"]="hc_component_earthquake|earthquake|earthquake|refresh,daily_build|false|false|network|25|1|210"
HCNEWS_COMPONENT_REGISTRY["quote"]="hc_component_quote|quote|quote|refresh,daily_build|false|false|network|20|1|220"
HCNEWS_COMPONENT_REGISTRY["futuro"]="hc_component_futuro|futuro|futuro|refresh,daily_build|false|false|network|40|0|230"

hc_components_list() {
	local name
	for name in "${!HCNEWS_COMPONENT_REGISTRY[@]}"; do
		echo "$name"
	done | sort
}

hc_component_raw() {
	local name="$1"
	[[ -n "${HCNEWS_COMPONENT_REGISTRY[$name]:-}" ]] || return 1
	echo "${HCNEWS_COMPONENT_REGISTRY[$name]}"
}

hc_component_get_field() {
	local name="$1"
	local field="$2"
	local raw
	raw=$(hc_component_raw "$name") || return 1

	local producer_fn cache_key ttl_key profiles enabled required parallel_group timeout_sec retries render_order
	IFS='|' read -r producer_fn cache_key ttl_key profiles enabled required parallel_group timeout_sec retries render_order <<<"$raw"

	case "$field" in
	producer_fn) echo "$producer_fn" ;;
	cache_key) echo "$cache_key" ;;
	ttl_key) echo "$ttl_key" ;;
	profiles) echo "$profiles" ;;
	enabled) echo "$enabled" ;;
	required) echo "$required" ;;
	parallel_group) echo "$parallel_group" ;;
	timeout_sec) echo "$timeout_sec" ;;
	retries) echo "$retries" ;;
	render_order) echo "$render_order" ;;
	*) return 1 ;;
	esac
}

hc_component_in_profile() {
	local name="$1"
	local profile="$2"
	local profiles
	profiles=$(hc_component_get_field "$name" profiles) || return 1

	local entry
	IFS=',' read -ra entries <<<"$profiles"
	for entry in "${entries[@]}"; do
		[[ "$entry" == "$profile" ]] && return 0
	done
	return 1
}
