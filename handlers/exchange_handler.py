import subprocess
import logging
from telegram import Update
from telegram.ext import ContextTypes
from config.constants import SCRIPT_PATHS
from config.keyboard import get_return_button

logger = logging.getLogger(__name__)

async def send_exchange(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Execute exchange script and send rates"""
    try:
        result = subprocess.run(
            ['bash', SCRIPT_PATHS['exchange']],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )
        
        if result.returncode != 0:
            logger.error("Failed to get exchange rates: %s", result.stderr)
            raise subprocess.CalledProcessError(result.returncode, SCRIPT_PATHS['exchange'])
        
        await update.callback_query.edit_message_text(
            text=result.stdout,
            reply_markup=get_return_button(),
            parse_mode='Markdown'
        )
    except subprocess.CalledProcessError as e:
        logger.error("Exchange script execution failed: %s", str(e))
        await update.callback_query.edit_message_text(
            text="❌ Não foi possível obter as cotações.",
            reply_markup=get_return_button()
        )
