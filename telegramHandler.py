import logging
from telegram import ForceReply, Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import (
    Application, CommandHandler, ContextTypes, MessageHandler, filters, JobQueue, CallbackQueryHandler
)
import os
from subprocess import PIPE, run
from datetime import datetime, timezone
from tokens import TOKEN  # Add this import
import json
import pytz  # Add this import

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

def load_schedules() -> dict:
    """Load scheduled times from file."""
    try:
        with open(SCHEDULE_FILE, 'r') as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {}

def save_schedule(chat_id: int, time: str) -> None:
    """Save scheduled time for a chat."""
    schedules = load_schedules()
    chat_id_str = str(chat_id)
    if chat_id_str not in schedules:
        schedules[chat_id_str] = []
    if time not in schedules[chat_id_str]:
        schedules[chat_id_str].append(time)
    with open(SCHEDULE_FILE, 'w') as f:
        json.dump(schedules, f)

def remove_schedule(chat_id: int, time: str = None) -> None:
    """Remove scheduled time(s) for a chat."""
    schedules = load_schedules()
    chat_id_str = str(chat_id)
    if chat_id_str in schedules:
        if time is None:
            del schedules[chat_id_str]
        elif time in schedules[chat_id_str]:
            schedules[chat_id_str].remove(time)
            if not schedules[chat_id_str]:  # Remove chat_id if no schedules left
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

# Command Handlers
async def start(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Send a welcome message with available options."""
    user = update.effective_user
    buttons = [
        [InlineKeyboardButton("Enviar Notícias", callback_data="send_news")],
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
        "/send [force] - Gera e envia o arquivo de notícias de hoje. Use 'force' para regenerar o arquivo.\n"
        "/schedule - Mostra horários agendados\n"
        "/schedule HH:MM - Adiciona novo horário de envio\n"
        "/schedule remove HH:MM - Remove horário específico\n"
        "/schedule off - Remove todos os horários"
    )
    await update.message.reply_text(help_text)

async def send_news(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Send the news file or generate it if missing."""
    force_generation = False
    
    # Check if command has arguments
    if context.args and "force" in context.args:
        force_generation = True
        logger.info("Force generation requested")

    filename = generate_news_file(force_generation)
    if not filename:
        await update.message.reply_text("Não foi possível criar o arquivo de notícias. Verifique os logs para mais detalhes.")
        return

    try:
        with open(filename, "rb") as f:
            await update.message.reply_document(document=f, filename=f"{datetime.now().strftime('%Y%m%d')}.txt")
            logger.info(f"News file sent successfully: {filename}")
    except Exception as e:
        logger.error(f"Error sending news file: {str(e)}")
        await update.message.reply_text("Erro ao enviar o arquivo de notícias.")

async def schedule_command(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Schedule daily news sending at specified times."""
    if not update.message:
        return
        
    chat_id = update.message.chat_id
    
    if len(context.args) == 0:
        # Show current schedules
        schedules = load_schedules()
        times = schedules.get(str(chat_id), [])
        if times:
            times_str = "\n".join(sorted(times))
            await update.message.reply_text(f"Horários agendados:\n{times_str}")
        else:
            await update.message.reply_text("Nenhum horário agendado.")
        return
    
    if context.args[0].lower() == "off":
        # Remove all schedules for this chat
        remove_schedule(chat_id)
        current_jobs = context.job_queue.get_jobs_by_name(str(chat_id))
        for job in current_jobs:
            job.schedule_removal()
        await update.message.reply_text("Todos os agendamentos foram removidos.")
        return

    if context.args[0].lower() == "remove":
        if len(context.args) != 2:
            await update.message.reply_text("Uso: /schedule remove HH:MM")
            return
        try:
            time_to_remove = datetime.strptime(context.args[1], "%H:%M").strftime("%H:%M")
            remove_schedule(chat_id, time_to_remove)
            current_jobs = context.job_queue.get_jobs_by_name(f"{chat_id}_{time_to_remove}")
            for job in current_jobs:
                job.schedule_removal()
            await update.message.reply_text(f"Agendamento para {time_to_remove} removido.")
        except ValueError:
            await update.message.reply_text("Formato de horário inválido. Use HH:MM")
        return

    try:
        local_time = datetime.strptime(context.args[0], "%H:%M")
        time_str = local_time.strftime("%H:%M")
        utc_time = convert_to_utc(time_str)
        
        # Add new job
        job = context.job_queue.run_daily(
            scheduled_send_news, 
            time=utc_time,
            chat_id=chat_id, 
            name=f"{chat_id}_{time_str}"
        )
        
        if job:
            save_schedule(chat_id, time_str)
            logger.info(f"Scheduled new job for chat {chat_id} at {time_str} (UTC: {utc_time})")
            await update.message.reply_text(f"Envio diário de notícias agendado para {time_str}.")
        else:
            await update.message.reply_text("Não foi possível agendar o envio. Tente novamente.")
            
    except ValueError as e:
        logger.error(f"Schedule error for chat {chat_id}: {str(e)}")
        await update.message.reply_text(
            "Formato de horário inválido.\n"
            "Uso:\n"
            "/schedule - mostra horários agendados\n"
            "/schedule HH:MM - adiciona novo horário\n"
            "/schedule remove HH:MM - remove horário específico\n"
            "/schedule off - remove todos os horários"
        )

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

async def button_handler(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Handle inline keyboard button clicks."""
    query = update.callback_query
    await query.answer()
    
    if query.data == "send_news":
        await send_news_callback(update, context)
    elif query.data == "help":
        await help_command_callback(update, context)

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
    for chat_id, times in schedules.items():
        for time_str in times:
            try:
                utc_time = convert_to_utc(time_str)
                job = application.job_queue.run_daily(
                    scheduled_send_news,
                    time=utc_time,
                    chat_id=int(chat_id),
                    name=f"{chat_id}_{time_str}"
                )
                if job:
                    logger.info(f"Loaded scheduled job for chat {chat_id} at {time_str} (UTC: {utc_time})")
                else:
                    logger.error(f"Failed to load job for chat {chat_id} at {time_str}")
            except ValueError as e:
                logger.error(f"Failed to load schedule for chat {chat_id} at {time_str}: {e}")

    # Schedule default news sending
    default_utc_time = convert_to_utc(DEFAULT_SEND_TIME)
    application.job_queue.run_daily(scheduled_send_news, time=default_utc_time)

    # Add command handlers
    application.add_handler(CommandHandler("start", start))
    application.add_handler(CommandHandler("help", help_command))
    application.add_handler(CommandHandler("send", send_news))
    application.add_handler(CommandHandler("schedule", schedule_command))
    application.add_handler(CallbackQueryHandler(button_handler))

    # Run the bot
    application.run_polling(allowed_updates=Update.ALL_TYPES)

if __name__ == "__main__":
    main()
