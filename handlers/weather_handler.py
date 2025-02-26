import subprocess
import logging
from telegram import Update
from telegram.ext import ContextTypes
from config.constants import SCRIPT_PATHS
from config.keyboard import get_return_button
from utils.text_utils import clean_ansi  # Add this import

logger = logging.getLogger(__name__)

async def send_weather(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Execute weather script and send forecast"""
    try:
        result = subprocess.run(
            ['bash', SCRIPT_PATHS['weather']],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )
        
        if result.returncode != 0:
            logger.error("Failed to get weather info: %s", result.stderr)
            raise subprocess.CalledProcessError(result.returncode, SCRIPT_PATHS['weather'])
        
        # Clean ANSI escape codes from the output
        clean_output = clean_ansi(result.stdout)
        logger.debug(f"Cleaned weather output: {clean_output}")
        
        await update.callback_query.edit_message_text(
            text=clean_output,
            reply_markup=get_return_button(),
            parse_mode='html'
        )
    except subprocess.CalledProcessError as e:
        logger.error("Weather script execution failed: %s", str(e))
        await update.callback_query.edit_message_text(
            text="❌ Não foi possível obter a previsão do tempo.",
            reply_markup=get_return_button()
        )
