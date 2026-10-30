// Called by the app right after a purchase or restore. Asks RevenueCat (with
// the SECRET key, which never leaves the server) what the signed-in player
// actually owns, and records exactly that. The app's own claim is ignored.
import { createClient } from 'npm:@supabase/supabase-js@2.45.4';
import { actionsForSubscriber, applyAction } from '../_shared/revenuecat.ts';
import { json, requireEnv } from '../_shared/http.ts';

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);
  const url = requireEnv('SUPABASE_URL');
  const auth = req.headers.get('authorization') ?? '';
  const asUser = createClient(url, requireEnv('SUPABASE_ANON_KEY'), {
    global: { headers: { Authorization: auth } },
    auth: { persistSession: false },
  });
  const { data: userData, error: userError } = await asUser.auth.getUser();
  if (userError || !userData.user) return json({ error: 'unauthorised' }, 401);
  const accountId = userData.user.id;

  let requested = '';
  try {
    requested = String((await req.json())?.product_id ?? '');
  } catch { /* body optional */ }

  const rc = await fetch(
    `https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(accountId)}`,
    { headers: { Authorization: `Bearer ${requireEnv('REVENUECAT_SECRET_API_KEY')}` } },
  );
  if (!rc.ok) return json({ accepted: false, message: `Store check failed (${rc.status}).` }, 502);
  const subscriber = (await rc.json())?.subscriber;

  const admin = createClient(url, requireEnv('SUPABASE_SERVICE_ROLE_KEY'), {
    auth: { persistSession: false },
  });
  let granted: string[] = [];
  let confirmed = false;
  for (const action of actionsForSubscriber(subscriber, accountId, new Date())) {
    const result = await applyAction(admin, action, 'revenuecat_sync');
    if (action.kind === 'record' && action.productId === requested && !action.revoked) {
      confirmed = true;
      granted = granted.concat(result?.granted_item_ids ?? []);
    }
  }
  return json({
    accepted: requested === '' || confirmed,
    duplicate: false,
    granted_item_ids: granted,
    message: requested && !confirmed ? 'The store has no record of this purchase yet.' : '',
  });
});
