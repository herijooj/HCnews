import re
from typing import List
from config.constants import MAX_MESSAGE_LENGTH

def clean_ansi(text: str) -> str:
    """Remove ANSI escape codes from text"""
    ansi_escape = re.compile(r'\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])')
    return ansi_escape.sub('', text)

def split_message(text: str) -> List[str]:
    """Split long messages while preserving line breaks"""
    if len(text) <= MAX_MESSAGE_LENGTH:
        return [text]
    
    chunks = []
    current_chunk = ""
    
    for line in text.split('\n'):
        if len(current_chunk) + len(line) + 1 <= MAX_MESSAGE_LENGTH:
            current_chunk += line + '\n'
        else:
            if current_chunk:
                chunks.append(current_chunk.rstrip())
            current_chunk = line + '\n'
    
    if current_chunk:
        chunks.append(current_chunk.rstrip())
    
    return chunks

def escape_markdownv2(text: str) -> str:
    """
    Escape special characters for MarkdownV2.
    
    MarkdownV2 requires these characters to be escaped: _*[]()~`>#+-=|{}.!
    This version escapes ALL special characters to ensure parsing always works.
    """
    if not text:
        return text
    
    # Characters that need to be escaped in MarkdownV2
    # We'll escape ALL of them to be safe
    escape_chars = {
        '_': r'\_',
        '*': r'\*',
        '[': r'\[',
        ']': r'\]',
        '(': r'\(',
        ')': r'\)',
        '~': r'\~',
        '`': r'\`',
        '>': r'\>',
        '#': r'\#',
        '+': r'\+',
        '-': r'\-',
        '=': r'\=',
        '|': r'\|',
        '{': r'\{',
        '}': r'\}',
        '.': r'\.',
        '!': r'\!',
    }
    
    # Apply escaping for each character
    for char, escaped in escape_chars.items():
        text = text.replace(char, escaped)
    
    return text
