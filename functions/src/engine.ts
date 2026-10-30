// Buzz Masters race engine: pure functions over plain room data.
//
// A direct port of the rules that were proven on PostgreSQL
// (race_tick / bm_submit_answer in the earlier SQL backend). No Firebase
// imports, so every rule is unit-tested without the emulator; the callable
// functions in index.ts run these inside Firestore transactions.

export const RULES = {
  distance: 100,
  correctGain: 10,
  fastGain: 15,
  fastMs: 3000,
  wrongPenalty: 5,
  timeoutPenalty: 3,
  dangerMax: 10,
  dangerGrace: 1,
  dangerFree: 3,
  windowMs: 8000,
  revealMs: 1500,
  countdownMs: 3000,
  maxQuestions: 30,
  maxSeats: 6,
  minPlayers: 2,
  lobbyMinutes: 30,
  staleSeconds: 20,
} as const;

export type Status = 'lobby' | 'countdown' | 'racing' | 'finished' | 'abandoned';
export type Speed = 'stopped' | 'cruising' | 'fast';

export interface Racer {
  uid: string;
  seat: number;
  name: string;
  color: number;
  progress: number;
  speed: Speed;
  finishedMs: number | null;
  eliminated: boolean;
  dangerStreak: number;
  correct: number;
  answered: number;
  ready: boolean;
  leftAt: number | null;
  lastSeen: number;
  joinedAt: number;
}

export interface Question {
  id: string;
  category: string;
  difficulty: string;
  prompt: string;
  options: string[];
  correctIndex: number;
}

export interface PublicQuestion {
  index: number;
  category: string;
  difficulty: string;
  prompt: string;
  options: string[];
}

export interface Result {
  uid: string;
  placing: number;
  name: string;
  color: number;
  progress: number;
  finished: boolean;
  eliminated: boolean;
  correct: number;
  answered: number;
}

/** The room document every member can read. Never holds an answer key. */
export interface Room {
  code: string;
  hostId: string;
  status: Status;
  isPublic: boolean;
  createdAt: number;
  expiresAt: number;
  startsAt: number | null;
  currentQ: number;
  qOpenedAt: number | null;
  qResolved: boolean;
  questionsResolved: number;
  questionCount: number;
  lastCorrectIndex: number | null;
  finishedAt: number | null;
  racers: Record<string, Racer>;
  memberIds: string[];
  /** The open question, published only once it has opened. */
  question: PublicQuestion | null;
  results: Result[] | null;
}

export interface Answer {
  option: number | null;
  correct: boolean;
  responseMs: number | null;
  delta: number;
  at: number;
}

/** Server-only: the question set with answers, and every submitted answer. */
export interface Secret {
  questions: Question[];
  answers: Record<string, Answer>; // `${uid}#${qIndex}`
}

export const answerKey = (uid: string, q: number) => `${uid}#${q}`;

export function newRoom(code: string, host: Racer, now: number, isPublic: boolean): Room {
  return {
    code,
    hostId: host.uid,
    status: 'lobby',
    isPublic,
    createdAt: now,
    expiresAt: now + RULES.lobbyMinutes * 60_000,
    startsAt: null,
    currentQ: -1,
    qOpenedAt: null,
    qResolved: false,
    questionsResolved: 0,
    questionCount: 0,
    lastCorrectIndex: null,
    finishedAt: null,
    racers: { [host.uid]: { ...host, seat: 1 } },
    memberIds: [host.uid],
    question: null,
    results: null,
  };
}

export function newRacer(uid: string, name: string, color: number, now: number): Racer {
  return {
    uid,
    seat: 1,
    name,
    color,
    progress: 0,
    speed: 'stopped',
    finishedMs: null,
    eliminated: false,
    dangerStreak: 0,
    correct: 0,
    answered: 0,
    ready: false,
    leftAt: null,
    lastSeen: now,
    joinedAt: now,
  };
}

export const isLive = (r: Room) =>
  r.status === 'lobby' || r.status === 'countdown' || r.status === 'racing';

const active = (p: Racer) => p.finishedMs === null && !p.eliminated;

/** Finishers by time, then racers still in by distance, then the eliminated; seat breaks ties. */
export function ranked(r: Room): Racer[] {
  return Object.values(r.racers).sort((a, b) => {
    const af = a.finishedMs !== null, bf = b.finishedMs !== null;
    if (af !== bf) return af ? -1 : 1;
    if (af && a.finishedMs !== b.finishedMs) return a.finishedMs! - b.finishedMs!;
    if (a.eliminated !== b.eliminated) return a.eliminated ? 1 : -1;
    if (a.progress !== b.progress) return b.progress - a.progress;
    return a.seat - b.seat;
  });
}

function recordResults(r: Room) {
  r.results = ranked(r).map((p, i) => ({
    uid: p.uid,
    placing: i + 1,
    name: p.name,
    color: p.color,
    progress: p.progress,
    finished: p.finishedMs !== null,
    eliminated: p.eliminated,
    correct: p.correct,
    answered: p.answered,
  }));
}

const publicQuestion = (q: Question, index: number): PublicQuestion => ({
  index,
  category: q.category,
  difficulty: q.difficulty,
  prompt: q.prompt,
  options: [...q.options],
});

/**
 * Applies every transition that is due at [now]: lobby expiry, countdown →
 * racing, question timeouts, the danger zone, the reveal pause, the finish.
 * Returns true when anything changed. Results are recorded exactly once,
 * when the status becomes 'finished'.
 */
export function tick(r: Room, s: Secret, now: number): boolean {
  let changed = false;
  for (let guard = 0; guard < 4; guard++) {
    if (r.status === 'lobby') {
      if (now >= r.expiresAt) {
        r.status = 'abandoned';
        changed = true;
      }
      break;
    }
    if (r.status === 'countdown') {
      if (now < r.startsAt!) break;
      r.status = 'racing';
      r.currentQ = 0;
      r.qOpenedAt = r.startsAt;
      r.qResolved = false;
      changed = true;
      continue;
    }
    if (r.status !== 'racing') break;

    const racers = Object.values(r.racers);
    if (racers.every((p) => p.leftAt !== null)) {
      r.status = 'abandoned';
      r.finishedAt = now;
      r.question = null;
      changed = true;
      break;
    }
    if (now < r.qOpenedAt!) break;

    // Publish the question once it has opened (never earlier).
    if (r.question?.index !== r.currentQ) {
      r.question = publicQuestion(s.questions[r.currentQ], r.currentQ);
      changed = true;
    }

    const unanswered = racers.filter(
      (p) => active(p) && !s.answers[answerKey(p.uid, r.currentQ)]);
    if (now < r.qOpenedAt! + RULES.windowMs && unanswered.length > 0) break;

    // Resolve: timeouts for anyone still silent (including disconnected).
    for (const p of unanswered) {
      const delta = -Math.min(p.progress, RULES.timeoutPenalty);
      s.answers[answerKey(p.uid, r.currentQ)] = {
        option: null, correct: false, responseMs: null, delta, at: now,
      };
      p.progress = Math.max(0, p.progress - RULES.timeoutPenalty);
      p.speed = 'stopped';
    }

    // Danger zone, after the safe start.
    if (r.questionsResolved >= RULES.dangerFree) {
      for (const p of racers) {
        if (!active(p)) continue;
        if (p.progress <= RULES.dangerMax) {
          p.dangerStreak += 1;
          p.eliminated = p.dangerStreak > RULES.dangerGrace;
        } else {
          p.dangerStreak = 0;
        }
      }
    }

    const correctIndex = s.questions[r.currentQ].correctIndex;
    const done = racers.some((p) => p.finishedMs !== null) ||
      !racers.some(active) ||
      r.questionsResolved + 1 >= Math.min(RULES.maxQuestions, s.questions.length);
    r.questionsResolved += 1;
    r.lastCorrectIndex = correctIndex;
    r.question = null;
    changed = true;

    if (done) {
      r.status = 'finished';
      r.finishedAt = now;
      r.qResolved = true;
      recordResults(r);
      break;
    }
    // Next question opens after the reveal pause.
    r.currentQ += 1;
    r.qOpenedAt = now + RULES.revealMs;
    r.qResolved = false;
  }
  return changed;
}

export type Fail = { ok: false; error: string };
export const fail = (error: string): Fail => ({ ok: false, error });

export interface AnswerOutcome {
  ok: true;
  correct: boolean;
  delta: number;
  progress: number;
  responseMs: number;
}

/** Judges one answer on the server clock. Call tick() before and after. */
export function submit(
  r: Room, s: Secret, uid: string, qIndex: number, option: number, now: number,
): AnswerOutcome | Fail {
  const p = r.racers[uid];
  if (!p) return fail('not_member');
  if (r.status !== 'racing') return fail('not_racing');
  if (p.leftAt !== null || !active(p)) return fail('not_active');
  if (qIndex !== r.currentQ || r.qResolved || now < r.qOpenedAt!) {
    return fail('wrong_question');
  }
  const ms = now - r.qOpenedAt!;
  if (ms >= RULES.windowMs) return fail('too_late');
  const q = s.questions[r.currentQ];
  if (!Number.isInteger(option) || option < 0 || option >= q.options.length) {
    return fail('invalid_option');
  }
  const key = answerKey(uid, r.currentQ);
  if (s.answers[key]) return fail('duplicate');

  const correct = option === q.correctIndex;
  const gain = correct
    ? (ms <= RULES.fastMs ? RULES.fastGain : RULES.correctGain)
    : -RULES.wrongPenalty;
  const progress = Math.min(RULES.distance, Math.max(0, p.progress + gain));
  const delta = progress - p.progress;
  s.answers[key] = { option, correct, responseMs: ms, delta, at: now };
  p.progress = progress;
  p.speed = !correct ? 'stopped' : ms <= RULES.fastMs ? 'fast' : 'cruising';
  p.correct += correct ? 1 : 0;
  p.answered += 1;
  p.lastSeen = now;
  if (progress >= RULES.distance) p.finishedMs = now - r.startsAt!;
  return { ok: true, correct, delta, progress, responseMs: ms };
}

/** Takes the lowest free seat. */
export function join(r: Room, racer: Racer, now: number): Fail | null {
  if (r.status !== 'lobby') return fail('already_started');
  const taken = new Set(Object.values(r.racers).map((p) => p.seat));
  let seat = 0;
  for (let s = 1; s <= RULES.maxSeats; s++) {
    if (!taken.has(s)) { seat = s; break; }
  }
  if (seat === 0) return fail('full');
  r.racers[racer.uid] = { ...racer, seat, joinedAt: now, lastSeen: now };
  if (!r.memberIds.includes(racer.uid)) r.memberIds.push(racer.uid);
  return null;
}

/** Leaving a lobby frees the seat (the host passes on); leaving a race forfeits. */
export function leave(r: Room, uid: string, now: number): Fail | null {
  const p = r.racers[uid];
  if (!p) return fail('not_member');
  if (r.status === 'lobby') {
    delete r.racers[uid];
    r.memberIds = r.memberIds.filter((m) => m !== uid);
    if (r.hostId === uid) {
      const next = Object.values(r.racers).sort((a, b) => a.seat - b.seat)[0];
      if (!next) r.status = 'abandoned';
      else r.hostId = next.uid;
    }
  } else if (r.status === 'countdown' || r.status === 'racing') {
    if (p.leftAt === null) {
      p.leftAt = now;
      p.eliminated = true;
      p.speed = 'stopped';
    }
  }
  return null;
}

/** Starts the countdown with the given question set. */
export function start(r: Room, s: Secret, uid: string, questions: Question[], now: number): Fail | null {
  if (r.hostId !== uid) return fail('not_host');
  if (r.status !== 'lobby') return fail('already_started');
  if (Object.keys(r.racers).length < RULES.minPlayers) return fail('not_enough_players');
  if (questions.length === 0) return fail('no_questions');
  s.questions = questions.slice(0, RULES.maxQuestions);
  s.answers = {};
  r.status = 'countdown';
  r.startsAt = now + RULES.countdownMs;
  r.currentQ = -1;
  r.qResolved = false;
  r.questionsResolved = 0;
  r.questionCount = s.questions.length;
  return null;
}

/**
 * Picks a race's questions: least seen by this field in the last 14 days
 * first, random within the same count. [seen] maps uid → questionId → ms.
 */
export function pickQuestions(
  bank: Question[], seen: Record<string, Record<string, number>>, now: number,
  random: () => number = Math.random,
): Question[] {
  const since = now - 14 * 86_400_000;
  const scored = bank.map((q) => ({
    q,
    seen: Object.values(seen).filter((m) => (m[q.id] ?? 0) > since).length,
    r: random(),
  }));
  scored.sort((a, b) => a.seen - b.seen || a.r - b.r);
  const chosen = scored.slice(0, RULES.maxQuestions);
  // Shuffle the chosen set so rotation does not fix the order.
  chosen.sort((a, b) => a.r - b.r);
  return chosen.map((c) => c.q);
}

/**
 * The view of a room for one member, in the JSON shape the app parses
 * (RoomState.fromJson). Times are relative to the server clock.
 */
export function stateFor(r: Room, roomId: string, uid: string, mine: Answer | null, now: number) {
  const players = Object.values(r.racers)
    .sort((a, b) => a.seat - b.seat)
    .map((p) => ({
      id: p.uid,
      seat: p.seat,
      name: p.name,
      color: p.color,
      progress: p.progress,
      speed: p.speed,
      finished: p.finishedMs !== null,
      finished_ms: p.finishedMs,
      eliminated: p.eliminated,
      danger: active(p) && r.questionsResolved >= RULES.dangerFree &&
        p.progress <= RULES.dangerMax,
      connected: p.leftAt === null && p.lastSeen > now - RULES.staleSeconds * 1000,
      left: p.leftAt !== null,
      ready: p.ready || p.uid === r.hostId,
      is_me: p.uid === uid,
      is_host: p.uid === r.hostId,
    }));
  const open = r.status === 'racing' && r.qOpenedAt !== null && now >= r.qOpenedAt &&
    r.question?.index === r.currentQ;
  return {
    ok: true,
    server_now: now,
    room_id: roomId,
    code: r.code,
    status: r.status,
    is_public: r.isPublic,
    host_id: r.hostId,
    is_host: r.hostId === uid,
    all_ready: Object.values(r.racers)
      .every((p) => p.uid === r.hostId || p.leftAt !== null || p.ready),
    countdown_ms: r.status === 'countdown' ? Math.max(0, r.startsAt! - now) : null,
    question_number: r.currentQ + 1,
    questions_resolved: r.questionsResolved,
    next_question_in_ms: r.status === 'racing' && r.qOpenedAt !== null && now < r.qOpenedAt
      ? r.qOpenedAt - now : null,
    last_correct_index: r.lastCorrectIndex,
    rules: {
      distance: RULES.distance,
      window_ms: RULES.windowMs,
      max_questions: RULES.maxQuestions,
      max_seats: RULES.maxSeats,
      min_players: RULES.minPlayers,
    },
    players,
    question: open ? {
      ...r.question!,
      remaining_ms: Math.max(0, RULES.windowMs - (now - r.qOpenedAt!)),
    } : null,
    my_answer: r.status === 'racing' && mine
      ? { option: mine.option, correct: mine.correct, delta: mine.delta }
      : null,
    results: r.status === 'finished' && r.results
      ? r.results.map((x) => ({
        id: x.uid, placing: x.placing, name: x.name, color: x.color,
        progress: x.progress, finished: x.finished, eliminated: x.eliminated,
        correct: x.correct, answered: x.answered, is_me: x.uid === uid,
      }))
      : null,
  };
}

/** UTC period keys a result counts towards: all time, its month, its ISO week. */
export function periodKeys(ms: number): { all: string; month: string; week: string } {
  const d = new Date(ms);
  const month = `m-${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}`;
  const day = (d.getUTCDay() + 6) % 7; // Monday = 0
  const monday = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate() - day));
  const week = `w-${monday.toISOString().slice(0, 10)}`;
  return { all: 'all', month, week };
}

export function cleanName(raw: unknown): string {
  const s = String(raw ?? '').trim().slice(0, 16);
  return s === '' ? 'Racer' : s;
}

export const cleanColor = (raw: unknown) =>
  Math.min(5, Math.max(0, Number.isInteger(raw) ? (raw as number) : 1));

export const FRIEND_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

export function friendCode(random: () => number = Math.random): string {
  let s = '';
  for (let i = 0; i < 6; i++) s += FRIEND_ALPHABET[Math.floor(random() * FRIEND_ALPHABET.length)];
  return s;
}

export const raceCode = (random: () => number = Math.random) =>
  String(Math.floor(random() * 1_000_000)).padStart(6, '0');

export const normaliseCode = (raw: unknown) => String(raw ?? '').replace(/[\s-]/g, '');
