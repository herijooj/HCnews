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
    """Generate RU menu for specified location using ru.sh, which handles its own caching."""
    logger.debug(f"Generating RU menu for location: {location}, force: {force}, today_only: {today_only}")

    command = [SCRIPT_PATHS['ru'], '-r', location]
    if force:
        command.append('--force')
    if today_only:
        command.append('-t')
            
    try:
        result = subprocess.run(
            command,
            capture_output=True, 
            text=True, 
            check=True
        )
        # The ru.sh script now directly outputs the content.
        # No need to write to or read from a file in Python.
        content = clean_ansi(result.stdout) # Clean ANSI codes if any
        return True, content
    except subprocess.CalledProcessError as e:
        logger.error(f"Failed to generate RU menu: {e}\nStderr: {e.stderr}")
        return False, f"Erro ao gerar cardápio: {clean_ansi(e.stderr) if e.stderr else 'Erro desconhecido'}"
    except Exception as e:
        logger.error(f"Error running RU script: {e}")
        return False, "Erro ao executar script do RU"

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
