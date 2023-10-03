# HC News
the HC version of JRMUNEWS.

![gothGirlReading](./scr/gothGirlReading.jpg)

HCNEWS is a daily news update inspired by JRMUNEWS, you can find more about JRMUNEWS on https://www.instagram.com/jrmunews/

Everyday since 2021 I've been sharing the JRMUNEWS to a group of friends of mine. it is a big text with the holidays that are celebrated that day, news, stock market, sports and etc... kinda like an RSS feed but worse. I love the JRMUNEWS but it is kinda bloated... so I've trying to build a more streamlined version tailored to my friends. The goal is to make something easily customisable but we have to focus on one thing at the time.


![Screenshot](./scr/Screenshot.png)

## Dependencies

HCNEWS requires the following dependencies:

- `xmlstarlet` you can find it [here](https://xmlstar.sourceforge.net/)
- `pup` you can find it [here](https://github.com/ericchiang/pup)
- `jq` you can find it [here](https://github.com/stedolan/jq)
- `date` you probably already have it, but if you don't you can find it [here](https://www.gnu.org/software/coreutils/manual/html_node/date-invocation.html)
- `curl` you probably already have it too, but if you don't you can find it [here](https://curl.se/)

If you want to run the Telegram bot (WIP) you can run 
```sh
  pip install -r requirements.txt
``` 

the requirements are:
- `python-telegram-bot` 
- `schedule`
- `httpx`

## Installation

### Linux
1. Install the dependencies using your package manager:
```sh
sudo apt install xmlstarlet pup jq date curl 
```
you may need to install `pup` from source, i use arch (btw) so i just installed it from the AUR.

2. Clone this repository:
```sh
git clone https://github.com/herijooj/HCnews.git
```
3. Go to the directory:
```sh
cd HCnews
```
4. Make the script executable:
```sh
chmod +x hcnews
```
5. Run the script:
```sh
./hcnews
```

## Usage
```sh
./hcnews
```
```sh
    Usage: ./hcnews.sh [options]
    Options:
      -h, --help: show the help message
      -s, --silent: the script will run silently
      -sa, --saints: show the saints of the day with the verbose description
      -n, --news: show the news with the shortened link
      -f, --file: if the output will be to a file"
```

# Contributing
If you want to contribute to this project, you can do so by opening a pull request or an issue. If you want to open a pull request, if you can, please open an issue first so we can discuss the changes you want to make.

# License
This project is licensed under the GNU General Public License - see the [LICENSE](LICENSE) file for details


# Credits
- [JRMUNEWS](https://www.instagram.com/jrmunews/) for the inspiration

you can find about the sites that i use to get the data on the script itself.

# Contact
- [Instagram | heric_camargo](https://www.instagram.com/heric_camargo/)
- [Twitter | herijooj](https://twitter.com/herijooj)

