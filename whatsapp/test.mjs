#!/usr/bin/env node
import { existsSync, mkdirSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';
import pino from 'pino';
import makeWASocket, {
  useMultiFileAuthState,
  fetchLatestBaileysVersion,
  makeCacheableSignalKeyStore,
  DisconnectReason,
  isJidNewsletter
} from 'baileys';

const __dirname = dirname(fileURLToPath(import.meta.url));
const AUTH_DIR = join(__dirname, 'baileys_auth');

const logger = pino({
  level: 'info',
  transport: {
    target: 'pino-pretty',
    options: { colorize: true }
  }
});

const TARGET = process.argv[2] || '554184501924@s.whatsapp.net';

async function main() {
  console.log(`=== Baileys Test ===`);
  console.log(`Sending test message to: ${TARGET}`);
  console.log(`Auth dir: ${AUTH_DIR}`);

  if (!existsSync(AUTH_DIR)) {
    console.error('Auth directory not found. Run auth.mjs first.');
    process.exit(1);
  }

  const { state, saveCreds } = await useMultiFileAuthState(AUTH_DIR);
  const { version } = await fetchLatestBaileysVersion();

  console.log(`Using Baileys version: ${version.join('.')}`);

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
    markOnlineOnConnect: false,
  });

  sock.ev.on('creds.update', saveCreds);

  sock.ev.on('connection.update', (update) => {
    const { connection, lastDisconnect } = update;
    console.log(`Connection: ${connection}`);

    if (connection === 'close') {
      console.log(`Disconnected: ${lastDisconnect?.error?.message}`);
    }
  });

  await new Promise(resolve => setTimeout(resolve, 5000));

  const isNews = isJidNewsletter(TARGET);
  console.log(`Is newsletter: ${isNews}`);

  console.log(`Sending message...`);
  try {
    const result = await sock.sendMessage(TARGET, {
      text: `Test from Baileys at ${new Date().toISOString()}`
    });
    console.log(`Message sent! ID: ${result.key?.id}`);
  } catch (error) {
    console.error(`Failed: ${error.message}`);
  }

  await new Promise(resolve => setTimeout(resolve, 3000));
  console.log('Done');
  process.exit(0);
}

main().catch(console.error);
