import subprocess
import logging
from telegram import Update
from telegram.ext import ContextTypes
from config.constants import SCRIPT_PATHS
from config.keyboard import get_return_button
from utils.text_utils import escape_markdownv2

logger = logging.getLogger(__name__)

async def send_bicho(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Execute bicho script and send tips. The script handles its own caching, if applicable."""
    try:
        # The bicho.sh script handles its own caching if it implements it.
        # No cache-related flags are assumed or needed here from the Python side.
        result = subprocess.run(
            ['bash', SCRIPT_PATHS['bicho']],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=True # Will raise CalledProcessError if returncode is non-zero
        )
        
        await update.callback_query.edit_message_text(
            text=escape_markdownv2(result.stdout),
            reply_markup=get_return_button(),
            parse_mode='MarkdownV2'
        )
    except subprocess.CalledProcessError as e:
        logger.error("Bicho script execution failed: %s", str(e))
        await update.callback_query.edit_message_text(
            text="❌ Não foi possível obter as dicas do Jogo do Bicho.",
            reply_markup=get_return_button()
        )
