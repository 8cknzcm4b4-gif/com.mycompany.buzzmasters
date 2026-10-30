// The server API against the Firestore emulator (real transactions and
// concurrency), with a controllable clock. Run with `npm run test:emulator`.
/* eslint-disable @typescript-eslint/no-explicit-any */
import { test, before } from 'node:test';
import assert from 'node:assert/strict';
import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { Api } from '../src/api';
import * as E from '../src/engine';

assert.ok(process.env.FIRESTORE_EMULATOR_HOST, 'run inside the Firestore emulator');
initializeApp({ projectId: 'demo-buzz-masters' });
const db = getFirestore();
let clock = Date.parse('2026-10-30T12:00:00Z');
const api = new Api(db, () => clock);
const call = (uid: string, op: string, args: Record<string, unknown> = {}) =>
  api.handle(op, uid, args) as Promise<any>;
const U = Array.from({ length: 9 }, (_, i) => `racerUid00000000000000000${i + 1}`);

async function correctFor(roomId: string) {
  const [r, s] = await Promise.all([
    db.doc(`rooms/${roomId}`).get(), db.doc(`rooms/${roomId}/secret/state`).get()]);
  return (s.data() as E.Secret).questions[(r.data() as E.Room).currentQ].correctIndex;
}

before(async () => {
  for (let i = 0; i < U.length; i++) {
    const p = await call(U[i], 'upsertProfile', { name: `  Racer ${i + 1} `, color: i % 6 });
    assert.equal(p.ok, true);
  }
});

test('profiles: a profile is required, names are cleaned, friend codes are unique', async () => {
  assert.deepEqual(await call('nobodyUid000000000000000000', 'createRoom'),
    { ok: false, error: 'no_profile' });
  const codes = new Set<string>();
  for (const u of U) codes.add((await call(u, 'friends')).my_code);
  assert.equal(codes.size, U.length);
  const p = await call(U[0], 'upsertProfile', { name: 'Nova', color: 0 });
  assert.equal(p.name, 'Nova');
  assert.equal((await call(U[0], 'friends')).my_code, [...codes][0], 'code kept on rename');
  assert.equal((await call(U[0], 'nonsense')).error, 'unknown_op');
});

let room = '';
let code = '';

test('six seats: create, join, rejoin, full, bad and unknown codes', async () => {
  const created = await call(U[0], 'createRoom');
  assert.equal(created.ok, true);
  assert.match(created.code, /^\d{6}$/);
  assert.equal(created.is_host, true);
  room = created.room_id;
  code = created.code;
  for (let i = 1; i < 6; i++) {
    const j = await call(U[i], 'joinRoom', { code: `${code.slice(0, 3)}-${code.slice(3)}` });
    assert.equal(j.ok, true, JSON.stringify(j));
    assert.equal(j.players.length, i + 1);
  }
  const again = await call(U[2], 'joinRoom', { code });
  assert.equal(again.players.length, 6, 'rejoining keeps the seat');
  assert.equal((await call(U[6], 'joinRoom', { code })).error, 'full');
  assert.equal((await call(U[6], 'joinRoom', { code: '12a' })).error, 'invalid_code');
  const unknown = code === '000000' ? '000001' : '000000';
  assert.equal((await call(U[6], 'joinRoom', { code: unknown })).error, 'not_found');
  assert.equal((await call(U[6], 'roomState', { roomId: room })).error, 'not_member');
});

test('readiness, then only the host can start, and resume finds the live room', async () => {
  const s = await call(U[1], 'setReady', { roomId: room, ready: true });
  assert.equal(s.players.find((p: any) => p.is_me).ready, true);
  assert.equal(s.all_ready, false);
  assert.equal((await call(U[1], 'startRace', { roomId: room })).error, 'not_host');
  const started = await call(U[0], 'startRace', { roomId: room });
  assert.equal(started.status, 'countdown');
  assert.equal(started.countdown_ms, E.RULES.countdownMs);
  assert.equal(started.question, null);
  const live = await call(U[3], 'myLiveRoom');
  assert.equal(live.room_id, room);
  assert.equal((await call(U[1], 'setReady', { roomId: room, ready: false })).error, 'already_started');
  const hist = await db.doc(`questionHistory/${U[0]}`).get();
  assert.equal(Object.keys(hist.get('seen')).length, 30);
});

test('six racers answer at the same instant: each answer is judged once', async () => {
  clock += E.RULES.countdownMs;
  const open = await call(U[0], 'roomState', { roomId: room });
  assert.equal(open.status, 'racing');
  assert.equal(open.question.index, 0);
  assert.deepEqual(Object.keys(open.question).sort(),
    ['category', 'difficulty', 'index', 'options', 'prompt', 'remaining_ms']);
  assert.equal(open.last_correct_index, null, 'no answer key in the view');
  const ok = await correctFor(room);
  clock += 1000;
  // Real concurrent transactions; racer 6 double-submits at the same time.
  const results = await Promise.all([
    ...U.slice(0, 6).map((u) => call(u, 'submitAnswer', { roomId: room, question: 0, option: ok })),
    call(U[5], 'submitAnswer', { roomId: room, question: 0, option: ok }),
  ]);
  const accepted = results.filter((r) => r.ok);
  assert.equal(accepted.length, 6);
  assert.equal(results.filter((r) => r.error === 'duplicate').length, 1);
  for (const r of accepted) assert.deepEqual([r.correct, r.delta], [true, 15]);
  const after = await call(U[0], 'roomState', { roomId: room });
  assert.equal(after.questions_resolved, 1, 'all answered: resolved at once');
  assert.equal(after.players.every((p: any) => p.progress === 15), true);
});

test('a dropped racer times out, reconnects and races on', async () => {
  clock += E.RULES.revealMs;
  await call(U[0], 'roomState', { roomId: room });
  const ok = await correctFor(room);
  // Racer 6 is silent this question.
  await Promise.all(U.slice(0, 5).map((u) =>
    call(u, 'submitAnswer', { roomId: room, question: 1, option: ok })));
  clock += E.RULES.windowMs;
  const s = await call(U[5], 'roomState', { roomId: room });
  assert.equal(s.question_number, 3);
  assert.equal(s.players.find((p: any) => p.is_me).progress, 15 - 3, 'timeout penalty');
  assert.equal(s.players.find((p: any) => p.is_me).connected, true);
});

test('the race finishes exactly once even when every racer ticks at the finish', async () => {
  // Racer 1 answers fast every question until they reach the line.
  for (let guard = 0; guard < 12; guard++) {
    clock += E.RULES.revealMs;
    const s = await call(U[0], 'roomState', { roomId: room });
    if (s.status !== 'racing') break;
    const ok = await correctFor(room);
    clock += 500;
    await call(U[0], 'submitAnswer', { roomId: room, question: s.question.index, option: ok });
    clock += E.RULES.windowMs;
    await Promise.all(U.slice(0, 6).map((u) => call(u, 'roomState', { roomId: room })));
  }
  const done = await call(U[2], 'roomState', { roomId: room });
  assert.equal(done.status, 'finished');
  assert.equal(done.results[0].id, U[0]);
  assert.equal(done.results.length, 6);
  const rows = await db.collection('leaderboards/all/rows').get();
  assert.equal(rows.size, 6);
  for (const d of rows.docs) assert.equal(d.get('races'), 1, 'recorded once');
  const board = await call(U[4], 'leaderboard', { period: 'week' });
  assert.equal(board.rows[0].id, U[0]);
  assert.equal(board.rows[0].wins, 1);
  assert.equal(board.rows.find((r: any) => r.is_me).id, U[4]);
  assert.equal((await call(U[0], 'leaderboard', { period: 'year' })).error, 'invalid_period');
  const history = await call(U[0], 'raceHistory');
  assert.deepEqual(history.races.map((r: any) => [r.placing, r.field]), [[1, 6]]);
  const n = await call(U[0], 'notifications');
  assert.ok(n.items.some((i: any) => i.kind === 'race_result' && i.payload.placing === 1));
  assert.equal((await call(U[0], 'myLiveRoom')).error, 'none');
});

test('friends, invites, blocking and reports', async () => {
  const [a, b, c] = [U[6], U[7], U[8]];
  const codeB = (await call(b, 'friends')).my_code;
  assert.equal((await call(a, 'sendFriendRequest', { code: codeB })).status, 'pending');
  assert.equal((await call(b, 'friends')).incoming[0].id, a);
  assert.equal((await call(b, 'notifications')).items[0].kind, 'friend_request');
  assert.equal((await call(b, 'respondFriendRequest', { requester: a, accept: true })).ok, true);
  assert.equal((await call(a, 'friends')).friends[0].id, b);
  const lobbyA = await call(a, 'createRoom');
  assert.equal((await call(a, 'inviteFriend', { roomId: lobbyA.room_id, friend: c })).error, 'not_friends');
  assert.equal((await call(a, 'inviteFriend', { roomId: lobbyA.room_id, friend: b })).ok, true);
  assert.equal((await call(b, 'friends')).invites[0].code, lobbyA.code);

  assert.equal((await call(a, 'blockPlayer', { player: b })).ok, true);
  assert.equal((await call(a, 'friends')).friends.length, 0);
  assert.equal((await call(b, 'friends')).invites.length, 0);
  assert.equal((await call(b, 'sendFriendRequest', { code: (await call(a, 'friends')).my_code })).error, 'not_found');
  assert.equal((await call(b, 'joinRoom', { code: lobbyA.code })).error, 'blocked');
  assert.equal((await call(a, 'blockedPlayers')).players[0].id, b);

  assert.equal((await call(c, 'reportPlayer', { target: a, reason: 'spam' })).error, 'invalid_reason');
  assert.equal((await call(c, 'reportPlayer', { target: a, reason: 'offensive_name' })).duplicate, false);
  assert.equal((await call(c, 'reportPlayer', { target: a, reason: 'cheating' })).duplicate, true);
  assert.equal((await call(U[0], 'reportQuestion', { roomId: room, question: 0, reason: 'unclear' })).ok, true);
  assert.equal((await call(c, 'reportQuestion', { roomId: room, question: 0, reason: 'unclear' })).error, 'not_member');
  await call(a, 'unblockPlayer', { player: b });
  assert.equal((await call(b, 'joinRoom', { code: lobbyA.code })).ok, true);
  await call(b, 'leaveRoom', { roomId: lobbyA.room_id });
  await call(a, 'leaveRoom', { roomId: lobbyA.room_id });
});

test('quick race joins an open public lobby, never a private one', async () => {
  const priv = await call(U[6], 'createRoom');
  const first = await call(U[7], 'quickJoin');
  assert.equal(first.is_public, true);
  assert.notEqual(first.room_id, priv.room_id);
  const second = await call(U[8], 'quickJoin');
  assert.equal(second.room_id, first.room_id);
  for (const [u, r] of [[U[6], priv], [U[7], first], [U[8], first]] as const) {
    await call(u, 'leaveRoom', { roomId: r.room_id });
  }
});

test('lobby creation is rate limited per hour', async () => {
  let last: any;
  let made = 0;
  for (let i = 0; i < 22; i++) {
    last = await call(U[8], 'createRoom');
    if (!last.ok) break;
    made++;
    await call(U[8], 'leaveRoom', { roomId: last.room_id });
  }
  assert.equal(last.error, 'rate_limited');
  assert.ok(made <= 20);
  clock += 3600_000;
});

const VIP = { uid: U[1], productId: 'buzzmasters_vip_monthly', price: '3.99 GBP', source: 'revenuecat_webhook' };

test('verified store events grant VIP once, with expiry, and revoke', async () => {
  const exp = clock + 30 * 86_400_000;
  const r1 = await api.storeEvent({ ...VIP, eventId: 'e1', transactionId: 't1', revoked: false, expiresAt: exp, willRenew: true });
  assert.equal(r1.accepted, true);
  assert.equal((await api.storeEvent({ ...VIP, eventId: 'e1', transactionId: 't1', revoked: false, expiresAt: exp, willRenew: true })).duplicate, true);
  let vip = (await db.doc(`entitlements/${U[1]}`).get()).get('vip');
  assert.deepEqual([vip.active, vip.expiresAt, vip.willRenew], [true, exp, true]);
  await api.storeRenewal('e2', U[1], VIP.productId, false);
  vip = (await db.doc(`entitlements/${U[1]}`).get()).get('vip');
  assert.deepEqual([vip.active, vip.willRenew], [true, false], 'cancelled: VIP until expiry');
  await api.storeEvent({ ...VIP, eventId: 'e3', transactionId: 't1', revoked: true, expiresAt: exp, willRenew: false });
  vip = (await db.doc(`entitlements/${U[1]}`).get()).get('vip');
  assert.equal(vip.active, false);
  assert.equal((await api.storeEvent({ ...VIP, productId: 'free_vip', eventId: 'e4', transactionId: 't9', revoked: false, expiresAt: null, willRenew: false })).accepted, false);
});

test('bundle purchases grant their items once; equipping needs ownership', async () => {
  const bundle = { ...VIP, productId: 'buzzmasters_legendary_bundle', revoked: false, expiresAt: null, willRenew: false };
  const r = await api.storeEvent({ ...bundle, eventId: 'b1', transactionId: 'tb1' });
  assert.deepEqual(r.granted_item_ids, ['frame_aurora', 'trail_neon', 'celebration_thunder', 'nameplate_chrome', 'neon_phantom']);
  const again = await api.storeEvent({ ...bundle, eventId: 'b2', transactionId: 'tb1' });
  assert.equal(again.duplicate, true);
  const items = await db.collection(`inventory/${U[1]}/items`).get();
  assert.equal(items.size, 5);
  assert.equal((await call(U[1], 'equip', { category: 'racingTrails', itemId: 'trail_neon' })).ok, true);
  assert.equal((await call(U[2], 'equip', { category: 'racingTrails', itemId: 'trail_neon' })).error, 'not_owned');
});

test('verified ad rewards pay once and respect the daily cap; daily reward once', async () => {
  const day = 20261030;
  const first = await api.ssvReward(U[2], 'ad-1', day, 50, 2);
  assert.deepEqual([first.outcome, first.coins], ['granted', 50]);
  assert.equal((await api.ssvReward(U[2], 'ad-1', day, 50, 2)).outcome, 'duplicate');
  assert.equal((await api.ssvReward(U[2], 'ad-2', day, 50, 2)).outcome, 'granted');
  assert.equal((await api.ssvReward(U[2], 'ad-3', day, 50, 2)).outcome, 'daily_cap_reached');
  // Simultaneous delivery of the same callback pays once.
  const both = await Promise.all([api.ssvReward(U[3], 'ad-9', day, 50, 5), api.ssvReward(U[3], 'ad-9', day, 50, 5)]);
  assert.deepEqual(both.map((b) => b.outcome).sort(), ['duplicate', 'granted']);
  const today = Number(new Date(clock).toISOString().slice(0, 10).replace(/-/g, ''));
  assert.equal((await call(U[2], 'claimDailyReward', { utcDay: today })).outcome, 'granted');
  assert.equal((await call(U[2], 'claimDailyReward', { utcDay: today })).outcome, 'duplicate');
  assert.equal((await call(U[2], 'claimDailyReward', { utcDay: 20200101 })).outcome, 'rejected');
  assert.equal((await db.doc(`wallets/${U[2]}`).get()).get('balance'), 150);
});

test('tournaments: free entry only, within dates, once', async () => {
  await db.doc('tournaments/t1').set({
    name: 'Autumn Cup', status: 'live', freeEntryOnly: true,
    startsAt: clock - 1000, endsAt: clock + 86_400_000, participantCount: 0,
  });
  await db.doc('tournaments/paid').set({ status: 'live', freeEntryOnly: false, startsAt: 0, endsAt: clock * 2 });
  assert.equal((await call(U[4], 'joinTournament', { tournamentId: 't1' })).joined, true);
  assert.equal((await call(U[4], 'joinTournament', { tournamentId: 't1' })).message, 'Already entered.');
  assert.equal((await call(U[4], 'joinTournament', { tournamentId: 'paid' })).joined, false);
  assert.equal((await call(U[4], 'standings', { tournamentId: 't1' })).scores[0].player_id, U[4]);
});

test('account deletion erases the player and anonymises past races', async () => {
  const uid = U[1];
  const out = await api.purgeAccount(uid);
  assert.equal(out.ok, true);
  for (const path of [`players/${uid}`, `entitlements/${uid}`, `wallets/${uid}`, `questionHistory/${uid}`]) {
    assert.equal((await db.doc(path).get()).exists, false, path);
  }
  assert.equal((await db.collection(`inventory/${uid}/items`).get()).size, 0);
  assert.equal((await db.collection('raceResults').where('uid', '==', uid).get()).size, 0);
  assert.equal((await db.collectionGroup('rows').where('uid', '==', uid).get()).size, 0);
  const r = (await db.doc(`rooms/${room}`).get()).data() as E.Room;
  assert.equal(r.results!.find((x) => x.uid === uid)!.name, 'Deleted racer');
  assert.equal((await call(uid, 'friends')).error, 'no_profile');
});
