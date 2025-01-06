import logging
from telegram import ForceReply, Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import (
    Application, CommandHandler, ContextTypes, MessageHandler, filters, JobQueue, CallbackQueryHandler
)
import telegram.error  # Add this import
import os
from subprocess import PIPE, run
from datetime import datetime, timezone
from tokens import TOKEN  # Add this import
import json
import pytz  # Add this import
import re  # Add this import

# Enable logging
logging.basicConfig(
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s", level=logging.INFO
)
logging.getLogger("httpx").setLevel(logging.WARNING)
logger = logging.getLogger(__name__)

# Initialize constants
NEWS_DIR = "news"
DEFAULT_SEND_TIME = "07:00"
SCHEDULE_FILE = "schedules.json"
ZODIAC_SIGNS = ["aries", "peixes", "aquario", "capricornio", "sagitario", 
                "escorpiao", "libra", "virgem", "leao", "cancer", "gemeos", "touro"]
MESSAGE_TYPES = {
    "news": "Notícias",
    "horoscope": "Horóscopo",
    "weather": "Previsão do Tempo",
    "exchange": "Cotações",
    "bicho": "Jogo do Bicho"
}
MAX_MESSAGE_SIZE = 4000  # Using 4000 to have some safety margin
SCHEDULE_MESSAGES = {
    "news": "📰 Notícias diárias",
    "horoscope": "🔮 Horóscopo do dia",
    "weather": "🌤️ Previsão do tempo",
    "exchange": "💱 Cotações",
    "bicho": "🎲 Palpites do jogo do bicho"
}
DEFAULT_SEND_AS_MESSAGE = True  # Default to sending as message instead of file

# Utility Functions
def ensure_news_directory():
    """Ensure the news directory exists."""
    if not os.path.exists(NEWS_DIR):
        os.makedirs(NEWS_DIR, exist_ok=True)

def generate_news_file(force_generation: bool) -> str:
    """Generate the news file using the bash script."""
    ensure_news_directory()
    today = datetime.now().strftime("%Y%m%d")
    filename = f"{NEWS_DIR}/{today}.news"

    if force_generation or not os.path.exists(filename):
        # Add -y flag to run in non-interactive mode
        result = run(['bash', 'hcnews.sh', '-f', '-sa', '-s'], stdout=PIPE, stderr=PIPE)
        if result.returncode != 0:
            logger.error("Failed to generate news file: %s", result.stderr.decode())
            return ""
    return filename if os.path.exists(filename) else ""

def generate_horoscope(force_generation: bool = False, sign: str = None) -> str:
    """Generate horoscope using the bash script and cache it."""
    ensure_news_directory()
    today = datetime.now().strftime("%Y%m%d")
    filename = f"{NEWS_DIR}/{today}.hrcp"

    if force_generation or not os.path.exists(filename):
        cmd = ['bash', 'horoscopo.sh', '-s']
        if sign:
            cmd.append(sign)
        result = run(cmd, stdout=PIPE, stderr=PIPE, text=True)
        if result.returncode != 0:
            logger.error("Failed to generate horoscope: %s", result.stderr)
            return ""
    
    if not sign:
        return filename if os.path.exists(filename) else ""
        
    try:
        with open(filename, 'r') as f:
            content = f.read()
            lines = content.split('\n')
            for i, line in enumerate(lines):
                if f"📌 {sign}" in line.lower():
                    return f"{lines[i-1]}\n{line}"
            return ""
    except FileNotFoundError:
        logger.error(f"Horoscope file not found: {filename}")
        return ""

def load_schedules() -> dict:
    """Load scheduled times from file."""
    try:
        with open(SCHEDULE_FILE, 'r') as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {}

def save_schedule(chat_id: int, time: str, msg_type: str = "news") -> None:
    """Save scheduled time and message type for a chat."""
    schedules = load_schedules()
    chat_id_str = str(chat_id)
    if chat_id_str not in schedules:
        schedules[chat_id_str] = []
    schedule_entry = {"time": time, "type": msg_type}
    if schedule_entry not in schedules[chat_id_str]:
        schedules[chat_id_str].append(schedule_entry)
    with open(SCHEDULE_FILE, 'w') as f:
        json.dump(schedules, f)

def remove_schedule(chat_id: int, time: str = None, msg_type: str = None) -> None:
    """Remove scheduled time(s) for a chat."""
    schedules = load_schedules()
    chat_id_str = str(chat_id)
    if chat_id_str in schedules:
        if time is None:
            del schedules[chat_id_str]
        else:
            schedules[chat_id_str] = [
                s for s in schedules[chat_id_str] 
                if s["time"] != time or (msg_type and s["type"] != msg_type)
            ]
            if not schedules[chat_id_str]:
                del schedules[chat_id_str]
        with open(SCHEDULE_FILE, 'w') as f:
            json.dump(schedules, f)

def convert_to_utc(time_str: str) -> datetime.time:
    """Convert local time string to UTC time object."""
    local = pytz.timezone('America/Sao_Paulo')  # Or your local timezone
    naive_dt = datetime.strptime(time_str, "%H:%M")
    local_dt = local.localize(datetime.combine(datetime.now().date(), naive_dt.time()))
    utc_dt = local_dt.astimezone(pytz.UTC)
    return utc_dt.time()

def clean_ansi(text: str) -> str:
    """Remove ANSI escape codes from text."""
    ansi_escape = re.compile(r'\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])')
    return ansi_escape.sub('', text)

def split_long_message(text: str) -> list[str]:
    """Split message into chunks respecting message size limit and line breaks."""
    if not text or len(text) <= MAX_MESSAGE_SIZE:
        return [text] if text else []
    
    messages = []
    current_msg = ""
    
    for line in text.split('\n'):
        # Check if adding this line would exceed limit
        if len(current_msg) + len(line) + 1 > MAX_MESSAGE_SIZE:
            if current_msg:
                messages.append(current_msg.strip())
                current_msg = line + '\n'
            else:
                # Single line is too long, force split it
                while line:
                    messages.append(line[:MAX_MESSAGE_SIZE])
                    line = line[MAX_MESSAGE_SIZE:]
        else:
            current_msg += line + '\n'
    
    if current_msg:
        messages.append(current_msg.strip())
    
    return messages

# Command Handlers
async def start(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Send a welcome message with available options."""
    user = update.effective_user
    buttons = [
        [InlineKeyboardButton("Enviar Notícias", callback_data="send_news")],
        [InlineKeyboardButton("Horóscopo", callback_data="horoscope")],
        [InlineKeyboardButton("Previsão do Tempo", callback_data="weather")],
        [InlineKeyboardButton("Cotações", callback_data="exchange")],
        [InlineKeyboardButton("Jogo do Bicho", callback_data="bicho")],
        [InlineKeyboardButton("Ajuda", callback_data="help")]
    ]
    keyboard = InlineKeyboardMarkup(buttons)
    await update.message.reply_html(
        rf"Olá {user.mention_html()}! Bem-vindo ao HCNEWS. Aqui estão suas opções:",
        reply_markup=keyboard
    )

async def help_command(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Send a detailed help message."""
    help_text = (
        "Aqui estão os comandos disponíveis:\n"
        "/start - Mostra a mensagem de boas-vindas e opções.\n"
        "/help - Exibe esta mensagem de ajuda.\n"
        "/send [force] [file] - Envia as notícias. Opções:\n"
        "  • force: Força geração de novo arquivo\n"
        "  • file: Envia como arquivo em vez de mensagem\n"
        "/horoscope [sign] [file] - Mostra o horóscopo.\n"
        "/schedule - Gerencia agendamentos"
    )
    await update.message.reply_text(help_text)

async def send_news(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Send the news file or generate it if missing."""
    force_generation = False
    send_as_file = False
    
    # Parse arguments
    if context.args:
        force_generation = "force" in context.args
        send_as_file = "file" in context.args
    
    filename = generate_news_file(force_generation)
    if not filename:
        await update.message.reply_text("Não foi possível criar o arquivo de notícias.")
        return

    try:
        with open(filename, "r", encoding='utf-8') as f:
            content = f.read()
            
        if send_as_file:
            with open(filename, "rb") as f:
                await update.message.reply_text("📰 Notícias do dia (arquivo)")
                await update.message.reply_document(
                    document=f,
                    filename=f"noticias_{datetime.now().strftime('%Y%m%d')}.txt"
                )
        else:
            messages = split_long_message(content)
            await update.message.reply_text("📰 Notícias do dia")
            for msg in messages:
                if msg:  # Don't send empty messages
                    await update.message.reply_text(msg)
            
            if len(messages) > 3:  # If message was split into many parts, offer file option
                await update.message.reply_text(
                    "💡 Muitas mensagens? Use '/send file' para receber como arquivo."
                )
    except Exception as e:
        logger.error(f"Error sending news: {str(e)}")
        await update.message.reply_text("Erro ao enviar as notícias.")

async def show_horoscope_menu(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Show the horoscope selection menu."""
    buttons = []
    row = []
    for i, sign in enumerate(ZODIAC_SIGNS, 1):
        row.append(InlineKeyboardButton(sign.capitalize(), callback_data=f"horoscope_{sign}"))
        if i % 3 == 0:  # Create rows of 3 buttons
            buttons.append(row)
            row = []
    if row:  # Add any remaining buttons
        buttons.append(row)
    buttons.append([InlineKeyboardButton("Todos os signos", callback_data="horoscope_all")])
    
    keyboard = InlineKeyboardMarkup(buttons)
    message = "Escolha um signo:"
    
    # Handle both direct commands and callback queries
    if update.callback_query:
        await update.callback_query.message.reply_text(message, reply_markup=keyboard)
    else:
        await update.message.reply_text(message, reply_markup=keyboard)

async def horoscope_command(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Send daily horoscope menu or specific sign."""
    if context.args:
        sign = context.args[0].lower()
        force = "force" in context.args
        if sign in ZODIAC_SIGNS:
            horoscope_text = generate_horoscope(force, sign)
        else:
            await update.message.reply_text("Signo inválido. Use o menu para selecionar um signo.")
            await show_horoscope_menu(update, context)
            return
    else:
        await show_horoscope_menu(update, context)
        return

    if horoscope_text:
        await update.message.reply_text(horoscope_text, parse_mode='Markdown')
    else:
        await update.message.reply_text("Não foi possível obter o horóscopo. Tente novamente mais tarde.")

async def schedule_command(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Schedule messages at specified times."""
    if not update.message:
        return
        
    chat_id = update.message.chat_id
    
    if len(context.args) == 0:
        # Show current schedules
        schedules = load_schedules()
        entries = schedules.get(str(chat_id), [])
        if entries:
            schedule_text = "📅 *Horários Agendados*\n\n"
            for entry in sorted(entries, key=lambda x: x["time"]):
                schedule_text += f"• {entry['time']} - {MESSAGE_TYPES[entry['type']]}\n"
            await update.message.reply_text(schedule_text, parse_mode='Markdown')
        else:
            await update.message.reply_text("📅 Nenhum horário agendado.\n\nUse /schedule HH:MM tipo para agendar.")
        return
    
    if context.args[0].lower() == "off":
        remove_schedule(chat_id)
        current_jobs = context.job_queue.get_jobs_by_name(str(chat_id))
        for job in current_jobs:
            job.schedule_removal()
        await update.message.reply_text("Todos os agendamentos foram removidos.")
        return

    if context.args[0].lower() == "remove":
        if len(context.args) < 2:
            await update.message.reply_text("Uso: /schedule remove HH:MM [tipo]")
            return
        try:
            time_to_remove = datetime.strptime(context.args[1], "%H:%M").strftime("%H:%M")
            msg_type = context.args[2] if len(context.args) > 2 else None
            if msg_type and msg_type not in MESSAGE_TYPES:
                await update.message.reply_text(f"Tipo de mensagem inválido. Opções: {', '.join(MESSAGE_TYPES.keys())}")
                return
            remove_schedule(chat_id, time_to_remove, msg_type)
            current_jobs = context.job_queue.get_jobs_by_name(f"{chat_id}_{time_to_remove}_{msg_type if msg_type else ''}")
            for job in current_jobs:
                job.schedule_removal()
            await update.message.reply_text(f"Agendamento para {time_to_remove} removido.")
        except ValueError:
            await update.message.reply_text("Formato de horário inválido. Use HH:MM")
        return

    if len(context.args) < 2:
        await update.message.reply_text(f"Uso: /schedule HH:MM tipo\nTipos disponíveis: {', '.join(MESSAGE_TYPES.keys())}")
        return

    try:
        local_time = datetime.strptime(context.args[0], "%H:%M")
        time_str = local_time.strftime("%H:%M")
        msg_type = context.args[1].lower()

        if msg_type not in MESSAGE_TYPES:
            await update.message.reply_text(f"Tipo de mensagem inválido. Opções: {', '.join(MESSAGE_TYPES.keys())}")
            return

        utc_time = convert_to_utc(time_str)
        
        # Add new job
        job = context.job_queue.run_daily(
            scheduled_send_message, 
            time=utc_time,
            chat_id=chat_id,
            name=f"{chat_id}_{time_str}_{msg_type}",
            data={"type": msg_type}
        )
        
        if job:
            save_schedule(chat_id, time_str, msg_type)
            logger.info(f"Scheduled new {msg_type} job for chat {chat_id} at {time_str} (UTC: {utc_time})")
            await update.message.reply_text(f"Envio diário de {MESSAGE_TYPES[msg_type]} agendado para {time_str}.")
        else:
            await update.message.reply_text("Não foi possível agendar o envio. Tente novamente.")
            
    except ValueError as e:
        logger.error(f"Schedule error for chat {chat_id}: {str(e)}")
        await update.message.reply_text(
            "Formato de horário inválido.\n"
            "Uso:\n"
            "/schedule - mostra horários agendados\n"
            f"/schedule HH:MM tipo - adiciona novo horário ({', '.join(MESSAGE_TYPES.keys())})\n"
            "/schedule remove HH:MM [tipo] - remove horário específico\n"
            "/schedule off - remove todos os horários"
        )

async def scheduled_send_message(context: ContextTypes.DEFAULT_TYPE) -> None:
    """Send scheduled message based on type."""
    try:
        chat_id = context.job.chat_id
        msg_type = context.job.data["type"]
        logger.info(f"Running scheduled {msg_type} job for chat {chat_id}")

        if msg_type == "news":
            filename = generate_news_file(force_generation=False)
            if filename:
                with open(filename, "r", encoding='utf-8') as f:
                    content = f.read()
                messages = split_long_message(content)
                
                await context.bot.send_message(chat_id=chat_id, text="📰 Notícias do dia")
                for msg in messages:
                    if msg:
                        await context.bot.send_message(chat_id=chat_id, text=msg)
                
                if len(messages) > 3:
                    # Also send as file for convenience when there are many messages
                    with open(filename, "rb") as f:
                        await context.bot.send_document(
                            chat_id=chat_id,
                            document=f,
                            filename=f"noticias_{datetime.now().strftime('%Y%m%d')}.txt",
                            caption="📎 Arquivo completo das notícias"
                        )
        
        elif msg_type == "horoscope":
            filename = generate_horoscope()
            if filename:
                with open(filename, "r", encoding='utf-8') as f:
                    content = f.read()
                messages = split_long_message(content)
                
                await context.bot.send_message(chat_id=chat_id, text="🔮 Horóscopo do dia")
                for msg in messages:
                    if msg:
                        await context.bot.send_message(chat_id=chat_id, text=msg)
                
                if len(messages) > 3:
                    with open(filename, "rb") as f:
                        await context.bot.send_document(
                            chat_id=chat_id,
                            document=f,
                            filename=f"horoscopo_{datetime.now().strftime('%Y%m%d')}.txt",
                            caption="📎 Arquivo completo do horóscopo"
                        )

        # ... rest of the message types remain unchanged ...

    except Exception as e:
        logger.error(f"Error in scheduled_send_message: {str(e)}")

async def scheduled_send_news(context: ContextTypes.DEFAULT_TYPE) -> None:
    """Send news daily as per the scheduled time."""
    try:
        chat_id = context.job.chat_id
        logger.info(f"Running scheduled job for chat {chat_id}")
        
        filename = generate_news_file(force_generation=False)
        if not filename:
            logger.error(f"Scheduled task: Failed to generate news file for chat {chat_id}")
            return

        with open(filename, "rb") as f:
            await context.bot.send_message(
                chat_id=chat_id,
                text="📰 Notícias do dia"
            )
            await context.bot.send_document(
                chat_id=chat_id, 
                document=f, 
                filename=f"{datetime.now().strftime('%Y%m%d')}.txt"
            )
            logger.info(f"Successfully sent scheduled news to chat {chat_id}")
    except Exception as e:
        logger.error(f"Error in scheduled_send_news: {str(e)}")

async def send_news_callback(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Send news file for callback queries."""
    force_generation = False
    filename = generate_news_file(force_generation)
    
    if not filename:
        await update.callback_query.message.reply_text(
            "Não foi possível criar o arquivo de notícias. Verifique os logs para mais detalhes."
        )
        return

    with open(filename, "rb") as f:
        await update.callback_query.message.reply_text("📰 Notícias do dia")
        await update.callback_query.message.reply_document(
            document=f, 
            filename=f"{datetime.now().strftime('%Y%m%d')}.txt"
        )

async def help_command_callback(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Send help message for callback queries."""
    help_text = (
        "Aqui estão os comandos disponíveis:\n"
        "/start - Mostra a mensagem de boas-vindas e opções.\n"
        "/help - Exibe esta mensagem de ajuda.\n"
        "/send [force] - Gera e envia o arquivo de notícias de hoje. Use 'force' para regenerar o arquivo.\n"
        "/schedule HH:MM - Agenda o envio diário de notícias no horário especificado."
    )
    await update.callback_query.message.reply_text(help_text)

async def get_weather_info() -> str:
    """Get weather information from weather.sh script."""
    result = run(['bash', 'weather.sh'], stdout=PIPE, stderr=PIPE, text=True)
    if result.returncode != 0:
        logger.error("Failed to get weather info: %s", result.stderr)
        return ""
    return clean_ansi(result.stdout)

async def get_exchange_rates() -> str:
    """Get exchange rates from exchange.sh script."""
    result = run(['bash', 'exchange.sh'], stdout=PIPE, stderr=PIPE, text=True)
    if result.returncode != 0:
        logger.error("Failed to get exchange rates: %s", result.stderr)
        return ""
    return result.stdout

async def get_bicho_info() -> str:
    """Get jogo do bicho information from bicho.sh script."""
    result = run(['bash', 'bicho.sh'], stdout=PIPE, stderr=PIPE, text=True)
    if result.returncode != 0:
        logger.error("Failed to get bicho info: %s", result.stderr)
        return ""
    return result.stdout

async def button_handler(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Handle inline keyboard button clicks."""
    query = update.callback_query
    await query.answer()
    
    if query.data == "send_news":
        await send_news_callback(update, context)
    elif query.data == "help":
        await help_command_callback(update, context)
    elif query.data == "horoscope":
        await show_horoscope_menu(update, context)
    elif query.data == "weather":
        weather_info = await get_weather_info()
        if weather_info:
            try:
                await query.message.reply_text(weather_info, parse_mode='MarkdownV2')
            except telegram.error.BadRequest:
                await query.message.reply_text(weather_info)
        else:
            await query.message.reply_text("Não foi possível obter a previsão do tempo.")
    elif query.data == "exchange":
        exchange_info = await get_exchange_rates()
        if exchange_info:
            await query.message.reply_text(exchange_info, parse_mode='Markdown')
        else:
            await query.message.reply_text("Não foi possível obter as cotações.")
    elif query.data == "bicho":
        bicho_info = await get_bicho_info()
        if bicho_info:
            await query.message.reply_text(bicho_info, parse_mode='Markdown')
        else:
            await query.message.reply_text("Não foi possível obter os palpites do jogo do bicho.")
    elif query.data.startswith("horoscope_"):
        sign = query.data.split("_")[1]
        if sign == "all":
            filename = generate_horoscope()
            if filename:
                with open(filename, "rb") as f:
                    await query.message.reply_text("🔮 Horóscopo do dia para todos os signos")
                    await query.message.reply_document(
                        document=f,
                        filename=f"horoscopo_{datetime.now().strftime('%Y%m%d')}.txt"
                    )
            else:
                await query.message.reply_text("Não foi possível obter o horóscopo. Tente novamente mais tarde.")
        else:
            horoscope_text = generate_horoscope(sign=sign)
            if horoscope_text:
                await query.message.reply_text(horoscope_text, parse_mode='Markdown')
            else:
                await query.message.reply_text("Não foi possível obter o horóscopo. Tente novamente mais tarde.")

# Main Function
def main() -> None:
    """Start the bot."""
    token = TOKEN  # Change this line to use the imported TOKEN
    if not token:
        logger.error("TOKEN environment variable is missing.")
        return

    application = Application.builder().token(token).build()

    # Load all scheduled jobs
    schedules = load_schedules()
    for chat_id, entries in schedules.items():
        for entry in entries:
            try:
                time_str = entry["time"]
                msg_type = entry.get("type", "news")  # Default to news for backward compatibility
                utc_time = convert_to_utc(time_str)
                job = application.job_queue.run_daily(
                    scheduled_send_message,
                    time=utc_time,
                    chat_id=int(chat_id),
                    name=f"{chat_id}_{time_str}_{msg_type}",
                    data={"type": msg_type}
                )
                if job:
                    logger.info(f"Loaded scheduled {msg_type} job for chat {chat_id} at {time_str}")
                else:
                    logger.error(f"Failed to load {msg_type} job for chat {chat_id} at {time_str}")
            except ValueError as e:
                logger.error(f"Failed to load schedule for chat {chat_id}: {e}")

    # Schedule default news sending
    default_utc_time = convert_to_utc(DEFAULT_SEND_TIME)
    application.job_queue.run_daily(scheduled_send_news, time=default_utc_time)

    # Add command handlers
    application.add_handler(CommandHandler("start", start))
    application.add_handler(CommandHandler("help", help_command))
    application.add_handler(CommandHandler("send", send_news))
    application.add_handler(CommandHandler("horoscope", horoscope_command))
    application.add_handler(CommandHandler("schedule", schedule_command))
    application.add_handler(CallbackQueryHandler(button_handler))

    # Run the bot
    application.run_polling(allowed_updates=Update.ALL_TYPES)
    application.add_handler(CommandHandler("send", send_news))

if __name__ == "__main__":
    main()

    application.add_handler(CommandHandler("horoscope", horoscope_command))
    application.add_handler(CommandHandler("schedule", schedule_command))
    application.add_handler(CallbackQueryHandler(button_handler))

    # Run the bot
    application.run_polling(allowed_updates=Update.ALL_TYPES)

if __name__ == "__main__":
    main()
