import Foundation
import SwiftData

@MainActor
enum MistiaRecurringBillMaintenance {

    // MARK: - Main entrypoint

    static func run(
        modelContext: ModelContext,
        sessionStore: SessionStore,
        referenceDate: Date = .now,
        calendar: Calendar = .current
    ) async {
        let bills = (try? modelContext.fetch(
            FetchDescriptor<RecurringBillPlan>(
                predicate: #Predicate { $0.deletedAt == nil && !$0.isArchived }
            )
        )) ?? []

        guard !bills.isEmpty else { return }

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

        let occurrences = (try? modelContext.fetch(
            FetchDescriptor<DueOccurrenceRecord>(
                predicate: #Predicate { $0.deletedAt == nil }
            )
        )) ?? []

        let transactionRecords = transactions.map(\.snapshot)
        let occurrenceSnaps = occurrences.map(\.planningSnapshot)
        let walletByID = Dictionary(uniqueKeysWithValues: wallets.map { ($0.id, $0) })
        let selectedMonth = PlanningLogic.startOfMonth(for: referenceDate, calendar: calendar)
        let startOfToday = calendar.startOfDay(for: referenceDate)
        let monthKey = PlanningLogic.monthKey(for: referenceDate, calendar: calendar)

        for bill in bills {
            let snap = bill.planningSnapshot
            let dueItems = PlanningLogic.recurringBillDueItems(
                bills: [snap],
                occurrences: occurrenceSnaps,
                selectedMonth: selectedMonth,
                calendar: calendar
            )
            guard let dueItem = dueItems.first, dueItem.status == .pending else { continue }
            guard PlanningLogic.startOfMonth(for: dueItem.dueDate, calendar: calendar) == selectedMonth else {
                continue
            }

            let requiresAmountInput = dueItem.amountMinor == nil
            let hasSufficientSetup = dueItem.amountMinor != nil && snap.paymentWalletID != nil

            if hasSufficientSetup,
               let amount = dueItem.amountMinor,
               let walletID = snap.paymentWalletID,
               let paymentWallet = walletByID[walletID] {

                let canPay = balanceSufficientToCover(
                    amount: amount,
                    wallet: paymentWallet,
                    records: transactionRecords
                )

                if canPay {
                    await attemptAutoPay(
                        bill: bill,
                        dueItem: dueItem,
                        paymentWallet: paymentWallet,
                        amount: amount,
                        monthKey: monthKey,
                        wallets: wallets,
                        occurrences: occurrences,
                        modelContext: modelContext,
                        sessionStore: sessionStore,
                        referenceDate: referenceDate
                    )
                } else {
                    upsertNotification(
                        key: "mistia.bill.autopay.failed.\(bill.id.uuidString.lowercased()).\(monthKey)",
                        title: mistiaLocalized(vi: "Không thể tự động thanh toán", en: "Auto payment failed", ja: "自動支払いに失敗しました"),
                        body: mistiaLocalized(
                            vi: "Ví không đủ số dư để thanh toán \(bill.name). Vui lòng nạp thêm hoặc thanh toán thủ công.",
                            en: "Insufficient balance to auto-pay \(bill.name). Please top up or pay manually.",
                            ja: "\(bill.name) の自動支払いに必要な残高がありません。入金するか手動で支払ってください。"
                        ),
                        kind: .billAutoPaymentFailed,
                        bill: bill,
                        dueItem: dueItem,
                        monthKey: monthKey,
                        modelContext: modelContext
                    )
                }
            } else if requiresAmountInput || snap.paymentWalletID == nil {
                // Variable-amount bill or no payment wallet — needs user action
                upsertNotification(
                    key: "mistia.bill.payment.required.\(bill.id.uuidString.lowercased()).\(monthKey)",
                    title: mistiaLocalized(vi: "Hóa đơn sắp đến hạn", en: "Bill due soon", ja: "請求の支払い期限が近づいています"),
                    body: mistiaLocalized(
                        vi: "\(bill.name) cần được thanh toán trước \(MistiaDateFormatting.shortDateString(for: dueItem.dueDate)).",
                        en: "\(bill.name) is due by \(MistiaDateFormatting.shortDateString(for: dueItem.dueDate)).",
                        ja: "\(bill.name) は \(MistiaDateFormatting.shortDateString(for: dueItem.dueDate)) までに支払いが必要です。"
                    ),
                    kind: .billPaymentRequired,
                    bill: bill,
                    dueItem: dueItem,
                    monthKey: monthKey,
                    modelContext: modelContext
                )
            }

            // Overdue handling — resurface daily until paid
            if dueItem.dueDate < startOfToday {
                upsertNotification(
                    key: "mistia.bill.overdue.\(bill.id.uuidString.lowercased()).\(monthKey)",
                    title: mistiaLocalized(vi: "Hóa đơn quá hạn", en: "Bill overdue", ja: "請求が延滞しています"),
                    body: mistiaLocalized(
                        vi: "\(bill.name) đã quá hạn thanh toán.",
                        en: "\(bill.name) is past its due date.",
                        ja: "\(bill.name) の支払い期限を過ぎています。"
                    ),
                    kind: .billOverdue,
                    bill: bill,
                    dueItem: dueItem,
                    monthKey: monthKey,
                    modelContext: modelContext,
                    forceUnread: true
                )
            }
        }
    }

    // MARK: - Auto-pay

    private static func attemptAutoPay(
        bill: RecurringBillPlan,
        dueItem: PlanningRecurringDueSnapshot,
        paymentWallet: LedgerWallet,
        amount: Int64,
        monthKey: String,
        wallets: [LedgerWallet],
        occurrences: [DueOccurrenceRecord],
        modelContext: ModelContext,
        sessionStore: SessionStore,
        referenceDate: Date
    ) async {
        let now = Date()
        let title = mistiaLocalized(
            vi: "Tự động thanh toán \(bill.name)",
            en: "Auto-paid \(bill.name)",
            ja: "\(bill.name) を自動支払いしました"
        )
        let tx = LedgerTransaction(
            primaryKind: .expense,
            title: title,
            amountMinor: amount,
            occurredAt: dueItem.dueDate,
            sourceWallet: paymentWallet
        )
        tx.updatedAt = now

        // Set category from bill
        if let category = bill.category {
            tx.category = category
        }

        modelContext.insert(tx)

        // Mark occurrence paid
        let selectedMonth = PlanningLogic.startOfMonth(for: dueItem.dueDate)

        do {
            _ = try PlanningPersistenceSupport.upsertOccurrence(
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
                recordID: tx.id,  // occurrence ID resolved in upsert
                modifiedAt: tx.updatedAt
            )

            upsertNotification(
                key: "mistia.bill.autopay.success.\(bill.id.uuidString.lowercased()).\(monthKey)",
                title: mistiaLocalized(vi: "Đã tự động thanh toán", en: "Auto payment complete", ja: "自動支払いが完了しました"),
                body: mistiaLocalized(
                    vi: "Mistia đã thanh toán \(amount.formattedCurrency(code: bill.currencyCode)) cho \(bill.name).",
                    en: "Mistia paid \(amount.formattedCurrency(code: bill.currencyCode)) for \(bill.name).",
                    ja: "Mistia は \(bill.name) に \(amount.formattedCurrency(code: bill.currencyCode)) を支払いました。"
                ),
                kind: .billAutoPaymentSucceeded,
                bill: bill,
                dueItem: dueItem,
                monthKey: monthKey,
                modelContext: modelContext
            )
        } catch {
            upsertNotification(
                key: "mistia.bill.autopay.failed.\(bill.id.uuidString.lowercased()).\(monthKey)",
                title: mistiaLocalized(vi: "Không thể tự động thanh toán", en: "Auto payment failed", ja: "自動支払いに失敗しました"),
                body: mistiaLocalized(
                    vi: "Lỗi khi thanh toán \(bill.name): \(error.localizedDescription)",
                    en: "Failed to auto-pay \(bill.name): \(error.localizedDescription)",
                    ja: "\(bill.name) の自動支払いに失敗しました: \(error.localizedDescription)"
                ),
                kind: .billAutoPaymentFailed,
                bill: bill,
                dueItem: dueItem,
                monthKey: monthKey,
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
        let existing = (try? modelContext.fetch(FetchDescriptor<AppNotificationRecord>())) ?? []
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

    // MARK: - Notification upsert

    private static func upsertNotification(
        key: String,
        title: String,
        body: String,
        kind: MistiaAppNotificationKind,
        bill: RecurringBillPlan,
        dueItem: PlanningRecurringDueSnapshot,
        monthKey: String,
        modelContext: ModelContext,
        forceUnread: Bool = false
    ) {
        guard MistiaNotificationPreferences.reminderEnabled(.bills) else { return }

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
        records: [TransactionRecordSnapshot]
    ) -> Bool {
        if wallet.kind == .creditCard {
            guard let profile = wallet.creditCardProfile else { return false }
            let debt = max(
                TransactionLogic.effectiveBalance(
                    for: TransactionWalletSnapshot(
                        id: wallet.id,
                        kind: .creditCard,
                        openingBalanceMinor: wallet.openingBalanceMinor
                    ),
                    records: records
                ),
                0
            )
            return (profile.creditLimitMinor - debt) >= amount
        } else {
            let balance = TransactionLogic.effectiveBalance(
                for: TransactionWalletSnapshot(
                    id: wallet.id,
                    kind: wallet.kind,
                    openingBalanceMinor: wallet.openingBalanceMinor
                ),
                records: records
            )
            return balance >= amount
        }
    }

    // MARK: - Ownership & audit (mirrors MistiaCreditCardStatementMaintenance)

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
}
