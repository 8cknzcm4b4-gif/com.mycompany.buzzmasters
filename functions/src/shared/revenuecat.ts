// RevenueCat → Buzz Masters store-event mapping.
//
// Pure functions (no Firebase or network APIs), unit-tested in
// functions/test/verification.test.ts.

export type StoreAction =
  | {
    kind: 'record';
    eventId: string;
    accountId: string;
    transactionId: string;
    productId: string;
    price: string;
    revoked: boolean;
    expiresAt: string | null;
    willRenew: boolean;
  }
  | {
    kind: 'renewal';
    eventId: string;
    accountId: string;
    productId: string;
    willRenew: boolean;
  }
  | { kind: 'ignore'; reason: string };

// Firebase Auth uids are 1–128 characters; RevenueCat anonymous ids
// ($RCAnonymousID:…) contain characters a Firebase uid never has.
const UID = /^[A-Za-z0-9_-]{6,128}$/;

/** Buzz Masters accounts are Firebase Auth uids; RevenueCat anonymous ids are not. */
export function isAccountId(id: unknown): id is string {
  return typeof id === 'string' && UID.test(id);
}

/** Constant-time string comparison, so the secret cannot be guessed by timing. */
export function timingSafeEqual(a: string, b: string): boolean {
  const enc = new TextEncoder();
  const x = enc.encode(a);
  const y = enc.encode(b);
  let diff = x.length ^ y.length;
  const n = Math.max(x.length, y.length);
  for (let i = 0; i < n; i++) diff |= (x[i] ?? 0) ^ (y[i] ?? 0);
  return diff === 0;
}

/**
 * RevenueCat sends the configured authorization value verbatim in the
 * Authorization header. Accepts it with or without a "Bearer " prefix.
 */
export function webhookAuthorised(header: string | null, secret: string): boolean {
  if (!secret || secret.length < 16 || !header) return false;
  const value = header.startsWith('Bearer ') ? header.slice(7) : header;
  return timingSafeEqual(value, secret);
}

const GRANT_TYPES = new Set([
  'INITIAL_PURCHASE',
  'RENEWAL',
  'UNCANCELLATION',
  'NON_RENEWING_PURCHASE',
  'PRODUCT_CHANGE',
  'SUBSCRIPTION_EXTENDED',
  'REFUND_REVERSED',
  'TEMPORARY_ENTITLEMENT_GRANT',
]);

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type Json = any;

function iso(ms: unknown): string | null {
  return typeof ms === 'number' && Number.isFinite(ms) ? new Date(ms).toISOString() : null;
}

/** Maps one RevenueCat webhook event to the store action it implies. */
export function actionForWebhook(event: Json, opts: { allowSandbox: boolean }): StoreAction {
  if (!event || typeof event !== 'object') return { kind: 'ignore', reason: 'no_event' };
  const type = String(event.type ?? '');
  if (type === 'TEST') return { kind: 'ignore', reason: 'test_event' };
  if (event.environment === 'SANDBOX' && !opts.allowSandbox) {
    return { kind: 'ignore', reason: 'sandbox_event' };
  }
  const accountId = event.app_user_id;
  if (!isAccountId(accountId)) return { kind: 'ignore', reason: 'not_a_buzz_masters_account' };
  const eventId = String(event.id ?? '');
  const productId = String(event.product_id ?? '');
  if (!eventId || !productId) return { kind: 'ignore', reason: 'missing_fields' };
  const transactionId = String(event.transaction_id ?? event.original_transaction_id ?? eventId);
  const price = event.price != null && event.currency
    ? `${event.price} ${event.currency}`
    : '';

  if (GRANT_TYPES.has(type)) {
    return {
      kind: 'record',
      eventId,
      accountId,
      transactionId,
      productId,
      price,
      revoked: false,
      expiresAt: iso(event.expiration_at_ms),
      willRenew: event.expiration_at_ms != null && type !== 'NON_RENEWING_PURCHASE',
    };
  }
  if (type === 'EXPIRATION' ||
      (type === 'CANCELLATION' && event.cancel_reason === 'CUSTOMER_SUPPORT')) {
    // Expired, or refunded by store support: access ends now.
    return {
      kind: 'record',
      eventId,
      accountId,
      transactionId,
      productId,
      price,
      revoked: true,
      expiresAt: iso(event.expiration_at_ms),
      willRenew: false,
    };
  }
  if (type === 'CANCELLATION') {
    // Auto-renew switched off: VIP continues until expiry.
    return { kind: 'renewal', eventId, accountId, productId, willRenew: false };
  }
  return { kind: 'ignore', reason: `unhandled_${type.toLowerCase() || 'unknown'}` };
}

/**
 * Actions that bring the database in line with RevenueCat's current view of
 * a subscriber (GET /v1/subscribers/{id}). Event ids are derived from the
 * store state, so repeating a sync applies nothing new.
 */
export function actionsForSubscriber(subscriber: Json, accountId: string, now: Date): StoreAction[] {
  if (!isAccountId(accountId) || !subscriber) return [];
  const out: StoreAction[] = [];
  const subs = subscriber.subscriptions ?? {};
  for (const productId of Object.keys(subs)) {
    const s = subs[productId] ?? {};
    const expires = s.expires_date ? new Date(s.expires_date) : null;
    const refunded = Boolean(s.refunded_at);
    const active = !refunded && (expires === null || expires.getTime() > now.getTime());
    const transactionId = String(
      s.store_transaction_id ?? `${productId}:${s.original_purchase_date ?? s.purchase_date ?? ''}`,
    );
    out.push({
      kind: 'record',
      eventId: `sync:${accountId}:${productId}:${s.expires_date ?? 'none'}:${active ? 'on' : 'off'}`,
      accountId,
      transactionId,
      productId,
      price: '',
      revoked: !active,
      expiresAt: expires ? expires.toISOString() : null,
      willRenew: active && !s.unsubscribe_detected_at,
    });
  }
  const once = subscriber.non_subscriptions ?? {};
  for (const productId of Object.keys(once)) {
    for (const p of once[productId] ?? []) {
      const transactionId = String(p.store_transaction_id ?? p.id ?? '');
      if (!transactionId) continue;
      out.push({
        kind: 'record',
        eventId: `sync:${accountId}:${productId}:${transactionId}`,
        accountId,
        transactionId,
        productId,
        price: '',
        revoked: Boolean(p.refunded_at),
        expiresAt: null,
        willRenew: false,
      });
    }
  }
  return out;
}
