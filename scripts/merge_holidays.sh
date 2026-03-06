#!/usr/bin/env bash

# Script to merge 2026 holidays with custom entries
# Creates a combined holidays.csv file

SCRIPT_DIR=$(dirname "$(realpath "${BASH_SOURCE[0]}")")
PROJECT_ROOT=$(realpath "$SCRIPT_DIR/..")
HOLIDAYS_2026="$PROJECT_ROOT/data/holidays_2026_scraped.csv"
HOLIDAYS_CUSTOM="$PROJECT_ROOT/data/holidays_custom.csv"
OUTPUT_FILE="$PROJECT_ROOT/data/holidays.csv"
TEMP_DIR="/tmp/holidays_merge_$$"

echo "Merging 2026 holidays with custom entries..."

# Backup current holidays.csv if it exists
if [[ -f "$OUTPUT_FILE" ]]; then
	BACKUP_FILE="$PROJECT_ROOT/data/holidays_backup_$(date +%Y%m%d_%H%M%S).csv"
	echo "Backing up current holidays.csv to: $(basename "$BACKUP_FILE")"
	cp "$OUTPUT_FILE" "$BACKUP_FILE"
fi

# Create temp directory
mkdir -p "$TEMP_DIR"

# Track all entries by key (month,day,description)
declare -A seen_entries

# Process 2026 holidays first
echo "Processing 2026 holidays..."
while IFS=, read -r month day emoji description; do
	# Skip empty lines
	[[ -z "$month" ]] && continue

	# Add default emoji if empty
	[[ -z "$emoji" ]] && emoji="📅"

	# Create unique key
	key="${month},${day},${description}"

	# Store entry
	echo "$month,$day,$emoji,$description" >>"$TEMP_DIR/merged.txt"
	seen_entries["$key"]=1
done <"$HOLIDAYS_2026"

# Process custom holidays (these will override 2026 if same key exists)
echo "Processing custom holidays..."
while IFS=, read -r month day emoji description; do
	# Skip empty lines
	[[ -z "$month" ]] && continue

	# Create unique key
	key="${month},${day},${description}"

	# If this entry already exists in 2026 file, skip it (2026 version is kept)
	# Unless it's a custom birthday/event we want to keep
	if [[ -n "${seen_entries[$key]:-}" ]]; then
		echo "  Skipping duplicate: $description"
		continue
	fi

	# Add custom entry
	echo "$month,$day,$emoji,$description" >>"$TEMP_DIR/custom.txt"
	seen_entries["$key"]=1
done <"$HOLIDAYS_CUSTOM"

# Count entries
count_2026=$(wc -l <"$TEMP_DIR/merged.txt")
count_custom=$(wc -l <"$TEMP_DIR/custom.txt" 2>/dev/null || echo "0")

echo ""
echo "Statistics:"
echo "  2026 holidays: $count_2026"
echo "  Custom entries: $count_custom"
echo "  Total unique: $((count_2026 + count_custom))"

# Merge and sort by month and day
echo ""
echo "Creating merged and sorted file..."
(
	cat "$TEMP_DIR/merged.txt"
	[[ -f "$TEMP_DIR/custom.txt" ]] && cat "$TEMP_DIR/custom.txt"
) | sort -t',' -k1,1n -k2,2n >"$OUTPUT_FILE"

# Clean up
rm -rf "$TEMP_DIR"

# Verify output
total=$(wc -l <"$OUTPUT_FILE")
echo ""
echo "✓ Created $OUTPUT_FILE with $total entries"
echo ""
echo "Sample entries:"
head -10 "$OUTPUT_FILE"
echo "..."
tail -5 "$OUTPUT_FILE"
