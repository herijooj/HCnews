#!/usr/bin/env bash

# this project is licensed under the GPL. See the LICENSE file for more information

# Include the other scripts
source ./file.sh
source ./header.sh
source ./saints.sh
source ./rss.sh

# help function
show_help() {
    echo "Usage: ./hcnews.sh [options]"
    echo "Options:"
    echo "  -h, --help: show the help"
    echo "  -s, --silent: the script will run silently"
    echo "  -sa, --saints: show the saints of the day with the verbose description"
    echo "  -n, --news: show the news with the shortened link"
}

# this function will receive the arguments
# usage: ./hcnews.sh [options]
# options:
#   -h, --help: show the help
#   -s, --silent: the script will run silently"
#   -sa, --saints: show the saints of the day with the verbose description
#   -n, --news: show the news with the shortened link
get_arguments() {
    # Define variables
    silent=false
    saints_verbose=false
    news_shortened=false

    # Get the arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -s|--silent)
                silent=true
                shift
                ;;
            -sa|--saints)
                saints_verbose=true
                shift
                ;;
            -n|--news)
                news_shortened=true
                shift
                ;;
            *)
                echo "Invalid argument: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Define main function
main() {
    # Define variables
    date=$(date +%Y%m%d)

    # Define paths
    news_file_name="$date.news"
    news_file_path="./news/$news_file_name"

    # RSS feeds
    feed_1=https://opopularpr.com.br/feed/
    feed_2=https://g1.globo.com/rss/g1/
    feed_3=https://feeds.folha.uol.com.br/mundo/rss091.xml
    # put this in an array
    feeds=("$feed_1" "$feed_2" "$feed_3")

    # Create the news file
    new_file "$news_file_name" "$news_file_path" "$silent"

    # Write the header
    write_header "$news_file_path" "$news_file_name"

    # Write the saint(s) of the day
    write_saints "$news_file_path" "$saints_verbose"

    # Write the news
    for feed in "${feeds[@]}"; do
        write_news "$news_file_path" "$feed" "$news_shortened"
    done

}

# Call the arguments function
get_arguments "$@"
# Call the main function
main