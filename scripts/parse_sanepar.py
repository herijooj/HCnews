import sys
import json
from html.parser import HTMLParser

class SaneparParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.in_next_data_script = False
        self.json_data = None

    def handle_starttag(self, tag, attrs):
        if tag == 'script':
            attrs_dict = dict(attrs)
            if attrs_dict.get('id') == '__NEXT_DATA__':
                self.in_next_data_script = True

    def handle_data(self, data):
        if self.in_next_data_script:
            self.json_data = data
            self.in_next_data_script = False

def main():
    html_content = sys.stdin.read()

    parser = SaneparParser()
    parser.feed(html_content)

    if parser.json_data:
        try:
            data = json.loads(parser.json_data)
            page_props = data['props']['pageProps']
            reservoirs = page_props['layout']['settings']['custom.reservoirLevels']['reservoirs']
            update_date = page_props['layout']['settings']['custom.reservoirLevels']['date']

            # Print each value on a new line for easy parsing in bash
            print(reservoirs[0]['reservoirLevel']) # Iraí
            print(reservoirs[1]['reservoirLevel']) # Passaúna
            print(reservoirs[2]['reservoirLevel']) # Piraquara 1
            print(reservoirs[3]['reservoirLevel']) # Piraquara 2
            print(reservoirs[4]['reservoirLevel']) # Total SAIC
            print(update_date)

        except (KeyError, IndexError, json.JSONDecodeError) as e:
            # Output nothing on error so the bash script can handle it
            pass

if __name__ == "__main__":
    main()
