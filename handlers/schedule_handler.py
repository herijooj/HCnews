import logging
from datetime import datetime, time
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import ContextTypes, ConversationHandler, JobQueue
from config.constants import MESSAGE_TYPES, RU_LOCATIONS, TIMEZONE
from config.keyboard import get_return_button, get_schedule_menu
from utils.schedule_utils import load_schedules, add_schedule, remove_schedule, save_schedules  # Added save_schedules
from utils.rss_utils import get_rss_feeds
from utils.text_utils import escape_markdownv2

logger = logging.getLogger(__name__)

# Conversation states
SELECTING_ACTION = 0
SELECTING_TYPE = 1
SELECTING_LOCATION = 2
SELECTING_TIME = 3
CUSTOM_TIME = 4
SELECTING_RSS_FEED = 5
ENTERING_CITY = 6  # New state for entering city name

# Predefined times
PRESET_TIMES = ["06:00", "07:00", "08:00", "10:00", "11:00", "12:00", "16:00", "17:00", "18:00", "Custom"]

# Predefined cities for weather
DEFAULT_CITIES = ["Curitiba", "São Paulo", "Rio de Janeiro", "Cuiabá", "Recife", "Custom"]

def get_type_keyboard() -> InlineKeyboardMarkup:
    """Create message type selection keyboard"""
    keyboard = []
    row = []
    
    # Add RSS to MESSAGE_TYPES for display
    message_types = MESSAGE_TYPES.copy()
    message_types['rss'] = '🌐 RSS Feed'
    
    for type_id, type_name in message_types.items():
        row.append(InlineKeyboardButton(type_name, callback_data=f"schedule_type_{type_id}"))
        if len(row) == 2:
            keyboard.append(row)
            row = []
    if row:
        keyboard.append(row)
    keyboard.append([InlineKeyboardButton("↩️ Voltar", callback_data="schedule_menu")])
    return InlineKeyboardMarkup(keyboard)

def get_time_keyboard() -> InlineKeyboardMarkup:
    """Create time selection keyboard"""
    keyboard = []
    row = []
    for time_str in PRESET_TIMES:
        row.append(InlineKeyboardButton(
            time_str,
            callback_data=f"schedule_time_{'custom' if time_str == 'Custom' else time_str}"
        ))
        if len(row) == 2:
            keyboard.append(row)
            row = []
    if row:
        keyboard.append(row)
    keyboard.append([InlineKeyboardButton("↩️ Voltar", callback_data="schedule_menu")])
    return InlineKeyboardMarkup(keyboard)

def get_city_keyboard() -> InlineKeyboardMarkup:
    """Create city selection keyboard for weather"""
    keyboard = []
    row = []
    for city in DEFAULT_CITIES:
        row.append(InlineKeyboardButton(
            city,
            callback_data=f"schedule_city_{'custom' if city == 'Custom' else city}"
        ))
        if len(row) == 2:
            keyboard.append(row)
            row = []
    if row:
        keyboard.append(row)
    keyboard.append([InlineKeyboardButton("↩️ Voltar", callback_data="schedule_menu")])
    return InlineKeyboardMarkup(keyboard)

def format_schedules(chat_id: int) -> str:
    """Format user's schedules for display"""
    schedules = load_schedules().get(str(chat_id), [])
    if not schedules:
        return "Nenhum agendamento encontrado."
    
    formatted = "📅 *Seus agendamentos:*\n\n"
    for i, schedule in enumerate(schedules, 1):
        msg_type = MESSAGE_TYPES[schedule['type']]
        
        if 'location' in schedule:
            location_str = ""
            if schedule['type'] == 'ru':
                location_str = f" ({RU_LOCATIONS[schedule['location']]})"
            elif schedule['type'] == 'weather':
                location_str = f" ({schedule['location']})"
            elif schedule['type'] == 'rss':
                location_str = f" ({schedule['location']})"
            formatted += f"{i}. {schedule['time']} - {msg_type}{location_str}\n"
        else:
            formatted += f"{i}. {schedule['time']} - {msg_type}\n"
    
    return formatted

async def handle_schedule_menu(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    """Show schedule management menu"""
    query = update.callback_query
    chat_id = update.effective_chat.id
    
    schedules_text = format_schedules(chat_id)
    try:
        await query.message.edit_text(
            f"{escape_markdownv2(schedules_text)}\n\nEscolha uma opção:",
            reply_markup=get_schedule_menu(),
            parse_mode='MarkdownV2'
        )
    except Exception as e:
        logger.info(f"Could not edit message for schedule menu, sending new: {str(e)}")
        await query.message.reply_text(
            f"{escape_markdownv2(schedules_text)}\n\nEscolha uma opção:",
            reply_markup=get_schedule_menu(),
            parse_mode='MarkdownV2'
        )
    return SELECTING_ACTION

async def handle_type_selection(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    """Handle message type selection"""
    query = update.callback_query
    await query.answer()
    
    try:
        await query.message.edit_text(
            "📝 Selecione o tipo de mensagem:",
            reply_markup=get_type_keyboard()
        )
    except Exception as e:
        logger.info(f"Could not edit message for type selection, sending new: {str(e)}")
        await query.message.reply_text(
            "📝 Selecione o tipo de mensagem:",
            reply_markup=get_type_keyboard()
        )
    return SELECTING_TYPE

async def handle_location_selection(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    """Handle RU location selection if needed"""
    query = update.callback_query
    msg_type = query.data.replace("schedule_type_", "")
    context.user_data['schedule_type'] = msg_type
    
    if msg_type == 'ru':
        # Show RU location selection
        keyboard = []
        for loc_id, loc_name in RU_LOCATIONS.items():
            keyboard.append([InlineKeyboardButton(
                f"🍽️ {loc_name}",
                callback_data=f"schedule_loc_{loc_id}"
            )])
        keyboard.append([InlineKeyboardButton("↩️ Voltar", callback_data="schedule_menu")])
        try:
            await query.message.edit_text(
                "📍 Selecione o local:",
                reply_markup=InlineKeyboardMarkup(keyboard)
            )
        except Exception as e:
            logger.info(f"Could not edit message for location selection, sending new: {str(e)}")
            await query.message.reply_text(
                "📍 Selecione o local:",
                reply_markup=InlineKeyboardMarkup(keyboard)
            )
        return SELECTING_LOCATION
    elif msg_type == 'rss':
        # Show RSS feed selection
        chat_id = update.effective_chat.id
        feeds = get_rss_feeds(chat_id)
        
        if not feeds:
            try:
                await query.message.edit_text(
                    "❌ Nenhum feed RSS configurado. Configure um RSS primeiro.",
                    reply_markup=get_schedule_menu()
                )
            except Exception as e:
                logger.info(f"Could not edit message for RSS warning, sending new: {str(e)}")
                await query.message.reply_text(
                    "❌ Nenhum feed RSS configurado. Configure um RSS primeiro.",
                    reply_markup=get_schedule_menu()
                )
            return ConversationHandler.END
            
        keyboard = []
        for name in feeds.keys():
            keyboard.append([InlineKeyboardButton(
                f"📲 {name}",
                callback_data=f"schedule_feed_{name}"
            )])
        keyboard.append([InlineKeyboardButton("↩️ Voltar", callback_data="schedule_menu")])
        
        try:
            await query.message.edit_text(
                "📱 Selecione o feed RSS:",
                reply_markup=InlineKeyboardMarkup(keyboard)
            )
        except Exception as e:
            logger.info(f"Could not edit message for RSS feed selection, sending new: {str(e)}")
            await query.message.reply_text(
                "📱 Selecione o feed RSS:",
                reply_markup=InlineKeyboardMarkup(keyboard)
            )
        return SELECTING_RSS_FEED
    elif msg_type == 'weather':
        # Show city selection for weather
        try:
            await query.message.edit_text(
                "🌆 Selecione a cidade para previsão do tempo:",
                reply_markup=get_city_keyboard()
            )
        except Exception as e:
            logger.info(f"Could not edit message for city selection, sending new: {str(e)}")
            await query.message.reply_text(
                "🌆 Selecione a cidade para previsão do tempo:",
                reply_markup=get_city_keyboard()
            )
        return SELECTING_LOCATION
    
    # Skip location/feed selection for other types
    try:
        await query.message.edit_text(
            "🕒 Selecione o horário:",
            reply_markup=get_time_keyboard()
        )
    except Exception as e:
        logger.info(f"Could not edit message for time selection, sending new: {str(e)}")
        await query.message.reply_text(
            "🕒 Selecione o horário:",
            reply_markup=get_time_keyboard()
        )
    return SELECTING_TIME

async def handle_rss_feed_selection(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    """Handle RSS feed selection for scheduling"""
    query = update.callback_query
    feed_name = query.data.replace("schedule_feed_", "")
    
    # Store the selected feed name
    context.user_data['schedule_feed'] = feed_name
    
    # Show time selection
    try:
        await query.message.edit_text(
            "🕒 Selecione o horário:",
            reply_markup=get_time_keyboard()
        )
    except Exception as e:
        logger.info(f"Could not edit message for time selection after RSS, sending new: {str(e)}")
        await query.message.reply_text(
            "🕒 Selecione o horário:",
            reply_markup=get_time_keyboard()
        )
    return SELECTING_TIME

async def handle_time_selection(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    """Handle time selection"""
    query = update.callback_query
    
    if query.data.startswith("schedule_loc_"):
        # Store location selection for RU
        location = query.data.replace("schedule_loc_", "")
        context.user_data['schedule_location'] = location
        
        # Show time selection
        try:
            await query.message.edit_text(
                "🕒 Selecione o horário:",
                reply_markup=get_time_keyboard()
            )
        except Exception as e:
            logger.info(f"Could not edit message for time selection after location, sending new: {str(e)}")
            await query.message.reply_text(
                "🕒 Selecione o horário:",
                reply_markup=get_time_keyboard()
            )
        return SELECTING_TIME
    elif query.data.startswith("schedule_city_"):
        # Handle city selection for weather
        city = query.data.replace("schedule_city_", "")
        
        if city == "custom":
            # Prompt for custom city input
            try:
                await query.message.edit_text(
                    "🌆 Digite o nome da cidade:",
                    reply_markup=InlineKeyboardMarkup([[
                        InlineKeyboardButton("↩️ Voltar", callback_data="schedule_menu")
                    ]])
                )
            except Exception as e:
                logger.info(f"Could not edit message for custom city input, sending new: {str(e)}")
                await query.message.reply_text(
                    "🌆 Digite o nome da cidade:",
                    reply_markup=InlineKeyboardMarkup([[
                        InlineKeyboardButton("↩️ Voltar", callback_data="schedule_menu")
                    ]])
                )
            return ENTERING_CITY
        
        # Store selected city
        context.user_data['schedule_location'] = city
        
        # Show time selection
        try:
            await query.message.edit_text(
                "🕒 Selecione o horário:",
                reply_markup=get_time_keyboard()
            )
        except Exception as e:
            logger.info(f"Could not edit message for time selection after city, sending new: {str(e)}")
            await query.message.reply_text(
                "🕒 Selecione o horário:",
                reply_markup=get_time_keyboard()
            )
        return SELECTING_TIME
    
    data = query.data.replace("schedule_time_", "")
    
    if data == "custom":
        try:
            await query.message.edit_text(
                "⌚ Digite o horário no formato HH:MM (ex: 09:30):",
                reply_markup=InlineKeyboardMarkup([[
                    InlineKeyboardButton("↩️ Voltar", callback_data="schedule_menu")
                ]])
            )
        except Exception as e:
            logger.info(f"Could not edit message for custom time input, sending new: {str(e)}")
            await query.message.reply_text(
                "⌚ Digite o horário no formato HH:MM (ex: 09:30):",
                reply_markup=InlineKeyboardMarkup([[
                    InlineKeyboardButton("↩️ Voltar", callback_data="schedule_menu")
                ]])
            )
        return CUSTOM_TIME
    
    # Add schedule with selected time
    if context.user_data['schedule_type'] == 'rss' and 'schedule_feed' in context.user_data:
        # For RSS feeds, add the feed name to the location field
        success = add_schedule(
            update.effective_chat.id,
            data,
            context.user_data['schedule_type'],
            context.user_data.get('schedule_feed')
        )
    else:
        success = add_schedule(
            update.effective_chat.id,
            data,
            context.user_data['schedule_type'],
            context.user_data.get('schedule_location')
        )
    
    if success:
        try:
            await query.message.edit_text(
                f"✅ Agendamento adicionado para {data}!",
                reply_markup=get_return_button()
            )
        except Exception as e:
            logger.info(f"Could not edit message for schedule success, sending new: {str(e)}")
            await query.message.reply_text(
                f"✅ Agendamento adicionado para {data}!",
                reply_markup=get_return_button()
            )
    else:
        try:
            await query.message.edit_text(
                "❌ Erro ao adicionar agendamento.",
                reply_markup=get_return_button()
            )
        except Exception as e:
            logger.info(f"Could not edit message for schedule error, sending new: {str(e)}")
            await query.message.reply_text(
                "❌ Erro ao adicionar agendamento.",
                reply_markup=get_return_button()
            )
    
    context.user_data.clear()
    return ConversationHandler.END

async def handle_custom_time(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    """Handle custom time input"""
    try:
        time_str = update.message.text.strip()
        # Validate format
        datetime.strptime(time_str, "%H:%M")
        
        success = add_schedule(
            update.effective_chat.id,
            time_str,
            context.user_data['schedule_type'],
            context.user_data.get('schedule_location')
        )
        
        if success:
            await update.message.reply_text(
                f"✅ Agendamento adicionado para {time_str}!",
                reply_markup=get_return_button()
            )
        else:
            await update.message.reply_text(
                "❌ Erro ao adicionar agendamento.",
                reply_markup=get_return_button()
            )
    except ValueError:
        await update.message.reply_text(
            "⚠️ Formato inválido. Use HH:MM (ex: 09:30)",
            reply_markup=get_return_button()
        )
    
    context.user_data.clear()
    return ConversationHandler.END

async def handle_custom_city(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    """Handle custom city input for weather"""
    city = update.message.text.strip()
    
    # Store the city
    context.user_data['schedule_location'] = city
    
    # Show time selection
    await update.message.reply_text(
        "🕒 Selecione o horário:",
        reply_markup=get_time_keyboard()
    )
    return SELECTING_TIME

async def handle_remove_schedule(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    """Handle schedule removal"""
    query = update.callback_query
    await query.answer()
    
    chat_id = update.effective_chat.id
    schedules = load_schedules().get(str(chat_id), [])
    keyboard = []
    
    if not schedules:
        try:
            await query.message.edit_text(
                "Nenhum agendamento para remover.",
                reply_markup=get_return_button()
            )
        except Exception as e:
            logger.info(f"Could not edit message for empty schedules, sending new: {str(e)}")
            await query.message.reply_text(
                "Nenhum agendamento para remover.",
                reply_markup=get_return_button()
            )
        return ConversationHandler.END
    
    for i, schedule in enumerate(schedules):
        msg_type = MESSAGE_TYPES[schedule['type']]
        
        # Format location display based on schedule type
        location = ""
        if 'location' in schedule:
            if schedule['type'] == 'ru':
                # For RU schedules, look up the location name in RU_LOCATIONS
                location = f" ({RU_LOCATIONS[schedule['location']]})"
            elif schedule['type'] == 'weather' or schedule['type'] == 'rss':
                # For weather or RSS schedules, use the location value directly
                location = f" ({schedule['location']})"
        
        keyboard.append([InlineKeyboardButton(
            f"❌ {schedule['time']} - {msg_type}{location}",
            callback_data=f"schedule_remove_{i}"
        )])
    
    keyboard.append([InlineKeyboardButton(
        "🗑️ Remover Todos",
        callback_data="schedule_remove_all"
    )])
    keyboard.append([InlineKeyboardButton("↩️ Voltar", callback_data="schedule_menu")])
    
    try:
        await query.message.edit_text(
            "Selecione o agendamento para remover:",
            reply_markup=InlineKeyboardMarkup(keyboard)
        )
    except Exception as e:
        logger.info(f"Could not edit message for remove schedule menu, sending new: {str(e)}")
        await query.message.reply_text(
            "Selecione o agendamento para remover:",
            reply_markup=InlineKeyboardMarkup(keyboard)
        )
    return SELECTING_ACTION

async def handle_remove_selection(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    """Handle the removal of a specific schedule"""
    query = update.callback_query
    await query.answer()
    
    chat_id = update.effective_chat.id
    data = query.data.replace("schedule_remove_", "")
    
    if data == "all":
        schedules = load_schedules()
        schedules[str(chat_id)] = []
        save_schedules(schedules)
        message = "✅ Todos os agendamentos foram removidos!"
    else:
        try:
            index = int(data)
            if remove_schedule(chat_id, index):
                message = "✅ Agendamento removido com sucesso!"
            else:
                message = "❌ Erro ao remover agendamento."
        except ValueError:
            message = "❌ Erro ao remover agendamento."
    
    try:
        await query.message.edit_text(
            message,
            reply_markup=get_return_button()
        )
    except Exception as e:
        logger.info(f"Could not edit message after schedule removal, sending new: {str(e)}")
        await query.message.reply_text(
            message,
            reply_markup=get_return_button()
        )
    return ConversationHandler.END
