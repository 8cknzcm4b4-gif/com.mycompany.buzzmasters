// Runs the Buzz Masters migrations on a real PostgreSQL engine (PGlite, PG 16
// compiled to WebAssembly) and drives the multiplayer RPCs as Supabase's
// `authenticated` role, with a controllable clock.
//
//   cd supabase/tests && npm install && npm test
import { test, before } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '@electric-sql/pglite';

const migrations = [
  '../migrations/20261029000100_monetisation.sql',
  '../migrations/20261030000100_multiplayer.sql',
].map((p) => readFileSync(new URL(p, import.meta.url), 'utf8'));

const db = new PGlite();
const users = {};
let clock = Date.parse('2026-10-30T12:00:00Z');

const uuid = (n) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const at = (ms) => { clock = ms; };
const tick = (ms) => { clock += ms; };

// Calls an RPC exactly as a signed-in client would.
async function rpc(user, fn, args = []) {
  const sub = user ? users[user] : '';
  await db.exec(`
    set test.now = '${new Date(clock).toISOString()}';
    set request.jwt.claim.sub = '${sub}';
    set role ${user ? 'authenticated' : 'anon'};`);
  try {
    const ph = args.map((_, i) => `$${i + 1}`).join(', ');
    const res = await db.query(`select public.${fn}(${ph}) as r`, args);
    return res.rows[0].r;
  } finally {
    await db.exec('reset role;');
  }
}

async function asSuper(sql, params = []) {
  await db.exec(`set test.now = '${new Date(clock).toISOString()}';`);
  return (await db.query(sql, params)).rows;
}

async function correctOption(roomId) {
  const [row] = await asSuper(
    `select q.correct_index from race_rooms r
       join race_questions q on q.id = r.question_ids[r.current_q + 1]
     where r.id = $1`, [roomId]);
  return row.correct_index;
}

before(async () => {
  // Supabase environment stand-ins.
  await db.exec(`
    create role anon nologin;
    create role authenticated nologin;
    create schema auth;
    create table auth.users (id uuid primary key);
    create function auth.uid() returns uuid language sql stable as
      $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
    create function auth.jwt() returns jsonb language sql stable as
      $$ select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb $$;
    grant usage on schema auth to anon, authenticated;
    grant usage on schema public to anon, authenticated;
    grant execute on function auth.uid(), auth.jwt() to anon, authenticated;
  `);
  for (const sql of migrations) await db.exec(sql);
  // Controllable clock for the race timers.
  await db.exec(`
    create or replace function public.race_now() returns timestamptz
    language sql volatile as $$
      select coalesce(nullif(current_setting('test.now', true), '')::timestamptz,
                      clock_timestamp()) $$;`);
  for (let i = 1; i <= 8; i++) {
    users[`p${i}`] = uuid(i);
    await db.query('insert into auth.users (id) values ($1)', [uuid(i)]);
  }
});

test('clients cannot read tables or call the API signed out', async () => {
  await db.exec("set request.jwt.claim.sub = ''; set role authenticated;");
  await assert.rejects(db.query('select * from public.race_questions'),
    /permission denied/);
  await assert.rejects(db.query('select * from public.race_rooms'),
    /permission denied/);
  await assert.rejects(db.query("select public.race_tick(gen_random_uuid())"),
    /permission denied/);
  await db.exec('reset role;');
  await assert.rejects(rpc(null, 'bm_create_room'), /permission denied/);
  const before = await rpc('p1', 'bm_create_room').catch((e) => e.message);
  assert.match(String(before), /no_profile/);
});

test('profiles get unique friend codes and clean names', async () => {
  const names = ['Nova', 'Blaze', 'Echo', 'Jet', 'Pixel', 'Rio', 'Zed', 'Max'];
  const codes = new Set();
  for (let i = 1; i <= 8; i++) {
    const p = await rpc(`p${i}`, 'bm_upsert_profile', [`  ${names[i - 1]}  `, i % 6]);
    assert.equal(p.ok, true);
    assert.equal(p.name, names[i - 1]);
    assert.match(p.friend_code, /^[A-Z0-9]{6}$/);
    codes.add(p.friend_code);
  }
  assert.equal(codes.size, 8);
  const long = await rpc('p8', 'bm_upsert_profile', ['ABCDEFGHIJKLMNOPQRSTUVWXYZ', 9]);
  assert.equal(long.name.length, 16);
  assert.equal(long.color, 5);
});

let room;
let code;

test('six seats: create, join, rejoin, full, bad codes', async () => {
  const created = await rpc('p1', 'bm_create_room');
  assert.equal(created.ok, true);
  assert.match(created.code, /^\d{6}$/);
  assert.equal(created.status, 'lobby');
  assert.equal(created.is_host, true);
  room = created.room_id;
  code = created.code;

  for (let i = 2; i <= 6; i++) {
    const j = await rpc(`p${i}`, 'bm_join_room', [
      i === 3 ? `${code.slice(0, 3)}-${code.slice(3)}` : code]);
    assert.equal(j.ok, true, `p${i} joins`);
    assert.equal(j.players.find((p) => p.is_me).seat, i);
  }
  const again = await rpc('p2', 'bm_join_room', [code]);
  assert.equal(again.ok, true, 'rejoining keeps the seat');
  assert.equal(again.players.length, 6);

  assert.deepEqual(await rpc('p7', 'bm_join_room', [code]),
    { ok: false, error: 'full' });
  assert.deepEqual(await rpc('p7', 'bm_join_room', ['12ab56']),
    { ok: false, error: 'invalid_code' });
  const missing = code === '000000' ? '000001' : '000000';
  assert.deepEqual(await rpc('p7', 'bm_join_room', [missing]),
    { ok: false, error: 'not_found' });
  assert.deepEqual(await rpc('p7', 'bm_room_state', [room]),
    { ok: false, error: 'not_member' });
});

test('only the host can start, and resume finds the live room', async () => {
  assert.deepEqual(await rpc('p2', 'bm_start_race', [room]),
    { ok: false, error: 'not_host' });
  const live = await rpc('p4', 'bm_my_live_room');
  assert.equal(live.ok, true);
  assert.equal(live.code, code);

  const started = await rpc('p1', 'bm_start_race', [room]);
  assert.equal(started.status, 'countdown');
  assert.ok(started.countdown_ms > 2900 && started.countdown_ms <= 3000);
  assert.equal(started.question, null, 'no question during the countdown');
  assert.deepEqual(await rpc('p7', 'bm_join_room', [code]),
    { ok: false, error: 'already_started' });
});

test('answers are judged by the server, once, inside the window', async () => {
  tick(3100);
  const s = await rpc('p1', 'bm_room_state', [room]);
  assert.equal(s.status, 'racing');
  assert.equal(s.question.index, 0);
  assert.equal(s.question.options.length, 4);
  assert.equal(JSON.stringify(s.question).includes('correct'), false,
    'the question never carries its answer');

  const right = await correctOption(room);
  const wrong = (right + 1) % 4;

  // Fast correct (+15), wrong at zero stays at zero.
  const fast = await rpc('p1', 'bm_submit_answer', [room, 0, right]);
  assert.deepEqual([fast.ok, fast.correct, fast.delta], [true, true, 15]);
  const miss = await rpc('p2', 'bm_submit_answer', [room, 0, wrong]);
  assert.deepEqual([miss.correct, miss.delta, miss.progress], [false, 0, 0]);

  // Duplicate, wrong index and bad option are all refused.
  assert.deepEqual(await rpc('p1', 'bm_submit_answer', [room, 0, wrong]),
    { ok: false, error: 'duplicate' });
  assert.deepEqual(await rpc('p3', 'bm_submit_answer', [room, 1, right]),
    { ok: false, error: 'wrong_question' });
  assert.deepEqual(await rpc('p3', 'bm_submit_answer', [room, 0, 9]),
    { ok: false, error: 'invalid_option' });

  // Slow correct (+10) after the fast threshold.
  tick(4000);
  const slow = await rpc('p3', 'bm_submit_answer', [room, 0, right]);
  assert.deepEqual([slow.correct, slow.delta], [true, 10]);

  const mine = await rpc('p1', 'bm_room_state', [room]);
  assert.deepEqual(mine.my_answer, { option: right, correct: true, delta: 15 });
  const me = mine.players.find((p) => p.is_me);
  assert.equal(me.progress, 15);
  assert.equal(me.speed, 'fast');
});

test('the window closes on the server clock: timeouts, reveal, next question',
  async () => {
    tick(4100); // 8.1 s after opening
    assert.deepEqual(await rpc('p4', 'bm_submit_answer', [room, 0, 0]),
      { ok: false, error: 'wrong_question' });
    const s = await rpc('p1', 'bm_room_state', [room]);
    assert.equal(s.questions_resolved, 1);
    assert.equal(s.question_number, 2);
    assert.equal(s.question, null, 'reveal pause before question 2');
    assert.ok(s.next_question_in_ms > 0);
    assert.ok(Number.isInteger(s.last_correct_index));
    const timedOut = s.players.find((p) => p.seat === 4);
    assert.equal(timedOut.progress, 0);
    assert.equal(timedOut.speed, 'stopped');

    tick(1600);
    const q2 = await rpc('p1', 'bm_room_state', [room]);
    assert.equal(q2.question.index, 1);
  });

test('when everyone answers the question resolves at once', async () => {
  const right = await correctOption(room);
  for (let i = 1; i <= 6; i++) {
    const r = await rpc(`p${i}`, 'bm_submit_answer', [room, 1, right]);
    assert.equal(r.ok, true);
  }
  const s = await rpc('p1', 'bm_room_state', [room]);
  assert.equal(s.questions_resolved, 2);
  assert.equal(s.question, null);
});

test('safe start, then the danger zone eliminates after one warning',
  async () => {
    // Q3: only p1 answers; the rest time out. Still inside the safe start.
    tick(1600);
    let right = await correctOption(room);
    await rpc('p1', 'bm_submit_answer', [room, 2, right]);
    tick(8100);
    let s = await rpc('p1', 'bm_room_state', [room]);
    assert.equal(s.questions_resolved, 3);
    assert.ok(s.players.every((p) => !p.eliminated));

    // p2 left the race mid-way: forfeits but the race carries on.
    assert.deepEqual(await rpc('p2', 'bm_leave_room', [room]), { ok: true });

    // Q4 and Q5: p1 keeps answering, everyone else sits at <= 10.
    for (const q of [3, 4]) {
      tick(1600);
      right = await correctOption(room);
      const ans = await rpc('p1', 'bm_submit_answer', [room, q, right]);
      assert.equal(ans.ok, true, `p1 answers question ${q}`);
      tick(8100);
      await rpc('p1', 'bm_room_state', [room]); // clients poll; this resolves
    }
    s = await rpc('p1', 'bm_room_state', [room]);
    const bySeat = Object.fromEntries(s.players.map((p) => [p.seat, p]));
    assert.equal(bySeat[1].eliminated, false);
    assert.equal(bySeat[2].left, true);
    assert.equal(bySeat[2].eliminated, true);
    // Seat 3 banked 25 (slow +10, fast +15), so it is still clear: 25-9=16.
    assert.equal(bySeat[3].eliminated, false);
    assert.equal(bySeat[3].progress, 16);
    // Seats 4-6 had 15: 12 after Q3, 9 after Q4 (warned), 6 after Q5 (out).
    for (const seat of [4, 5, 6]) {
      assert.equal(bySeat[seat].progress, 6);
      assert.equal(bySeat[seat].eliminated, true, `seat ${seat} out`);
    }
  });

test('reaching the distance finishes the race with placings and a leaderboard',
  async () => {
    let s = await rpc('p1', 'bm_room_state', [room]);
    // Only p1 is still racing, so the race ended when everyone else was out.
    if (s.status !== 'finished') {
      for (let q = s.question_number - 1; q < 30 && s.status === 'racing'; q++) {
        tick(1600);
        await rpc('p1', 'bm_submit_answer', [room, q, await correctOption(room)]);
        tick(8100); // seat 3 stays silent and times out
        s = await rpc('p1', 'bm_room_state', [room]);
      }
    }
    assert.equal(s.status, 'finished');
    assert.equal(s.results.length, 6);
    assert.equal(s.results[0].name, 'Nova');
    assert.equal(s.results[0].placing, 1);
    assert.equal(new Set(s.results.map((r) => r.placing)).size, 6);

    const board = await rpc('p3', 'bm_leaderboard', [10]);
    assert.equal(board.ok, true);
    assert.equal(board.rows[0].name, 'Nova');
    assert.equal(board.rows[0].wins, 1);
    assert.equal(board.rows.find((r) => r.is_me).races, 1);

    assert.deepEqual(await rpc('p1', 'bm_my_live_room'),
      { ok: false, error: 'none' });
    assert.deepEqual(await rpc('p1', 'bm_submit_answer', [room, 0, 0]),
      { ok: false, error: 'not_racing' });
  });

test('a racer who reaches 100 wins outright', async () => {
  const r = await rpc('p7', 'bm_create_room');
  await rpc('p8', 'bm_join_room', [r.code]);
  await rpc('p7', 'bm_start_race', [r.room_id]);
  tick(3100);
  let s;
  for (let q = 0; q < 7; q++) {
    s = await rpc('p7', 'bm_room_state', [r.room_id]);
    if (s.status !== 'racing') break;
    const right = await correctOption(r.room_id);
    await rpc('p7', 'bm_submit_answer', [r.room_id, q, right]);
    await rpc('p8', 'bm_submit_answer', [r.room_id, q, right]);
    tick(1600);
    // p8 answers 4 s late each time; p7 always fast: 15 x 7 = 105 -> finish.
  }
  s = await rpc('p8', 'bm_room_state', [r.room_id]);
  assert.equal(s.status, 'finished');
  assert.equal(s.results[0].name, 'Zed');
  assert.equal(s.results[0].finished, true);
});

test('lobbies expire, empty lobbies are abandoned, and host passes on',
  async () => {
    const a = await rpc('p3', 'bm_create_room');
    await rpc('p4', 'bm_join_room', [a.code]);
    await rpc('p3', 'bm_leave_room', [a.room_id]);
    const s = await rpc('p4', 'bm_room_state', [a.room_id]);
    assert.equal(s.is_host, true, 'host passes to the next seat');

    const b = await rpc('p5', 'bm_create_room');
    tick(31 * 60 * 1000);
    assert.deepEqual(await rpc('p6', 'bm_join_room', [b.code]),
      { ok: false, error: 'expired' });

    const c = await rpc('p6', 'bm_create_room');
    await rpc('p6', 'bm_leave_room', [c.room_id]);
    const [row] = await asSuper('select status from race_rooms where id = $1',
      [c.room_id]);
    assert.equal(row.status, 'abandoned');
    assert.deepEqual(await rpc('p6', 'bm_start_race', [c.room_id]),
      { ok: false, error: 'already_started' });
  });

test('starting alone is refused', async () => {
  const r = await rpc('p5', 'bm_create_room');
  assert.deepEqual(await rpc('p5', 'bm_start_race', [r.room_id]),
    { ok: false, error: 'not_enough_players' });
  await rpc('p5', 'bm_leave_room', [r.room_id]);
});

test('friends by code, requests, invites into a lobby', async () => {
  const me = await rpc('p1', 'bm_friends');
  const p2code = (await rpc('p2', 'bm_friends')).my_code;
  assert.deepEqual(await rpc('p1', 'bm_send_friend_request', [me.my_code]),
    { ok: false, error: 'self' });
  assert.deepEqual(await rpc('p1', 'bm_send_friend_request', ['ZZZZZZ']),
    { ok: false, error: 'not_found' });
  assert.deepEqual(
    await rpc('p1', 'bm_send_friend_request', [p2code.toLowerCase()]),
    { ok: true, status: 'pending' });

  const inbox = await rpc('p2', 'bm_friends');
  assert.equal(inbox.incoming[0].name, 'Nova');
  assert.deepEqual(
    await rpc('p2', 'bm_respond_friend_request', [users.p1, true]),
    { ok: true });
  assert.equal((await rpc('p1', 'bm_friends')).friends[0].name, 'Blaze');

  const lobby = await rpc('p1', 'bm_create_room');
  assert.deepEqual(await rpc('p1', 'bm_invite_friend', [lobby.room_id, users.p5]),
    { ok: false, error: 'not_friends' });
  assert.deepEqual(await rpc('p1', 'bm_invite_friend', [lobby.room_id, users.p2]),
    { ok: true });
  const invites = (await rpc('p2', 'bm_friends')).invites;
  assert.equal(invites.length, 1);
  assert.equal(invites[0].code, lobby.code);
  assert.equal(invites[0].from, 'Nova');

  await rpc('p2', 'bm_join_room', [invites[0].code]);
  assert.equal((await rpc('p2', 'bm_friends')).invites.length, 0,
    'joining clears the invite');

  // Mutual request auto-accepts.
  const p4code = (await rpc('p4', 'bm_friends')).my_code;
  const p3code = (await rpc('p3', 'bm_friends')).my_code;
  await rpc('p3', 'bm_send_friend_request', [p4code]);
  assert.deepEqual(await rpc('p4', 'bm_send_friend_request', [p3code]),
    { ok: true, status: 'accepted' });

  assert.deepEqual(await rpc('p1', 'bm_remove_friend', [users.p2]), { ok: true });
  assert.equal((await rpc('p1', 'bm_friends')).friends.length, 0);
});

test('the monetisation API keeps its grants', async () => {
  await db.exec(`set request.jwt.claim.sub = '${users.p1}'; set role authenticated;`);
  try {
    const res = await db.query('select public.wallet_balance($1) as b', [users.p1]);
    assert.equal(Number(res.rows[0].b), 0);
  } finally {
    await db.exec('reset role;');
  }
});
