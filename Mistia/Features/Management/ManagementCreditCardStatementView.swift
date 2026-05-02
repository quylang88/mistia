import SwiftData
import SwiftUI

struct ManagementCreditCardStatementView: View {
    @Environment(\.calendar) private var calendar
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Environment(SessionStore.self) private var sessionStore

    let wallet: LedgerWallet

    @Query(filter: #Predicate<LedgerTransaction> { $0.deletedAt == nil && !$0.isArchived })
    private var allTransactions: [LedgerTransaction]

    @State private var selectedMonth = PlanningLogic.startOfMonth(for: .now)
    @State private var showingAlert = false
    @State private var alertMessage = ""

    private var monthYearTitle: String {
        MistiaDateFormatting.monthYearString(for: selectedMonth, calendar: calendar)
    }

    private var availableMonths: [Date] {
        let currentMonth = PlanningLogic.startOfMonth(for: .now, calendar: calendar)
        return (0...24).compactMap { i in
            calendar.date(byAdding: .month, value: -i, to: currentMonth)
        }.reversed()
    }

    private var monthlyTransactions: [LedgerTransaction] {
        allTransactions.filter { tx in
            tx.sourceWallet?.id == wallet.id &&
            tx.primaryKind == .expense &&
            calendar.isDate(tx.occurredAt, equalTo: selectedMonth, toGranularity: .month)
        }.sorted { $0.occurredAt > $1.occurredAt }
    }

    private var totalSpentMinor: Int64 {
        monthlyTransactions.reduce(0) { $0 + $1.amountMinor }
    }

    private var isAlreadyPaid: Bool {
        allTransactions.contains { tx in
            tx.destinationWallet?.id == wallet.id &&
            tx.primaryKind == .transfer &&
            tx.transferSubtype == .internalTransfer &&
            calendar.isDate(tx.occurredAt, equalTo: selectedMonth, toGranularity: .month) &&
            tx.title.contains(mistiaLocalized(vi: "thanh toán thẻ", en: "card payment", ja: "カード支払い"))
        }
    }

    private var accentPurple: Color {
        MistiaAccent.purple.color
    }

    var body: some View {
        VStack(spacing: 0) {
            monthSelector

            TabView(selection: $selectedMonth) {
                ForEach(availableMonths, id: \.self) { month in
                    ScrollView {
                        VStack(spacing: 20) {
                            summaryCardForMonth(month)

                            transactionsSectionForMonth(month)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 20)
                    }
                    .tag(month)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .background(MistiaBackgroundView(tone: .muted))
        .navigationTitle(wallet.name)
        .navigationBarTitleDisplayMode(.inline)
        .alert(mistiaLocalized(vi: "Thông báo", en: "Notice", ja: "お知らせ"), isPresented: $showingAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
    }

    private var monthSelector: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 25) {
                    ForEach(availableMonths, id: \.self) { month in
                        VStack(spacing: 8) {
                            Text(MistiaDateFormatting.monthYearString(for: month, calendar: calendar))
                                .font(.system(size: 15, weight: selectedMonth == month ? .bold : .medium, design: .rounded))
                                .foregroundStyle(selectedMonth == month ? AnyShapeStyle(accentPurple) : AnyShapeStyle(Color.secondary))

                            if selectedMonth == month {
                                Capsule()
                                    .fill(accentPurple)
                                    .frame(width: 40, height: 3)
                            } else {
                                Color.clear.frame(height: 3)
                            }
                        }
                        .id(month)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.snappy) {
                                selectedMonth = month
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }
            .onAppear {
                proxy.scrollTo(selectedMonth, anchor: .center)
            }
            .onChange(of: selectedMonth) { _, newValue in
                proxy.scrollTo(newValue, anchor: .center)
            }
            .background(Color(UIColor.secondarySystemGroupedBackground).opacity(0.5))
            .overlay(alignment: .bottom) {
                Divider()
            }
        }
    }

    private func monthlyTransactions(for month: Date) -> [LedgerTransaction] {
        allTransactions.filter { tx in
            tx.sourceWallet?.id == wallet.id &&
            tx.primaryKind == .expense &&
            calendar.isDate(tx.occurredAt, equalTo: month, toGranularity: .month)
        }.sorted { $0.occurredAt > $1.occurredAt }
    }

    private func totalSpentMinor(for month: Date) -> Int64 {
        monthlyTransactions(for: month).reduce(0) { $0 + $1.amountMinor }
    }

    private func isAlreadyPaid(for month: Date) -> Bool {
        allTransactions.contains { tx in
            tx.destinationWallet?.id == wallet.id &&
            tx.primaryKind == .transfer &&
            tx.transferSubtype == .internalTransfer &&
            calendar.isDate(tx.occurredAt, equalTo: month, toGranularity: .month) &&
            tx.title.contains(mistiaLocalized(vi: "thanh toán thẻ", en: "card payment", ja: "カード支払い"))
        }
    }

    private func summaryCardForMonth(_ month: Date) -> some View {
        let total = totalSpentMinor(for: month)
        let paid = isAlreadyPaid(for: month)

        return MistiaGlassCard(cornerRadius: 24, tint: accentPurple.opacity(0.12)) {
            VStack(spacing: 16) {
                VStack(spacing: 8) {
                    Text(mistiaLocalized(vi: "Tổng chi tiêu", en: "Total spending", ja: "合計支出"))
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)

                    Text(total.formattedCurrency(code: wallet.currencyCode))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                }

                Button {
                    performPayment(for: month, total: total)
                } label: {
                    HStack {
                        if paid {
                            Image(systemName: "checkmark.circle.fill")
                            Text(mistiaLocalized(vi: "Đã thanh toán", en: "Paid", ja: "支払い済み"))
                        } else {
                            Text(mistiaLocalized(vi: "Thanh toán", en: "Pay now", ja: "支払う"))
                        }
                    }
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(paid ? Color.gray.opacity(0.3) : accentPurple)
                    .foregroundStyle(paid ? AnyShapeStyle(Color.secondary) : AnyShapeStyle(Color.white))
                    .clipShape(Capsule())
                }
                .disabled(paid || total <= 0)
            }
            .padding(20)
        }
    }

    private func transactionsSectionForMonth(_ month: Date) -> some View {
        let transactions = monthlyTransactions(for: month)

        return VStack(alignment: .leading, spacing: 12) {
            Text(mistiaLocalized(vi: "Giao dịch chi tiêu", en: "Spending transactions", ja: "利用明細"))
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.leading, 4)

            MistiaBlockCard(cornerRadius: 22, padding: 0) {
                if transactions.isEmpty {
                    Text(mistiaLocalized(vi: "Không có giao dịch nào", en: "No transactions", ja: "取引はありません"))
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(transactions.enumerated()), id: \.element.id) { index, tx in
                            TransactionRow(tx: tx, currencyCode: wallet.currencyCode)

                            if index < transactions.count - 1 {
                                Divider().padding(.leading, 56)
                            }
                        }
                    }
                }
            }
        }
    }

    private func performPayment(for month: Date, total: Int64) {
        guard let sourceWallet = wallet.creditCardProfile?.paymentSourceWallet else {
            alertMessage = mistiaLocalized(vi: "Vui lòng thiết lập ví nguồn thanh toán cho thẻ này trong phần sửa ví.", en: "Please set up a payment source wallet for this card in wallet settings.", ja: "ウォレット設定でこのカードの支払い元ウォレットを設定してください。")
            showingAlert = true
            return
        }

        let sourceBalanceMinor = TransactionLogic.effectiveBalance(
            for: TransactionWalletSnapshot(id: sourceWallet.id, kind: sourceWallet.kind, openingBalanceMinor: sourceWallet.openingBalanceMinor),
            records: allTransactions.map(\.snapshot)
        )

        if sourceBalanceMinor < total {
            alertMessage = mistiaLocalized(vi: "Số dư ví nguồn không đủ để thanh toán.", en: "Insufficient funds in the source wallet.", ja: "支払い元ウォレットの残高が不足しています。")
            showingAlert = true
            return
        }

        let monthStr = MistiaDateFormatting.monthYearString(for: month, calendar: calendar)
        let txTitle = mistiaLocalized(vi: "Thanh toán thẻ tháng \(monthStr)", en: "Card payment for \(monthStr)", ja: "カード支払い \(monthStr)")

        let paymentTx = LedgerTransaction(
            primaryKind: .transfer,
            transferSubtype: .internalTransfer,
            title: txTitle,
            amountMinor: total,
            occurredAt: month == PlanningLogic.startOfMonth(for: .now) ? .now : month,
            sourceWallet: sourceWallet,
            destinationWallet: wallet
        )

        modelContext.insert(paymentTx)

        do {
            try modelContext.save()
            sessionStore.recordUpsert(entity: .transaction, recordID: paymentTx.id, modifiedAt: paymentTx.updatedAt)
            alertMessage = mistiaLocalized(vi: "Đã thanh toán thành công.", en: "Payment successful.", ja: "支払いが完了しました。")
            showingAlert = true
        } catch {
            alertMessage = error.localizedDescription
            showingAlert = true
        }
    }
}

private struct TransactionRow: View {
    let tx: LedgerTransaction
    let currencyCode: String

    var body: some View {
        HStack(spacing: 12) {
            MistiaFinanceIconView(
                icon: tx.category?.iconSymbolName ?? tx.primaryKind.financeIconToken,
                fallbackColor: MistiaAccent.expense.color,
                size: 32
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(tx.title.isEmpty ? (tx.category?.localizedDisplayName ?? "") : tx.title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(MistiaDateFormatting.shortDateString(for: tx.occurredAt))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("-" + tx.amountMinor.formattedCurrency(code: currencyCode))
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(MistiaAccent.expense.color)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}
