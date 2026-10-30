// Account deletion on a real PostgreSQL engine (PGlite, PG 16).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '@electric-sql/pglite';

const read = (f) => readFileSync(new URL(`../migrations/${f}`, import.meta.url), 'utf8');
const A = '00000000-0000-4000-8000-00000000000a';
const B = '00000000-0000-4000-8000-00000000000b';

async function setup() {
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
    insert into auth.users values ('${A}'), ('${B}');
  `);
  for (const f of ['20261029000100_monetisation.sql', '20261030000100_multiplayer.sql',
    '20261030000200_monetisation_security.sql', '20261030000300_account_deletion.sql']) {
    await db.exec(read(f));
  }
  return db;
}

async function as(db, role, sub, sql, params = []) {
  await db.exec(`set request.jwt.claim.sub = '${sub ?? ''}'; set role ${role};`);
  try { return (await db.query(sql, params)).rows; } finally { await db.exec('reset role;'); }
}

const counts = async (db, id) => (await db.query(`
  select
    (select count(*) from player_profiles where id = $1::uuid)::int as profile,
    (select count(*) from race_room_players where player_id = $1::uuid)::int as seats,
    (select count(*) from race_rooms where host_id = $1::uuid)::int as rooms,
    (select count(*) from friend_links where requester = $1::uuid or addressee = $1::uuid)::int as friends,
    (select count(*) from player_entitlements where account_id = $1::text)::int as vip,
    (select count(*) from player_inventory where account_id = $1::text)::int as items,
    (select count(*) from wallet_transactions where account_id = $1::text)::int as wallet,
    (select count(*) from purchase_events where account_id = $1::text)::int as purchases,
    (select count(*) from ad_reward_events where account_id = $1::text)::int as ads`,
[id])).rows[0];

test('a purge erases one player completely and leaves others intact', async () => {
  const db = await setup();
  for (const [id, name] of [[A, 'Ann'], [B, 'Ben']]) {
    await as(db, 'authenticated', id, 'select public.bm_upsert_profile($1, 1)', [name]);
  }
  const room = (await as(db, 'authenticated', A, 'select public.bm_create_room() as r'))[0].r;
  await as(db, 'authenticated', B, 'select public.bm_join_room($1)', [room.code]);
  const benRoom = (await as(db, 'authenticated', B, 'select public.bm_create_room() as r'))[0].r;
  await as(db, 'authenticated', A, 'select public.bm_join_room($1)', [benRoom.code]);
  const benCode = (await as(db, 'authenticated', B, 'select public.bm_friends() as r'))[0].r.my_code;
  await as(db, 'authenticated', A, 'select public.bm_send_friend_request($1)', [benCode]);
  for (const id of [A, B]) {
    await as(db, 'service_role', null,
      `select public.monetisation_store_event($1, $2, 'tx', 'buzzmasters_starter_bundle', '', false, null, false, 'revenuecat_sync')`,
      [`e-${id}`, id]);
    await as(db, 'service_role', null,
      `select public.monetisation_store_event($1, $2, 'tx-v', 'buzzmasters_vip_monthly', '', false, null, true, 'revenuecat_sync')`,
      [`v-${id}`, id]);
    await as(db, 'service_role', null,
      'select public.monetisation_ssv_reward($1, $2, 1, 50, 5)', [id, `ad-${id}`]);
  }
  const before = await counts(db, A);
  assert.ok(Object.values(before).every((n) => n > 0), JSON.stringify(before));

  // Clients cannot purge anyone, themselves included.
  await assert.rejects(as(db, 'authenticated', A,
    'select public.bm_purge_account($1)', [A]), /permission denied/);

  const [res] = await as(db, 'service_role', null,
    'select public.bm_purge_account($1) as r', [A]);
  assert.equal(res.r.ok, true);
  assert.deepEqual(await counts(db, A), {
    profile: 0, seats: 0, rooms: 0, friends: 0, vip: 0, items: 0, wallet: 0,
    purchases: 0, ads: 0,
  });

  const ben = await counts(db, B);
  assert.equal(ben.profile, 1);
  assert.equal(ben.rooms, 1, "Ben's own room survives");
  assert.equal(ben.seats, 1, "Ann's room went with her; Ben keeps his seat in his");
  assert.equal(ben.vip, 1);
  assert.equal(ben.items, 3);
  assert.equal(ben.wallet, 1);

  // Deleting the auth user afterwards (as the Edge Function does) is clean.
  await db.query('delete from auth.users where id = $1', [A]);
});
