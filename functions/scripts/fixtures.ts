// Writes test/fixtures/room_views.json: room documents and the exact view
// the server returns for them, so the app's local view builder
// (lib/bm/online/room_view.dart) is checked against the real engine.
import { writeFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import * as E from '../src/engine';
import { BANK } from '../src/questions';

const T0 = Date.parse('2026-10-30T12:00:00Z');
const cases: unknown[] = [];
const snap = (name: string, r: E.Room, uid: string, mine: E.Answer | null, now: number) => {
  const doc = JSON.parse(JSON.stringify(r));
  const mineDoc = mine ? { q: r.currentQ, option: mine.option, correct: mine.correct, delta: mine.delta } : null;
  cases.push({ name, doc, uid, mine: mineDoc, now, view: E.stateFor(r, 'room-1', uid, mine, now) });
};

const r = E.newRoom('482913', E.newRacer('host', 'Nova', 0, T0), T0, true);
const s: E.Secret = { questions: [], answers: {} };
for (let i = 2; i <= 6; i++) E.join(r, E.newRacer(`p${i}`, `Racer ${i}`, i - 1, T0 + i), T0 + i);
r.racers.p2.ready = true;
snap('lobby with readiness', r, 'p2', null, T0 + 1000);
E.start(r, s, 'host', BANK.slice(0, 30), T0 + 2000);
snap('countdown', r, 'p3', null, T0 + 3000);
E.tick(r, s, T0 + 5000);
snap('question open', r, 'host', null, T0 + 6000);
const out = E.submit(r, s, 'host', 0, s.questions[0].correctIndex, T0 + 6500) as E.AnswerOutcome;
E.submit(r, s, 'p2', 0, (s.questions[0].correctIndex + 1) % 4, T0 + 7000);
snap('answered', r, 'host', s.answers[E.answerKey('host', 0)], T0 + 7000);
E.tick(r, s, T0 + 5000 + 8000);
snap('reveal pause', r, 'p4', null, T0 + 13500);
snap('stale racer', r, 'p4', null, T0 + 40_000);
let now = T0 + 14_500;
for (let q = 1; q < 12 && r.status === 'racing'; q++) {
  E.tick(r, s, now);
  E.submit(r, s, 'p5', r.currentQ, s.questions[r.currentQ].correctIndex, now + 100);
  now += 8000;
  E.tick(r, s, now);
  now += 1500;
}
snap('finished', r, 'p5', null, now);
void out;
mkdirSync(join(__dirname, '../../../test/fixtures'), { recursive: true });
writeFileSync(join(__dirname, '../../../test/fixtures/room_views.json'), JSON.stringify(cases, null, 1));
console.log(`wrote ${cases.length} cases`);
