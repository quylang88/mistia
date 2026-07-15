# Credit Card Transaction-Only Debt Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove credit-card opening debt from Mistia so current debt and available credit are derived only from active posted transactions, consistently in owner, family-member, editor, and Supabase paths.

**Architecture:** Keep the shared `openingBalanceMinor` storage field for non-card wallets, but give `TransactionWalletSnapshot` a kind-aware seed that is always zero for credit cards. Remove every credit-card editor path that reads, derives, or writes opening debt, while retaining calculated read-only available credit. Replace the existing Supabase balance function through a forward migration and verify it with a real pgTAP database test.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, XCTest/Swift Testing through Swift Package Manager and Xcode, PostgreSQL, Supabase CLI 2.109.0, pgTAP.

## Global Constraints

- Do not reset, null, or bulk-rewrite existing credit-card `openingBalanceMinor` values.
- Credit-card balance seed is zero; cash, bank, and every other non-card wallet retain their existing opening-balance behavior.
- Available credit remains `max(credit limit - transaction-backed debt, 0)` and remains visible only as calculated data.
- Creating or editing a credit card must not expose an available-credit/open-debt input and must not assign `openingBalanceMinor`.
- A statement remains paid only when a valid payment transaction proves it; this change must not synthesize payments or alter payment matching.
- Do not broaden family permissions or change RLS.
- Do not add user-facing copy. Touch the String Catalog only if an existing key becomes globally unused.
- Create the SQL migration with `supabase migration new credit_card_transaction_only_debt`; do not invent its timestamp manually.
- Execute implementation in an isolated `codex/credit-card-transaction-only-debt` worktree, then merge into `develop` and remove the worktree.

---

### Task 1: Make local credit-card debt transaction-only

**Files:**
- Modify: `Tests/MistiaCoreLogicTests/TransactionLogicTests.swift`
- Modify: `MistiaTests/CreditCardAvailableCreditTests.swift`
- Modify: `MistiaTests/PlanningDuePaymentPersistenceTests.swift`
- Modify: `Tests/MistiaCoreLogicTests/FamilyOverviewCalculatorTests.swift`
- Modify: `Mistia/Shared/CoreLogic/FinanceEnums.swift`
- Modify: `Mistia/Shared/CoreLogic/TransactionLogic.swift`
- Modify: `Mistia/Features/Management/ManagementEditors.swift`
- Modify: `Mistia/Features/Management/ManagementView.swift`
- Modify: `Mistia/Features/Planning/PlanningEditors.swift`

**Interfaces:**
- Consumes: `TransactionWalletSnapshot`, `TransactionWalletBalanceIndex`, `TransactionLogic.walletBalanceIndex`, `LedgerWalletKind`, existing transaction delta rules.
- Produces: `TransactionWalletSnapshot.balanceSeedMinor: Int64` and `LedgerWalletKind.usesOpeningBalance: Bool`; all local card consumers receive transaction-only debt.

- [ ] **Step 1: Write the failing core regressions**

Add focused tests to `TransactionLogicTests.swift` before changing production code:

```swift
func testCreditCardBalanceIgnoresStoredOpeningDebtAndUsesRealPayments() {
    let card = TransactionWalletSnapshot(
        id: UUID(),
        kind: .creditCard,
        openingBalanceMinor: 46_058
    )
    let occurredAt = Date(timeIntervalSince1970: 1_783_728_000)
    let records = [
        makeRecord(
            primaryKind: .expense,
            amountMinor: 70_214,
            occurredAt: occurredAt,
            sourceWalletID: card.id,
            sourceWalletKind: .creditCard
        ),
        makeRecord(
            primaryKind: .transfer,
            transferSubtype: .internalTransfer,
            amountMinor: 44_298,
            occurredAt: occurredAt.addingTimeInterval(60),
            destinationWalletID: card.id,
            destinationWalletKind: .creditCard
        )
    ]

    let index = TransactionLogic.walletBalanceIndex(wallets: [card], records: records)
    let balance = TransactionLogic.creditCardBalance(
        creditLimitMinor: 350_000,
        wallet: card,
        balanceIndex: index
    )

    XCTAssertEqual(index.balance(for: card), 25_916)
    XCTAssertEqual(balance.currentDebtMinor, 25_916)
    XCTAssertEqual(balance.availableCreditMinor, 324_084)
}

func testBalanceSeedAndMissingIndexFallbackIgnoreOnlyCardOpeningBalance() {
    let card = TransactionWalletSnapshot(id: UUID(), kind: .creditCard, openingBalanceMinor: 46_058)
    let bank = TransactionWalletSnapshot(id: UUID(), kind: .bank, openingBalanceMinor: 46_058)
    let emptyIndex = TransactionWalletBalanceIndex(balancesByWalletID: [:])

    XCTAssertEqual(TransactionLogic.effectiveBalance(for: card, records: []), 0)
    XCTAssertEqual(TransactionLogic.effectiveBalance(for: bank, records: []), 46_058)
    XCTAssertEqual(emptyIndex.balance(for: card), 0)
    XCTAssertEqual(emptyIndex.balance(for: bank), 46_058)
    XCTAssertFalse(LedgerWalletKind.creditCard.usesOpeningBalance)
    XCTAssertTrue(LedgerWalletKind.bank.usesOpeningBalance)
}
```

Update the existing mixed-wallet assertion from a card balance of `13_000` to `3_000`, and delete the obsolete `testCreditCardOpeningDebtPreservesCurrentDebtAfterLimitOnlyEdit` test because the helper it specifies will be removed.

- [ ] **Step 2: Write the failing app and Family regressions**

Change `CreditCardAvailableCreditTests.testPlanningSnapshotUsesLedgerDebtAndLatestLimit` to use `openingBalanceMinor: 46_058`, one real card expense of `25_916`, a `350_000` limit, and these assertions:

```swift
XCTAssertEqual(snapshot?.currentDebtMinor, 25_916)
XCTAssertEqual(snapshot?.availableCreditMinor, 324_084)
```

In `PlanningDuePaymentPersistenceTests`, replace the card's opening debt with a real posted expense before testing the exact available amount:

```swift
let card = LedgerWallet(
    name: "Credit card",
    kind: .creditCard,
    iconSymbolName: LedgerWalletKind.creditCard.defaultIconSymbolName,
    iconColorHex: LedgerWalletKind.creditCard.defaultColorHex
)
let purchase = LedgerTransaction(
    primaryKind: .expense,
    title: "Existing card purchase",
    amountMinor: 20_000,
    occurredAt: makeDate(year: 2026, month: 7, day: 1),
    sourceWallet: card
)
context.insert(purchase)
```

Add `testComputeIgnoresCreditCardOpeningDebtForFamilyMemberView` to `FamilyOverviewCalculatorTests`. Build one member-owned credit-card input with `openingBalanceMinor: 46_058`, limit `350_000`, and one posted expense transaction of `25_916`. Use a family owner different from the wallet owner and assert:

```swift
let cardRow = result.walletRows.first { $0.name == "Member Card" }
XCTAssertEqual(cardRow?.debtMinor, 25_916)
XCTAssertEqual(cardRow?.currentBalanceMinor, 324_084)
```

- [ ] **Step 3: Run the regressions and verify RED**

Run:

```bash
swift test --filter TransactionLogicTests/testCreditCardBalanceIgnoresStoredOpeningDebtAndUsesRealPayments
swift test --filter TransactionLogicTests/testBalanceSeedAndMissingIndexFallbackIgnoreOnlyCardOpeningBalance
swift test --filter FamilyOverviewCalculatorTests/testComputeIgnoresCreditCardOpeningDebtForFamilyMemberView
xcodebuild -project Mistia.xcodeproj -scheme Mistia -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' -only-testing:MistiaTests/CreditCardAvailableCreditTests test
```

Expected: each new behavior test fails because the current reducers still include `openingBalanceMinor` for cards or because `usesOpeningBalance` does not exist yet. If the named simulator is unavailable, select one concrete installed iOS simulator and record the substituted destination.

- [ ] **Step 4: Implement the kind-aware balance seed**

Add the semantic policy to `FinanceEnums.swift`:

```swift
var usesOpeningBalance: Bool {
    self != .creditCard
}
```

Add the seed to `TransactionWalletSnapshot`:

```swift
var balanceSeedMinor: Int64 {
    kind.usesOpeningBalance ? openingBalanceMinor : 0
}
```

Use `balanceSeedMinor` in all three balance entry points:

```swift
func balance(for wallet: TransactionWalletSnapshot) -> Int64 {
    balancesByWalletID[wallet.id] ?? wallet.balanceSeedMinor
}

var balance = wallet.balanceSeedMinor

for wallet in wallets {
    balancesByWalletID[wallet.id] = wallet.balanceSeedMinor
    kindByWalletID[wallet.id] = wallet.kind
}
```

Delete `TransactionLogic.creditCardOpeningDebtMinor` entirely.

- [ ] **Step 5: Remove Management open-debt input and writes**

In `ManagementEditors.swift`:

- Show the new-wallet opening input only when `draft.kind.usesOpeningBalance`; do not substitute an available-credit input for cards.
- Remove `availableCreditText`, `availableCreditMinor`, their initialization, and all limit/task synchronization blocks from `WalletDraft` and the view.
- In `performSave`, assign `existingWallet.openingBalanceMinor` only inside `if draft.kind.usesOpeningBalance`.
- Construct a new wallet without an opening-balance argument, then assign `newWallet.openingBalanceMinor = draft.openingBalanceMinor` only for kinds that use it.
- Delete the `creditCardOpeningDebtMinor` call and target-debt calculation.
- Simplify `ManagementBalanceAdjustmentSheet` to non-card balance adjustment: remove `creditLimit`, card titles/placeholders, disabled card fields, available-to-debt conversion, and card-specific income direction.

In `ManagementView.swift`, replace the raw missing-index fallback with the kind-aware seed:

```swift
let fallbackBalance = TransactionWalletSnapshot(
    id: wallet.id,
    kind: wallet.kind,
    openingBalanceMinor: wallet.openingBalanceMinor
).balanceSeedMinor
```

- [ ] **Step 6: Remove Planning open-debt input and writes**

In `PlanningEditors.swift`:

- Remove `availableCreditText` from `PlanningCreditCardDraft` and its initializer.
- Remove the available-credit field, limit-change hook, and task synchronization.
- Remove `paymentAmountText`, `initialPaymentAmountText`, `dismissBaselineDraft`, and unused `currentDueSnapshot` state/calculation from `PlanningCreditCardEditorSheet`.
- Remove the editor-local `storedTransactions` query and balance-index helpers when they have no remaining consumers.
- Parse only `creditLimitMinor` during save.
- Do not assign `wallet.openingBalanceMinor` when editing.
- Initialize a new credit-card wallet without an `openingBalanceMinor` argument.

Keep `storedOccurrences`, profile metadata, payment-source selection, and statement/payment logic unchanged.

- [ ] **Step 7: Verify GREEN and audit forbidden paths**

Run:

```bash
swift test --filter TransactionLogicTests
swift test --filter FamilyOverviewCalculatorTests
xcodebuild -project Mistia.xcodeproj -scheme Mistia -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' -only-testing:MistiaTests/CreditCardAvailableCreditTests -only-testing:MistiaTests/PlanningDuePaymentPersistenceTests test
! rg -n 'availableCreditText|creditCardOpeningDebtMinor' Mistia/Features/Management/ManagementEditors.swift Mistia/Features/Planning/PlanningEditors.swift Mistia/Shared/CoreLogic/TransactionLogic.swift
rg -n 'openingBalanceMinor\s*=' Mistia/Features/Management/ManagementEditors.swift Mistia/Features/Planning/PlanningEditors.swift
```

Expected: all focused tests pass; the forbidden-symbol search returns no matches; remaining assignments are guarded to non-card Management kinds and no Planning credit-card save assignment remains.

- [ ] **Step 8: Commit local behavior**

```bash
git add Tests/MistiaCoreLogicTests/TransactionLogicTests.swift Tests/MistiaCoreLogicTests/FamilyOverviewCalculatorTests.swift MistiaTests/CreditCardAvailableCreditTests.swift MistiaTests/PlanningDuePaymentPersistenceTests.swift Mistia/Shared/CoreLogic/FinanceEnums.swift Mistia/Shared/CoreLogic/TransactionLogic.swift Mistia/Features/Management/ManagementEditors.swift Mistia/Features/Management/ManagementView.swift Mistia/Features/Planning/PlanningEditors.swift
git diff --cached --check
git commit -m "fix: make credit card debt transaction-only"
```

---

### Task 2: Make the Supabase snapshot transaction-only

**Files:**
- Create: `supabase/tests/database/credit_card_transaction_only_debt.sql`
- Create via CLI: exact path printed under `supabase/migrations/` by `supabase migration new credit_card_transaction_only_debt`

**Interfaces:**
- Consumes: `public.mistia_calculate_wallet_current_balance(uuid, uuid, text, bigint)`, wallet/profile/transaction balance triggers.
- Produces: same function signature and grants, with a zero card seed and unchanged non-card seed; refreshed `ledger_wallets.current_balance_minor` snapshots.

- [ ] **Step 1: Write the failing pgTAP regression**

Create `supabase/tests/database/credit_card_transaction_only_debt.sql` with a transaction-scoped test fixture:

```sql
begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(4);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values (
  '20000000-0000-4000-8000-000000000001',
  'authenticated', 'authenticated', 'card-balance@mistia.test', '',
  timezone('utc'::text, now()),
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{}'::jsonb,
  timezone('utc'::text, now()), timezone('utc'::text, now())
)
on conflict (id) do nothing;

insert into public.ledger_wallets (
  id, user_id, name, kind_raw_value, icon_symbol_name, icon_color_hex,
  currency_code, opening_balance_minor
)
values (
  '20000000-0000-4000-8000-000000000002',
  '20000000-0000-4000-8000-000000000001',
  'Member Card', 'creditCard', 'creditcard', '#7C3AED', 'JPY', 46058
);

insert into public.credit_card_profiles (
  id, user_id, issuer_name, network_raw_value, last4, credit_limit_minor,
  statement_closing_day, payment_due_day, wallet_id
)
values (
  '20000000-0000-4000-8000-000000000003',
  '20000000-0000-4000-8000-000000000001',
  'Test', 'visa', '1234', 350000, 10, 26,
  '20000000-0000-4000-8000-000000000002'
);

insert into public.ledger_transactions (
  id, user_id, primary_kind_raw_value, entry_status_raw_value, title,
  amount_minor, occurred_at, source_wallet_id
)
values (
  '20000000-0000-4000-8000-000000000004',
  '20000000-0000-4000-8000-000000000001',
  'expense', 'posted', 'Real purchase', 25916,
  timezone('utc'::text, now()),
  '20000000-0000-4000-8000-000000000002'
);

select is(
  public.mistia_calculate_wallet_current_balance(
    '20000000-0000-4000-8000-000000000002',
    '20000000-0000-4000-8000-000000000001',
    'creditCard', 46058
  ),
  324084::bigint,
  'credit card available credit ignores stored opening debt'
);

select is(
  (select current_balance_minor from public.ledger_wallets where id = '20000000-0000-4000-8000-000000000002'),
  324084::bigint,
  'wallet snapshot trigger stores transaction-only available credit'
);

select is(
  (select opening_balance_minor from public.ledger_wallets where id = '20000000-0000-4000-8000-000000000002'),
  46058::bigint,
  'migration does not reset shared opening storage'
);

select is(
  public.mistia_calculate_wallet_current_balance(
    '20000000-0000-4000-8000-000000000099',
    '20000000-0000-4000-8000-000000000001',
    'bank', 46058
  ),
  46058::bigint,
  'non-card wallets retain opening balance'
);

select * from finish();
rollback;
```

- [ ] **Step 2: Run pgTAP and verify RED**

Run:

```bash
supabase start
supabase test db supabase/tests/database/credit_card_transaction_only_debt.sql --local
```

Expected: the card assertions fail because the current function still includes `opening_balance_minor`, producing available credit `278026` instead of `324084`.

- [ ] **Step 3: Generate and implement the migration**

Run:

```bash
supabase migration new credit_card_transaction_only_debt
```

In the exact generated file, replace `mistia_calculate_wallet_current_balance` with this complete definition:

```sql
create or replace function public.mistia_calculate_wallet_current_balance(
  p_wallet_id uuid,
  p_user_id uuid,
  p_wallet_kind text,
  p_opening_balance_minor bigint
)
returns bigint
language sql
stable
as $$
  with raw_balance as (
    select
      case when p_wallet_kind = 'creditCard' then 0 else p_opening_balance_minor end
      + coalesce(
        (
          select sum(
            case
              when tx.source_wallet_id = p_wallet_id then
                public.mistia_wallet_balance_delta(
                  p_wallet_kind,
                  tx.primary_kind_raw_value,
                  tx.transfer_subtype_raw_value,
                  tx.debt_intent_raw_value,
                  tx.amount_minor,
                  'source'
                )
              else 0
            end
            +
            case
              when tx.destination_wallet_id = p_wallet_id then
                public.mistia_wallet_balance_delta(
                  p_wallet_kind,
                  tx.primary_kind_raw_value,
                  tx.transfer_subtype_raw_value,
                  tx.debt_intent_raw_value,
                  tx.amount_minor,
                  'destination'
                )
              else 0
            end
          )
          from public.ledger_transactions tx
          where tx.user_id = p_user_id
            and tx.deleted_at is null
            and coalesce(tx.is_archived, false) = false
            and tx.entry_status_raw_value = 'posted'
            and (
              tx.source_wallet_id = p_wallet_id
              or tx.destination_wallet_id = p_wallet_id
            )
        ),
        0
      ) as balance_minor
  ),
  credit_profile as (
    select coalesce(profile.credit_limit_minor, 0) as credit_limit_minor
    from public.credit_card_profiles profile
    where profile.wallet_id = p_wallet_id
      and profile.user_id = p_user_id
      and profile.deleted_at is null
    order by profile.updated_at desc
    limit 1
  )
  select case
    when p_wallet_kind = 'creditCard' then
      greatest(
        coalesce((select credit_limit_minor from credit_profile), 0)
          - greatest((select balance_minor from raw_balance), 0),
        0
      )
    else
      (select balance_minor from raw_balance)
  end;
$$;
```

Keep the function signature, `language sql`, and `stable` property unchanged. End the migration with the full-wallet backfill:

```sql
update public.ledger_wallets wallet
set current_balance_minor = public.mistia_calculate_wallet_current_balance(
  wallet.id,
  wallet.user_id,
  wallet.kind_raw_value,
  wallet.opening_balance_minor
)
where wallet.current_balance_minor is distinct from public.mistia_calculate_wallet_current_balance(
  wallet.id,
  wallet.user_id,
  wallet.kind_raw_value,
  wallet.opening_balance_minor
);
```

Do not include any statement that assigns, nulls, or cleans up `opening_balance_minor` on card rows.

- [ ] **Step 4: Verify GREEN and migration integrity**

Run:

```bash
supabase db reset
supabase test db supabase/tests/database/credit_card_transaction_only_debt.sql --local
supabase migration list --local
git diff --check
```

Expected: pgTAP reports 4 passing assertions; reset applies all migrations; the new migration appears locally; diff check is clean.

- [ ] **Step 5: Commit cloud behavior**

```bash
git add supabase/migrations supabase/tests/database/credit_card_transaction_only_debt.sql
git diff --cached --check
git commit -m "fix: ignore card opening debt in cloud balance"
```

---

### Task 3: Full verification, merge, and cleanup

**Files:**
- Verify: all files changed in Tasks 1–2
- Verify unchanged unless globally dead: `Mistia/Localizable.xcstrings`
- Verify unchanged unless regenerated: `Mistia/Shared/CoreLogic/L10n.generated.swift`

**Interfaces:**
- Consumes: completed local and cloud implementations.
- Produces: verified commits merged into `develop`, with no remaining implementation worktree.

- [ ] **Step 1: Audit spec coverage and forbidden semantics**

Run:

```bash
rg -n 'creditCardOpeningDebtMinor|availableCreditText' Mistia Tests MistiaTests
rg -n 'openingBalanceMinor\s*=' Mistia/Features/Management/ManagementEditors.swift Mistia/Features/Planning/PlanningEditors.swift
rg -n 'opening_balance_minor\s*=\s*(0|null)|set\s+opening_balance_minor' supabase/migrations supabase/tests
git diff develop...HEAD --stat
git diff develop...HEAD --check
```

Expected: no obsolete card-opening helper/state; only guarded non-card editor assignment remains; no SQL reset; diff is clean.

- [ ] **Step 2: Run complete package and database tests**

Run serially:

```bash
swift test
supabase test db supabase/tests/database --local
```

Expected: all Swift package and pgTAP tests pass with zero failures.

- [ ] **Step 3: Run localization and app verification**

Run:

```bash
swift scripts/generate-l10n.swift --input Mistia/Localizable.xcstrings --output Mistia/Shared/CoreLogic/L10n.generated.swift --check --strict-keys
xcodebuild -project Mistia.xcodeproj -scheme Mistia -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' -only-testing:MistiaTests/CreditCardAvailableCreditTests -only-testing:MistiaTests/PlanningDuePaymentPersistenceTests test
xcodebuild -project Mistia.xcodeproj -scheme Mistia -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Run build and tests serially or with separate DerivedData paths to avoid `XCBuildData/build.db` locks. Expected: strict localization check, focused app tests, and unsigned iOS build all pass.

- [ ] **Step 4: Commit only if verification required a corrective change**

If verification exposed a defect, write or retain the failing regression first, make the minimal correction, rerun the failed command, then commit:

```bash
git add -u
git diff --cached --check
git commit -m "fix: complete transaction-only card debt"
```

If no correction was required, do not create an empty commit.

- [ ] **Step 5: Merge and remove the worktree**

From `/Users/quylang/Projects/mistia`:

```bash
git status --short --branch
git merge --no-ff codex/credit-card-transaction-only-debt -m "merge: make credit card debt transaction-only"
git worktree remove .worktrees/credit-card-transaction-only-debt
git branch -d codex/credit-card-transaction-only-debt
git status --short --branch
git log -5 --oneline
```

Expected: merge succeeds on `develop`, the worktree directory and feature branch are removed, and `develop` is clean.
