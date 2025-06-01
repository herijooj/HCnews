import logging
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import ContextTypes, ConversationHandler
from utils.rss_utils import (
    get_rss_feeds, get_rss_feed, save_rss_feed, remove_rss_feed, validate_rss_url,
    generate_rss_content, get_rss_filename
)
from utils.text_utils import split_message, escape_markdownv2
from config.keyboard import get_return_button, get_rss_menu

logger = logging.getLogger(__name__)

# Conversation states
WAITING_FOR_URL = 0
WAITING_FOR_FEED_NAME = 1
SELECTING_FEED = 2

# Re-add handle_clear_rss function for backwards compatibility
async def handle_clear_rss(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    """Show list of feeds to remove (for backward compatibility)"""
    return await handle_remove_rss_selection(update, context)

async def handle_rss_menu(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Show RSS feed menu"""
    query = update.callback_query
    chat_id = update.effective_chat.id
    
    feeds = get_rss_feeds(chat_id)
    
    if feeds:
        status_text = f"🌐 {len(feeds)} RSS feed(s) configurado(s)"
        
        # Add buttons for each feed
        keyboard = []
        for name, url in feeds.items():
            keyboard.append([InlineKeyboardButton(f"📲 {name}", callback_data=f"rss_view_{name}")])
            
        keyboard.append([
            InlineKeyboardButton("➕ Adicionar Feed", callback_data="rss_set"),
            InlineKeyboardButton("➖ Remover Feed", callback_data="rss_remove")
        ])
    else:
        status_text = "🌐 Nenhum RSS configurado"
        keyboard = [
            [
                InlineKeyboardButton("➕ Adicionar Feed", callback_data="rss_set"),
            ]
        ]
    
    keyboard.append([InlineKeyboardButton("🏠 Menu Principal", callback_data="main_menu")])
    
    await query.message.edit_text(
        f"{status_text}\n\nO que deseja fazer?",
        reply_markup=InlineKeyboardMarkup(keyboard)
    )

async def handle_set_rss(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    """Start the process of setting RSS URL"""
    query = update.callback_query
    await query.answer()
    
    await query.message.edit_text(
        "Por favor, envie a URL do feed RSS que deseja adicionar.\n\n"
        "Exemplo: https://exemplo.com/feed.xml\n\n"
        "Digite /cancel para cancelar.",
        reply_markup=InlineKeyboardMarkup([[
            InlineKeyboardButton("◀️ Voltar", callback_data="rss")
        ]])
    )
    return WAITING_FOR_URL

async def handle_url_input(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    """Handle RSS URL input"""
    url = update.message.text.strip()
    chat_id = update.effective_chat.id
    
    if url == "/cancel":
        await update.message.reply_text(
            "Operação cancelada.",
            reply_markup=get_rss_menu()
        )
        return ConversationHandler.END
    
    if not validate_rss_url(url):
        await update.message.reply_text(
            "⚠️ URL inválida. A URL deve começar com http:// ou https://\n"
            "Tente novamente ou digite /cancel para cancelar."
        )
        return WAITING_FOR_URL
    
    # Store URL temporarily
    context.user_data['rss_url'] = url
    
    # Ask for feed name
    await update.message.reply_text(
        "Como você deseja nomear este feed? (deixe em branco para nome automático)\n\n"
        "Digite /cancel para cancelar.",
        reply_markup=InlineKeyboardMarkup([[
            InlineKeyboardButton("◀️ Voltar", callback_data="rss")
        ]])
    )
    return WAITING_FOR_FEED_NAME

async def handle_feed_name_input(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    """Handle RSS feed name input"""
    name = update.message.text.strip()
    chat_id = update.effective_chat.id
    url = context.user_data.get('rss_url')
    
    if name == "/cancel":
        await update.message.reply_text(
            "Operação cancelada.",
            reply_markup=get_rss_menu()
        )
        context.user_data.pop('rss_url', None)
        return ConversationHandler.END
    
    if not url:
        await update.message.reply_text(
            "⚠️ Erro: URL não encontrada. Tente novamente.",
            reply_markup=get_rss_menu()
        )
        return ConversationHandler.END
    
    # Use empty name to trigger auto-naming
    if not name:
        name = None
        
    # Save RSS feed
    name = save_rss_feed(chat_id, url, name)
    
    # Test RSS feed
    success, content = generate_rss_content(url, force=True)
    
    if not success or not content.strip():
        # Remove the feed if test fails
        remove_rss_feed(chat_id, name)
        
        await update.message.reply_text(
            f"⚠️ Não foi possível processar o RSS. Verifique a URL.\n"
            f"Erro: {content}",
            reply_markup=get_rss_menu()
        )
        context.user_data.pop('rss_url', None)
        return ConversationHandler.END
    
    await update.message.reply_text(
        f"✅ RSS configurado com sucesso!\n"
        f"Nome: {name}\n"
        f"URL: {url}",
        reply_markup=get_rss_menu()
    )
    context.user_data.pop('rss_url', None)
    return ConversationHandler.END

async def handle_remove_rss_selection(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    """Show list of feeds to remove"""
    query = update.callback_query
    await query.answer()
    
    chat_id = update.effective_chat.id
    feeds = get_rss_feeds(chat_id)
    
    if not feeds:
        await query.message.edit_text(
            "❌ Nenhum RSS configurado para remover.",
            reply_markup=get_rss_menu()
        )
        return ConversationHandler.END
        
    keyboard = []
    for name, url in feeds.items():
        keyboard.append([InlineKeyboardButton(
            f"❌ {name}", 
            callback_data=f"rss_delete_{name}"
        )])
        
    if len(feeds) > 1:
        keyboard.append([InlineKeyboardButton(
            "🗑️ Remover Todos", 
            callback_data="rss_delete_all"
        )])
        
    keyboard.append([InlineKeyboardButton("◀️ Voltar", callback_data="rss")])
    
    await query.message.edit_text(
        "Selecione o feed RSS para remover:",
        reply_markup=InlineKeyboardMarkup(keyboard)
    )
    return SELECTING_FEED

async def handle_remove_feed(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    """Handle removal of specific feed"""
    query = update.callback_query
    await query.answer()
    
    chat_id = update.effective_chat.id
    data = query.data.replace("rss_delete_", "")
    
    if data == "all":
        success = remove_rss_feed(chat_id)
        message = "✅ Todos os feeds RSS foram removidos!" if success else "❌ Erro ao remover feeds."
    else:
        success = remove_rss_feed(chat_id, data)
        message = f"✅ Feed '{data}' removido com sucesso!" if success else "❌ Erro ao remover feed."
    
    await query.message.edit_text(
        message,
        reply_markup=get_rss_menu()
    )
    return ConversationHandler.END

async def handle_view_feed(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """View specific feed"""
    query = update.callback_query
    await query.answer()
    
    chat_id = update.effective_chat.id
    feed_name = query.data.replace("rss_view_", "")
    url = get_rss_feed(chat_id, feed_name)
    
    if not url:
        await query.message.edit_text(
            "❌ Feed não encontrado.",
            reply_markup=get_rss_menu()
        )
        return
    
    keyboard = [
        [
            InlineKeyboardButton("📱 Ver feed", callback_data=f"rss_message_{feed_name}"),
            InlineKeyboardButton("📎 Baixar feed", callback_data=f"rss_file_{feed_name}")
        ],
        [
            InlineKeyboardButton("🗑️ Remover feed", callback_data=f"rss_delete_{feed_name}"),
            InlineKeyboardButton("◀️ Voltar", callback_data="rss")
        ]
    ]
    
    await query.message.edit_text(
        f"🌐 Feed: {feed_name}\n"
        f"URL: {url}\n\n"
        f"O que deseja fazer?",
        reply_markup=InlineKeyboardMarkup(keyboard)
    )

async def send_specific_rss_as_message(update: Update, context: ContextTypes.DEFAULT_TYPE, feed_name: str = None) -> None:
    """Send RSS feed content as message"""
    chat_id = update.effective_chat.id
    
    # Extract feed name if not provided (from callback data)
    if feed_name is None and update.callback_query.data.startswith("rss_message_"):
        feed_name = update.callback_query.data.replace("rss_message_", "")
    
    rss_url = get_rss_feed(chat_id, feed_name)
    
    if not rss_url:
        await update.callback_query.message.edit_text(
            "Nenhum RSS configurado ou feed não encontrado.",
            reply_markup=get_rss_menu()
        )
        return
    
    # Show loading message
    await update.callback_query.answer("Processando RSS...")
    await update.callback_query.message.edit_text(
        f"🔄 Processando RSS {feed_name if feed_name else ''}...",
        reply_markup=None
    )
    
    success, content = generate_rss_content(rss_url)
    
    if not success or not content.strip():
        await update.callback_query.message.edit_text(
            f"❌ Não foi possível processar o RSS. Tente novamente mais tarde.\n"
            f"Erro: {content}",
            reply_markup=get_rss_menu()
        )
        return
    
    # Add feed name to content
    if feed_name:
        content = f"📰 Feed: {feed_name}\n\n{content}"
    
    # Escape content for MarkdownV2
    escaped_content = escape_markdownv2(content)
    
    # Split message if too long
    messages = split_message(escaped_content)
    
    # Important: Edit the original message instead of deleting it
    for i, msg in enumerate(messages):
        if i == 0:
            try:
                await update.callback_query.message.edit_text(
                    msg,
                    parse_mode='MarkdownV2',
                    reply_markup=None,  # No button on the first message if multiple
                    disable_web_page_preview=True
                )
            except Exception as markdown_error:
                # If MarkdownV2 parsing fails, send without parse_mode
                logger.warning(f"RSS MarkdownV2 parsing failed, sending without formatting: {str(markdown_error)}")
                await update.callback_query.message.edit_text(
                    msg,
                    reply_markup=None,
                    disable_web_page_preview=True
                )
        else:
            if i == len(messages) - 1:  # Last message
                try:
                    await update.callback_query.message.reply_text(
                        msg,
                        parse_mode='MarkdownV2',
                        reply_markup=get_return_button(),
                        disable_web_page_preview=True
                    )
                except Exception as markdown_error:
                    logger.warning(f"RSS MarkdownV2 parsing failed, sending without formatting: {str(markdown_error)}")
                    await update.callback_query.message.reply_text(
                        msg,
                        reply_markup=get_return_button(),
                        disable_web_page_preview=True
                    )
            else:
                try:
                    await update.callback_query.message.reply_text(
                        msg,
                        parse_mode='MarkdownV2',
                        disable_web_page_preview=True
                    )
                except Exception as markdown_error:
                    logger.warning(f"RSS MarkdownV2 parsing failed, sending without formatting: {str(markdown_error)}")
                    await update.callback_query.message.reply_text(
                        msg,
                        disable_web_page_preview=True
                    )
    
    # If there's only one message, add the return button to the original message
    if len(messages) == 1:
        try:
            await update.callback_query.message.edit_text(
                messages[0],
                parse_mode='MarkdownV2',
                reply_markup=get_return_button(),
                disable_web_page_preview=True
            )
        except Exception as e:
            # If edit fails, send a new message with return button
            await update.callback_query.message.reply_text(
                "🔙 Voltar ao menu",
                reply_markup=get_return_button()
            )

async def send_rss_as_message(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Send RSS feed content as message (main handler for backward compatibility)"""
    chat_id = update.effective_chat.id
    feeds = get_rss_feeds(chat_id)
    
    if not feeds:
        await update.callback_query.message.edit_text(
            "Nenhum RSS configurado. Configure um RSS primeiro.",
            reply_markup=get_rss_menu()
        )
        return
    
    if len(feeds) == 1:
        # If only one feed, show it directly
        feed_name = next(iter(feeds.keys()))
        await send_specific_rss_as_message(update, context, feed_name)
    else:
        # If multiple feeds, ask which one to show
        keyboard = []
        for name in feeds.keys():
            keyboard.append([InlineKeyboardButton(
                f"📲 {name}", 
                callback_data=f"rss_message_{name}"
            )])
        keyboard.append([InlineKeyboardButton("◀️ Voltar", callback_data="rss")])
        
        await update.callback_query.message.edit_text(
            "Selecione qual feed deseja visualizar:",
            reply_markup=InlineKeyboardMarkup(keyboard)
        )

async def send_specific_rss_as_file(update: Update, context: ContextTypes.DEFAULT_TYPE, feed_name: str = None) -> None:
    """Send specific RSS feed content as file"""
    chat_id = update.effective_chat.id
    
    # Extract feed name if not provided (from callback data)
    if feed_name is None and update.callback_query.data.startswith("rss_file_"):
        feed_name = update.callback_query.data.replace("rss_file_", "")
    
    rss_url = get_rss_feed(chat_id, feed_name)
    
    if not rss_url:
        await update.callback_query.message.edit_text(
            "Nenhum RSS configurado ou feed não encontrado.",
            reply_markup=get_rss_menu()
        )
        return
    
    # Show loading message
    await update.callback_query.answer("Processando RSS...")
    await update.callback_query.message.edit_text(
        f"🔄 Processando RSS {feed_name if feed_name else ''}...",
        reply_markup=None
    )
    
    success, content = generate_rss_content(rss_url)
    
    if not success or not content.strip():
        await update.callback_query.message.edit_text(
            f"❌ Não foi possível processar o RSS. Tente novamente mais tarde.\n"
            f"Erro: {content}",
            reply_markup=get_rss_menu()
        )
        return
    
    # Add feed name to content if available
    if feed_name:
        content = f"📰 Feed: {feed_name}\n\n{content}"
    
    # Save to file and send
    filename = get_rss_filename(rss_url)
    with open(filename, 'w') as f:
        f.write(content)
    
    # Send document with return button
    with open(filename, 'rb') as f:
        document_msg = await update.callback_query.message.reply_document(
            document=f,
            filename=filename,
            caption=f"📰 Feed RSS {feed_name if feed_name else ''}"
        )
    
    # Send a separate message with the return button
    await document_msg.reply_text(
        "🔙 Voltar ao menu",
        reply_markup=get_return_button()
    )
    
    # Update the original message instead of deleting it
    try:
        await update.callback_query.message.edit_text(
            f"✅ Feed RSS {feed_name if feed_name else ''} enviado como arquivo.",
            reply_markup=get_return_button()
        )
    except Exception:
        # If edit fails, don't worry - the return button is already sent
        pass
    
    # Clean up
    import os
    os.remove(filename)

async def send_rss_as_file(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Send RSS feed content as file (main handler for backward compatibility)"""
    chat_id = update.effective_chat.id
    feeds = get_rss_feeds(chat_id)
    
    if not feeds:
        await update.callback_query.message.edit_text(
            "Nenhum RSS configurado. Configure um RSS primeiro.",
            reply_markup=get_rss_menu()
        )
        return
    
    if len(feeds) == 1:
        # If only one feed, show it directly
        feed_name = next(iter(feeds.keys()))
        await send_specific_rss_as_file(update, context, feed_name)
    else:
        # If multiple feeds, ask which one to show
        keyboard = []
        for name in feeds.keys():
            keyboard.append([InlineKeyboardButton(
                f"📎 {name}", 
                callback_data=f"rss_file_{name}"
            )])
        keyboard.append([InlineKeyboardButton("◀️ Voltar", callback_data="rss")])
        
        await update.callback_query.message.edit_text(
            "Selecione qual feed deseja baixar:",
            reply_markup=InlineKeyboardMarkup(keyboard)
        )
