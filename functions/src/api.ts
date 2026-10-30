// Buzz Masters server API on Firestore.
//
// Every operation the app performs goes through `handle(op, uid, args)`,
// which the `api` callable exposes (index.ts). The race engine is in
// engine.ts; this file loads and saves its data inside Firestore
// transactions, so concurrent answers, joins and ticks never conflict, and
// rewards are applied exactly once (document ids are the idempotency keys).
//
// Clients cannot write any of these collections (firestore.rules); they read
// only their own documents and the rooms they are in.
import {
  FieldValue, Firestore, Transaction, DocumentReference,
} from 'firebase-admin/firestore';
import * as E from './engine';
import { BANK } from './questions';

export type Json = Record<string, unknown>;
export type Clock = () => number;

/** Store products the server recognises (prices always come from the store). */
export const PRODUCTS: Record<string, { entitlement: string | null; grants: string[] }> = {
  buzzmasters_vip_monthly: { entitlement: 'buzzmasters_vip', grants: [] },
  buzzmasters_vip_annual: { entitlement: 'buzzmasters_vip', grants: [] },
  buzzmasters_starter_bundle: {
    entitlement: null, grants: ['frame_aurora', 'trail_neon', 'celebration_thunder'],
  },
  buzzmasters_neon_bundle: {
    entitlement: null, grants: ['trail_neon', 'nameplate_chrome', 'frame_aurora'],
  },
  buzzmasters_legendary_bundle: {
    entitlement: null,
    grants: ['frame_aurora', 'trail_neon', 'celebration_thunder', 'nameplate_chrome', 'neon_phantom'],
  },
};

export const itemCategory = (item: string) =>
  item.startsWith('frame') ? 'profileFrames'
    : item.startsWith('trail') ? 'racingTrails'
      : item.startsWith('celebration') ? 'celebrations'
        : item.startsWith('nameplate') ? 'nameplates'
          : 'avatars';

const err = (error: string) => ({ ok: false as const, error });
const LIVE: E.Status[] = ['lobby', 'countdown', 'racing'];

export class Api {
  constructor(readonly db: Firestore, readonly now: Clock = Date.now) {}

  // ---------------------------------------------------------------- refs
  private player = (uid: string) => this.db.doc(`players/${uid}`);
  private room = (id: string) => this.db.doc(`rooms/${id}`);
  private secret = (id: string) => this.db.doc(`rooms/${id}/secret/state`);
  private mine = (id: string, uid: string) => this.db.doc(`rooms/${id}/mine/${uid}`);
  private pair = (a: string, b: string) => this.db.doc(`friendLinks/${[a, b].sort().join('_')}`);
  private block = (a: string, b: string) => this.db.doc(`blocks/${a}_${b}`);

  // ---------------------------------------------------------------- helpers
  private async profile(uid: string) {
    const snap = await this.player(uid).get();
    return snap.exists ? (snap.data() as { name: string; color: number; friendCode: string }) : null;
  }

  async isBlocked(a: string, b: string): Promise<boolean> {
    const [x, y] = await Promise.all([this.block(a, b).get(), this.block(b, a).get()]);
    return x.exists || y.exists;
  }

  /** Fixed-window counter; true while within [max] calls per window. */
  async rateOk(uid: string, action: string, max: number, windowSeconds: number): Promise<boolean> {
    const bucket = Math.floor(this.now() / 1000 / windowSeconds);
    const ref = this.db.doc(`rateLimits/${uid}_${action}_${bucket}`);
    return this.db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const hits = (snap.exists ? (snap.get('hits') as number) : 0) + 1;
      tx.set(ref, {
        uid, action, hits,
        expiresAt: new Date((bucket + 2) * windowSeconds * 1000),
      });
      return hits <= max;
    });
  }

  private notify(tx: Transaction, uid: string, kind: string, payload: Json) {
    tx.create(this.db.collection(`players/${uid}/notifications`).doc(), {
      kind, payload, createdAt: this.now(), read: false,
    });
  }

  /** Loads a room and its secret in [tx], runs [fn], saves what changed. */
  private async withRoom<T>(
    roomId: string,
    fn: (r: E.Room, s: E.Secret, tx: Transaction, now: number) => Promise<T> | T,
  ): Promise<T | { ok: false; error: string }> {
    return this.db.runTransaction(async (tx) => {
      const [rs, ss] = await Promise.all([tx.get(this.room(roomId)), tx.get(this.secret(roomId))]);
      if (!rs.exists) return err('not_found');
      const r = rs.data() as E.Room;
      const s = (ss.exists ? ss.data() : { questions: [], answers: {} }) as E.Secret;
      const before = JSON.stringify(r);
      const beforeSecret = JSON.stringify(s);
      const wasFinished = r.status === 'finished';
      const now = this.now();
      const out = await fn(r, s, tx, now);
      if (JSON.stringify(r) !== before) tx.set(this.room(roomId), r);
      if (JSON.stringify(s) !== beforeSecret) tx.set(this.secret(roomId), s);
      if (!wasFinished && r.status === 'finished') this.recordFinish(tx, roomId, r, now);
      return out;
    });
  }

  /** Results, rankings and notifications, written once when a race finishes. */
  private recordFinish(tx: Transaction, roomId: string, r: E.Room, now: number) {
    const keys = E.periodKeys(now);
    for (const x of r.results ?? []) {
      tx.set(this.db.doc(`raceResults/${roomId}_${x.uid}`), {
        roomId, uid: x.uid, placing: x.placing, field: r.results!.length,
        progress: x.progress, finished: x.finished, eliminated: x.eliminated,
        correct: x.correct, answered: x.answered, recordedAt: now,
      });
      for (const period of [keys.all, keys.month, keys.week]) {
        tx.set(this.db.doc(`leaderboards/${period}/rows/${x.uid}`), {
          uid: x.uid, name: x.name, color: x.color,
          wins: FieldValue.increment(x.placing === 1 ? 1 : 0),
          podiums: FieldValue.increment(x.placing <= 3 ? 1 : 0),
          races: FieldValue.increment(1),
          updatedAt: now,
        }, { merge: true });
      }
      this.notify(tx, x.uid, 'race_result', { room_id: roomId, placing: x.placing });
    }
  }

  private async state(roomId: string, uid: string) {
    const [rs, ms] = await Promise.all([this.room(roomId).get(), this.mine(roomId, uid).get()]);
    const r = rs.data() as E.Room;
    const mine = ms.exists && ms.get('q') === r.currentQ ? (ms.data() as E.Answer) : null;
    return E.stateFor(r, roomId, uid, mine, this.now());
  }

  // ---------------------------------------------------------------- dispatch
  async handle(op: string, uid: string, a: Json): Promise<unknown> {
    if (op === 'upsertProfile') return this.upsertProfile(uid, a.name, a.color);
    const me = await this.profile(uid);
    if (!me) return err('no_profile');
    switch (op) {
      case 'createRoom': return this.createRoom(uid, me, a.isPublic === true);
      case 'joinRoom': return this.joinRoom(uid, me, String(a.code ?? ''));
      case 'quickJoin': return this.quickJoin(uid, me);
      case 'roomState': return this.roomState(uid, String(a.roomId ?? ''));
      case 'myLiveRoom': return this.myLiveRoom(uid);
      case 'leaveRoom': return this.leaveRoom(uid, String(a.roomId ?? ''));
      case 'startRace': return this.startRace(uid, String(a.roomId ?? ''));
      case 'submitAnswer':
        return this.submitAnswer(uid, String(a.roomId ?? ''), Number(a.question), Number(a.option));
      case 'setReady': return this.setReady(uid, String(a.roomId ?? ''), a.ready === true);
      case 'friends': return this.friends(uid, me);
      case 'sendFriendRequest': return this.sendFriendRequest(uid, me, String(a.code ?? ''));
      case 'respondFriendRequest':
        return this.respondFriendRequest(uid, me, String(a.requester ?? ''), a.accept === true);
      case 'removeFriend': return this.removeFriend(uid, String(a.friend ?? ''));
      case 'inviteFriend':
        return this.inviteFriend(uid, me, String(a.roomId ?? ''), String(a.friend ?? ''));
      case 'blockPlayer': return this.blockPlayer(uid, String(a.player ?? ''));
      case 'unblockPlayer': return this.unblockPlayer(uid, String(a.player ?? ''));
      case 'blockedPlayers': return this.blockedPlayers(uid);
      case 'reportPlayer':
        return this.reportPlayer(uid, String(a.target ?? ''), String(a.reason ?? ''),
          a.details == null ? null : String(a.details), a.roomId == null ? null : String(a.roomId));
      case 'reportQuestion':
        return this.reportQuestion(uid, String(a.roomId ?? ''), Number(a.question),
          String(a.reason ?? ''), a.details == null ? null : String(a.details));
      case 'leaderboard': return this.leaderboard(uid, String(a.period ?? 'all'), Number(a.limit ?? 50));
      case 'raceHistory': return this.raceHistory(uid, Number(a.limit ?? 20));
      case 'notifications': return this.notifications(uid, Number(a.limit ?? 30));
      case 'markNotificationsRead': return this.markNotificationsRead(uid);
      case 'registerDevice': return this.registerDevice(uid, String(a.token ?? ''), String(a.platform ?? ''));
      case 'claimDailyReward': return this.claimDailyReward(uid, Number(a.utcDay));
      case 'equip': return this.equip(uid, String(a.category ?? ''), String(a.itemId ?? ''));
      case 'joinTournament': return this.joinTournament(uid, String(a.tournamentId ?? ''));
      case 'standings': return this.standings(String(a.tournamentId ?? ''));
      default: return err('unknown_op');
    }
  }

  // ---------------------------------------------------------------- profile
  async upsertProfile(uid: string, rawName: unknown, rawColor: unknown) {
    const name = E.cleanName(rawName);
    const color = E.cleanColor(rawColor);
    return this.db.runTransaction(async (tx) => {
      const ref = this.player(uid);
      const snap = await tx.get(ref);
      let code = snap.exists ? (snap.get('friendCode') as string) : '';
      if (!code) {
        for (let i = 0; i < 20 && !code; i++) {
          const c = E.friendCode();
          if (!(await tx.get(this.db.doc(`friendCodes/${c}`))).exists) code = c;
        }
        if (!code) return err('server_error');
        tx.create(this.db.doc(`friendCodes/${code}`), { uid });
      }
      tx.set(ref, {
        name, color, friendCode: code,
        createdAt: snap.exists ? snap.get('createdAt') : this.now(),
      });
      return { ok: true, id: uid, name, color, friend_code: code };
    });
  }

  // ---------------------------------------------------------------- rooms
  private async liveRoomByCode(code: string, tx?: Transaction) {
    const q = this.db.collection('rooms').where('code', '==', code).where('status', 'in', LIVE);
    const snap = tx ? await tx.get(q) : await q.get();
    return snap.docs[0] ?? null;
  }

  async createRoom(uid: string, me: { name: string; color: number }, isPublic: boolean) {
    if (!(await this.rateOk(uid, 'create_room', 20, 3600))) return err('rate_limited');
    const ref = this.db.collection('rooms').doc();
    await this.db.runTransaction(async (tx) => {
      let code = '';
      for (let i = 0; i < 30 && !code; i++) {
        const c = E.raceCode();
        if (!(await this.liveRoomByCode(c, tx))) code = c;
      }
      if (!code) throw new Error('no_code');
      const now = this.now();
      const room = E.newRoom(code, E.newRacer(uid, me.name, me.color, now), now, isPublic);
      tx.create(ref, room);
      tx.create(this.secret(ref.id), { questions: [], answers: {} });
    });
    return this.state(ref.id, uid);
  }

  async joinRoom(uid: string, me: { name: string; color: number }, rawCode: string) {
    const code = E.normaliseCode(rawCode);
    if (!/^\d{6}$/.test(code)) return err('invalid_code');
    if (!(await this.rateOk(uid, 'join_room', 60, 600))) return err('rate_limited');
    const live = await this.liveRoomByCode(code);
    if (!live) {
      const any = await this.db.collection('rooms').where('code', '==', code).limit(1).get();
      return err(any.empty ? 'not_found' : 'expired');
    }
    const members = Object.keys((live.data() as E.Room).racers);
    for (const m of members) {
      if (m !== uid && await this.isBlocked(uid, m)) {
        const own = (live.data() as E.Room).racers[uid];
        if (!own || own.leftAt !== null) return err('blocked');
      }
    }
    const out = await this.withRoom(live.id, (r, s, tx, now) => {
      E.tick(r, s, now);
      if (!E.isLive(r)) return err('expired');
      const own = r.racers[uid];
      if (own && own.leftAt === null) {
        own.lastSeen = now;
        return null;
      }
      if (r.status !== 'lobby') return err('already_started');
      if (own) delete r.racers[uid];
      const failed = E.join(r, E.newRacer(uid, me.name, me.color, now), now);
      if (failed) return failed;
      tx.delete(this.db.doc(`invites/${live.id}_${uid}`));
      return null;
    });
    if (out) return out;
    return this.state(live.id, uid);
  }

  async quickJoin(uid: string, me: { name: string; color: number }) {
    const live = await this.myLiveRoom(uid);
    if ((live as Json).ok) return live;
    const open = await this.db.collection('rooms')
      .where('status', '==', 'lobby').where('isPublic', '==', true)
      .where('expiresAt', '>', this.now()).limit(50).get();
    const candidates = open.docs
      .map((d) => ({ id: d.id, r: d.data() as E.Room }))
      .filter((c) => Object.keys(c.r.racers).length < E.RULES.maxSeats)
      .sort((a, b) => Object.keys(b.r.racers).length - Object.keys(a.r.racers).length ||
        a.r.createdAt - b.r.createdAt);
    for (const c of candidates) {
      let blocked = false;
      for (const m of Object.keys(c.r.racers)) {
        if (await this.isBlocked(uid, m)) { blocked = true; break; }
      }
      if (blocked) continue;
      const joined = await this.joinRoom(uid, me, c.r.code) as Json;
      if (joined.ok) return joined;
    }
    return this.createRoom(uid, me, true);
  }

  async roomState(uid: string, roomId: string) {
    if (!roomId) return err('not_member');
    const out = await this.withRoom(roomId, (r, s, _tx, now) => {
      if (!r.racers[uid]) return err('not_member');
      E.tick(r, s, now);
      const p = r.racers[uid];
      // Heartbeat: only refreshed every few seconds, so polling stays cheap.
      if (p && p.leftAt === null && now - p.lastSeen > 4000) p.lastSeen = now;
      return null;
    });
    if (out) return out;
    return this.state(roomId, uid);
  }

  async myLiveRoom(uid: string) {
    const snap = await this.db.collection('rooms')
      .where('memberIds', 'array-contains', uid).where('status', 'in', LIVE).get();
    const rooms = snap.docs
      .filter((d) => (d.data() as E.Room).racers[uid]?.leftAt === null)
      .sort((a, b) => (b.data() as E.Room).racers[uid].joinedAt -
        (a.data() as E.Room).racers[uid].joinedAt);
    for (const d of rooms) {
      const state = await this.roomState(uid, d.id) as Json;
      if (state.ok && LIVE.includes(state.status as E.Status)) return state;
    }
    return err('none');
  }

  async leaveRoom(uid: string, roomId: string) {
    const out = await this.withRoom(roomId, (r, s, _tx, now) => {
      const failed = E.leave(r, uid, now);
      if (failed) return failed;
      E.tick(r, s, now);
      return { ok: true };
    });
    return out;
  }

  async startRace(uid: string, roomId: string) {
    const roomSnap = await this.room(roomId).get();
    if (!roomSnap.exists) return err('not_found');
    const members = Object.keys((roomSnap.data() as E.Room).racers);
    const seen: Record<string, Record<string, number>> = {};
    await Promise.all(members.map(async (m) => {
      const h = await this.db.doc(`questionHistory/${m}`).get();
      seen[m] = (h.exists ? h.get('seen') : {}) ?? {};
    }));
    const bank = await this.questionBank();
    const out = await this.withRoom(roomId, (r, s, tx, now) => {
      E.tick(r, s, now);
      const picked = E.pickQuestions(bank, seen, now);
      const failed = E.start(r, s, uid, picked, now);
      if (failed) return failed;
      for (const m of Object.keys(r.racers)) {
        const update: Json = {};
        for (const q of picked) update[`seen.${q.id}`] = now;
        tx.set(this.db.doc(`questionHistory/${m}`), { seen: {} }, { merge: true });
        tx.update(this.db.doc(`questionHistory/${m}`), update as Record<string, number>);
        tx.delete(this.db.doc(`invites/${roomId}_${m}`));
      }
      return null;
    });
    if (out) return out;
    return this.state(roomId, uid);
  }

  private bankCache: { at: number; questions: E.Question[] } | null = null;

  /** Active questions, cached for a minute per server instance. */
  async questionBank(): Promise<E.Question[]> {
    if (this.bankCache && this.now() - this.bankCache.at < 60_000) return this.bankCache.questions;
    const snap = await this.db.collection('questions').where('active', '==', true).get();
    const questions = snap.empty
      ? BANK
      : snap.docs.map((d) => ({ id: d.id, ...(d.data() as Omit<E.Question, 'id'>) }));
    this.bankCache = { at: this.now(), questions };
    return questions;
  }

  async submitAnswer(uid: string, roomId: string, qIndex: number, option: number) {
    return this.withRoom(roomId, (r, s, tx, now) => {
      E.tick(r, s, now);
      const outcome = E.submit(r, s, uid, qIndex, option, now);
      if (!outcome.ok) return outcome;
      tx.set(this.mine(roomId, uid), {
        q: qIndex, option, correct: outcome.correct, delta: outcome.delta,
      });
      E.tick(r, s, now);
      return {
        ok: true, correct: outcome.correct, delta: outcome.delta,
        progress: outcome.progress, response_ms: outcome.responseMs,
      };
    });
  }

  async setReady(uid: string, roomId: string, ready: boolean) {
    const out = await this.withRoom(roomId, (r, s, _tx, now) => {
      E.tick(r, s, now);
      const p = r.racers[uid];
      if (r.status !== 'lobby') return err(p ? 'already_started' : 'not_member');
      if (!p || p.leftAt !== null) return err('not_member');
      p.ready = ready;
      p.lastSeen = now;
      return null;
    });
    if (out) return out;
    return this.state(roomId, uid);
  }

  // ---------------------------------------------------------------- friends
  private async friendList(uid: string) {
    const snap = await this.db.collection('friendLinks').where('members', 'array-contains', uid).get();
    return snap.docs.map((d) => d.data() as {
      requester: string; addressee: string; status: string; members: string[];
    });
  }

  private async entries(ids: string[]) {
    const out: Json[] = [];
    for (const id of ids) {
      const p = await this.profile(id);
      if (p) out.push({ id, name: p.name, color: p.color });
    }
    return out;
  }

  async friends(uid: string, me: { friendCode: string }) {
    const links = await this.friendList(uid);
    const other = (l: { members: string[] }) => l.members.find((m) => m !== uid) ?? uid;
    const friends = await this.entries(links.filter((l) => l.status === 'accepted').map(other));
    friends.sort((a, b) => String(a.name).localeCompare(String(b.name)));
    const incoming = await this.entries(
      links.filter((l) => l.status === 'pending' && l.addressee === uid).map((l) => l.requester));
    const outgoing = await this.entries(
      links.filter((l) => l.status === 'pending' && l.requester === uid).map((l) => l.addressee));
    const inv = await this.db.collection('invites').where('to', '==', uid).get();
    const invites: Json[] = [];
    for (const d of inv.docs.sort((a, b) => b.get('createdAt') - a.get('createdAt'))) {
      const rs = await this.room(d.get('roomId')).get();
      const r = rs.data() as E.Room | undefined;
      if (!r || r.status !== 'lobby' || r.expiresAt <= this.now()) continue;
      const from = await this.profile(d.get('from'));
      invites.push({ room_id: rs.id, code: r.code, from: from?.name ?? '', from_id: d.get('from') });
    }
    return { ok: true, my_code: me.friendCode, friends, incoming, outgoing, invites };
  }

  async sendFriendRequest(uid: string, me: { name: string }, rawCode: string) {
    if (!(await this.rateOk(uid, 'friend_request', 30, 3600))) return err('rate_limited');
    const code = rawCode.trim().toUpperCase();
    const target = /^[A-Z0-9]{6}$/.test(code) ? await this.db.doc(`friendCodes/${code}`).get() : null;
    if (!target?.exists) return err('not_found');
    const other = target.get('uid') as string;
    if (other === uid) return err('self');
    if (await this.isBlocked(uid, other)) return err('not_found'); // never reveal a block
    return this.db.runTransaction(async (tx) => {
      const ref = this.pair(uid, other);
      const snap = await tx.get(ref);
      if (snap.exists && snap.get('status') === 'accepted') return err('already_friends');
      if (snap.exists && snap.get('requester') === other) {
        tx.update(ref, { status: 'accepted' });
        this.notify(tx, other, 'friend_accepted', { from_id: uid, from: me.name });
        return { ok: true, status: 'accepted' };
      }
      if (!snap.exists) {
        tx.create(ref, {
          requester: uid, addressee: other, status: 'pending',
          members: [uid, other], createdAt: this.now(),
        });
        this.notify(tx, other, 'friend_request', { from_id: uid, from: me.name });
      }
      return { ok: true, status: 'pending' };
    });
  }

  async respondFriendRequest(uid: string, me: { name: string }, requester: string, accept: boolean) {
    if (!requester) return err('not_found');
    return this.db.runTransaction(async (tx) => {
      const ref = this.pair(uid, requester);
      const snap = await tx.get(ref);
      if (!snap.exists || snap.get('status') !== 'pending' || snap.get('addressee') !== uid) {
        return err('not_found');
      }
      if (accept) {
        tx.update(ref, { status: 'accepted' });
        this.notify(tx, requester, 'friend_accepted', { from_id: uid, from: me.name });
      } else {
        tx.delete(ref);
      }
      return { ok: true };
    });
  }

  async removeFriend(uid: string, friend: string) {
    if (friend) await this.pair(uid, friend).delete();
    return { ok: true };
  }

  async inviteFriend(uid: string, me: { name: string }, roomId: string, friend: string) {
    const rs = await this.room(roomId).get();
    const r = rs.data() as E.Room | undefined;
    if (!r || !r.racers[uid] || r.racers[uid].leftAt !== null) return err('not_member');
    if (r.status !== 'lobby') return err('already_started');
    const link = friend ? await this.pair(uid, friend).get() : null;
    if (!link?.exists || link.get('status') !== 'accepted') return err('not_friends');
    if (!(await this.rateOk(uid, 'invite', 60, 3600))) return err('rate_limited');
    await this.db.runTransaction(async (tx) => {
      tx.set(this.db.doc(`invites/${roomId}_${friend}`), {
        roomId, from: uid, to: friend, createdAt: this.now(),
      });
      this.notify(tx, friend, 'race_invite', {
        room_id: roomId, code: r.code, from_id: uid, from: me.name,
      });
    });
    return { ok: true };
  }

  async blockPlayer(uid: string, player: string) {
    if (!player || player === uid) return err('self');
    if (!(await this.player(player).get()).exists) return err('not_found');
    const batch = this.db.batch();
    batch.set(this.block(uid, player), { blocker: uid, blocked: player, createdAt: this.now() });
    batch.delete(this.pair(uid, player));
    const invites = await this.db.collection('invites').where('to', 'in', [uid, player]).get();
    for (const d of invites.docs) {
      const from = d.get('from');
      if ((d.get('to') === uid && from === player) || (d.get('to') === player && from === uid)) {
        batch.delete(d.ref);
      }
    }
    await batch.commit();
    return { ok: true };
  }

  async unblockPlayer(uid: string, player: string) {
    if (player) await this.block(uid, player).delete();
    return { ok: true };
  }

  async blockedPlayers(uid: string) {
    const snap = await this.db.collection('blocks').where('blocker', '==', uid).get();
    const ids = snap.docs.sort((a, b) => b.get('createdAt') - a.get('createdAt')).map((d) => d.get('blocked'));
    return { ok: true, players: await this.entries(ids) };
  }

  // ---------------------------------------------------------------- reports
  async reportPlayer(uid: string, target: string, reason: string, details: string | null, roomId: string | null) {
    if (!target || target === uid) return err('self');
    if (!(await this.player(target).get()).exists) return err('not_found');
    if (!['offensive_name', 'cheating', 'harassment', 'other'].includes(reason)) {
      return err('invalid_reason');
    }
    const open = await this.db.collection('playerReports').where('reporter', '==', uid)
      .where('target', '==', target).where('status', '==', 'open').limit(1).get();
    if (!open.empty) return { ok: true, duplicate: true };
    if (!(await this.rateOk(uid, 'report', 10, 86400))) return err('rate_limited');
    let room: string | null = null;
    if (roomId) {
      const r = (await this.room(roomId).get()).data() as E.Room | undefined;
      if (r?.racers[uid] && r.racers[target]) room = roomId;
    }
    await this.db.collection('playerReports').add({
      reporter: uid, target, roomId: room, reason,
      details: details?.trim().slice(0, 280) ?? null, status: 'open', createdAt: this.now(),
    });
    return { ok: true, duplicate: false };
  }

  /** By question number in a race the reporter is in; ids never reach clients. */
  async reportQuestion(uid: string, roomId: string, qIndex: number, reason: string, details: string | null) {
    const [rs, ss] = await Promise.all([this.room(roomId).get(), this.secret(roomId).get()]);
    const r = rs.data() as E.Room | undefined;
    if (!r || !r.racers[uid]) return err('not_member');
    if (!Number.isInteger(qIndex) || qIndex < 0 || qIndex > r.currentQ ||
        r.status === 'lobby' || r.status === 'countdown') {
      return err('wrong_question');
    }
    if (!['wrong_answer', 'unclear', 'offensive', 'other'].includes(reason)) {
      return err('invalid_reason');
    }
    const qid = (ss.data() as E.Secret).questions[qIndex]?.id;
    if (!qid) return err('wrong_question');
    const ref = this.db.doc(`questionReports/${qid}_${uid}`);
    if ((await ref.get()).exists) return { ok: true, duplicate: true };
    if (!(await this.rateOk(uid, 'report', 10, 86400))) return err('rate_limited');
    await ref.create({
      reporter: uid, questionId: qid, roomId, reason,
      details: details?.trim().slice(0, 280) ?? null, createdAt: this.now(),
    });
    const count = await this.db.collection('questionReports').where('questionId', '==', qid).count().get();
    if (count.data().count >= 3) {
      await this.db.doc(`questions/${qid}`).set({ needsReview: true }, { merge: true });
    }
    return { ok: true, duplicate: false };
  }

  // ---------------------------------------------------------------- rankings
  async leaderboard(uid: string, period: string, limit: number) {
    const keys = E.periodKeys(this.now());
    const key = period === 'all' ? keys.all : period === 'month' ? keys.month
      : period === 'week' ? keys.week : null;
    if (!key) return err('invalid_period');
    const n = Math.min(200, Math.max(1, Number.isFinite(limit) ? limit : 50));
    const snap = await this.db.collection(`leaderboards/${key}/rows`)
      .orderBy('wins', 'desc').orderBy('podiums', 'desc').orderBy('races', 'desc')
      .limit(n).get();
    let rank = 0;
    let prev = '';
    const rows = snap.docs.map((d, i) => {
      const x = d.data();
      const tie = `${x.wins}/${x.podiums}/${x.races}`;
      if (tie !== prev) { rank = i + 1; prev = tie; }
      return {
        rank, id: d.id, name: x.name, color: x.color,
        wins: x.wins, podiums: x.podiums, races: x.races, is_me: d.id === uid,
      };
    });
    return { ok: true, period, rows };
  }

  async raceHistory(uid: string, limit: number) {
    const snap = await this.db.collection('raceResults').where('uid', '==', uid)
      .orderBy('recordedAt', 'desc').limit(Math.min(100, Math.max(1, limit || 20))).get();
    return {
      ok: true,
      races: snap.docs.map((d) => {
        const x = d.data();
        return {
          room_id: x.roomId, placing: x.placing, field: x.field, progress: x.progress,
          finished: x.finished, eliminated: x.eliminated, correct: x.correct,
          answered: x.answered, recorded_at: x.recordedAt,
        };
      }),
    };
  }

  async notifications(uid: string, limit: number) {
    const col = this.db.collection(`players/${uid}/notifications`);
    const old = await col.where('createdAt', '<', this.now() - 30 * 86_400_000).get();
    await Promise.all(old.docs.map((d) => d.ref.delete()));
    const [items, unread] = await Promise.all([
      col.orderBy('createdAt', 'desc').limit(Math.min(100, Math.max(1, limit || 30))).get(),
      col.where('read', '==', false).count().get(),
    ]);
    return {
      ok: true,
      unread: unread.data().count,
      items: items.docs.map((d) => ({
        id: d.id, kind: d.get('kind'), payload: d.get('payload'),
        created_at: d.get('createdAt'), read: d.get('read') === true,
      })),
    };
  }

  async markNotificationsRead(uid: string) {
    const snap = await this.db.collection(`players/${uid}/notifications`).where('read', '==', false).get();
    const batch = this.db.batch();
    for (const d of snap.docs) batch.update(d.ref, { read: true });
    await batch.commit();
    return { ok: true };
  }

  async registerDevice(uid: string, token: string, platform: string) {
    if (token.length < 20 || token.length > 4096) return err('invalid_token');
    await this.db.doc(`players/${uid}/devices/${encodeURIComponent(token).slice(0, 1400)}`)
      .set({ token, platform: platform.slice(0, 16), updatedAt: this.now() });
    return { ok: true };
  }

  // ---------------------------------------------------------------- monetisation
  /**
   * Applies one store-verified purchase (from the RevenueCat webhook or REST
   * sync — never from the app). Idempotent per transaction id.
   */
  async recordPurchase(
    tx: Transaction, uid: string, transactionId: string, productId: string,
    price: string, revoked: boolean, expiresAt: number | null, willRenew: boolean,
  ) {
    const product = PRODUCTS[productId];
    if (!product) return { accepted: false, message: 'Unknown product.' };
    const eventRef = this.db.doc(`purchases/${uid}/events/${encodeURIComponent(transactionId)}`);
    const itemRefs = product.grants.map((g) => this.db.doc(`inventory/${uid}/items/${g}`));
    const [event, ...items] = await Promise.all([tx.get(eventRef), ...itemRefs.map((r) => tx.get(r))]);
    const duplicate = event.exists;
    const now = this.now();
    if (!duplicate) {
      tx.create(eventRef, {
        transactionId, productId, price, state: revoked ? 'revoked' : 'success',
        revoked, createdAt: now,
      });
    } else if (revoked && !event.get('revoked')) {
      tx.update(eventRef, { revoked: true, state: 'revoked' });
    }
    const entRef = this.db.doc(`entitlements/${uid}`);
    if (revoked) {
      if (product.entitlement) {
        tx.set(entRef, { vip: { active: false, productId, willRenew: false, source: 'store', updatedAt: now } }, { merge: true });
      }
      this.audit(tx, uid, 'purchase_revoked', { transactionId, productId });
      return { accepted: true, duplicate, granted_item_ids: [], message: 'Revoked.' };
    }
    if (product.entitlement) {
      tx.set(entRef, {
        vip: { active: true, productId, expiresAt, willRenew, source: 'store', updatedAt: now },
      }, { merge: true });
    }
    product.grants.forEach((g, i) => {
      if (!items[i].exists) {
        tx.create(itemRefs[i], {
          category: itemCategory(g), equipped: false, grantedBy: transactionId, grantedAt: now,
        });
      }
    });
    this.audit(tx, uid, 'purchase_recorded', { transactionId, productId, duplicate });
    return {
      accepted: true, duplicate, granted_item_ids: product.grants,
      message: duplicate ? 'Already owned.' : '',
    };
  }

  /** One verified store event, applied exactly once (event id is the key). */
  async storeEvent(a: {
    eventId: string; uid: string; transactionId: string; productId: string; price: string;
    revoked: boolean; expiresAt: number | null; willRenew: boolean; source: string;
  }) {
    return this.db.runTransaction(async (tx) => {
      const ref = this.db.doc(`storeEvents/${encodeURIComponent(a.eventId)}`);
      const snap = await tx.get(ref);
      if (snap.exists) {
        return { accepted: true, duplicate: true, granted_item_ids: [], message: 'Event already applied.' };
      }
      const result = await this.recordPurchase(tx, a.uid, a.transactionId, a.productId, a.price,
        a.revoked, a.expiresAt, a.willRenew);
      tx.create(ref, {
        uid: a.uid, productId: a.productId, transactionId: a.transactionId,
        revoked: a.revoked, expiresAt: a.expiresAt, source: a.source, receivedAt: this.now(),
      });
      return result;
    });
  }

  /** Auto-renew switched off: VIP continues until expiry. */
  async storeRenewal(eventId: string, uid: string, productId: string, willRenew: boolean) {
    return this.db.runTransaction(async (tx) => {
      const ref = this.db.doc(`storeEvents/${encodeURIComponent(eventId)}`);
      const ent = this.db.doc(`entitlements/${uid}`);
      const [snap, e] = await Promise.all([tx.get(ref), tx.get(ent)]);
      if (snap.exists) return { accepted: true, duplicate: true };
      tx.create(ref, { uid, productId, source: 'revenuecat_webhook', receivedAt: this.now() });
      if (PRODUCTS[productId]?.entitlement && e.exists && e.get('vip')) {
        tx.update(ent, { 'vip.willRenew': willRenew, 'vip.updatedAt': this.now() });
      }
      return { accepted: true, duplicate: false };
    });
  }

  private audit(tx: Transaction, uid: string, action: string, detail: Json) {
    tx.create(this.db.collection('auditLogs').doc(), { uid, action, detail, createdAt: this.now() });
  }

  private async credit(
    tx: Transaction, uid: string, key: string, delta: number, reason: string, utcDay: number,
    walletSnap: FirebaseFirestore.DocumentSnapshot, wallet: DocumentReference,
  ) {
    const balance = (walletSnap.exists ? (walletSnap.get('balance') as number) : 0) + delta;
    tx.set(wallet, { balance, updatedAt: this.now() }, { merge: true });
    tx.create(this.db.doc(`wallets/${uid}/ledger/${encodeURIComponent(key)}`), {
      delta, balanceAfter: balance, reason, utcDay, createdAt: this.now(),
    });
  }

  /** A rewarded advert Google has verified (SSV). Once per event, capped per day. */
  async ssvReward(uid: string, eventId: string, utcDay: number, coins: number, maxPerDay: number) {
    if (!eventId.trim()) return { outcome: 'rejected', coins: 0, used_today: 0 };
    const amount = Math.max(1, Math.min(coins, 1000));
    const max = Math.max(1, Math.min(maxPerDay, 20));
    return this.db.runTransaction(async (tx) => {
      const ref = this.db.doc(`adRewards/${uid}/events/${encodeURIComponent(eventId)}`);
      const wallet = this.db.doc(`wallets/${uid}`);
      const [snap, today, w] = await Promise.all([
        tx.get(ref),
        tx.get(this.db.collection(`adRewards/${uid}/events`).where('utcDay', '==', utcDay)),
        tx.get(wallet),
      ]);
      const used = today.size;
      if (snap.exists) return { outcome: 'duplicate', coins: 0, used_today: used };
      if (used >= max) return { outcome: 'daily_cap_reached', coins: 0, used_today: used };
      tx.create(ref, { utcDay, coins: amount, verification: 'ssv_verified', createdAt: this.now() });
      await this.credit(tx, uid, `ad:${eventId}`, amount, 'ad_reward', utcDay, w, wallet);
      this.audit(tx, uid, 'ad_reward_granted', { eventId, coins: amount, utcDay });
      return { outcome: 'granted', coins: amount, used_today: used + 1 };
    });
  }

  async claimDailyReward(uid: string, utcDay: number) {
    // Only today's reward, allowing a day either side for the player's time zone.
    const day = (offset: number) =>
      Number(new Date(this.now() + offset * 86_400_000).toISOString().slice(0, 10).replace(/-/g, ''));
    if (![day(-1), day(0), day(1)].includes(utcDay)) return { outcome: 'rejected', coins: 0 };
    const key = `daily:${utcDay}`;
    return this.db.runTransaction(async (tx) => {
      const wallet = this.db.doc(`wallets/${uid}`);
      const ledger = this.db.doc(`wallets/${uid}/ledger/${encodeURIComponent(key)}`);
      const [w, l] = await Promise.all([tx.get(wallet), tx.get(ledger)]);
      if (l.exists) return { outcome: 'duplicate', coins: 0 };
      await this.credit(tx, uid, key, 50, 'daily_reward', utcDay, w, wallet);
      this.audit(tx, uid, 'daily_reward_claimed', { utcDay });
      return { outcome: 'granted', coins: 50 };
    });
  }

  async equip(uid: string, category: string, itemId: string) {
    return this.db.runTransaction(async (tx) => {
      const ref = this.db.doc(`inventory/${uid}/items/${itemId}`);
      const [item, same] = await Promise.all([
        tx.get(ref),
        tx.get(this.db.collection(`inventory/${uid}/items`).where('category', '==', category)),
      ]);
      if (!itemId || !item.exists) return err('not_owned');
      for (const d of same.docs) if (d.get('equipped')) tx.update(d.ref, { equipped: false });
      tx.update(ref, { equipped: true });
      return { ok: true };
    });
  }

  async joinTournament(uid: string, tournamentId: string) {
    if (!tournamentId) return { joined: false, message: 'Tournament not found.' };
    return this.db.runTransaction(async (tx) => {
      const ref = this.db.doc(`tournaments/${tournamentId}`);
      const entry = this.db.doc(`tournaments/${tournamentId}/entries/${uid}`);
      const [t, e] = await Promise.all([tx.get(ref), tx.get(entry)]);
      if (!t.exists) return { joined: false, message: 'Tournament not found.' };
      if (t.get('freeEntryOnly') !== true) return { joined: false, message: 'Paid entry is not supported.' };
      const now = this.now();
      if (!['published', 'live'].includes(t.get('status')) ||
          now < t.get('startsAt') || now > t.get('endsAt')) {
        return { joined: false, message: 'Entry is closed.' };
      }
      if (e.exists) return { joined: false, message: 'Already entered.' };
      tx.create(entry, { uid, correct: 0, tieBreakMs: 0, joinedAt: now });
      tx.update(ref, { participantCount: FieldValue.increment(1) });
      this.audit(tx, uid, 'tournament_joined', { tournamentId });
      return { joined: true, message: '' };
    });
  }

  async standings(tournamentId: string) {
    if (!tournamentId) return { ok: true, scores: [] };
    const snap = await this.db.collection(`tournaments/${tournamentId}/entries`)
      .orderBy('correct', 'desc').orderBy('tieBreakMs', 'asc').limit(50).get();
    return {
      ok: true,
      scores: snap.docs.map((d) => ({
        player_id: d.id, correct: d.get('correct'), tie_break_ms: d.get('tieBreakMs'),
      })),
    };
  }

  // ---------------------------------------------------------------- account deletion
  /** Erases the player's data (App Store 5.1.1(v)); the caller deletes the auth user. */
  async purgeAccount(uid: string) {
    const counts: Record<string, number> = {};
    const del = async (label: string, refs: DocumentReference[]) => {
      counts[label] = (counts[label] ?? 0) + refs.length;
      for (let i = 0; i < refs.length; i += 400) {
        const batch = this.db.batch();
        for (const r of refs.slice(i, i + 400)) batch.delete(r);
        await batch.commit();
      }
    };
    const q = async (path: string, field?: string, value?: unknown) => {
      const col = this.db.collection(path);
      const snap = field ? await col.where(field, '==', value).get() : await col.get();
      return snap.docs.map((d) => d.ref);
    };

    // Live rooms: leave (frees lobby seats, forfeits races). Finished rooms
    // keep the race for the other players, with this racer anonymised.
    const rooms = await this.db.collection('rooms').where('memberIds', 'array-contains', uid).get();
    for (const d of rooms.docs) {
      await this.withRoom(d.id, (r, s, _tx, now) => {
        if (E.isLive(r)) { E.leave(r, uid, now); E.tick(r, s, now); }
        if (r.racers[uid]) r.racers[uid].name = 'Deleted racer';
        for (const x of r.results ?? []) if (x.uid === uid) x.name = 'Deleted racer';
        return null;
      });
    }
    const me = await this.player(uid).get();
    const code = me.exists ? (me.get('friendCode') as string) : null;
    await del('notifications', await q(`players/${uid}/notifications`));
    await del('devices', await q(`players/${uid}/devices`));
    const links = await this.db.collection('friendLinks').where('members', 'array-contains', uid).get();
    await del('friends', links.docs.map((d) => d.ref));
    await del('invites', [...await q('invites', 'to', uid), ...await q('invites', 'from', uid)]);
    await del('blocks', [...await q('blocks', 'blocker', uid), ...await q('blocks', 'blocked', uid)]);
    await del('reports', [...await q('playerReports', 'reporter', uid), ...await q('playerReports', 'target', uid)]);
    await del('question_reports', await q('questionReports', 'reporter', uid));
    await del('results', await q('raceResults', 'uid', uid));
    const boards = await this.db.collectionGroup('rows').where('uid', '==', uid).get();
    await del('leaderboard_rows', boards.docs.map((d) => d.ref));
    await del('rate_limits', await q('rateLimits', 'uid', uid));
    await del('wallet', [...await q(`wallets/${uid}/ledger`), this.db.doc(`wallets/${uid}`)]);
    await del('inventory', await q(`inventory/${uid}/items`));
    await del('purchases', await q(`purchases/${uid}/events`));
    await del('ad_rewards', await q(`adRewards/${uid}/events`));
    await del('entitlements', [this.db.doc(`entitlements/${uid}`)]);
    await del('tournament_entries', (await this.db.collectionGroup('entries').where('uid', '==', uid).get()).docs.map((d) => d.ref));
    await del('store_events', await q('storeEvents', 'uid', uid));
    await del('audit_logs', await q('auditLogs', 'uid', uid));
    await del('history', [this.db.doc(`questionHistory/${uid}`)]);
    await del('profile', [this.player(uid), ...(code ? [this.db.doc(`friendCodes/${code}`)] : [])]);
    return { ok: true, deleted: counts };
  }
}
