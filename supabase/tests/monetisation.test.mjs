// Monetisation security on a real PostgreSQL engine (PGlite, PG 16).
//
// Proves the defects in 20261029000100_monetisation.sql (client-callable
// purchase/reward writers, broken bundle loop) and that
// 20261030000200_monetisation_security.sql closes them.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '@electric-sql/pglite';

const read = (p) => readFileSync(new URL(p, import.meta.url), 'utf8');
const MONETISATION = read('../migrations/20261029000100_monetisation.sql');
const MULTIPLAYER = read('../migrations/20261030000100_multiplayer.sql');
const SECURITY = read('../migrations/20261030000200_monetisation_security.sql');

const ALICE = '00000000-0000-4000-8000-0000000000a1';
const MALLORY = '00000000-0000-4000-8000-0000000000b2';

// Supabase-like environment: roles, auth helpers, default table grants and a
// service role that bypasses RLS.
async function supabaseLike(migrations) {
  const db = new PGlite();
  await db.exec(`
    create role anon nologin;
    create role authenticated nologin;
    create role service_role nologin bypassrls;
    create schema auth;
    create table auth.users (id uuid primary key);
    create function auth.uid() returns uuid language sql stable as
      $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
    create function auth.jwt() returns jsonb language sql stable as
      $$ select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb $$;
    grant usage on schema auth, public to anon, authenticated, service_role;
    grant execute on function auth.uid(), auth.jwt() to anon, authenticated, service_role;
    alter default privileges in schema public
      grant all on tables to anon, authenticated, service_role;
    insert into auth.users values ('${ALICE}'), ('${MALLORY}');
  `);
  for (const sql of migrations) await db.exec(sql);
  return db;
}

async function as(db, role, sub, sql, params = []) {
  await db.exec(`set request.jwt.claim.sub = '${sub ?? ''}'; set role ${role};`);
  try {
    return (await db.query(sql, params)).rows;
  } finally {
    await db.exec('reset role;');
  }
}

test('BEFORE: the original migration lets anyone grant themselves VIP and coins',
  async () => {
    const db = await supabaseLike([MONETISATION]);
    // Mallory, signed in, records a "purchase" for Alice's account and her own.
    const [vip] = await as(db, 'authenticated', MALLORY,
      `select public.monetisation_record_purchase($1, 'fake-tx', 'buzzmasters_vip_monthly', '£0', false) as r`,
      [MALLORY]);
    assert.equal(vip.r.accepted, true, 'client-side VIP grant was accepted');
    const [coins] = await as(db, 'authenticated', MALLORY,
      `select public.monetisation_grant_ad_reward($1, 'fake-ad', 1, true, 1000, 20) as r`,
      [ALICE]);
    assert.equal(coins.r.outcome, 'granted', 'coins granted to another account');
    // And the bundle loop is broken outright.
    await assert.rejects(
      as(db, 'service_role', null,
        `select public.monetisation_record_purchase($1, 'tx-b', 'buzzmasters_starter_bundle', '£1.99', false)`,
        [ALICE]),
      /column "g" does not exist/);
  });

const fixed = () => supabaseLike([MONETISATION, MULTIPLAYER, SECURITY]);

test('AFTER: clients can no longer call the writers', async () => {
  const db = await fixed();
  await assert.rejects(as(db, 'authenticated', MALLORY,
    `select public.monetisation_record_purchase($1, 't', 'buzzmasters_vip_monthly', '', false)`,
    [MALLORY]), /permission denied/);
  await assert.rejects(as(db, 'authenticated', MALLORY,
    `select public.monetisation_grant_ad_reward($1, 'e', 1, true, 50, 5)`,
    [MALLORY]), /permission denied/);
  await assert.rejects(as(db, 'authenticated', MALLORY,
    `select public.monetisation_store_event('x', $1, 't', 'buzzmasters_vip_monthly', '', false, null, true, 'revenuecat_sync')`,
    [MALLORY]), /permission denied/);
  await assert.rejects(as(db, 'authenticated', MALLORY,
    `select public.monetisation_ssv_reward($1, 'e', 1, 50, 5)`,
    [MALLORY]), /permission denied/);
  await assert.rejects(as(db, 'anon', null,
    `select public.monetisation_entitlement($1)`, [ALICE]), /permission denied/);
  await assert.rejects(as(db, 'authenticated', MALLORY,
    `select public.monetisation_entitlement_unchecked($1)`, [ALICE]),
    /permission denied/);
});

test('AFTER: client RPCs only act on the caller’s own account', async () => {
  const db = await fixed();
  await assert.rejects(as(db, 'authenticated', MALLORY,
    `select public.monetisation_entitlement($1)`, [ALICE]), /forbidden_account/);
  await assert.rejects(as(db, 'authenticated', MALLORY,
    `select public.monetisation_claim_daily_reward($1, 100)`, [ALICE]),
    /forbidden_account/);
  const [own] = await as(db, 'authenticated', ALICE,
    `select public.monetisation_entitlement($1) as r`, [ALICE]);
  assert.equal(own.r.active, false);
  const [daily] = await as(db, 'authenticated', ALICE,
    `select public.monetisation_claim_daily_reward($1, 100) as r`, [ALICE]);
  assert.equal(daily.r.outcome, 'granted');
});

test('AFTER: verified store events grant VIP once, with expiry, and revoke',
  async () => {
    const db = await fixed();
    const expires = '2026-12-01T00:00:00Z';
    const apply = (id, revoked) => as(db, 'service_role', null,
      `select public.monetisation_store_event($1, $2, 'tx-1', 'buzzmasters_vip_monthly', '£3.99', $3, $4, true, 'revenuecat_webhook') as r`,
      [id, ALICE, revoked, expires]);

    const [first] = await apply('evt-1', false);
    assert.equal(first.r.accepted, true);
    const [replay] = await apply('evt-1', false);
    assert.equal(replay.r.duplicate, true, 'the same webhook event applies once');

    let [ent] = await as(db, 'authenticated', ALICE,
      `select public.monetisation_entitlement($1) as r`, [ALICE]);
    assert.equal(ent.r.active, true);
    assert.equal(ent.r.will_renew, true);
    assert.equal(new Date(ent.r.expires_at).toISOString(), '2026-12-01T00:00:00.000Z');

    // Auto-renew turned off: still VIP until expiry.
    await as(db, 'service_role', null,
      `select public.monetisation_store_renewal('evt-2', $1, 'buzzmasters_vip_monthly', false)`,
      [ALICE]);
    [ent] = await as(db, 'authenticated', ALICE,
      `select public.monetisation_entitlement($1) as r`, [ALICE]);
    assert.deepEqual([ent.r.active, ent.r.will_renew], [true, false]);

    // Expiry / refund revokes.
    await apply('evt-3', true);
    [ent] = await as(db, 'authenticated', ALICE,
      `select public.monetisation_entitlement($1) as r`, [ALICE]);
    assert.equal(ent.r.active, false);

    // Non-Buzz-Masters ids (e.g. RevenueCat anonymous ids) are refused.
    const [anonId] = await as(db, 'service_role', null,
      `select public.monetisation_store_event('evt-4', '$RCAnonymousID:abc', 'tx', 'buzzmasters_vip_monthly', '', false, null, false, 'revenuecat_sync') as r`);
    assert.equal(anonId.r.accepted, false);
  });

test('AFTER: bundle purchases grant their items (loop fixed)', async () => {
  const db = await fixed();
  const [r] = await as(db, 'service_role', null,
    `select public.monetisation_store_event('evt-b', $1, 'tx-b', 'buzzmasters_starter_bundle', '£1.99', false, null, false, 'revenuecat_sync') as r`,
    [ALICE]);
  assert.deepEqual(r.r.granted_item_ids,
    ['frame_aurora', 'trail_neon', 'celebration_thunder']);
  const owned = await as(db, 'authenticated', ALICE,
    'select item_id from public.player_inventory order by item_id');
  assert.deepEqual(owned.map((o) => o.item_id),
    ['celebration_thunder', 'frame_aurora', 'trail_neon']);
  // RLS: Mallory sees none of Alice's items.
  const theirs = await as(db, 'authenticated', MALLORY,
    'select item_id from public.player_inventory');
  assert.equal(theirs.length, 0);
});

test('AFTER: SSV-verified ad rewards pay once, respect the cap, and are marked',
  async () => {
    const db = await fixed();
    const reward = (event) => as(db, 'service_role', null,
      `select public.monetisation_ssv_reward($1, $2, 200, 50, 2) as r`, [ALICE, event]);
    assert.equal((await reward('ad-1'))[0].r.outcome, 'granted');
    assert.equal((await reward('ad-1'))[0].r.outcome, 'duplicate');
    assert.equal((await reward('ad-2'))[0].r.outcome, 'granted');
    assert.equal((await reward('ad-3'))[0].r.outcome, 'daily_cap_reached');
    const rows = await as(db, 'authenticated', ALICE,
      `select event_id, verification from public.ad_reward_events order by event_id`);
    assert.deepEqual(rows, [
      { event_id: 'ad-1', verification: 'ssv_verified' },
      { event_id: 'ad-2', verification: 'ssv_verified' },
    ]);
    const wallet = await as(db, 'authenticated', ALICE,
      'select sum(delta)::int as coins from public.wallet_transactions');
    assert.equal(wallet[0].coins, 100);
  });
