#!/usr/bin/env node
import { readFileSync, existsSync, mkdirSync, writeFileSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import { spawn } from 'child_process';
import pino from 'pino';
import makeWASocket, {
  useMultiFileAuthState,
  fetchLatestBaileysVersion,
  makeCacheableSignalKeyStore,
  DisconnectReason,
  DEFAULT_CONNECTION_CONFIG
} from 'baileys';

const __dirname = dirname(fileURLToPath(import.meta.url));
const HCNEWS_PATH = process.env.HCNEWS_PATH || join(__dirname, '..');
const AUTH_DIR = process.env.AUTH_DIR || join(__dirname, 'baileys_auth');
const LOG_FILE = process.env.LOG_FILE || '/var/lib/hcnews-whatsapp/send.log';
const WHATSAPP_CHANNEL_ID = process.env.WHATSAPP_CHANNEL_ID || '120363206957534786@newsletter';
const DRY_RUN = process.env.DRY_RUN === 'true';

const logger = pino({
  level: 'info',
  transport: {
    targets: [
      {
        target: 'pino/file',
        options: { destination: LOG_FILE },
        level: 'info'
      },
      {
        target: 'pino-pretty',
        options: { colorize: true },
        level: 'info'
      }
    ]
  }
});

function log(level, message) {
  const timestamp = new Date().toISOString();
  const logLine = `[${timestamp}] [${level}] ${message}`;
  console.log(logLine);
}

function logInfo(message) { log('INFO', message); }
function logWarn(message) { log('WARN', message); }
function logError(message) { log('ERROR', message); }
function logDebug(message) { log('DEBUG', message); }

function generateContent() {
  return new Promise((resolve, reject) => {
    logInfo('Generating HCNews content...');

    const hcnewsScript = join(HCNEWS_PATH, 'hcnews.sh');

    if (!existsSync(hcnewsScript)) {
      reject(new Error(`hcnews.sh not found at ${hcnewsScript}`));
      return;
    }

    const proc = spawn('bash', [hcnewsScript], {
      cwd: HCNEWS_PATH,
      env: { ...process.env }
    });

    let stdout = '';
    let stderr = '';

    proc.stdout.on('data', (data) => {
      stdout += data.toString();
    });

    proc.stderr.on('data', (data) => {
      stderr += data.toString();
    });

    proc.on('close', (code) => {
      if (code !== 0) {
        logWarn(`hcnews.sh stderr: ${stderr}`);
        reject(new Error(`hcnews.sh exited with code ${code}`));
        return;
      }

      if (!stdout || stdout.trim().length === 0) {
        reject(new Error('hcnews.sh produced empty content'));
        return;
      }

      const lineCount = stdout.split('\n').filter(line => line.trim()).length;
      if (lineCount < 10) {
        logWarn(`Content seems short (${lineCount} lines), proceeding anyway`);
      }

      logInfo(`Generated content: ${lineCount} lines`);
      resolve(stdout);
    });

    proc.on('error', (err) => {
      reject(new Error(`Failed to execute hcnews.sh: ${err.message}`));
    });
  });
}

async function sendMessage(sock, jid, text) {
  if (DRY_RUN) {
    logInfo(`[DRY RUN] Would send message to ${jid}`);
    logInfo(`[DRY RUN] Message length: ${text.length} characters`);
    return { id: 'dry-run-' + Date.now() };
  }

  try {
    const result = await sock.sendMessage(jid, { text });
    logInfo(`Message sent successfully to ${jid}`);
    logInfo(`Message ID: ${result.key?.id || 'unknown'}`);
    return result;
  } catch (error) {
    throw new Error(`Failed to send message: ${error.message}`);
  }
}

async function waitForConnection(sock, maxAttempts = 30, intervalMs = 5000) {
  logInfo('Waiting for WhatsApp connection...');

  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    if (sock.ws.readyState === 0 || sock.ws.readyState === 1) {
      const connectionState = sock.ws.readyState === 0 ? 'CONNECTING' : 'OPEN';
      logInfo(`WebSocket state: ${connectionState} (attempt ${attempt}/${maxAttempts})`);
    }

    if (sock.user) {
      logInfo(`Connected as ${sock.user.id || sock.user.name || 'unknown'}`);
      return true;
    }

    await new Promise(resolve => setTimeout(resolve, intervalMs));
  }

  throw new Error('Connection did not establish within timeout');
}

async function main() {
  logInfo('=== HCNews WhatsApp Worker (Baileys) starting ===');

  if (DRY_RUN) {
    logInfo('Running in DRY RUN mode - no messages will be sent');
  }

  if (!existsSync(AUTH_DIR)) {
    mkdirSync(AUTH_DIR, { recursive: true });
    logInfo(`Created auth directory: ${AUTH_DIR}`);
  }

  logInfo(`Auth directory: ${AUTH_DIR}`);
  logInfo(`HCNews path: ${HCNEWS_PATH}`);
  logInfo(`Target channel: ${WHATSAPP_CHANNEL_ID}`);

  let content;
  try {
    content = await generateContent();
  } catch (error) {
    logError(`Content generation failed: ${error.message}`);
    process.exit(1);
  }

  let sock;
  try {
    logInfo('Initializing Baileys socket...');

    const { state, saveCreds } = await useMultiFileAuthState(AUTH_DIR);
    const { version } = await fetchLatestBaileysVersion();

    logInfo(`Using Baileys version: ${version.join('.')}`);

    sock = makeWASocket({
      version,
      logger,
      auth: {
        creds: state.creds,
        keys: makeCacheableSignalKeyStore(state.keys, logger),
      },
      msgRetryCounterCache: {
        get: (key) => null,
        set: () => {},
        delete: () => {},
      },
      getMessage: async () => undefined,
      markOnlineOnConnect: false,
      shouldIgnoreJid: (jid) => {
        return jid?.endsWith('@newsletter') || false;
      },
    });

    sock.ev.on('creds.update', saveCreds);

    sock.ev.on('connection.update', async (update) => {
      const { connection, lastDisconnect, qr } = update;

      if (qr) {
        logInfo('QR Code received - scan with WhatsApp to authenticate');
        logInfo('QR Code:', qr);
      }

      if (connection === 'close') {
        const shouldReconnect = lastDisconnect?.error?.output?.statusCode !== DisconnectReason.loggedOut;
        logWarn(`Connection closed: ${lastDisconnect?.error?.message || 'unknown'}`);
        logWarn(`Reconnecting: ${shouldReconnect}`);
      }

      if (connection === 'open') {
        logInfo('WhatsApp connection established');
      }
    });

    await waitForConnection(sock, 60, 5000);

  } catch (error) {
    logError(`Failed to initialize Baileys: ${error.message}`);
    process.exit(1);
  }

  try {
    await sendMessage(sock, WHATSAPP_CHANNEL_ID, content);
    logInfo('=== HCNews WhatsApp Worker completed successfully ===');
    process.exit(0);
  } catch (error) {
    logError(`Failed to send message: ${error.message}`);
    process.exit(1);
  }
}

main().catch((error) => {
  logError(`Unhandled error: ${error.message}`);
  process.exit(1);
});
