import json
from typing import Dict, List
from datetime import datetime
import pytz
from config.constants import TIMEZONE

def load_schedules() -> Dict:
    try:
        with open('data/schedules.json', 'r') as f:
            return json.load(f)
    except FileNotFoundError:
        return {}

def save_schedules(schedules: Dict) -> None:
    with open('data/schedules.json', 'w') as f:
        json.dump(schedules, f)

async def send_scheduled_message(context):
    """Send scheduled message to user"""
    job = context.job
    chat_id = job.chat_id
    msg_type = job.data['type']
    location = job.data.get('location')

    # Import handlers here to avoid circular imports
    from handlers.news_handler import send_news_as_message
    from handlers.weather_handler import send_weather
    from handlers.exchange_handler import send_exchange
    from handlers.bicho_handler import send_bicho
    from handlers.horoscope_handler import send_horoscope
    from handlers.ru_handler import send_ru_menu, handle_ru_selection
    from handlers.rss_handler import send_specific_rss_as_message

    # Create proper mock objects for the handlers
    class MockMessage:
        def __init__(self, chat_id):
            self.chat_id = chat_id
            
        async def reply_text(self, *args, **kwargs):
            await context.bot.send_message(chat_id=self.chat_id, *args, **kwargs)
            
        async def reply_document(self, *args, **kwargs):
            await context.bot.send_document(chat_id=self.chat_id, *args, **kwargs)

    class MockCallback:
        def __init__(self, message):
            self.message = message

        async def edit_message_text(self, *args, **kwargs):
            await context.bot.send_message(chat_id=self.message.chat_id, *args, **kwargs)
            
        async def answer(self, *args, **kwargs):
            pass

    class MockUpdate:
        def __init__(self, chat_id):
            self.effective_chat = type('obj', (object,), {'id': chat_id})
            self.message = MockMessage(chat_id)
            self.callback_query = MockCallback(self.message)

    mock_update = MockUpdate(chat_id)

    # Send scheduled message based on type
    try:
        if msg_type == 'news':
            await send_news_as_message(mock_update, context)
        elif msg_type == 'weather':
            await send_weather(mock_update, context)
        elif msg_type == 'exchange':
            await send_exchange(mock_update, context)
        elif msg_type == 'bicho':
            await send_bicho(mock_update, context)
        elif msg_type == 'horoscope':
            await send_horoscope(mock_update, context)
        elif msg_type == 'rss':
            # For RSS, location contains the feed name
            feed_name = location
            await send_specific_rss_as_message(mock_update, context, feed_name)
        elif msg_type == 'ru' and location:
            await handle_ru_selection(mock_update, context, f"ru_{location}")
    except Exception as e:
        logger.error(f"Error sending scheduled message: {str(e)}")
        await context.bot.send_message(
            chat_id=chat_id,
            text=f"❌ Erro ao enviar mensagem agendada: {str(e)}"
        )

def create_job(application, chat_id: int, schedule: dict) -> None:
    """Create a job for a schedule"""
    time_parts = schedule['time'].split(':')
    hour, minute = map(int, time_parts)
    
    # Convert to UTC for job scheduling
    local_time = TIMEZONE.localize(datetime.now().replace(
        hour=hour, minute=minute, second=0, microsecond=0))
    utc_time = local_time.astimezone(pytz.UTC)
    
    # Schedule job
    application.job_queue.run_daily(
        send_scheduled_message,
        utc_time.time(),
        chat_id=chat_id,
        data=schedule,
        name=f"{chat_id}_{schedule['type']}_{schedule['time']}"
    )

def setup_jobs(application) -> None:
    """Setup jobs for all existing schedules"""
    schedules = load_schedules()
    for chat_id, user_schedules in schedules.items():
        for schedule in user_schedules:
            create_job(application, int(chat_id), schedule)

def add_schedule(chat_id: int, time: str, msg_type: str, location: str = None) -> bool:
    """Add a new schedule and create its job"""
    schedules = load_schedules()
    chat_id_str = str(chat_id)
    
    if chat_id_str not in schedules:
        schedules[chat_id_str] = []
    
    schedule = {"time": time, "type": msg_type}
    if location:
        schedule["location"] = location
    
    schedules[chat_id_str].append(schedule)
    save_schedules(schedules)
    
    # Create job for the new schedule
    from telegram.ext import ApplicationBuilder
    application = ApplicationBuilder.application
    create_job(application, chat_id, schedule)
    
    return True

def remove_schedule(chat_id: int, index: int) -> bool:
    schedules = load_schedules()
    chat_id = str(chat_id)
    
    if chat_id in schedules and 0 <= index < len(schedules[chat_id]):
        schedules[chat_id].pop(index)
        save_schedules(schedules)
        return True
    return False

def convert_to_utc(time_str: str) -> datetime:
    """Convert local time to UTC for job scheduling"""
    local_dt = TIMEZONE.localize(datetime.strptime(time_str, "%H:%M"))
    return local_dt.astimezone(pytz.UTC)
