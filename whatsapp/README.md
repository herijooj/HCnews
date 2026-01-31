# HCNews WhatsApp Integration (Baileys)

This folder contains the WhatsApp integration for HCNews, now using [Baileys](https://github.com/WhiskeySockets/Baileys) instead of WAHA.

## Migration from WAHA to Baileys

### What Changed

- **Before**: Used WAHA (WhatsApp HTTP API) running as a Docker container on hc-m91p
- **After**: Uses Baileys (Node.js library) running directly on hc-m91p

### Key Differences

| Aspect | WAHA | Baileys |
|--------|------|---------|
| Architecture | HTTP REST API | WebSocket + Node.js library |
| Auth | Dashboard QR code | Local auth files |
| Dependencies | Docker | Node.js 18+ |
| Message sending | `curl` to API | `sock.sendMessage()` function |

## Setup

### 1. Install Node.js Dependencies

```bash
cd /home/hc/Documentos/HCnews/whatsapp
npm install
```

### 2. Authenticate with WhatsApp

Run the authentication script to generate the QR code:

```bash
cd /home/hc/Documentos/HCnews/whatsapp
node auth.mjs
```

Scan the QR code with WhatsApp:
1. Open WhatsApp on your phone
2. Go to Settings > Linked Devices > Link a Device

### 3. Test the Worker

```bash
# Dry run (no messages sent)
cd /home/hc/Documentos/HCnews/whatsapp
DRY_RUN=true node worker.mjs

# Or via the bash wrapper
./worker.sh --dry-run
```

## Architecture

```
r-h3 (orchestrator, always-on)
    |
    | SSH
    v
hc-m91p (worker, intermittent)
    |
    | runs
    v
Baileys (Node.js library)
    |
    | connects via WebSocket
    v
WhatsApp Servers
```

## Files

- `config.sh` - Configuration (host, channel ID, paths)
- `worker.sh` - Bash wrapper that ensures Node.js deps and runs the worker
- `worker.mjs` - Main Baileys worker (Node.js, ESM)
- `auth.mjs` - Authentication script for initial QR code pairing
- `package.json` - Node.js dependencies
- `orchestrator.sh` - Runs on r-h3, wakes hc-m91p via WoL, runs worker via SSH

## Configuration

Set these environment variables in `config.local.sh`:

```bash
# Auth directory (where Baileys stores session files)
BAILEYS_AUTH_DIR="${HOME}/.config/hcnews-whatsapp/baileys_auth"

# WhatsApp channel ID
WHATSAPP_CHANNEL_ID="120363206957534786@newsletter"

# Node.js path (if not in PATH)
NODE_PATH="/usr/bin/node"

# Debug mode
DEBUG="true"

# Dry run (no messages sent)
DRY_RUN="true"
```

## SSH Access

### hc-m91p (where the worker runs)

```bash
# Via Tailscale
ssh hc@hc-m91p.tail82a040.ts.net

# Via LAN
ssh hc@192.168.100.18
ssh hc@hc-m91p.home
```

### r-h3 (where the orchestrator runs)

```bash
# Via Tailscale
ssh hc@r-h3.tail82a040.ts.net

# Via LAN
ssh hc@192.168.100.14
ssh hc@r-h3.home

# As root
ssh root@r-h3.tail82a040.ts.net
```

## Troubleshooting

### Authentication Issues

If you get authentication errors:

1. Delete the auth directory:
   ```bash
   rm -rf /home/hc/Documentos/HCnews/whatsapp/baileys_auth
   ```

2. Re-authenticate:
   ```bash
   node auth.mjs
   ```

### Connection Issues

The worker will automatically retry on connection issues. Check logs at:
- `/var/lib/hcnews-whatsapp/send.log`

### QR Code Not Scanning

1. Make sure WhatsApp is updated
2. Try unlinking all devices first (Settings > Linked Devices)
3. Restart the auth script

## References

- [Baileys GitHub](https://github.com/WhiskeySockets/Baileys)
- [Baileys Wiki](https://baileys.wiki/)
- [Infrastructure Documentation](../docs/INFRASTRUCTURE.md)
- [Quick Access](../docs/QUICK_ACCESS.md)
