#!/usr/bin/env bash

# Get the saint(s) of the day from the Vatican website.
# https://www.vaticannews.va/pt/santo-do-dia/MONTH/DAY.html
# This function prints the name(s) and the description of the saint(s).
get_saints_of_the_day_verbose () {
    # Get the current month and day.
    local month
    local day
    month=$(date +%m)
    day=$(date +%d)

    # Get the URL
    local url="https://www.vaticannews.va/pt/santo-do-dia/$month/$day.html"

    # Only the names
    local names
    names=$(curl -s "$url" | pup '.section__head h2 text{}' | sed '/^$/d')

    # The description
    local description
    description=$(curl -s "$url" | pup '.section__head h2 text{}, .section__content p text{}' | sed '/^$/d' | sed '1d'| sed '/^[[:space:]]*$/d')

    # Iterate over each name and print the corresponding description.
    local name
    while read -r name; do
        echo "😇 $name"
        echo "$description" | head -n 1
        description=$(echo "$description" | tail -n +2)
    done <<< "$names"
}

# Get the saint(s) of the day from the Vatican website.
# https://www.vaticannews.va/pt/santo-do-dia/MONTH/DAY.html
# This function only prints the name of the saint(s).
get_saints_of_the_day () {
    # Get the current month and day.
    local month
    local day
    month=$(date +%m)
    day=$(date +%d)

    # Get the URL
    local url="https://www.vaticannews.va/pt/santo-do-dia/$month/$day.html"

    # Only the names
    local names
    names=$(curl -s "$url" | pup '.section__head h2 text{}' | sed '/^$/d')

    local name
    while read -r name; do
        echo "😇 $name"
    done <<< "$names"
}

write_saints () {
    local news_file_path=$1
    local saints_verbose=$2

    echo "🙏 Santos do dia 💒" >> "$news_file_path"
    if [[ "$saints_verbose" == "true" ]]; then
        get_saints_of_the_day_verbose >> "$news_file_path"
    else
        get_saints_of_the_day >> "$news_file_path"
    fi
    echo "" >> "$news_file_path"
}