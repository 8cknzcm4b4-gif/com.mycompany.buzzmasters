// firestore.rules against the emulator: clients read only what is theirs,
// and can write nothing — scores, VIP, coins and rewards are server-only.
import { test, before, after } from 'node:test';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import {
  assertFails, assertSucceeds, initializeTestEnvironment, type RulesTestEnvironment,
} from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, updateDoc, deleteDoc, collection, getDocs, addDoc } from 'firebase/firestore';

let env: RulesTestEnvironment;
const ALICE = 'aliceUid00000000000000000001';
const MALLORY = 'malloryUid000000000000000002';

before(async () => {
  const [host, port] = process.env.FIRESTORE_EMULATOR_HOST!.split(':');
  env = await initializeTestEnvironment({
    projectId: 'demo-buzz-masters-rules',
    firestore: {
      host, port: Number(port),
      rules: readFileSync(join(__dirname, '../../../firestore.rules'), 'utf8'),
    },
  });
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, `players/${ALICE}`), { name: 'Alice', friendCode: 'ABC234' });
    await setDoc(doc(db, `players/${ALICE}/notifications/n1`), { kind: 'race_result' });
    await setDoc(doc(db, 'rooms/r1'), { memberIds: [ALICE], status: 'racing', racers: {} });
    await setDoc(doc(db, 'rooms/r1/secret/state'), { questions: [{ correctIndex: 2 }] });
    await setDoc(doc(db, `rooms/r1/mine/${ALICE}`), { q: 0, option: 2 });
    await setDoc(doc(db, `leaderboards/all/rows/${ALICE}`), { wins: 1 });
    await setDoc(doc(db, `entitlements/${ALICE}`), { vip: { active: true } });
    await setDoc(doc(db, `wallets/${ALICE}`), { balance: 50 });
    await setDoc(doc(db, `wallets/${ALICE}/ledger/daily:1`), { delta: 50 });
    await setDoc(doc(db, `inventory/${ALICE}/items/trail_neon`), { equipped: false });
    await setDoc(doc(db, `adRewards/${ALICE}/events/ad-1`), { verification: 'ssv_verified' });
    await setDoc(doc(db, 'tournaments/live'), { status: 'live' });
    await setDoc(doc(db, 'tournaments/draft'), { status: 'draft' });
    await setDoc(doc(db, 'questions/q001'), { correctIndex: 1 });
    await setDoc(doc(db, 'friendCodes/ABC234'), { uid: ALICE });
  });
});

after(async () => { await env?.cleanup(); });

test('players read their own profile, notifications and answers only', async () => {
  const alice = env.authenticatedContext(ALICE).firestore();
  const mallory = env.authenticatedContext(MALLORY).firestore();
  await assertSucceeds(getDoc(doc(alice, `players/${ALICE}`)));
  await assertSucceeds(getDocs(collection(alice, `players/${ALICE}/notifications`)));
  await assertSucceeds(getDoc(doc(alice, `rooms/r1/mine/${ALICE}`)));
  await assertFails(getDoc(doc(mallory, `players/${ALICE}`)));
  await assertFails(getDocs(collection(mallory, `players/${ALICE}/notifications`)));
  await assertFails(getDoc(doc(mallory, `rooms/r1/mine/${ALICE}`)));
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), `players/${ALICE}`)));
});

test('rooms are visible to their racers only; answer keys to nobody', async () => {
  const alice = env.authenticatedContext(ALICE).firestore();
  const mallory = env.authenticatedContext(MALLORY).firestore();
  await assertSucceeds(getDoc(doc(alice, 'rooms/r1')));
  await assertFails(getDoc(doc(mallory, 'rooms/r1')));
  await assertFails(getDoc(doc(alice, 'rooms/r1/secret/state')));
  await assertFails(getDoc(doc(alice, 'questions/q001')));
  await assertFails(getDoc(doc(alice, 'friendCodes/ABC234')));
});

test('no client can write scores, rooms, profiles or rankings', async () => {
  const alice = env.authenticatedContext(ALICE).firestore();
  await assertFails(updateDoc(doc(alice, 'rooms/r1'), { status: 'finished' }));
  await assertFails(setDoc(doc(alice, 'rooms/r2'), { memberIds: [ALICE] }));
  await assertFails(setDoc(doc(alice, `rooms/r1/mine/${ALICE}`), { q: 0, option: 1, correct: true }));
  await assertFails(updateDoc(doc(alice, `players/${ALICE}`), { name: 'x' }));
  await assertFails(setDoc(doc(alice, `leaderboards/all/rows/${ALICE}`), { wins: 999 }));
  await assertFails(addDoc(collection(alice, 'raceResults'), { uid: ALICE, placing: 1 }));
  await assertFails(deleteDoc(doc(alice, `players/${ALICE}/notifications/n1`)));
});

test('nobody can grant themselves VIP, coins, items or ad rewards', async () => {
  const alice = env.authenticatedContext(ALICE).firestore();
  const mallory = env.authenticatedContext(MALLORY).firestore();
  await assertSucceeds(getDoc(doc(alice, `entitlements/${ALICE}`)));
  await assertSucceeds(getDoc(doc(alice, `wallets/${ALICE}`)));
  await assertSucceeds(getDocs(collection(alice, `wallets/${ALICE}/ledger`)));
  await assertSucceeds(getDocs(collection(alice, `inventory/${ALICE}/items`)));
  await assertSucceeds(getDoc(doc(alice, `adRewards/${ALICE}/events/ad-1`)));
  await assertFails(setDoc(doc(mallory, `entitlements/${MALLORY}`), { vip: { active: true } }));
  await assertFails(updateDoc(doc(alice, `entitlements/${ALICE}`), { 'vip.expiresAt': 9e15 }));
  await assertFails(setDoc(doc(alice, `wallets/${ALICE}`), { balance: 1_000_000 }));
  await assertFails(setDoc(doc(alice, `wallets/${ALICE}/ledger/free`), { delta: 999 }));
  await assertFails(setDoc(doc(alice, `inventory/${ALICE}/items/neon_phantom`), { equipped: true }));
  await assertFails(setDoc(doc(alice, `adRewards/${ALICE}/events/fake`), { verification: 'ssv_verified' }));
  await assertFails(setDoc(doc(alice, `purchases/${ALICE}/events/fake`), { state: 'success' }));
  await assertFails(getDoc(doc(mallory, `entitlements/${ALICE}`)));
  await assertFails(getDoc(doc(mallory, `wallets/${ALICE}`)));
});

test('rankings and published tournaments are readable when signed in', async () => {
  const alice = env.authenticatedContext(ALICE).firestore();
  await assertSucceeds(getDoc(doc(alice, `leaderboards/all/rows/${ALICE}`)));
  await assertSucceeds(getDoc(doc(alice, 'tournaments/live')));
  await assertFails(getDoc(doc(alice, 'tournaments/draft')));
  await assertFails(setDoc(doc(alice, 'tournaments/live/entries/' + ALICE), { correct: 99 }));
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), `leaderboards/all/rows/${ALICE}`)));
});
