const { onCall, onRequest, HttpsError } = require('firebase-functions/v2/https');
const { setGlobalOptions } = require('firebase-functions/v2');
const logger = require('firebase-functions/logger');
const admin = require('firebase-admin');

if (!admin.apps.length) {
  admin.initializeApp();
}

setGlobalOptions({
  region: 'us-central1',
  maxInstances: 10,
});

const db = admin.firestore();
const messaging = admin.messaging();

const LIST_PAYLOAD = 'spx_opportunities';
const OPPORTUNITY_PREFIX = 'spx_opportunity:';
const INVALID_TOKEN_CODES = new Set([
  'messaging/invalid-registration-token',
  'messaging/registration-token-not-registered',
]);

function trimText(value, fallback = '') {
  if (value == null) return fallback;
  const normalized = String(value).trim();
  return normalized.length > 0 ? normalized : fallback;
}

function coerceBool(value, fallback = false) {
  if (typeof value === 'boolean') return value;
  if (typeof value === 'string') {
    const normalized = value.trim().toLowerCase();
    if (normalized === 'true') return true;
    if (normalized === 'false') return false;
  }
  return fallback;
}

function normalizePayload(data) {
  const explicit = trimText(data.payload, '');
  if (explicit) return explicit;

  const opportunityId = trimText(data.opportunityId, '');
  if (opportunityId) return `${OPPORTUNITY_PREFIX}${opportunityId}`;

  const target = trimText(data.target, '').toLowerCase();
  if (target === LIST_PAYLOAD) return LIST_PAYLOAD;

  return '';
}

function opportunityIdFromPayload(payload) {
  if (!payload.startsWith(OPPORTUNITY_PREFIX)) return '';
  return payload.substring(OPPORTUNITY_PREFIX.length).trim();
}

function canSendToUser(auth, userId) {
  if (!auth) return false;
  if (auth.uid === userId) return true;
  if (auth.token && auth.token.admin === true) return true;
  return false;
}

function normalizeInput(data) {
  const userId = trimText(data.userId, '');
  if (!userId) {
    throw new HttpsError('invalid-argument', 'userId is required.');
  }

  const payload = normalizePayload(data);
  if (!payload) {
    throw new HttpsError(
      'invalid-argument',
      'payload or opportunityId/target is required.'
    );
  }

  if (payload !== LIST_PAYLOAD && !payload.startsWith(OPPORTUNITY_PREFIX)) {
    throw new HttpsError('invalid-argument', 'Unsupported payload value.');
  }

  const title = trimText(data.title, 'SPX Opportunity Found');
  const body = trimText(data.body, 'New SPX opportunity is available.');
  const platform = trimText(data.platform, '');
  const dryRun = coerceBool(data.dryRun, false);
  const opportunityId = trimText(
    data.opportunityId,
    opportunityIdFromPayload(payload)
  );

  return {
    userId,
    payload,
    title,
    body,
    platform,
    dryRun,
    opportunityId,
  };
}

async function loadEnabledTokens(userId, { platform } = {}) {
  let query = db
    .collection('users')
    .doc(userId)
    .collection('push_tokens')
    .where('alertsEnabled', '==', true);

  const normalizedPlatform = trimText(platform, '').toLowerCase();
  if (normalizedPlatform) {
    query = query.where('platform', '==', normalizedPlatform);
  }

  const snapshot = await query.get();
  return snapshot.docs
    .map((doc) => {
      const data = doc.data() || {};
      const token = trimText(data.token || doc.id, '');
      return {
        ref: doc.ref,
        token,
      };
    })
    .filter((item) => item.token.length > 0);
}

async function dispatchSpxPush(input) {
  const tokens = await loadEnabledTokens(input.userId, {
    platform: input.platform,
  });
  if (tokens.length === 0) {
    return {
      userId: input.userId,
      payload: input.payload,
      platform: input.platform || null,
      attempted: 0,
      success: 0,
      failed: 0,
      invalidTokensRemoved: 0,
      dryRun: input.dryRun,
      messageIds: [],
      errors: [],
    };
  }

  const dataPayload = {
    payload: input.payload,
    title: input.title,
    body: input.body,
    ...(input.payload === LIST_PAYLOAD ? { target: LIST_PAYLOAD } : {}),
    ...(input.opportunityId ? { opportunityId: input.opportunityId } : {}),
  };

  let success = 0;
  let failed = 0;
  let invalidTokensRemoved = 0;
  const messageIds = [];
  const errors = [];

  const sendTasks = tokens.map(async (tokenEntry) => {
    try {
      const response = await messaging.send(
        {
          token: tokenEntry.token,
          notification: {
            title: input.title,
            body: input.body,
          },
          data: dataPayload,
        },
        input.dryRun
      );
      success += 1;
      messageIds.push(response);
    } catch (error) {
      failed += 1;
      const code = trimText(error && error.code, 'unknown');
      const message = trimText(error && error.message, 'unknown error');
      errors.push({
        token: tokenEntry.token,
        code,
        message,
      });

      if (INVALID_TOKEN_CODES.has(code) && !input.dryRun) {
        try {
          await tokenEntry.ref.delete();
          invalidTokensRemoved += 1;
        } catch (cleanupError) {
          logger.warn('Failed to remove invalid push token doc', {
            userId: input.userId,
            token: tokenEntry.token,
            cleanupError: String(cleanupError),
          });
        }
      }
    }
  });

  await Promise.all(sendTasks);

  logger.info('SPX push dispatch complete', {
    userId: input.userId,
    payload: input.payload,
    platform: input.platform || 'all',
    attempted: tokens.length,
    success,
    failed,
    invalidTokensRemoved,
    dryRun: input.dryRun,
  });

  return {
    userId: input.userId,
    payload: input.payload,
    platform: input.platform || null,
    attempted: tokens.length,
    success,
    failed,
    invalidTokensRemoved,
    dryRun: input.dryRun,
    messageIds,
    errors,
  };
}

function isAuthorizedHttpRequest(request) {
  const expectedKey = trimText(process.env.SPX_PUSH_DISPATCH_KEY, '');
  if (!expectedKey) return false;

  const headerKey = trimText(request.get('x-spx-dispatch-key'), '');
  if (headerKey && headerKey === expectedKey) return true;

  const authHeader = trimText(request.get('authorization'), '');
  const token = authHeader.toLowerCase().startsWith('bearer ')
    ? authHeader.substring(7).trim()
    : '';
  return token === expectedKey;
}

function normalizeHttpBody(body) {
  if (!body) return {};
  if (typeof body === 'object') return body;
  if (typeof body === 'string') {
    try {
      return JSON.parse(body);
    } catch (_) {
      return {};
    }
  }
  return {};
}

exports.sendSpxOpportunityPush = onCall(
  {
    timeoutSeconds: 60,
    memory: '256MiB',
  },
  async (request) => {
    const data = normalizeInput(request.data || {});
    if (!canSendToUser(request.auth, data.userId)) {
      throw new HttpsError(
        'permission-denied',
        'Caller cannot send push notifications for this user.'
      );
    }
    return dispatchSpxPush(data);
  }
);

exports.sendSpxOpportunityPushHttp = onRequest(
  {
    timeoutSeconds: 60,
    memory: '256MiB',
    cors: true,
  },
  async (request, response) => {
    if (request.method !== 'POST') {
      response.status(405).json({ error: 'method-not-allowed' });
      return;
    }

    if (!isAuthorizedHttpRequest(request)) {
      response.status(401).json({ error: 'unauthorized' });
      return;
    }

    try {
      const data = normalizeInput(normalizeHttpBody(request.body));
      const result = await dispatchSpxPush(data);
      response.status(200).json(result);
    } catch (error) {
      if (error instanceof HttpsError) {
        response.status(400).json({
          error: error.code,
          message: error.message,
        });
        return;
      }

      logger.error('SPX HTTP push dispatch failed', {
        message: String(error),
      });
      response.status(500).json({
        error: 'internal',
        message: 'SPX push dispatch failed.',
      });
    }
  }
);
