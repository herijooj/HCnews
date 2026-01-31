#!/usr/bin/env node
import { existsSync, mkdirSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';
import pino from 'pino';
import QRCode from 'qrcode';
import makeWASocket, {
  useMultiFileAuthState,
  fetchLatestBaileysVersion,
  makeCacheableSignalKeyStore,
  DEFAULT_CONNECTION_CONFIG
} from 'baileys';

const __dirname = dirname(fileURLToPath(import.meta.url));
const AUTH_DIR = process.env.AUTH_DIR || join(__dirname, 'baileys_auth');

const logger = pino({
  level: 'info',
  transport: {
    target: 'pino-pretty',
    options: { colorize: true }
  }
});

async function displayQR(qrData) {
  try {
    const qrAscii = await QRCode.toString(qrData, { type: 'terminal', small: true });
    console.log('\n');
    console.log('========================================');
    console.log('  Scan with WhatsApp:');
    console.log('========================================');
    console.log(qrAscii);
    console.log('========================================\n');
  } catch (err) {
    console.log('\n');
    console.log('========================================');
    console.log('QR Code (copy to QR generator if needed):');
    console.log('========================================');
    console.log(qrData);
    console.log('========================================\n');
  }
}

function log(level, message) {
  console.log(`[${level}] ${message}`);
}

async function main() {
  console.log('=== HCNews WhatsApp Authentication ===');
  console.log(`Auth directory: ${AUTH_DIR}`);

  if (!existsSync(AUTH_DIR)) {
    mkdirSync(AUTH_DIR, { recursive: true });
    console.log(`Created auth directory: ${AUTH_DIR}`);
  }

  const { state, saveCreds } = await useMultiFileAuthState(AUTH_DIR);
  const { version, isLatest } = await fetchLatestBaileysVersion();

  console.log(`Using Baileys version: ${version.join('.')} (latest: ${isLatest})`);

  const sock = makeWASocket({
    version,
    logger,
    auth: {
      creds: state.creds,
      keys: makeCacheableSignalKeyStore(state.keys, logger),
    },
    msgRetryCounterCache: {
      get: () => null,
      set: () => {},
      delete: () => {},
    },
    getMessage: async () => undefined,
  });

  sock.ev.on('creds.update', saveCreds);

  sock.ev.on('connection.update', async (update) => {
    const { connection, lastDisconnect, qr } = update;

    if (qr) {
      await displayQR(qr);
    }

    if (connection === 'open') {
      console.log('\n');
      console.log('========================================');
      console.log('Successfully authenticated with WhatsApp!');
      console.log('========================================');
      console.log(`Connected as: ${sock.user?.id || 'unknown'}`);
      console.log('========================================\n');
      console.log('You can now run the worker to send messages.');
      process.exit(0);
    }

    if (connection === 'close') {
      const shouldReconnect = lastDisconnect?.error?.output?.statusCode !== 401;
      if (!shouldReconnect) {
        console.log('Authentication failed or was logged out.');
        process.exit(1);
      }
    }
  });

  console.log('Waiting for QR code...');
  console.log('Please scan the QR code with your WhatsApp app.');
  console.log('On WhatsApp: Settings > Linked Devices > Link a Device\n');
}

main().catch((error) => {
  console.error(`Error: ${error.message}`);
  process.exit(1);
});
