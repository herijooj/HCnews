#!/usr/bin/env bash

# this function is used to generate the news file
new_file () {

    DATE=$1
    NEWS_FILE_NAME=$2
    NEWS_FILE_PATH=$3

    # if [ -f $news_file_path ]; then
    #     echo "The news file $news_file_path already exists."
    #     echo "Please remove it before generating a new one."
    #     exit 1
    # fi

    touch $NEWS_FILE_PATH
    echo "The news file $NEWS_FILE_PATH was created."
}