import Foundation
import SwiftData

@MainActor
enum MistiaRecurringBillMaintenance {

    // MARK: - Main entrypoint

    static func run(
        modelContext: ModelContext,
        sessionStore: SessionStore,
        referenceDate: Date = .now,
        calendar: Calendar = MistiaCalendar.current
    ) async {
        guard let snapshot = MistiaDueMaintenanceSnapshot.make(
            modelContext: modelContext,
            sessionStore: sessionStore
        ) else { return }

        await run(
            snapshot: snapshot,
            modelContext: modelContext,
            sessionStore: sessionStore,
            referenceDate: referenceDate,
            calendar: calendar
        )
    }

    static func run(
        snapshot: MistiaDueMaintenanceSnapshot,
        modelContext: ModelContext,
        sessionStore: SessionStore,
        referenceDate: Date = .now,
        calendar: Calendar = MistiaCalendar.current
    ) async {
        removeStaleBillNotifications(
            billOwnerMap: snapshot.billOwnerMap,
            activeUserID: snapshot.activeUserID,
            modelContext: modelContext
        )

        for bill in snapshot.activeBills where bill.isPaused {
            resolveNotifications(for: bill.id, modelContext: modelContext)
        }

        let activeBills = snapshot.activeBills.filter { !$0.isPaused }
        guard !activeBills.isEmpty else { return }

        let selectedMonth = PlanningLogic.startOfMonth(for: referenceDate, calendar: calendar)
        let previousMonth = calendar.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth
        let startOfToday = calendar.startOfDay(for: referenceDate)
        let pendingDueItemsByBillID = pendingRecurringDueItemsByBillID(
            bills: activeBills.map(\.planningSnapshot),
            occurrences: snapshot.activeOccurrenceSnapshots,
            selectedMonths: [previousMonth, selectedMonth],
            calendar: calendar
        )

        for bill in activeBills {
            let snap = bill.planningSnapshot
            let dueItems = pendingDueItemsByBillID[bill.id] ?? []

            for dueItem in dueItems {
                let cycleMonthKey = PlanningLogic.monthKey(for: dueItem.paymentStartDate, calendar: calendar)
                let paymentStartDay = calendar.startOfDay(for: dueItem.paymentStartDate)
                let dueDay = calendar.startOfDay(for: dueItem.dueDate)
                let autoPayDay = dueItem.autoPayDate.map { calendar.startOfDay(for: $0) }
                let isPaymentStartToday = paymentStartDay == startOfToday
                let isDeadlineToday = dueItem.hasExplicitDueDate && dueDay == startOfToday
                let isAutoPayToday = dueItem.autoPayEnabled && autoPayDay == startOfToday
                let isOverdue = dueDay < startOfToday

                let amountText = dueItem.amountMinor.map { $0.formattedCurrency(code: snap.currencyCode) }

                if isAutoPayToday,
                   let amount = dueItem.amountMinor,
                   let walletID = snap.paymentWalletID,
                   let paymentWallet = snapshot.walletByID[walletID] {

                    let canPay = balanceSufficientToCover(
                        amount: amount,
                        wallet: paymentWallet,
                        balanceIndex: snapshot.balanceIndex
                    )

                    if canPay {
                        await attemptAutoPay(
                            bill: bill,
                            dueItem: dueItem,
                            paymentWallet: paymentWallet,
                            amount: amount,
                            monthKey: cycleMonthKey,
                            occurrences: snapshot.activeOccurrences,
                            ownershipScopes: snapshot.ownershipScopes,
                            modelContext: modelContext,
                            sessionStore: sessionStore,
                            referenceDate: referenceDate
                        )
                        continue
                    } else {
                        upsertNotification(
                            key: "mistia.bill.autopay.failed.\(bill.id.uuidString.lowercased()).\(cycleMonthKey)",
                            title: L10n.shared.notifications.mistiarecurringbillmaintenance.autoPaymentFailed,
                            body: L10n.shared.notifications.mistiarecurringbillmaintenance.insufficientBalanceToAutoPayValuePlease(String(describing: bill.name)),
                            kind: .billAutoPaymentFailed,
                            bill: bill,
                            dueItem: dueItem,
                            monthKey: cycleMonthKey,
                            recipientUserID: snapshot.activeUserID,
                            modelContext: modelContext
                        )
                    }
                } else if isAutoPayToday && dueItem.autoPayEnabled {
                    upsertNotification(
                        key: "mistia.bill.autopay.failed.\(bill.id.uuidString.lowercased()).\(cycleMonthKey)",
                        title: L10n.shared.notifications.mistiarecurringbillmaintenance.autoPaymentFailed,
                        body: L10n.shared.notifications.mistiarecurringbillmaintenance.valueIsMissingAnAmountOrPayment(String(describing: bill.name)),
                        kind: .billAutoPaymentFailed,
                        bill: bill,
                        dueItem: dueItem,
                        monthKey: cycleMonthKey,
                        recipientUserID: snapshot.activeUserID,
                        modelContext: modelContext
                    )
                }

                if isPaymentStartToday || isDeadlineToday {
                    let keyPhase = isDeadlineToday ? "deadline" : "start"
                    let title = isDeadlineToday
                        ? L10n.shared.notifications.mistiarecurringbillmaintenance.billDueToday
                        : L10n.shared.notifications.mistiarecurringbillmaintenance.paymentDate
                    let body: String
                    if let amountText {
                        body = dueItem.hasExplicitDueDate
                            ? L10n.shared.notifications.mistiarecurringbillmaintenance.valueValueIsDueByValue(String(describing: bill.name), String(describing: amountText), String(describing: MistiaDateFormatting.shortDateString(for: dueItem.dueDate)))
                            : L10n.shared.notifications.mistiarecurringbillmaintenance.valueValueIsReadyToPayToday(String(describing: bill.name), String(describing: amountText))
                    } else {
                        body = dueItem.hasExplicitDueDate
                            ? L10n.shared.notifications.mistiarecurringbillmaintenance.valueIsDueByValue(String(describing: bill.name), String(describing: MistiaDateFormatting.shortDateString(for: dueItem.dueDate)))
                            : L10n.shared.notifications.mistiarecurringbillmaintenance.valueIsReadyToPayToday(String(describing: bill.name))
                    }

                    upsertNotification(
                        key: "mistia.bill.payment.\(keyPhase).\(bill.id.uuidString.lowercased()).\(cycleMonthKey)",
                        title: title,
                        body: body,
                        kind: .billPaymentRequired,
                        bill: bill,
                        dueItem: dueItem,
                        monthKey: cycleMonthKey,
                        recipientUserID: snapshot.activeUserID,
                        modelContext: modelContext
                    )
                }

                // Overdue handling — resurface daily until paid
                if isOverdue {
                    let body: String
                    if let amountText {
                        body = L10n.shared.notifications.mistiarecurringbillmaintenance.valueValueIsPastItsDueDate(String(describing: bill.name), String(describing: amountText))
                    } else {
                        body = L10n.shared.notifications.mistiarecurringbillmaintenance.valueIsPastItsDueDate(String(describing: bill.name))
                    }

                    upsertNotification(
                        key: "mistia.bill.overdue.\(bill.id.uuidString.lowercased()).\(cycleMonthKey)",
                        title: L10n.shared.notifications.mistiarecurringbillmaintenance.billOverdue,
                        body: body,
                        kind: .billOverdue,
                        bill: bill,
                        dueItem: dueItem,
                        monthKey: cycleMonthKey,
                        recipientUserID: snapshot.activeUserID,
                        modelContext: modelContext,
                        forceUnread: true
                    )
                }
            }
        }
    }

    private static func pendingRecurringDueItemsByBillID(
        bills: [PlanningBillSnapshot],
        occurrences: [PlanningDueOccurrenceSnapshot],
        selectedMonths: [Date],
        calendar: Calendar
    ) -> [UUID: [PlanningRecurringDueSnapshot]] {
        guard !bills.isEmpty, !selectedMonths.isEmpty else { return [:] }

        var dueItemsByBillID: [UUID: [PlanningRecurringDueSnapshot]] = [:]
        dueItemsByBillID.reserveCapacity(bills.count)

        for selectedMonth in selectedMonths {
            let dueItems = PlanningLogic.recurringBillDueItems(
                bills: bills,
                occurrences: occurrences,
                selectedMonth: selectedMonth,
                calendar: calendar
            )
            for dueItem in dueItems where dueItem.status == .pending && dueItem.sourceKind == .recurringBill {
                dueItemsByBillID[dueItem.sourceID, default: []].append(dueItem)
            }
        }

        return dueItemsByBillID
    }

    // MARK: - Auto-pay

    private static func attemptAutoPay(
        bill: RecurringBillPlan,
        dueItem: PlanningRecurringDueSnapshot,
        paymentWallet: LedgerWallet,
        amount: Int64,
        monthKey: String,
        occurrences: [DueOccurrenceRecord],
        ownershipScopes: [OwnedRecordScope],
        modelContext: ModelContext,
        sessionStore: SessionStore,
        referenceDate: Date
    ) async {
        let now = Date()
        let title = L10n.shared.notifications.mistiarecurringbillmaintenance.autoPaidValue(String(describing: bill.name))
        let tx = LedgerTransaction(
            primaryKind: .expense,
            title: title,
            amountMinor: amount,
            occurredAt: referenceDate,
            sourceWallet: paymentWallet
        )
        tx.updatedAt = now

        // Set category from bill
        if let category = bill.category {
            tx.category = category
        }

        modelContext.insert(tx)

        // Mark occurrence paid
        let selectedMonth = PlanningLogic.startOfMonth(for: dueItem.paymentStartDate)

        do {
            let occurrence = try PlanningPersistenceSupport.upsertOccurrence(
                sourceKind: .recurringBill,
                sourceID: bill.id,
                selectedMonth: selectedMonth,
                scheduledDate: dueItem.dueDate,
                amountMinor: amount,
                linkedTransactionID: tx.id,
                occurrences: occurrences,
                modelContext: modelContext,
                paidAt: now
            )

            // Ownership + audit
            let subjectUserID = try recordOwnershipAndAudit(
                transaction: tx,
                sourceWalletID: paymentWallet.id,
                actorUserID: sessionStore.activeLocalProfileUserID,
                ownershipScopes: ownershipScopes,
                modelContext: modelContext
            )
            try recordOwnership(
                entity: .dueOccurrenceRecord,
                recordID: occurrence.id,
                ownerUserID: subjectUserID,
                updatedAt: occurrence.updatedAt,
                modelContext: modelContext
            )

            try modelContext.save()
            sessionStore.recordUpsert(
                entity: .transaction,
                recordID: tx.id,
                modifiedAt: tx.updatedAt,
                subjectUserIDOverride: subjectUserID
            )
            sessionStore.recordUpsert(
                entity: .dueOccurrenceRecord,
                recordID: occurrence.id,
                modifiedAt: occurrence.updatedAt,
                subjectUserIDOverride: subjectUserID
            )

            upsertNotification(
                key: "mistia.bill.autopay.success.\(bill.id.uuidString.lowercased()).\(monthKey)",
                title: L10n.shared.notifications.mistiarecurringbillmaintenance.autoPaymentComplete,
                body: L10n.shared.notifications.mistiarecurringbillmaintenance.mistiaPaidValueForValue(String(describing: amount.formattedCurrency(code: bill.currencyCode)), String(describing: bill.name)),
                kind: .billAutoPaymentSucceeded,
                bill: bill,
                dueItem: dueItem,
                monthKey: monthKey,
                recipientUserID: sessionStore.activeLocalProfileUserID,
                modelContext: modelContext
            )
        } catch {
            upsertNotification(
                key: "mistia.bill.autopay.failed.\(bill.id.uuidString.lowercased()).\(monthKey)",
                title: L10n.shared.notifications.mistiarecurringbillmaintenance.autoPaymentFailed,
                body: L10n.shared.notifications.mistiarecurringbillmaintenance.failedToAutoPayValueValue(String(describing: bill.name), String(describing: error.localizedDescription)),
                kind: .billAutoPaymentFailed,
                bill: bill,
                dueItem: dueItem,
                monthKey: monthKey,
                recipientUserID: sessionStore.activeLocalProfileUserID,
                modelContext: modelContext
            )
        }
    }

    // MARK: - Resolve after manual payment

    static func resolveNotifications(for billID: UUID, monthKey: String, modelContext: ModelContext) {
        let prefix = "mistia.bill."
        let suffix = ".\(billID.uuidString.lowercased()).\(monthKey)"
        let resolvedKinds: [MistiaAppNotificationKind] = [
            .billPaymentRequired, .billAutoPaymentFailed, .billOverdue
        ]
        let billResourceTypeRawValue = MistiaFamilyNotificationResourceType.bill.rawValue
        let localReminderSourceRawValue = MistiaAppNotificationSource.localReminder.rawValue
        let systemSourceRawValue = MistiaAppNotificationSource.system.rawValue
        let existing = (try? modelContext.fetch(
            FetchDescriptor<AppNotificationRecord>(
                predicate: #Predicate<AppNotificationRecord> { row in
                    row.resourceTypeRawValue == billResourceTypeRawValue
                        && (
                            row.sourceRawValue == localReminderSourceRawValue
                                || row.sourceRawValue == systemSourceRawValue
                        )
                }
            )
        )) ?? []
        let now = Date()
        for row in existing
            where row.key.hasPrefix(prefix)
            && row.key.hasSuffix(suffix)
            && resolvedKinds.contains(row.kind) {
            row.isRead = true
            row.readAt = row.readAt ?? now
            row.actionState = .resolved
            row.updatedAt = now
        }
        try? modelContext.save()
    }

    static func resolveNotifications(for billID: UUID, modelContext: ModelContext) {
        let resolvedKinds: [MistiaAppNotificationKind] = [
            .billPaymentRequired, .billAutoPaymentFailed, .billOverdue
        ]
        let billResourceTypeRawValue = MistiaFamilyNotificationResourceType.bill.rawValue
        let localReminderSourceRawValue = MistiaAppNotificationSource.localReminder.rawValue
        let systemSourceRawValue = MistiaAppNotificationSource.system.rawValue
        let existing = (try? modelContext.fetch(
            FetchDescriptor<AppNotificationRecord>(
                predicate: #Predicate<AppNotificationRecord> { row in
                    row.resourceTypeRawValue == billResourceTypeRawValue
                        && row.resourceID == billID
                        && (
                            row.sourceRawValue == localReminderSourceRawValue
                                || row.sourceRawValue == systemSourceRawValue
                        )
                }
            )
        )) ?? []
        let now = Date()
        for row in existing where resolvedKinds.contains(row.kind) {
            row.isRead = true
            row.readAt = row.readAt ?? now
            row.actionState = .resolved
            row.updatedAt = now
        }
        try? modelContext.save()
    }

    // MARK: - Notification upsert

    private static func upsertNotification(
        key: String,
        title: String,
        body: String,
        kind: MistiaAppNotificationKind,
        bill: RecurringBillPlan,
        dueItem: PlanningRecurringDueSnapshot,
        monthKey: String,
        recipientUserID: UUID?,
        modelContext: ModelContext,
        forceUnread: Bool = false
    ) {
        guard MistiaNotificationPreferences.reminderEnabled(.bills) else { return }
        guard let recipientUserID else { return }

        let payload = DueNotificationActionPayload(
            sourceKind: PlanningDueSourceKind.recurringBill.rawValue,
            sourceID: bill.id,
            dueMonthKey: monthKey,
            dueDate: dueItem.dueDate,
            requiresAmountInput: dueItem.amountMinor == nil,
            currencyCode: bill.currencyCode,
            billName: bill.name,
            linkedPaymentWalletID: bill.paymentWallet?.id
        )
        let metadataJSON: String? = {
            guard let data = try? JSONEncoder.mistiaSyncEncoder.encode(payload) else { return nil }
            return String(data: data, encoding: .utf8)
        }()

        let existing = (try? modelContext.fetch(
            FetchDescriptor<AppNotificationRecord>(
                predicate: #Predicate { $0.key == key }
            )
        ))?.first

        if let existing {
            existing.title = title
            existing.body = body
            existing.kind = kind
            existing.source = .system
            existing.recipientUserID = recipientUserID
            existing.resourceType = .bill
            existing.resourceID = bill.id
            existing.metadataJSON = metadataJSON
            existing.updatedAt = .now
            if forceUnread {
                existing.createdAt = .now
                existing.isRead = false
                existing.readAt = nil
            }
        } else {
            modelContext.insert(AppNotificationRecord(
                key: key,
                createdAt: .now,
                updatedAt: .now,
                title: title,
                body: body,
                kind: kind,
                source: .system,
                isRead: false,
                recipientUserID: recipientUserID,
                resourceType: .bill,
                resourceID: bill.id,
                metadataJSON: metadataJSON
            ))
        }

        try? modelContext.save()
    }

    // MARK: - Balance check

    private static func balanceSufficientToCover(
        amount: Int64,
        wallet: LedgerWallet,
        balanceIndex: TransactionWalletBalanceIndex
    ) -> Bool {
        if wallet.kind == .creditCard {
            guard let profile = wallet.creditCardProfile else { return false }
            let debt = max(
                balanceIndex.balance(
                    for: TransactionWalletSnapshot(
                        id: wallet.id,
                        kind: .creditCard,
                        openingBalanceMinor: wallet.openingBalanceMinor
                    )
                ),
                0
            )
            return (profile.creditLimitMinor - debt) >= amount
        } else {
            let balance = balanceIndex.balance(
                for: TransactionWalletSnapshot(
                    id: wallet.id,
                    kind: wallet.kind,
                    openingBalanceMinor: wallet.openingBalanceMinor
                )
            )
            return balance >= amount
        }
    }

    // MARK: - Ownership & audit (mirrors MistiaCreditCardStatementMaintenance)

    private static func recordOwnershipAndAudit(
        transaction: LedgerTransaction,
        sourceWalletID: UUID,
        actorUserID: UUID?,
        ownershipScopes: [OwnedRecordScope],
        modelContext: ModelContext
    ) throws -> UUID? {
        let subjectUserID = TransactionAuditStore.resolveOwnerUserID(
            forWalletID: sourceWalletID,
            ownershipScopes: ownershipScopes
        )
        if let subjectUserID {
            try MistiaRecordOwnershipStore.upsert(
                entity: .transaction,
                recordID: transaction.id,
                ownerUserID: subjectUserID,
                updatedAt: transaction.updatedAt,
                context: modelContext
            )
        }
        if let createdBy = actorUserID ?? subjectUserID {
            try TransactionAuditStore.upsert(
                transactionID: transaction.id,
                createdByUserID: createdBy,
                lastModifiedByUserID: actorUserID ?? createdBy,
                updatedAt: transaction.updatedAt,
                context: modelContext
            )
        }
        return subjectUserID
    }

    private static func recordOwnership(
        entity: MistiaSyncEntity,
        recordID: UUID,
        ownerUserID: UUID?,
        updatedAt: Date,
        modelContext: ModelContext
    ) throws {
        guard let ownerUserID else { return }
        try MistiaRecordOwnershipStore.upsert(
            entity: entity,
            recordID: recordID,
            ownerUserID: ownerUserID,
            updatedAt: updatedAt,
            context: modelContext
        )
    }

    private static func removeStaleBillNotifications(
        billOwnerMap: [UUID: UUID],
        activeUserID: UUID,
        modelContext: ModelContext
    ) {
        let billResourceTypeRawValue = MistiaFamilyNotificationResourceType.bill.rawValue
        let localReminderSourceRawValue = MistiaAppNotificationSource.localReminder.rawValue
        let systemSourceRawValue = MistiaAppNotificationSource.system.rawValue
        let rows = (try? modelContext.fetch(
            FetchDescriptor<AppNotificationRecord>(
                predicate: #Predicate<AppNotificationRecord> { row in
                    row.resourceTypeRawValue == billResourceTypeRawValue
                        && (
                            row.sourceRawValue == localReminderSourceRawValue
                                || row.sourceRawValue == systemSourceRawValue
                        )
                }
            )
        )) ?? []
        let billKinds: Set<MistiaAppNotificationKind> = [
            .billPaymentRequired,
            .billAutoPaymentSucceeded,
            .billAutoPaymentFailed,
            .billOverdue
        ]
        var didDelete = false

        for row in rows where billKinds.contains(row.kind) {
            guard let resourceID = row.resourceID,
                  let ownerUserID = billOwnerMap[resourceID],
                  ownerUserID != activeUserID else {
                continue
            }
            modelContext.delete(row)
            didDelete = true
        }

        if didDelete {
            try? modelContext.save()
        }
    }
}
