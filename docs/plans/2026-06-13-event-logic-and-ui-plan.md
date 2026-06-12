# Event Logic and UI Improvements Implementation Plan

> **For Antigravity:** REQUIRED WORKFLOW: Use `.agent/workflows/execute-plan.md` to execute this plan in single-flow mode.

**Goal:** Implement improvements to event cost sharing status tracking, prevent event disappearance, filter completed events, lock fully settled nợ/loans from editing, and standardize notifications empty state.

**Architecture:** Use SwiftData/SwiftUI queries. Modify core model filters, add event-based segmentation mapping to `TransactionSegment`, construct settlement progress calculation for participants, and lock edit states on completed payments in nợ sheets.

**Tech Stack:** Swift, SwiftUI, SwiftData, Mistia CoreLogic.

---

### Task 1: Update Ongoing Event Logic Filter
**Files:**
- Modify: `Mistia/Shared/CoreLogic/TransactionLogic.swift:446-449`

**Step 1: Write implementation**
Modify the filter in `preparingEventSnapshots` to include groups that are not `.settled`:
```swift
        return groups
            .filter { $0.kind == .sharedExpense && $0.status != .settled && !$0.isArchived }
```

**Step 2: Commit**
```bash
git add Mistia/Shared/CoreLogic/TransactionLogic.swift
git commit -m "feat: include non-settled groups in ongoing event snapshots"
```

---

### Task 2: Implement allEventSnapshots Method
**Files:**
- Modify: `Mistia/Shared/CoreLogic/TransactionLogic.swift` (add after `preparingEventSnapshots`)

**Step 1: Write implementation**
Implement `allEventSnapshots` in `SettlementLogic` namespace to fetch both ongoing and completed events:
```swift
    static func allEventSnapshots(
        groups: [SettlementGroupRecordSnapshot],
        participants: [SettlementParticipantRecordSnapshot],
        records: [TransactionRecordSnapshot]
    ) -> [PreparingSettlementEventSnapshot] {
        let participantsByGroupID = Dictionary(grouping: participants) { $0.groupID }
        let recordsByGroupID = Dictionary(
            grouping: records.filter(isSharedExpenseEventBill)
        ) { record in
            record.settlementGroupID ?? UUID()
        }

        return groups
            .filter { $0.kind == .sharedExpense && !$0.isArchived }
            .map { group in
                let groupParticipants = participantsByGroupID[group.id] ?? []
                let visibleParticipantNames = groupParticipants
                    .filter { !$0.isSelf }
                    .sorted(by: participantSort)
                    .map(\.displayName)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                let billRecords = recordsByGroupID[group.id] ?? []
                let totalPaid = billRecords.reduce(Int64.zero) { total, record in
                    total + max(record.amountMinor, 0)
                }
                let latestRecordDate = billRecords.map(\.occurredAt).max()
                let latestParticipantDate = groupParticipants.map(\.updatedAt).max()
                let lastUpdatedAt = [
                    group.updatedAt,
                    latestRecordDate,
                    latestParticipantDate
                ]
                    .compactMap { $0 }
                    .max() ?? group.updatedAt

                return PreparingSettlementEventSnapshot(
                    id: group.id,
                    title: group.title,
                    currencyCode: group.currencyCode,
                    totalPaidMinor: totalPaid,
                    billCount: billRecords.count,
                    participantNames: visibleParticipantNames,
                    note: group.note,
                    occurredAt: group.occurredAt,
                    lastUpdatedAt: lastUpdatedAt
                )
            }
    }
```

**Step 2: Commit**
```bash
git add Mistia/Shared/CoreLogic/TransactionLogic.swift
git commit -m "feat: implement allEventSnapshots helper"
```

---

### Task 3: Support isEventOnly Filter in TransactionFilterState
**Files:**
- Modify: `Mistia/Shared/CoreLogic/TransactionLogic.swift:199-209`, `Mistia/Shared/CoreLogic/TransactionLogic.swift:1519-1580`

**Step 1: Write implementation**
Add `isEventOnly` to `TransactionFilterState`:
```swift
struct TransactionFilterState: Equatable {
    var isAdjustmentOnly: Bool = false
    var isEventOnly: Bool = false
    ...
}
```
And update the matching logic in `matches`:
```swift
        if filters.isEventOnly {
            guard record.settlementGroupID != nil else { return false }
        }
```

**Step 2: Commit**
```bash
git add Mistia/Shared/CoreLogic/TransactionLogic.swift
git commit -m "feat: add isEventOnly to TransactionFilterState"
```

---

### Task 4: Add Event Segment to TransactionSegment
**Files:**
- Modify: `Mistia/Features/Transactions/TransactionsView.swift:4-40`, `Mistia/Features/Transactions/TransactionsView.swift:777-781`

**Step 1: Write implementation**
Add `.event` case to `TransactionSegment`:
```swift
private enum TransactionSegment: String, CaseIterable, Hashable {
    case expense
    case income
    case transfer
    case event
    case adjustment

    var title: String {
        switch self {
        case .expense:
            return L10n.transactions.transactions.expense2
        case .income:
            return L10n.transactions.transactions.income2
        case .transfer:
            return L10n.transactions.transactions.transfer
        case .event:
            return "Sự kiện"
        case .adjustment:
            return L10n.transactions.transactions.adjustment
        }
    }

    var tint: Color {
        MistiaAccent.purple.color
    }

    var kind: TransactionPrimaryKind? {
        switch self {
        case .expense:
            return .expense
        case .income:
            return .income
        case .transfer:
            return .transfer
        case .event, .adjustment:
            return nil
        }
    }
}
```
And update `effectiveFilters`:
```swift
    private var effectiveFilters: TransactionFilterState {
        var effective = filterState
        effective.isAdjustmentOnly = selectedSegment == .adjustment
        effective.isEventOnly = selectedSegment == .event
        return effective
    }
```

**Step 2: Commit**
```bash
git add Mistia/Features/Transactions/TransactionsView.swift
git commit -m "feat: add event segment to TransactionSegment"
```

---

### Task 5: Render Event List when Event Segment Selected
**Files:**
- Modify: `Mistia/Features/Transactions/TransactionsView.swift` (add `EventCashflowRow` view, update `body` list content)

**Step 1: Write implementation**
Define `EventCashflowRow` at the end of the file:
```swift
private struct EventCashflowRow: View {
    let event: PreparingSettlementEventSnapshot

    private var participantText: String {
        if event.participantNames.isEmpty {
            return L10n.transactions.settlement.noParticipantsYet
        }
        return event.participantNames.joined(separator: ", ")
    }

    var body: some View {
        HStack(spacing: 12) {
            TransactionIconTile(
                icon: "mistia.settlement.event",
                tint: MistiaAccent.purple.color
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(participantText)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(L10n.transactions.settlement.billCountValue(String(event.billCount)))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)

            Text(event.totalPaidMinor.formattedCurrency(code: event.currencyCode))
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(MistiaAccent.expense.color)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .contentShape(Rectangle())
    }
}
```
Add the computed property `allEvents`:
```swift
    private var allEvents: [PreparingSettlementEventSnapshot] {
        SettlementLogic.allEventSnapshots(
            groups: visibleSettlementGroups.map(\.recordSnapshot),
            participants: visibleSettlementParticipants.map(\.recordSnapshot),
            records: activeTransactions.map(\.snapshot)
        )
        .sorted { $0.occurredAt > $1.occurredAt }
    }
```
And conditionally render the event list in `body` of `TransactionsView` (under `MistiaPinnedTopBarScaffold` block):
```swift
                    if selectedSegment == .event {
                        let events = allEvents
                        if events.isEmpty {
                            MistiaEmptyStateContent(
                                title: "Chưa có sự kiện nào",
                                message: "Các sự kiện chia chi phí sẽ xuất hiện ở đây.",
                                buttonTitle: nil,
                                accent: MistiaAccent.purple.color,
                                symbols: ["calendar", "person.2.fill"]
                            )
                            .padding(.top, 40)
                        } else {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Sự kiện chia chi phí")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)
                                    .tracking(0.6)
                                    .padding(.horizontal, 2)
                                
                                MistiaBlockCard(
                                    cornerRadius: 22,
                                    tint: Color(UIColor.secondarySystemGroupedBackground),
                                    padding: 0
                                ) {
                                    VStack(spacing: 0) {
                                        ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                                            Button {
                                                preparingSettlementTarget = PreparingSettlementEventSheetTarget(groupID: event.id)
                                            } label: {
                                                EventCashflowRow(event: event)
                                                    .padding(.horizontal, 14)
                                                    .padding(.vertical, 12)
                                            }
                                            .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 18))
                                            
                                            if index < events.count - 1 {
                                                Divider()
                                                    .padding(.leading, 52)
                                                    .padding(.trailing, 0)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    } else {
                        if !preparingSettlementEvents.isEmpty {
                            preparingSettlementSection(preparingSettlementEvents)
                        }
                        if !listSnapshot.openDebtPositions.isEmpty {
                            outstandingDebtSection(
                                listSnapshot.openDebtPositions,
                                receivableTotals: listSnapshot.openReceivableDebtTotals
                            )
                        }
                        if !openSettlementItems.isEmpty {
                            openSettlementSection(openSettlementItems)
                        }
                        transactionsContent(listSnapshot, exchangeRateIndex: exchangeRateIndex)
                    }
```
Hide the category filter menu chip when selected segment is `.event`:
```swift
            if selectedSegment?.kind != .transfer && selectedSegment != .adjustment && selectedSegment != .event {
```

**Step 2: Commit**
```bash
git add Mistia/Features/Transactions/TransactionsView.swift
git commit -m "feat: render event list for event segment in TransactionsView"
```

---

### Task 6: Implement Participant Settlement Progress in Calculator Sheet
**Files:**
- Modify: `Mistia/Features/Transactions/SettlementSheets.swift` (Update `SettlementSplitCalculatorSheet` logic & views)

**Step 1: Write implementation**
Define `ParticipantSettlementProgress` struct and `ParticipantSettlementProgressRow` inside `SettlementSheets.swift`:
```swift
struct ParticipantSettlementProgress: Identifiable {
    let id: UUID
    let displayName: String
    let normalizedKey: String
    let hasDebt: Bool
    let isReceivable: Bool
    let originalAmount: Int64
    let paidAmount: Int64
    let remainingAmount: Int64
    let isSettled: Bool
}

private struct ParticipantSettlementProgressRow: View {
    let progress: ParticipantSettlementProgress
    let currencyCode: String
    
    private var isReceivable: Bool {
        progress.isReceivable
    }
    
    private var amountColor: Color {
        if !progress.hasDebt || progress.isSettled {
            return MistiaAccent.income.color
        }
        return isReceivable ? MistiaAccent.debtLend.color : MistiaAccent.debtBorrow.color
    }
    
    private var icon: String {
        if !progress.hasDebt || progress.isSettled {
            return "checkmark.circle.fill"
        }
        return isReceivable ? TransactionDebtIntent.lend.financeIconToken : TransactionDebtIntent.borrow.financeIconToken
    }
    
    private var title: String {
        progress.displayName
    }
    
    private var subtitle: String {
        if !progress.hasDebt {
            return "Đã thanh toán xong (Không có nợ)"
        }
        if progress.isSettled {
            return "Đã thanh toán xong"
        }
        
        let paidFormatted = progress.paidAmount.formattedCurrency(code: currencyCode)
        let remainingFormatted = progress.remainingAmount.formattedCurrency(code: currencyCode)
        
        if isReceivable {
            return "Đã trả: \(paidFormatted) • Còn lại: \(remainingFormatted)"
        } else {
            return "Bạn đã trả: \(paidFormatted) • Còn lại: \(remainingFormatted)"
        }
    }
    
    private var amountText: String {
        if !progress.hasDebt || progress.isSettled {
            return "Đã xong"
        }
        let remainingFormatted = progress.remainingAmount.formattedCurrency(code: currencyCode)
        return isReceivable ? "+\(remainingFormatted)" : "-\(remainingFormatted)"
    }
    
    var body: some View {
        HStack(spacing: 12) {
            MistiaFinanceIconView(
                icon: icon,
                fallbackColor: amountColor,
                size: 36
            )
            
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer(minLength: 12)
            
            Text(amountText)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(amountColor)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .contentShape(Rectangle())
    }
}
```

Add helper properties/methods inside `SettlementSplitCalculatorSheet`:
```swift
    private var isFinalized: Bool {
        if let status = group?.status {
            return status == .open || status == .partiallySettled || status == .settled
        }
        return false
    }

    private func participantSettlementProgressList() -> [ParticipantSettlementProgress] {
        nonSelfParticipants.map { participant in
            let name = participant.displayName
            let key = participant.normalizedKey ?? TransactionLogic.normalizeCounterpartyName(name) ?? ""
            
            let participantTxs = transactions.filter {
                $0.settlementGroupID == target.groupID
                    && $0.transferSubtype == .debt
                    && ($0.normalizedCounterpartyKey ?? TransactionLogic.normalizeCounterpartyName($0.counterpartyName)) == key
                    && $0.deletedAt == nil
                    && !$0.isArchived
            }
            
            let principalTx = participantTxs.first {
                $0.settlementRole == .sharedExpenseReceivable || $0.settlementRole == .sharedExpensePayable
            }
            
            if let principalTx {
                let isReceivable = principalTx.settlementRole == .sharedExpenseReceivable
                let originalAmount = principalTx.amountMinor
                let paidAmount = participantTxs
                    .filter { $0.settlementRole == .sharedExpenseReceipt || $0.settlementRole == .sharedExpensePayment }
                    .reduce(0) { $0 + $1.amountMinor }
                let remainingAmount = max(0, originalAmount - paidAmount)
                return ParticipantSettlementProgress(
                    id: participant.id,
                    displayName: name,
                    normalizedKey: key,
                    hasDebt: true,
                    isReceivable: isReceivable,
                    originalAmount: originalAmount,
                    paidAmount: paidAmount,
                    remainingAmount: remainingAmount,
                    isSettled: remainingAmount == 0
                )
            } else {
                return ParticipantSettlementProgress(
                    id: participant.id,
                    displayName: name,
                    normalizedKey: key,
                    hasDebt: false,
                    isReceivable: false,
                    originalAmount: 0,
                    paidAmount: 0,
                    remainingAmount: 0,
                    isSettled: true
                )
            }
        }
    }

    private func openDebtSettlement(forParticipantKey normalizedKey: String, displayName: String) {
        guard let position = debtPosition(forParticipantKey: normalizedKey, displayName: displayName) else {
            return
        }
        debtSettlementTarget = DebtSettlementSheetTarget(position: position)
    }

    private func debtPosition(
        forParticipantKey normalizedKey: String,
        displayName: String
    ) -> CounterpartyDebtSnapshot? {
        let existingRecords = transactions
            .filter {
                $0.settlementGroupID == target.groupID
                    && $0.transferSubtype == .debt
                    && ($0.normalizedCounterpartyKey ?? TransactionLogic.normalizeCounterpartyName($0.counterpartyName)) == normalizedKey
                    && $0.deletedAt == nil
                    && !$0.isArchived
            }
            .map(\.snapshot)
        
        let netMinor = existingRecords.reduce(Int64.zero) { total, record in
            switch record.debtIntent {
            case .lend:
                return total + record.amountMinor
            case .collect:
                return total - record.amountMinor
            case .borrow:
                return total - record.amountMinor
            case .repay:
                return total + record.amountMinor
            case nil:
                return total
            }
        }
        guard netMinor != 0 else { return nil }

        return CounterpartyDebtSnapshot(
            id: "\(normalizedKey)|\(currencyCode)|\(target.groupID.uuidString)",
            displayName: displayName,
            normalizedCounterpartyKey: normalizedKey,
            netMinor: netMinor,
            currencyCode: currencyCode,
            preferredWalletID: linkedBills.first?.sourceWallet?.id ?? wallets.first?.id,
            relatedRecords: existingRecords.sorted { $0.occurredAt > $1.occurredAt }
        )
    }
```

Update `Form` in `SettlementSplitCalculatorSheet` to conditionally show/hide inputs and progress:
```swift
                if !isFinalized {
                    Section(L10n.transactions.settlement.participants) {
                        if nonSelfParticipants.isEmpty {
                            SettlementEventExpenseEmptyState(...)
                        } else {
                            ForEach(nonSelfParticipants) { participant in
                                SharedExpenseParticipantPaidInputRow(
                                    participant: participant,
                                    currencyCode: currencyCode,
                                    paidText: paidTextBinding(for: participant)
                                )
                            }
                        }
                    }
                }

                Section(isFinalized ? "Tiến độ thanh toán" : L10n.transactions.settlement.sharedExpenseTitle) {
                    if isFinalized {
                        ForEach(participantSettlementProgressList()) { progress in
                            if progress.hasDebt && !progress.isSettled {
                                Button {
                                    openDebtSettlement(forParticipantKey: progress.normalizedKey, displayName: progress.displayName)
                                } label: {
                                    ParticipantSettlementProgressRow(progress: progress, currencyCode: currencyCode)
                                }
                                .buttonStyle(.plain)
                            } else {
                                ParticipantSettlementProgressRow(progress: progress, currencyCode: currencyCode)
                            }
                        }
                    } else {
                        if !allInputsProvided {
                            Text("Vui lòng nhập số tiền cho tất cả người tham gia để chia chi phí.")
                                .foregroundStyle(.secondary)
                                .italic()
                                .font(.system(size: 14, design: .rounded))
                        } else if suggestionsForSelf.isEmpty {
                            Text(L10n.transactions.settlement.noSettlementNeeded)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(suggestionsForSelf.enumerated()), id: \.offset) { _, suggestion in
                                Button {
                                    openDebtSettlement(for: suggestion)
                                } label: {
                                    SharedExpenseSuggestionActionRow(...)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
```
Hide the checkmark toolbar item when finalized:
```swift
                ToolbarItem(placement: .topBarTrailing) {
                    if !isFinalized {
                        Button {
                            finalizeSplit()
                        } label: {
                            Image(systemName: "checkmark")
                                ...
                        }
                        .disabled(nonSelfParticipants.isEmpty || !allInputsProvided)
                        .opacity((nonSelfParticipants.isEmpty || !allInputsProvided) ? 0.45 : 1)
                    }
                }
```

**Step 2: Commit**
```bash
git add Mistia/Features/Transactions/SettlementSheets.swift
git commit -m "feat: show settlement progress in calculator sheet when event is finalized"
```

---

### Task 7: Lock Editing in SettlementDetailSheet when Completed
**Files:**
- Modify: `Mistia/Features/Transactions/SettlementSheets.swift:2590-2646`

**Step 1: Write implementation**
Wrap inputs and disable toolbar items in `SettlementDetailSheet` when remaining balance is 0:
```swift
                if target.item.remainingMinor > 0 {
                    Section {
                        MistiaCurrencyInputField(
                            L10n.planning.duepayment.enterAmount,
                            text: $amountText,
                            font: .mistiaRounded(size: 17, weight: .semibold)
                        )
                        .frame(minHeight: 44)

                        Picker(L10n.planning.duepayment.paymentWallet, selection: $selectedWalletID) {
                            Text(L10n.planning.duepayment.chooseWallet).tag(Optional<UUID>.none)
                            ForEach(availableWallets) { wallet in
                                Text(walletPickerAccess.title(for: wallet)).tag(Optional(wallet.id))
                            }
                        }
                        .pickerStyle(.menu)
                    }
                } else {
                    Section {
                        HStack {
                            Spacer()
                            Text("Khoản nợ này đã được thanh toán hoàn tất")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
                }
```
And conditionally show the checkmark button:
```swift
                ToolbarItem(placement: .topBarTrailing) {
                    if target.item.remainingMinor > 0 {
                        Button {
                            save()
                        } label: {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(MistiaAccent.checkmarkPurple.color)
                                .frame(width: 30, height: 30)
                        }
                        .buttonStyle(.glassProminent)
                        .buttonBorderShape(.circle)
                        .tint(MistiaAccent.purple.color)
                        .disabled(isSaveDisabled)
                        .opacity(isSaveDisabled ? 0.45 : 1)
                    }
                }
```

**Step 2: Commit**
```bash
git add Mistia/Features/Transactions/SettlementSheets.swift
git commit -m "feat: lock editing in SettlementDetailSheet when obligation is completed"
```

---

### Task 8: Lock Editing in DebtSettlementSheet when Completed
**Files:**
- Modify: `Mistia/Features/Transactions/TransactionsView.swift:2443-2511`

**Step 1: Write implementation**
Wrap inputs and disable toolbar items in `DebtSettlementSheet` when target amount is 0:
```swift
                if target.amountMinor > 0 {
                    Section {
                        MistiaCurrencyInputField(
                            L10n.planning.duepayment.enterAmount,
                            text: $amountText,
                            font: .mistiaRounded(size: 17, weight: .semibold)
                        )
                        .frame(minHeight: 44)

                        Picker(L10n.planning.duepayment.paymentWallet, selection: $selectedWalletID) {
                            Text(L10n.planning.duepayment.chooseWallet).tag(Optional<UUID>.none)
                            ForEach(availableWallets) { wallet in
                                Text(walletPickerAccess.title(for: wallet)).tag(Optional(wallet.id))
                            }
                        }
                        .pickerStyle(.menu)
                    }
                } else {
                    Section {
                        HStack {
                            Spacer()
                            Text("Khoản nợ này đã được thanh toán hoàn tất")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
                }
```
And checkmark button in toolbar trailing:
```swift
                ToolbarItem(placement: .topBarTrailing) {
                    if target.amountMinor > 0 {
                        Button {
                            save()
                        } label: {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(MistiaAccent.checkmarkPurple.color)
                                .frame(width: 30, height: 30)
                        }
                        .buttonStyle(.glassProminent)
                        .buttonBorderShape(.circle)
                        .tint(MistiaAccent.purple.color)
                        .disabled(isSaveDisabled)
                        .opacity(isSaveDisabled ? 0.45 : 1)
                    }
                }
```

**Step 2: Commit**
```bash
git add Mistia/Features/Transactions/TransactionsView.swift
git commit -m "feat: lock editing in DebtSettlementSheet when debt is completed"
```

---

### Task 9: Align Empty State in NotificationCenterView
**Files:**
- Modify: `Mistia/Features/Notifications/NotificationCenterView.swift:808-824`

**Step 1: Write implementation**
Use `MistiaEmptyStateContent` for `emptyState` in `NotificationCenterView`:
```swift
    private var emptyState: some View {
        MistiaEmptyStateContent(
            title: L10n.notifications.notificationcenter.noNotificationsYet,
            message: L10n.notifications.notificationcenter.permissionRequestsAndFamilyActivityWillAppear,
            buttonTitle: nil,
            accent: MistiaAccent.purple.color,
            symbols: ["bell.slash.fill", "bell.badge", "envelope.badge"]
        )
    }
```

**Step 2: Commit**
```bash
git add Mistia/Features/Notifications/NotificationCenterView.swift
git commit -m "feat: align notification center empty state with app style"
```
