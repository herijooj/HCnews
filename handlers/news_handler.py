import logging
import os
import subprocess
from datetime import datetime
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import ContextTypes
from config.constants import SCRIPT_PATHS
from config.keyboard import get_news_menu, get_return_button
from utils.text_utils import clean_ansi, split_message
from utils.rss_utils import get_rss_feed

logger = logging.getLogger(__name__)

async def generate_news_file(force: bool = False) -> tuple[bool, str]:
    """Generate news file using hcnews.sh script"""
    date_str = datetime.now().strftime("%Y%m%d")
    news_file = f"data/news/{date_str}.news"
    
    if not force and os.path.exists(news_file):
        return True, news_file
        
    try:
        subprocess.run(
            [SCRIPT_PATHS['news'], "-f", "-sa", "-s"],
            check=True
        )
        
        # Check if file was created
        if os.path.exists(news_file):
            return True, news_file
        return False, "News file was not created"
        
    except subprocess.CalledProcessError as e:
        return False, f"Script error: {str(e)}"

async def send_news_as_file(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Send news as a text file"""
    success, result = await generate_news_file(force=False)
    if not success:
        await update.effective_message.reply_text(
            "❌ Não foi possível gerar o arquivo de notícias.",
            reply_markup=get_return_button()
        )
        return
        
    date_str = datetime.now().strftime("%Y%m%d")
    with open(result, 'rb') as f:
        await context.bot.send_document(
            chat_id=update.effective_chat.id,
            document=f,
            filename=f"HCNEWS{date_str}.txt",
            caption="📰 Notícias do dia",
            reply_markup=get_return_button()
        )

async def send_news_as_message(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Send news as a message, splitting if necessary"""
    success, result = await generate_news_file(force=False)
    if not success:
        await update.effective_message.reply_text(
            "❌ Não foi possível gerar as notícias.",
            reply_markup=get_return_button()
        )
        return
        
    with open(result, 'r', encoding='utf-8') as f:
        content = "📰 Notícias do dia\n\n" + f.read()
        
    messages = split_message(content)
    # Send all messages except the last one
    for msg in messages[:-1]:
        await update.effective_message.reply_text(msg)
    # Send the last message with the return button
    await update.effective_message.reply_text(
        messages[-1],
        reply_markup=get_return_button()
    )

async def handle_news_menu(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Handle the news menu"""
    query = update.callback_query
    await query.answer()
    
    await query.message.edit_text(
        "📰 Notícias\n\nEscolha uma opção:",
        reply_markup=get_news_menu()
    )
