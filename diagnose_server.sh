#!/usr/bin/env bash
# HCNews Server Diagnostic Script

echo "🔍 HCNews Performance Diagnostic Report"
echo "========================================"
echo "Date: $(date)"
echo "Hostname: $(hostname)"
echo ""

echo "📊 SYSTEM RESOURCES"
echo "-------------------"
echo "CPU Cores: $(nproc 2>/dev/null || echo 'unknown')"
echo "RAM Total: $(free -h 2>/dev/null | grep Mem: | awk '{print $2}' || echo 'unknown')"
echo "RAM Available: $(free -h 2>/dev/null | grep Mem: | awk '{print $7}' || echo 'unknown')"
echo "Load Average: $(uptime | awk -F'load average:' '{print $2}' || echo 'unknown')"
echo "Disk Space: $(df -h . 2>/dev/null | tail -1 | awk '{print $4 " available"}' || echo 'unknown')"
echo ""

echo "🛠️  TOOL VERSIONS"
echo "----------------"
echo "Bash: $BASH_VERSION"
echo "Curl: $(curl --version 2>/dev/null | head -1 || echo 'NOT FOUND')"
echo "XMLStarlet: $(xmlstarlet --version 2>/dev/null | head -1 || echo 'NOT FOUND')"
echo "AWK: $(awk --version 2>/dev/null | head -1 || echo 'unknown')"
echo "JQ: $(jq --version 2>/dev/null || echo 'NOT FOUND')"
echo "BC: $(bc --version 2>/dev/null | head -1 || echo 'NOT FOUND')"
echo ""

echo "⏱️  PERFORMANCE TESTS"
echo "--------------------"

# Test 1: Basic computation
echo -n "Basic computation (1000 calculations): "
time_start=$(date +%s.%N)
for i in {1..1000}; do
    result=$((i * 2 + 1))
done
time_end=$(date +%s.%N)
computation_time=$(echo "scale=3; ($time_end - $time_start) * 1000" | bc 2>/dev/null || echo "error")
echo "${computation_time}ms"

# Test 2: File I/O
echo -n "File I/O (write/read 1000 lines): "
time_start=$(date +%s.%N)
test_file="/tmp/hcnews_io_test.txt"
for i in {1..1000}; do
    echo "test line $i" >> "$test_file"
done
cat "$test_file" > /dev/null
rm -f "$test_file"
time_end=$(date +%s.%N)
io_time=$(echo "scale=3; ($time_end - $time_start) * 1000" | bc 2>/dev/null || echo "error")
echo "${io_time}ms"

# Test 3: Subprocess creation
echo -n "Subprocess creation (100 echo commands): "
time_start=$(date +%s.%N)
for i in {1..100}; do
    echo "test" > /dev/null
done
time_end=$(date +%s.%N)
subprocess_time=$(echo "scale=3; ($time_end - $time_start) * 1000" | bc 2>/dev/null || echo "error")
echo "${subprocess_time}ms"

# Test 4: Network connectivity (if curl available)
if command -v curl >/dev/null 2>&1; then
    echo -n "Network test (curl google.com): "
    time_start=$(date +%s.%N)
    curl -s --max-time 5 --connect-timeout 2 "https://google.com" > /dev/null 2>&1
    curl_exit_code=$?
    time_end=$(date +%s.%N)
    network_time=$(echo "scale=3; ($time_end - $time_start) * 1000" | bc 2>/dev/null || echo "error")
    if [[ $curl_exit_code -eq 0 ]]; then
        echo "${network_time}ms (SUCCESS)"
    else
        echo "${network_time}ms (FAILED - exit code: $curl_exit_code)"
    fi
else
    echo "Network test: SKIPPED (curl not available)"
fi

# Test 5: Date command performance (fixed measurement)
echo -n "Date command (100 calls): "
# Use bash's built-in SECONDS for more accurate timing
SECONDS=0
for i in {1..100}; do
    current_date=$(date +%s)
done
date_time=$(echo "scale=3; $SECONDS * 1000" | bc 2>/dev/null || echo "error")
echo "${date_time}ms"

# Test 6: ARM-specific date analysis (fixed measurement)
echo -n "Single date call latency: "
SECONDS=0
single_date=$(date +%s)
single_date_time=$(echo "scale=3; $SECONDS * 1000" | bc 2>/dev/null || echo "error")
echo "${single_date_time}ms"

# Test 7: Different date format performance
echo -n "Date +%s (10 calls): "
SECONDS=0
for i in {1..10}; do date +%s >/dev/null; done
echo "$(echo "scale=3; $SECONDS * 1000" | bc)ms"

echo -n "Date +%s.%N (10 calls): "
SECONDS=0  
for i in {1..10}; do date +%s.%N >/dev/null; done
echo "$(echo "scale=3; $SECONDS * 1000" | bc)ms"

echo -n "Date +%Y%m%d (10 calls): "
SECONDS=0
for i in {1..10}; do date +%Y%m%d >/dev/null; done  
echo "$(echo "scale=3; $SECONDS * 1000" | bc)ms"

echo -n "CPU architecture: "
uname -m
echo -n "Date binary location: "
which date
echo -n "Date binary info: "
file $(which date) 2>/dev/null || echo "unknown"

echo ""
echo "🎯 PERFORMANCE ANALYSIS"
echo "----------------------"

# Analyze results
if command -v bc >/dev/null 2>&1; then
    if [[ "$computation_time" != "error" ]]; then
        if (( $(echo "$computation_time > 100" | bc -l) )); then
            echo "⚠️  CPU: SLOW (${computation_time}ms) - Expected <50ms"
        else
            echo "✅ CPU: Normal (${computation_time}ms)"
        fi
    fi
    
    if [[ "$io_time" != "error" ]]; then
        if (( $(echo "$io_time > 500" | bc -l) )); then
            echo "⚠️  Disk I/O: SLOW (${io_time}ms) - Expected <200ms"
        else
            echo "✅ Disk I/O: Normal (${io_time}ms)"
        fi
    fi
    
    if [[ "$subprocess_time" != "error" ]]; then
        if (( $(echo "$subprocess_time > 1000" | bc -l) )); then
            echo "⚠️  Subprocess: SLOW (${subprocess_time}ms) - Expected <500ms"
        else
            echo "✅ Subprocess: Normal (${subprocess_time}ms)"
        fi
    fi
else
    echo "⚠️  BC not available - cannot analyze performance metrics"
fi

echo ""
echo "💡 RECOMMENDATIONS"
echo "------------------"
echo "Run this script on both your local machine and server."
echo "Compare the results to identify the bottleneck."
echo ""
echo "Common issues:"
echo "- High CPU time = Server under load or weak CPU"
echo "- High I/O time = Slow/network disk storage"
echo "- High subprocess time = Process limits or overhead"
echo "- Network failures = DNS/firewall issues"
echo ""
echo "🏁 Diagnostic complete!"