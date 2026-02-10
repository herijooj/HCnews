#!/usr/bin/env bash
# =============================================================================
# HCnews Air Quality Component
# =============================================================================
# Fetches Air Quality Index (AQI) data from OpenWeatherMap Air Pollution API
# Displays current AQI level with health recommendations for the city
# =============================================================================

# Source common library if not already loaded
# shellcheck source=/dev/null
[[ -n "${_HCNEWS_COMMON_LOADED:-}" ]] || source "${HCNEWS_COMMON_PATH}common.sh" 2>/dev/null || source "${BASH_SOURCE%/*}/lib/common.sh"

# AQI Level descriptions and emojis
# OpenWeatherMap AQI: 1=Good, 2=Fair, 3=Moderate, 4=Poor, 5=Very Poor
declare -A AQI_LEVELS=(
	["1"]="🟢 Bom"
	["2"]="🟡 Razoável"
	["3"]="🟠 Moderado"
	["4"]="🔴 Ruim"
	["5"]="🟣 Muito Ruim"
)

declare -A AQI_HEALTH_TIPS=(
	["1"]="Qualidade do ar ideal para atividades ao ar livre."
	["2"]="Qualidade aceitável. Grupos sensíveis devem limitar exposição prolongada."
	["3"]="Pessoas sensíveis podem sentir desconforto. Considere reduzir atividades intensas."
	["4"]="Evite atividades ao ar livre. Use máscara se necessário sair."
	["5"]="Condições perigosas. Evite sair de casa. Mantenha janelas fechadas."
)

declare -A AQI_EMOJIS=(
	["1"]="🟢"
	["2"]="🟡"
	["3"]="🟠"
	["4"]="🔴"
	["5"]="🟣"
)

# City coordinates lookup (lat,lon) - add more as needed
declare -A CITY_COORDS=(
	["curitiba"]="-25.4284,-49.2733"
	["sao paulo"]="-23.5505,-46.6333"
	["rio de janeiro"]="-22.9068,-43.1729"
	["brasilia"]="-15.7942,-47.8825"
	["belo_horizonte"]="-19.9167,-43.9345"
	["porto_alegre"]="-30.0346,-51.2177"
	["salvador"]="-12.9714,-38.5014"
	["recife"]="-8.0476,-34.8770"
	["fortaleza"]="-3.7172,-38.5433"
	["manaus"]="-3.1190,-60.0217"
	["florianopolis"]="-27.5969,-48.5495"
	["londrina"]="-23.3045,-51.1696"
	["maringa"]="-23.4205,-51.9333"
	["ponta grossa"]="-25.0945,-50.1633"
)

# Help function
show_help() {
	echo "Usage: ./airquality.sh [City] [--no-cache|--force]"
	echo ""
	echo "Fetches Air Quality Index (AQI) data for one or more cities."
	echo ""
	echo "Options:"
	echo "  --no-cache    Disable cache use"
	echo "  --force       Force refresh even if cache exists"
	echo ""
	echo "If no city is provided, it fetches a pre-defined list of cities in parallel."
}

# Get coordinates for a city (fallback to geocoding API if not in lookup)
get_city_coords() {
	local city="$1"
	local city_lower="${city,,}"
	city_lower="${city_lower// /_}"

	# Check lookup table first
	if [[ -n "${CITY_COORDS[$city_lower]:-}" ]]; then
		echo "${CITY_COORDS[$city_lower]}"
		return 0
	fi

	# Normalize with spaces for API
	local city_query="${city// /%20}"

	# Use OpenWeatherMap Geocoding API
	local geo_url="https://api.openweathermap.org/geo/1.0/direct?q=${city_query},BR&limit=1&appid=${openweathermap_API_KEY}"
	local geo_response
	geo_response=$(curl -s -4 --compressed --connect-timeout 5 --max-time 10 "$geo_url")

	local lat lon
	lat=$(echo "$geo_response" | jq -r '.[0].lat // empty' 2>/dev/null)
	lon=$(echo "$geo_response" | jq -r '.[0].lon // empty' 2>/dev/null)

	if [[ -n "$lat" && -n "$lon" ]]; then
		echo "$lat,$lon"
		return 0
	fi

	# No fallback for generic lookup (to avoid duplicates in multicity)
	return 1
}

# Format pollutant value with unit
format_pollutant() {
	local name="$1"
	local value="$2"
	local unit="${3:-μg/m³}"

	if [[ -z "$value" || "$value" == "null" ]]; then
		echo "N/A"
		return
	fi

	# Round to 1 decimal
	LC_ALL=C printf "%.1f %s" "$value" "$unit"
}

# Main function to get air quality data for a single city
get_airquality() {
	local CITY="${1:-Curitiba}"
	local city_lower="${CITY,,}"
	local city_norm="${city_lower// /_}"
	local SHORT_FORMAT="${2:-false}"

	local date_str
	date_str=$(hcnews_get_date_format)

	local cache_file
	local cache_suffix=""
	[ "$SHORT_FORMAT" = "true" ] && cache_suffix="_short"
	hcnews_set_cache_path cache_file "airquality" "$date_str" "${city_norm}${cache_suffix}"

	# Check cache
	if [ "${_airquality_USE_CACHE:-true}" = true ] &&
		hcnews_check_cache "$cache_file" "$CACHE_TTL_SECONDS" "${_airquality_FORCE_REFRESH:-false}"; then
		hcnews_read_cache "$cache_file"
		return
	fi

	# Get coordinates
	local coords
	coords=$(get_city_coords "$CITY") || coords="-25.4284,-49.2733" # Fallback to Curitiba only at the edge
	IFS=',' read -r lat lon <<<"$coords"

	# Use /dev/shm for temp files if available
	local tmp_dir="/dev/shm"
	[[ -d "$tmp_dir" && -w "$tmp_dir" ]] || tmp_dir="/tmp"
	local air_temp="${tmp_dir}/.airquality_${city_norm}_$$"

	# Fetch air quality data from OpenWeatherMap Air Pollution API
	local AIR_URL="https://api.openweathermap.org/data/2.5/air_pollution?lat=${lat}&lon=${lon}&appid=${openweathermap_API_KEY}"

	curl -s -4 -A "Mozilla/5.0 (Script; HCnews)" --compressed --connect-timeout 5 --max-time 10 "$AIR_URL" >"$air_temp"

	local AIR_DATA
	AIR_DATA=$(<"$air_temp")
	rm -f "$air_temp"

	# Validate response
	local aqi
	aqi=$(echo "$AIR_DATA" | jq -r '.list[0].main.aqi // empty' 2>/dev/null)

	if [[ -z "$aqi" ]]; then
		echo "❌ Dados de qualidade do ar não disponíveis para ${CITY}."
		return 1
	fi

	# Extract pollutant components
	local components
	components=$(echo "$AIR_DATA" | jq -r '.list[0].components' 2>/dev/null)

	local pm25 pm10 o3 no2 so2 co
	pm25=$(echo "$components" | jq -r '.pm2_5 // empty' 2>/dev/null)
	pm10=$(echo "$components" | jq -r '.pm10 // empty' 2>/dev/null)
	o3=$(echo "$components" | jq -r '.o3 // empty' 2>/dev/null)
	no2=$(echo "$components" | jq -r '.no2 // empty' 2>/dev/null)
	so2=$(echo "$components" | jq -r '.so2 // empty' 2>/dev/null)
	co=$(echo "$components" | jq -r '.co // empty' 2>/dev/null)

	# Get level description and tips
	local level_desc="${AQI_LEVELS[$aqi]:-🔵 Desconhecido}"
	local health_tip="${AQI_HEALTH_TIPS[$aqi]:-Sem informações disponíveis.}"
	local level_emoji="${AQI_EMOJIS[$aqi]:-🔵}"

	# Get current time for update timestamp
	local now="${current_time:-$(date +"%H:%M:%S")}"

	# Build output
	local OUTPUT
	if [ "$SHORT_FORMAT" = "true" ]; then
		# Even shorter format for multicity list
		printf -v OUTPUT -- '- %s *%s*: %s (PM2.5: `%s`)' \
			"$level_emoji" "$CITY" "${level_desc#* }" "$(format_pollutant "PM2.5" "$pm25")"
	else
		printf -v OUTPUT '🌬️ *Qualidade do Ar - %s*
Índice: *%s*
💡 _%s_

📊 *Poluentes:*
- PM2.5: `%s` | PM10: `%s`
- O₃: `%s` | NO₂: `%s`

_Fonte: OpenWeatherMap · %s_' \
			"$CITY" \
			"$level_desc" \
			"$health_tip" \
			"$(format_pollutant "PM2.5" "$pm25")" \
			"$(format_pollutant "PM10" "$pm10")" \
			"$(format_pollutant "O3" "$o3")" \
			"$(format_pollutant "NO2" "$no2")" \
			"$now"
	fi

	# Cache the result
	[ "${_airquality_USE_CACHE:-true}" = true ] && hcnews_write_cache "$cache_file" "$OUTPUT"

	echo "$OUTPUT"
}

# Write function called by hcnews.sh or standalone
write_airquality() {
	local CITY="${1:-Curitiba}"
	local SHORT_FORMAT="${2:-false}"
	local block
	block=$(get_airquality "$CITY" "$SHORT_FORMAT") || {
		echo "$block"
		return 1
	}

	echo -e "$block\n"
}

# Parallel multicity fetch
write_airquality_all() {
	local CITIES=("Curitiba" "Londrina" "Maringá" "Ponta Grossa" "Cascavel" "São José dos Pinhais" "Foz do Iguaçu" "São Paulo" "Rio de Janeiro" "Brasília")
	local tmp_dir="/tmp/airquality_$$"
	mkdir -p "$tmp_dir"

	echo "🌬️ *Qualidade do Ar no Brasil*"
	echo ""

	# Fetch in parallel
	for i in "${!CITIES[@]}"; do
		(
			local city="${CITIES[$i]}"
			local result
			if result=$(get_airquality "$city" "true"); then
				echo "$result" >"$tmp_dir/$i"
			fi
		) &
		# Tiny delay to prevent API rate limit issues on start
		sleep 0.2
	done

	wait

	# Check if any files were created
	if [ -z "$(ls -A "$tmp_dir" 2>/dev/null)" ]; then
		echo "⚠️ Nenhum dado de qualidade do ar disponível no momento."
		echo ""
	else
		# Output in order
		for i in "${!CITIES[@]}"; do
			if [ -f "$tmp_dir/$i" ]; then
				cat "$tmp_dir/$i"
				echo ""
			fi
		done
	fi

	echo "📖 *Legenda:* 🟢 Bom · 🟡 Razoável · 🟠 Moderado · 🔴 Ruim · 🟣 Muito Ruim"
	echo ""
	echo "_Fonte: OpenWeatherMap · Atualizado: ${current_time:-$(date +"%H:%M:%S")}_"
	rm -rf "$tmp_dir"
}

# Standard argument parsing
hcnews_parse_args "$@"
_airquality_USE_CACHE=$_HCNEWS_USE_CACHE
_airquality_FORCE_REFRESH=$_HCNEWS_FORCE_REFRESH
# Shift to remaining arguments for city name
set -- "${_HCNEWS_REMAINING_ARGS[@]}"

# Use centralized TTL (added to common.sh)
CACHE_TTL_SECONDS="${HCNEWS_CACHE_TTL["airquality"]:-10800}"

# Run standalone if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	# If a city is provided (not starting with --), fetch only that city
	if [[ -n "$1" && "$1" != --* ]]; then
		write_airquality "$1"
	else
		write_airquality_all
	fi
fi
