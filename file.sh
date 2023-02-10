#!/usr/bin/env bash

# this function is used to generate the news file
new_file () {

    date=$(date +%Y%m%d)
    news_file_name=$date.news
    news_file_path=./news/$news_file_name

    # if [ -f $news_file_path ]; then
    #     echo "The news file $news_file_path already exists."
    #     echo "Please remove it before generating a new one."
    #     exit 1
    # fi

    touch $news_file_path
}