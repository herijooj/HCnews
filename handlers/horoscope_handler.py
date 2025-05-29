import os
import subprocess
import logging
from datetime import datetime
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import ContextTypes
from config.constants import SCRIPT_PATHS, PROJECT_ROOT
from config.keyboard import get_return_button
from utils.text_utils import clean_ansi, split_message

logger = logging.getLogger(__name__)

def generate_horoscope(force: bool = False) -> tuple[bool, str]:
    """Generate horoscope using the script and return content."""
    logger.debug(f"generate_horoscope called with force: {force!r}")
    
    command = ["bash", SCRIPT_PATHS['horoscope']]
    if force:
        command.append("--force")
        
    try:
        result = subprocess.run(
            command, 
            capture_output=True, 
            text=True, 
            check=True
        )
        content = result.stdout
        
        return True, content
            
    except subprocess.CalledProcessError as e:
        logger.error(f"Failed to generate horoscope: {e}\nStderr: {e.stderr}")
        return False, f"Erro ao gerar horóscopo: {e.stderr if e.stderr else 'Erro desconhecido'}"
    except Exception as e:
        logger.error(f"Error running horoscope script: {e}")
        return False, "Erro ao executar script do horóscopo"

async def send_horoscope(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Generate and send horoscope for all signs"""
    query = update.callback_query
    await query.answer()
    
    success, content = generate_horoscope()
        
    if not success:
        logger.warning(f"Horoscope generation failed: {content}")
        await query.message.edit_text(
            f"❌ {content}",
            reply_markup=get_return_button()
        )
        return
    
    # Log content length for debugging
    logger.debug(f"Generated horoscope content length: {len(content)} chars")
    
    # Clean ANSI codes and prepare message
    clean_content = clean_ansi(content.strip())
    message = clean_content
    
    # Split message into multiple parts if too long
    messages = split_message(message)
    
    try:
        # Send first message by editing the existing one
        await query.message.edit_text(
            messages[0],
            reply_markup=get_return_button() if len(messages) == 1 else None,
            parse_mode='Markdown'
        )
        
        # Send remaining messages as new messages
        for i, msg_part in enumerate(messages[1:], 1):
            await query.message.reply_text(
                msg_part,
                reply_markup=get_return_button() if i == len(messages) - 1 else None,
                parse_mode='Markdown'
            )
    except Exception as e:
        logger.error(f"Error sending horoscope messages: {str(e)}")
        await query.message.reply_text(
            f"❌ Erro ao enviar horóscopo: {str(e)}",
            reply_markup=get_return_button()
        )
