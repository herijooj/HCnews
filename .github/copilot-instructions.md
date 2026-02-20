# HCnews Copilot Instructions

## Project Overview
HCnews is a daily news aggregator that generates a comprehensive text-based news digest. Written primarily in Bash with Python components for utilities, it fetches data from RSS feeds, APIs, and local sources, then formats everything into a unified daily newspaper output.

## Architecture & Data Flow

### 1. Hybrid Structure
- **Bash Layer (`hcnews.sh`, `scripts/`)**: Contains the core business logic. Each feature (weather, news, horoscope) is a separate Bash script that fetches data, handles caching, and formats the output.
- **Library Layer (`scripts/lib/`)**: Shared utilities for orchestration, background jobs, caching, and the component registry (`hc_component_*` functions).
- **Python Layer (`utils/`)**: Utility scripts for scheduling and RSS processing.

### 2. Data Flow
1.  **Invocation**: `hcnews.sh` or `build_daily.sh` is run.
2.  **Execution**: Script checks its local file-based cache (`data/cache/`).
    -   *Hit*: Returns cached content.
    -   *Miss*: Fetches data (curl/wget), processes it (jq/pup/xmlstarlet), caches it, and returns it.
3.  **Output**: Formatted text (often with emojis) to `stdout`.

## Key Conventions

### Component Pattern
- Each feature is implemented as a `hc_component_<name>` function (e.g., `hc_component_weather`, `hc_component_rss`).
- Components are registered in `scripts/lib/components.sh` via the `HCNEWS_COMPONENT_REGISTRY` associative array.
- Individual feature scripts live in `scripts/` (e.g., `scripts/weather.sh`, `scripts/rss.sh`).

### Caching Strategy
- **Responsibility**: Caching is strictly the responsibility of the **Bash scripts**.
- **Location**: Cache files are stored in `data/cache/<component>/`.
- **Bypass cache**: Use `--no-cache` to disable caching, or `--force` to force a refresh.

### Script Execution
- **Method**: Scripts output formatted text to `stdout`. Errors go to `stderr`.
- **Pathing**: Scripts are located in `scripts/` or the root `hcnews.sh`.

### Bash Scripting Patterns
- **Sourcing**: `hcnews.sh` sources individual scripts from `scripts/`.
- **Dependencies**: Scripts rely heavily on CLI tools: `jq` (JSON), `pup` (HTML), `xmlstarlet` (XML), `curl`, `date`.

### Configuration
- **`config.sh`**: Default settings (RSS feeds, city, cache dir, API key env-var names). Copy to `config.local.sh` to override without modifying tracked files.
- **`.secrets`** (untracked): Holds `openweathermap_API_KEY` and `CoinMarketCap_API_KEY`. See `.secrets.example`.
- Environment variables (e.g., `HCNEWS_CITY`, `HCNEWS_FEEDS_PRIMARY`) override `config.sh` defaults.

## Development Workflow

### Prerequisites
Ensure the following system tools are installed (see `README.md` or `default.nix`):
- `xmlstarlet`, `pup`, `jq`, `curl`, `shellcheck`, `shfmt`

### Linting
```bash
bash scripts/lint.sh   # shellcheck on all .sh files
```
The CI workflow also runs `shfmt -d` on changed shell files to enforce formatting.

### Testing & Debugging
1.  **Test individual scripts** directly in the terminal to verify output and formatting:
    ```bash
    ./scripts/weather.sh --force
    ```
2.  **Run full CLI build**:
    ```bash
    ./hcnews.sh
    ```
3.  **Run daily build** (generates `public/news_*.out` files):
    ```bash
    ./build_daily.sh
    ```

### CLI Flags
| Flag | Description |
|------|-------------|
| `-h`, `--help` | Show help |
| `-s`, `--silent` | Suppress progress output |
| `-sa`, `--saints` | Show verbose saints description |
| `-n`, `--news` | Show news with shortened links |
| `-t`, `--timing` | Show per-function execution timing |
| `--no-cache` | Disable caching for this run |
| `--force` | Force-refresh cache for this run |
| `--full-url` | Use full URLs instead of shortened links (web builds) |

## Critical Files
- `hcnews.sh`: Main entry point; sources all scripts, handles CLI args, orchestrates output.
- `build_daily.sh`: Generates separate `public/news_*.out` files for different content types.
- `config.sh`: Default configuration (copy to `config.local.sh` to customise).
- `scripts/lib/common.sh`: Shared helper utilities.
- `scripts/lib/components.sh`: Component registry mapping names to `hc_component_*` functions.
- `scripts/lib/orchestrator.sh`: Parallel fetch orchestration logic.
- `scripts/lib/jobs.sh`: Background job management utilities.
- `scripts/`: Feature modules, each implementing one `hc_component_*` function.
