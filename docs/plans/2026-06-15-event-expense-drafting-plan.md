# Event Expense Drafting and Unlinking Implementation Plan

> **For Antigravity:** REQUIRED WORKFLOW: Use `.agent/workflows/execute-plan.md` to execute this plan in single-flow mode.

**Goal:** Implement in-memory drafting for linking and unlinking expenses in the event/shared expense editor, committing updates to the database only when the user saves the event.

**Architecture:** Track database-linked transaction IDs in two in-memory sets (`initialLinkedBillIDs` and `currentLinkedBillIDs`). Filter the displayed linked bills computed property using `currentLinkedBillIDs`, handle unlinking by removing from `currentLinkedBillIDs`, and atomically apply additions/deletions/group total recalculations in `saveSharedExpense()`.

**Tech Stack:** Swift, SwiftUI, SwiftData, Mistia CoreLogic.

---

### Task 1: Add State Variables for Linked Bill Tracking

**Files:**
- Modify: [SettlementSheets.swift](file:///Users/quylang/Projects/mistia/Mistia/Features/Transactions/SettlementSheets.swift#L120-L125)

**Step 1: Add `@State` variables**
Declare `currentLinkedBillIDs` and `initialLinkedBillIDs` inside `SettlementEditorSheet` struct:
```swift
    @State private var currentLinkedBillIDs: Set<UUID> = []
    @State private var initialLinkedBillIDs: Set<UUID> = []
```

**Step 2: Run compiler check**
Run: `swift build`
Expected: Compile successfully.

**Step 3: Commit**
```bash
git add Mistia/Features/Transactions/SettlementSheets.swift
git commit -m "feat: add current and initial linked bill IDs state to event editor"
```

---

### Task 2: Initialize State Variables in loadSharedExpenseDraftIfNeeded

**Files:**
- Modify: [SettlementSheets.swift](file:///Users/quylang/Projects/mistia/Mistia/Features/Transactions/SettlementSheets.swift#L822-L842)

**Step 1: Update draft loading logic**
Modify `loadSharedExpenseDraftIfNeeded()` to fetch DB-linked transactions and initialize the state sets first:
```swift
    private func loadSharedExpenseDraftIfNeeded() {
        hasLoadedSharedExpenseDraft = true
        guard case .editSharedExpense = target,
              let group = editingSharedExpenseGroup else {
            return
        }

        // Initialize linked bill IDs first
        let dbLinked = transactions.filter {
            $0.settlementGroupID == group.id
                && $0.settlementRole == .sharedExpensePaid
                && $0.deletedAt == nil
                && !$0.isArchived
        }
        let dbLinkedIDs = Set(dbLinked.map(\.id))
        initialLinkedBillIDs = dbLinkedIDs
        currentLinkedBillIDs = dbLinkedIDs

        eventTitle = group.title
        eventNote = group.note ?? ""
        let rows = settlementParticipants
            .filter { $0.groupID == group.id && !$0.isSelf && $0.deletedAt == nil }
            .sorted {
                if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
                return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
            .map { SharedExpenseParticipantDraft(id: $0.id, name: $0.displayName, paidText: "") }
        participantRows = rows.isEmpty ? [SharedExpenseParticipantDraft(name: "", paidText: "")] : rows
        selectedSharedWalletID = linkedSharedExpenseBills.first?.sourceWallet?.id ?? availableWallets.first?.id
        selectedSharedCategoryID = linkedSharedExpenseBills.first?.category?.id ?? expenseCategories.first?.id
        billRows = []
    }
```

**Step 2: Run compiler check**
Run: `swift build`
Expected: Compile successfully.

**Step 3: Commit**
```bash
git add Mistia/Features/Transactions/SettlementSheets.swift
git commit -m "feat: initialize initial and current linked bill IDs in loadSharedExpenseDraftIfNeeded"
```

---

### Task 3: Update linkedSharedExpenseBills Computed Property

**Files:**
- Modify: [SettlementSheets.swift](file:///Users/quylang/Projects/mistia/Mistia/Features/Transactions/SettlementSheets.swift#L206-L221)

**Step 1: Filter using currentLinkedBillIDs**
Update `linkedSharedExpenseBills` computed property to filter transactions matching IDs in `currentLinkedBillIDs`:
```swift
    private var linkedSharedExpenseBills: [LedgerTransaction] {
        transactions
            .filter {
                currentLinkedBillIDs.contains($0.id)
                    && $0.deletedAt == nil
                    && !$0.isArchived
            }
            .sorted {
                if $0.occurredAt != $1.occurredAt {
                    return $0.occurredAt > $1.occurredAt
                }
                return $0.updatedAt > $1.updatedAt
            }
    }
```

**Step 2: Run compiler check**
Run: `swift build`
Expected: Compile successfully.

**Step 3: Commit**
```bash
git add Mistia/Features/Transactions/SettlementSheets.swift
git commit -m "feat: filter linkedSharedExpenseBills using currentLinkedBillIDs"
```

---

### Task 4: Implement In-Memory Detach Swipe Action

**Files:**
- Modify: [SettlementSheets.swift](file:///Users/quylang/Projects/mistia/Mistia/Features/Transactions/SettlementSheets.swift#L644-L652)
- Add: `detachBillDraft(_:)` in [SettlementSheets.swift](file:///Users/quylang/Projects/mistia/Mistia/Features/Transactions/SettlementSheets.swift#L1233)

**Step 1: Add detachBillDraft**
Add `detachBillDraft` method right above/below `detachBill`:
```swift
    private func detachBillDraft(_ bill: LedgerTransaction) {
        currentLinkedBillIDs.remove(bill.id)
    }
```

**Step 2: Update swipe action in UI**
Change the swipe action on linked bills to call `detachBillDraft(bill)` instead of `detachBill(bill)`:
```swift
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        detachBillDraft(bill)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel(L10n.common.delete)
                }
```

**Step 3: Run compiler check**
Run: `swift build`
Expected: Compile successfully.

**Step 4: Commit**
```bash
git add Mistia/Features/Transactions/SettlementSheets.swift
git commit -m "feat: use in-memory detachBillDraft for swipe to delete action"
```

---

### Task 5: Atomic Save and Detach in saveSharedExpense()

**Files:**
- Modify: [SettlementSheets.swift](file:///Users/quylang/Projects/mistia/Mistia/Features/Transactions/SettlementSheets.swift#L1071-L1163)

**Step 1: Update saveSharedExpense to detach unlinked bills and save everything atomically**
Update the method to find all detached bills, reset their settlement attributes, calculate the correct event total from all active linked bills, and pass the combined list to `persistPreparedSharedExpense`:
```swift
    private func saveSharedExpense() {
        let title = eventTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            alertMessage = L10n.transactions.settlement.enterEventName
            return
        }
        let participantNames = normalizedParticipantNames()

        let now = Date()
        let ownerUserID = resolvedSharedExpenseOwnerUserID()
        let group: SettlementGroup
        let shouldDismissAfterSave: Bool

        switch target {
        case .newSharedExpense:
            group = SettlementGroup(
                kind: .sharedExpense,
                status: .preparing,
                title: title,
                currencyCode: activeCurrencyCode,
                occurredAt: now,
                totalMinor: 0,
                expectedMinor: 0,
                settledMinor: 0,
                organizerUserID: ownerUserID,
                note: eventNote.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank,
                createdAt: now,
                updatedAt: now
            )
            modelContext.insert(group)
            shouldDismissAfterSave = true
        case .editSharedExpense:
            guard let existingGroup = editingSharedExpenseGroup else {
                alertMessage = L10n.transactions.settlement.settlementNotFound
                return
            }
            group = existingGroup
            group.title = title
            group.currencyCode = activeCurrencyCode
            group.note = eventNote.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            group.updatedAt = now
            shouldDismissAfterSave = true
        }

        let participants = upsertPreparingParticipants(
            groupID: group.id,
            participantNames: participantNames,
            ownerUserID: ownerUserID,
            modifiedAt: now
        )

        // 1. Process detached bills (those in initial but not current)
        let detachedBillIDs = initialLinkedBillIDs.subtracting(currentLinkedBillIDs)
        var detachedBills: [LedgerTransaction] = []
        for billID in detachedBillIDs {
            if let bill = transactions.first(where: { $0.id == billID }) {
                let billOwnerUserID = bill.sourceWallet.flatMap { walletPickerAccess.walletOwnerUserID(for: $0) } ?? ownerUserID
                bill.settlementGroupID = nil
                bill.settlementObligationID = nil
                bill.settlementRoleRawValue = nil
                bill.reportingExpenseMinor = nil
                bill.reportingIncomeMinor = nil
                bill.updatedAt = now
                if let billOwnerUserID {
                    try? MistiaRecordOwnershipStore.upsert(
                        entity: .transaction,
                        recordID: bill.id,
                        ownerUserID: billOwnerUserID,
                        updatedAt: now,
                        context: modelContext
                    )
                }
                detachedBills.append(bill)
            }
        }

        // 2. Process newly added/linked bills
        var newlyCreatedTransactions: [LedgerTransaction] = []
        var newlyAttachedTransactions: [LedgerTransaction] = []

        for row in billRows {
            switch row.mode {
            case .newExpense:
                guard let transaction = makeSharedExpenseBillTransaction(from: row, groupID: group.id, defaultTitle: title, now: now) else {
                    continue
                }
                modelContext.insert(transaction)
                newlyCreatedTransactions.append(transaction)
            case .existingExpense:
                guard let existingID = row.existingTransactionID,
                      let transaction = attachableExpenseTransactions.first(where: { $0.id == existingID }) else {
                    continue
                }
                transaction.settlementGroupID = group.id
                transaction.settlementRole = .sharedExpensePaid
                transaction.reportingExpenseMinor = max(transaction.amountMinor, 0)
                transaction.reportingIncomeMinor = 0
                transaction.updatedAt = now
                newlyAttachedTransactions.append(transaction)
            }
        }

        // 3. Recalculate group total using all active linked bills
        let allLinkedBills = linkedSharedExpenseBills + newlyCreatedTransactions + newlyAttachedTransactions
        let linkedTotal = allLinkedBills.reduce(Int64(0)) { $0 + max($1.amountMinor, 0) }
        group.totalMinor = linkedTotal
        group.expectedMinor = 0
        group.settledMinor = 0
        group.status = .preparing
        group.updatedAt = now

        // 4. Save and register sync mutations
        persistPreparedSharedExpense(
            group: group,
            participants: participants,
            transactions: newlyCreatedTransactions + newlyAttachedTransactions + detachedBills,
            ownerUserID: ownerUserID,
            modifiedAt: now,
            dismissAfterSave: shouldDismissAfterSave
        )
    }
```

**Step 2: Run compiler check**
Run: `swift build`
Expected: Compile successfully.

**Step 3: Run core logic tests**
Run: `swift test`
Expected: All tests pass.

**Step 4: Commit**
```bash
git add Mistia/Features/Transactions/SettlementSheets.swift
git commit -m "feat: atomically persist detached bills and calculate correct total minor in saveSharedExpense"
```
