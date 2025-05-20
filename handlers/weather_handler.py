import logging
import subprocess
from telegram import Update
from telegram.ext import ContextTypes
from config.constants import SCRIPT_PATHS
from config.keyboard import get_return_button
from utils.text_utils import clean_ansi

logger = logging.getLogger(__name__)

async def send_weather(update: Update, context: ContextTypes.DEFAULT_TYPE, city: str = "Curitiba") -> None:
    """Send weather information"""
    query = update.callback_query
    if query:
        await query.answer()
        message = query.message
    else:
        message = update.message

    # Show typing indicator
    await context.bot.send_chat_action(chat_id=update.effective_chat.id, action="typing")

    try:
        # Execute the weather script with city parameter
        logger.info(f"Getting weather for city: '{city}'")
        
        # Use default city if an empty string was passed
        if not city.strip():
            city = "Curitiba"
            logger.info(f"Using default city: {city}")
        
        # Add a status message to show we're processing
        status_msg = await message.reply_text(f"🔍 Buscando previsão do tempo para {city}...")
        
        # Construct command with explicit arguments
        # The weather.sh script now handles its own caching.
        # No cache-related flags are needed here.
        command = [SCRIPT_PATHS['weather']]
        if city:
            command.append(city)
        command.append("--telegram")
        
        logger.info(f"Running command: {' '.join(command)}")
        
        result = subprocess.run(
            command,
            capture_output=True,
            text=True,
            check=False  # Don't raise exception, handle it manually
        )
        
        # Log the output for debugging
        logger.info(f"Weather script stdout: {result.stdout[:200]}...")
        if result.stderr:
            logger.info(f"Weather script stderr: {result.stderr}")
        
        # Delete the status message
        await status_msg.delete()
        
        if result.returncode != 0:
            error_msg = clean_ansi(result.stderr) if result.stderr else "Erro desconhecido"
            # Also check stdout for error messages
            if "❌ Erro:" in result.stdout:
                error_msg = clean_ansi(result.stdout)
            await message.reply_text(
                f"{error_msg}\n\nTente outra cidade.",
                reply_markup=get_return_button()
            )
            return
            
        weather_text = clean_ansi(result.stdout)

        # Send the message using Markdown parse mode
        try:
            await message.reply_text(
                text=weather_text,
                parse_mode='Markdown', # Use Markdown as the script already formats it
                reply_markup=get_return_button()
            )
        except Exception as e:
            logger.warning(f"Failed to send as Markdown: {str(e)}. Sending without parse mode.")
            # If Markdown fails, send without any parse mode
            await message.reply_text(
                text=weather_text,
                parse_mode=None,
                reply_markup=get_return_button()
            )
            
        logger.info("Weather info sent successfully")
    except Exception as e:
        logger.error(f"Unexpected error in send_weather: {str(e)}")
        await message.reply_text(
            f"❌ Erro inesperado ao buscar previsão do tempo: {str(e)}",
            reply_markup=get_return_button()
        )
