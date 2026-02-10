#!/usr/bin/env bash

# HCnews Benchmark Script
# Runs each module with and without cache and logs the timings.

LOG_FILE="benchmark_results.log"
SCRIPT_DIR=$(dirname "$(realpath "$0")")
cd "$SCRIPT_DIR" || exit 1

# Ensure we are in nix-shell environment if possible/needed
if ! command -v jq &>/dev/null; then
	echo "Warning: jq not found. Some scripts may fail. Please run in nix-shell."
fi

# Clear log file
echo "HCnews Benchmark Run - $(date)" >"$LOG_FILE"
echo "==========================================" >>"$LOG_FILE"

# Function to run a benchmark
run_benchmark() {
	local name="$1"
	local command="$2"
	local iterations_cached=3

	echo "Benchmarking: $name"
	echo "------------------------------------------" >>"$LOG_FILE"
	echo "Module: $name" >>"$LOG_FILE"

	# --- Forced Run (No Cache) ---
	echo "  Running Forced (No Cache)..."
	local start_ts
	start_ts=$(date +%s%N)
	# We use --force to bypass cache
	# Suppress output, we only care about time and exit code
	if eval "$command --force" >/dev/null 2>&1; then
		local end_ts
		end_ts=$(date +%s%N)
		local duration
		duration=$(((end_ts - start_ts) / 1000000))
		echo "  Forced: ${duration} ms"
		echo "  Forced Run: ${duration} ms (Success)" >>"$LOG_FILE"
	else
		echo "  Forced: FAILED"
		echo "  Forced Run: FAILED" >>"$LOG_FILE"
	fi

	# --- Cached Runs ---
	echo "  Running Cached ($iterations_cached iterations)..."
	echo "  Cached Runs:" >>"$LOG_FILE"

	local total_cached=0
	for ((i = 1; i <= iterations_cached; i++)); do
		local start_ts
		start_ts=$(date +%s%N)
		# Standard run (uses cache if available)
		if eval "$command" >/dev/null 2>&1; then
			local end_ts
			end_ts=$(date +%s%N)
			local duration
			duration=$(((end_ts - start_ts) / 1000000))
			echo "    Run $i: ${duration} ms"
			echo "    Run $i: ${duration} ms" >>"$LOG_FILE"
			total_cached=$((total_cached + duration))
		else
			echo "    Run $i: FAILED"
			echo "    Run $i: FAILED" >>"$LOG_FILE"
		fi
	done

	local avg_cached
	avg_cached=$((total_cached / iterations_cached))
	echo "  Avg Cached: ${avg_cached} ms"
	echo "  Avg Cached: ${avg_cached} ms" >>"$LOG_FILE"
	echo "" >>"$LOG_FILE"
	echo ""
}

# Define modules to test
# format: "Name|Command"
MODULES=(
	"RSS (O Popular)|./scripts/rss.sh 'https://opopularpr.com.br/feed/'"
	"Saints|./scripts/saints.sh"
	"Weather|./scripts/weather.sh 'Curitiba'"
	"Exchange|./scripts/exchange.sh"
	"Moon Phase|./scripts/moonphase.sh"
	"Quotes|./scripts/quote.sh"
	"Bicho|./scripts/bicho.sh"
	"Did You Know|./scripts/didyouknow.sh"
	"Horoscope (Aries)|./scripts/horoscopo.sh 'aries'"
	"Sanepar|./scripts/sanepar.sh"
	"Music Chart|./scripts/musicchart.sh"
	"Futuro|./scripts/futuro.sh"
	"Holidays|./scripts/holidays.sh"
	"States|./scripts/states.sh"
)

# Run benchmarks
for module in "${MODULES[@]}"; do
	IFS='|' read -r name cmd <<<"$module"
	run_benchmark "$name" "$cmd"
done

echo "Benchmark complete. Results saved to $LOG_FILE"
