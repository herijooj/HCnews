#!/usr/bin/env bash

# Include the other scripts
source ./file.sh
source ./header.sh
source ./saints.sh
source ./holidays.sh
source ./rss.sh

# Define main function
main() {

    # Define variables
    date=$(date +%Y%m%d)

    # Define paths
    news_file_name="$date.news"
    news_file_path="./news/$news_file_name"
    holidays_file_path=holidays.md

    # RSS feeds
    feed_1=https://opopularpr.com.br/feed/
    feed_2=https://g1.globo.com/rss/g1/
    feed_3=https://feeds.folha.uol.com.br/mundo/rss091.xml

    # Create the holiday table
    # get_holiday_table "$holidays_file_path"

    # Create the news file
    new_file "$news_file_name" "$news_file_path"

    # Write the header
    write_header "$news_file_path" "$news_file_name"

    # Write the saint(s) of the day
    write_saints "$news_file_path"

    # write_holidays "$news_file_path"
    write_news "$news_file_path" "$feed_1"
    echo "" >> "$news_file_path"
    write_news "$news_file_path" "$feed_2"
    echo "" >> "$news_file_path"
    write_news "$news_file_path" "$feed_3"
}

# Call the main function
main