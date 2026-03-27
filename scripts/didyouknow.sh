#!/usr/bin/env bash

# Source common library if not already loaded
[[ -n "${_HCNEWS_COMMON_LOADED:-}" ]] || source "${HCNEWS_COMMON_PATH}common.sh" 2>/dev/null || source "${BASH_SOURCE%/*}/lib/common.sh"

get_didyouknow() {
	local use_cache="${_didyouknow_USE_CACHE:-${_HCNEWS_USE_CACHE:-true}}"
	local force_refresh="${_didyouknow_FORCE_REFRESH:-${_HCNEWS_FORCE_REFRESH:-false}}"
	local date_str
	date_str=$(hcnews_get_date_format)

	local component_name="didyouknow"
	if [[ "${HCNEWS_HTML_OUTPUT:-false}" == "true" ]]; then
		component_name="didyouknow_html"
	fi

	local cache_file
	hcnews_set_cache_path cache_file "$component_name" "$date_str"
	local ttl=${HCNEWS_CACHE_TTL["didyouknow"]:-86400}

	# Cache check
	if [[ "$use_cache" = true ]] && hcnews_check_cache "$cache_file" "$ttl" "$force_refresh"; then
		hcnews_read_cache "$cache_file"
		return 0
	fi

	local URL="https://pt.wikipedia.org/w/api.php?action=query&prop=extracts|revisions&explaintext=1&titles=Predefini%C3%A7%C3%A3o:Sabia_que&rvprop=content&format=json"

	local response
	response=$(curl -s -H "User-Agent: HCnews/1.0 (https://github.com/herijooj/HCnews)" --compressed --connect-timeout 5 --max-time 10 "$URL") || return 1

	# Process directly. Extract lines starting with … or ...
	local items
	items=$(jq -r '.query.pages[]?.extract' <<<"$response" | grep -E '^[….]' | sed 's/^… //;s/^\.\.\. //;s/\\n/ /g' | shuf -n 1)

	# Fallback if empty
	if [[ -z "$items" ]]; then
		return 1
	fi

	# Clean text
	items=$(echo "$items" | tr -s ' ' | sed 's/^ *//;s/ *$//')
	if type hcnews_decode_html_entities &>/dev/null; then
		items=$(hcnews_decode_html_entities "$items")
	fi

	local output="📚 *Você sabia?*"
	output+=$'\n'
	output+="- ${items}"

	# Image handling for HTML output
	if [[ "${HCNEWS_HTML_OUTPUT:-false}" == "true" ]] && [[ "$items" =~ \(imagem\) ]]; then
		local wikitext
		wikitext=$(jq -r '.query.pages[]?.revisions[0]["*"]' <<<"$response")

		local image_filename
		# Extract content inside <imagemap> ... </imagemap>
		local imagemap_content
		imagemap_content=$(echo "$wikitext" | sed -n '/<imagemap>/,/<\/imagemap>/p')
		image_filename=$(echo "$imagemap_content" | grep -iE "^\s*(Imagem|File|Ficheiro):" | head -n 1 | cut -d'|' -f1)

		# Clean filename
		image_filename=$(echo "$image_filename" | tr -d '[:space:]')

		if [[ -n "$image_filename" ]]; then
			# Fetch image URL
			local image_api_url="https://pt.wikipedia.org/w/api.php?action=query&titles=${image_filename}&prop=imageinfo&iiprop=url&format=json"
			local image_response
			image_response=$(curl -s -H "User-Agent: HCnews/1.0 (https://github.com/herijooj/HCnews)" --compressed --connect-timeout 5 --max-time 10 "$image_api_url")

			local image_url
			image_url=$(jq -r '.query.pages[].imageinfo[0].url // empty' <<<"$image_response")

			if [[ -n "$image_url" ]]; then
				output+=$'\n'
				output+="![Imagem](${image_url})"
			fi
		fi
	fi

	output+=$'\n_Fonte: Wikipedia_'

	if [[ "$use_cache" == true ]]; then
		hcnews_write_cache "$cache_file" "$output"
	fi
	echo "$output"
}

hc_component_didyouknow() {
	get_didyouknow
}

# -------------------------------- Running locally --------------------------------

# Standard help
show_help() {
	echo "Usage: ./didyouknow.sh [--no-cache|--force]"
	echo "Fetches a random 'Did You Know' fact from Wikipedia."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	hcnews_parse_args "$@"
	if [[ ${#_HCNEWS_REMAINING_ARGS[@]} -gt 0 ]]; then
		echo "Invalid argument: ${_HCNEWS_REMAINING_ARGS[0]}" >&2
		show_help
		exit 1
	fi
	_didyouknow_USE_CACHE=$_HCNEWS_USE_CACHE
	_didyouknow_FORCE_REFRESH=$_HCNEWS_FORCE_REFRESH
	hc_component_didyouknow
fi
