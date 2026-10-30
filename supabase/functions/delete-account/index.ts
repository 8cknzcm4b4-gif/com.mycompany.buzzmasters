// In-app account deletion (App Store guideline 5.1.1(v)).
//
// The signed-in player calls this with their own JWT. It verifies the JWT,
// erases their game, social and monetisation data (bm_purge_account), then
// deletes the auth user. Subscriptions must still be cancelled in the App
// Store / Google Play; the app tells the player so before confirming.
import { createClient } from 'npm:@supabase/supabase-js@2.45.4';
import { json, requireEnv } from '../_shared/http.ts';

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);
  const url = requireEnv('SUPABASE_URL');
  const asUser = createClient(url, requireEnv('SUPABASE_ANON_KEY'), {
    global: { headers: { Authorization: req.headers.get('authorization') ?? '' } },
    auth: { persistSession: false },
  });
  const { data, error } = await asUser.auth.getUser();
  if (error || !data.user) return json({ error: 'unauthorised' }, 401);
  const userId = data.user.id;

  const admin = createClient(url, requireEnv('SUPABASE_SERVICE_ROLE_KEY'), {
    auth: { persistSession: false },
  });
  const purge = await admin.rpc('bm_purge_account', { p_user: userId });
  if (purge.error) {
    console.error('purge failed', purge.error);
    return json({ error: 'purge_failed' }, 500);
  }
  const removed = await admin.auth.admin.deleteUser(userId);
  if (removed.error) {
    console.error('auth delete failed', removed.error);
    return json({ error: 'auth_delete_failed' }, 500);
  }
  return json({ ok: true, deleted: purge.data?.deleted ?? {} });
});
