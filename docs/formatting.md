# HCNews — WhatsApp Text Constraints (Consumer Apps + Web + Business API)

## 1) Scope and terminology

**WhatsApp has two materially different “text pipes”:**

1. **Consumer clients**: WhatsApp on **Android / iOS / Web / Desktop** (human typing or WhatsApp Web automation).
2. **WhatsApp Business Platform APIs**: Cloud API / partner BSPs (programmatic sending).

Many limits and rendering behaviors differ between these two. This document focuses on **text-message constraints** (not media).

---

## 2) Message size limits (hard limits)

### 2.1 Consumer clients (Android / iOS / Web / Desktop)
- **Max message length** is widely reported as **65,536 characters** per message.[^limit-consumer]
- “Character” counting is implementation-defined; emojis and some Unicode sequences may count as more than 1 unit depending on how the client/server counts. Treat this as a **hard cap that can be hit unexpectedly** when using many emojis/combining marks.

### 2.2 WhatsApp Business Platform API (Cloud API / BSPs)
- **Max text body length: 4,096 characters** per message.[^limit-api]
- This limit is usually enforced by API validation and/or BSP gateways.

**Implication:** if HCNews is ever sent through the Business Platform (now or later), long editions must be **split into multiple messages**.

---

## 3) Rendering constraints (no fixed “columns”)

### 3.1 There is no stable “characters-per-line” rule
WhatsApp does **not** provide a fixed-width layout. Line breaks depend on:
- device screen width (and user font scaling / accessibility settings),
- the platform font (Android vs iOS vs Web/desktop),
- emoji glyph widths (which differ by platform),
- whether the line contains monospace formatting.

**Constraint:** any layout that depends on exact alignment (tables made of spaces, ASCII art columns, progress bars built from repeated characters, etc.) will drift across clients.

### 3.2 Platform differences you must assume
- **Android vs iOS**: different system fonts and emoji sets → different line wraps and perceived spacing.
- **WhatsApp Web/Desktop**: different fonts again (browser/OS dependent) → line wraps can differ from both mobile platforms.
- **Emoji sequences** (skin tones, ZWJ family emojis, flags) are especially likely to change line wrapping.

**Constraint:** treat all content as *responsive text*; design for graceful wrapping.

---

## 4) Newlines, whitespace, and copying behavior

### 4.1 Newlines
- WhatsApp preserves **explicit newlines** you insert.
- When a message is long, some clients may show a condensed preview (notifications, chat list snippet) with different truncation.

### 4.2 Multiple spaces
- Multiple consecutive spaces can be visually unstable (wrapping + font differences).
- Some clients/features may normalize whitespace in previews, even if the message bubble preserves it.

**Constraint:** do not rely on sequences of spaces for alignment.

### 4.3 Copy/paste and automation
- WhatsApp Web automation stacks can introduce subtle differences (e.g., normalization of newlines, trimming). Treat final rendering as the source of truth; test the actual send path.

---

## 5) WhatsApp “markdown-like” formatting (actual supported syntax)

WhatsApp supports a **limited markup**, not full Markdown.[^formatting]

### 5.1 Inline text styles
- **Bold**: `*text*`
- *Italic*: `_text_`
- ~~Strikethrough~~: `~text~`
- `Inline code`: `` `text` ``
- Monospace: <code>```text```</code>

**Constraints:**
- This is not CommonMark/GFM. Features like headings (`#`), underline, markdown links (`[text](url)`), and tables are not supported.
- Nesting/overlapping styles is not specified; some combinations may work, but it is not reliable across all clients/versions.

### 5.2 Lists
- **Bulleted list**: start a line with `- ` or `* ` (symbol + space), e.g. `- item`.[^formatting]
- **Numbered list**: start a line with `1. ` (number + dot + space), e.g. `1. item`.[^formatting]

**Constraints:**
- Nested lists/indentation are not a formal feature; results vary by client and may degrade to plain text.

### 5.3 Block quote
- **Quote**: start a line with `> ` (greater-than + space).[^formatting]

### 5.4 Escaping literal markup characters
There is no universally reliable “escape” syntax comparable to Markdown backslash-escaping.
- Practical workaround: wrap literals in **inline code** (backticks) so `* _ ~` show as-is.

---

## 6) Links and previews

### 6.1 Link preview generation
- WhatsApp may generate a preview card for links, but preview behavior can vary by client and content.
- Previews can be **cached**; updating a page may not refresh the preview for previously shared URLs.[^preview-cache]

### 6.2 User privacy setting: disable link previews
- WhatsApp includes a setting to **disable link previews** (recipient-side behavior depends on their settings).[^disable-previews]

**Constraints:**
- Do not assume a preview will appear.
- Do not rely on preview images/titles to carry essential information; the URL text must be sufficient.

---

## 7) Constraints specifically relevant to layout-driven newsletters

### 7.1 Avoid “grid” constructs
- No tables via spaces.
- No fixed-width columns.
- No “progress bars” that assume equal character widths (unless you accept drift).

### 7.2 Keep semantic structure resilient
- Prefer: short lines, clear section headers, bullets, and explicit newlines.
- Assume any long line will wrap differently on Android/iOS/Web.

### 7.3 Monospace is not a silver bullet
- Monospace blocks improve alignment **within a client**, but fonts and wrapping behavior still differ across platforms (and may wrap or horizontally scroll depending on client/version).

---

## 8) QA checklist (minimum cross-client validation)

For every template change, validate on:
- Android phone (default font size + one larger accessibility size)
- iPhone (default font size + one larger accessibility size)
- WhatsApp Web (Chrome/Edge) on a typical desktop resolution

Check:
- section boundaries remain readable after wrapping,
- list markers render as intended,
- code/monospace blocks do not break layout,
- very long messages remain under the applicable character cap(s),
- links are readable without previews.

---

## 9) Known unknowns / items to empirically verify for your stack

These are constraints that vary by version/platform and should be measured in *your* distribution path:
- exact character-counting behavior for emojis/Unicode (what counts as “1 character” at the limit),
- whether monospace blocks wrap vs horizontally scroll on your target client versions,
- whether WhatsApp Web automation trims trailing spaces/newlines,
- link preview frequency when multiple URLs exist in a single message.

---

# Footnotes (sources)
[^limit-consumer]: Consumer client limit reported as 65,536 characters.
[^limit-api]: WhatsApp Business Platform text object body max length is 4,096 characters.
[^formatting]: WhatsApp-supported formatting shortcuts (bold/italic/strike/monospace, lists, quotes, inline code).
[^preview-cache]: Link previews may remain unchanged due to caching.
[^disable-previews]: WhatsApp setting to disable link previews.
