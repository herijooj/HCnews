#!/usr/bin/env bash
set -euo pipefail

mapfile -t shell_files < <(git ls-files '*.sh')

if [[ ${#shell_files[@]} -eq 0 ]]; then
	echo "No shell files found."
	exit 0
fi

echo "Running shellcheck..."
shellcheck -S warning -e SC1090,SC1091 "${shell_files[@]}"

echo "Lint OK"
