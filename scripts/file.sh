#!/usr/bin/env bash

# This function is used to generate the news file.
new_file() {
	local news_file_name=$1
	local news_file_path=$2
	local silent=$3

	# If the directory doesn't exist, create it.
	if [[ ! -d "data/news" ]]; then
		mkdir -p data/news
	fi

	# Always overwrite the file without asking for user confirmation.
	touch "$news_file_path"
	echo "The news file $news_file_path was created or overwritten."
}
