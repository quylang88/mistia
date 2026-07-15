import Foundation
import SwiftData

@MainActor
enum MistiaCreditCardStatementMaintenance {
    private struct StatementOccurrenceUpsertResult {
        let record: DueOccurrenceRecord
        let lastAutoPaymentAttemptAt: Date?
    }

    private struct ExistingAutoPaymentKey: Hashable {
        let sourceWalletID: UUID
        let destinationWalletID: UUID
        let amountMinor: Int64
        let paymentDay: Date

        init(
            sourceWalletID: UUID,
            destinationWalletID: UUID,
            amountMinor: Int64,
            paymentDay: Date
        ) {
            self.sourceWalletID = sourceWalletID
            self.destinationWalletID = destinationWalletID
            self.amountMinor = amountMinor
            self.paymentDay = paymentDay
        }

        init?(transaction: LedgerTransaction, calendar: Calendar) {
            guard transaction.primaryKind == .transfer,
                  transaction.transferSubtype == .internalTransfer,
                  transaction.entryStatus == .posted,
                  !transaction.isArchived,
                  transaction.deletedAt == nil,
                  let sourceWalletID = transaction.sourceWallet?.id,
                  let destinationWalletID = transaction.destinationWallet?.id else {
                return nil
            }

            self.init(
                sourceWalletID: sourceWalletID,
                destinationWalletID: destinationWalletID,
                amountMinor: transaction.amountMinor,
                paymentDay: calendar.startOfDay(for: transaction.occurredAt)
            )
        }
    }

    private struct ExistingAutoPaymentIndex {
        private var transactionsByKey: [ExistingAutoPaymentKey: LedgerTransaction] = [:]

        init(transactions: [LedgerTransaction], calendar: Calendar) {
            transactionsByKey.reserveCapacity(transactions.count)

            for transaction in transactions {
                guard let key = ExistingAutoPaymentKey(transaction: transaction, calendar: calendar) else {
                    continue
                }
                if let existing = transactionsByKey[key], existing.updatedAt >= transaction.updatedAt {
                    continue
                }
                transactionsByKey[key] = transaction
            }
        }

        func transaction(
            for statement: PlanningCreditCardStatementSnapshot,
            calendar: Calendar
        ) -> LedgerTransaction? {
            guard let sourceWalletID = statement.paymentSourceWalletID else { return nil }

            return transactionsByKey[
                ExistingAutoPaymentKey(
                    sourceWalletID: sourceWalletID,
                    destinationWalletID: statement.walletID,
                    amountMinor: statement.amountMinor,
                    paymentDay: calendar.startOfDay(for: statement.dueDate)
                )
            ]
        }
    }

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
        removeStaleCreditCardNotifications(
            walletOwnerMap: snapshot.walletOwnerMap,
            activeUserID: snapshot.activeUserID,
            modelContext: modelContext
        )

        let accounts = snapshot.activeWallets.compactMap {
            $0.planningCreditCardSnapshot(balanceIndex: snapshot.balanceIndex)
        }
        guard !accounts.isEmpty else { return }

        let currentMonth = PlanningLogic.startOfMonth(for: referenceDate, calendar: calendar)
        let statementMonths = (0...24).compactMap { offset in
            calendar.date(byAdding: .month, value: -offset, to: currentMonth)
        }
        var occurrences = snapshot.activeOccurrences
        let occurrenceSnapshots = occurrences.map(\.planningSnapshot)
        let statementsByWalletID = Dictionary(
            grouping: PlanningLogic.creditCardStatementItems(
                accounts: accounts,
                records: snapshot.activeTransactionRecords,
                occurrences: occurrenceSnapshots,
                statementMonths: statementMonths,
                referenceDate: referenceDate,
                calendar: calendar
            ),
            by: \.walletID
        )
        let existingAutoPayments = ExistingAutoPaymentIndex(
            transactions: snapshot.activeTransactions,
            calendar: calendar
        )

        for account in accounts {
            let statements = statementsByWalletID[account.walletID] ?? []

            for statement in statements where statement.amountMinor > 0 {
                guard statement.state != .unclosed else { continue }

                let occurrenceResult = upsertClosedStatementOccurrence(
                    statement,
                    occurrences: &occurrences,
                    modelContext: modelContext,
                    sessionStore: sessionStore,
                    calendar: calendar
                )
                let occurrence = occurrenceResult.record
                upsertStatementReadyNotification(
                    statement,
                    modelContext: modelContext,
                    recipientUserID: sessionStore.activeLocalProfileUserID,
                    calendar: calendar
                )

                guard account.autoPayEnabled else { continue }

                if let existingPayment = existingAutoPaymentTransaction(
                    for: statement,
                    in: existingAutoPayments,
                    calendar: calendar
                ) {
                    markOccurrencePaid(
                        occurrence,
                        for: statement,
                        linkedTransaction: existingPayment,
                        modelContext: modelContext,
                        sessionStore: sessionStore,
                        calendar: calendar
                    )
                    continue
                }

                guard shouldAttemptAutoPayment(
                    occurrence: occurrence,
                    lastAttemptAt: occurrenceResult.lastAutoPaymentAttemptAt,
                    referenceDate: referenceDate,
                    calendar: calendar
                ) else {
                    continue
                }

                let sourceBalanceMinor = paymentSourceBalance(
                    for: statement,
                    walletByID: snapshot.walletByID,
                    balanceIndex: snapshot.balanceIndex
                )
                let autoPaymentDecision = PlanningLogic.creditCardAutoPaymentDecision(
                    statement: statement,
                    sourceWalletBalanceMinor: sourceBalanceMinor,
                    referenceDate: referenceDate,
                    calendar: calendar
                )

                switch autoPaymentDecision {
                case .notDue, .alreadyPaid:
                    continue
                case .missingLinkedWallet:
                    upsertAutoPaymentFailureNotification(
                        statement,
                        reason: L10n.shared.notifications.mistiacreditcardstatementmaintenance.noLinkedWalletIsSet,
                        modelContext: modelContext,
                        recipientUserID: sessionStore.activeLocalProfileUserID,
                        calendar: calendar
                    )
                    markAutoPaymentAttemptFailed(
                        occurrence,
                        modelContext: modelContext,
                        sessionStore: sessionStore
                    )
                case .insufficientFunds:
                    upsertAutoPaymentFailureNotification(
                        statement,
                        reason: L10n.shared.notifications.mistiacreditcardstatementmaintenance.theLinkedWalletHasInsufficientFunds,
                        modelContext: modelContext,
                        recipientUserID: sessionStore.activeLocalProfileUserID,
                        calendar: calendar
                    )
                    markAutoPaymentAttemptFailed(
                        occurrence,
                        modelContext: modelContext,
                        sessionStore: sessionStore
                    )
                case .payable:
                    await attemptAutoPayment(
                        statement,
                        occurrence: occurrence,
                        walletByID: snapshot.walletByID,
                        balanceIndex: snapshot.balanceIndex,
                        ownershipScopes: snapshot.ownershipScopes,
                        modelContext: modelContext,
                        sessionStore: sessionStore,
                        calendar: calendar
                    )
                }
            }
        }
    }

    @discardableResult
    private static func upsertClosedStatementOccurrence(
        _ statement: PlanningCreditCardStatementSnapshot,
        occurrences: inout [DueOccurrenceRecord],
        modelContext: ModelContext,
        sessionStore: SessionStore,
        calendar: Calendar
    ) -> StatementOccurrenceUpsertResult {
        let monthKey = PlanningLogic.monthKey(for: statement.statementMonth, calendar: calendar)
        let legacyDueMonthKey = PlanningLogic.monthKey(for: statement.dueDate, calendar: calendar)
        let now = Date()

        if let existing = occurrences.first(where: {
            $0.sourceKind == .creditCard
                && $0.sourceID == statement.walletID
                && ($0.selectedMonthKey == monthKey || $0.selectedMonthKey == legacyDueMonthKey)
        }) {
            var didChange = false
            let lastAutoPaymentAttemptAt = existing.status == .pending
                && existing.paidAt == nil
                && existing.linkedTransactionID == nil
                ? existing.updatedAt
                : nil
            if existing.selectedMonthKey != monthKey {
                existing.selectedMonthKey = monthKey
                didChange = true
            }
            guard existing.status == .pending else {
                if didChange {
                    existing.updatedAt = now
                    try? modelContext.save()
                    sessionStore.recordUpsert(
                        entity: .dueOccurrenceRecord,
                        recordID: existing.id,
                        modifiedAt: existing.updatedAt
                    )
                }
                return StatementOccurrenceUpsertResult(
                    record: existing,
                    lastAutoPaymentAttemptAt: nil
                )
            }
            if existing.scheduledDate != statement.dueDate {
                existing.scheduledDate = statement.dueDate
                didChange = true
            }
            if existing.amountMinorSnapshot != statement.amountMinor {
                existing.amountMinorSnapshot = statement.amountMinor
                didChange = true
            }
            if didChange {
                existing.updatedAt = now
                try? modelContext.save()
                sessionStore.recordUpsert(
                    entity: .dueOccurrenceRecord,
                    recordID: existing.id,
                    modifiedAt: existing.updatedAt
                )
            }
            return StatementOccurrenceUpsertResult(
                record: existing,
                lastAutoPaymentAttemptAt: lastAutoPaymentAttemptAt
            )
        }

        let record = DueOccurrenceRecord(
            sourceKind: .creditCard,
            sourceID: statement.walletID,
            selectedMonthKey: monthKey,
            scheduledDate: statement.dueDate,
            amountMinorSnapshot: statement.amountMinor,
            status: .pending,
            createdAt: now,
            updatedAt: now
        )
        modelContext.insert(record)
        occurrences.append(record)
        try? modelContext.save()
        sessionStore.recordUpsert(
            entity: .dueOccurrenceRecord,
            recordID: record.id,
            modifiedAt: record.updatedAt
        )
        return StatementOccurrenceUpsertResult(
            record: record,
            lastAutoPaymentAttemptAt: nil
        )
    }

    private static func paymentSourceBalance(
        for statement: PlanningCreditCardStatementSnapshot,
        walletByID: [UUID: LedgerWallet],
        balanceIndex: TransactionWalletBalanceIndex
    ) -> Int64? {
        guard let sourceWalletID = statement.paymentSourceWalletID,
              let sourceWallet = walletByID[sourceWalletID] else {
            return nil
        }

        return balanceIndex.balance(
            for: TransactionWalletSnapshot(
                id: sourceWallet.id,
                kind: sourceWallet.kind,
                openingBalanceMinor: sourceWallet.openingBalanceMinor
            )
        )
    }

    private static func shouldAttemptAutoPayment(
        occurrence: DueOccurrenceRecord,
        lastAttemptAt: Date?,
        referenceDate: Date,
        calendar: Calendar
    ) -> Bool {
        guard occurrence.status == .pending,
              occurrence.paidAt == nil,
              occurrence.linkedTransactionID == nil else {
            return false
        }
        guard let lastAttemptAt else { return true }
        return calendar.startOfDay(for: lastAttemptAt) < calendar.startOfDay(for: referenceDate)
    }

    private static func existingAutoPaymentTransaction(
        for statement: PlanningCreditCardStatementSnapshot,
        in index: ExistingAutoPaymentIndex,
        calendar: Calendar
    ) -> LedgerTransaction? {
        index.transaction(for: statement, calendar: calendar)
    }

    private static func markOccurrencePaid(
        _ occurrence: DueOccurrenceRecord,
        for statement: PlanningCreditCardStatementSnapshot,
        linkedTransaction: LedgerTransaction,
        modelContext: ModelContext,
        sessionStore: SessionStore,
        calendar: Calendar
    ) {
        occurrence.status = .paid
        occurrence.selectedMonthKey = PlanningLogic.monthKey(for: statement.statementMonth, calendar: calendar)
        occurrence.paidAt = linkedTransaction.occurredAt
        occurrence.linkedTransactionID = linkedTransaction.id
        occurrence.amountMinorSnapshot = statement.amountMinor
        occurrence.scheduledDate = statement.dueDate
        occurrence.updatedAt = Date()
        try? modelContext.save()
        sessionStore.recordUpsert(
            entity: .dueOccurrenceRecord,
            recordID: occurrence.id,
            modifiedAt: occurrence.updatedAt
        )
    }

    private static func markAutoPaymentAttemptFailed(
        _ occurrence: DueOccurrenceRecord,
        modelContext: ModelContext,
        sessionStore: SessionStore
    ) {
        occurrence.updatedAt = Date()
        try? modelContext.save()
        sessionStore.recordUpsert(
            entity: .dueOccurrenceRecord,
            recordID: occurrence.id,
            modifiedAt: occurrence.updatedAt
        )
    }

    private static func attemptAutoPayment(
        _ statement: PlanningCreditCardStatementSnapshot,
        occurrence: DueOccurrenceRecord,
        walletByID: [UUID: LedgerWallet],
        balanceIndex: TransactionWalletBalanceIndex,
        ownershipScopes: [OwnedRecordScope],
        modelContext: ModelContext,
        sessionStore: SessionStore,
        calendar: Calendar
    ) async {
        guard let sourceWalletID = statement.paymentSourceWalletID,
              let sourceWallet = walletByID[sourceWalletID],
              let cardWallet = walletByID[statement.walletID] else {
            upsertAutoPaymentFailureNotification(
                statement,
                reason: L10n.shared.notifications.mistiacreditcardstatementmaintenance.noLinkedWalletIsSet,
                modelContext: modelContext,
                recipientUserID: sessionStore.activeLocalProfileUserID,
                calendar: calendar
            )
            markAutoPaymentAttemptFailed(
                occurrence,
                modelContext: modelContext,
                sessionStore: sessionStore
            )
            return
        }

        let sourceBalanceMinor = balanceIndex.balance(
            for: TransactionWalletSnapshot(
                id: sourceWallet.id,
                kind: sourceWallet.kind,
                openingBalanceMinor: sourceWallet.openingBalanceMinor
            )
        )
        guard sourceBalanceMinor >= statement.amountMinor else {
            upsertAutoPaymentFailureNotification(
                statement,
                reason: L10n.shared.notifications.mistiacreditcardstatementmaintenance.theLinkedWalletHasInsufficientFunds,
                modelContext: modelContext,
                recipientUserID: sessionStore.activeLocalProfileUserID,
                calendar: calendar
            )
            markAutoPaymentAttemptFailed(
                occurrence,
                modelContext: modelContext,
                sessionStore: sessionStore
            )
            return
        }

        let title = L10n.shared.notifications.mistiacreditcardstatementmaintenance.autoPaymentForValue(String(describing: statement.walletName))
        let paymentTx = LedgerTransaction(
            primaryKind: .transfer,
            transferSubtype: .internalTransfer,
            title: title,
            amountMinor: statement.amountMinor,
            occurredAt: statement.dueDate,
            sourceWallet: sourceWallet,
            destinationWallet: cardWallet
        )
        paymentTx.updatedAt = Date()
        modelContext.insert(paymentTx)

        occurrence.status = .paid
        occurrence.selectedMonthKey = PlanningLogic.monthKey(for: statement.statementMonth, calendar: calendar)
        occurrence.paidAt = statement.dueDate
        occurrence.linkedTransactionID = paymentTx.id
        occurrence.amountMinorSnapshot = statement.amountMinor
        occurrence.scheduledDate = statement.dueDate
        occurrence.updatedAt = paymentTx.updatedAt

        let subjectUserID: UUID?
        do {
            subjectUserID = try recordOwnershipAndAudit(
                transaction: paymentTx,
                sourceWalletID: sourceWallet.id,
                actorUserID: sessionStore.activeLocalProfileUserID,
                ownershipScopes: ownershipScopes,
                modelContext: modelContext
            )
        } catch {
            subjectUserID = nil
        }

        do {
            try modelContext.save()
            sessionStore.recordUpsert(
                entity: .transaction,
                recordID: paymentTx.id,
                modifiedAt: paymentTx.updatedAt,
                subjectUserIDOverride: subjectUserID
            )
            sessionStore.recordUpsert(
                entity: .dueOccurrenceRecord,
                recordID: occurrence.id,
                modifiedAt: occurrence.updatedAt
            )
            upsertAutoPaymentSuccessNotification(
                statement,
                modelContext: modelContext,
                calendar: calendar,
                recipientUserID: sessionStore.activeLocalProfileUserID,
                createdAt: paymentTx.updatedAt
            )
        } catch {
            upsertAutoPaymentFailureNotification(
                statement,
                reason: error.localizedDescription,
                modelContext: modelContext,
                recipientUserID: sessionStore.activeLocalProfileUserID,
                calendar: calendar
            )
            markAutoPaymentAttemptFailed(
                occurrence,
                modelContext: modelContext,
                sessionStore: sessionStore
            )
        }
    }

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
        if let createdByUserID = actorUserID ?? subjectUserID {
            try TransactionAuditStore.upsert(
                transactionID: transaction.id,
                createdByUserID: createdByUserID,
                lastModifiedByUserID: actorUserID ?? createdByUserID,
                updatedAt: transaction.updatedAt,
                context: modelContext
            )
        }
        return subjectUserID
    }

    private static func upsertStatementReadyNotification(
        _ statement: PlanningCreditCardStatementSnapshot,
        modelContext: ModelContext,
        recipientUserID: UUID?,
        calendar: Calendar
    ) {
        let statementMonthString = MistiaDateFormatting.statementMonthYearString(
            for: statement.statementMonth,
            calendar: calendar
        )
        upsertNotification(
            key: "mistia.credit.statement.ready.\(statement.walletID.uuidString.lowercased()).\(PlanningLogic.monthKey(for: statement.statementMonth, calendar: calendar))",
            title: L10n.shared.notifications.mistiacreditcardstatementmaintenance.statementReady,
            body: L10n.notifications.creditCard.statementReadyBody(
                statementMonthString,
                statement.walletName,
                statement.amountMinor.formattedCurrency(code: statement.currencyCode),
                MistiaDateFormatting.shortDateString(for: statement.dueDate)
            ),
            kind: .creditCardStatementReady,
            resourceID: statement.walletID,
            modelContext: modelContext,
            createdAt: statement.closingDate,
            recipientUserID: recipientUserID,
            metadataJSON: creditCardMetadataJSON(
                actionKind: .statementReady,
                statement: statement,
                calendar: calendar
            )
        )
    }

    private static func upsertAutoPaymentSuccessNotification(
        _ statement: PlanningCreditCardStatementSnapshot,
        modelContext: ModelContext,
        calendar: Calendar,
        recipientUserID: UUID?,
        createdAt: Date
    ) {
        upsertNotification(
            key: "mistia.credit.autopay.success.\(statement.walletID.uuidString.lowercased()).\(PlanningLogic.monthKey(for: statement.statementMonth))",
            title: L10n.shared.notifications.mistiacreditcardstatementmaintenance.autoPaymentComplete,
            body: L10n.shared.notifications.mistiacreditcardstatementmaintenance.mistiaPaidValueForValue(String(describing: statement.amountMinor.formattedCurrency(code: statement.currencyCode)), String(describing: statement.walletName)),
            kind: .creditCardAutoPaymentSucceeded,
            resourceID: statement.walletID,
            modelContext: modelContext,
            createdAt: createdAt,
            recipientUserID: recipientUserID,
            metadataJSON: creditCardMetadataJSON(
                actionKind: .autoPaymentSucceeded,
                statement: statement,
                calendar: calendar
            )
        )
    }

    private static func upsertAutoPaymentFailureNotification(
        _ statement: PlanningCreditCardStatementSnapshot,
        reason: String,
        modelContext: ModelContext,
        recipientUserID: UUID?,
        calendar: Calendar
    ) {
        let statementMonthString = MistiaDateFormatting.statementMonthYearString(
            for: statement.statementMonth,
            calendar: calendar
        )
        upsertNotification(
            key: "mistia.credit.autopay.failed.\(statement.walletID.uuidString.lowercased()).\(PlanningLogic.monthKey(for: statement.statementMonth))",
            title: L10n.shared.notifications.mistiacreditcardstatementmaintenance.autoPaymentFailed,
            body: L10n.notifications.creditCard.autoPaymentFailedBody(
                statementMonthString,
                statement.walletName,
                reason
            ),
            kind: .creditCardAutoPaymentFailed,
            resourceID: statement.walletID,
            modelContext: modelContext,
            createdAt: Date(),
            recipientUserID: recipientUserID,
            metadataJSON: creditCardMetadataJSON(
                actionKind: .autoPaymentFailed,
                statement: statement,
                calendar: calendar
            )
        )
    }

    private static func upsertNotification(
        key: String,
        title: String,
        body: String,
        kind: MistiaAppNotificationKind,
        resourceID: UUID,
        modelContext: ModelContext,
        createdAt: Date,
        recipientUserID: UUID?,
        metadataJSON: String?
    ) {
        guard MistiaNotificationPreferences.reminderEnabled(.creditCards) else { return }
        guard let recipientUserID else { return }

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
            existing.resourceType = .card
            existing.resourceID = resourceID
            existing.metadataJSON = metadataJSON
            existing.updatedAt = .now
        } else {
            modelContext.insert(AppNotificationRecord(
                key: key,
                createdAt: createdAt,
                updatedAt: .now,
                title: title,
                body: body,
                kind: kind,
                source: .system,
                isRead: false,
                recipientUserID: recipientUserID,
                resourceType: .card,
                resourceID: resourceID,
                metadataJSON: metadataJSON
            ))
        }

        try? modelContext.save()
    }

    private static func removeStaleCreditCardNotifications(
        walletOwnerMap: [UUID: UUID],
        activeUserID: UUID,
        modelContext: ModelContext
    ) {
        let cardResourceTypeRawValue = MistiaFamilyNotificationResourceType.card.rawValue
        let localReminderSourceRawValue = MistiaAppNotificationSource.localReminder.rawValue
        let systemSourceRawValue = MistiaAppNotificationSource.system.rawValue
        let rows = (try? modelContext.fetch(
            FetchDescriptor<AppNotificationRecord>(
                predicate: #Predicate<AppNotificationRecord> { row in
                    row.resourceTypeRawValue == cardResourceTypeRawValue
                        && (
                            row.sourceRawValue == localReminderSourceRawValue
                                || row.sourceRawValue == systemSourceRawValue
                        )
                }
            )
        )) ?? []
        let creditKinds: Set<MistiaAppNotificationKind> = [
            .creditCardStatementReady,
            .creditCardAutoPaymentSucceeded,
            .creditCardAutoPaymentFailed
        ]
        var didDelete = false

        for row in rows where creditKinds.contains(row.kind) {
            guard let resourceID = row.resourceID,
                  let ownerUserID = walletOwnerMap[resourceID],
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

    private static func creditCardMetadataJSON(
        actionKind: CreditCardNotificationActionKind,
        statement: PlanningCreditCardStatementSnapshot,
        calendar: Calendar
    ) -> String? {
        let payload = CreditCardNotificationActionPayload(
            actionKind: actionKind,
            statementMonthKey: PlanningLogic.monthKey(for: statement.statementMonth, calendar: calendar),
            dueDate: statement.dueDate,
            linkedPaymentWalletID: statement.paymentSourceWalletID,
            walletName: statement.walletName,
            currencyCode: statement.currencyCode
        )
        guard let data = try? JSONEncoder.mistiaSyncEncoder.encode(payload) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}
