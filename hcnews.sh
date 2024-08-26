#!/usr/bin/env bash
# this project is licensed under the GPL. See the LICENSE file for more information

# Includes ========================================================================
SCRIPT_DIR=$(dirname "$0")

source "$SCRIPT_DIR/file.sh"
source "$SCRIPT_DIR/header.sh"
source "$SCRIPT_DIR/saints.sh"
source "$SCRIPT_DIR/rss.sh"
source "$SCRIPT_DIR/exchange.sh"
source "$SCRIPT_DIR/UFPR/ferias.sh"
source "$SCRIPT_DIR/UFPR/ru.sh"
source "$SCRIPT_DIR/musicchart.sh"
source "$SCRIPT_DIR/weather.sh"
source "$SCRIPT_DIR/didyouknow.sh"
source "$SCRIPT_DIR/holidays.sh"

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
    echo "  -f, --file: if the output will be to a file"
}

# this function will receive the arguments
get_arguments() {
    # Define variables
    silent=false
    saints_verbose=false
    news_shortened=false
    file=false

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
            -f|--file)
                file=true
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

# Função para imprimir o footer
function footer {
    echo "🤝 Quer contribuir com o HCNEWS? 🙋"
    echo "O HCNEWS é gerado automaticamente todos os dias 🤖 "
    echo "Tecnologias usadas: RSS 📰 Bash 🚀 Python 🐍 Nix 💻"
    echo "✨ https://github.com/herijooj/HCnews ✨"
    echo "Que Deus abençoe a todos! 🙏"
    echo ""
}


function output {

    # Define variables
    saints_verbose=$1
    news_shortened=$2
    
    # RSS feeds
    o_popular=https://opopularpr.com.br/feed/
    newyorker=https://www.newyorker.com/feed/magazine/rss
    folha=https://feeds.folha.uol.com.br/mundo/rss091.xml
    g1=https://g1.globo.com/rss/g1/pr/parana/
    formula1=https://www.formula1.com/content/fom-website/en/latest/all.xml
    bcc=http://feeds.bbci.co.uk/news/world/latin_america/rss.xml

    # put this in an array
    feeds=("$o_popular" "$newyorker" "$g1")

    # Write the header
    write_header

    # Write the saint(s) of the day
    write_saints "$saints_verbose"

    # Write the exchange rates
    write_exchange

    # Help HCNEWS
    help_hcnews

    # Write the holidays
    write_holidays "$month" "$day"

    # Write the music chart
    write_music_chart

    # Write the weather
    write_weather "$city" "false"

    # Write "Did you know?"
    write_did_you_know

    # UFPR 

    # time to vacation
    #write_ferias

    # menu of the day
    write_menu

    # Write the news
    for feed in "${feeds[@]}"; do
        write_news "$feed" "$news_shortened" 
    done

    # # Write the F1 news
    # echo "🏎️ F1 🏎️"
    # write_news "$formula1" "$news_shortened"

    # # Write the tech news
    # echo "🤖 Tech 🤖"
    # write_news "$bcc" "$news_shortened"

    # Write the footer
    footer
}

# Main =============================================================================

# Get the arguments
get_arguments "$@"

# Define Variables
date=$(date +%Y%m%d)
month=$(date +%m)
day=$(date +%d)
city="Curitiba"

# if the output will be to a file
if [[ $file == true ]]; then
    # Define paths
    news_file_name="$date.news"
    news_file_path="./news/$news_file_name"

    # Create the news file
    new_file "$news_file_name" "$news_file_path" "$silent"

    # Output to the file
    output "$saints_verbose" "$news_shortened" >> "$news_file_path"
    exit 0
else
    # Output to the terminal
    output "$saints_verbose" "$news_shortened"
    exit 0
fi