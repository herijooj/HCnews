# HCnews Copilot Instructions

## Project Overview
HCnews is a daily news aggregator that generates a comprehensive text-based news digest. Written primarily in Bash with Python components for utilities, it fetches data from RSS feeds, APIs, and local sources, then formats everything into a unified daily newspaper output.

## Architecture & Data Flow

### 1. Hybrid Structure
- **Bash Layer (`hcnews.sh`, `scripts/`)**: Contains the core business logic. Each feature (weather, news, horoscope) is a separate Bash script that fetches data, handles caching, and formats the output.
- **Python Layer (`utils/`)**: Utility scripts for scheduling and RSS processing.

### 2. Data Flow
1.  **Invocation**: `hcnews.sh` or `build_daily.sh` is run.
2.  **Execution**: Script checks its local file-based cache (`data/cache/`).
    -   *Hit*: Returns cached content.
    -   *Miss*: Fetches data (curl/wget), processes it (jq/pup/xmlstarlet), caches it, and returns it.
3.  **Output**: Formatted text (often with emojis) to `stdout`.

## Key Conventions

### Caching Strategy
- **Responsibility**: Caching is strictly the responsibility of the **Bash scripts**.
- **Location**: Cache files are stored in `data/cache/<component>/`.
- **Force Refresh**: Use the `--force` flag to bypass cache.

### Script Execution
- **Method**: Scripts output formatted text to `stdout`. Errors go to `stderr`.
- **Pathing**: Scripts are located in `scripts/` or the root `hcnews.sh`.

### Bash Scripting Patterns
- **Sourcing**: `hcnews.sh` sources individual scripts from `scripts/`.
- **Dependencies**: Scripts rely heavily on CLI tools: `jq` (JSON), `pup` (HTML), `xmlstarlet` (XML), `curl`, `date`.

## Development Workflow

### Prerequisites
Ensure the following system tools are installed (see `README.md` or `default.nix`):
- `xmlstarlet`, `pup`, `jq`, `curl`

### Testing & Debugging
1.  **Test Scripts**: Run the Bash script directly in the terminal to verify output and formatting.
    ```bash
    ./scripts/weather.sh --force
    ```
2.  **Run Full Build**:
    ```bash
    ./build_daily.sh
    ```

## Critical Files
- `hcnews.sh`: Main entry point for generating the full news report.
- `build_daily.sh`: Generates separate output files for different content types.
- `scripts/`: Feature modules with `write_*` functions.
