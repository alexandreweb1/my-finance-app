// Follow-up probe: (a) clean re-run of the two section-8 checks that my own
// section-1 mutation invalidated, (b) is a junk-typed workspace repairable?
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { doc, setDoc, updateDoc, deleteDoc, getDoc } from 'firebase/firestore';

const __dirname = dirname(fileURLToPath(import.meta.url));
const RULES = readFileSync(join(__dirname, '..', 'firestore.rules'), 'utf8');
const A = 'owner_A', M = 'member_M', V = 'viewer_V';
let env, passed = 0, failed = 0; const fails = [];
async function t(n, fn) { try { await fn(); passed++; console.log('  PASS  ' + n); }
  catch (e) { failed++; fails.push(n); console.log('  FAIL  ' + n + '\n        ' + String(e.message).slice(0,200)); } }
const as = (u) => env.authenticatedContext(u, { email: u + '@x.com' }).firestore();

const ws = (over) => ({ ownerId: A, name: 'C', memberUids: [A, M, V],
  roles: { [A]: 'editor', [M]: 'editor', [V]: 'viewer' },
  isDefault: false, archived: false, order: 0, createdAt: new Date(), ...over });

(async () => {
  env = await initializeTestEnvironment({ projectId: 'demo-fintab2', firestore: { rules: RULES, host: '127.0.0.1', port: 8080 } });
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'users', A), { email: 'a@x.com' });
    await setDoc(doc(db, 'users', M), { email: 'm@x.com' });
    await setDoc(doc(db, 'workspaces', 'ws_h'), ws({ type: 'holding' }));
    await setDoc(doc(db, 'workspaces', 'ws_junk'), ws({ type: 'pf' }));
    await setDoc(doc(db, 'workspaces', 'ws_null'), ws({ type: null }));
    await setDoc(doc(db, 'holding_members', 'hm1'), { userId: A, workspaceId: 'ws_h', name: 'S1', quotaBps: 5000 });
    await setDoc(doc(db, 'holding_contributions', 'hc1'), { userId: A, workspaceId: 'ws_h', memberId: 'hm1', amountCents: 100, createdBy: A });
  });

  console.log('\n=== clean re-run of the section-8 checks ===');
  await t('editor member READS holding_members', () => assertSucceeds(getDoc(doc(as(M), 'holding_members', 'hm1'))));
  await t('editor member READS holding_contributions', () => assertSucceeds(getDoc(doc(as(M), 'holding_contributions', 'hc1'))));
  await t('viewer member READS holding_contributions', () => assertSucceeds(getDoc(doc(as(V), 'holding_contributions', 'hc1'))));
  await t('editor MAY create a holding_contribution (intended)', () =>
    assertSucceeds(setDoc(doc(as(M), 'holding_contributions', 'hc_new'),
      { userId: A, workspaceId: 'ws_h', memberId: 'hm1', amountCents: 1000, createdBy: M })));
  await t('viewer may NOT create a holding_contribution', () =>
    assertFails(setDoc(doc(as(V), 'holding_contributions', 'hc_v'),
      { userId: A, workspaceId: 'ws_h', memberId: 'hm1', amountCents: 1000, createdBy: V })));

  console.log('\n=== is a workspace with an out-of-list `type` repairable from a client? ===');
  await t('owner READS the junk-typed ws (unchanged)', () => assertSucceeds(getDoc(doc(as(A), 'workspaces', 'ws_junk'))));
  await t('rename it -> DENIED', () => assertFails(updateDoc(doc(as(A), 'workspaces', 'ws_junk'), { name: 'x' })));
  await t('rename it AND fix the type in the same write -> DENIED (sticky)', () =>
    assertFails(updateDoc(doc(as(A), 'workspaces', 'ws_junk'), { name: 'x', type: 'personal' })));
  await t('rewrite type to the SAME junk value -> DENIED (validWorkspaceType)', () =>
    assertFails(updateDoc(doc(as(A), 'workspaces', 'ws_junk'), { type: 'pf' })));
  await t('same for a null type: any update -> DENIED', () =>
    assertFails(updateDoc(doc(as(A), 'workspaces', 'ws_null'), { name: 'x' })));
  await t('null type: set type=personal in the same write -> DENIED (sticky)', () =>
    assertFails(updateDoc(doc(as(A), 'workspaces', 'ws_null'), { type: 'personal' })));
  await t('owner can still DELETE the junk-typed ws (escape hatch)', () =>
    assertSucceeds(deleteDoc(doc(as(A), 'workspaces', 'ws_junk'))));

  console.log(`\n==== ${passed} passed, ${failed} failed ====`);
  if (failed) console.log('FAILED:\n - ' + fails.join('\n - '));
  await env.cleanup(); process.exit(0);
})();
