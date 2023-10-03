import logging
import schedule
import time

from telegram import ForceReply, Update
from telegram.ext import Application, CommandHandler, ContextTypes, MessageHandler, filters

import os
import tokens
from io import StringIO
from subprocess import PIPE, run

# Enable logging
logging.basicConfig(
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s", level=logging.INFO
)
# set higher logging level for httpx to avoid all GET and POST requests being logged
logging.getLogger("httpx").setLevel(logging.WARNING)

logger = logging.getLogger(__name__)


# Define a few command handlers. These usually take the two arguments update and
# context.
async def start(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Send a message when the command /start is issued."""
    user = update.effective_user
    await update.message.reply_html(
        rf"Hi {user.mention_html()}!",
        reply_markup=ForceReply(selective=True),
    )


async def help_command(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Send a message when the command /help is issued."""
    await update.message.reply_text("Help!")

async def send_news(update, context):
    """Send the output of the bash script when the command /send is issued."""
    # Get the output of the bash script
    result = run(['bash', 'hcnews.sh'], stdout=PIPE, stderr=PIPE, universal_newlines=True)
    # break the message every blank line
    result = result.stdout.split('\n\n')
    # Send each part of the message
    for part in result:
        await update.message.reply_text(part)

def main() -> None:
    """Start the bot."""
    # Create the Application and pass it your bot's token.
    token = os.environ["TOKEN"]
    application = Application.builder().token(token).build()

    # on different commands - answer in Telegram
    application.add_handler(CommandHandler("start", start))
    application.add_handler(CommandHandler("help", help_command))
    application.add_handler(CommandHandler("send", send_news))

    # Schedule the news to be sent at a certain time
    schedule.every().day.at("09:00").do(send_news)  # Change the time as per your requirement

    # Run the bot until the user presses Ctrl-C
    application.run_polling(allowed_updates=Update.ALL_TYPES)
    while True:
        schedule.run_pending()
        time.sleep(1)


if __name__ == "__main__":
    main()