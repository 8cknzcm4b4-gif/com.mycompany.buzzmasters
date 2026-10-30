// RevenueCat webhook → verified VIP / purchase records.
//
// Configure in RevenueCat → Integrations → Webhooks with URL
//   https://<ref>.supabase.co/functions/v1/revenuecat-webhook
// and an Authorization header value equal to REVENUECAT_WEBHOOK_SECRET.
// Deploy with --no-verify-jwt (RevenueCat does not send a Supabase JWT).
import { createClient } from 'npm:@supabase/supabase-js@2.45.4';
import { actionForWebhook, applyAction, webhookAuthorised } from '../_shared/revenuecat.ts';
import { json, requireEnv } from '../_shared/http.ts';

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);
  if (!webhookAuthorised(req.headers.get('authorization'), Deno.env.get('REVENUECAT_WEBHOOK_SECRET') ?? '')) {
    return json({ error: 'unauthorised' }, 401);
  }
  let body: { event?: unknown };
  try {
    body = await req.json();
  } catch {
    return json({ error: 'bad_json' }, 400);
  }
  const action = actionForWebhook(body.event, {
    allowSandbox: Deno.env.get('REVENUECAT_ALLOW_SANDBOX') === 'true',
  });
  const admin = createClient(requireEnv('SUPABASE_URL'), requireEnv('SUPABASE_SERVICE_ROLE_KEY'), {
    auth: { persistSession: false },
  });
  try {
    const result = await applyAction(admin, action, 'revenuecat_webhook');
    return json({ ok: true, action: action.kind, result });
  } catch (e) {
    // Non-2xx makes RevenueCat retry; events are idempotent by id.
    console.error('revenuecat-webhook failed', e);
    return json({ error: 'apply_failed' }, 500);
  }
});
