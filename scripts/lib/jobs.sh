#!/usr/bin/env bash

# Background job management for parallel network operations
declare -A background_jobs

# Initialize jobs system (temp dir)
init_jobs() {
    # Temp directory for background job files (created once, cleaned up at exit)
    # Use /dev/shm (RAM) if available for performance
    if [[ -d "/dev/shm" && -w "/dev/shm" ]]; then
        _HCNEWS_TEMP_DIR="/dev/shm/hcnews_$$"
    else
        _HCNEWS_TEMP_DIR="/tmp/hcnews_$$"
    fi
    mkdir -p "$_HCNEWS_TEMP_DIR"
    
    # Export it so subshells can see it (though they get their own via copy, the path string is what matters)
    export _HCNEWS_TEMP_DIR
    
    # Register trap to clean up on exit
    # Note: caller script must not override this trap without chaining
    trap 'rm -rf "$_HCNEWS_TEMP_DIR"' EXIT
}

# Start a network operation in background with timing
start_background_job() {
    local job_name="$1"
    local command="$2"
    # Use predictable temp file names instead of spawning mktemp
    local temp_file="${_HCNEWS_TEMP_DIR}/${job_name}.out"
    local timing_file="${_HCNEWS_TEMP_DIR}/${job_name}.time"
    
    # Run command in background - use subshell (inherit env) instead of new process
    (
        if [[ "$timing" == true ]]; then
            _job_start=$(date +%s%N)
            eval "$command"
            _job_end=$(date +%s%N)
            echo $(((_job_end - _job_start) / 1000000)) > "$timing_file"
        else
            eval "$command"
        fi
    ) > "$temp_file" 2>&1 &

    local pid=$!
    
    background_jobs["$job_name"]="$pid:$temp_file:$timing_file"
}

# Wait for a background job and gets its output
wait_for_job() {
    local job_name="$1"
    local job_info="${background_jobs[$job_name]}"
    
    if [[ -n "$job_info" ]]; then
        local pid="${job_info%%:*}"
        local temp_file="${job_info#*:}"
        temp_file="${temp_file%%:*}"
        local timing_file="${job_info##*:}"
        
        # Use bash's wait with timeout instead of polling loop
        wait "$pid" 2>/dev/null
        local wait_status=$?
        
        # If wait failed (e.g. interrupted) but process is still running, retry waiting
        while [[ $wait_status -ne 0 ]] && kill -0 "$pid" 2>/dev/null; do
             wait "$pid" 2>/dev/null
             wait_status=$?
        done
        
        # Fallback polling
        if kill -0 "$pid" 2>/dev/null; then
             local elapsed=0
             while kill -0 "$pid" 2>/dev/null; do
                 sleep 0.1
                 elapsed=$((elapsed + 1))
                 if [[ $elapsed -gt 50 ]]; then # 5 second timeout safety
                     kill "$pid" 2>/dev/null
                     rm -f "$temp_file" "$timing_file"
                     return 1
                 fi
             done
        fi
        
        # Store timing data if available
        if [[ "$timing" == true && -f "$timing_file" ]]; then
            local job_time
            # Use built-in read to avoid fork
            job_time=$(<"$timing_file")
            if [[ -n "$job_time" && "$job_time" =~ ^[0-9]+$ ]]; then
                # Assume TIMING_DATA is available (caller sources timing.sh)
                TIMING_DATA["${job_name}_elapsed"]=$job_time
                TIMING_DATA["timed_functions"]="${TIMING_DATA["timed_functions"]} $job_name"
                # Save to shared file for cross-subshell persistence
                if type -t save_timing_entry >/dev/null; then
                    save_timing_entry "$job_name" "$job_time"
                fi
            fi
        fi
        
        # Get the output and clean up
        if [[ -f "$temp_file" ]]; then
            cat "$temp_file"
        fi
        
        unset background_jobs["$job_name"]
        return 0
    fi
    return 1
}

format_f1_time() {
    local start_time_ns=$1
    local end_time_ns=$2
    local elapsed_ns=$((10#$end_time_ns - 10#$start_time_ns))
    local total_ms=$((elapsed_ns / 1000000))
    local minutes=$((total_ms / 60000))
    local remaining_ms=$((total_ms % 60000))
    local seconds=$((remaining_ms / 1000))
    local milliseconds=$((remaining_ms % 1000))
    
    if [[ $minutes -gt 0 ]]; then
        printf "%d:%02d.%03ds" $minutes $seconds $milliseconds
    else
        printf "%d.%03ds" $seconds $milliseconds
    fi
}
