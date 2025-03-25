import os
import subprocess
import logging
from datetime import datetime
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import ContextTypes
from config.constants import SCRIPT_PATHS, PROJECT_ROOT, RU_LOCATIONS
from config.keyboard import get_return_button
from utils.text_utils import clean_ansi

logger = logging.getLogger(__name__)

def get_ru_keyboard() -> InlineKeyboardMarkup:
    """Create a 2-column keyboard with RU locations"""
    keyboard = []
    row = []
    for location_id, location_name in RU_LOCATIONS.items():
        row.append(InlineKeyboardButton(
            f"🍽️ {location_name}",
            callback_data=f"ru_{location_id}"
        ))
        if len(row) == 2:
            keyboard.append(row)
            row = []
    
    # Add any remaining buttons
    if row:
        keyboard.append(row)
    
    # Add Main Menu button
    keyboard.append([InlineKeyboardButton("🏠 Menu Principal", callback_data="main_menu")])
    return InlineKeyboardMarkup(keyboard)

def generate_ru_menu(location: str, force: bool = False, today_only: bool = False) -> tuple[bool, str]:
    """Generate RU menu for specified location"""
    logger.debug(f"Generating RU menu for location: {location}, today_only: {today_only}")
    
    data_dir = os.path.join(PROJECT_ROOT, "data", "news")
    os.makedirs(data_dir, exist_ok=True)
    
    today = datetime.now()
    cache_suffix = "_today" if today_only else "_full"
    filename = os.path.join(data_dir, f"{today.strftime('%Y%m%d')}_{location}{cache_suffix}.ru")
    
    if force or not os.path.exists(filename):
        logger.debug(f"Generating new RU menu file: {filename}")
        try:
            cmd = [SCRIPT_PATHS['ru'], '-r', location]
            if today_only:
                cmd.append('-t')
                
            result = subprocess.run(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                check=True
            )
            with open(filename, 'w', encoding='utf-8') as f:
                f.write(result.stdout)
        except subprocess.CalledProcessError as e:
            logger.error(f"Failed to generate RU menu: {e}")
            return False, "Erro ao gerar cardápio"
    
    try:
        with open(filename, 'r', encoding='utf-8') as f:
            content = f.read()
        return True, content
    except Exception as e:
        logger.error(f"Error reading RU menu: {e}")
        return False, "Erro ao ler cardápio"

async def send_ru_menu(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Show RU location selection menu"""
    await update.callback_query.edit_message_text(
        "🍽️ Escolha um Restaurante Universitário:",
        reply_markup=get_ru_keyboard()
    )

async def handle_ru_selection(update: Update, context: ContextTypes.DEFAULT_TYPE, callback_data: str) -> None:
    """Handle RU location selection"""
    query = update.callback_query
    await query.answer()
    
    location = callback_data.replace("ru_", "")
    logger.debug(f"RU selection: {location}")
    
    # Don't use today_only flag for manual requests
    success, content = generate_ru_menu(location, force=False, today_only=False)
    if not success:
        await query.message.edit_text(
            f"❌ {content}",
            reply_markup=get_return_button()
        )
        return
    
    location_name = RU_LOCATIONS.get(location, location)
    message = f"{content}"
    
    # Truncate if too long
    if len(message) > 4096:
        message = message[:4093] + "..."
    
    await query.message.edit_text(
        message,
        reply_markup=get_return_button(),
        parse_mode='Markdown'
    )
