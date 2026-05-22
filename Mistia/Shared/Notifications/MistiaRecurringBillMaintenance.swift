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

        guard !snapshot.activeBills.isEmpty else { return }

        let selectedMonth = PlanningLogic.startOfMonth(for: referenceDate, calendar: calendar)
        let previousMonth = calendar.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth
        let startOfToday = calendar.startOfDay(for: referenceDate)

        for bill in snapshot.activeBills {
            let snap = bill.planningSnapshot
            let dueItems = [previousMonth, selectedMonth]
                .flatMap { month in
                    PlanningLogic.recurringBillDueItems(
                        bills: [snap],
                        occurrences: snapshot.activeOccurrenceSnapshots,
                        selectedMonth: month,
                        calendar: calendar
                    )
                }
                .filter { $0.status == .pending }

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
                            title: mistiaLocalized(vi: "Không thể tự động thanh toán", en: "Auto payment failed", ja: "自動支払いに失敗しました"),
                            body: mistiaLocalized(
                                vi: "Ví không đủ số dư để thanh toán \(bill.name). Vui lòng nạp thêm hoặc thanh toán thủ công.",
                                en: "Insufficient balance to auto-pay \(bill.name). Please top up or pay manually.",
                                ja: "\(bill.name) の自動支払いに必要な残高がありません。入金するか手動で支払ってください。"
                            ),
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
                        title: mistiaLocalized(vi: "Không thể tự động thanh toán", en: "Auto payment failed", ja: "自動支払いに失敗しました"),
                        body: mistiaLocalized(
                            vi: "\(bill.name) thiếu số tiền hoặc ví thanh toán để tự động thanh toán.",
                            en: "\(bill.name) is missing an amount or payment wallet for auto payment.",
                            ja: "\(bill.name) の自動支払いに必要な金額またはウォレットが不足しています。"
                        ),
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
                        ? mistiaLocalized(vi: "Hóa đơn đến hạn hôm nay", en: "Bill due today", ja: "請求の支払期限日です")
                        : mistiaLocalized(vi: "Đến ngày thanh toán", en: "Payment date", ja: "支払開始日です")
                    let body: String
                    if let amountText {
                        body = dueItem.hasExplicitDueDate
                            ? mistiaLocalized(
                                vi: "\(bill.name) (\(amountText)) cần được thanh toán trước \(MistiaDateFormatting.shortDateString(for: dueItem.dueDate)).",
                                en: "\(bill.name) (\(amountText)) is due by \(MistiaDateFormatting.shortDateString(for: dueItem.dueDate)).",
                                ja: "\(bill.name) は \(MistiaDateFormatting.shortDateString(for: dueItem.dueDate)) までに \(amountText) の支払いが必要です。"
                            )
                            : mistiaLocalized(
                                vi: "\(bill.name) (\(amountText)) cần được thanh toán hôm nay.",
                                en: "\(bill.name) (\(amountText)) is ready to pay today.",
                                ja: "\(bill.name) は本日 \(amountText) の支払いが必要です。"
                            )
                    } else {
                        body = dueItem.hasExplicitDueDate
                            ? mistiaLocalized(
                                vi: "\(bill.name) cần được thanh toán trước \(MistiaDateFormatting.shortDateString(for: dueItem.dueDate)).",
                                en: "\(bill.name) is due by \(MistiaDateFormatting.shortDateString(for: dueItem.dueDate)).",
                                ja: "\(bill.name) は \(MistiaDateFormatting.shortDateString(for: dueItem.dueDate)) までに支払いが必要です。"
                            )
                            : mistiaLocalized(
                                vi: "\(bill.name) cần được thanh toán hôm nay.",
                                en: "\(bill.name) is ready to pay today.",
                                ja: "\(bill.name) は本日支払いが必要です。"
                            )
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
                        body = mistiaLocalized(
                            vi: "\(bill.name) (\(amountText)) đã quá hạn thanh toán.",
                            en: "\(bill.name) (\(amountText)) is past its due date.",
                            ja: "\(bill.name) (\(amountText)) の支払い期限を過ぎています。"
                        )
                    } else {
                        body = mistiaLocalized(
                            vi: "\(bill.name) đã quá hạn thanh toán.",
                            en: "\(bill.name) is past its due date.",
                            ja: "\(bill.name) の支払い期限を過ぎています。"
                        )
                    }

                    upsertNotification(
                        key: "mistia.bill.overdue.\(bill.id.uuidString.lowercased()).\(cycleMonthKey)",
                        title: mistiaLocalized(vi: "Hóa đơn quá hạn", en: "Bill overdue", ja: "請求が延滞しています"),
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
        let title = mistiaLocalized(
            vi: "Tự động thanh toán \(bill.name)",
            en: "Auto-paid \(bill.name)",
            ja: "\(bill.name) を自動支払いしました"
        )
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
                recipientUserID: sessionStore.activeLocalProfileUserID,
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
        let rows = (try? modelContext.fetch(FetchDescriptor<AppNotificationRecord>())) ?? []
        let billKinds: Set<MistiaAppNotificationKind> = [
            .billPaymentRequired,
            .billAutoPaymentSucceeded,
            .billAutoPaymentFailed,
            .billOverdue
        ]
        var didDelete = false

        for row in rows
            where (row.source == .system || row.source == .localReminder)
            && row.resourceType == .bill
            && billKinds.contains(row.kind) {
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
