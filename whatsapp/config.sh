#!/usr/bin/env bash
# =============================================================================
# HCNews WhatsApp Integration - Configuration
# =============================================================================
# This file contains configuration for the WhatsApp automation workflow.
# Copy to config.local.sh and edit for local overrides.
# =============================================================================

# -----------------------------------------------------------------------------
# Secrets (read from environment)
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# -----------------------------------------------------------------------------
# Target Machine Settings (hc-m91p - the worker with WAHA)
# -----------------------------------------------------------------------------
TARGET_HOST="${TARGET_HOST:-hc-m91p.tail82a040.ts.net}"
TARGET_MAC="${TARGET_MAC:-d0:27:88:5d:e0:bd}"
TARGET_USER="${TARGET_USER:-hc}"
TARGET_LAN_IP="${TARGET_LAN_IP:-192.168.100.18}"

# Network interface on r-h3 used to send WoL packets
# r-h3 uses 'end0' (Armbian naming)
WOL_INTERFACE="${WOL_INTERFACE:-end0}"

# -----------------------------------------------------------------------------
# Baileys Settings (running on hc-m91p)
# -----------------------------------------------------------------------------
# Auth state directory for Baileys
BAILEYS_AUTH_DIR="${BAILEYS_AUTH_DIR:-/home/hc/Documentos/HCnews/whatsapp/baileys_auth}"

# WhatsApp Channel ID for HCNews
# Channel URL: https://whatsapp.com/channel/0029VaCRDb6FSAszqoID6k2Y
# Channel Name: "HCNews 2026!"
WHATSAPP_CHANNEL_ID="${WHATSAPP_CHANNEL_ID:-120363206957534786@newsletter}"

# Node.js binary path (for Baileys worker)
NODE_PATH="${NODE_PATH:-node}"

# -----------------------------------------------------------------------------
# Paths
# -----------------------------------------------------------------------------
# HCNews project path on local machine
HCNEWS_PATH="${HCNEWS_PATH:-/home/hc/Documentos/HCnews}"

# HCNews project path on target/remote machine (hc-m91p)
# Used by orchestrator when running worker via SSH
REMOTE_HCNEWS_PATH="${REMOTE_HCNEWS_PATH:-/home/hc/Documentos/HCnews}"

# State directory on orchestrator (r-h3)
STATE_DIR="${STATE_DIR:-/var/lib/hcnews-whatsapp}"

# Log file
LOG_FILE="${LOG_FILE:-${STATE_DIR}/send.log}"

# -----------------------------------------------------------------------------
# Timing Configuration
# -----------------------------------------------------------------------------
# Seconds to wait for machine to come online after WoL
WAKE_TIMEOUT="${WAKE_TIMEOUT:-180}"

# Seconds between SSH availability checks
WAKE_CHECK_INTERVAL="${WAKE_CHECK_INTERVAL:-10}"

# SSH connection timeout
SSH_TIMEOUT="${SSH_TIMEOUT:-30}"

# SSH command execution timeout (hcnews.sh can take a while)
SSH_COMMAND_TIMEOUT="${SSH_COMMAND_TIMEOUT:-300}"

# Hour after which to stop retrying (24h format)
MAX_RETRY_HOUR="${MAX_RETRY_HOUR:-23}"

# Minimum hour to start trying (24h format)
MIN_START_HOUR="${MIN_START_HOUR:-6}"

# -----------------------------------------------------------------------------
# Behavior Flags
# -----------------------------------------------------------------------------
# Set to true to enable verbose logging
DEBUG="${DEBUG:-false}"

# Set to true to skip actual WhatsApp send (for testing)
DRY_RUN="${DRY_RUN:-false}"
