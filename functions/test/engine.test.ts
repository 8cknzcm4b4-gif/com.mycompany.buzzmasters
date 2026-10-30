// The race engine's rules, without Firebase: the same scenarios that were
// proven on PostgreSQL for the earlier backend.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import * as E from '../src/engine';
import { BANK } from '../src/questions';

const T0 = Date.parse('2026-10-30T12:00:00Z');

function lobby(n: number, now = T0) {
  const r = E.newRoom('123456', E.newRacer('p1', 'Racer 1', 0, now), now, false);
  const s: E.Secret = { questions: [], answers: {} };
  for (let i = 2; i <= n; i++) {
    assert.equal(E.join(r, E.newRacer(`p${i}`, `Racer ${i}`, i % 6, now), now), null);
  }
  return { r, s };
}

function racing(n: number) {
  const { r, s } = lobby(n);
  assert.equal(E.start(r, s, 'p1', BANK.slice(0, 30), T0), null);
  E.tick(r, s, T0 + E.RULES.countdownMs);
  assert.equal(r.status, 'racing');
  return { r, s, t: T0 + E.RULES.countdownMs };
}

const correct = (r: E.Room, s: E.Secret) => s.questions[r.currentQ].correctIndex;

test('six seats, then full; the lowest free seat is reused', () => {
  const { r } = lobby(6);
  assert.deepEqual(Object.values(r.racers).map((p) => p.seat).sort(), [1, 2, 3, 4, 5, 6]);
  assert.deepEqual(E.join(r, E.newRacer('p7', 'x', 1, T0), T0), E.fail('full'));
  E.leave(r, 'p3', T0);
  assert.equal(E.join(r, E.newRacer('p7', 'x', 1, T0), T0), null);
  assert.equal(r.racers.p7.seat, 3);
});

test('only the host starts, never alone, and the host passes on when they leave', () => {
  const solo = lobby(1);
  assert.deepEqual(E.start(solo.r, solo.s, 'p1', BANK, T0), E.fail('not_enough_players'));
  const { r, s } = lobby(3);
  assert.deepEqual(E.start(r, s, 'p2', BANK, T0), E.fail('not_host'));
  E.leave(r, 'p1', T0);
  assert.equal(r.hostId, 'p2');
  E.leave(r, 'p2', T0);
  E.leave(r, 'p3', T0);
  assert.equal(r.status, 'abandoned');
});

test('lobbies expire after 30 minutes', () => {
  const { r, s } = lobby(2);
  E.tick(r, s, T0 + 29 * 60_000);
  assert.equal(r.status, 'lobby');
  E.tick(r, s, T0 + 30 * 60_000);
  assert.equal(r.status, 'abandoned');
});

test('the question is published only once it opens, and never with its answer', () => {
  const { r, s } = lobby(2);
  E.start(r, s, 'p1', BANK.slice(0, 30), T0);
  E.tick(r, s, T0 + 2000);
  assert.equal(r.status, 'countdown');
  assert.equal(r.question, null);
  E.tick(r, s, T0 + 3000);
  assert.equal((r.question as E.PublicQuestion | null)?.index, 0);
  assert.equal('correctIndex' in (r.question as unknown as object), false);
  const view = E.stateFor(r, 'room', 'p1', null, T0 + 3000);
  assert.deepEqual(Object.keys(view.question!).sort(),
    ['category', 'difficulty', 'index', 'options', 'prompt', 'remaining_ms']);
  assert.equal(view.last_correct_index, null, 'no answer revealed before the question closes');
  assert.equal(view.question?.remaining_ms, E.RULES.windowMs);
});

test('answers are judged on the server clock: fast, normal, wrong, late, duplicate', () => {
  const { r, s, t } = racing(4);
  const ok = correct(r, s);
  const wrong = (ok + 1) % 4;
  const fast = E.submit(r, s, 'p1', 0, ok, t + 1000);
  assert.deepEqual(fast.ok && [fast.correct, fast.delta], [true, 15]);
  const normal = E.submit(r, s, 'p2', 0, ok, t + 5000);
  assert.deepEqual(normal.ok && [normal.correct, normal.delta], [true, 10]);
  const bad = E.submit(r, s, 'p3', 0, wrong, t + 2000);
  assert.deepEqual(bad.ok && [bad.correct, bad.delta], [false, 0], 'cannot drop below 0');
  assert.deepEqual(E.submit(r, s, 'p1', 0, ok, t + 1500), E.fail('duplicate'));
  assert.deepEqual(E.submit(r, s, 'p4', 1, ok, t + 1500), E.fail('wrong_question'));
  assert.deepEqual(E.submit(r, s, 'p4', 0, 9, t + 1500), E.fail('invalid_option'));
  assert.deepEqual(E.submit(r, s, 'p4', 0, ok, t + 8000), E.fail('too_late'));
  assert.deepEqual(E.submit(r, s, 'nobody', 0, ok, t + 100), E.fail('not_member'));
});

test('the window closes on the server clock: timeouts, reveal, next question', () => {
  const { r, s, t } = racing(3);
  E.submit(r, s, 'p1', 0, correct(r, s), t + 1000);
  E.submit(r, s, 'p2', 0, correct(r, s), t + 1000);
  E.tick(r, s, t + 7999);
  assert.equal(r.currentQ, 0, 'still open for p3');
  E.tick(r, s, t + 8000);
  assert.equal(r.currentQ, 1);
  assert.equal(r.questionsResolved, 1);
  assert.equal(r.lastCorrectIndex, s.questions[0].correctIndex);
  assert.equal(s.answers[E.answerKey('p3', 0)].option, null);
  assert.equal(r.question, null, 'hidden during the reveal pause');
  E.tick(r, s, t + 8000 + E.RULES.revealMs);
  assert.equal((r.question as E.PublicQuestion | null)?.index, 1);
});

test('when everyone answers, the question resolves at once', () => {
  const { r, s, t } = racing(2);
  E.submit(r, s, 'p1', 0, correct(r, s), t + 500);
  E.submit(r, s, 'p2', 0, correct(r, s), t + 700);
  E.tick(r, s, t + 700);
  assert.equal(r.currentQ, 1);
});

test('safe start, then the danger zone eliminates after one warning', () => {
  const { r, s, t } = racing(2);
  let now = t;
  // p1 races ahead; p2 never answers and stays at 0.
  for (let q = 0; q < 5; q++) {
    E.submit(r, s, 'p1', q, correct(r, s), now + 500);
    now += E.RULES.windowMs;
    E.tick(r, s, now);
    if (q < 3) assert.equal(r.racers.p2.eliminated, false, `safe through Q${q + 1}`);
    now += E.RULES.revealMs;
    E.tick(r, s, now);
  }
  assert.equal(r.racers.p2.eliminated, true);
  assert.equal(r.status, 'racing', 'p1 races on alone');
  assert.deepEqual(E.submit(r, s, 'p2', r.currentQ, 0, now + 100), E.fail('not_active'));
});

test('reaching the distance finishes the race with placings, recorded once', () => {
  const { r, s, t } = racing(3);
  let now = t;
  for (let q = 0; q < 7 && r.status === 'racing'; q++) {
    E.submit(r, s, 'p2', q, correct(r, s), now + 500);
    E.submit(r, s, 'p1', q, correct(r, s), now + 4000);
    E.submit(r, s, 'p3', q, correct(r, s), now + 4500);
    E.tick(r, s, now + 4500);
    now += 4500 + E.RULES.revealMs;
    E.tick(r, s, now);
  }
  assert.equal(r.status, 'finished');
  assert.equal(r.racers.p2.finishedMs !== null, true);
  assert.deepEqual(r.results!.map((x) => [x.uid, x.placing]), [['p2', 1], ['p1', 2], ['p3', 3]]);
  const once = JSON.stringify(r.results);
  E.tick(r, s, now + 60_000);
  assert.equal(JSON.stringify(r.results), once, 'results never change after the finish');
});

test('leaving mid-race forfeits; everyone leaving abandons the race', () => {
  const { r, s, t } = racing(2);
  E.leave(r, 'p2', t + 100);
  assert.equal(r.racers.p2.eliminated, true);
  assert.deepEqual(E.submit(r, s, 'p2', 0, 0, t + 200), E.fail('not_active'));
  E.leave(r, 'p1', t + 300);
  E.tick(r, s, t + 300);
  assert.equal(r.status, 'abandoned');
});

test('disconnected racers time out and show as reconnecting after 20 s', () => {
  const { r, s, t } = racing(2);
  const view = E.stateFor(r, 'room', 'p1', null, t + 21_000);
  assert.equal(view.players.find((p) => p.id === 'p2')!.connected, false);
  E.tick(r, s, t + 8000);
  assert.equal(s.answers[E.answerKey('p2', 0)].option, null);
});

test('rotation: least-seen questions first, so a 60-question bank gives two fresh races', () => {
  assert.equal(BANK.length, 60);
  assert.equal(new Set(BANK.map((q) => q.id)).size, 60);
  for (const q of BANK) {
    assert.ok(q.correctIndex >= 0 && q.correctIndex < q.options.length, q.id);
  }
  const first = E.pickQuestions(BANK, {}, T0);
  const seen = { p1: Object.fromEntries(first.map((q) => [q.id, T0])) };
  const second = E.pickQuestions(BANK, seen, T0 + 1000);
  assert.equal(first.length, 30);
  assert.equal(second.filter((q) => first.some((f) => f.id === q.id)).length, 0);
  const later = E.pickQuestions(BANK, seen, T0 + 15 * 86_400_000);
  assert.equal(later.length, 30, 'history older than 14 days no longer counts');
});

test('period keys: UTC month and Monday-start week', () => {
  assert.deepEqual(E.periodKeys(Date.parse('2026-10-30T12:00:00Z')),
    { all: 'all', month: 'm-2026-10', week: 'w-2026-10-26' });
  assert.equal(E.periodKeys(Date.parse('2026-11-01T23:00:00Z')).week, 'w-2026-10-26');
  assert.equal(E.periodKeys(Date.parse('2026-11-02T00:00:00Z')).week, 'w-2026-11-02');
});

test('names and colours are cleaned', () => {
  assert.equal(E.cleanName('  Nova  '), 'Nova');
  assert.equal(E.cleanName(''), 'Racer');
  assert.equal(E.cleanName('ABCDEFGHIJKLMNOPQRSTUVWXYZ').length, 16);
  assert.equal(E.cleanColor(9), 5);
  assert.equal(E.cleanColor(-2), 0);
  assert.match(E.friendCode(), /^[A-Z2-9]{6}$/);
  assert.match(E.raceCode(), /^\d{6}$/);
});
