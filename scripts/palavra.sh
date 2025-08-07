#!/usr/bin/env bash
# this project is licensed under the GPL. See the LICENSE file for more information

# Function to get the word of the day from dicio.com.br
write_palavra_do_dia() {
    # URL of the word of the day page
    local url="https://www.dicio.com.br/palavra-do-dia/"

    # Fetch the page content
    local content=$(curl -s "$url")

    # Extract the word, meaning, and quote using pup
    local palavra=$(echo "$content" | pup 'div.word-of-day:first-of-type h3 a text{}')
    local significado=$(echo "$content" | pup 'p.word-of-day--description.significado.textonovo' text{})
    local citacao=$(echo "$content" | pup 'div.word-of-day:first-of-type .word-of-day--extra:last-of-type p:first-of-type' text{})

    # Output the formatted word of the day
    echo "📖 *Palavra do Dia:* ${palavra}"
    echo "- ${significado}"
    echo "_${citacao}_"
    echo ""
}
