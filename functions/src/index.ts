// Buzz Masters Cloud Functions (europe-west2, London).
//
//   api                — the app's single callable: rooms, races, friends,
//                         moderation, rankings, daily reward, equip, tournaments
//   syncPurchases      — after a purchase/restore: asks RevenueCat (secret key,
//                         server only) what the player owns and records exactly that
//   deleteAccount      — erases the caller's data, then their auth user
//   revenuecatWebhook  — RevenueCat → server (shared secret, constant time)
//   admobSsv           — Google AdMob rewarded-ad verification (ECDSA)
//   pushNotification   — sends FCM for new in-app notifications
//   adminSummary       — monetisation counts, for `monetisation_admin` users
import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';
import { setGlobalOptions } from 'firebase-functions/v2';
import { HttpsError, onCall, onRequest } from 'firebase-functions/v2/https';
import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import { defineBoolean, defineInt, defineSecret } from 'firebase-functions/params';
import * as logger from 'firebase-functions/logger';
import { Api } from './api';
import { actionForWebhook, actionsForSubscriber, isAccountId, webhookAuthorised, type StoreAction }
  from './shared/revenuecat';
import { utcDay, VERIFIER_KEYS_URL, verifyAdMobSsv, type VerifierKey } from './shared/admob_ssv';

initializeApp();
setGlobalOptions({ region: 'europe-west2', maxInstances: 20 });

const db = getFirestore();
const api = new Api(db);

const REVENUECAT_WEBHOOK_SECRET = defineSecret('REVENUECAT_WEBHOOK_SECRET');
const REVENUECAT_SECRET_API_KEY = defineSecret('REVENUECAT_SECRET_API_KEY');
const AD_REWARD_COINS = defineInt('AD_REWARD_COINS', { default: 50 });
const AD_REWARD_MAX_PER_DAY = defineInt('AD_REWARD_MAX_PER_DAY', { default: 5 });
const ALLOW_SANDBOX = defineBoolean('REVENUECAT_ALLOW_SANDBOX', { default: false });
/**
 * App Check: set ENFORCE_APP_CHECK=true in functions/.env once App Attest
 * (iOS), Play Integrity (Android) and reCAPTCHA (web) are registered.
 */
const callable = { enforceAppCheck: process.env.ENFORCE_APP_CHECK === 'true', cors: true };

function requireUid(auth: { uid: string } | undefined): string {
  if (!auth?.uid) throw new HttpsError('unauthenticated', 'not_authenticated');
  return auth.uid;
}

export const apiCall = onCall(callable, async (req) => {
  const uid = requireUid(req.auth);
  const op = String((req.data as { op?: unknown })?.op ?? '');
  const args = ((req.data as { args?: unknown })?.args ?? {}) as Record<string, unknown>;
  return api.handle(op, uid, args);
});

async function applyStoreAction(action: StoreAction, source: string) {
  if (action.kind === 'ignore') return { accepted: true, ignored: action.reason };
  if (action.kind === 'renewal') {
    return api.storeRenewal(action.eventId, action.accountId, action.productId, action.willRenew);
  }
  return api.storeEvent({
    eventId: action.eventId, uid: action.accountId, transactionId: action.transactionId,
    productId: action.productId, price: action.price, revoked: action.revoked,
    expiresAt: action.expiresAt ? Date.parse(action.expiresAt) : null,
    willRenew: action.willRenew, source,
  });
}

export const syncPurchases = onCall(
  { ...callable, secrets: [REVENUECAT_SECRET_API_KEY] },
  async (req) => {
    const uid = requireUid(req.auth);
    const requested = String((req.data as { product_id?: unknown })?.product_id ?? '');
    const rc = await fetch(
      `https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(uid)}`,
      { headers: { Authorization: `Bearer ${REVENUECAT_SECRET_API_KEY.value()}` } },
    );
    if (!rc.ok) return { accepted: false, message: `Store check failed (${rc.status}).` };
    const subscriber = (await rc.json() as { subscriber?: unknown })?.subscriber;
    let granted: string[] = [];
    let confirmed = false;
    for (const action of actionsForSubscriber(subscriber, uid, new Date())) {
      const result = await applyStoreAction(action, 'revenuecat_sync') as { granted_item_ids?: string[] };
      if (action.kind === 'record' && action.productId === requested && !action.revoked) {
        confirmed = true;
        granted = granted.concat(result?.granted_item_ids ?? []);
      }
    }
    return {
      accepted: requested === '' || confirmed,
      duplicate: false,
      granted_item_ids: granted,
      message: requested && !confirmed ? 'The store has no record of this purchase yet.' : '',
    };
  },
);

export const deleteAccount = onCall(callable, async (req) => {
  const uid = requireUid(req.auth);
  const result = await api.purgeAccount(uid);
  await getAuth().deleteUser(uid);
  return result;
});

export const adminSummary = onCall(callable, async (req) => {
  requireUid(req.auth);
  if (req.auth?.token?.monetisation_admin !== true) {
    throw new HttpsError('permission-denied', 'not_admin');
  }
  const [vip, purchases, refunds, ads] = await Promise.all([
    db.collection('entitlements').where('vip.active', '==', true).count().get(),
    db.collectionGroup('events').where('state', '==', 'success').count().get(),
    db.collectionGroup('events').where('revoked', '==', true).count().get(),
    db.collectionGroup('events').where('verification', '==', 'ssv_verified').count().get(),
  ]);
  return {
    active_vip: vip.data().count,
    purchases: purchases.data().count,
    refunds: refunds.data().count,
    verified_ad_rewards: ads.data().count,
  };
});

export const revenuecatWebhook = onRequest(
  { secrets: [REVENUECAT_WEBHOOK_SECRET] },
  async (req, res) => {
    if (req.method !== 'POST') { res.status(405).json({ error: 'method_not_allowed' }); return; }
    if (!webhookAuthorised(req.get('authorization') ?? null, REVENUECAT_WEBHOOK_SECRET.value())) {
      res.status(401).json({ error: 'unauthorised' });
      return;
    }
    const action = actionForWebhook((req.body as { event?: unknown })?.event,
      { allowSandbox: ALLOW_SANDBOX.value() });
    try {
      res.json(await applyStoreAction(action, 'revenuecat_webhook'));
    } catch (e) {
      logger.error('revenuecat webhook failed', e);
      res.status(500).json({ error: 'apply_failed' }); // RevenueCat retries
    }
  },
);

let cachedKeys: { keys: VerifierKey[]; at: number } | null = null;
async function verifierKeys(): Promise<VerifierKey[]> {
  if (cachedKeys && Date.now() - cachedKeys.at < 6 * 3600_000) return cachedKeys.keys;
  const res = await fetch(VERIFIER_KEYS_URL);
  if (!res.ok) throw new Error(`verifier keys ${res.status}`);
  const keys = ((await res.json() as { keys?: VerifierKey[] })?.keys ?? []);
  cachedKeys = { keys, at: Date.now() };
  return keys;
}

export const admobSsv = onRequest(async (req, res) => {
  if (req.method !== 'GET') { res.status(405).json({ error: 'method_not_allowed' }); return; }
  const url = new URL(req.originalUrl, 'https://ssv.invalid');
  let result = await verifyAdMobSsv(url, await verifierKeys());
  if (!result.ok && result.reason === 'unknown_key_id') {
    cachedKeys = null; // Google rotated its keys: refresh once.
    result = await verifyAdMobSsv(url, await verifierKeys());
  }
  if (!result.ok) { res.status(400).json({ error: result.reason }); return; }
  const reward = result.reward;
  if (!isAccountId(reward.userId)) { res.status(400).json({ error: 'unknown_user' }); return; }
  const eventId = reward.customData || `ssv-${reward.transactionId}`;
  const out = await api.ssvReward(reward.userId, eventId, utcDay(reward.timestampMs || Date.now()),
    AD_REWARD_COINS.value(), AD_REWARD_MAX_PER_DAY.value());
  res.json({ ok: true, outcome: out.outcome });
});

const PUSH_TEXT: Record<string, (p: Record<string, unknown>) => { title: string; body: string }> = {
  friend_request: (p) => ({ title: 'Friend request', body: `${p.from} wants to race with you.` }),
  friend_accepted: (p) => ({ title: 'New friend', body: `${p.from} accepted your request.` }),
  race_invite: (p) => ({ title: 'Race invite', body: `${p.from} invited you to race ${p.code}.` }),
  race_result: (p) => ({ title: 'Race finished', body: `You finished #${p.placing}.` }),
};

export const pushNotification = onDocumentCreated(
  'players/{uid}/notifications/{id}',
  async (event) => {
    const data = event.data?.data();
    const text = data ? PUSH_TEXT[String(data.kind)] : undefined;
    if (!text) return;
    const devices = await db.collection(`players/${event.params.uid}/devices`).get();
    const tokens = devices.docs.map((d) => String(d.get('token')));
    if (tokens.length === 0) return;
    const { title, body } = text((data!.payload ?? {}) as Record<string, unknown>);
    const res = await getMessaging().sendEachForMulticast({
      tokens, notification: { title, body }, data: { kind: String(data!.kind) },
    });
    // Forget tokens the device has dropped.
    await Promise.all(res.responses.map((r, i) =>
      r.success || !/registration-token-not-registered|invalid-registration-token/
        .test(r.error?.code ?? '') ? null : devices.docs[i].ref.delete()));
  },
);
