#!/usr/bin/env bash

# this function writes the holidays to the news file
write_holidays () {
    # get the file path
    file_path=$1
    # write a new line
    echo "" >> $file_path
    echo "🗓 HOJE É DIA... 🎉" >> $file_path
    echo "" >> $file_path
}