#!/usr/bin/env bash
# =============================================================================
# HCNews WhatsApp Worker
# =============================================================================
# This script runs on hc-m91p and:
# 1. Generates HCNews content using hcnews.sh
# 2. Sends it to the WhatsApp channel via WAHA API
# =============================================================================

set -euo pipefail

# Load environment from .secrets (if direnv is not active)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${WAHA_API_KEY:-}" ]]; then
	# shellcheck disable=SC1091
	[[ -f "${SCRIPT_DIR}/../.secrets" ]] && source "${SCRIPT_DIR}/../.secrets"
fi

# Check if all required dependencies are available
check_dependencies() {
	local missing=()
	for cmd in pup jq xmlstarlet bc python3; do
		if ! command -v "$cmd" &>/dev/null; then
			missing+=("$cmd")
		fi
	done

	if [[ ${#missing[@]} -gt 0 ]]; then
		echo "Missing dependencies: ${missing[*]}" >&2
		return 1
	fi
	return 0
}

# Re-exec under nix-shell if any dependency is missing
if ! check_dependencies; then
	echo "[WARN] Missing dependencies, attempting to re-exec under nix-shell..." >&2
	SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
	HCNEWS_PATH="${HCNEWS_PATH:-${SCRIPT_DIR}/..}"
	nix_file="${HCNEWS_PATH}/default.nix"

	# Export API key so nix-shell inherits it
	export WAHA_API_KEY

	if [[ -f "${nix_file}" ]]; then
		echo "[INFO] Found nix file at ${nix_file}, re-executing..." >&2
		exec nix-shell "${nix_file}" --run "bash $0 $*"
	else
		echo "[ERROR] Nix file not found at ${nix_file}" >&2
		echo "[ERROR] Cannot re-exec under nix-shell, dependencies are missing" >&2
		exit 1
	fi
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load configuration
source "${SCRIPT_DIR}/config.sh"
# shellcheck disable=SC1091
[[ -f "${SCRIPT_DIR}/config.local.sh" ]] && source "${SCRIPT_DIR}/config.local.sh"

# -----------------------------------------------------------------------------
# Argument Parsing
# -----------------------------------------------------------------------------
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

# -----------------------------------------------------------------------------
# Logging
# -----------------------------------------------------------------------------
log() {
	local level="$1"
	shift
	echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${level}] $*" >&2
}

log_info() { log "INFO" "$@"; }
log_warn() { log "WARN" "$@"; }
log_error() { log "ERROR" "$@"; }
log_debug() { # shellcheck disable=SC2015
	[[ "${DEBUG}" == "true" ]] && log "DEBUG" "$@" || true
}

# -----------------------------------------------------------------------------
# Secrets Validation
# -----------------------------------------------------------------------------
require_waha_secrets() {
	if [[ -z "${WAHA_API_KEY:-}" ]]; then
		log_error "WAHA_API_KEY is not set. Export it in the environment."
		return 1
	fi
	return 0
}

# -----------------------------------------------------------------------------
# Content Generation
# -----------------------------------------------------------------------------
generate_content() {
	log_info "Generating HCNews content..."

	local hcnews_script="${HCNEWS_PATH}/hcnews.sh"

	if [[ ! -x "${hcnews_script}" ]]; then
		log_error "hcnews.sh not found or not executable at ${hcnews_script}"
		return 1
	fi

	# Generate content
	local content
	if ! content=$("${hcnews_script}" 2>/dev/null); then
		log_error "hcnews.sh failed to generate content"
		return 1
	fi

	# Validate content
	if [[ -z "${content}" ]]; then
		log_error "hcnews.sh produced empty content"
		return 1
	fi

	local line_count
	line_count=$(echo "${content}" | wc -l)
	if ((line_count < 10)); then
		log_error "Content seems too short (${line_count} lines), something may be wrong"
		return 1
	fi

	log_info "Generated content: ${line_count} lines"
	echo "${content}"
}

# -----------------------------------------------------------------------------
# WAHA API Interaction
# -----------------------------------------------------------------------------
start_waha_session() {
	log_info "Attempting to start WAHA session..."

	local response
	response=$(curl -s -w "\n%{http_code}" \
		-X POST \
		-H "X-Api-Key: ${WAHA_API_KEY}" \
		-H "Content-Type: application/json" \
		-d "{\"name\": \"${WAHA_SESSION}\"}" \
		"${WAHA_URL}/api/sessions/start")

	local http_code
	http_code=$(echo "${response}" | tail -n1)

	if [[ "${http_code}" == "200" || "${http_code}" == "201" ]]; then
		log_info "Session start triggered"
		return 0
	else
		log_warn "Failed to start session: HTTP ${http_code}"
		return 1
	fi
}

check_waha_session() {
	log_info "Checking WAHA session status..."

	local max_attempts=12 # 12 attempts * 10 seconds = 2 minutes
	local attempt=1

	while ((attempt <= max_attempts)); do
		local response
		response=$(curl -s -w "\n%{http_code}" \
			-H "X-Api-Key: ${WAHA_API_KEY}" \
			"${WAHA_URL}/api/sessions/${WAHA_SESSION}")

		local http_code
		http_code=$(echo "${response}" | tail -n1)
		local body
		body=$(echo "${response}" | sed '$d')

		if [[ "${http_code}" != "200" ]]; then
			log_warn "Failed to check session status: HTTP ${http_code} (attempt ${attempt}/${max_attempts})"
			sleep 10
			((attempt++))
			continue
		fi

		local status
		status=$(echo "${body}" | jq -r '.status // .state // "unknown"')

		log_info "WAHA session status: ${status} (attempt ${attempt}/${max_attempts})"

		case "${status}" in
		WORKING | CONNECTED)
			log_info "WAHA session is ready"
			return 0
			;;
		STARTING)
			log_info "Session is starting, waiting..."
			sleep 10
			((attempt++))
			continue
			;;
		STOPPED)
			log_info "Session is stopped, attempting to start..."
			start_waha_session
			sleep 10
			((attempt++))
			continue
			;;
		SCAN_QR_CODE)
			log_error "WAHA session needs re-authentication (QR code scan required)"
			log_error "Please scan QR at: ${WAHA_URL}/dashboard"
			return 1
			;;
		*)
			log_warn "Unknown session state: ${status}, waiting..."
			sleep 10
			((attempt++))
			continue
			;;
		esac
	done

	log_error "WAHA session did not become ready within timeout"
	return 1
}

send_to_whatsapp() {
	local content="$1"
	local targets=("${WHATSAPP_CHANNEL_ID}" "${WHATSAPP_GROUP_ID}")
	local failed=0

	for target in "${targets[@]}"; do
		log_info "Sending message to ${target}..."

		# Escape content for JSON
		local escaped_content
		escaped_content=$(echo "${content}" | jq -Rs '.')

		# Build the request payload
		local payload
		payload=$(
			cat <<EOF
{
    "chatId": "${target}",
    "text": ${escaped_content},
    "session": "${WAHA_SESSION}"
}
EOF
		)

		log_debug "Payload: ${payload}"

		if [[ "${DRY_RUN}" == "true" ]]; then
			log_info "[DRY RUN] Would send message to ${target}"
			continue
		fi

		# Send the message
		local response
		response=$(curl -s -w "\n%{http_code}" \
			-X POST \
			-H "Content-Type: application/json" \
			-H "X-Api-Key: ${WAHA_API_KEY}" \
			-d "${payload}" \
			"${WAHA_URL}/api/sendText")

		local http_code
		http_code=$(echo "${response}" | tail -n1)
		local body
		body=$(echo "${response}" | sed '$d')

		log_debug "Response: ${body}"

		if [[ "${http_code}" == "200" || "${http_code}" == "201" ]]; then
			log_info "Message sent successfully to ${target}!"

			# Try to extract message ID for confirmation
			local msg_id
			msg_id=$(echo "${body}" | jq -r '.id // .key.id // "unknown"' 2>/dev/null || echo "unknown")
			# Handle case where key.id is an object
			if [[ "${msg_id}" == *"fromMe"* ]]; then
				msg_id=$(echo "${body}" | jq -r '.key.id // "unknown"' 2>/dev/null || echo "unknown")
			fi
			log_info "Message ID: ${msg_id}"
		else
			log_error "Failed to send message to ${target}: HTTP ${http_code}"
			log_error "Response: ${body}"
			failed=1
		fi
	done

	return ${failed}
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
	log_info "=== HCNews WhatsApp Worker starting ==="

	if [[ "${DRY_RUN}" == "true" ]]; then
		log_info "Running in DRY RUN mode - no messages will be sent"
	fi

	if ! require_waha_secrets; then
		exit 1
	fi

	# Check WAHA session is working
	if ! check_waha_session; then
		log_error "WAHA session check failed"
		exit 1
	fi

	# Generate content
	local content
	if ! content=$(generate_content); then
		log_error "Content generation failed"
		exit 1
	fi

	# Send to WhatsApp
	if ! send_to_whatsapp "${content}"; then
		log_error "Failed to send message to WhatsApp"
		exit 1
	fi

	log_info "=== HCNews WhatsApp Worker completed successfully ==="
	exit 0
}

# Run main
main "$@"
