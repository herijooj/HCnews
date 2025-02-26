import os
import subprocess
import logging
from datetime import datetime
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import ContextTypes
from config.constants import SCRIPT_PATHS, PROJECT_ROOT
from config.keyboard import get_return_button

logger = logging.getLogger(__name__)

ZODIAC_SIGNS = [
    "♈ Áries", "♉ Touro", "♊ Gêmeos",
    "♋ Câncer", "♌ Leão", "♍ Virgem",
    "♎ Libra", "♏ Escorpião", "♐ Sagitário",
    "♑ Capricórnio", "♒ Aquário", "♓ Peixes"
]

SIGN_TO_CRUDE = {
    "♈ Áries": "aries",
    "♉ Touro": "touro",
    "♊ Gêmeos": "gemeos",
    "♋ Câncer": "cancer",
    "♌ Leão": "leao",
    "♍ Virgem": "virgem",
    "♎ Libra": "libra",
    "♏ Escorpião": "escorpiao",
    "♐ Sagitário": "sagitario",
    "♑ Capricórnio": "capricornio",
    "♒ Aquário": "aquario",
    "♓ Peixes": "peixes"
}

def get_zodiac_keyboard() -> InlineKeyboardMarkup:
    """Create a 3-column keyboard with zodiac signs"""
    keyboard = []
    row = []
    for i, sign in enumerate(ZODIAC_SIGNS, 1):
        row.append(InlineKeyboardButton(sign.title(), callback_data=f"horoscope_{sign}"))
        if i % 3 == 0:
            keyboard.append(row)
            row = []
    
    # Add "All Signs" and "Main Menu" buttons
    keyboard.append([
        InlineKeyboardButton("🔮 Todos os Signos", callback_data="horoscope_all"),
        InlineKeyboardButton("🏠 Menu Principal", callback_data="main_menu")
    ])
    return InlineKeyboardMarkup(keyboard)

def generate_horoscope(sign: str = None) -> tuple[bool, str]:
    """Generate horoscope using the script and return content."""
    logger.debug(f"generate_horoscope called with sign: {sign!r}")
    
    data_dir = os.path.join(PROJECT_ROOT, "data", "news")
    os.makedirs(data_dir, exist_ok=True)
    
    today = datetime.now()
    filename = os.path.join(data_dir, f"{today.strftime('%Y%m%d')}.hrcp")
    
    # Generate file if it doesn't exist
    if not os.path.exists(filename):
        logger.debug(f"Horoscope file {filename} does not exist, generating...")
        try:
            subprocess.run([SCRIPT_PATHS['horoscope'], "-s"], check=True)
        except subprocess.CalledProcessError as e:
            logger.error(f"Failed to generate horoscope: {e}")
            return False, "Erro ao gerar horóscopo"
    
    try:
        with open(filename, 'r', encoding='utf-8') as f:
            content = f.read()
            
        if not sign:  # Return full content
            return True, content
            
        # Convert fancy sign name to crude version
        crude_name = SIGN_TO_CRUDE.get(sign)
        if not crude_name:
            logger.error(f"Unknown sign format: {sign}")
            return False, f"Formato de signo desconhecido: {sign}"
            
        logger.debug(f"Converting {sign!r} to crude name: {crude_name!r}")
        
        # Find specific sign's horoscope
        lines = content.split('\n')
        for i, line in enumerate(lines):
            logger.debug(f"Checking line {i}: {line[:50]}...")
            if f"📌 {crude_name}" in line.lower():
                logger.debug(f"Found match at line {i}")
                return True, f"{lines[i-1]}\n{lines[i]}"
                
        logger.warning(f"Sign {crude_name!r} not found in horoscope content")
        return False, f"Horóscopo para {sign} não encontrado"
            
    except Exception as e:
        logger.error(f"Error reading horoscope: {e}")
        return False, "Erro ao ler horóscopo"

async def send_horoscope(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Show zodiac sign selection menu"""
    await update.callback_query.edit_message_text(
        "🔮 Escolha um signo:",
        reply_markup=get_zodiac_keyboard()
    )

async def handle_horoscope_selection(update: Update, context: ContextTypes.DEFAULT_TYPE, callback_data: str) -> None:
    """Handle zodiac sign selection"""
    query = update.callback_query
    await query.answer()
    
    selected = callback_data.replace("horoscope_", "")
    logger.debug(f"Horoscope selection callback_data: {callback_data!r}, selected: {selected!r}")
    
    if selected == "all":
        success, content = generate_horoscope()
    else:
        success, content = generate_horoscope(selected)
        
    if not success:
        logger.warning(f"Horoscope generation failed for {selected!r}: {content}")
        await query.message.edit_text(
            f"❌ {content}",
            reply_markup=get_return_button()
        )
        return
    
    # Log content length for debugging
    logger.debug(f"Generated horoscope content length: {len(content)} chars")
    message = "🔮 *Horóscopo do Dia* 🔮\n\n" + content
    
    # Truncate if too long
    if len(message) > 4096:
        logger.warning(f"Truncating message from {len(message)} to 4096 chars")
        message = message[:4093] + "..."
        
    await query.message.edit_text(
        message,
        reply_markup=get_return_button(),
        parse_mode='Markdown'
    )
