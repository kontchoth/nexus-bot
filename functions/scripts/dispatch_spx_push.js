#!/usr/bin/env node
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const admin = require('firebase-admin');

const LIST_PAYLOAD = 'spx_opportunities';
const OPPORTUNITY_PREFIX = 'spx_opportunity:';
const INVALID_TOKEN_CODES = new Set([
  'messaging/invalid-registration-token',
  'messaging/registration-token-not-registered',
]);

function usage() {
  const cmd = path.basename(process.argv[1] || 'dispatch_spx_push.js');
  console.log(`Usage:
  node scripts/${cmd} \\
    --user <firebase-uid> \\
    [--project <project-id>] \\
    [--service-account <path-to-json>] \\
    [--payload spx_opportunities|spx_opportunity:<id>] \\
    [--opportunity-id <id>] \\
    [--target spx_opportunities] \\
    [--title <title>] \\
    [--body <body>] \\
    [--platform android|ios|macos|web|windows|linux|fuchsia] \\
    [--dry-run true|false] \\
    [--prune-invalid true|false]

Notes:
  - One of --payload, --opportunity-id, or --target is required.
  - If --service-account is omitted, ADC is used (GOOGLE_APPLICATION_CREDENTIALS).
  - Default: --dry-run false, --prune-invalid true.
`);
}

function parseArgs(argv) {
  const args = {
    userId: '',
    projectId: '',
    serviceAccount: '',
    payload: '',
    opportunityId: '',
    target: '',
    title: 'SPX Opportunity Found',
    body: 'New SPX opportunity is available.',
    platform: '',
    dryRun: false,
    pruneInvalid: true,
  };

  for (let i = 0; i < argv.length; i += 1) {
    const key = argv[i];
    const next = argv[i + 1];
    switch (key) {
      case '--user':
        args.userId = (next || '').trim();
        i += 1;
        break;
      case '--project':
        args.projectId = (next || '').trim();
        i += 1;
        break;
      case '--service-account':
        args.serviceAccount = (next || '').trim();
        i += 1;
        break;
      case '--payload':
        args.payload = (next || '').trim();
        i += 1;
        break;
      case '--opportunity-id':
        args.opportunityId = (next || '').trim();
        i += 1;
        break;
      case '--target':
        args.target = (next || '').trim();
        i += 1;
        break;
      case '--title':
        args.title = (next || '').trim();
        i += 1;
        break;
      case '--body':
        args.body = (next || '').trim();
        i += 1;
        break;
      case '--platform':
        args.platform = (next || '').trim().toLowerCase();
        i += 1;
        break;
      case '--dry-run':
        args.dryRun = parseBool(next, false);
        i += 1;
        break;
      case '--prune-invalid':
        args.pruneInvalid = parseBool(next, true);
        i += 1;
        break;
      case '-h':
      case '--help':
        usage();
        process.exit(0);
        break;
      default:
        throw new Error(`Unknown argument: ${key}`);
    }
  }
  return args;
}

function parseBool(value, fallback) {
  const normalized = String(value || '').trim().toLowerCase();
  if (normalized === 'true') return true;
  if (normalized === 'false') return false;
  return fallback;
}

function normalizePayload(args) {
  if (args.payload) return args.payload;
  if (args.opportunityId) return `${OPPORTUNITY_PREFIX}${args.opportunityId}`;
  if (args.target.toLowerCase() === LIST_PAYLOAD) return LIST_PAYLOAD;
  return '';
}

function extractOpportunityId(payload) {
  if (!payload.startsWith(OPPORTUNITY_PREFIX)) return '';
  return payload.substring(OPPORTUNITY_PREFIX.length).trim();
}

function validateArgs(args) {
  if (!args.userId) {
    throw new Error('--user is required');
  }

  const payload = normalizePayload(args);
  if (!payload) {
    throw new Error('Provide one of --payload, --opportunity-id, or --target');
  }

  if (payload !== LIST_PAYLOAD && !payload.startsWith(OPPORTUNITY_PREFIX)) {
    throw new Error('Unsupported payload value');
  }

  return {
    ...args,
    payload,
    opportunityId: args.opportunityId || extractOpportunityId(payload),
  };
}

function initAdmin(args) {
  const config = {};
  if (args.projectId) config.projectId = args.projectId;

  if (args.serviceAccount) {
    const raw = fs.readFileSync(args.serviceAccount, 'utf8');
    const cert = JSON.parse(raw);
    config.credential = admin.credential.cert(cert);
  } else {
    config.credential = admin.credential.applicationDefault();
  }

  admin.initializeApp(config);
  return {
    db: admin.firestore(),
    messaging: admin.messaging(),
  };
}

async function loadEnabledTokens(db, args) {
  let query = db
    .collection('users')
    .doc(args.userId)
    .collection('push_tokens')
    .where('alertsEnabled', '==', true);

  if (args.platform) {
    query = query.where('platform', '==', args.platform);
  }

  const snapshot = await query.get();
  return snapshot.docs
    .map((doc) => {
      const data = doc.data() || {};
      const token = String(data.token || doc.id || '').trim();
      return { token, ref: doc.ref };
    })
    .filter((row) => row.token.length > 0);
}

async function dispatch({ db, messaging }, args) {
  const tokens = await loadEnabledTokens(db, args);
  const result = {
    userId: args.userId,
    payload: args.payload,
    platform: args.platform || null,
    attempted: tokens.length,
    success: 0,
    failed: 0,
    invalidTokensRemoved: 0,
    dryRun: args.dryRun,
    messageIds: [],
    errors: [],
  };

  if (tokens.length === 0) {
    return result;
  }

  const dataPayload = {
    payload: args.payload,
    title: args.title,
    body: args.body,
    ...(args.payload === LIST_PAYLOAD ? { target: LIST_PAYLOAD } : {}),
    ...(args.opportunityId ? { opportunityId: args.opportunityId } : {}),
  };

  await Promise.all(
    tokens.map(async (tokenEntry) => {
      try {
        const messageId = await messaging.send(
          {
            token: tokenEntry.token,
            notification: {
              title: args.title,
              body: args.body,
            },
            data: dataPayload,
          },
          args.dryRun
        );
        result.success += 1;
        result.messageIds.push(messageId);
      } catch (error) {
        const code = String(error && error.code ? error.code : 'unknown');
        const message = String(
          error && error.message ? error.message : 'unknown error'
        );
        result.failed += 1;
        result.errors.push({
          token: tokenEntry.token,
          code,
          message,
        });

        if (
          args.pruneInvalid &&
          !args.dryRun &&
          INVALID_TOKEN_CODES.has(code)
        ) {
          try {
            await tokenEntry.ref.delete();
            result.invalidTokensRemoved += 1;
          } catch (cleanupError) {
            result.errors.push({
              token: tokenEntry.token,
              code: 'cleanup_failed',
              message: String(cleanupError),
            });
          }
        }
      }
    })
  );

  return result;
}

async function main() {
  try {
    const parsed = parseArgs(process.argv.slice(2));
    const args = validateArgs(parsed);
    const ctx = initAdmin(args);
    const result = await dispatch(ctx, args);
    process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
    process.exit(0);
  } catch (error) {
    process.stderr.write(`Error: ${String(error && error.message ? error.message : error)}\n`);
    usage();
    process.exit(1);
  }
}

main();
