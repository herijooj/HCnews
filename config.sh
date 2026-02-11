#!/usr/bin/env bash
# =============================================================================
# HCNews Configuration File
# =============================================================================
# Copy this file to config.local.sh and edit to customize.
# Values here are the defaults - config.local.sh will override them.
# =============================================================================

# Load secrets if available (fallback if direnv/.envrc not active)
# shellcheck disable=SC1091
[[ -f "${HCNEWS_ROOT:-$(dirname "${BASH_SOURCE[0]}")}/.secrets" ]] && source "${HCNEWS_ROOT:-$(dirname "${BASH_SOURCE[0]}")}/.secrets"

# -----------------------------------------------------------------------------
# Location Settings
# -----------------------------------------------------------------------------
# Default city for weather (case-insensitive, spaces allowed)
HCNEWS_CITY="${HCNEWS_CITY:-Curitiba}"

# Multi-city weather (for --all flag)
# shellcheck disable=SC2034
HCNEWS_WEATHER_CITIES=(
	"Curitiba"
	"São Paulo"
	"Rio de Janeiro"
	"Londrina"
	"Florianópolis"
)

# -----------------------------------------------------------------------------
# RSS Feeds Configuration
# -----------------------------------------------------------------------------
# Primary news feeds (comma-separated for main news)
HCNEWS_FEEDS_PRIMARY="${HCNEWS_FEEDS_PRIMARY:-opopular,plantao190}"

# All available feeds (associative array - key: feed name, value: URL)
# Can be used with -n flag or extended news output
# shellcheck disable=SC2034
declare -gA HCNEWS_FEEDS=(
	["opopular"]="https://opopularpr.com.br/feed/"
	["plantao190"]="https://plantao190.com.br/feed/"
	# ["xvcuritiba"]="https://xvcuritiba.com.br/feed/"  # Disabled: DNS issues
	["bandab"]="https://www.bandab.com.br/web-stories/feed/"
	["g1_parana"]="https://g1.globo.com/rss/g1/pr/parana/"
	["g1_cinema"]="https://g1.globo.com/rss/g1/pop-arte/cinema/"
	["newyorker"]="https://www.newyorker.com/feed/magazine/rss"
	["folha"]="https://feeds.folha.uol.com.br/mundo/rss091.xml"
	["formula1"]="https://www.formula1.com/content/fom-website/en/latest/all.xml"
	["bbc"]="http://feeds.bbci.co.uk/news/world/latin_america/rss.xml"
)

# -----------------------------------------------------------------------------
# Music Chart Settings
# -----------------------------------------------------------------------------
# Apple Music RSS URL (country code and chart type)
HCNEWS_MUSIC_CHART_URL="${HCNEWS_MUSIC_CHART_URL:-https://rss.applemarketingtools.com/api/v2/br/music/most-played/10/songs.json}"
HCNEWS_MUSIC_LIMIT="${HCNEWS_MUSIC_LIMIT:-10}"

# -----------------------------------------------------------------------------
# Horoscope Settings
# -----------------------------------------------------------------------------
# Available signs (in Portuguese)
# shellcheck disable=SC2034
HCNEWS_HOROSCOPE_SIGNS=(
	"aries"
	"touro"
	"gemeos"
	"cancer"
	"leao"
	"virgem"
	"libra"
	"escorpiao"
	"sagitario"
	"capricornio"
	"aquario"
	"peixes"
)

# -----------------------------------------------------------------------------
# Caching Settings (can be overridden by CLI flags)
# -----------------------------------------------------------------------------
# Set to false to disable all caching
HCNEWS_USE_CACHE="${HCNEWS_USE_CACHE:-true}"

# Cache directory (default: data/cache in project root)
HCNEWS_CACHE_DIR="${HCNEWS_CACHE_DIR:-${HCNEWS_HOME:-$(dirname "${BASH_SOURCE[0]}")}/data/cache}"

# -----------------------------------------------------------------------------
# Output Settings
# -----------------------------------------------------------------------------
# Full URLs instead of shortened links (for web builds)
HCNEWS_FULL_URL="${HCNEWS_FULL_URL:-false}"

# -----------------------------------------------------------------------------
# API Keys (expected via environment variables, e.g., .envrc)
# -----------------------------------------------------------------------------
# OpenWeatherMap - get yours at https://openweathermap.org/api
: "${openweathermap_API_KEY:=${OPENWEATHERMAP_API_KEY:-}}"

# CoinMarketCap - get yours at https://coinmarketcap.com/api
: "${CoinMarketCap_API_KEY:=${COINMARKETCAP_API_KEY:-}}"

# -----------------------------------------------------------------------------
# Regional Settings
# -----------------------------------------------------------------------------
# Timezone (for display purposes)
HCNEWS_TZ="${HCNEWS_TZ:-America/Sao_Paulo}"

# Date format (used throughout)
HCNEWS_DATE_FORMAT="${HCNEWS_DATE_FORMAT:-%d/%m/%Y}"
