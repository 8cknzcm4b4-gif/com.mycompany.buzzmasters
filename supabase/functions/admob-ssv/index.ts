// AdMob rewarded-ad server-side verification callback.
//
// Set as the SSV callback URL on the rewarded ad unit in AdMob:
//   https://<ref>.supabase.co/functions/v1/admob-ssv
// Deploy with --no-verify-jwt (Google does not send a Supabase JWT).
// The app sets user_id = Supabase user id and custom_data = its event id.
import { createClient } from 'npm:@supabase/supabase-js@2.45.4';
import { utcDay, VERIFIER_KEYS_URL, verifyAdMobSsv, type VerifierKey } from '../_shared/admob_ssv.ts';
import { isAccountId } from '../_shared/revenuecat.ts';
import { json, requireEnv } from '../_shared/http.ts';

let cachedKeys: { keys: VerifierKey[]; at: number } | null = null;

async function verifierKeys(): Promise<VerifierKey[]> {
  if (cachedKeys && Date.now() - cachedKeys.at < 6 * 3600 * 1000) return cachedKeys.keys;
  const res = await fetch(VERIFIER_KEYS_URL);
  if (!res.ok) throw new Error(`verifier keys ${res.status}`);
  const keys = ((await res.json())?.keys ?? []) as VerifierKey[];
  cachedKeys = { keys, at: Date.now() };
  return keys;
}

Deno.serve(async (req) => {
  if (req.method !== 'GET') return json({ error: 'method_not_allowed' }, 405);
  const url = new URL(req.url);
  let result = await verifyAdMobSsv(url, await verifierKeys());
  if (!result.ok && result.reason === 'unknown_key_id') {
    cachedKeys = null; // Google rotated keys: refresh once.
    result = await verifyAdMobSsv(url, await verifierKeys());
  }
  if (!result.ok) return json({ error: result.reason }, 400);

  const reward = result.reward;
  if (!isAccountId(reward.userId)) return json({ error: 'unknown_user' }, 400);
  const eventId = reward.customData || `ssv-${reward.transactionId}`;
  const admin = createClient(requireEnv('SUPABASE_URL'), requireEnv('SUPABASE_SERVICE_ROLE_KEY'), {
    auth: { persistSession: false },
  });
  const { data, error } = await admin.rpc('monetisation_ssv_reward', {
    p_account_id: reward.userId,
    p_event_id: eventId,
    p_utc_day: utcDay(reward.timestampMs || Date.now()),
    p_coins: Number(Deno.env.get('AD_REWARD_COINS') ?? '50'),
    p_max_per_day: Number(Deno.env.get('AD_REWARD_MAX_PER_DAY') ?? '5'),
  });
  if (error) {
    console.error('admob-ssv failed', error);
    return json({ error: 'apply_failed' }, 500);
  }
  return json({ ok: true, outcome: data?.outcome });
});
