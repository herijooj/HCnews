#!/usr/bin/env bash

# include the other scripts
source ./file.sh
source ./header.sh
source ./holidays.sh
source ./rss.sh

# variables
DATE=$(date +%Y%m%d)
echo $DATE
NEWS_FILE_NAME=$DATE.news
echo $NEWS_FILE_NAME
NEWS_FILE_PATH=./news/$NEWS_FILE_NAME
echo $NEWS_FILE_PATH

# main function
main () {
    
    FEED_1=https://opopularpr.com.br/feed/
    FEED_2=http://g1.globo.com/dynamo/pr/parana/rss2.xml

    new_file $DATE $NEWS_FILE_PATH $NEWS_FILE_NAME
    write_header $NEWS_FILE_PATH
    #write_holidays $NEWS_FILE_PATH
    write_news $NEWS_FILE_PATH $FEED_1
    echo "" >> $NEWS_FILE_PATH 
    write_news $NEWS_FILE_PATH $FEED_2

    # echo the date and the date rss format
    echo "The date is: $(date)"
    echo "The date 24 hours ago was: $(get_date_24_hours_rss)"

}

# call the main function
main