// Tests the Edge Function logic exactly as deployed (the shared .ts modules,
// run by Node's built-in TypeScript support) and wires it to the real
// migrations on PGlite.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { webcrypto as crypto } from 'node:crypto';
import { PGlite } from '@electric-sql/pglite';
import {
  actionForWebhook, actionsForSubscriber, applyAction, timingSafeEqual,
  webhookAuthorised,
} from '../functions/_shared/revenuecat.ts';
import { derToRaw, utcDay, verifyAdMobSsv } from '../functions/_shared/admob_ssv.ts';

const ALICE = '00000000-0000-4000-8000-0000000000a1';
const event = (over = {}) => ({
  id: 'evt-1', type: 'INITIAL_PURCHASE', app_user_id: ALICE,
  product_id: 'buzzmasters_vip_monthly', transaction_id: 'GPA.1',
  expiration_at_ms: Date.parse('2026-12-01T00:00:00Z'), price: 3.99,
  currency: 'GBP', environment: 'PRODUCTION', ...over,
});

test('webhook secret: constant-time, Bearer optional, weak secrets refused', () => {
  const secret = 'whsec_0123456789abcdef';
  assert.equal(webhookAuthorised(`Bearer ${secret}`, secret), true);
  assert.equal(webhookAuthorised(secret, secret), true);
  assert.equal(webhookAuthorised('Bearer wrong', secret), false);
  assert.equal(webhookAuthorised(null, secret), false);
  assert.equal(webhookAuthorised('short', 'short'), false, 'secret too short');
  assert.equal(timingSafeEqual('abc', 'abcd'), false);
});

test('webhook events map to grant / revoke / renewal / ignore', () => {
  const opts = { allowSandbox: false };
  const grant = actionForWebhook(event(), opts);
  assert.equal(grant.kind, 'record');
  assert.equal(grant.revoked, false);
  assert.equal(grant.expiresAt, '2026-12-01T00:00:00.000Z');
  assert.equal(grant.willRenew, true);
  assert.equal(grant.price, '3.99 GBP');

  assert.equal(actionForWebhook(event({ type: 'RENEWAL', id: 'e2' }), opts).kind, 'record');
  const expired = actionForWebhook(event({ type: 'EXPIRATION' }), opts);
  assert.deepEqual([expired.kind, expired.revoked], ['record', true]);
  const refund = actionForWebhook(
    event({ type: 'CANCELLATION', cancel_reason: 'CUSTOMER_SUPPORT' }), opts);
  assert.equal(refund.revoked, true);
  const optOut = actionForWebhook(
    event({ type: 'CANCELLATION', cancel_reason: 'UNSUBSCRIBE' }), opts);
  assert.deepEqual([optOut.kind, optOut.willRenew], ['renewal', false]);

  assert.equal(actionForWebhook(event({ type: 'TEST' }), opts).reason, 'test_event');
  assert.equal(actionForWebhook(event({ environment: 'SANDBOX' }), opts).reason,
    'sandbox_event');
  assert.equal(actionForWebhook(event({ environment: 'SANDBOX' }),
    { allowSandbox: true }).kind, 'record');
  assert.equal(actionForWebhook(event({ app_user_id: '$RCAnonymousID:1' }), opts).reason,
    'not_a_buzz_masters_account');
  assert.equal(actionForWebhook(event({ type: 'BILLING_ISSUE' }), opts).kind, 'ignore');
});

test('subscriber sync: active, expired, refunded and one-off purchases', () => {
  const now = new Date('2026-11-01T00:00:00Z');
  const actions = actionsForSubscriber({
    subscriptions: {
      buzzmasters_vip_monthly: { expires_date: '2026-12-01T00:00:00Z',
        original_purchase_date: '2026-10-01T00:00:00Z' },
      buzzmasters_vip_annual: { expires_date: '2026-10-01T00:00:00Z' },
    },
    non_subscriptions: {
      buzzmasters_neon_bundle: [{ id: 'np1', store_transaction_id: 'T-9' }],
      buzzmasters_starter_bundle: [{ id: 'np2', refunded_at: '2026-10-20T00:00:00Z' }],
    },
  }, ALICE, now);
  const by = Object.fromEntries(actions.map((a) => [a.productId, a]));
  assert.equal(by.buzzmasters_vip_monthly.revoked, false);
  assert.equal(by.buzzmasters_vip_monthly.willRenew, true);
  assert.equal(by.buzzmasters_vip_annual.revoked, true);
  assert.equal(by.buzzmasters_neon_bundle.transactionId, 'T-9');
  assert.equal(by.buzzmasters_starter_bundle.revoked, true);
  // Same state → same event ids, so a repeated sync applies nothing new.
  const again = actionsForSubscriber({ subscriptions: {
    buzzmasters_vip_monthly: { expires_date: '2026-12-01T00:00:00Z' } } }, ALICE, now);
  assert.equal(again[0].eventId, by.buzzmasters_vip_monthly.eventId);
  assert.deepEqual(actionsForSubscriber({}, 'not-a-uuid', now), []);
});

// --- AdMob SSV with a real P-256 key, signed exactly as Google does --------

function rawToDer(raw) {
  const int = (b) => {
    let v = Array.from(b);
    while (v.length > 1 && v[0] === 0) v.shift();
    if (v[0] & 0x80) v.unshift(0);
    return [0x02, v.length, ...v];
  };
  const body = [...int(raw.slice(0, 32)), ...int(raw.slice(32))];
  return new Uint8Array([0x30, body.length, ...body]);
}
const b64url = (bytes) => Buffer.from(bytes).toString('base64')
  .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');

async function signedCallback(query, { keyId = 1234 } = {}) {
  const pair = await crypto.subtle.generateKey(
    { name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify']);
  const spki = Buffer.from(await crypto.subtle.exportKey('spki', pair.publicKey))
    .toString('base64');
  const raw = new Uint8Array(await crypto.subtle.sign(
    { name: 'ECDSA', hash: 'SHA-256' }, pair.privateKey, new TextEncoder().encode(query)));
  const url = new URL(`https://x.test/admob-ssv?${query}&signature=${b64url(rawToDer(raw))}&key_id=${keyId}`);
  return { url, keys: [{ keyId, base64: spki }] };
}

const QUERY = 'ad_network=5450213213286189855&ad_unit=1234567890&custom_data=ad-777'
  + `&reward_amount=1&reward_item=coins&timestamp=1793448000000&transaction_id=abc123&user_id=${ALICE}`;

test('SSV: a genuine signature verifies and yields the reward', async () => {
  const { url, keys } = await signedCallback(QUERY);
  const r = await verifyAdMobSsv(url, keys);
  assert.equal(r.ok, true);
  assert.equal(r.reward.userId, ALICE);
  assert.equal(r.reward.customData, 'ad-777');
  assert.equal(r.reward.transactionId, 'abc123');
  assert.equal(utcDay(r.reward.timestampMs), 20261031);
});

test('SSV: tampering, wrong key and missing signature are rejected', async () => {
  const { url, keys } = await signedCallback(QUERY);
  const forged = new URL(url.href.replace(`user_id=${ALICE}`,
    'user_id=00000000-0000-4000-8000-0000000000b2'));
  assert.deepEqual(await verifyAdMobSsv(forged, keys), { ok: false, reason: 'bad_signature' });
  const other = await signedCallback(QUERY);
  // Same key id, different key: the signature does not match.
  assert.deepEqual(await verifyAdMobSsv(url, other.keys),
    { ok: false, reason: 'bad_signature' });
  assert.deepEqual(await verifyAdMobSsv(new URL(`https://x.test/?${QUERY}`), keys),
    { ok: false, reason: 'missing_signature' });
  const wrongId = new URL(url.href.replace('key_id=1234', 'key_id=999'));
  assert.deepEqual(await verifyAdMobSsv(wrongId, keys), { ok: false, reason: 'unknown_key_id' });
});

test('DER → raw handles leading-zero integers', () => {
  const der = new Uint8Array([0x30, 0x08, 0x02, 0x02, 0x00, 0x80, 0x02, 0x02, 0x01, 0x02]);
  const raw = derToRaw(der);
  assert.equal(raw.length, 64);
  assert.equal(raw[31], 0x80);
  assert.equal(raw[62], 0x01);
  assert.equal(raw[63], 0x02);
});

// --- End to end: webhook JSON → mapping → real Postgres ---------------------

test('a RevenueCat webhook purchase becomes VIP for that player only', async () => {
  const read = (p) => readFileSync(new URL(p, import.meta.url), 'utf8');
  const db = new PGlite();
  await db.exec(`
    create role anon nologin; create role authenticated nologin;
    create role service_role nologin bypassrls;
    create schema auth; create table auth.users (id uuid primary key);
    create function auth.uid() returns uuid language sql stable as
      $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
    create function auth.jwt() returns jsonb language sql stable as $$ select '{}'::jsonb $$;
    grant usage on schema auth, public to anon, authenticated, service_role;
    grant execute on function auth.uid(), auth.jwt() to anon, authenticated, service_role;
  `);
  for (const f of ['20261029000100_monetisation.sql', '20261030000100_multiplayer.sql',
    '20261030000200_monetisation_security.sql']) {
    await db.exec(read(`../migrations/${f}`));
  }
  // The service-role client the Edge Function uses, over the real database.
  const serviceRole = {
    async rpc(fn, params) {
      const names = Object.keys(params);
      await db.exec('set role service_role;');
      try {
        const sql = `select public.${fn}(${names.map((n, i) => `${n} => $${i + 1}`).join(', ')}) as r`;
        const res = await db.query(sql, names.map((n) => params[n]));
        return { data: res.rows[0].r, error: null };
      } catch (e) {
        return { data: null, error: { message: e.message } };
      } finally {
        await db.exec('reset role;');
      }
    },
  };
  const ent = async (sub) => {
    await db.exec(`set request.jwt.claim.sub = '${sub}'; set role authenticated;`);
    try {
      return (await db.query('select public.monetisation_entitlement($1) as r', [sub])).rows[0].r;
    } finally { await db.exec('reset role;'); }
  };

  const purchase = actionForWebhook(event(), { allowSandbox: false });
  const first = await applyAction(serviceRole, purchase, 'revenuecat_webhook');
  assert.equal(first.accepted, true);
  // RevenueCat retries deliver the same event id: applied once.
  assert.equal((await applyAction(serviceRole, purchase, 'revenuecat_webhook')).duplicate, true);
  assert.equal((await ent(ALICE)).active, true);
  assert.equal((await ent('00000000-0000-4000-8000-0000000000b2')).active, false);

  await applyAction(serviceRole,
    actionForWebhook(event({ id: 'evt-2', type: 'EXPIRATION' }), { allowSandbox: false }),
    'revenuecat_webhook');
  assert.equal((await ent(ALICE)).active, false);
});
