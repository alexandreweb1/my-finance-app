// Emulator-based security tests for ../firestore.rules
//
// Run with:
//   firebase emulators:exec --project demo-fintab --only firestore \
//     "node firestore-rules-test/rules.test.js"
//
// Each test asserts a write/read either SUCCEEDS (legit flow) or FAILS
// (attack / denied). Scenarios mirror the adversarial review of the 3
// critical fixes (masterUserId escalation, subscription forging, deletion).

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from '@firebase/rules-unit-testing';
import {
  doc,
  setDoc,
  getDoc,
  updateDoc,
  deleteDoc,
  writeBatch,
  serverTimestamp,
  Timestamp,
  deleteField,
  arrayRemove,
} from 'firebase/firestore';

const __dirname = dirname(fileURLToPath(import.meta.url));
const RULES = readFileSync(join(__dirname, '..', 'firestore.rules'), 'utf8');

const A = 'master_A';
const C = 'collab_C';
const D = 'stranger_D';
const V = 'viewer_V';
const A_EMAIL = 'master@example.com';
const C_EMAIL = 'collab@example.com';
const V_EMAIL = 'viewer@example.com';
const INV = 'inv_AC';

// Holding fixtures: one Holding Carteira (A owns, C edits, V only reads) and
// one PF Carteira of the same owner, used as the "other Carteira" in the
// cross-workspace and holdingSplit-injection tests.
const WS_H = 'ws_holding';
const WS_PF = 'ws_pf';
const M1 = 'hm_socio1';
const M_OTHER = 'hm_socio_pf';
const HC1 = 'hc_aporte1';

const days = (n) => Timestamp.fromMillis(Date.now() + n * 86400 * 1000);

let env;
let passed = 0;
let failed = 0;
const failures = [];

async function test(name, fn) {
  try {
    await fn();
    passed++;
    console.log(`  ✅ ${name}`);
  } catch (e) {
    failed++;
    failures.push({ name, error: e.message });
    console.log(`  ❌ ${name}\n       ${e.message}`);
  }
}

// Auth context helpers (token carries email so callerEmail() works).
const asA = () => env.authenticatedContext(A, { email: A_EMAIL }).firestore();
const asC = () => env.authenticatedContext(C, { email: C_EMAIL }).firestore();
// Stranger D shares C's email-less identity; give D a distinct email.
const asD = () => env.authenticatedContext(D, { email: 'd@example.com' }).firestore();
const asV = () => env.authenticatedContext(V, { email: V_EMAIL }).firestore();
// Mixed-case email to prove callerEmail().lower() normalisation.
const asCUpper = () =>
  env.authenticatedContext(C, { email: 'Collab@Example.com' }).firestore();

// Seed baseline data with rules DISABLED (simulates prior legit state).
async function seed() {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'users', A), { userId: A, email: A_EMAIL });
    await setDoc(doc(db, 'users', C), { userId: C, email: C_EMAIL });
    await setDoc(doc(db, 'users', D), { userId: D, email: 'd@example.com' });
    await setDoc(doc(db, 'transactions', 'tx_A1'), {
      userId: A,
      title: 'A salary',
      amount: 100,
    });
    await setDoc(doc(db, 'invitations', INV), {
      id: INV,
      masterUserId: A,
      masterEmail: A_EMAIL,
      masterName: 'A',
      inviteeEmail: C_EMAIL,
      status: 'pending',
      createdAt: serverTimestamp(),
    });
  });
}

// Promote C to an accepted collaborator of A (rules DISABLED), used by tests
// that need the post-accept state without re-running the batch each time.
async function makeCcollaborator() {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await updateDoc(doc(db, 'invitations', INV), {
      status: 'accepted',
      collaboratorUserId: C,
    });
    await setDoc(
      doc(db, 'users', C),
      { userId: C, email: C_EMAIL, masterUserId: A, masterInvitationId: INV },
      { merge: true },
    );
  });
}

// Seeds the Holding scenario on top of seed() (rules DISABLED). Roles mirror
// production: the owner is always an editor of their own Carteira.
async function seedHolding() {
  await seed();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'users', V), { userId: V, email: V_EMAIL });
    await setDoc(doc(db, 'workspaces', WS_H), {
      ownerId: A,
      name: 'Holding da Família',
      type: 'holding',
      holdingQuotaMode: 'proportional',
      memberUids: [A, C, V],
      roles: { [A]: 'editor', [C]: 'editor', [V]: 'viewer' },
      isDefault: false,
      archived: false,
      order: 1,
      createdAt: serverTimestamp(),
    });
    await setDoc(doc(db, 'workspaces', WS_PF), {
      ownerId: A,
      name: 'Pessoal',
      type: 'personal',
      memberUids: [A, C],
      roles: { [A]: 'editor', [C]: 'editor' },
      isDefault: true,
      archived: false,
      order: 0,
      createdAt: serverTimestamp(),
    });
    await setDoc(doc(db, 'holding_members', M1), socio({ name: 'Alex' }));
    await setDoc(
      doc(db, 'holding_members', M_OTHER),
      socio({ name: 'Sócio da PF', workspaceId: WS_PF }),
    );
    await setDoc(doc(db, 'holding_contributions', HC1), aporte(A));
  });
}

// Valid payloads; `by` is the uid recording the aporte (createdBy must be the
// caller). Overrides make each attack differ from a legit write by one field.
function socio(over = {}) {
  return {
    userId: A,
    workspaceId: WS_H,
    name: 'Sócio',
    quotaBps: 5000,
    joinedAt: days(-365),
    createdAt: serverTimestamp(),
    ...over,
  };
}

function aporte(by, over = {}) {
  return {
    userId: A,
    workspaceId: WS_H,
    memberId: M1,
    amountCents: 500000, // R$ 5.000,00
    date: days(-10),
    createdBy: by,
    createdAt: serverTimestamp(),
    ...over,
  };
}

async function main() {
  env = await initializeTestEnvironment({
    projectId: 'demo-fintab',
    firestore: { rules: RULES, host: '127.0.0.1', port: 8080 },
  });

  console.log('\n── masterUserId / privilege escalation ──');

  await seed();
  await test('ATTACK: stranger sets masterUserId=A on own profile without invite → denied', async () => {
    await assertFails(
      updateDoc(doc(asD(), 'users', D), { masterUserId: A }),
    );
  });

  await seed();
  await test('ATTACK: create own profile with masterUserId=A directly → denied', async () => {
    // fresh uid with no existing profile
    const E = 'fresh_E';
    const dbE = env.authenticatedContext(E, { email: 'e@example.com' }).firestore();
    await assertFails(
      setDoc(doc(dbE, 'users', E), { userId: E, masterUserId: A }),
    );
  });

  await seed();
  await test('ATTACK: stranger creates invitation with masterUserId=A (someone else) → denied', async () => {
    await assertFails(
      setDoc(doc(asD(), 'invitations', 'inv_fake'), {
        id: 'inv_fake',
        masterUserId: A,
        masterEmail: A_EMAIL,
        inviteeEmail: 'd@example.com',
        status: 'pending',
      }),
    );
  });

  await seed();
  await test('HAPPY: C accepts invite via batch (invitation→accepted + profile link) → allowed', async () => {
    const db = asC();
    const batch = writeBatch(db);
    batch.update(doc(db, 'invitations', INV), {
      status: 'accepted',
      collaboratorUserId: C,
    });
    batch.set(
      doc(db, 'users', C),
      { masterUserId: A, masterInvitationId: INV },
      { merge: true },
    );
    await assertSucceeds(batch.commit());
  });

  await seed();
  await test('ATTACK: C forges link with masterInvitationId pointing at someone-else’s invite → denied', async () => {
    // Invitation INV is addressed to C, but C tries to claim D as master with a
    // mismatched invitation (status still pending → invitationAuthorizesLink fails).
    await assertFails(
      setDoc(
        doc(asC(), 'users', C),
        { masterUserId: D, masterInvitationId: INV },
        { merge: true },
      ),
    );
  });

  await seed();
  await makeCcollaborator();
  await test('HAPPY: collaborator C reads master A’s transaction → allowed', async () => {
    await assertSucceeds(getDoc(doc(asC(), 'transactions', 'tx_A1')));
  });

  await seed();
  await makeCcollaborator();
  await test('ATTACK: stranger D reads master A’s transaction → denied', async () => {
    await assertFails(getDoc(doc(asD(), 'transactions', 'tx_A1')));
  });

  await seed();
  await makeCcollaborator();
  await test('HAPPY: collaborator C updates own displayName (masterUserId untouched) → allowed', async () => {
    await assertSucceeds(
      updateDoc(doc(asC(), 'users', C), { displayName: 'Carlos' }),
    );
  });

  await seed();
  await makeCcollaborator();
  await test('HAPPY: C leaves shared account (removes masterUserId + masterInvitationId) → allowed', async () => {
    await assertSucceeds(
      updateDoc(doc(asC(), 'users', C), {
        masterUserId: deleteField(),
        masterInvitationId: deleteField(),
      }),
    );
  });

  await seed();
  await makeCcollaborator();
  await test('HAPPY: master A detaches collaborator C (removes link fields on C’s doc) → allowed', async () => {
    await assertSucceeds(
      updateDoc(doc(asA(), 'users', C), {
        masterUserId: deleteField(),
        masterInvitationId: deleteField(),
      }),
    );
  });

  await seed();
  await makeCcollaborator();
  await test('ATTACK: collaborator C re-points own masterUserId to D while linked → denied', async () => {
    await assertFails(
      updateDoc(doc(asC(), 'users', C), { masterUserId: D }),
    );
  });

  await seed();
  await test('ATTACK: invitee C mutates inviteeEmail on the invitation → denied', async () => {
    await assertFails(
      updateDoc(doc(asC(), 'invitations', INV), { inviteeEmail: 'd@example.com' }),
    );
  });

  await seed();
  await makeCcollaborator();
  await test('HAPPY (B2): C declines own accepted invite on self-deletion → allowed', async () => {
    await assertSucceeds(
      updateDoc(doc(asC(), 'invitations', INV), { status: 'declined' }),
    );
  });

  await seed();
  await makeCcollaborator();
  await test('ATTACK: collaborator C deletes the master’s invitation doc → denied', async () => {
    await assertFails(deleteDoc(doc(asC(), 'invitations', INV)));
  });

  await seed();
  await test('HAPPY: callerEmail().lower() — mixed-case token email still matches invite', async () => {
    // C authenticates with 'Collab@Example.com'; invite stored 'collab@example.com'.
    await assertSucceeds(
      updateDoc(doc(asCUpper(), 'invitations', INV), {
        status: 'accepted',
        collaboratorUserId: C,
      }),
    );
  });

  console.log('\n── subscription validation ──');

  await seed();
  await test('HAPPY: legit annual write (366d, server ts) → allowed', async () => {
    await assertSucceeds(
      setDoc(doc(asA(), 'subscriptions', A), {
        type: 'annual',
        status: 'active',
        purchaseToken: 'a-real-long-jws-receipt-token-value',
        productId: 'pro_annual',
        expiryDate: days(366),
        updatedAt: serverTimestamp(),
      }),
    );
  });

  await seed();
  await test('HAPPY: empty purchaseToken on restore still allowed (B1 fix) → allowed', async () => {
    await assertSucceeds(
      setDoc(doc(asA(), 'subscriptions', A), {
        type: 'monthly',
        status: 'active',
        purchaseToken: '',
        productId: 'pro_monthly',
        expiryDate: days(32),
        updatedAt: serverTimestamp(),
      }),
    );
  });

  await seed();
  await test('HAPPY: clearSubscription (status=expired, merge) → allowed', async () => {
    await assertSucceeds(
      setDoc(
        doc(asA(), 'subscriptions', A),
        { status: 'expired', updatedAt: serverTimestamp() },
        { merge: true },
      ),
    );
  });

  await seed();
  await test('ATTACK: perpetual Pro (expiryDate = now+10y) → denied', async () => {
    await assertFails(
      setDoc(doc(asA(), 'subscriptions', A), {
        type: 'annual',
        status: 'active',
        purchaseToken: 'x'.repeat(40),
        productId: 'pro_annual',
        expiryDate: days(3650),
        updatedAt: serverTimestamp(),
      }),
    );
  });

  await seed();
  await test('ATTACK: junk extra field in subscription → denied', async () => {
    await assertFails(
      setDoc(doc(asA(), 'subscriptions', A), {
        type: 'annual',
        status: 'active',
        purchaseToken: 'x'.repeat(40),
        productId: 'pro_annual',
        expiryDate: days(366),
        updatedAt: serverTimestamp(),
        hacked: true,
      }),
    );
  });

  await seed();
  await test('ATTACK: unknown productId → denied', async () => {
    await assertFails(
      setDoc(doc(asA(), 'subscriptions', A), {
        type: 'annual',
        status: 'active',
        purchaseToken: 'x'.repeat(40),
        productId: 'pirate_lifetime',
        expiryDate: days(366),
        updatedAt: serverTimestamp(),
      }),
    );
  });

  await seed();
  await test('ATTACK: client-set updatedAt (not server time) → denied', async () => {
    await assertFails(
      setDoc(doc(asA(), 'subscriptions', A), {
        type: 'annual',
        status: 'active',
        purchaseToken: 'x'.repeat(40),
        productId: 'pro_annual',
        expiryDate: days(366),
        updatedAt: Timestamp.fromMillis(Date.now() - 1000),
      }),
    );
  });

  await seed();
  await test('ATTACK: write to ANOTHER user’s subscription doc → denied', async () => {
    await assertFails(
      setDoc(doc(asD(), 'subscriptions', A), {
        type: 'annual',
        status: 'active',
        purchaseToken: 'x'.repeat(40),
        productId: 'pro_annual',
        expiryDate: days(366),
        updatedAt: serverTimestamp(),
      }),
    );
  });

  await seed();
  await test('KNOWN RESIDUAL RISK: forged ~399d Pro with padded token is bounded-but-allowed', async () => {
    // Documents the accepted limitation: closing this needs server-side receipt
    // validation (Cloud Function). The rule only CAPS the damage to <400d.
    await assertSucceeds(
      setDoc(doc(asA(), 'subscriptions', A), {
        type: 'annual',
        status: 'active',
        purchaseToken: 'x'.repeat(21),
        productId: 'pro_annual',
        expiryDate: days(399),
        updatedAt: serverTimestamp(),
      }),
    );
  });

  console.log('\n── account deletion (owner wipes own data) ──');

  await seed();
  await test('HAPPY: owner deletes own transaction → allowed', async () => {
    await assertSucceeds(deleteDoc(doc(asA(), 'transactions', 'tx_A1')));
  });

  await seed();
  await test('HAPPY: owner deletes own subscription + user doc → allowed', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'subscriptions', A), { status: 'expired' });
    });
    await assertSucceeds(deleteDoc(doc(asA(), 'subscriptions', A)));
    await assertSucceeds(deleteDoc(doc(asA(), 'users', A)));
  });

  console.log('\n── Holding: sócios (quem é dono de quanto) ──');

  await seedHolding();
  await test('HAPPY: viewer V reads a sócio of the Holding → allowed', async () => {
    await assertSucceeds(getDoc(doc(asV(), 'holding_members', M1)));
  });

  await seedHolding();
  await test('ATTACK: non-member D reads a sócio → denied', async () => {
    await assertFails(getDoc(doc(asD(), 'holding_members', M1)));
  });

  await seedHolding();
  await test('ATTACK: non-member D reads an aporte → denied', async () => {
    await assertFails(getDoc(doc(asD(), 'holding_contributions', HC1)));
  });

  await seedHolding();
  await test('HAPPY: owner A creates a sócio → allowed', async () => {
    await assertSucceeds(
      setDoc(doc(asA(), 'holding_members', 'hm_novo'), socio({ name: 'Bia' })),
    );
  });

  await seedHolding();
  await test('ATTACK: editor C creates a sócio → denied (cap table is owner-only)', async () => {
    await assertFails(
      setDoc(doc(asC(), 'holding_members', 'hm_c'), socio({ name: 'C' })),
    );
  });

  await seedHolding();
  await test('ATTACK: editor C enlarges a sócio’s quota → denied', async () => {
    await assertFails(
      updateDoc(doc(asC(), 'holding_members', M1), { quotaBps: 9000 }),
    );
  });

  await seedHolding();
  await test('ATTACK: quotaBps above 100% (12000 bps) → denied', async () => {
    await assertFails(
      updateDoc(doc(asA(), 'holding_members', M1), { quotaBps: 12000 }),
    );
  });

  await seedHolding();
  await test('ATTACK: quotaBps as a float (50.5) → denied', async () => {
    await assertFails(
      updateDoc(doc(asA(), 'holding_members', M1), { quotaBps: 50.5 }),
    );
  });

  await seedHolding();
  await test('ATTACK: sócio with an empty name → denied', async () => {
    await assertFails(
      updateDoc(doc(asA(), 'holding_members', M1), { name: '' }),
    );
  });

  await seedHolding();
  await test('HAPPY: owner A renames a sócio → allowed', async () => {
    await assertSucceeds(
      updateDoc(doc(asA(), 'holding_members', M1), { name: 'Alexandre' }),
    );
  });

  await seedHolding();
  await test('ATTACK: owner moves a sócio to another Carteira → denied', async () => {
    await assertFails(
      updateDoc(doc(asA(), 'holding_members', M1), { workspaceId: WS_PF }),
    );
  });

  await seedHolding();
  await test('ATTACK: editor C deletes a sócio → denied', async () => {
    await assertFails(deleteDoc(doc(asC(), 'holding_members', M1)));
  });

  await seedHolding();
  await test('HAPPY: owner A deletes a sócio → allowed', async () => {
    await assertSucceeds(deleteDoc(doc(asA(), 'holding_members', M1)));
  });

  console.log('\n── Holding: aportes (trilha do dinheiro, append-only) ──');

  await seedHolding();
  await test('HAPPY: editor C records their own aporte → allowed', async () => {
    await assertSucceeds(
      setDoc(doc(asC(), 'holding_contributions', 'hc_c'), aporte(C)),
    );
  });

  await seedHolding();
  await test('ATTACK: viewer V records an aporte → denied', async () => {
    await assertFails(
      setDoc(doc(asV(), 'holding_contributions', 'hc_v'), aporte(V)),
    );
  });

  await seedHolding();
  await test('ATTACK: non-member D records an aporte in the Holding → denied', async () => {
    await assertFails(
      setDoc(doc(asD(), 'holding_contributions', 'hc_d'), aporte(D)),
    );
  });

  await seedHolding();
  await test('ATTACK: aporte with a forged createdBy (C claims A recorded it) → denied', async () => {
    await assertFails(
      setDoc(doc(asC(), 'holding_contributions', 'hc_forged'), aporte(A)),
    );
  });

  await seedHolding();
  await test('ATTACK: aporte of zero → denied', async () => {
    await assertFails(
      setDoc(
        doc(asC(), 'holding_contributions', 'hc_zero'),
        aporte(C, { amountCents: 0 }),
      ),
    );
  });

  await seedHolding();
  await test('ATTACK: aporte above kMaxCents (1e11) → denied', async () => {
    await assertFails(
      setDoc(
        doc(asC(), 'holding_contributions', 'hc_huge'),
        aporte(C, { amountCents: 100000000000 }),
      ),
    );
  });

  await seedHolding();
  await test('ATTACK: aporte with fractional centavos (float) → denied', async () => {
    await assertFails(
      setDoc(
        doc(asC(), 'holding_contributions', 'hc_float'),
        aporte(C, { amountCents: 1000.5 }),
      ),
    );
  });

  await seedHolding();
  await test('HAPPY: retirada (negative amount) → allowed', async () => {
    await assertSucceeds(
      setDoc(
        doc(asC(), 'holding_contributions', 'hc_neg'),
        aporte(C, { amountCents: -250000 }),
      ),
    );
  });

  await seedHolding();
  await test('ATTACK: aporte pointing at a sócio of ANOTHER Carteira → denied', async () => {
    await assertFails(
      setDoc(
        doc(asC(), 'holding_contributions', 'hc_cross'),
        aporte(C, { memberId: M_OTHER }),
      ),
    );
  });

  await seedHolding();
  await test('ATTACK: aporte pointing at a sócio that does not exist → denied', async () => {
    await assertFails(
      setDoc(
        doc(asC(), 'holding_contributions', 'hc_ghost'),
        aporte(C, { memberId: 'hm_inexistente' }),
      ),
    );
  });

  await seedHolding();
  await test('HAPPY: new sócio + first aporte in the SAME batch (getAfter) → allowed', async () => {
    const db = asA();
    const batch = writeBatch(db);
    batch.set(doc(db, 'holding_members', 'hm_batch'), socio({ name: 'Novo' }));
    batch.set(
      doc(db, 'holding_contributions', 'hc_batch'),
      aporte(A, { memberId: 'hm_batch' }),
    );
    await assertSucceeds(batch.commit());
  });

  await seedHolding();
  await test('ATTACK: owner A rewrites amountCents after creation → denied', async () => {
    await assertFails(
      updateDoc(doc(asA(), 'holding_contributions', HC1), { amountCents: 1 }),
    );
  });

  await seedHolding();
  await test('ATTACK: editor C rewrites amountCents after creation → denied', async () => {
    await assertFails(
      updateDoc(doc(asC(), 'holding_contributions', HC1), { amountCents: 1 }),
    );
  });

  await seedHolding();
  await test('ATTACK: aporte re-pointed at another sócio after creation → denied', async () => {
    await assertFails(
      updateDoc(doc(asC(), 'holding_contributions', HC1), { memberId: M_OTHER }),
    );
  });

  await seedHolding();
  await test('HAPPY: editor C fixes only the note → allowed', async () => {
    await assertSucceeds(
      updateDoc(doc(asC(), 'holding_contributions', HC1), {
        note: 'entrada do apartamento',
      }),
    );
  });

  await seedHolding();
  await test('ATTACK: editor C deletes an aporte → denied', async () => {
    await assertFails(deleteDoc(doc(asC(), 'holding_contributions', HC1)));
  });

  await seedHolding();
  await test('HAPPY: owner A deletes an aporte (cascade / LGPD) → allowed', async () => {
    await assertSucceeds(deleteDoc(doc(asA(), 'holding_contributions', HC1)));
  });

  console.log('\n── Carteira: tipo válido, tipo imutável, regressões ──');

  await seedHolding();
  await test('ATTACK: Carteira created with an unknown type → denied', async () => {
    await assertFails(
      setDoc(doc(asA(), 'workspaces', 'ws_novo'), {
        ownerId: A,
        name: 'Pirata',
        type: 'pirate',
        memberUids: [A],
        roles: { [A]: 'editor' },
        createdAt: serverTimestamp(),
      }),
    );
  });

  await seedHolding();
  await test('ATTACK: Holding flipped to personal (would strand its sócios) → denied', async () => {
    await assertFails(
      updateDoc(doc(asA(), 'workspaces', WS_H), { type: 'personal' }),
    );
  });

  await seedHolding();
  await test('ATTACK: unknown holdingQuotaMode → denied', async () => {
    await assertFails(
      updateDoc(doc(asA(), 'workspaces', WS_H), { holdingQuotaMode: 'whatever' }),
    );
  });

  await seedHolding();
  await test('HAPPY: owner switches the Holding to fixed quotas → allowed', async () => {
    await assertSucceeds(
      updateDoc(doc(asA(), 'workspaces', WS_H), { holdingQuotaMode: 'fixed' }),
    );
  });

  await seedHolding();
  await test('REGRESSION: rename a Carteira still works', async () => {
    await assertSucceeds(
      updateDoc(doc(asA(), 'workspaces', WS_H), { name: 'Holding Silva' }),
    );
  });

  await seedHolding();
  await test('REGRESSION: archive a Carteira still works', async () => {
    await assertSucceeds(
      updateDoc(doc(asA(), 'workspaces', WS_H), { archived: true }),
    );
  });

  await seedHolding();
  await test('REGRESSION: removeCollaborator (memberUids + roles key) still works', async () => {
    await assertSucceeds(
      updateDoc(doc(asA(), 'workspaces', WS_H), {
        memberUids: arrayRemove(C),
        [`roles.${C}`]: deleteField(),
      }),
    );
  });

  console.log('\n── transactions: rateio congelado só dentro de Holding ──');

  await seedHolding();
  await test('HAPPY: transaction with holdingSplit inside the Holding → allowed', async () => {
    await assertSucceeds(
      setDoc(doc(asA(), 'transactions', 'tx_h'), {
        userId: A,
        workspaceId: WS_H,
        title: 'Condomínio',
        amount: 1200,
        holdingSplit: { [M1]: 60000, hm_outro: 60000 },
        holdingPaidBy: M1,
      }),
    );
  });

  await seedHolding();
  await test('ATTACK: holdingSplit injected into a PF Carteira → denied', async () => {
    await assertFails(
      setDoc(doc(asA(), 'transactions', 'tx_pf_split'), {
        userId: A,
        workspaceId: WS_PF,
        title: 'Mercado',
        amount: 200,
        holdingSplit: { [M1]: 20000 },
      }),
    );
  });

  await seedHolding();
  await test('ATTACK: holdingSplit on a legacy (Carteira-less) transaction → denied', async () => {
    await assertFails(
      setDoc(doc(asA(), 'transactions', 'tx_legacy_split'), {
        userId: A,
        title: 'Antiga',
        amount: 50,
        holdingSplit: { [M1]: 5000 },
      }),
    );
  });

  await seedHolding();
  await test('REGRESSION: ordinary transaction in a PF Carteira still allowed', async () => {
    await assertSucceeds(
      setDoc(doc(asA(), 'transactions', 'tx_pf'), {
        userId: A,
        workspaceId: WS_PF,
        title: 'Mercado',
        amount: 200,
      }),
    );
  });

  await env.cleanup();

  console.log(`\n${'─'.repeat(48)}`);
  console.log(`RESULT: ${passed} passed, ${failed} failed`);
  if (failed > 0) {
    console.log('\nFAILURES:');
    for (const f of failures) console.log(`  • ${f.name}\n    ${f.error}`);
    process.exit(1);
  }
  console.log('All security rule tests passed ✅');
}

main().catch((e) => {
  console.error('FATAL', e);
  process.exit(2);
});
