// AdMob rewarded-ad server-side verification (SSV).
//
// Google calls our callback with the reward details, then `signature` and
// `key_id` as the last two query parameters. The signature is an ECDSA
// P-256 / SHA-256 signature (DER, base64url) over everything in the query
// string before "&signature=", made with one of the keys published at
// https://www.gstatic.com/admob/reward/verifier-keys.json.
//
// Pure WebCrypto, so the same code runs in Deno and in Node tests.

export const VERIFIER_KEYS_URL = 'https://www.gstatic.com/admob/reward/verifier-keys.json';

export interface VerifierKey {
  keyId: number | string;
  base64: string; // DER SubjectPublicKeyInfo, base64
}

export interface SsvReward {
  userId: string;
  customData: string;
  transactionId: string;
  rewardAmount: number;
  rewardItem: string;
  adUnit: string;
  timestampMs: number;
}

export type SsvResult = { ok: true; reward: SsvReward } | { ok: false; reason: string };

function b64ToBytes(b64: string): Uint8Array {
  const norm = b64.replace(/-/g, '+').replace(/_/g, '/');
  const padded = norm + '='.repeat((4 - (norm.length % 4)) % 4);
  const bin = atob(padded);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

/** Converts an ASN.1 DER ECDSA signature to the raw r||s form WebCrypto wants. */
export function derToRaw(der: Uint8Array, size = 32): Uint8Array {
  let i = 0;
  if (der[i++] !== 0x30) throw new Error('not_a_der_sequence');
  let len = der[i++];
  if (len & 0x80) i += len & 0x7f; // long-form length (not expected for P-256)
  const readInt = (): Uint8Array => {
    if (der[i++] !== 0x02) throw new Error('not_a_der_integer');
    const n = der[i++];
    let v = der.slice(i, i + n);
    i += n;
    while (v.length > size && v[0] === 0) v = v.slice(1);
    if (v.length > size) throw new Error('integer_too_long');
    const padded = new Uint8Array(size);
    padded.set(v, size - v.length);
    return padded;
  };
  const r = readInt();
  const s = readInt();
  const raw = new Uint8Array(size * 2);
  raw.set(r, 0);
  raw.set(s, size);
  return raw;
}

/** Verifies an AdMob SSV callback URL against Google's verifier keys. */
export async function verifyAdMobSsv(url: URL, keys: VerifierKey[]): Promise<SsvResult> {
  const query = url.search.startsWith('?') ? url.search.slice(1) : url.search;
  const cut = query.indexOf('&signature=');
  if (cut < 0) return { ok: false, reason: 'missing_signature' };
  const message = query.slice(0, cut);
  const params = url.searchParams;
  const signature = params.get('signature');
  const keyId = params.get('key_id');
  if (!signature || !keyId) return { ok: false, reason: 'missing_signature' };
  const key = keys.find((k) => String(k.keyId) === keyId);
  if (!key) return { ok: false, reason: 'unknown_key_id' };

  let valid = false;
  try {
    const publicKey = await crypto.subtle.importKey(
      'spki',
      b64ToBytes(key.base64),
      { name: 'ECDSA', namedCurve: 'P-256' },
      false,
      ['verify'],
    );
    valid = await crypto.subtle.verify(
      { name: 'ECDSA', hash: 'SHA-256' },
      publicKey,
      derToRaw(b64ToBytes(signature)),
      new TextEncoder().encode(message),
    );
  } catch {
    valid = false;
  }
  if (!valid) return { ok: false, reason: 'bad_signature' };

  return {
    ok: true,
    reward: {
      userId: params.get('user_id') ?? '',
      customData: params.get('custom_data') ?? '',
      transactionId: params.get('transaction_id') ?? '',
      rewardAmount: Number(params.get('reward_amount') ?? '0'),
      rewardItem: params.get('reward_item') ?? '',
      adUnit: params.get('ad_unit') ?? '',
      timestampMs: Number(params.get('timestamp') ?? '0'),
    },
  };
}

/** `yyyymmdd` in UTC — the same day unit as the app's utcDayOf(). */
export function utcDay(ms: number): number {
  const d = new Date(ms);
  return d.getUTCFullYear() * 10000 + (d.getUTCMonth() + 1) * 100 + d.getUTCDate();
}
