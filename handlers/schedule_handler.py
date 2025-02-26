import logging
from datetime import datetime, time
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import ContextTypes, ConversationHandler, JobQueue
from config.constants import MESSAGE_TYPES, RU_LOCATIONS, TIMEZONE
from config.keyboard import get_return_button, get_schedule_menu
from utils.schedule_utils import load_schedules, add_schedule, remove_schedule, save_schedules  # Added save_schedules

logger = logging.getLogger(__name__)

# Conversation states
SELECTING_ACTION = 0
SELECTING_TYPE = 1
SELECTING_LOCATION = 2
SELECTING_TIME = 3
CUSTOM_TIME = 4

# Predefined times
PRESET_TIMES = ["06:00", "07:00", "08:00", "10:00", "11:00", "12:00", "16:00", "17:00", "18:00", "Custom"]

def get_type_keyboard() -> InlineKeyboardMarkup:
    """Create message type selection keyboard"""
    keyboard = []
    row = []
    for type_id, type_name in MESSAGE_TYPES.items():
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

def format_schedules(chat_id: int) -> str:
    """Format user's schedules for display"""
    schedules = load_schedules().get(str(chat_id), [])
    if not schedules:
        return "Nenhum agendamento encontrado."
    
    formatted = "📅 *Seus agendamentos:*\n\n"
    for i, schedule in enumerate(schedules, 1):
        msg_type = MESSAGE_TYPES[schedule['type']]
        location = f" ({RU_LOCATIONS[schedule['location']]})" if 'location' in schedule else ""
        formatted += f"{i}. {schedule['time']} - {msg_type}{location}\n"
    return formatted

async def handle_schedule_menu(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    """Show schedule management menu"""
    query = update.callback_query
    chat_id = update.effective_chat.id
    
    schedules_text = format_schedules(chat_id)
    await query.message.edit_text(
        f"{schedules_text}\n\nEscolha uma opção:",
        reply_markup=get_schedule_menu(),
        parse_mode='Markdown'
    )
    return SELECTING_ACTION

async def handle_type_selection(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    """Handle message type selection"""
    query = update.callback_query
    await query.answer()
    
    await query.message.edit_text(
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
        await query.message.edit_text(
            "📍 Selecione o local:",
            reply_markup=InlineKeyboardMarkup(keyboard)
        )
        return SELECTING_LOCATION
    
    # Skip location selection for other types
    await query.message.edit_text(
        "🕒 Selecione o horário:",
        reply_markup=get_time_keyboard()
    )
    return SELECTING_TIME

async def handle_time_selection(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    """Handle time selection"""
    query = update.callback_query
    data = query.data.replace("schedule_time_", "")
    
    if data == "custom":
        await query.message.edit_text(
            "⌚ Digite o horário no formato HH:MM (ex: 09:30):",
            reply_markup=InlineKeyboardMarkup([[
                InlineKeyboardButton("↩️ Voltar", callback_data="schedule_menu")
            ]])
        )
        return CUSTOM_TIME
    
    # Add schedule with selected time
    success = add_schedule(
        update.effective_chat.id,
        data,
        context.user_data['schedule_type'],
        context.user_data.get('schedule_location')
    )
    
    if success:
        await query.message.edit_text(
            f"✅ Agendamento adicionado para {data}!",
            reply_markup=get_return_button()
        )
    else:
        await query.message.edit_text(
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

async def handle_remove_schedule(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    """Handle schedule removal"""
    query = update.callback_query
    await query.answer()
    
    chat_id = update.effective_chat.id
    schedules = load_schedules().get(str(chat_id), [])
    keyboard = []
    
    if not schedules:
        await query.message.edit_text(
            "Nenhum agendamento para remover.",
            reply_markup=get_return_button()
        )
        return ConversationHandler.END
    
    for i, schedule in enumerate(schedules):
        msg_type = MESSAGE_TYPES[schedule['type']]
        location = f" ({RU_LOCATIONS[schedule['location']]})" if 'location' in schedule else ""
        keyboard.append([InlineKeyboardButton(
            f"❌ {schedule['time']} - {msg_type}{location}",
            callback_data=f"schedule_remove_{i}"
        )])
    
    keyboard.append([InlineKeyboardButton(
        "🗑️ Remover Todos",
        callback_data="schedule_remove_all"
    )])
    keyboard.append([InlineKeyboardButton("↩️ Voltar", callback_data="schedule_menu")])
    
    await query.message.edit_text(
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
    
    await query.message.edit_text(
        message,
        reply_markup=get_return_button()
    )
    return ConversationHandler.END
