// Community, moderation, readiness, public lobbies, rotation, rankings,
// notifications, rate limits and Realtime signals — on a real PostgreSQL
// engine (PGlite, PG 16), with every migration applied in order on a
// Supabase-like environment (default table grants, realtime publication).
import { test, before } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { PGlite } from '@electric-sql/pglite';

const dir = new URL('../migrations/', import.meta.url);
const files = readdirSync(dir).filter((f) => f.endsWith('.sql')).sort();

const db = new PGlite();
const users = {};
let clock = Date.parse('2026-10-30T12:00:00Z');
const uuid = (n) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const tick = (ms) => { clock += ms; };

async function as(user, sql, params = []) {
  await db.exec(`
    set test.now = '${new Date(clock).toISOString()}';
    set request.jwt.claim.sub = '${user ? users[user] : ''}';
    set role ${user ? 'authenticated' : 'anon'};`);
  try {
    return (await db.query(sql, params)).rows;
  } finally {
    await db.exec('reset role;');
  }
}

async function rpc(user, fn, args = []) {
  const ph = args.map((_, i) => `$${i + 1}`).join(', ');
  const [row] = await as(user, `select public.${fn}(${ph}) as r`, args);
  return row.r;
}

async function sql(text, params = []) {
  await db.exec(`set test.now = '${new Date(clock).toISOString()}';`);
  return (await db.query(text, params)).rows;
}

async function lobbyWith(host, guests, { isPublic = false } = {}) {
  const room = await rpc(host, 'bm_create_room', isPublic ? [true] : []);
  assert.equal(room.ok, true, JSON.stringify(room));
  for (const g of guests) {
    const j = await rpc(g, 'bm_join_room', [room.code]);
    assert.equal(j.ok, true, JSON.stringify(j));
  }
  return room;
}

before(async () => {
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
    -- Supabase grants table access by default; RLS and the migrations' own
    -- revokes are what must keep clients out.
    alter default privileges in schema public
      grant all on tables to anon, authenticated, service_role;
    create publication supabase_realtime;
  `);
  for (const f of files) await db.exec(readFileSync(new URL(f, dir), 'utf8'));
  await db.exec(`
    create or replace function public.race_now() returns timestamptz
    language sql volatile as $$
      select coalesce(nullif(current_setting('test.now', true), '')::timestamptz,
                      clock_timestamp()) $$;`);
  for (let i = 1; i <= 9; i++) {
    users[`p${i}`] = uuid(i);
    await db.query('insert into auth.users (id) values ($1)', [uuid(i)]);
    await rpc(`p${i}`, 'bm_upsert_profile', [`Racer ${i}`, i % 6]);
  }
});

test('every migration applies in order and Realtime publishes only the two signal tables', async () => {
  assert.deepEqual(files, [
    '20261029000100_monetisation.sql',
    '20261030000100_multiplayer.sql',
    '20261030000200_monetisation_security.sql',
    '20261030000300_account_deletion.sql',
    '20261030000400_community_and_moderation.sql',
  ]);
  const pub = await sql(`select tablename from pg_publication_tables
                         where pubname = 'supabase_realtime' order by 1`);
  assert.deepEqual(pub.map((r) => r.tablename),
    ['player_notifications', 'race_room_signals']);
  const count = await sql(`select count(*)::int as n from race_questions where active`);
  assert.equal(count[0].n, 60);
  const fixed = await sql(`select prompt from race_questions where id = 'q023'`);
  assert.equal(fixed[0].prompt, 'What is "app" short for?');
});

test('RLS: new tables are closed to clients; signals and notifications are member/owner only', async () => {
  for (const t of ['player_blocks', 'player_reports', 'question_reports',
    'player_question_history', 'bm_rate_hits']) {
    await assert.rejects(as('p1', `select * from public.${t}`), /permission denied/, t);
    await assert.rejects(as('p1', `insert into public.${t} default values`), /permission denied/, t);
  }
  await assert.rejects(as(null, 'select * from public.race_room_signals'), /permission denied/);
  await assert.rejects(as('p1', `update public.race_room_signals set version = 0`), /permission denied/);
  await assert.rejects(as('p1', `delete from public.player_notifications`), /permission denied/);
  await assert.rejects(rpc(null, 'bm_quick_join'), /permission denied/);
  for (const fn of ['bm_rate_ok', 'bm_notify', 'bm_is_blocked', 'race_signal']) {
    const [{ granted }] = await sql(
      `select bool_or(has_function_privilege('authenticated', p.oid, 'execute')) as granted
         from pg_proc p where proname = $1`, [fn]);
    assert.equal(granted, false, fn);
  }

  const room = await lobbyWith('p1', ['p2']);
  const seenByMember = await as('p2', 'select room_id, version from race_room_signals');
  assert.deepEqual(seenByMember.map((r) => r.room_id), [room.room_id]);
  const before = Number(seenByMember[0].version);
  assert.deepEqual(await as('p3', 'select * from race_room_signals'), []);
  await rpc('p2', 'bm_set_ready', [room.room_id, true]);
  const [after] = await as('p1', 'select version from race_room_signals where room_id = $1', [room.room_id]);
  assert.ok(Number(after.version) > before, 'a seat change bumps the signal');
  // Polling refreshes last_seen but must not signal, or clients would loop.
  tick(500);
  await rpc('p1', 'bm_room_state', [room.room_id]);
  await rpc('p2', 'bm_room_state', [room.room_id]);
  const [polled] = await as('p1', 'select version from race_room_signals where room_id = $1', [room.room_id]);
  assert.equal(Number(polled.version), Number(after.version), 'polls do not bump the signal');
  await rpc('p1', 'bm_leave_room', [room.room_id]);
  await rpc('p2', 'bm_leave_room', [room.room_id]);
});

test('readiness: members toggle it, the host counts as ready, and it locks once started', async () => {
  const room = await lobbyWith('p1', ['p2', 'p3']);
  assert.equal(room.is_public, false);
  let s = await rpc('p1', 'bm_room_state', [room.room_id]);
  assert.equal(s.all_ready, false);
  assert.deepEqual(s.players.map((p) => p.ready), [true, false, false]);
  s = await rpc('p2', 'bm_set_ready', [room.room_id, true]);
  s = await rpc('p3', 'bm_set_ready', [room.room_id, true]);
  assert.equal(s.all_ready, true);
  s = await rpc('p3', 'bm_set_ready', [room.room_id, false]);
  assert.equal(s.all_ready, false);
  assert.equal((await rpc('p4', 'bm_set_ready', [room.room_id, true])).error, 'not_member');
  assert.equal((await rpc('p1', 'bm_start_race', [room.room_id])).status, 'countdown');
  assert.equal((await rpc('p2', 'bm_set_ready', [room.room_id, false])).error, 'already_started');
  for (const p of ['p1', 'p2', 'p3']) await rpc(p, 'bm_leave_room', [room.room_id]);
});

test('quick race: joins the fullest public lobby, never a private one, else opens one', async () => {
  const priv = await lobbyWith('p1', []);
  const first = await rpc('p2', 'bm_quick_join');
  assert.equal(first.ok, true);
  assert.equal(first.is_public, true);
  assert.notEqual(first.room_id, priv.room_id);
  assert.equal(first.is_host, true);
  const second = await rpc('p3', 'bm_quick_join');
  assert.equal(second.room_id, first.room_id);
  assert.equal(second.players.length, 2);
  // Asking again while seated returns the same room (resume), not a new seat.
  const again = await rpc('p3', 'bm_quick_join');
  assert.equal(again.room_id, first.room_id);
  assert.equal(again.players.length, 2);
  for (const [p, r] of [['p1', priv], ['p2', first], ['p3', first]]) {
    await rpc(p, 'bm_leave_room', [r.room_id]);
  }
});

test('blocking removes the friendship and keeps both players apart', async () => {
  const codes = {};
  for (const p of ['p4', 'p5']) codes[p] = (await rpc(p, 'bm_friends')).my_code;
  assert.equal((await rpc('p4', 'bm_send_friend_request', [codes.p5])).status, 'pending');
  assert.equal((await rpc('p5', 'bm_send_friend_request', [codes.p4])).status, 'accepted');
  assert.equal((await rpc('p4', 'bm_friends')).friends.length, 1);

  assert.equal((await rpc('p4', 'bm_block_player', [users.p5])).ok, true);
  assert.equal((await rpc('p4', 'bm_friends')).friends.length, 0);
  assert.deepEqual((await rpc('p4', 'bm_blocked_players')).players.map((p) => p.id), [users.p5]);
  // The blocked player is not told; the code just "does not exist".
  assert.equal((await rpc('p5', 'bm_send_friend_request', [codes.p4])).error, 'not_found');
  assert.equal((await rpc('p4', 'bm_block_player', [users.p4])).error, 'self');

  const lobby = await lobbyWith('p4', [], { isPublic: true });
  assert.equal((await rpc('p5', 'bm_join_room', [lobby.code])).error, 'blocked');
  const quick = await rpc('p5', 'bm_quick_join');
  assert.notEqual(quick.room_id, lobby.room_id, 'quick race skips a blocker\'s lobby');
  await rpc('p5', 'bm_leave_room', [quick.room_id]);

  await rpc('p4', 'bm_unblock_player', [users.p5]);
  assert.equal((await rpc('p5', 'bm_join_room', [lobby.code])).ok, true);
  await rpc('p5', 'bm_leave_room', [lobby.room_id]);
  await rpc('p4', 'bm_leave_room', [lobby.room_id]);
});

test('reports: validated, de-duplicated, rate limited; questions by number, flagged at three', async () => {
  assert.equal((await rpc('p6', 'bm_report_player', [users.p7, 'spam'])).error, 'invalid_reason');
  assert.equal((await rpc('p6', 'bm_report_player', [users.p6, 'other'])).error, 'self');
  const r1 = await rpc('p6', 'bm_report_player', [users.p7, 'offensive_name', '  rude  ']);
  assert.deepEqual([r1.ok, r1.duplicate], [true, false]);
  assert.equal((await rpc('p6', 'bm_report_player', [users.p7, 'cheating'])).duplicate, true);
  const [rep] = await sql('select reason, details, status from player_reports where reporter = $1', [users.p6]);
  assert.deepEqual(rep, { reason: 'offensive_name', details: 'rude', status: 'open' });

  const room = await lobbyWith('p1', ['p2', 'p3', 'p6']);
  assert.equal((await rpc('p1', 'bm_report_question', [room.room_id, 0, 'unclear'])).error, 'wrong_question');
  await rpc('p1', 'bm_start_race', [room.room_id]);
  tick(3100);
  const live = await rpc('p1', 'bm_room_state', [room.room_id]);
  assert.equal(live.status, 'racing');
  assert.equal(live.question.id, undefined, 'question ids never reach clients');
  assert.equal((await rpc('p9', 'bm_report_question', [room.room_id, 0, 'unclear'])).error, 'not_member');
  assert.equal((await rpc('p1', 'bm_report_question', [room.room_id, 5, 'unclear'])).error, 'wrong_question');
  for (const p of ['p1', 'p2']) {
    assert.equal((await rpc(p, 'bm_report_question', [room.room_id, 0, 'wrong_answer'])).ok, true);
  }
  assert.equal((await rpc('p1', 'bm_report_question', [room.room_id, 0, 'other'])).duplicate, true);
  const qid = (await sql('select question_ids[1] as q from race_rooms where id = $1', [room.room_id]))[0].q;
  const flag = async () => (await sql('select needs_review, active from race_questions where id = $1', [qid]))[0];
  assert.deepEqual(await flag(), { needs_review: false, active: true });
  await rpc('p3', 'bm_report_question', [room.room_id, 0, 'wrong_answer']);
  assert.deepEqual(await flag(), { needs_review: true, active: true });

  // p6 has used one report today; nine more are allowed, then refused.
  const targets = ['p1', 'p2', 'p3', 'p4', 'p5', 'p8', 'p9'];
  for (const t of targets) await rpc('p6', 'bm_report_player', [users[t], 'other']);
  await rpc('p6', 'bm_report_question', [room.room_id, 0, 'unclear']);
  tick(8000);
  await rpc('p6', 'bm_room_state', [room.room_id]);
  tick(2000);
  await rpc('p6', 'bm_room_state', [room.room_id]);
  assert.equal((await rpc('p6', 'bm_report_question', [room.room_id, 1, 'unclear'])).ok, true);
  assert.equal((await rpc('p6', 'bm_report_question', [room.room_id, 1, 'other'])).duplicate, true);
  tick(10000);
  await rpc('p6', 'bm_room_state', [room.room_id]);
  assert.equal((await rpc('p6', 'bm_report_question', [room.room_id, 2, 'unclear'])).error, 'rate_limited');
  for (const p of ['p1', 'p2', 'p3', 'p6']) await rpc(p, 'bm_leave_room', [room.room_id]);
});

test('question rotation: the same field gets fresh questions next race', async () => {
  const a = await lobbyWith('p7', ['p8']);
  await rpc('p7', 'bm_start_race', [a.room_id]);
  const b = await lobbyWith('p7', ['p8']);
  await rpc('p7', 'bm_start_race', [b.room_id]);
  const [{ first, second }] = await sql(`
    select (select question_ids from race_rooms where id = $1) as first,
           (select question_ids from race_rooms where id = $2) as second`,
  [a.room_id, b.room_id]);
  assert.equal(first.length, 30);
  assert.equal(second.length, 30);
  assert.equal(first.filter((q) => second.includes(q)).length, 0,
    'a 60-question bank gives two races with no repeats');
  const [{ n }] = await sql('select count(*)::int as n from player_question_history where player_id = $1', [users.p7]);
  assert.equal(n, 60);
  for (const r of [a, b]) for (const p of ['p7', 'p8']) await rpc(p, 'bm_leave_room', [r.room_id]);
});

test('weekly and monthly rankings count only results in that period', async () => {
  const room = (await sql(`insert into race_rooms (code, host_id, expires_at, status)
    values ('999001', $1, now(), 'finished') returning id`, [users.p9]))[0].id;
  const old = (await sql(`insert into race_rooms (code, host_id, expires_at, status)
    values ('999002', $1, now(), 'finished') returning id`, [users.p9]))[0].id;
  // 2026-10-30 is a Friday: this week started Monday 26 Oct.
  await sql(`insert into race_results (room_id, player_id, finish_place, progress,
    finished, eliminated, correct, answered, recorded_at) values
    ($1, $3, 1, 100, true, false, 9, 10, '2026-10-29T10:00:00Z'),
    ($2, $3, 1, 100, true, false, 9, 10, '2026-10-05T10:00:00Z'),
    ($2, $4, 2, 80, false, false, 7, 10, '2026-09-20T10:00:00Z')`,
  [room, old, users.p9, users.p8]);
  const row = (rows, id) => rows.find((r) => r.id === id);
  const week = await rpc('p9', 'bm_leaderboard_period', ['week', 50]);
  const month = await rpc('p9', 'bm_leaderboard_period', ['month', 50]);
  const all = await rpc('p9', 'bm_leaderboard_period', ['all', 50]);
  assert.equal(row(week.rows, users.p9).wins, 1);
  assert.equal(row(month.rows, users.p9).wins, 2);
  assert.equal(row(week.rows, users.p8), undefined);
  assert.equal(row(all.rows, users.p8).races, 1);
  assert.equal(row(week.rows, users.p9).is_me, true);
  assert.equal((await rpc('p9', 'bm_leaderboard_period', ['year', 50])).error, 'invalid_period');
  const history = await rpc('p9', 'bm_race_history', [10]);
  assert.deepEqual(history.races.map((r) => r.placing), [1, 1]);
});

test('notifications: friend requests, acceptances, invites and results reach only the recipient', async () => {
  await rpc('p2', 'bm_mark_notifications_read');
  const code2 = (await rpc('p2', 'bm_friends')).my_code;
  await rpc('p1', 'bm_send_friend_request', [code2]);
  let n2 = await rpc('p2', 'bm_notifications', [10]);
  assert.equal(n2.unread, 1);
  assert.equal(n2.items[0].kind, 'friend_request');
  assert.equal(n2.items[0].payload.from, 'Racer 1');
  await rpc('p2', 'bm_respond_friend_request', [users.p1, true]);
  const n1 = await rpc('p1', 'bm_notifications', [10]);
  assert.equal(n1.items[0].kind, 'friend_accepted');

  const room = await lobbyWith('p1', []);
  await rpc('p1', 'bm_invite_friend', [room.room_id, users.p2]);
  n2 = await rpc('p2', 'bm_notifications', [10]);
  assert.equal(n2.items[0].kind, 'race_invite');
  assert.equal(n2.items[0].payload.code, room.code);
  // Realtime reads go through RLS: own rows only.
  const mine = await as('p2', 'select distinct player_id from player_notifications');
  assert.deepEqual(mine.map((r) => r.player_id), [users.p2]);
  await rpc('p2', 'bm_mark_notifications_read');
  assert.equal((await rpc('p2', 'bm_notifications', [10])).unread, 0);
  const results = await rpc('p9', 'bm_notifications', [10]);
  assert.ok(results.items.some((i) => i.kind === 'race_result' && i.payload.placing === 1));
  await rpc('p1', 'bm_leave_room', [room.room_id]);
});

test('abuse protection: lobby creation is capped per hour', async () => {
  let last;
  const made = [];
  for (let i = 0; i < 25; i++) {
    last = await rpc('p3', 'bm_create_room');
    if (!last.ok) break;
    made.push(last.room_id);
    await rpc('p3', 'bm_leave_room', [last.room_id]);
  }
  assert.equal(last.error, 'rate_limited');
  assert.ok(made.length <= 20 && made.length >= 1, `made ${made.length}`);
  tick(3600 * 1000);
  const fresh = await rpc('p3', 'bm_create_room');
  assert.equal(fresh.ok, true, 'the limit resets in the next hour');
  await rpc('p3', 'bm_leave_room', [fresh.room_id]);
});

test('account deletion also erases blocks, reports, history and notifications', async () => {
  const id = users.p6;
  await rpc('p6', 'bm_block_player', [users.p9]);
  const count = async () => (await sql(`select
      (select count(*) from player_blocks where blocker = $1 or blocked = $1)
    + (select count(*) from player_reports where reporter = $1 or target = $1)
    + (select count(*) from question_reports where reporter = $1)
    + (select count(*) from player_question_history where player_id = $1)
    + (select count(*) from player_notifications where player_id = $1)
    + (select count(*) from bm_rate_hits where player_id = $1) as n`, [id]))[0].n;
  assert.ok(Number(await count()) > 0);
  await db.exec('set role service_role;');
  try {
    const [{ r }] = (await db.query('select public.bm_purge_account($1::uuid) as r', [id])).rows;
    assert.equal(r.ok, true);
  } finally {
    await db.exec('reset role;');
  }
  assert.equal(Number(await count()), 0);
});
