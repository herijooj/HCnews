#!/usr/bin/env bash

# include the other scripts
source ./file.sh
source ./header.sh
source ./holidays.sh

# variables
date=$(date +%Y%m%d)
news_file_name=$date.news
news_file_path=./news/$news_file_name

# main function
main () {
    
    new_file
    write_header $news_file_path
    write_holidays $news_file_path

}

# call the main function
main