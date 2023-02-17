#!/usr/bin/env bash

# this function converts a date in RSS format to unix
# RFC 2822 example: Fri, 03 Feb 2023 16:00:00 +0000
date_rss_to_unix () {

    # change the locale to en_US
    export LC_ALL=en_US.UTF-8

    # get the date in RSS format
    DATE_RSS=$1

    # convert the date to unix
    DATE_UNIX=$(date -d "$DATE_RSS" +%s)

    # change the locale back to normal
    export LC_ALL=C


    # return the date in unix
    echo "$DATE_UNIX"
}

# this function returns the date from 24 hours ago in RFC 2822
# example: Fri, 03 Feb 2023 16:00:00 +0000
get_date_24_hours_rss () {
    export LC_ALL=en_US.UTF-8

    # get the date in RFC 2822
    DATE_RSS=$(date -R -d "24 hours ago")
    export LC_ALL=C

    # return the date in RFC 2822
    echo "$DATE_RSS"
}

# this function compares two dates in RSS format
# returns 1 if the first date is greater than the second
# returns 0 if the first date is less than the second
compare_dates_rss () {

    # get the dates in RSS format
    DATE_1=$1
    DATE_2=$2

    # convert the dates to unix
    DATE_1_UNIX=$(date_rss_to_unix "$DATE_1")
    DATE_2_UNIX=$(date_rss_to_unix "$DATE_2")

    # compare the dates
    if [ "$DATE_1_UNIX" -gt "$DATE_2_UNIX" ]; then
        echo 1
    else
        echo 0
    fi
}

# this function returns the news from an RSS feed
# it receives the feed as an argument
# we use the xmlstarlet to parse the XML
get_news_RSS () {

    RSS_FEED=$1

    # get the timestamp for 24 hours ago in Unix format
    export LC_ALL=en_US.UTF-8
    TIMESTAMP=$(get_date_24_hours_rss)
    export LC_ALL=C

    # fetch the RSS feed and extract the date, title and link
    NEWS=$(curl -s "$RSS_FEED" | xmlstarlet sel -t -m "/rss/channel/item" -v "pubDate" -o "|" -v "title" -o "|" -v "link" -n)
    
    # loop through the news
    while read -r line; do
        DATE=$(echo "$line" | cut -d "|" -f 1)
        TITLE=$(echo "$line" | cut -d "|" -f 2)

        # compare the date with the timestamp
        if [ "$(compare_dates_rss "$DATE" "$TIMESTAMP")" -eq 1 ]; then
            echo "📰 $TITLE"
        fi
    done <<< "$NEWS"
}

write_news () {

    FILE_PATH=$1
    RSS_FEED=$2

    PORTAL=$(echo "$RSS_FEED" | cut -d "/" -f 3)

    # write the news to the file
    echo "📰 $PORTAL 📰" >> $FILE_PATH
    echo "" >> $FILE_PATH
    echo "$(get_news_RSS "$RSS_FEED")" >> $FILE_PATH
}

