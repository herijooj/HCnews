#!/usr/bin/env bash

# this function writes the holidays to the news file
write_holidays () {
    # get the file path
    FILE_PATH=$1
    # write a new line
    echo "" >> $FILE_PATH
    echo "🗓 HOJE É DIA... 🎉" >> $FILE_PATH
    echo "" >> $FILE_PATH
}