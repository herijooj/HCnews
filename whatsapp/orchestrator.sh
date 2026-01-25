#!/usr/bin/env bash
# =============================================================================
# HCNews WhatsApp Orchestrator
# =============================================================================
# This script runs on r-h3 (always-on server) and coordinates:
# 1. Checking if we've already sent today
# 2. Waking hc-m91p via Wake-on-LAN if needed
# 3. Running the worker script via SSH
# 4. Shutting down hc-m91p if we woke it
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load environment from .secrets (if direnv is not active)
if [[ -z "${WAHA_API_KEY:-}" ]]; then
    [[ -f "${SCRIPT_DIR}/../.secrets" ]] && source "${SCRIPT_DIR}/../.secrets"
fi

# Load configuration
source "${SCRIPT_DIR}/config.sh"
[[ -f "${SCRIPT_DIR}/config.local.sh" ]] && source "${SCRIPT_DIR}/config.local.sh"

# -----------------------------------------------------------------------------
# Logging
# -----------------------------------------------------------------------------
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Log to file
    mkdir -p "$(dirname "${LOG_FILE}")"
    echo "[${timestamp}] [${level}] ${message}" >> "${LOG_FILE}"
    
    # Log to stderr (for journald when running as service)
    echo "[${level}] ${message}" >&2
}

log_info()  { log "INFO" "$@"; }
log_warn()  { log "WARN" "$@"; }
log_error() { log "ERROR" "$@"; }
log_debug() { [[ "${DEBUG}" == "true" ]] && log "DEBUG" "$@" || true; }

# -----------------------------------------------------------------------------
# State Management
# -----------------------------------------------------------------------------
get_today() {
    date '+%Y-%m-%d'
}

is_sent_today() {
    local state_file="${STATE_DIR}/last_sent"
    if [[ -f "${state_file}" ]]; then
        local last_sent
        last_sent=$(cat "${state_file}")
        [[ "${last_sent}" == "$(get_today)" ]]
    else
        return 1
    fi
}

mark_sent() {
    mkdir -p "${STATE_DIR}"
    get_today > "${STATE_DIR}/last_sent"
    log_info "Marked as sent for $(get_today)"
}

# Track if we woke the machine (to know if we should shut it down)
set_woke_flag() {
    touch "${STATE_DIR}/.we_woke_machine"
}

clear_woke_flag() {
    rm -f "${STATE_DIR}/.we_woke_machine"
}

did_we_wake() {
    [[ -f "${STATE_DIR}/.we_woke_machine" ]]
}

# -----------------------------------------------------------------------------
# Time Window Checks
# -----------------------------------------------------------------------------
is_within_retry_window() {
    local current_hour
    current_hour=$(date '+%-H')
    
    if (( current_hour >= MIN_START_HOUR && current_hour <= MAX_RETRY_HOUR )); then
        return 0
    else
        return 1
    fi
}

# -----------------------------------------------------------------------------
# Machine Availability
# -----------------------------------------------------------------------------
is_host_reachable() {
    local ssh_host="${TARGET_LAN_IP}"
    ssh -o ConnectTimeout=5 \
        -o BatchMode=yes \
        -o StrictHostKeyChecking=accept-new \
        "${TARGET_USER}@${ssh_host}" \
        "echo ok" &>/dev/null
}

wake_host() {
    log_info "Sending Wake-on-LAN to ${TARGET_MAC} via ${WOL_INTERFACE}"
    
    # Try etherwake (common on Debian/Armbian) - check both PATH and /usr/sbin
    if command -v etherwake &>/dev/null; then
        sudo etherwake -i "${WOL_INTERFACE}" "${TARGET_MAC}"
    elif [[ -x /usr/sbin/etherwake ]]; then
        sudo /usr/sbin/etherwake -i "${WOL_INTERFACE}" "${TARGET_MAC}"
    elif command -v wakeonlan &>/dev/null; then
        wakeonlan -i "${TARGET_LAN_IP%.*}.255" "${TARGET_MAC}"
    else
        log_error "No Wake-on-LAN tool found (etherwake or wakeonlan)"
        return 1
    fi
}

wait_for_host() {
    local timeout="${WAKE_TIMEOUT}"
    local interval="${WAKE_CHECK_INTERVAL}"
    local elapsed=0

    log_info "Waiting for ${TARGET_LAN_IP} to become reachable (timeout: ${timeout}s)"

    while (( elapsed < timeout )); do
        if is_host_reachable; then
            log_info "Host ${TARGET_LAN_IP} is now reachable after ${elapsed}s"
            return 0
        fi

        log_debug "Host not reachable yet, waiting... (${elapsed}/${timeout}s)"
        sleep "${interval}"
        (( elapsed += interval ))
    done

    log_error "Host ${TARGET_LAN_IP} did not become reachable within ${timeout}s"
    return 1
}

# -----------------------------------------------------------------------------
# Remote Execution
# -----------------------------------------------------------------------------
run_worker() {
    log_info "Executing worker script on ${TARGET_LAN_IP}"

    local worker_path="${REMOTE_HCNEWS_PATH}/whatsapp/worker.sh"
    local ssh_opts=(
        -o ConnectTimeout="${SSH_TIMEOUT}"
        -o BatchMode=yes
        -o StrictHostKeyChecking=accept-new
    )

    local remote_host="${TARGET_LAN_IP}"
    
    # Wrap command in nix-shell to ensure dependencies are available
    local remote_cmd="cd ${REMOTE_HCNEWS_PATH} && nix-shell ${REMOTE_HCNEWS_PATH}/default.nix --run 'bash ${worker_path}'"
    if [[ "${DRY_RUN}" == "true" ]]; then
        remote_cmd="cd ${REMOTE_HCNEWS_PATH} && nix-shell ${REMOTE_HCNEWS_PATH}/default.nix --run 'bash ${worker_path} --dry-run'"
    fi
    
    log_debug "Remote command: ${remote_cmd}"
    
    if timeout "${SSH_COMMAND_TIMEOUT}" ssh "${ssh_opts[@]}" \
        "${TARGET_USER}@${remote_host}" "${remote_cmd}"; then
        log_info "Worker script completed successfully"
        return 0
    else
        local exit_code=$?
        log_error "Worker script failed with exit code ${exit_code}"
        return "${exit_code}"
    fi
}

shutdown_host() {
    log_info "Shutting down ${TARGET_LAN_IP}"

    local ssh_opts=(
        -o ConnectTimeout="${SSH_TIMEOUT}"
        -o StrictHostKeyChecking=accept-new
    )

    ssh "${ssh_opts[@]}" \
        "${TARGET_USER}@${TARGET_LAN_IP}" \
        "poweroff" || true

    sleep 5
    log_info "Shutdown command sent to ${TARGET_LAN_IP}"
}

# -----------------------------------------------------------------------------
# Main Orchestration
# -----------------------------------------------------------------------------
shutdown_if_we_woke() {
    if did_we_wake; then
        log_info "Shutting down machine (we woke it)"
        shutdown_host
    else
        log_info "Machine was already on, leaving it running"
    fi
    clear_woke_flag
}

run_with_retry() {
    local max_retries="${MAX_RETRIES:-3}"
    local retry_count=0
    local was_already_on=false

    # Check if host is already reachable
    if is_host_reachable; then
        log_info "Host ${TARGET_LAN_IP} is already online"
        was_already_on=true
    fi

    while (( retry_count < max_retries )); do
        (( retry_count++ ))

        if (( retry_count > 1 )); then
            log_info "Retry attempt ${retry_count}/${max_retries}"
        fi

        # Wake the machine if needed
        local need_to_wake=false
        if ! is_host_reachable; then
            log_info "Host ${TARGET_LAN_IP} is offline, attempting wake"

            if ! wake_host; then
                log_error "Failed to send Wake-on-LAN packet"
                if (( retry_count < max_retries )); then
                    sleep 60
                    continue
                else
                    return 1
                fi
            fi

            set_woke_flag
            need_to_wake=true

            if ! wait_for_host; then
                log_error "Host did not come online"
                clear_woke_flag
                if (( retry_count < max_retries )); then
                    sleep 60
                    continue
                else
                    return 1
                fi
            fi
        elif ! $was_already_on; then
            set_woke_flag
            need_to_wake=true
        fi

        # Run the worker script
        if run_worker; then
            log_info "Message sent successfully!"
            mark_sent
            shutdown_if_we_woke
            return 0
        else
            log_error "Worker failed"

            # Always shut down on failure
            shutdown_if_we_woke

            if (( retry_count < max_retries )); then
                log_info "Waiting before retry..."
                sleep 60
                continue
            else
                log_error "All retry attempts exhausted"
                return 1
            fi
        fi
    done

    return 1
}

main() {
    log_info "=== HCNews WhatsApp Orchestrator starting ==="

    # Clear any stale woke flag from previous runs
    clear_woke_flag

    # Check if already sent today
    if is_sent_today; then
        log_info "Already sent today ($(get_today)), skipping"
        exit 0
    fi

    # Check if within retry window
    if ! is_within_retry_window; then
        log_info "Outside retry window (${MIN_START_HOUR}:00 - ${MAX_RETRY_HOUR}:00), skipping"
        exit 0
    fi

    # Run with retry logic
    if run_with_retry; then
        exit 0
    else
        exit 1
    fi
}

# Run main
main "$@"
