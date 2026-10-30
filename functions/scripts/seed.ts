// Seeds the question bank into Firestore (`questions/`). Uses Application
// Default Credentials or the emulator (FIRESTORE_EMULATOR_HOST). Only ever
// targets buzz-masters-race or a demo-* emulator project.
import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { BANK } from '../src/questions';

const projectId = process.env.GCLOUD_PROJECT ?? 'buzz-masters-race';
if (projectId !== 'buzz-masters-race' && !projectId.startsWith('demo-')) {
  throw new Error(`refusing to seed ${projectId}`);
}
initializeApp({ projectId });
(async () => {
  const db = getFirestore();
  const batch = db.batch();
  for (const { id, ...q } of BANK) {
    batch.set(db.doc(`questions/${id}`), { ...q, active: true }, { merge: true });
  }
  await batch.commit();
  console.log(`seeded ${BANK.length} questions into ${projectId}`);
})();
