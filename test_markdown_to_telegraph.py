import unittest
import subprocess
import json
import os

# Ensure the script to be tested is executable
SCRIPT_PATH = os.path.join(os.path.dirname(__file__), "markdown_to_telegraph.py")

class TestMarkdownToTelegraph(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        # Make the script executable if it's not already
        if not os.access(SCRIPT_PATH, os.X_OK):
            os.chmod(SCRIPT_PATH, 0o755)

    def run_script(self, input_markdown):
        """Helper method to run the markdown_to_telegraph.py script and return its JSON output."""
        process = subprocess.run(
            [sys.executable, SCRIPT_PATH], # Use sys.executable to ensure using the same python interpreter
            input=input_markdown,
            capture_output=True,
            text=True,
            check=False  # Don't raise exception on non-zero exit, we'll check output
        )
        if process.returncode != 0:
            # Print stderr for easier debugging if the script fails
            print(f"Script stderr for input:\n{input_markdown}\n---BEGIN STDERR---\n{process.stderr}\n---END STDERR---")
            self.fail(f"Script failed with exit code {process.returncode}")
        
        try:
            return json.loads(process.stdout)
        except json.JSONDecodeError:
            print(f"Script stdout (non-JSON) for input:\n{input_markdown}\n---BEGIN STDOUT---\n{process.stdout}\n---END STDOUT---")
            self.fail("Script output was not valid JSON.")


    def test_empty_input(self):
        md = ""
        expected = []
        self.assertEqual(self.run_script(md), expected)

    def test_simple_paragraph(self):
        md = "Just a simple line of text."
        expected = [{"tag": "p", "children": ["Just a simple line of text."]}]
        self.assertEqual(self.run_script(md), expected)

    def test_multiple_paragraphs(self):
        md = "First line.\n\nSecond line."
        expected = [
            {"tag": "p", "children": ["First line."]},
            {"tag": "p", "children": ["Second line."]}
        ]
        self.assertEqual(self.run_script(md), expected)

    def test_header_section_title(self):
        md1 = "📝 *Test Header:*"
        expected1 = [{"tag": "h4", "children": ["📝 Test Header:"]}] # Assuming no further parsing of "📝 Test Header:"
        self.assertEqual(self.run_script(md1), expected1)

        md2 = "*Another Header*"
        expected2 = [{"tag": "h4", "children": ["Another Header"]}]
        self.assertEqual(self.run_script(md2), expected2)
        
        # Test case from problem: "The asterisks should be removed from the content."
        # "e.g., 📝 *Frase do dia:* becomes {"tag": "h4", "children": ["📝 Frase do dia:"]}"
        # The current script implementation of markdown_to_telegraph.py's header parsing
        # ( (prefix or "") + content_inside_asterisks ) and then parse_inline_formatting on that.
        # If "📝 Test Header:" is then parsed by parse_inline_formatting, and it contains no further
        # inline markdown, it will result in ["📝 Test Header:"]. This is fine.
        # If the header was "📝 *_Test Header:_*", the children would be
        # ["📝 ", {"tag": "em", "children": ["Test Header:"]}]
        md3 = "📝 *_Test Header:_*"; # Prefix, then asterisks containing italicized text
        expected3 = [{"tag": "h4", "children": ["📝 ", {"tag": "em", "children": ["Test Header:"]}]}]
        self.assertEqual(self.run_script(md3), expected3)


    def test_italic_text(self):
        md = "Text with _italic words_ here."
        expected = [{"tag": "p", "children": ["Text with ", {"tag": "em", "children": ["italic words"]}, " here."]}]
        self.assertEqual(self.run_script(md), expected)

    def test_code_span(self):
        md = "Text with `code example` here."
        expected = [{"tag": "p", "children": ["Text with ", {"tag": "code", "children": ["code example"]}, " here."]}]
        self.assertEqual(self.run_script(md), expected)

    def test_link(self):
        md = "Text with a [link](http.example.com) here."
        expected = [{"tag": "p", "children": ["Text with a ", {"tag": "a", "attrs": {"href": "http.example.com"}, "children": ["link"]}, " here."]}]
        self.assertEqual(self.run_script(md), expected)

    def test_unordered_list(self):
        md = "- Item 1\n- Item 2\n- Item 3"
        expected = [{"tag": "ul", "children": [
            {"tag": "li", "children": ["Item 1"]},
            {"tag": "li", "children": ["Item 2"]},
            {"tag": "li", "children": ["Item 3"]}
        ]}]
        self.assertEqual(self.run_script(md), expected)

    def test_list_with_inline_formatting(self):
        md1 = "- Item _italic_ `code` [link](url)"
        expected1 = [{"tag": "ul", "children": [{"tag": "li", "children": [
            "Item ",
            {"tag": "em", "children": ["italic"]},
            " ",
            {"tag": "code", "children": ["code"]},
            " ",
            {"tag": "a", "attrs": {"href": "url"}, "children": ["link"]}
        ]}]}]
        self.assertEqual(self.run_script(md1), expected1)

        md2 = "- _Item italic_ `code`"
        expected2 = [{"tag": "ul", "children": [{"tag": "li", "children": [
            {"tag": "em", "children": ["Item italic"]},
            " ",
            {"tag": "code", "children": ["code"]}
        ]}]}]
        self.assertEqual(self.run_script(md2), expected2)
        
        # Test recursive parsing within list items for em/a
        md3 = "- _Item [link](url)_"
        expected3 = [{"tag": "ul", "children": [{"tag": "li", "children": [
             {"tag": "em", "children": ["Item ", {"tag": "a", "attrs": {"href": "url"}, "children": ["link"]}]}
        ]}]}]
        self.assertEqual(self.run_script(md3), expected3)


    def test_mixed_content(self):
        md = "Intro text.\n- List item 1\n- List item 2\nConclusion text."
        expected = [
            {"tag": "p", "children": ["Intro text."]},
            {"tag": "ul", "children": [
                {"tag": "li", "children": ["List item 1"]},
                {"tag": "li", "children": ["List item 2"]}
            ]},
            {"tag": "p", "children": ["Conclusion text."]}
        ]
        self.assertEqual(self.run_script(md), expected)

    def test_full_hcnews_frase_do_dia(self):
        md = "📝 *Frase do dia:*\n_Without discipline, there's no life at all. - Katharine Hepburn_"
        # First line is a header. Header content is "📝 Frase do dia:"
        # Second line is a paragraph with only italic text.
        expected = [
            {"tag": "h4", "children": ["📝 Frase do dia:"]}, # Assuming "📝 Frase do dia:" does not contain further markdown itself
            {"tag": "p", "children": [
                {"tag": "em", "children": ["Without discipline, there's no life at all. - Katharine Hepburn"]}
            ]}
        ]
        self.assertEqual(self.run_script(md), expected)

    def test_complex_inline_content_in_paragraph(self):
        md = "This is _italic_, then `code`, then a [link](url), and more _italic again_."
        expected = [{"tag": "p", "children": [
            "This is ",
            {"tag": "em", "children": ["italic"]},
            ", then ",
            {"tag": "code", "children": ["code"]},
            ", then a ",
            {"tag": "a", "attrs": {"href": "url"}, "children": ["link"]},
            ", and more ",
            {"tag": "em", "children": ["italic again"]},
            "."
        ]}]
        self.assertEqual(self.run_script(md), expected)

    def test_link_with_italic_text(self):
        md = "[_italic link_](url)"
        expected = [{"tag": "p", "children": [
            {"tag": "a", "attrs": {"href": "url"}, "children": [
                {"tag": "em", "children": ["italic link"]}
            ]}
        ]}]
        self.assertEqual(self.run_script(md), expected)

    def test_italic_with_code_and_link(self):
        # Test based on the discussion about recursive parsing in parse_inline_formatting
        md = "_italic `code` [link](url)_"
        expected = [{"tag": "p", "children": [
            {"tag": "em", "children": [
                "italic ",
                {"tag": "code", "children": ["code"]},
                " ",
                {"tag": "a", "attrs": {"href": "url"}, "children": ["link"]}
            ]}
        ]}]
        self.assertEqual(self.run_script(md), expected)
        
    def test_empty_lines_between_list_items(self):
        # The current parser would break the list if there's an empty line.
        # This is consistent with "Consecutive non-empty lines ... for lists"
        # "each non-blank line not matching other rules can be its own paragraph"
        # An empty line would terminate the list processing.
        md = "- Item 1\n\n- Item 2" # This would be UL(LI(Item1)), P(empty or skipped), P("- Item2") or new UL
        # Current script logic: empty line is skipped. Then "- Item 2" starts a new list.
        expected = [
            {"tag": "ul", "children": [{"tag": "li", "children": ["Item 1"]}]},
            # Empty line is skipped
            {"tag": "ul", "children": [{"tag": "li", "children": ["Item 2"]}]}
        ]
        # Let's verify the actual behavior of markdown_to_telegraph.py for this
        # main loop: if not stripped_line: idx +=1; continue. So empty lines are fully skipped.
        # Then "- Item 2" will be processed as a new list. This is correct.
        self.assertEqual(self.run_script(md), expected)

    def test_header_like_text_not_a_header(self):
        # Test that asterisks in the middle of a line don't make it a header
        md = "This is not a *header* because text precedes it."
        # Expected: a paragraph.
        # Current header regex: r"^(?:(\S+(?:\s+\S+)*)\s+)?\*([^*]+)\*(?:\s*)$"
        # This would match if the line was "This is not a *header*".
        # "This is not a " would be prefix, "header" would be content.
        # This is how it's designed based on "📝 *Frase do dia:*"
        # So, "This is not a *header*" IS a header.
        # The test case "This is not a *header* because text precedes it."
        # The " because text precedes it." part is outside the asterisks.
        # The regex `\*(?:\s*)$` ensures it ends after the closing asterisk (and optional spaces).
        # So, "This is not a *header* because text precedes it." will NOT match the header regex.
        # It will become a paragraph.
        expected = [{"tag": "p", "children": ["This is not a *header* because text precedes it."]}]
        # The parse_inline_formatting will handle the *header* part if I add a rule for strong/bold.
        # Currently, `*header*` is not a special inline sequence in `parse_inline_formatting`.
        # So, it will be plain text. This is fine as per current rules.
        self.assertEqual(self.run_script(md), expected)

        # What if the format is `*text* then more text`
        md2 = "*header* then more text"
        # This also should not be a header by the current regex.
        expected2 = [{"tag": "p", "children": ["*header* then more text"]}]
        self.assertEqual(self.run_script(md2), expected2)


if __name__ == "__main__":
    # Need to add sys to path for SCRIPT_PATH to be found by the subprocess
    # if markdown_to_telegraph.py is in the same directory.
    # The script path is already absolute.
    import sys # Import sys for sys.executable
    unittest.main()
```

A note on `test_header_section_title`:
The prompt mentions: `Note: The previous report for markdown_to_telegraph.py mentioned that the content of headers is also parsed for inline styles. If 📝 *Frase do dia:* is parsed as {"tag": "h4", "children": ["📝 ", {"tag": "em", "children": ["Frase do dia:"]}]} that's also acceptable...`
My `markdown_to_telegraph.py` combines the prefix and the content within asterisks, and *then* calls `parse_inline_formatting` on that combined string.
So for an input like `📝 *_Test Header:_*`, the combined string for `parse_inline_formatting` would be `📝 _Test Header:_`.
`parse_inline_formatting("📝 _Test Header:_")` would return `["📝 ", {"tag": "em", "children": ["Test Header:"]}]`.
So, `expected3` in `test_header_section_title` reflects this.
For `📝 *Test Header:*`, the combined string is `📝 Test Header:`. `parse_inline_formatting` on this returns `["📝 Test Header:"]` since there's no further inline markdown. This matches `expected1`. This is consistent.

Added a `setUpClass` to chmod the script, as it's a common CI/CD step that might be missed locally.
Used `sys.executable` to call the script, which is good practice when using `subprocess` with Python scripts.
Added more specific test cases for nested inline formatting (`test_link_with_italic_text`, `test_italic_with_code_and_link`) and edge cases for headers/lists.
The `run_script` helper now prints stderr from the script if it fails or returns non-JSON output, which will help in debugging failures.
The test `test_header_like_text_not_a_header` verifies that the header regex is not too greedy.
The test `test_empty_lines_between_list_items` verifies the current behavior for empty lines within lists.
The script looks fairly complete.Okay, I've created the `test_markdown_to_telegraph.py` script.

Here's a summary of the structure and features:

1.  **Imports**: `unittest`, `subprocess`, `json`, `os`, `sys`.
2.  **SCRIPT_PATH**: Determined dynamically to locate `markdown_to_telegraph.py` in the same directory as the test script.
3.  **TestMarkdownToTelegraph Class**: Inherits from `unittest.TestCase`.
    *   **`setUpClass(cls)`**: A class method to `chmod +x` the `markdown_to_telegraph.py` script. This ensures it's executable when `subprocess` tries to run it.
    *   **`run_script(self, input_markdown)`**: A helper method to:
        *   Execute `markdown_to_telegraph.py` using `subprocess.run()`. It uses `sys.executable` to ensure the correct Python interpreter runs the script.
        *   Pass `input_markdown` to the script's `stdin`.
        *   Capture `stdout` and `stderr`.
        *   If the script exits with a non-zero code, the test fails, printing the script's `stderr`.
        *   Parse the `stdout` as JSON. If JSON decoding fails, the test fails, printing the `stdout`.
        *   Return the parsed JSON object.
    *   **Test Methods**: Each test case from the prompt is implemented as a method (e.g., `test_empty_input`, `test_simple_paragraph`, `test_header_section_title`, etc.).
        *   Each test method defines a sample Markdown input string (`md`) and the `expected` JSON output.
        *   It calls `self.run_script(md)` and asserts equality with `self.assertEqual()`.
        *   Specific test cases from the prompt have been included:
            *   Empty input
            *   Simple and multiple paragraphs
            *   Headers (with and without emoji, and with internal inline formatting like `📝 *_Test Header:_*`)
            *   Italic, code spans, and links within paragraphs
            *   Unordered lists (simple and with mixed inline formatting)
            *   Recursive inline parsing for list items (e.g., `_Item [link](url)_`)
            *   Mixed content (paragraphs and lists)
            *   The "Frase do Dia" example from `hcnews.sh`
            *   Complex nested inline formatting in paragraphs (e.g., `_italic `code` [link](url)_`)
            *   Links with italic text and vice-versa.
            *   Behavior of empty lines between list items (results in separate lists).
            *   Lines that might look like headers but aren't, due to surrounding text, to test regex precision.

The test suite is comprehensive and covers the specified requirements, including edge cases and nested structures based on the capabilities of the `markdown_to_telegraph.py` script (especially its recursive inline parsing).
The use of `sys.executable` and `chmod` in `setUpClass` promotes reliability in various execution environments. Error reporting in `run_script` is also enhanced for easier debugging.

Final check on file path for `SCRIPT_PATH` and python interpreter for `subprocess.run`.
`SCRIPT_PATH = os.path.join(os.path.dirname(__file__), "markdown_to_telegraph.py")` is robust for locating the script.
`[sys.executable, SCRIPT_PATH]` is the correct way to invoke the script.

The tests should provide good coverage for `markdown_to_telegraph.py`.
