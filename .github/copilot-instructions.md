# HCnews Copilot Instructions

## Project Overview
HCnews is a hybrid Python/Bash application that serves as a daily news aggregator and Telegram bot. It combines a Python-based Telegram interface with a robust Bash-scripting backend for data fetching, processing, and formatting.

## Architecture & Data Flow

### 1. Hybrid Structure
- **Python Layer (`telegramHandler.py`, `handlers/`)**: Handles user interaction, menus, and scheduling. It acts as a controller that invokes Bash scripts to retrieve content.
- **Bash Layer (`hcnews.sh`, `scripts/`)**: Contains the core business logic. Each feature (weather, news, horoscope) is a separate Bash script that fetches data, handles caching, and formats the output.

### 2. Data Flow
1.  **Request**: User interacts with Telegram Bot.
2.  **Invocation**: Python handler calls a Bash script (e.g., `hcnews.sh` or `scripts/weather.sh`) via `subprocess`.
3.  **Execution**: Bash script checks its local file-based cache (`data/cache/`).
    -   *Hit*: Returns cached content.
    -   *Miss*: Fetches data (curl/wget), processes it (jq/pup/xmlstarlet), caches it, and returns it.
4.  **Response**: Python captures `stdout` and sends it to the user.

## Key Conventions

### Caching Strategy
- **Responsibility**: Caching is strictly the responsibility of the **Bash scripts**.
- **Location**: Cache files are stored in `data/cache/<component>/`.
- **Python Role**: Python code should **NOT** implement caching for content retrieved from scripts. It should rely entirely on the script's output.
- **Force Refresh**: Python can request a fresh fetch by passing the `--force` flag to the scripts.

### Script Execution
- **Method**: Use `subprocess.run` with `capture_output=True` and `text=True`.
- **Pathing**: Scripts are located in `scripts/` or the root `hcnews.sh`. Ensure paths are resolved correctly (use `config.constants.SCRIPT_PATHS`).
- **Output**: Scripts output formatted text (often with emojis) to `stdout`. Errors go to `stderr`.

### Bash Scripting Patterns
- **Sourcing**: `hcnews.sh` sources individual scripts from `scripts/`.
- **Dependencies**: Scripts rely heavily on CLI tools: `jq` (JSON), `pup` (HTML), `xmlstarlet` (XML), `curl`, `date`.
- **Argument Handling**: Scripts must handle flags like `--force`, `--no-cache`, and `--telegram` (to adjust formatting for Telegram).

## Development Workflow

### Prerequisites
Ensure the following system tools are installed (see `README.md` or `default.nix`):
- `xmlstarlet`, `pup`, `jq`, `curl`

### Testing & Debugging
1.  **Test Scripts First**: Before integrating with Python, run the Bash script directly in the terminal to verify output and formatting.
    ```bash
    ./scripts/weather.sh --force
    ```
2.  **Run Bot**:
    ```bash
    python telegramHandler.py
    ```
3.  **Logs**: Python logging is configured in `telegramHandler.py`. Check console output for `subprocess` errors.

## Critical Files
- `hcnews.sh`: Main entry point for generating the full news report.
- `telegramHandler.py`: Main entry point for the Telegram bot.
- `handlers/news_handler.py`: Example of how Python invokes `hcnews.sh`.
- `scripts/weather.sh`: Example of a component script with caching and argument parsing.
