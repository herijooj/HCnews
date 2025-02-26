import json
import os
import hashlib
import subprocess
from datetime import datetime
from typing import Dict, Tuple, List, Optional, Any
from utils.text_utils import split_message, clean_ansi

def load_rss_feeds() -> Dict[str, Any]:
    """Load saved RSS feeds"""
    try:
        with open('data/rss_feeds.json', 'r') as f:
            feeds = json.load(f)
            
            # Convert legacy format (chat_id: url) to new format (chat_id: {name: url})
            for chat_id, value in feeds.items():
                if isinstance(value, str):
                    feeds[chat_id] = {"Default": value}
                    
            return feeds
    except FileNotFoundError:
        return {}

def save_rss_feed(chat_id: int, url: str, name: str = None) -> str:
    """Save RSS feed URL for a chat with an optional name
    
    Returns the name used for the feed
    """
    feeds = load_rss_feeds()
    chat_id_str = str(chat_id)
    
    # Initialize feeds for this chat if not exists
    if chat_id_str not in feeds:
        feeds[chat_id_str] = {}
    
    # Auto-generate name if not provided
    if not name:
        try:
            name = url.split('/')[2]  # Use domain as name
            
            # If name exists, append a number
            base_name = name
            counter = 1
            while name in feeds[chat_id_str]:
                name = f"{base_name}_{counter}"
                counter += 1
                
        except (IndexError, ValueError):
            # Default name with timestamp
            timestamp = datetime.now().strftime("%Y%m%d%H%M%S")
            name = f"feed_{timestamp}"
    
    # Save the feed
    feeds[chat_id_str][name] = url
    
    # Ensure directory exists
    os.makedirs('data', exist_ok=True)
    
    with open('data/rss_feeds.json', 'w') as f:
        json.dump(feeds, f)
        
    return name

def remove_rss_feed(chat_id: int, feed_name: str = None) -> bool:
    """Remove RSS feed for a chat
    
    If feed_name is None, removes all feeds for this chat
    """
    feeds = load_rss_feeds()
    chat_id_str = str(chat_id)
    
    if chat_id_str not in feeds:
        return False
        
    if feed_name is None:
        # Remove all feeds
        del feeds[chat_id_str]
        success = True
    elif feed_name in feeds[chat_id_str]:
        # Remove specific feed
        del feeds[chat_id_str][feed_name]
        if not feeds[chat_id_str]:
            del feeds[chat_id_str]  # Remove chat entry if no feeds left
        success = True
    else:
        success = False
    
    if success:
        with open('data/rss_feeds.json', 'w') as f:
            json.dump(feeds, f)
    
    return success

def get_rss_feeds(chat_id: int) -> Dict[str, str]:
    """Get all RSS feeds for a chat as {name: url}"""
    feeds = load_rss_feeds()
    return feeds.get(str(chat_id), {})

def get_rss_feed(chat_id: int, feed_name: str = None) -> Optional[str]:
    """Get RSS feed URL for a chat
    
    If feed_name is None and there's only one feed, returns that feed
    If feed_name is None and there are multiple feeds, returns None
    """
    feeds = get_rss_feeds(chat_id)
    
    if not feeds:
        return None
        
    if feed_name is None:
        if len(feeds) == 1:
            return next(iter(feeds.values()))
        else:
            return None
    
    return feeds.get(feed_name)

def validate_rss_url(url: str) -> bool:
    """Basic validation of RSS URL"""
    return url.startswith(('http://', 'https://'))

def get_url_hash(url: str) -> str:
    """Get a short hash of a URL"""
    return hashlib.md5(url.encode()).hexdigest()[:8]

def get_rss_cache_path(url: str) -> str:
    """Get the cache path for an RSS feed"""
    today = datetime.now().strftime('%Y%m%d')
    url_hash = get_url_hash(url)
    
    # Ensure directory exists
    os.makedirs('news', exist_ok=True)
    
    return f'news/{today}_rss_{url_hash}.txt'

def generate_rss_content(url: str, force: bool = False) -> Tuple[bool, str]:
    """Generate RSS feed content from URL"""
    cache_path = get_rss_cache_path(url)
    
    # Check if cache exists and is not forced
    if os.path.exists(cache_path) and not force:
        with open(cache_path, 'r') as f:
            return True, f.read()
    
    # Generate new content
    try:
        result = subprocess.run(
            ['bash', 'scripts/rss.sh', '-l', '-f', url],
            capture_output=True, text=True, check=True
        )
        content = clean_ansi(result.stdout)
        
        # Cache the result
        with open(cache_path, 'w') as f:
            f.write(content)
            
        return True, content
    except subprocess.CalledProcessError as e:
        error_msg = f"Error processing RSS feed: {e.stderr}"
        return False, error_msg
    except Exception as e:
        error_msg = f"Unexpected error processing RSS feed: {str(e)}"
        return False, error_msg

def get_rss_filename(url: str) -> str:
    """Get a filename for an RSS feed"""
    today = datetime.now().strftime('%Y%m%d')
    url_hash = get_url_hash(url)
    url_domain = url.split('/')[2] if len(url.split('/')) > 2 else 'custom'
    return f"{url_domain}_{today}_{url_hash}.txt"
