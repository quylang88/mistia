import Foundation
import SwiftData

@MainActor
enum MistiaCreditCardStatementMaintenance {
    static func run(
        modelContext: ModelContext,
        sessionStore: SessionStore,
        referenceDate: Date = .now,
        calendar: Calendar = MistiaCalendar.current
    ) async {
        let wallets = (try? modelContext.fetch(
            FetchDescriptor<LedgerWallet>(
                predicate: #Predicate { $0.deletedAt == nil && !$0.isArchived }
            )
        )) ?? []
        let transactions = (try? modelContext.fetch(
            FetchDescriptor<LedgerTransaction>(
                predicate: #Predicate { $0.deletedAt == nil && !$0.isArchived }
            )
        )) ?? []
        var occurrences = (try? modelContext.fetch(
            FetchDescriptor<DueOccurrenceRecord>(
                predicate: #Predicate { $0.deletedAt == nil }
            )
        )) ?? []

        let transactionRecords = transactions.map(\.planningRecordSnapshot)
        let accounts = wallets.compactMap { $0.planningCreditCardSnapshot(records: transactionRecords) }
        guard !accounts.isEmpty else { return }

        let currentMonth = PlanningLogic.startOfMonth(for: referenceDate, calendar: calendar)
        let statementMonths = (0...24).compactMap { offset in
            calendar.date(byAdding: .month, value: -offset, to: currentMonth)
        }
        let walletByID = Dictionary(uniqueKeysWithValues: wallets.map { ($0.id, $0) })

        for account in accounts {
            let statements = PlanningLogic.creditCardStatementItems(
                accounts: [account],
                records: transactionRecords,
                occurrences: occurrences.map(\.planningSnapshot),
                statementMonths: statementMonths,
                referenceDate: referenceDate,
                calendar: calendar
            )

            for statement in statements where statement.amountMinor > 0 {
                guard statement.state != .unclosed else { continue }

                let occurrence = upsertClosedStatementOccurrence(
                    statement,
                    occurrences: &occurrences,
                    modelContext: modelContext,
                    sessionStore: sessionStore,
                    calendar: calendar
                )
                upsertStatementReadyNotification(
                    statement,
                    modelContext: modelContext,
                    recipientUserID: sessionStore.activeLocalProfileUserID,
                    calendar: calendar
                )

                let sourceBalanceMinor = paymentSourceBalance(
                    for: statement,
                    walletByID: walletByID,
                    transactions: transactions
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
                        reason: mistiaLocalized(vi: "chưa thiết lập ví liên kết", en: "no linked wallet is set", ja: "連携ウォレットが未設定です"),
                        modelContext: modelContext,
                        recipientUserID: sessionStore.activeLocalProfileUserID,
                        calendar: calendar
                    )
                case .insufficientFunds:
                    upsertAutoPaymentFailureNotification(
                        statement,
                        reason: mistiaLocalized(vi: "ví liên kết không đủ số dư", en: "the linked wallet has insufficient funds", ja: "連携ウォレットの残高が不足しています"),
                        modelContext: modelContext,
                        recipientUserID: sessionStore.activeLocalProfileUserID,
                        calendar: calendar
                    )
                case .payable:
                    await attemptAutoPayment(
                        statement,
                        occurrence: occurrence,
                        wallets: wallets,
                        walletByID: walletByID,
                        transactions: transactions,
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
    ) -> DueOccurrenceRecord {
        let monthKey = PlanningLogic.monthKey(for: statement.statementMonth, calendar: calendar)
        let legacyDueMonthKey = PlanningLogic.monthKey(for: statement.dueDate, calendar: calendar)
        let now = Date()

        if let existing = occurrences.first(where: {
            $0.sourceKind == .creditCard
                && $0.sourceID == statement.walletID
                && ($0.selectedMonthKey == monthKey || $0.selectedMonthKey == legacyDueMonthKey)
        }) {
            var didChange = false
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
                return existing
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
            return existing
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
        return record
    }

    private static func paymentSourceBalance(
        for statement: PlanningCreditCardStatementSnapshot,
        walletByID: [UUID: LedgerWallet],
        transactions: [LedgerTransaction]
    ) -> Int64? {
        guard let sourceWalletID = statement.paymentSourceWalletID,
              let sourceWallet = walletByID[sourceWalletID] else {
            return nil
        }

        return TransactionLogic.effectiveBalance(
            for: TransactionWalletSnapshot(
                id: sourceWallet.id,
                kind: sourceWallet.kind,
                openingBalanceMinor: sourceWallet.openingBalanceMinor
            ),
            records: transactions.map(\.snapshot)
        )
    }

    private static func attemptAutoPayment(
        _ statement: PlanningCreditCardStatementSnapshot,
        occurrence: DueOccurrenceRecord,
        wallets: [LedgerWallet],
        walletByID: [UUID: LedgerWallet],
        transactions: [LedgerTransaction],
        modelContext: ModelContext,
        sessionStore: SessionStore,
        calendar: Calendar
    ) async {
        guard let sourceWalletID = statement.paymentSourceWalletID,
              let sourceWallet = walletByID[sourceWalletID],
              let cardWallet = walletByID[statement.walletID] else {
            upsertAutoPaymentFailureNotification(
                statement,
                reason: mistiaLocalized(vi: "chưa thiết lập ví liên kết", en: "no linked wallet is set", ja: "連携ウォレットが未設定です"),
                modelContext: modelContext,
                recipientUserID: sessionStore.activeLocalProfileUserID,
                calendar: calendar
            )
            return
        }

        let sourceBalanceMinor = TransactionLogic.effectiveBalance(
            for: TransactionWalletSnapshot(
                id: sourceWallet.id,
                kind: sourceWallet.kind,
                openingBalanceMinor: sourceWallet.openingBalanceMinor
            ),
            records: transactions.map(\.snapshot)
        )
        guard sourceBalanceMinor >= statement.amountMinor else {
            upsertAutoPaymentFailureNotification(
                statement,
                reason: mistiaLocalized(vi: "ví liên kết không đủ số dư", en: "the linked wallet has insufficient funds", ja: "連携ウォレットの残高が不足しています"),
                modelContext: modelContext,
                recipientUserID: sessionStore.activeLocalProfileUserID,
                calendar: calendar
            )
            return
        }

        let title = mistiaLocalized(
            vi: "Tự động thanh toán thẻ \(statement.walletName)",
            en: "Auto payment for \(statement.walletName)",
            ja: "\(statement.walletName) の自動支払い"
        )
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
        }
    }

    private static func recordOwnershipAndAudit(
        transaction: LedgerTransaction,
        sourceWalletID: UUID,
        actorUserID: UUID?,
        modelContext: ModelContext
    ) throws -> UUID? {
        let ownershipScopes = try modelContext.fetch(FetchDescriptor<OwnedRecordScope>())
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
            title: mistiaLocalized(vi: "Sao kê đã chốt", en: "Statement ready", ja: "明細が確定しました"),
            body: mistiaLocalized(
                vi: "Số tiền cần thanh toán tháng \(statementMonthString) của thẻ \(statement.walletName) là \(statement.amountMinor.formattedCurrency(code: statement.currencyCode)). Hạn \(MistiaDateFormatting.shortDateString(for: statement.dueDate)).",
                en: "\(statement.walletName) needs \(statement.amountMinor.formattedCurrency(code: statement.currencyCode)) by \(MistiaDateFormatting.shortDateString(for: statement.dueDate)).",
                ja: "\(statement.walletName) は \(MistiaDateFormatting.shortDateString(for: statement.dueDate)) までに \(statement.amountMinor.formattedCurrency(code: statement.currencyCode)) の支払いが必要です。"
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
            title: mistiaLocalized(vi: "Đã tự động thanh toán", en: "Auto payment complete", ja: "自動支払いが完了しました"),
            body: mistiaLocalized(
                vi: "Mistia đã thanh toán \(statement.amountMinor.formattedCurrency(code: statement.currencyCode)) cho thẻ \(statement.walletName).",
                en: "Mistia paid \(statement.amountMinor.formattedCurrency(code: statement.currencyCode)) for \(statement.walletName).",
                ja: "Mistia は \(statement.walletName) に \(statement.amountMinor.formattedCurrency(code: statement.currencyCode)) を支払いました。"
            ),
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
            title: mistiaLocalized(vi: "Tự động thanh toán thất bại", en: "Auto payment failed", ja: "自動支払いに失敗しました"),
            body: mistiaLocalized(
                vi: "Không thể tự động thanh toán sao kê tháng \(statementMonthString) của thẻ \(statement.walletName) vì \(reason). Vui lòng nạp thêm tiền hoặc thanh toán thủ công.",
                en: "Mistia could not auto-pay \(statement.walletName) because \(reason). Please add funds or pay manually.",
                ja: "\(reason) のため \(statement.walletName) の自動支払いができませんでした。入金するか手動で支払ってください。"
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
