// TEMP adversarial probe — LEGACY DATA + OLD BUILDS lens.
// Question: do the NEW rules deny a write that an ALREADY-INSTALLED build
// (1.1.8 and older) performs today against data that is ALREADY in Firestore?
// Every write shape below is copied verbatim from git HEAD (= shipped 1.1.8).
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { doc, addDoc, collection, setDoc, updateDoc, deleteDoc, getDoc, writeBatch,
         serverTimestamp, deleteField, arrayRemove } from 'firebase/firestore';

const __dirname = dirname(fileURLToPath(import.meta.url));
const RULES = readFileSync(join(__dirname, '..', 'firestore.rules'), 'utf8');

const A = 'owner_A';        // owner / master
const C = 'collab_C';       // LEGACY account-wide collaborator (users/C.masterUserId == A)
const M = 'member_M';       // workspace-scoped member (editor)
const V = 'viewer_V';       // workspace-scoped member (viewer)
const S = 'stranger_S';

let env, passed = 0, failed = 0;
const fails = [];
async function t(name, fn) {
  try { await fn(); passed++; console.log(`  PASS  ${name}`); }
  catch (e) { failed++; fails.push(name); console.log(`  FAIL  ${name}\n        ${String(e.message).slice(0,220)}`); }
}
const as = (u) => env.authenticatedContext(u, { email: `${u}@x.com` }).firestore();
const anon = () => env.unauthenticatedContext().firestore();

// ── Workspace doc shapes that can exist in production TODAY ─────────────────
const wsBase = (over = {}) => ({
  ownerId: A, name: 'Carteira', memberUids: [A, C, M, V],
  roles: { [A]: 'editor', [C]: 'editor', [M]: 'editor', [V]: 'viewer' },
  isDefault: false, archived: false, order: 0, createdAt: new Date(), ...over,
});
const WS_SHAPES = {
  ws_personal:  wsBase({ type: 'personal' }),                 // notifier create / migration
  ws_business:  wsBase({ type: 'business' }),                 // notifier create (PJ)
  ws_notype:    (() => { const d = wsBase(); delete d.type; return d; })(),  // hand-made / pre-Carteira
  ws_nulltype:  wsBase({ type: null }),                       // type written as null
  ws_junk:      wsBase({ type: 'pf' }),                       // console/script/experiment value
  ws_empty:     wsBase({ type: '' }),                         // empty string
  ws_holding:   wsBase({ type: 'holding' }),                  // only exists AFTER 1.1.9 ships
};

// EXACT ledger doc shape written by shipped builds.
const ledgerDoc = (over = {}) => ({
  userId: A, title: 'x', amount: 10, type: 'expense', category: 'c',
  date: new Date(), description: null, walletId: 'w', sourceWalletId: null,
  goalId: null, isPending: false, tags: [], attachmentUrls: [],
  workspaceId: 'ws_personal', createdAt: serverTimestamp(), ...over,
});
const LEDGER = ['transactions','categories','budgets','wallets','goals',
  'recurring_transactions','category_rules','bills','investment_assets','investment_trades'];

async function seed() {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'users', A), { email: `${A}@x.com`, workspaceMigrationVersion: 2 });
    await setDoc(doc(db, 'users', C), { email: `${C}@x.com`, masterUserId: A, masterInvitationId: 'inv1' });
    await setDoc(doc(db, 'users', M), { email: `${M}@x.com` });
    await setDoc(doc(db, 'users', V), { email: `${V}@x.com` });
    await setDoc(doc(db, 'users', S), { email: `${S}@x.com` });
    for (const [id, d] of Object.entries(WS_SHAPES)) await setDoc(doc(db, 'workspaces', id), d);
    // Pre-migration ledger docs (no workspaceId at all) in every backfilled collection.
    for (const c of LEDGER) {
      const d = ledgerDoc(); delete d.workspaceId;
      await setDoc(doc(db, c, `legacy_${c}`), d);
      await setDoc(doc(db, c, `scoped_${c}`), ledgerDoc());
    }
    // A big legacy batch for the migration backfill (400-doc batches in prod).
    for (let i = 0; i < 60; i++) {
      const d = ledgerDoc(); delete d.workspaceId;
      await setDoc(doc(db, 'transactions', `bf_${i}`), d);
    }
    // Ledger docs whose Carteira has a weird/missing type.
    for (const w of ['ws_notype','ws_nulltype','ws_junk','ws_empty']) {
      await setDoc(doc(db, 'transactions', `tx_${w}`), ledgerDoc({ workspaceId: w }));
    }
    // Orphans: docs whose Carteira was already deleted (cascade interrupted).
    await setDoc(doc(db, 'transactions', 'tx_orphan'), ledgerDoc({ workspaceId: 'ws_gone' }));
    await setDoc(doc(db, 'investment_assets', 'ia_orphan'), ledgerDoc({ workspaceId: 'ws_gone' }));
    // New-collection docs (post-1.1.9 data) for read-isolation tests.
    await setDoc(doc(db, 'holding_members', 'hm1'), { userId: A, workspaceId: 'ws_holding', name: 'Sócio 1', quotaBps: 5000 });
    await setDoc(doc(db, 'holding_contributions', 'hc1'), { userId: A, workspaceId: 'ws_holding', memberId: 'hm1', amountCents: 500000, createdBy: A });
    // Orphaned holding docs (Carteira already deleted).
    await setDoc(doc(db, 'holding_members', 'hm_orphan'), { userId: A, workspaceId: 'ws_gone', name: 'S', quotaBps: 1 });
    await setDoc(doc(db, 'holding_contributions', 'hc_orphan'), { userId: A, workspaceId: 'ws_gone', memberId: 'hm_orphan', amountCents: 1, createdBy: A });
  });
}

(async () => {
  env = await initializeTestEnvironment({ projectId: 'demo-fintab', firestore: { rules: RULES, host: '127.0.0.1', port: 8080 } });
  await seed();

  console.log('\n=== 1. SHIPPED 1.1.8 /workspaces WRITES against every legacy doc shape ===');
  for (const id of Object.keys(WS_SHAPES)) {
    // workspaces_notifier.rename() — partial update
    await t(`rename ${id}  [workspaces_notifier.dart:44]`, () =>
      assertSucceeds(updateDoc(doc(as(A), 'workspaces', id), { name: 'Novo nome' })));
    // workspaces_notifier.setArchived() — partial update
    await t(`archive ${id}  [workspaces_notifier.dart:57]`, () =>
      assertSucceeds(updateDoc(doc(as(A), 'workspaces', id), { archived: true })));
    // sharing_remote_datasource.removeCollaborator() — arrayRemove + roles.X delete
    await t(`removeCollaborator on ${id}  [sharing_remote_datasource.dart:194]`, () =>
      assertSucceeds(updateDoc(doc(as(A), 'workspaces', id), {
        memberUids: arrayRemove(M), [`roles.${M}`]: deleteField() })));
  }

  console.log('\n=== 2. SHIPPED create paths ===');
  await t('notifier.create PF  [workspaces_notifier.dart:24]', () =>
    assertSucceeds(addDoc(collection(as(A), 'workspaces'), {
      ownerId: A, name: 'Nova', type: 'personal', memberUids: [A],
      roles: { [A]: 'editor' }, isDefault: false, archived: false,
      order: 1750000000, createdAt: serverTimestamp() })));
  await t('notifier.create PJ', () =>
    assertSucceeds(addDoc(collection(as(A), 'workspaces'), {
      ownerId: A, name: 'Empresa', type: 'business', memberUids: [A],
      roles: { [A]: 'editor' }, isDefault: false, archived: false,
      order: 1750000001, createdAt: serverTimestamp() })));
  await t('migration creates ws_<uid>_default  [workspace_migration_provider.dart:98]', () =>
    assertSucceeds(setDoc(doc(as(A), 'workspaces', `ws_${A}_default`), {
      ownerId: A, name: 'Pessoal', type: 'personal', memberUids: [A, C],
      roles: { [A]: 'editor', [C]: 'editor' }, isDefault: true, archived: false,
      order: 0, createdAt: serverTimestamp() })));

  console.log('\n=== 3. MIGRATION set()-OVERWRITE (get() threw -> exists=false -> full set) ===');
  const migSet = (id) => setDoc(doc(as(A), 'workspaces', id), {
    ownerId: A, name: 'Pessoal', type: 'personal', memberUids: [A],
    roles: { [A]: 'editor' }, isDefault: true, archived: false, order: 0,
    createdAt: serverTimestamp() });
  await t('overwrite a PERSONAL ws (the only shape ws_<uid>_default can have)', () => assertSucceeds(migSet('ws_personal')));
  await t('overwrite a no-type ws', () => assertSucceeds(migSet('ws_notype')));
  await t('overwrite a BUSINESS ws -> denied by workspaceTypeSticky (expected)', () => assertFails(migSet('ws_business')));
  await t('overwrite a HOLDING ws -> denied by workspaceTypeSticky (expected)', () => assertFails(migSet('ws_holding')));

  console.log('\n=== 4. MIGRATION BACKFILL (batch.update workspaceId) + invitation stamping ===');
  await t('backfill 60 legacy transactions in ONE batch  [workspace_migration_provider.dart:139]', async () => {
    const db = as(A); const b = writeBatch(db);
    for (let i = 0; i < 60; i++) b.update(doc(db, 'transactions', `bf_${i}`), { workspaceId: 'ws_personal' });
    await assertSucceeds(b.commit());
  });
  for (const c of LEDGER) {
    await t(`backfill workspaceId onto legacy ${c}`, () =>
      assertSucceeds(updateDoc(doc(as(A), c, `legacy_${c}`), { workspaceId: 'ws_personal' })));
  }

  console.log('\n=== 5. LEDGER writes inside Carteiras with a weird/missing type ===');
  for (const w of ['ws_notype','ws_nulltype','ws_junk','ws_empty']) {
    await t(`create a transaction in ${w}`, () =>
      assertSucceeds(setDoc(doc(as(A), 'transactions', `new_${w}`), ledgerDoc({ workspaceId: w }))));
    await t(`update the transaction in ${w}`, () =>
      assertSucceeds(updateDoc(doc(as(A), 'transactions', `tx_${w}`), { title: 'edit' })));
    await t(`MOVE a tx into ${w} (move screen)`, () =>
      assertSucceeds(updateDoc(doc(as(A), 'transactions', `scoped_transactions`), { workspaceId: w })));
  }
  await t('legacy collaborator edits a tx in a no-type Carteira', () =>
    assertSucceeds(updateDoc(doc(as(C), 'transactions', 'tx_ws_notype'), { title: 'collab' })));

  console.log('\n=== 6. ORPHANS: doc whose Carteira is already deleted ===');
  await t('owner updates an orphaned transaction (legacyAccess)', () =>
    assertSucceeds(updateDoc(doc(as(A), 'transactions', 'tx_orphan'), { title: 'fix' })));
  await t('owner MOVES an orphaned transaction back into a real Carteira', () =>
    assertSucceeds(updateDoc(doc(as(A), 'transactions', 'tx_orphan'), { workspaceId: 'ws_personal' })));
  await t('owner deletes an orphaned investment_asset (cascade leftover)', () =>
    assertSucceeds(deleteDoc(doc(as(A), 'investment_assets', 'ia_orphan'))));
  await t('owner deletes an ORPHANED holding_member (Carteira gone)', () =>
    assertSucceeds(deleteDoc(doc(as(A), 'holding_members', 'hm_orphan'))));
  await t('owner deletes an ORPHANED holding_contribution (Carteira gone)', () =>
    assertSucceeds(deleteDoc(doc(as(A), 'holding_contributions', 'hc_orphan'))));

  console.log('\n=== 7. DELETE CASCADE with the workspace doc removed FIRST ===');
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'workspaces', 'ws_doomed'), wsBase({ type: 'business' }));
    await setDoc(doc(db, 'transactions', 'doomed_tx'), ledgerDoc({ workspaceId: 'ws_doomed' }));
    await setDoc(doc(db, 'holding_members', 'doomed_hm'), { userId: A, workspaceId: 'ws_doomed', name: 'S', quotaBps: 10 });
    await setDoc(doc(db, 'holding_contributions', 'doomed_hc'), { userId: A, workspaceId: 'ws_doomed', memberId: 'doomed_hm', amountCents: 1, createdBy: A });
  });
  await t('delete the workspace doc first', () =>
    assertSucceeds(deleteDoc(doc(as(A), 'workspaces', 'ws_doomed'))));
  await t('then delete its leftover transaction', () =>
    assertSucceeds(deleteDoc(doc(as(A), 'transactions', 'doomed_tx'))));
  await t('then delete its leftover holding_member', () =>
    assertSucceeds(deleteDoc(doc(as(A), 'holding_members', 'doomed_hm'))));
  await t('then delete its leftover holding_contribution', () =>
    assertSucceeds(deleteDoc(doc(as(A), 'holding_contributions', 'doomed_hc'))));

  console.log('\n=== 8. NEW COLLECTIONS: read isolation / no accidental widening ===');
  await t('member (editor) READS holding_members', () => assertSucceeds(getDoc(doc(as(M), 'holding_members', 'hm1'))));
  await t('viewer READS holding_members', () => assertSucceeds(getDoc(doc(as(V), 'holding_members', 'hm1'))));
  await t('STRANGER cannot read holding_members', () => assertFails(getDoc(doc(as(S), 'holding_members', 'hm1'))));
  await t('STRANGER cannot read holding_contributions', () => assertFails(getDoc(doc(as(S), 'holding_contributions', 'hc1'))));
  await t('ANONYMOUS cannot read holding_members', () => assertFails(getDoc(doc(anon(), 'holding_members', 'hm1'))));
  await t('LEGACY account-wide collaborator (not a ws member) cannot read holding_members', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'holding_members', 'hm_priv'),
        { userId: A, workspaceId: 'ws_private', name: 'S', quotaBps: 1 });
      await setDoc(doc(ctx.firestore(), 'workspaces', 'ws_private'), wsBase({ type: 'holding', memberUids: [A], roles: { [A]: 'editor' } }));
    });
    await assertFails(getDoc(doc(as(C), 'holding_members', 'hm_priv')));
  });
  await t('editor collaborator cannot CREATE a holding_member (owner-only)', () =>
    assertFails(setDoc(doc(as(M), 'holding_members', 'hm_bad'),
      { userId: A, workspaceId: 'ws_holding', name: 'Eu', quotaBps: 10000 })));
  await t('editor collaborator cannot RAISE their own quota', () =>
    assertFails(updateDoc(doc(as(M), 'holding_members', 'hm1'), { quotaBps: 10000 })));
  await t('stranger cannot create a holding_member in someone else\'s Carteira', () =>
    assertFails(setDoc(doc(as(S), 'holding_members', 'hm_bad2'),
      { userId: S, workspaceId: 'ws_holding', name: 'Eu', quotaBps: 10000 })));
  await t('editor MAY create a holding_contribution (intended)', () =>
    assertSucceeds(setDoc(doc(as(M), 'holding_contributions', 'hc_new'),
      { userId: A, workspaceId: 'ws_holding', memberId: 'hm1', amountCents: 1000, createdBy: M })));
  await t('editor cannot rewrite a contribution amount', () =>
    assertFails(updateDoc(doc(as(M), 'holding_contributions', 'hc1'), { amountCents: 999 })));
  await t('editor cannot DELETE a contribution (owner-only)', () =>
    assertFails(deleteDoc(doc(as(M), 'holding_contributions', 'hc1'))));

  console.log('\n=== 9. NO WIDENING of existing collections (spot checks) ===');
  await t('stranger still cannot read a transaction', () => assertFails(getDoc(doc(as(S), 'transactions', 'scoped_transactions'))));
  await t('stranger still cannot write a workspace', () => assertFails(updateDoc(doc(as(S), 'workspaces', 'ws_personal'), { name: 'hax' })));
  await t('viewer still cannot write a transaction', () => assertFails(updateDoc(doc(as(V), 'transactions', 'scoped_transactions'), { title: 'hax' })));
  await t('legacy collaborator still CAN create a legacy (no-workspaceId) tx', async () => {
    const d = ledgerDoc(); delete d.workspaceId;
    await assertSucceeds(setDoc(doc(as(C), 'transactions', 'legacy_by_collab'), d));
  });

  console.log(`\n==== ${passed} passed, ${failed} failed ====`);
  if (failed) console.log('FAILED:\n - ' + fails.join('\n - '));
  await env.cleanup();
  process.exit(0);
})();
