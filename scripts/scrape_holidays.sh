#!/usr/bin/env bash

# Script to scrape Calendarr 2026 holidays and convert to CSV
# Output format: MM,DD,,description (emoji column empty)

URL="https://www.calendarr.com/brasil/datas-comemorativas-2026/"
HTML_FILE="/tmp/holidays_2026_raw.html"
OUTPUT_FILE="/home/hc/Documentos/HCnews/data/holidays_2026_scraped.csv"

# Month name to number mapping
get_month_num() {
	local month="$1"
	month=$(echo "$month" | sed 's/&amp;/\&/g; s/&ccedil;/ç/g; s/&atilde;/ã/g; s/&otilde;/õ/g; s/&aacute;/á/g; s/&eacute;/é/g; s/&iacute;/í/g; s/&oacute;/ó/g; s/&uacute;/ú/g')

	case "$month" in
	Janeiro) echo "01" ;;
	Fevereiro) echo "02" ;;
	Março) echo "03" ;;
	Abril) echo "04" ;;
	Maio) echo "05" ;;
	Junho) echo "06" ;;
	Julho) echo "07" ;;
	Agosto) echo "08" ;;
	Setembro) echo "09" ;;
	Outubro) echo "10" ;;
	Novembro) echo "11" ;;
	Dezembro) echo "12" ;;
	*) echo "00" ;;
	esac
}

# Download the HTML
echo "Downloading holidays data from Calendarr..."
curl -s -A "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36" "$URL" -o "$HTML_FILE"

# Create or clear output file (no header, format: month,day,emoji,description)
: >"$OUTPUT_FILE"

# Line numbers for each month section
declare -a month_lines=(324 1257 2343 3663 5001 6663 8091 9123 10434 11925 13686 14943)
total_months=${#month_lines[@]}

# Process each month
for ((i = 0; i < total_months; i++)); do
	start_line=${month_lines[$i]}

	# Next month's start line (or end of file for December)
	if [[ $i -lt $((total_months - 1)) ]]; then
		end_line=${month_lines[$((i + 1))]}
	else
		end_line=$(wc -l <"$HTML_FILE")
	fi

	# Extract month section
	sed -n "${start_line},$((end_line - 1))p" "$HTML_FILE" >/tmp/current_month.txt

	# Extract month name
	month_full=$(head -3 /tmp/current_month.txt | grep -oP '<span>\K[^<]+' | head -1)
	month_num_val=$(get_month_num "$month_full")

	if [[ "$month_num_val" == "00" ]]; then
		echo "Warning: Could not map month '$month_full' to number"
		continue
	fi

	echo "Processing $month_full (month $month_num_val, lines $start_line-$end_line)..."

	# Extract all holiday entries by finding lines with <li> tags and their context
	grep -n '<li data-\(holiday\|optional\|dayof\|other\|curious\)' /tmp/current_month.txt | while IFS=: read -r li_line rest; do
		# Extract the day (3 lines after <li>)
		day_line=$((li_line + 3))
		day=$(sed -n "${day_line}p" /tmp/current_month.txt | grep -oP '\b[0-9]+\b' | head -1)

		# Format day with leading zero
		if [[ -n "$day" && ${#day} -eq 1 ]]; then
			day="0$day"
		fi

		# Extract the description (6 lines after <li>)
		desc_line=$((li_line + 6))
		description=$(sed -n "${desc_line}p" /tmp/current_month.txt | grep -oP 'holiday-name[^>]*>\K[^<]+')

		# Clean description
		description=$(echo "$description" | sed 's/([^)]*)//g; s/&nbsp;/ /g; s/  */ /g; s/^ *//;s/ *$//')

		# Skip if empty
		[[ -z "$day" || -z "$description" ]] && continue

		# Output to CSV
		echo "$month_num_val,$day,,$description" >>"$OUTPUT_FILE"
	done

	rm -f /tmp/current_month.txt
done

# Clean up
rm -f "$HTML_FILE"

# Count entries
entry_count=$(wc -l <"$OUTPUT_FILE")
echo ""
echo "Done! Created $OUTPUT_FILE"
echo "Total entries: $((entry_count - 1)) (excluding header)"
echo ""
echo "Sample entries:"
head -20 "$OUTPUT_FILE"
