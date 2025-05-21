import sys
import json
import re

def parse_inline_formatting(text):
    """
    Parses inline markdown like _italic_, `code`, and [link](url).
    """
    # Order of patterns matters. Links should be processed first if they can contain other formatting.
    # For simplicity, this version processes strong/em/code first, then links.
    # More complex parsers might use a multi-stage approach or a more sophisticated tokenizer.

    # Regex to find _italic_, *bold* (strong), `code`
    # We'll use a simplified regex that captures one token at a time
    # and iteratively builds the children list.
    
    # Pattern for _italic_, `code`, and [link text](url)
    # We'll handle one type at a time for now, then combine.
    # Let's start with _italic_ and `code`
    
    # This regex will find _italic_, `code`, or [text](url)
    # It uses named groups to identify which pattern matched.
    # For links, it captures the text and the URL.
    # For italic and code, it captures the content.
    pattern = re.compile(r'(_(?P<italic>.+?)_)|(`(?P<code>.+?)`)|(\[(?P<link_text>.+?)\]\((?P<link_url>.+?)\))')
    
    children = []
    last_end = 0
    
    for match in pattern.finditer(text):
        start, end = match.span()
        
        # Add preceding text if any
        if start > last_end:
            children.append(text[last_end:start])
            
        if match.group('italic'):
            # Recursively parse content of em tags
            children.append({"tag": "em", "children": parse_inline_formatting(match.group('italic'))})
        elif match.group('code'):
            # Code tags contain literal text, no further parsing of their content
            children.append({"tag": "code", "children": [match.group('code')]})
        elif match.group('link_text') and match.group('link_url'):
            # Recursively parse content of a tags (link text)
            children.append({
                "tag": "a", 
                "attrs": {"href": match.group('link_url')},
                "children": parse_inline_formatting(match.group('link_text'))
            })
        
        last_end = end
        
    # Add remaining text if any
    if last_end < len(text):
        children.append(text[last_end:])
        
    # Filter out empty strings that might result from splitting
    return [child for child in children if child]


def process_markdown_line(line):
    """
    Processes a single line of markdown.
    This will be expanded to handle different block types.
    """
    stripped_line = line.strip()
    # This function will now specifically handle paragraphs.
    # Header and list logic will be in the main loop.
    if not stripped_line: # Should not happen if called correctly from main
        return None
    return {"tag": "p", "children": parse_inline_formatting(stripped_line)}

def main():
    markdown_text = sys.stdin.read()
    lines = markdown_text.splitlines()
    output_nodes = []
    
    idx = 0
    while idx < len(lines):
        line = lines[idx]
        stripped_line = line.strip()

        if not stripped_line:
            idx += 1
            continue

        # Try to match headers: "Emoji *Text*" or "*Text*"
        # Example: 📝 *Frase do dia:*  becomes <h4>📝 Frase do dia:</h4>
        # The asterisks are removed.
        header_match = re.match(r"^(?:(\S+(?: \S+)*)\s+)?\*(.+?)\*(?:\s+)?$", stripped_line)
        # A simpler one might be: ^(\S+\s+)?\*(.+?)\*
        # Let's use one that captures an optional prefix (emoji/text) and then content in asterisks
        # Regex: (Optional Prefix Group) then (Content In Asterisks Group)
        # Prefix can be emoji or words. Content is inside asterisks.
        # Example: "📝 *Frase do dia:*" -> prefix="📝", content="Frase do dia:"
        # Example: "*Just Title*" -> prefix=None, content="Just Title"
        
        # Revised header regex: Matches optional prefix (non-greedy) and content within asterisks.
        # Ensures asterisks are present for it to be a header.
        # ^\s* (?: ([^\*]*?) \s+)? \* ([^\*]+?) \* \s*$
        # This regex was getting too complex. Let's simplify based on example `📝 *Frase do dia:*`
        # The rule says: "typically starting and ending with an asterisk"
        # And "The asterisks should be removed from the content."
        # "📝 *Frase do dia:*" becomes {"tag": "h4", "children": ["📝 Frase do dia:"]}
        # This implies the content for h4 is "📝 Frase do dia:", and the original line was `📝 *Frase do dia:*`
        # So, we need to capture "📝 " and "Frase do dia:".
        
        # Let's try this: capture (anything before *) then (*content*)
        # header_match = re.match(r"^(.*?)?\s?\*(.+?)\*\s*$", stripped_line)
        # This would make "my *bold* text" a header. Not good.
        
        # If the rule is "Lines that ... typically starting and ending with an asterisk": `* CONTENT *`
        # Or "and containing an emoji (e.g., `📝 *Frase do dia:*`)"
        # This suggests the emoji can be outside or inside the asterisks.
        # If `📝 *Frase do dia:*` -> `<h4>📝 Frase do dia:</h4>`
        #   Then the content is `prefix + inner_content_of_asterisks`.
        # Regex: `^(\S+(?:\s+\S+)*\s+)?\*([^*]+)\*$`
        #   Group 1: Optional prefix (e.g., "📝 ")
        #   Group 2: Content inside asterisks (e.g., "Frase do dia:")
        # If line is `*Actual Title*`, group 1 is None, group 2 is "Actual Title"
        # If line is `Emoji *Title*`, group 1 is "Emoji ", group 2 is "Title"
        
        # Let's use the example `📝 *Frase do dia:*` as a guide.
        # It becomes `{"tag": "h4", "children": ["📝 Frase do dia:"]}`.
        # A regex that can achieve this: `r"^(\S+\s+)?\*([^*]+)\*$"`.
        # Or, if the emoji is also part of what's inside asterisks: `r"^\*(.+)\*$"`.
        # The example output `["📝 Frase do dia:"]` implies the emoji is part of the text.
        # If the input is `*📝 Frase do dia:*`, then `r"^\*(.+)\*$"`.
        # If input is `📝 *Frase do dia:*`, then `r"^(\S+\s+)\*([^*]+)\*$"`.
        # The problem states: "The asterisks should be removed from the content."
        # "e.g., `📝 *Frase do dia:*`" implies this is the raw line.
        
        # Trying this header regex: `^(\S+)\s+\*(.+?)\*$` for "EMOJI *CONTENT*"
        # and `^\*(.+?)\*$` for "*CONTENT*"
        # Let's combine: `(?:^(\S+)\s+\*(.+?)\*$)|(?:^\*(.+?)\*$)`
        # Group1: EMOJI, Group2: CONTENT | Group3: CONTENT
        
        header_pattern = r"^(?:(\S+(?:\s\S+)*)\s+)?\*([^*]+)\*$"
        # This pattern:
        # Optional Group 1: `(\S+(?:\s\S+)*)\s+`  -- captures "prefix text "
        # Group 2: `([^*]+)` -- captures content inside asterisks
        # Example: "📝 *Frase do dia:*"
        #   Group 1: "📝 "
        #   Group 2: "Frase do dia:"
        # Example: "*Solo Title*"
        #   Group 1: None
        #   Group 2: "Solo Title"
        
        # Simpler approach: if line looks like `X *Y*` or `*Y*` and is a title.
        # The problem says "typically starting and ending with an asterisk". This would mean `*...*`.
        # e.g. `*📝 Frase do dia:*`
        # If the line is `*📝 Frase do dia:*`, then `re.match(r"^\*(.+)\*$", stripped_line)`
        # Content would be `match.group(1)`.
        # If the line is `📝 *Frase do dia:*`, this regex won't match.
        
        # Let's stick to the example `📝 *Frase do dia:*` -> `h4` with children `["📝 Frase do dia:"]`
        # This means the original asterisks were only around `Frase do dia:`.
        # So, regex: `^(\S+\s+)?\*([^*]+)\*$` (as used before)
        # header_match = re.match(r"^(\S+\s+)?\*([^*]+)\*$", stripped_line)
        # Re-evaluating based on "typically starting and ending with an asterisk"
        # This could mean the entire "📝 Frase do dia:" is wrapped in asterisks.
        # e.g. `*📝 Frase do dia:*`
        # If so, `header_match = re.match(r"^\*(.+?)\*$", stripped_line)`
        # And the children would be `parse_inline_formatting(header_match.group(1))`.
        # This seems more consistent with "asterisks are removed".
        
        # Header rule: Lines like "EMOJI *Text*" or "*Text*"
        # Example: "📝 *Frase do dia:*" becomes h4 with children "📝 Frase do dia:"
        # The asterisks are removed.
        # Regex: optional_prefix_group + *content_group*
        # Prefix: (\S+(?:\s+\S+)*\s+)?  -- Non-greedy, captures leading text and space
        # Content: \*([^*]+)\*         -- Captures text between asterisks
        
        header_match = re.match(r"^(?:(\S+(?:\s+\S+)*)\s+)?\*([^*]+)\*(?:\s*)$", stripped_line)
        # Ensure it's the whole line by adding (?:\s*)$ to consume trailing spaces.
        # The (?:\s+\S+)* part in prefix allows multi-word prefixes like "Figure 1: "

        if header_match:
            prefix = header_match.group(1)
            content_inside_asterisks = header_match.group(2)
            
            full_content_text = ""
            if prefix:
                full_content_text += prefix # Already ends with a space due to regex `\s+`
            full_content_text += content_inside_asterisks
            
            # The rule "typically starting and ending with an asterisk" is a bit ambiguous.
            # If it means the *entire line* is `*...*`, then `📝 *Frase do dia:*` wouldn't match.
            # If it means the *significant part* is `*...*`, then `📝 *Frase do dia:*` fits.
            # The example `📝 *Frase do dia:*` -> `{"tag": "h4", "children": ["📝 Frase do dia:"]}`
            # strongly suggests the interpretation I'm using now.
            
            # For a line to be a header, it should mostly be this pattern.
            # Not, for example, "Some text then 📝 *Frase do dia:* and more text."
            # The `^(?:...)$` ensures the pattern covers the whole stripped_line.
            
            output_nodes.append({"tag": "h4", "children": parse_inline_formatting(full_content_text.strip())})
            idx += 1
        # List items: lines starting with "- "
        elif stripped_line.startswith("- "):
            list_items = []
            while idx < len(lines):
                current_line = lines[idx].strip()
                if current_line.startswith("- "):
                    item_content = current_line[2:] # Remove "- "
                    list_items.append({"tag": "li", "children": parse_inline_formatting(item_content)})
                    idx += 1
                else:
                    break # End of list
            if list_items:
                output_nodes.append({"tag": "ul", "children": list_items})
            # idx is already advanced past the list items
        else:
            # Default to paragraph
            node = process_markdown_line(stripped_line) # process_markdown_line expects a non-stripped line, but it strips it.
            if node: # process_markdown_line can return None if line is empty after stripping.
                output_nodes.append(node)
            idx += 1
            
    print(json.dumps(output_nodes, ensure_ascii=False))

if __name__ == "__main__":
    main()
