#!/usr/bin/env bash

# Source common library if not already loaded
[[ -n "${_HCNEWS_COMMON_LOADED:-}" ]] || source "${HCNEWS_COMMON_PATH:-${BASH_SOURCE%/*}/../lib/common.sh}" 2>/dev/null || source "${BASH_SOURCE%/*}/scripts/lib/common.sh"

# Define available RU locations
declare -A RU_LOCATIONS=(
	["politecnico"]="https://proad.ufpr.br/ru/ru-centro-politecnico/"
	["agrarias"]="https://proad.ufpr.br/ru/cardapio-ru-agrarias/"
	["botanico"]="https://proad.ufpr.br/ru/cardapio-ru-jardim-botanico/"
	["central"]="https://proad.ufpr.br/ru/ru-central/"
	["toledo"]="https://proad.ufpr.br/ru/6751-2/"
	["mirassol"]="https://proad.ufpr.br/ru/cardapio-ru-mirassol/"
	["jandaia"]="https://proad.ufpr.br/ru/cardapio-ru-jandaia-do-sul/"
	["palotina"]="https://proad.ufpr.br/ru/cardapio-ru-palotina/"
	["cem"]="https://proad.ufpr.br/ru/cardapio-ru-cem/"
	["matinhos"]="https://proad.ufpr.br/ru/cardapio-ru-matinhos/"
)

# Friendly names for display
declare -A RU_NAMES=(
	["politecnico"]="Politécnico"
	["agrarias"]="Agrárias"
	["botanico"]="Botânico"
	["central"]="Central"
	["toledo"]="Toledo"
	["mirassol"]="Mirassol"
	["jandaia"]="Jandaia"
	["palotina"]="Palotina"
	["cem"]="CEM"
	["matinhos"]="Matinhos"
)

# Configuration with defaults
SELECTED_LOCATION="${SELECTED_LOCATION:-politecnico}"
SHOW_ONLY_TODAY=${SHOW_ONLY_TODAY:-false}

# Cache settings
_ru_USE_CACHE=${_HCNEWS_USE_CACHE:-true}
_ru_FORCE_REFRESH=${_HCNEWS_FORCE_REFRESH:-false}
_ru_CACHE_TTL=${HCNEWS_CACHE_TTL["ru"]:-43200} # 12 hours

# Resolve cache directory relative to common logic - handled by get_cache_path

function list_locations() {
	echo "Available RU locations:"
	for loc in "${!RU_LOCATIONS[@]}"; do
		echo "  - $loc"
	done
}

# Function to get today's day of the week in Portuguese
function get_today_weekday() {
	# Use cached weekday if available
	local dow
	if [[ -n "$weekday" ]]; then
		dow=$weekday
	else
		dow=$(date +%u)
	fi

	case "$dow" in
	1) echo "Segunda-feira" ;;
	2) echo "Terça-feira" ;;
	3) echo "Quarta-feira" ;;
	4) echo "Quinta-feira" ;;
	5) echo "Sexta-feira" ;;
	6) echo "Sábado" ;;
	7) echo "Domingo" ;;
	esac
}

# Function to retrieve the menu from the website
function get_menu() {
	local location="$1"
	local use_cache="${_ru_USE_CACHE:-${_HCNEWS_USE_CACHE:-true}}"
	local force_refresh="${_ru_FORCE_REFRESH:-${_HCNEWS_FORCE_REFRESH:-false}}"
	local show_today="${SHOW_ONLY_TODAY:-false}"
	local today=""
	local today_base=""

	if [[ "$show_today" == "true" ]]; then
		today=$(get_today_weekday)
		today_base="${today,,}"
		today_base="${today_base%%-*}"
	fi

	local date_string
	date_string=$(hcnews_get_date_format)
	local cache_variant="$location"
	if [[ "$show_today" == "true" ]]; then
		cache_variant="${location}_today"
	fi
	local cache_file
	hcnews_set_cache_path cache_file "ru" "$date_string" "$cache_variant"

	# Check cache
	if [[ "$use_cache" == "true" ]] && hcnews_check_cache "$cache_file" "$_ru_CACHE_TTL" "$force_refresh"; then
		hcnews_read_cache "$cache_file"
		return
	fi

	local url="${RU_LOCATIONS[$location]}"
	local pretty_name="${RU_NAMES[$location]}"
	if [[ -z "$pretty_name" ]]; then
		pretty_name="$location"
	fi

	# Process content using pup and awk
	local content
	content=$(
		set -o pipefail
		curl -fsS -4 --compressed --connect-timeout 5 --max-time 10 "$url" |
			perl -0777 -pe 's/<style[^>]*>.*?<\/style>//gis; s/<script[^>]*>.*?<\/script>//gis; s/<!--.*?-->//gs' |
			LC_ALL=C sed -e 's/<[^>]*>//g' |
			awk -v show_today="$show_today" -v today_base="$today_base" -v today_label="$today" '
        function emit_pending_meal() {
            if (pending_meal != "") {
                if (include_section == 1) {
                    print "\n" pending_meal
                }
                pending_meal = ""
            }
        }
        BEGIN { 
            print "🍽️  *Cardápio RU '"$pretty_name"'*" 
            skip = 0
            current_line = ""
            menu_started = 0
            pending_meal = ""
            include_section = (show_today == "true") ? 0 : 1
            matched_day = 0
            has_content = 0
        }
        /SENHOR USUÁRIO/ { skip = 1; next }
        /LEGENDA/ { skip = 1; next }
        /Cardápio sujeito/ { skip = 1; next }
        skip { next }
        
        /^[[:space:]]*$/ { next }
        /Cardápio RU/ { next }
        /:/ && (/table|background|border|padding|margin|color|font|width|height|display|overflow/) { next }
        /\{|\}/ { next }
        /\.wp-block/ { next }
        
        # Detect day headers first - this starts the menu
        /((Segunda|Ter[cç]a|Quarta|Quinta|Sexta)[-]?[Ff]eira|(S[áa]bado|Domingo)).*[0-9]/ {
            menu_started = 1
            if (current_line != "") {
                if (include_section == 1) {
                    print current_line
                    has_content = 1
                }
                current_line = ""
            }
            pending_meal = ""
            gsub(/^[[:space:]]+|[[:space:]]+$/, "")
            pos = match($0, /[0-9]/)
            if (pos > 0) {
                day = substr($0, 1, pos-1)
                date = substr($0, pos)
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", day)
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", date)

                if (show_today == "true") {
                    day_l = tolower(day)
                    day_b = day_l
                    sub(/-.*/, "", day_b)

                    if (day_b == today_base) {
                        include_section = 1
                        matched_day = 1
                        print "\n📅 *" day "* " date
                    } else {
                        if (matched_day == 1) {
                            exit
                        }
                        include_section = 0
                    }
                } else {
                    include_section = 1
                    print "\n📅 *" day "* " date
                }
            }
            next
        }
        
        # Skip all content before menu starts
        !menu_started { next }
        
        /Café da manhã/ { 
            if (current_line != "") {
                if (include_section == 1) {
                    print current_line
                    has_content = 1
                }
                current_line = ""
            }
            if (include_section == 1) {
                pending_meal = "🥪 *CAFÉ DA MANHÃ* 🥪"
            } else {
                pending_meal = ""
            }
            next 
        }
        /Almoço/ { 
            if (current_line != "") {
                if (include_section == 1) {
                    print current_line
                    has_content = 1
                }
                current_line = ""
            }
            if (include_section == 1) {
                pending_meal = "🍝 *ALMOÇO* 🍝"
            } else {
                pending_meal = ""
            }
            next 
        }
        /Jantar/ { 
            if (current_line != "") {
                if (include_section == 1) {
                    print current_line
                    has_content = 1
                }
                current_line = ""
            }
            if (include_section == 1) {
                pending_meal = "🍛 *JANTAR* 🍛"
            } else {
                pending_meal = ""
            }
            next 
        }
        
        /^(Contêm|Contém|Indicado)/ { next }
        
        {
            if (include_section != 1) next

            # Check for connectives
            if (/^[[:space:]]*e / || /^[[:space:]]*\+/ || /^[[:space:]]*Molho para salada:/) {
                gsub(/^[[:space:]]+|[[:space:]]+$/, "")
                gsub(/Molho para salada:/, "+")
                if (current_line != "") {
                    current_line = current_line " " $0
                } else {
                    emit_pending_meal()
                    current_line = "- " $0
                }
                next
            }
            
            gsub(/^[[:space:]]+|[[:space:]]+$/, "")
            if (length($0) == 0) next
            gsub(/2ª [Oo]pção:/, "ou")
            
            if (current_line != "") {
                print current_line
                has_content = 1
            }
            emit_pending_meal()
            current_line = "- " $0
        }
        END {
            if (current_line != "") {
                if (include_section == 1) {
                    print current_line
                    has_content = 1
                }
            }
            if (show_today == "true" && has_content == 0) {
                print "Não há cardápio disponível para hoje (" today_label ")."
            }
        }' 2>/dev/null
	)

	# Validate content
	if [[ -z "$content" || "$content" == "🍽️  *Cardápio RU $pretty_name*" ]]; then
		if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
			echo "O RU está fechado ou o cardápio é especial."
		else
			echo "O RU está *fechado* ou o cardápio é *especial*."
		fi
		return
	fi

	# Write to cache
	if [[ "$use_cache" == "true" ]]; then
		hcnews_write_cache "$cache_file" "$content"
	fi

	echo "$content"
}

# Function to display the menu
hc_component_ru() {
	get_menu "$SELECTED_LOCATION"
	echo ""
}

# Help function
help() {
	echo "Usage: $0 [options]"
	echo "Prints the RU menu to the console."
	echo "Options:"
	echo "  -h, --help: show this help message"
	echo "  -l, --list: list available RU locations"
	echo "  -r, --ru LOCATION: select RU location (default: politecnico)"
	echo "  -t, --today: show only today's menu"
	echo "  -n, --no-cache: do not use cached data"
	echo "  -f, --force: force refresh cache"
}

# Main script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	# Process arguments checks
	# Process arguments checks
	hcnews_parse_args "$@"
	_ru_USE_CACHE=$_HCNEWS_USE_CACHE
	_ru_FORCE_REFRESH=$_HCNEWS_FORCE_REFRESH

	set -- "${_HCNEWS_REMAINING_ARGS[@]}"

	while [[ $# -gt 0 ]]; do
		case "$1" in
		-l | --list)
			list_locations
			exit 0
			;;
		-r | --ru)
			if [ -z "$2" ]; then
				echo "Error: RU location not specified"
				exit 1
			fi
			if [[ -v "RU_LOCATIONS[$2]" ]]; then
				SELECTED_LOCATION="$2"
			else
				echo "Error: Invalid RU location '$2'"
				list_locations
				exit 1
			fi
			shift
			;;
		-t | --today)
			SHOW_ONLY_TODAY=true
			;;
		esac
		shift
	done

	hc_component_ru
fi
