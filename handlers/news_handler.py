import logging
import os
import subprocess
import io
from datetime import datetime
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import ContextTypes
from config.constants import SCRIPT_PATHS
from config.keyboard import get_news_menu, get_return_button
from utils.text_utils import clean_ansi, split_message

logger = logging.getLogger(__name__)

async def get_news_content_from_script(force_refresh_components: bool = False) -> tuple[bool, str]:
    """Get news content by running hcnews.sh script and capturing its stdout.
    
    Args:
        force_refresh_components: If True, passes '--force' to hcnews.sh 
                                  to refresh its internal caches.
                                  
    Returns:
        A tuple (success, content_or_error_message).
        If success is True, the second element is the news content (str).
        If success is False, the second element is an error message (str).
    """
    news_script_path = SCRIPT_PATHS.get('news')
    if not news_script_path:
        logger.error("News script path 'news' not found in SCRIPT_PATHS.")
        return False, "News script path configuration error."
    if not os.path.exists(news_script_path):
        logger.error(f"News script does not exist at configured path: {news_script_path}")
        return False, f"News script not found at path: {news_script_path}"

    command = [news_script_path, "-sa", "-s"]
    if force_refresh_components:
        command.append("--force")
        logger.info(f"Calling hcnews.sh with --force to refresh components.")
    else:
        logger.info(f"Calling hcnews.sh without --force.")
        
    try:
        process = subprocess.run(command, check=False, capture_output=True, text=True, encoding='utf-8', timeout=120)
        
        if process.returncode != 0:
            error_message = f"Script error for command '{' '.join(command)}'. Return code: {process.returncode}\nStderr: {process.stderr.strip()}\nStdout: {process.stdout.strip()}"
            logger.error(error_message)
            return False, f"Script execution failed: {process.stderr.strip() or 'Unknown script error'}"
        
        news_content = process.stdout
        if not news_content.strip():
            logger.warning(f"hcnews.sh ran successfully but produced empty output. Command: {' '.join(command)}")
            return False, "News script produced no output."
            
        logger.info(f"Successfully got news content from hcnews.sh stdout. Length: {len(news_content)}")
        return True, news_content
        
    except FileNotFoundError: 
        logger.error(f"News script '{news_script_path}' not found or not executable.")
        return False, f"News script '{news_script_path}' not found or not executable."
    except subprocess.TimeoutExpired:
        logger.error(f"Script execution timed out for command: {' '.join(command)}")
        return False, "Script execution timed out."
    except Exception as e: 
        logger.error(f"An unexpected error occurred in get_news_content_from_script: {str(e)}")
        return False, f"An unexpected error occurred: {str(e)}"

async def send_news_as_file(update: Update, context: ContextTypes.DEFAULT_TYPE, force_refresh: bool = False) -> None:
    """Send news as a text file, generated on-the-fly."""
    await update.effective_message.reply_text("⏳ Gerando e enviando arquivo de notícias...")
    
    success, news_content = await get_news_content_from_script(force_refresh_components=force_refresh)
    
    if not success:
        await update.effective_message.reply_text(
            f"❌ Não foi possível gerar o arquivo de notícias.\nErro: {news_content}",
            reply_markup=get_return_button()
        )
        return
        
    date_str = datetime.now().strftime("%Y%m%d")
    try:
        file_content_bytes = news_content.encode('utf-8')
        in_memory_file = io.BytesIO(file_content_bytes)
        in_memory_file.name = f"HCNEWS{date_str}.txt" 
        
        await context.bot.send_document(
            chat_id=update.effective_chat.id,
            document=in_memory_file,
            filename=in_memory_file.name,
            caption="📰 Notícias do dia",
            reply_markup=get_return_button()
        )
    except Exception as e:
        logger.error(f"Error sending news as file: {str(e)}")
        await update.effective_message.reply_text(
            f"❌ Ocorreu um erro ao enviar o arquivo de notícias.\nErro: {str(e)}",
            reply_markup=get_return_button()
        )

async def send_news_as_message(update: Update, context: ContextTypes.DEFAULT_TYPE, force_refresh: bool = False) -> None:
    """Send news as a message, splitting if necessary, generated on-the-fly."""
    await update.effective_message.reply_text("⏳ Gerando notícias...")

    success, news_content_raw = await get_news_content_from_script(force_refresh_components=force_refresh)
    
    if not success:
        await update.effective_message.reply_text(
            f"❌ Não foi possível gerar as notícias.\nErro: {news_content_raw}",
            reply_markup=get_return_button()
        )
        return
        
    content_for_message = "📰 Notícias do dia\n\n" + clean_ansi(news_content_raw.strip())
        
    messages = split_message(content_for_message)
    try:
        for i, msg_part in enumerate(messages):
            if i == len(messages) - 1:
                await update.effective_message.reply_text(msg_part, reply_markup=get_return_button())
            else:
                await update.effective_message.reply_text(msg_part)
    except Exception as e:
        logger.error(f"Error sending news as message parts: {str(e)}")
        await update.effective_message.reply_text(
            f"❌ Ocorreu um erro ao enviar as notícias.\nErro: {str(e)}",
            reply_markup=get_return_button()
        )

async def handle_news_menu(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Handle the news menu callback queries."""
    query = update.callback_query
    await query.answer()

    if query.data == "news_regenerate":
        await query.message.reply_text("🔄 Forçando atualização e regeneração dos componentes de notícias...")
        success, result_content = await get_news_content_from_script(force_refresh_components=True)
        if success:
            await query.message.edit_text(
                "✅ Componentes de notícias foram atualizados! Escolha uma opção:",
                reply_markup=get_news_menu()
            )
        else:
            await query.message.edit_text(
                f"❌ Não foi possível atualizar os componentes de notícias.\nErro: {result_content}",
                reply_markup=get_news_menu()
            )
        return

    await query.message.edit_text(
        "📰 Notícias\n\nEscolha como deseja receber as notícias ou force uma atualização dos componentes:",
        reply_markup=get_news_menu()
    )
