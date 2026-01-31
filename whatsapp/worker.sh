#!/usr/bin/env bash
# =============================================================================
# HCNews WhatsApp Worker (Baileys)
# =============================================================================
# This script runs on hc-m91p and:
# 1. Ensures Node.js dependencies are installed
# 2. Generates HCNews content using hcnews.sh
# 3. Sends it to the WhatsApp channel via Baileys
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -z "${BAILEYS_AUTH_DIR:-}" ]]; then
    [[ -f "${SCRIPT_DIR}/../.secrets" ]] && source "${SCRIPT_DIR}/../.secrets"
fi

source "${SCRIPT_DIR}/config.sh"
[[ -f "${SCRIPT_DIR}/config.local.sh" ]] && source "${SCRIPT_DIR}/config.local.sh"

DRY_RUN="${DRY_RUN:-false}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$1] $2" >&2
}

log_info()  { log "INFO" "$@"; }
log_warn()  { log "WARN" "$@"; }
log_error() { log "ERROR" "$@"; }
log_debug() { [[ "${DEBUG}" == "true" ]] && log "DEBUG" "$@" || true; }

check_node_dependencies() {
    local whatsapp_dir="${SCRIPT_DIR}"
    local package_json="${whatsapp_dir}/package.json"
    local node_modules="${whatsapp_dir}/node_modules"

    if [[ ! -f "${package_json}" ]]; then
        log_error "package.json not found in ${whatsapp_dir}"
        return 1
    fi

    if [[ ! -d "${node_modules}" ]]; then
        log_info "Installing Node.js dependencies..."
        cd "${whatsapp_dir}"
        if ! npm install 2>&1; then
            log_error "Failed to install Node.js dependencies"
            return 1
        fi
        log_info "Node.js dependencies installed successfully"
    else
        log_debug "Node.js dependencies already installed"
    fi

    return 0
}

run_baileys_worker() {
    local whatsapp_dir="${SCRIPT_DIR}"
    local worker_script="${whatsapp_dir}/worker.mjs"

    if [[ ! -f "${worker_script}" ]]; then
        log_error "Baileys worker script not found at ${worker_script}"
        return 1
    fi

    log_info "Running Baileys worker..."

    export HCNEWS_PATH="${HCNEWS_PATH:-${SCRIPT_DIR}/..}"
    export AUTH_DIR="${BAILEYS_AUTH_DIR:-${whatsapp_dir}/baileys_auth}"
    export LOG_FILE="${LOG_FILE:-/var/lib/hcnews-whatsapp/send.log}"
    export WHATSAPP_CHANNEL_ID="${WHATSAPP_CHANNEL_ID:-120363206957534786@newsletter}"

    if [[ "${DRY_RUN}" == "true" ]]; then
        export DRY_RUN=true
    fi

    cd "${whatsapp_dir}"

    if "${NODE_PATH:-node}" "${worker_script}"; then
        log_info "Baileys worker completed successfully"
        return 0
    else
        local exit_code=$?
        log_error "Baileys worker failed with exit code ${exit_code}"
        return "${exit_code}"
    fi
}

main() {
    log_info "=== HCNews WhatsApp Worker (Baileys) starting ==="

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "Running in DRY RUN mode - no messages will be sent"
    fi

    if ! check_node_dependencies; then
        log_error "Failed to check/install Node.js dependencies"
        exit 1
    fi

    if ! run_baileys_worker; then
        log_error "Baileys worker failed"
        exit 1
    fi

    log_info "=== HCNews WhatsApp Worker completed successfully ==="
    exit 0
}

main "$@"
