import logging
import os
from datetime import datetime
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import Application, CommandHandler, CallbackQueryHandler, ContextTypes, ConversationHandler, MessageHandler, filters
from config.constants import MESSAGE_TYPES, RU_LOCATIONS, SCRIPT_PATHS, TIMEZONE
from utils.schedule_utils import load_schedules, add_schedule, remove_schedule
from utils.text_utils import clean_ansi, split_message
from tokens import TOKEN
from handlers.news_handler import handle_news_menu, send_news_as_message, send_news_as_file, generate_news_file
from config.keyboard import get_main_menu, get_return_button
from handlers.weather_handler import send_weather
from handlers.exchange_handler import send_exchange
from handlers.bicho_handler import send_bicho
from handlers.horoscope_handler import send_horoscope, handle_horoscope_selection
from handlers.ru_handler import send_ru_menu, handle_ru_selection
from handlers.rss_handler import (
    handle_rss_menu, handle_set_rss, handle_url_input, handle_clear_rss,
    handle_remove_feed, handle_feed_name_input, handle_view_feed,
    send_rss_as_message, send_rss_as_file, send_specific_rss_as_message,
    send_specific_rss_as_file,  # Added the missing import
    WAITING_FOR_URL, WAITING_FOR_FEED_NAME, SELECTING_FEED
)
from handlers.schedule_handler import (
    SELECTING_ACTION, SELECTING_TYPE, SELECTING_LOCATION, SELECTING_TIME, CUSTOM_TIME, SELECTING_RSS_FEED,
    handle_schedule_menu, handle_type_selection, handle_location_selection, handle_time_selection,
    handle_custom_time, handle_remove_schedule, handle_remove_selection, handle_rss_feed_selection
)

# Configure logging
logging.basicConfig(
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    level=logging.DEBUG  # Changed from INFO to DEBUG
)
logging.getLogger('httpx').setLevel(logging.WARNING)
logger = logging.getLogger(__name__)

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Send welcome message and main menu"""
    await update.message.reply_html(
        f"Olá {update.effective_user.first_name}! 👋\n"
        f"Bem-vindo ao *HCNEWS*!\n"
        f"Selecione uma opção abaixo:",
        reply_markup=get_main_menu()
    )

async def button_callback(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Handle button presses"""
    query = update.callback_query
    await query.answer()
    
    # Don't handle schedule-related callbacks here
    if query.data.startswith("schedule"):
        return
    
    # Don't handle RSS-related callbacks that need conversation
    if query.data in ["rss_set", "rss_clear"]:
        return
    
    if query.data == "settings":
        await query.message.reply_text(
            "⚙️ Configurações ainda não implementadas.",
            reply_markup=get_return_button()
        )
        return
    
    if query.data == "news":
        await handle_news_menu(update, context)
    elif query.data == "news_message":
        await send_news_as_message(update, context)
    elif query.data == "news_file":
        await send_news_as_file(update, context)
    elif query.data == "news_force":
        # First notify the user we're updating
        await query.message.reply_text("🔄 Forçando atualização das notícias...")
        success, result = await generate_news_file(force(True))
        if success:
            # Send in the same format that was last used (file or message)
            if query.message.reply_markup.inline_keyboard[0][0].callback_data == "news_message":
                await send_news_as_message(update, context)
            else:
                await send_news_as_file(update, context)
        else:
            await query.message.reply_text(f"❌ Falha ao atualizar as notícias: {result}")
    elif query.data == "rss":
        await handle_rss_menu(update, context)
    elif query.data == "rss_message":
        await send_rss_as_message(update, context)
    elif query.data == "rss_file":
        await send_rss_as_file(update, context)
    elif query.data == "horoscope":
        await send_horoscope(update, context)
    elif query.data.startswith("horoscope_"):
        await handle_horoscope_selection(update, context, query.data)
    elif query.data == "weather":
        await send_weather(update, context)
    elif query.data == "exchange":
        await send_exchange(update, context)
    elif query.data == "bicho":
        await send_bicho(update, context)
    elif query.data == "ru":
        await send_ru_menu(update, context)
    elif query.data.startswith("ru_"):
        await handle_ru_selection(update, context, query.data)
    elif query.data == "main_menu":
        await query.message.edit_text(
            "Selecione uma opção:",
            reply_markup=get_main_menu()
        )

def main() -> None:
    """Start the bot"""
    # check if the scripts exist and are executable
    for script in SCRIPT_PATHS.values():
        if not os.path.exists(script):
            raise FileNotFoundError(f"Script {script} not found.")
        if not os.access(script, os.X_OK):
            raise PermissionError(f"Script {script} is not executable.")

    application = Application.builder().token(TOKEN).build()
    
    # Make application available globally for job creation
    from telegram.ext import ApplicationBuilder
    ApplicationBuilder.application = application
    
    # Setup existing schedule jobs
    from utils.schedule_utils import setup_jobs
    setup_jobs(application)
    
    # Add the start command handler
    application.add_handler(CommandHandler("start", start))
    
    # Add conversation handler for RSS operations
    rss_handler = ConversationHandler(
        entry_points=[
            CallbackQueryHandler(handle_set_rss, pattern="^rss_set$"),
            CallbackQueryHandler(handle_clear_rss, pattern="^rss_clear$"),
            CallbackQueryHandler(handle_remove_feed, pattern="^rss_delete_"),
            CallbackQueryHandler(handle_view_feed, pattern="^rss_view_"),
            CallbackQueryHandler(send_specific_rss_as_message, pattern="^rss_message_"),
            CallbackQueryHandler(send_specific_rss_as_file, pattern="^rss_file_"),
        ],
        states={
            WAITING_FOR_URL: [
                MessageHandler(filters.TEXT & ~filters.COMMAND, handle_url_input),
                CallbackQueryHandler(handle_rss_menu, pattern="^rss$"),
            ],
            WAITING_FOR_FEED_NAME: [
                MessageHandler(filters.TEXT & ~filters.COMMAND, handle_feed_name_input),
                CallbackQueryHandler(handle_rss_menu, pattern="^rss$"),
            ],
            SELECTING_FEED: [
                CallbackQueryHandler(handle_remove_feed, pattern="^rss_delete_"),
                CallbackQueryHandler(handle_rss_menu, pattern="^rss$"),
            ],
        },
        fallbacks=[
            CallbackQueryHandler(handle_rss_menu, pattern="^rss$"),
            CallbackQueryHandler(button_callback, pattern="^main_menu$"),
            MessageHandler(filters.COMMAND, lambda u, c: ConversationHandler.END),
        ],
        per_message=False,
        name="rss_conversation"
    )
    
    # Add conversation handler for scheduling
    schedule_handler = ConversationHandler(
        entry_points=[
            CallbackQueryHandler(handle_schedule_menu, pattern="^schedule$")
        ],
        states={
            SELECTING_ACTION: [
                CallbackQueryHandler(handle_type_selection, pattern="^schedule_add$"),
                CallbackQueryHandler(handle_remove_schedule, pattern="^schedule_remove$"),
                CallbackQueryHandler(handle_remove_selection, pattern="^schedule_remove_"),
                CallbackQueryHandler(button_callback, pattern="^main_menu$")
            ],
            SELECTING_TYPE: [
                CallbackQueryHandler(handle_location_selection, pattern="^schedule_type_"),
                CallbackQueryHandler(handle_schedule_menu, pattern="^schedule_menu$")
            ],
            SELECTING_LOCATION: [
                CallbackQueryHandler(handle_time_selection, pattern="^schedule_loc_"),
                CallbackQueryHandler(handle_schedule_menu, pattern="^schedule_menu$")
            ],
            SELECTING_RSS_FEED: [  # Add RSS feed selection state
                CallbackQueryHandler(handle_rss_feed_selection, pattern="^schedule_feed_"),
                CallbackQueryHandler(handle_schedule_menu, pattern="^schedule_menu$")
            ],
            SELECTING_TIME: [
                CallbackQueryHandler(handle_time_selection, pattern="^schedule_time_"),
                CallbackQueryHandler(handle_schedule_menu, pattern="^schedule_menu$")
            ],
            CUSTOM_TIME: [
                MessageHandler(filters.TEXT & ~filters.COMMAND, handle_custom_time),
                CallbackQueryHandler(handle_schedule_menu, pattern="^schedule_menu$"),
                CallbackQueryHandler(button_callback, pattern="^main_menu$")
            ],
        },
        fallbacks=[
            CallbackQueryHandler(handle_schedule_menu, pattern="^schedule_menu$"),
            CallbackQueryHandler(button_callback, pattern="^main_menu$"),
            MessageHandler(filters.ALL, lambda u, c: ConversationHandler.END)
        ],
        per_message=False,  # Changed from True to False
        name="schedule_conversation"  # Add a name for debugging
    )
    
    # Important: Add handlers before the general callback handler
    application.add_handler(rss_handler)
    application.add_handler(schedule_handler)
    application.add_handler(CallbackQueryHandler(button_callback))
    
    # Start the bot
    application.run_polling()

if __name__ == '__main__':
    main()
