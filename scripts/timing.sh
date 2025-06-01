#!/usr/bin/env bash
# This script provides timing utilities for the HCnews project

# Global array to store timing data
declare -A TIMING_DATA

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
    local end_time=$(date +%s%N)
    local start_time=${TIMING_DATA["${func_name}_start"]}
    
    if [[ -z "$start_time" ]]; then
        echo "Error: No start time found for $func_name"
        return 1
    fi
    
    local elapsed_ms=$(( (end_time - start_time) / 1000000 ))
    TIMING_DATA["${func_name}_elapsed"]=$elapsed_ms
    
    # Store the function name in the list of timed functions
    TIMING_DATA["timed_functions"]="${TIMING_DATA["timed_functions"]} $func_name"
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
    
    # Create an array of functions and their times for sorting
    declare -a sorted_functions
    for func in ${TIMING_DATA["timed_functions"]}; do
        elapsed=${TIMING_DATA["${func}_elapsed"]}
        sorted_functions+=("$elapsed:$func")
    done
    
    # Sort the functions by time (descending)
    IFS=$'\n' sorted_functions=($(sort -rn -t: -k1 <<< "${sorted_functions[*]}"))
    unset IFS
    
    # Print the sorted list
    for entry in "${sorted_functions[@]}"; do
        IFS=':' read -r time func <<< "$entry"
        printf "⏱️ %-30s %8d ms\n" "$func" "$time"
    done
    
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
    local elapsed=$(end_timing "$func_name")
    
    return $result
}

# Reset all timing data
# Usage: reset_timing_data
reset_timing_data() {
    unset TIMING_DATA
    declare -gA TIMING_DATA
}