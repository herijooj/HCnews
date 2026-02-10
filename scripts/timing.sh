#!/usr/bin/env bash
# This script provides timing utilities for the HCnews project

# Global array to store timing data
declare -A TIMING_DATA

# File to persist timing data across subshells
_TIMING_DATA_FILE=""

# Initialize timing data file for cross-subshell persistence
init_timing_file() {
	# shellcheck disable=SC2154
	if [[ "$timing" == true && -n "$_HCNEWS_TEMP_DIR" ]]; then
		_TIMING_DATA_FILE="${_HCNEWS_TEMP_DIR}/timing_data.txt"
		: >"$_TIMING_DATA_FILE" # Create/truncate file
	fi
}

# Save a timing entry to the shared file (for subshell persistence)
save_timing_entry() {
	local name="$1"
	local elapsed="$2"
	if [[ -n "$_TIMING_DATA_FILE" && -w "$_TIMING_DATA_FILE" ]]; then
		echo "${name}:${elapsed}" >>"$_TIMING_DATA_FILE"
	fi
}

# Load timing entries from shared file into TIMING_DATA (avoids duplicates)
load_timing_entries() {
	if [[ -f "$_TIMING_DATA_FILE" ]]; then
		while IFS=: read -r name elapsed; do
			if [[ -n "$name" && -n "$elapsed" ]]; then
				# Only add if not already present (avoid duplicates)
				if [[ -z "${TIMING_DATA["${name}_elapsed"]}" ]]; then
					TIMING_DATA["${name}_elapsed"]=$elapsed
					TIMING_DATA["timed_functions"]="${TIMING_DATA["timed_functions"]} $name"
				fi
			fi
		done <"$_TIMING_DATA_FILE"
	fi
}

# Start timing a function
# Usage: start_timing "function_name"
start_timing() {
	# Only do timing work if timing is enabled
	if [[ "$timing" != true ]]; then
		return 0
	fi

	local func_name=$1
	TIMING_DATA["${func_name}_start"]=$(date +%s%N)
}

# End timing a function and print the result
# Usage: end_timing "function_name"
end_timing() {
	# Only do timing work if timing is enabled
	if [[ "$timing" != true ]]; then
		return 0
	fi

	local func_name=$1
	local end_time
	end_time=$(date +%s%N)
	local start_time=${TIMING_DATA["${func_name}_start"]}

	if [[ -z "$start_time" ]]; then
		echo "Error: No start time found for $func_name"
		return 1
	fi

	local elapsed_ms
	elapsed_ms=$(((end_time - start_time) / 1000000))
	TIMING_DATA["${func_name}_elapsed"]=$elapsed_ms

	# Store the function name in the list of timed functions
	TIMING_DATA["timed_functions"]="${TIMING_DATA["timed_functions"]} $func_name"

	# Also save to file for cross-subshell persistence
	save_timing_entry "$func_name" "$elapsed_ms"
}

# Print timing for a specific function
# Usage: print_timing "function_name"
print_timing() {
	local func_name=$1
	local elapsed=${TIMING_DATA["${func_name}_elapsed"]}

	if [[ -z "$elapsed" ]]; then
		echo "No timing data found for $func_name"
		return 1
	fi

	echo "⏱️ $func_name: $elapsed ms"
}

# Print timing summary for all timed functions
# Usage: print_timing_summary
print_timing_summary() {
	echo "📊 Function Timing Summary 📊"
	echo "============================="

	# If no functions have been timed, exit
	if [[ -z "${TIMING_DATA["timed_functions"]}" ]]; then
		echo "No functions have been timed."
		return 0
	fi

	# Separate async (background) jobs from sync operations
	declare -a async_jobs
	declare -a sync_ops

	for func in ${TIMING_DATA["timed_functions"]}; do
		elapsed=${TIMING_DATA["${func}_elapsed"]}
		# Background jobs have specific names (no write_ prefix typically)
		case "$func" in
		menu | music_chart | ai_fortune | weather | all_news | saints | exchange | sanepar | did_you_know | desculpa | bicho | header_moon | header_quote)
			async_jobs+=("$elapsed:$func")
			;;
		*)
			sync_ops+=("$elapsed:$func")
			;;
		esac
	done

	# Print async jobs first (these run in parallel)
	if [[ ${#async_jobs[@]} -gt 0 ]]; then
		echo "🔀 Background Jobs (parallel):"
		mapfile -t sorted < <(sort -rn -t: -k1 <<<"${async_jobs[*]}")
		for entry in "${sorted[@]}"; do
			IFS=':' read -r time func <<<"$entry"
			printf "   ⏱️ %-26s %8d ms\n" "$func" "$time"
		done
		echo ""
	fi

	# Print sync operations
	if [[ ${#sync_ops[@]} -gt 0 ]]; then
		echo "🔁 Synchronous Operations:"
		mapfile -t sorted < <(sort -rn -t: -k1 <<<"${sync_ops[*]}")
		for entry in "${sorted[@]}"; do
			IFS=':' read -r time func <<<"$entry"
			printf "   ⏱️ %-26s %8d ms\n" "$func" "$time"
		done
	fi

	echo "============================="
}

# Wrapper function to time the execution of another function
# Usage: time_function function_name [arg1 arg2 ...]
time_function() {
	local func_name=$1
	shift

	start_timing "$func_name"
	"$func_name" "$@"
	local result=$?
	local elapsed
	elapsed=$(end_timing "$func_name")

	return $result
}

# Reset all timing data
# Usage: reset_timing_data
reset_timing_data() {
	unset TIMING_DATA
	declare -gA TIMING_DATA
}
