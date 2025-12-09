from telegram import InlineKeyboardButton, InlineKeyboardMarkup
from .constants import MESSAGE_TYPES

def get_main_menu() -> InlineKeyboardMarkup:
    """Return the main menu keyboard markup"""
    keyboard = [
        [
            InlineKeyboardButton(MESSAGE_TYPES['news'], callback_data="news"),
            InlineKeyboardButton(MESSAGE_TYPES['horoscope'], callback_data="horoscope")
        ],
        [
            InlineKeyboardButton(MESSAGE_TYPES['weather'], callback_data="weather"),
            InlineKeyboardButton(MESSAGE_TYPES['exchange'], callback_data="exchange")
        ],
        [
            InlineKeyboardButton(MESSAGE_TYPES['bicho'], callback_data="bicho"),
            InlineKeyboardButton(MESSAGE_TYPES['ru'], callback_data="ru")
        ],
        [
            InlineKeyboardButton(MESSAGE_TYPES['rss'], callback_data="rss"),
            InlineKeyboardButton("⏰ Agendamentos", callback_data="schedule")
        ],
        [
            InlineKeyboardButton("⚙️ Configurações", callback_data="settings")
        ]
    ]
    return InlineKeyboardMarkup(keyboard)

def get_news_menu() -> InlineKeyboardMarkup:
    """Return the news menu keyboard markup"""
    keyboard = [
        [
            InlineKeyboardButton("📝 Ver como mensagem", callback_data="news_message"),
            InlineKeyboardButton("📎 Baixar arquivo", callback_data="news_file")
        ],
        [
            InlineKeyboardButton("🔄 Forçar atualização", callback_data="news_force"),
            InlineKeyboardButton("🔄 Atualizar e baixar", callback_data="news_regenerate")
        ],
        [
            InlineKeyboardButton("🏠 Menu Principal", callback_data="main_menu")
        ]
    ]
    return InlineKeyboardMarkup(keyboard)

def get_rss_menu() -> InlineKeyboardMarkup:
    """Return the RSS feed menu keyboard markup"""
    keyboard = [
        [
            InlineKeyboardButton("📱 Ver feed RSS", callback_data="rss_message"),
            InlineKeyboardButton("📎 Baixar feed RSS", callback_data="rss_file")
        ],
        [
            InlineKeyboardButton("🌐 Definir RSS Feed", callback_data="rss_set"),
            InlineKeyboardButton("🗑️ Limpar RSS Feed", callback_data="rss_clear")
        ],
        [InlineKeyboardButton("🏠 Menu Principal", callback_data="main_menu")]
    ]
    return InlineKeyboardMarkup(keyboard)

def get_return_button() -> InlineKeyboardMarkup:
    """Return a single button to return to main menu"""
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("🏠 Menu Principal", callback_data="main_menu")]
    ])

def get_schedule_menu() -> InlineKeyboardMarkup:
    """Return the schedule management menu keyboard"""
    keyboard = [
        [
            InlineKeyboardButton("➕ Adicionar", callback_data="schedule_add"),
            InlineKeyboardButton("➖ Remover", callback_data="schedule_remove")
        ],
        [InlineKeyboardButton("🏠 Menu Principal", callback_data="main_menu")]
    ]
    return InlineKeyboardMarkup(keyboard)
