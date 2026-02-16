#!/usr/bin/env bash

[[ -n "${_HCNEWS_ORCH_LOADED:-}" ]] && return 0
_HCNEWS_ORCH_LOADED=true

hc_orch_start_network_jobs() {
	local city="$1"
	local saints_verbose="$2"
	local ru_location="$3"

	start_timing "network_parallel_start"

	local sports_filter_main="${HCNEWS_SPORTS_FILTER_MAIN:-Brasileirão Série A,Libertadores,Copa do Brasil,Paranaense}"

	start_background_job "weather" "(_weather_USE_CACHE=\$_HCNEWS_USE_CACHE; _weather_FORCE_REFRESH=\$_HCNEWS_FORCE_REFRESH; hc_component_weather '$city')"
	start_background_job "saints" "(_saints_USE_CACHE=\$_HCNEWS_USE_CACHE; _saints_FORCE_REFRESH=\$_HCNEWS_FORCE_REFRESH; hc_component_saints '$saints_verbose')"
	start_background_job "exchange" "(_exchange_USE_CACHE=\$_HCNEWS_USE_CACHE; _exchange_FORCE_REFRESH=\$_HCNEWS_FORCE_REFRESH; hc_component_exchange)"
	start_background_job "sports" "(HCNEWS_SPORTS_FILTER='${sports_filter_main}' _sports_USE_CACHE=\$_HCNEWS_USE_CACHE; _sports_FORCE_REFRESH=\$_HCNEWS_FORCE_REFRESH; hc_component_sports)"
	start_background_job "onthisday" "(_onthisday_USE_CACHE=\$_HCNEWS_USE_CACHE; _onthisday_FORCE_REFRESH=\$_HCNEWS_FORCE_REFRESH; hc_component_onthisday)"
	start_background_job "did_you_know" "(_didyouknow_USE_CACHE=\$_HCNEWS_USE_CACHE; _didyouknow_FORCE_REFRESH=\$_HCNEWS_FORCE_REFRESH; hc_component_didyouknow)"
	start_background_job "bicho" "(_bicho_USE_CACHE=\$_HCNEWS_USE_CACHE; _bicho_FORCE_REFRESH=\$_HCNEWS_FORCE_REFRESH; hc_component_bicho)"
	start_background_job "ru" "(SELECTED_LOCATION='${ru_location}' SHOW_ONLY_TODAY=true _ru_USE_CACHE=\$_HCNEWS_USE_CACHE; _ru_FORCE_REFRESH=\$_HCNEWS_FORCE_REFRESH; hc_component_ru)"
	start_background_job "header_moon" "(_moonphase_USE_CACHE=\$_HCNEWS_USE_CACHE; _moonphase_FORCE_REFRESH=\$_HCNEWS_FORCE_REFRESH; hc_component_moonphase)"

	end_timing "network_parallel_start"
}

hc_orch_collect_network_data() {
	[[ -z "$moon_phase_output" ]] && { moon_phase_output=$(wait_for_job "header_moon") || moon_phase_output=""; }
	[[ -z "$saints_output" ]] && { saints_output=$(wait_for_job "saints") || saints_output=""; }
	[[ -z "$exchange_output" ]] && { exchange_output=$(wait_for_job "exchange") || exchange_output=""; }
	[[ -z "$sports_output" ]] && { sports_output=$(wait_for_job "sports") || sports_output=""; }
	[[ -z "$weather_output" ]] && { weather_output=$(wait_for_job "weather") || weather_output=""; }
	[[ -z "$didyouknow_output" ]] && { didyouknow_output=$(wait_for_job "did_you_know") || didyouknow_output=""; }
	[[ -z "$bicho_output" ]] && { bicho_output=$(wait_for_job "bicho") || bicho_output=""; }
	[[ -z "$ru_output" ]] && { ru_output=$(wait_for_job "ru") || ru_output=""; }
	[[ -z "$onthisday_output" ]] && { onthisday_output=$(wait_for_job "onthisday") || onthisday_output=""; }
}

hc_orch_run_local_jobs() {
	local month="$1"
	local day="$2"

	start_timing "local_header"
	# shellcheck disable=SC2034
	header_core_output=$(hc_component_header)
	end_timing "local_header"

	start_timing "local_holidays"
	# shellcheck disable=SC2034
	holidays_output=$(hc_component_holidays "$month" "$day")
	end_timing "local_holidays"

	start_timing "local_states"
	# shellcheck disable=SC2034
	states_output=$(hc_component_states "$month" "$day")
	end_timing "local_states"

	start_timing "local_emoji"
	# shellcheck disable=SC2034
	emoji_output=$(hc_component_emoji)
	end_timing "local_emoji"
}

hc_orch_fetch_main_data() {
	local city="$1"
	local saints_verbose="$2"
	local ru_location="$3"
	local month="$4"
	local day="$5"

	hc_orch_start_network_jobs "$city" "$saints_verbose" "$ru_location"
	hc_orch_run_local_jobs "$month" "$day"
	hc_orch_collect_network_data
}
