---
description: Create a new data source script following HCNews patterns
---

# Add Data Source

Create a new data source module for HCNews following the established patterns.

## When to use
When you need to add a new data source (API, RSS feed, scraping source) to the daily news build.

## How to use

Provide the following information:
1. **Script name** (e.g., `sports.sh`, `lottery.sh`)
2. **Data source URL** (API endpoint or page to scrape)
3. **Data format** (JSON, XML, HTML)
4. **Field(s) to extract** (what data to include in output)
5. **Cache TTL** (how often to refresh, in seconds)

## Output

This skill will:
1. Create `scripts/{name}.sh` following the standard template
2. Add the TTL entry to `scripts/lib/common.sh` (in `HCNEWS_CACHE_TTL` associative array)
3. Add the script sourcing line to `hcnews.sh` (in the main case statement)
4. Add the script call to `build_daily.sh` (in the parallel fetch section)
5. Create the cache subdirectory in `data/cache/`

## Example

```
Skill: add-data-source
Script name: sports.sh
URL: https://api.example.com/sports
Format: JSON
Field: headlines
TTL: 7200 (2 hours)
```

## Pattern followed

The generated script will:
- Source `common.sh` and `jobs.sh` from `lib/`
- Use `hcnews_parse_args` for argument handling
- Check cache with `hcnews_check_cache` and `hcnews_read_cache`
- Fetch with `curl -s`
- Process with `jq` (JSON) or `pup`/`xmlstarlet` (HTML/XML)
- Write cache with `hcnews_write_cache`
- Output the result

## Common TTL values

| Frequency | TTL (seconds) |
|-----------|---------------|
| Hourly    | 3600          |
| 2 hours   | 7200          |
| 6 hours   | 21600         |
| 12 hours  | 43200         |
| Daily     | 82800         |

## Notes

- Script name must end in `.sh`
- Output should be plain text (UTF-8), not JSON
- For multiple fields, concatenate with newlines
- Use `echo` for output (not `printf`)
