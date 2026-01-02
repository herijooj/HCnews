# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

HCNews is a daily news aggregator that generates a comprehensive text-based news digest. Inspired by JRMUNEWS, it's written primarily in Bash with Python components for Telegram bot integration. The project fetches data from RSS feeds, APIs, and local sources, then formats everything into a unified daily newspaper output.

## Common Commands

```bash
# Run the main news generator (outputs to terminal)
./hcnews.sh

# Build all output variants (tudo, noticias, horoscopo, weather)
./build_daily.sh

# Refresh all cached data
./refresh_cache.sh

# Run with timing info
./hcnews.sh --timing

# Force refresh cache
./hcnews.sh --force

# Disable cache for a run
./hcnews.sh --no-cache
```

## Architecture

### Entry Points
- **hcnews.sh** (`hcnews.sh:1`): Main orchestrator. Sources all feature scripts, manages parallel background jobs, and renders final output.
- **build_daily.sh** (`build_daily.sh:1`): Generates separate output files for different content types.

### Script Organization (`scripts/`)
- **lib/common.sh** (`scripts/lib/common.sh:1`): Core library with caching, date utilities, HTML entity decoding, and argument parsing. All scripts source this.
- **lib/jobs.sh** (`scripts/lib/jobs.sh:1`): Background job management using temp files in `/dev/shm` or `/tmp`.
- **Feature modules**: Each `*.sh` file exports a `write_*` function (e.g., `write_weather`, `write_news`).

### Data Flow
1. `hcnews.sh` sources `lib/common.sh` and all feature scripts
2. Initializes parallel job system and timing
3. `start_network_jobs()` launches background fetches (weather, RSS, etc.)
4. `run_local_jobs()` runs synchronous local operations (header, holidays)
5. `collect_network_data()` blocks until all background jobs complete
6. `render_output()` assembles content sections in order
7. `footer()` adds timing and branding

### Caching System
- **Location**: `data/cache/<component>/`
- **TTL Configuration**: Centralized in `common.sh:57` as `HCNEWS_CACHE_TTL` associative array
- **Key Functions**: `hcnews_check_cache()`, `hcnews_read_cache()`, `hcnews_write_cache()`
- **Pattern**: Each script checks cache first; on miss, fetches → caches → returns

### Parallel Execution
- Uses `jobs.sh` with subshells and temp files for background operations
- All network I/O runs in parallel to minimize total execution time
- Output captured in temp files, read synchronously after all jobs complete

## Key Conventions

### Script Structure
```bash
#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
hcnews_parse_args "$@"
# ... script-specific logic ...
```

### Writing New Modules
1. Create `scripts/<module>.sh`
2. Source `lib/common.sh` for caching utilities
3. Define `write_<module>() { ... }` function
4. Export output to stdout
5. Use `hcnews_check_cache()` with component name matching `HCNEWS_CACHE_TTL`
6. Add to `hcnews.sh` source list and `start_network_jobs()` orchestration

### Environment Variables
- `openweathermap_API_KEY`: Required for weather data
- `_HCNEWS_USE_CACHE`: Boolean (default true)
- `_HCNEWS_FORCE_REFRESH`: Boolean (default false)
- `hc_full_url`: Use full URLs vs shortened (for web builds)

### Date Handling
- `date_format`: `YYYYMMDD` format for cache filenames
- Main script pre-computes: `weekday`, `month`, `day`, `year`, `start_time`
- Scripts should use cached values from `common.sh` helpers to avoid subprocess spawning

## Dependencies
- `xmlstarlet`, `pup`, `jq`, `curl`, `date` (core CLI tools)
- `openweathermap_API_KEY` environment variable for weather
- Python 3 + `python-telegram-bot` for Telegram bot
- `nix` flake available for reproducible development environment
