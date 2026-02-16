#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(dirname "$(realpath "${BASH_SOURCE[0]}")")
ROOT_DIR=$(realpath "$SCRIPT_DIR/..")
TEMPLATE_FILE="$ROOT_DIR/.github/template.html"
PUBLIC_DIR="$ROOT_DIR/public"
DATE=$(date +'%d/%m/%Y')

if [[ ! -f "$TEMPLATE_FILE" ]]; then
	echo "Error: template not found at $TEMPLATE_FILE" >&2
	exit 1
fi

mkdir -p "$PUBLIC_DIR"

pages=(
	"news_tudo.out:index.html:Tudo"
	"news_noticias.out:noticias.html:Noticias"
	"news_horoscopo.out:horoscopo.html:Horoscopo"
	"news_esportes.out:esportes.html:Futebol"
	"news_weather.out:weather.html:Previsao do Tempo"
	"news_hackernews.out:hackernews.html:Hacker News"
	"news_ru.out:ru.html:RU"
)

echo "Generating HTML files..." >&2

for spec in "${pages[@]}"; do
	IFS=: read -r source_file target_file label <<<"$spec"
	source_path="$PUBLIC_DIR/$source_file"
	target_path="$PUBLIC_DIR/$target_file"

	if [[ ! -s "$source_path" ]]; then
		echo "Error: missing or empty source file for $label: $source_path" >&2
		exit 1
	fi

	sed "s|{{DATE}}|$DATE|g" "$TEMPLATE_FILE" |
		sed -e '/{{CONTENT}}/r '"$source_path" -e '/{{CONTENT}}/d' >"$target_path"

	echo " - public/$target_file" >&2
done

echo "HTML generation complete." >&2
