#!/usr/bin/env bash

# This function is used to generate the news file.
new_file() {
    local news_file_name=$1
    local news_file_path=$2
    local silent=$3

    # If the directory doesn't exist, create it.
    if [[ ! -d "./news" ]]; then
        mkdir news
    fi

    # If the file already exists, ask the user if they want to overwrite it.
    # if the program is running silently, the file will be overwritten.
    if [[ -f "$news_file_path" ]]; then
        if [[ $silent == true ]]; then
            touch "$news_file_path"
            return
        fi
        echo "The news file $news_file_name already exists."
        read -p "Do you want to overwrite it? [y/n] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            touch "$news_file_path"
            echo "The news file $news_file_path was overwritten."
        else
            # If the user doesn't want to overwrite the file, exit the script.
            echo "Exiting the script."
            exit 1
        fi
    else
        touch "$news_file_path"
        echo "The news file $news_file_path was created."
    fi
}