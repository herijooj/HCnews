import os
from typing import Dict
import pytz

# Get the project root directory
PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

TIMEZONE = pytz.timezone('America/Sao_Paulo')

MESSAGE_TYPES = {
    'news': '📰 Notícias',
    'horoscope': '🔮 Horóscopo',
    'weather': '🌤️ Previsão do Tempo',
    'exchange': '💱 Cotações',
    'bicho': '🎲 Jogo do Bicho',
    'ru': '🍽️ Cardápio RU'
}

RU_LOCATIONS = {
    'politecnico': 'Politécnico',
    'agrarias': 'Agrárias',
    'botanico': 'Jardim Botânico',
    'central': 'Central',
    'toledo': 'Toledo',
    'mirassol': 'Mirassol',
    'jandaia': 'Jandaia do Sul',
    'palotina': 'Palotina',
    'cem': 'CEM',
    'matinhos': 'Matinhos'
}

SCRIPT_PATHS = {
    'news': os.path.join(PROJECT_ROOT, 'hcnews.sh'),
    'horoscope': os.path.join(PROJECT_ROOT, 'scripts', 'horoscopo.sh'),
    'weather': os.path.join(PROJECT_ROOT, 'scripts', 'weather.sh'),
    'exchange': os.path.join(PROJECT_ROOT, 'scripts', 'exchange.sh'),
    'bicho': os.path.join(PROJECT_ROOT, 'scripts', 'bicho.sh'),
    'ru': os.path.join(PROJECT_ROOT, 'scripts', 'UFPR', 'ru.sh')
}

MAX_MESSAGE_LENGTH = 4000
