#!/usr/bin/env bash
# this project is licensed under the GPL. See the LICENSE file for more information

# Includes ========================================================================
source ./file.sh
source ./header.sh
source ./saints.sh
source ./rss.sh
source ./exchange.sh
source ./UFPR/ferias.sh
source ./UFPR/ru.sh
source ./musicchart.sh
source ./weather.sh

# ==================================================================================

# Functions ========================================================================

# help function
# usage: ./hcnews.sh [options]
# options:
#   -h, --help: show the help
#   -s, --silent: the script will run silently"
#   -sa, --saints: show the saints of the day with the verbose description
#   -n, --news: show the news with the shortened link
show_help() {
    echo "Usage: ./hcnews.sh [options]"
    echo "Options:"
    echo "  -h, --help: show the help"
    echo "  -s, --silent: the script will run silently"
    echo "  -sa, --saints: show the saints of the day with the verbose description"
    echo "  -n, --news: show the news with the shortened link"
}

# this function will receive the arguments
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


# this function will ask for help
# 🤝 Quer contribuir com o HCNEWS? 🙋
# ✨https://github.com/herijooj/HCnews✨
function help_hcnews {
    echo "🤝 Quer contribuir com o HCNEWS? 🙋"
    echo "✨ https://github.com/herijooj/HCnews ✨"
    echo ""
}

# ==================================================================================

# Main =============================================================================

# Get the arguments
get_arguments "$@"

# Define Variables
date=$(date +%Y%m%d)
city="Curitiba"

# Define paths
news_file_name="$date.news"
news_file_path="./news/$news_file_name"

# RSS feeds
feed_1=https://opopularpr.com.br/feed/
feed_2=https://www.newyorker.com/feed/magazine/rss
feed_3=https://feeds.folha.uol.com.br/mundo/rss091.xml
feed_4=https://www.formula1.com/content/fom-website/en/latest/all.xml
feed_5=http://feeds.bbci.co.uk/news/world/latin_america/rss.xml

# put this in an array
feeds=("$feed_1" "$feed_2" "$feed_3")

# Create the news file
new_file "$news_file_name" "$news_file_path" "$silent"

# Write the header
write_header >> "$news_file_path"

# Write the saint(s) of the day
write_saints "$saints_verbose" >> "$news_file_path"

# Write the exchange rates
write_exchange >> "$news_file_path"

# Help HCNEWS
help_hcnews >> "$news_file_path"

# Write the music chart
write_music_chart >> "$news_file_path"

# Write the weather
write_weather "$city" "false" >> "$news_file_path"

# Write the news
for feed in "${feeds[@]}"; do
    write_news "$feed" "$news_shortened" >> "$news_file_path" 
done

# Write the F1 news
echo "🏎️ F1 🏎️" >> "$news_file_path"
write_news "$feed_4" "$news_shortened" >> "$news_file_path"

# Write the tech news
echo "🤖 Tech 🤖" >> "$news_file_path"
write_news "$feed_5" "$news_shortened" >> "$news_file_path"

# UFPR 
echo "🎓 UFPR 🎓" >> "$news_file_path"
# time to vacation
write_ferias >> "$news_file_path"

# menu of the day
write_menu >> "$news_file_path"
