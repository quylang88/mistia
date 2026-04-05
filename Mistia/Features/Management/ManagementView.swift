import SwiftData
import SwiftUI

private enum ManagementNavigationDestination: String, Identifiable {
    case authPlaceholder
    case settings
    case archivedItems

    var id: String { rawValue }
}

private struct ManagementInfoAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

struct ManagementView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Environment(SessionStore.self) private var sessionStore

    @AppStorage(MistiaAppStorageKey.hideQuickCreate) private var hideQuickCreate = false

    @Query(sort: [SortDescriptor(\LedgerWallet.sortOrder), SortDescriptor(\LedgerWallet.createdAt)])
    private var storedWallets: [LedgerWallet]
    @Query(sort: [SortDescriptor(\TransactionCategory.createdAt), SortDescriptor(\TransactionCategory.sortOrder)])
    private var storedCategories: [TransactionCategory]

    @State private var destination: ManagementNavigationDestination?
    @State private var walletEditorTarget: ManagementWalletEditorTarget?
    @State private var categoryEditorTarget: ManagementCategoryEditorTarget?
    @State private var selectedCategoryKind: TransactionCategoryKind = .expense
    @State private var infoAlert: ManagementInfoAlert?
    @State private var showsDeleteAllConfirmation = false

    private var cardTint: Color {
        colorScheme == .dark ? .white.opacity(0.018) : .white.opacity(0.12)
    }

    private var sectionLabelColor: Color {
        colorScheme == .dark ? .white.opacity(0.66) : Color(red: 0.36, green: 0.37, blue: 0.43)
    }

    private var accentPurple: Color {
        Color(red: 0.43, green: 0.23, blue: 0.76)
    }

    private var activeWallets: [LedgerWallet] {
        storedWallets
            .filter { !$0.isArchived }
            .sorted {
                if $0.sortOrder != $1.sortOrder {
                    return $0.sortOrder < $1.sortOrder
                }
                return $0.createdAt < $1.createdAt
            }
    }

    private var visibleCategories: [TransactionCategory] {
        storedCategories
            .filter { !$0.isArchived && $0.kind == selectedCategoryKind }
            .sorted {
                if $0.sortOrder != $1.sortOrder {
                    return $0.sortOrder < $1.sortOrder
                }
                return $0.createdAt < $1.createdAt
            }
    }

    private let dataActions = ManagementDataActionKind.allCases

    var body: some View {
        NavigationStack {
            MistiaPinnedTopBarScaffold(
                tone: .muted,
                title: mistiaLocalized(vi: "Quản lý", en: "Manage", ja: "管理"),
                embedsInNavigationStack: false,
                showsLeadingAvatar: false,
                trailingSystemImage: "gearshape",
                onTrailingTap: { destination = .settings },
                contentSpacing: 20
            ) {
                profileSection
                walletsSection
                categoriesSection
                dataSection
            }
            .navigationDestination(item: $destination) { route in
                switch route {
                case .authPlaceholder:
                    ManagementAccountView()
                case .settings:
                    SettingsView()
                case .archivedItems:
                    ManagementArchivedItemsView()
                }
            }
        }
        .sheet(item: $walletEditorTarget) { target in
            ManagementWalletEditorSheet(target: target)
        }
        .sheet(item: $categoryEditorTarget) { target in
            ManagementCategoryEditorSheet(target: target)
        }
        .task {
            do {
                try MistiaBootstrap.seedDefaultCategoriesIfNeeded(modelContext: modelContext)
            } catch {
                infoAlert = ManagementInfoAlert(
                    title: mistiaLocalized(vi: "Không thể khởi tạo danh mục", en: "Couldn't initialize categories", ja: "カテゴリを初期化できませんでした"),
                    message: error.localizedDescription
                )
            }
        }
        .onAppear {
            hideQuickCreate = destination != nil
        }
        .onChange(of: destination, initial: true) { _, newValue in
            hideQuickCreate = newValue != nil
        }
        .onDisappear {
            hideQuickCreate = false
        }
        .alert(item: $infoAlert) { alert in
            Alert(
                title: Text(mistiaCatalog(alert.title)),
                message: Text(mistiaCatalog(alert.message)),
                dismissButton: .default(Text(mistiaLocalized(vi: "OK", en: "OK", ja: "OK")))
            )
        }
        .confirmationDialog(
            mistiaLocalized(vi: "Xóa toàn bộ dữ liệu quản lý?", en: "Delete all management data?", ja: "管理データをすべて削除しますか？"),
            isPresented: $showsDeleteAllConfirmation,
            titleVisibility: .visible
        ) {
            Button(mistiaLocalized(vi: "Xóa toàn bộ dữ liệu", en: "Delete all data", ja: "すべてのデータを削除"), role: .destructive) {
                deleteAllManagementData()
            }

            Button(mistiaLocalized(vi: "Hủy", en: "Cancel", ja: "キャンセル"), role: .cancel) { }
        } message: {
            Text(
                mistiaLocalized(
                    vi: "Hành động này sẽ xóa toàn bộ dữ liệu Mistia đang lưu trên thiết bị này.",
                    en: "This will delete all Mistia data stored on this device.",
                    ja: "この操作により、この端末に保存されている Mistia の全データが削除されます。"
                )
            )
        }
    }

    private var profileSection: some View {
        Group {
            if let summary = sessionStore.summary {
                ManagementProfileCard(
                    summary: summary,
                    syncStatusTitle: sessionStore.syncStatusTitle,
                    syncStatusDetail: sessionStore.syncStatusDetail,
                    tint: cardTint
                ) {
                    destination = .authPlaceholder
                }
            } else {
                ManagementSignedOutCard(accent: accentPurple, tint: cardTint) {
                    destination = .authPlaceholder
                }
            }
        }
    }

    private var walletsSection: some View {
        ManagementSection(title: mistiaLocalized(vi: "Ví", en: "Wallets", ja: "ウォレット"), titleColor: sectionLabelColor) {
            ManagementCard(tint: cardTint) {
                if activeWallets.isEmpty {
                    ManagementEmptyState(
                        title: mistiaLocalized(vi: "Chưa có ví nào", en: "No wallets yet", ja: "ウォレットはまだありません"),
                        message: mistiaLocalized(
                            vi: "Thêm ví tiền mặt, PayPay, ví ngân hàng hoặc credit card để bắt đầu quản lý nguồn tiền.",
                            en: "Add cash, PayPay, bank, or credit card wallets to start managing your money sources.",
                            ja: "現金、PayPay、銀行口座、クレジットカードのウォレットを追加して資金管理を始めましょう。"
                        ),
                        buttonTitle: mistiaLocalized(vi: "Thêm ví", en: "Add wallet", ja: "ウォレットを追加"),
                        accent: accentPurple,
                        symbols: ["banknote.fill", "wallet.pass.fill", "building.columns.fill", "creditcard.fill"]
                    ) {
                        walletEditorTarget = ManagementWalletEditorTarget(wallet: nil, defaultKind: .cash)
                    }
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(activeWallets.enumerated()), id: \.element.id) { index, wallet in
                            ManagementWalletRow(wallet: wallet) {
                                walletEditorTarget = ManagementWalletEditorTarget(wallet: wallet, defaultKind: wallet.kind)
                            }

                            if index < activeWallets.count - 1 {
                                Divider()
                                    .padding(.leading, 52)
                            }
                        }

                        Divider()
                            .padding(.horizontal, 14)

                        ManagementFooterAddButton(
                            title: mistiaLocalized(vi: "Thêm ví", en: "Add wallet", ja: "ウォレットを追加"),
                            accent: accentPurple
                        ) {
                            walletEditorTarget = ManagementWalletEditorTarget(wallet: nil, defaultKind: .cash)
                        }
                    }
                }
            }
        }
    }

    private var categoriesSection: some View {
        ManagementSection(title: mistiaLocalized(vi: "Danh mục", en: "Categories", ja: "カテゴリ"), titleColor: sectionLabelColor) {
            VStack(alignment: .leading, spacing: 12) {
                ManagementCategoryKindPicker(selection: $selectedCategoryKind)

                ManagementCard(tint: cardTint) {
                    if visibleCategories.isEmpty {
                        ManagementEmptyState(
                            title: selectedCategoryKind == .expense
                                ? mistiaLocalized(vi: "Chưa có danh mục chi tiêu", en: "No expense categories yet", ja: "支出カテゴリはまだありません")
                                : mistiaLocalized(vi: "Chưa có danh mục thu nhập", en: "No income categories yet", ja: "収入カテゴリはまだありません"),
                            message: selectedCategoryKind == .expense
                                ? mistiaLocalized(
                                    vi: "Tạo nhóm chi tiêu riêng để giao dịch và ngân sách bám sát cách bạn quản lý hằng ngày.",
                                    en: "Create expense groups so your transactions and budgets match how you manage money every day.",
                                    ja: "支出グループを作成すると、取引や予算を日々の管理方法に合わせやすくなります。"
                                )
                                : mistiaLocalized(
                                    vi: "Tách riêng nguồn thu để nhìn rõ tiền lương, thưởng, freelance hay hoàn tiền.",
                                    en: "Separate your income sources to clearly track salary, bonuses, freelance work, or refunds.",
                                    ja: "収入源を分けておくと、給与、賞与、副業、返金などを分かりやすく把握できます。"
                                ),
                            buttonTitle: mistiaLocalized(vi: "Thêm danh mục", en: "Add category", ja: "カテゴリを追加"),
                            accent: accentPurple,
                            symbols: selectedCategoryKind == .expense
                                ? ["fork.knife", "bag.fill", "airplane", "plus"]
                                : ["briefcase.fill", "gift.fill", "chart.line.uptrend.xyaxis", "plus"]
                        ) {
                            categoryEditorTarget = ManagementCategoryEditorTarget(category: nil, defaultKind: selectedCategoryKind)
                        }
                    } else {
                        VStack(spacing: 0) {
                            LazyVGrid(
                                columns: [
                                    GridItem(.adaptive(minimum: 108, maximum: 148), spacing: 12)
                                ],
                                spacing: 12
                            ) {
                                ForEach(visibleCategories, id: \.id) { category in
                                    ManagementCategoryTile(category: category) {
                                        categoryEditorTarget = ManagementCategoryEditorTarget(category: category, defaultKind: category.kind)
                                    }
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 14)

                            Divider()
                                .padding(.horizontal, 14)

                            ManagementFooterAddButton(
                                title: mistiaLocalized(vi: "Thêm danh mục", en: "Add category", ja: "カテゴリを追加"),
                                accent: accentPurple
                            ) {
                                categoryEditorTarget = ManagementCategoryEditorTarget(category: nil, defaultKind: selectedCategoryKind)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 14)
                        }
                    }
                }
            }
        }
    }

    private var dataSection: some View {
        ManagementSection(title: mistiaLocalized(vi: "Dữ liệu", en: "Data", ja: "データ"), titleColor: sectionLabelColor) {
            ManagementCard(tint: cardTint) {
                VStack(spacing: 0) {
                    ForEach(Array(dataActions.enumerated()), id: \.element.id) { index, action in
                        ManagementActionRow(action: action) {
                            handleDataAction(action)
                        }

                        if index < dataActions.count - 1 {
                            Divider()
                                .padding(.leading, 52)
                        }
                    }
                }
            }
        }
    }

    private func handleDataAction(_ action: ManagementDataActionKind) {
        switch action {
        case .exportData:
            infoAlert = ManagementInfoAlert(
                title: action.title,
                message: mistiaLocalized(
                    vi: "Flow export sẽ được nối ở pha sau. Dữ liệu quản lý hiện đã được lưu local bằng SwiftData.",
                    en: "The export flow will be connected later. Management data is currently stored locally with SwiftData.",
                    ja: "書き出しフローは後続フェーズで追加されます。管理データは現在 SwiftData でローカル保存されています。"
                )
            )
        case .importData:
            infoAlert = ManagementInfoAlert(
                title: action.title,
                message: mistiaLocalized(
                    vi: "Flow import chưa được bật trong build này.",
                    en: "The import flow isn't enabled in this build yet.",
                    ja: "このビルドでは取り込みフローはまだ有効になっていません。"
                )
            )
        case .backupRestore:
            infoAlert = ManagementInfoAlert(
                title: action.title,
                message: mistiaLocalized(
                    vi: "Backup & khôi phục sẽ được nối sau khi chốt chiến lược sync.",
                    en: "Backup and restore will be added after the sync strategy is finalized.",
                    ja: "バックアップと復元は同期戦略の確定後に追加されます。"
                )
            )
        case .archivedItems:
            destination = .archivedItems
        case .deleteAllData:
            showsDeleteAllConfirmation = true
        }
    }

    private func deleteAllManagementData() {
        do {
            let now = Date()
            let wallets = try modelContext.fetch(FetchDescriptor<LedgerWallet>())
            let categories = try modelContext.fetch(FetchDescriptor<TransactionCategory>())
            let creditProfiles = try modelContext.fetch(FetchDescriptor<CreditCardProfile>())
            let transactions = try modelContext.fetch(FetchDescriptor<LedgerTransaction>())
            let budgets = try modelContext.fetch(FetchDescriptor<BudgetPlan>())
            let goals = try modelContext.fetch(FetchDescriptor<SavingsGoal>())
            let recurringBills = try modelContext.fetch(FetchDescriptor<RecurringBillPlan>())
            let installments = try modelContext.fetch(FetchDescriptor<InstallmentPlan>())
            let dueOccurrences = try modelContext.fetch(FetchDescriptor<DueOccurrenceRecord>())
            let mutations =
                wallets.map {
                    MistiaSyncMutation(entity: .wallet, recordID: $0.id, kind: .delete, modifiedAt: now)
                }
                + categories.map {
                    MistiaSyncMutation(entity: .category, recordID: $0.id, kind: .delete, modifiedAt: now)
                }
                + creditProfiles.map {
                    MistiaSyncMutation(entity: .creditCardProfile, recordID: $0.id, kind: .delete, modifiedAt: now)
                }
                + transactions.map {
                    MistiaSyncMutation(entity: .transaction, recordID: $0.id, kind: .delete, modifiedAt: now)
                }
                + budgets.map {
                    MistiaSyncMutation(entity: .budgetPlan, recordID: $0.id, kind: .delete, modifiedAt: now)
                }
                + goals.map {
                    MistiaSyncMutation(entity: .savingsGoal, recordID: $0.id, kind: .delete, modifiedAt: now)
                }
                + recurringBills.map {
                    MistiaSyncMutation(entity: .recurringBillPlan, recordID: $0.id, kind: .delete, modifiedAt: now)
                }
                + installments.map {
                    MistiaSyncMutation(entity: .installmentPlan, recordID: $0.id, kind: .delete, modifiedAt: now)
                }
                + dueOccurrences.map {
                    MistiaSyncMutation(entity: .dueOccurrenceRecord, recordID: $0.id, kind: .delete, modifiedAt: now)
                }

            for wallet in wallets {
                modelContext.delete(wallet)
            }

            for category in categories {
                modelContext.delete(category)
            }

            for profile in creditProfiles {
                modelContext.delete(profile)
            }

            for transaction in transactions {
                modelContext.delete(transaction)
            }

            for budget in budgets {
                modelContext.delete(budget)
            }

            for goal in goals {
                modelContext.delete(goal)
            }

            for recurringBill in recurringBills {
                modelContext.delete(recurringBill)
            }

            for installment in installments {
                modelContext.delete(installment)
            }

            for occurrence in dueOccurrences {
                modelContext.delete(occurrence)
            }

            try modelContext.save()
            sessionStore.recordMutations(mutations)

            infoAlert = ManagementInfoAlert(
                title: mistiaLocalized(vi: "Đã xóa dữ liệu", en: "Data deleted", ja: "データを削除しました"),
                message: mistiaLocalized(
                    vi: "Toàn bộ dữ liệu Mistia trong máy hiện tại đã được xóa.",
                    en: "All Mistia data on this device has been deleted.",
                    ja: "この端末の Mistia データをすべて削除しました。"
                )
            )
        } catch {
            infoAlert = ManagementInfoAlert(
                title: mistiaLocalized(vi: "Không thể xóa dữ liệu", en: "Couldn't delete data", ja: "データを削除できませんでした"),
                message: error.localizedDescription
            )
        }
    }
}

struct ManagementSection<Content: View>: View {
    let title: String
    let titleColor: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(titleColor)
                .padding(.horizontal, 2)

            content
        }
    }
}

private struct ManagementCard<Content: View>: View {
    let tint: Color
    @ViewBuilder let content: Content

    var body: some View {
        content
            .background {
                ManagementCardBackground(tint: tint)
            }
    }
}

private struct ManagementProfileCard: View {
    let summary: SessionSummary
    let syncStatusTitle: String
    let syncStatusDetail: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ManagementCard(tint: tint) {
                HStack(spacing: 14) {
                    MistiaAvatarBadge(
                        initials: summary.initials,
                        avatarURL: summary.avatarURL,
                        size: 50,
                        showsStatus: false
                    )

                    VStack(alignment: .leading, spacing: 5) {
                        Text(summary.displayName)
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)

                        Text(summary.email)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)

                        Text(syncStatusTitle)
                            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color(red: 0.43, green: 0.23, blue: 0.76))
                            .padding(.top, 2)

                        Text(syncStatusDetail)
                            .font(.system(size: 12.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
            }
        }
        .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 20))
    }
}

private struct ManagementSignedOutCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let accent: Color
    let tint: Color
    let action: () -> Void

    private var badgeFill: LinearGradient {
        LinearGradient(
            colors: [
                accent.opacity(colorScheme == .dark ? 0.46 : 0.18),
                accent.opacity(colorScheme == .dark ? 0.24 : 0.08)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var badgeForeground: Color {
        colorScheme == .dark ? Color(red: 0.90, green: 0.74, blue: 1.00) : accent
    }

    private var buttonFill: Color {
        colorScheme == .dark ? .white.opacity(0.12) : .black.opacity(0.08)
    }

    private var buttonForeground: Color {
        colorScheme == .dark ? Color(red: 0.90, green: 0.74, blue: 1.00) : accent
    }

    var body: some View {
        ManagementCard(tint: tint) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(badgeFill)

                        Circle()
                            .strokeBorder(.white.opacity(colorScheme == .dark ? 0.12 : 0.24), lineWidth: 0.8)

                        Image(systemName: "person.crop.circle.fill.badge.plus")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(badgeForeground)
                    }
                    .frame(width: 54, height: 54)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(mistiaLocalized(vi: "Đăng nhập để đồng bộ dữ liệu", en: "Sign in to sync your data", ja: "ログインしてデータを同期"))
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        Text(
                            mistiaLocalized(
                                vi: "Lưu an toàn ví, danh mục và sẵn sàng cho backup hoặc sync ở các bản sau.",
                                en: "Keep your wallets and categories safe, ready for backup or sync in future versions.",
                                ja: "ウォレットとカテゴリを安全に保持し、今後のバックアップや同期に備えます。"
                            )
                        )
                            .font(.system(size: 13.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Button(action: action) {
                    Text(mistiaLocalized(vi: "Đăng nhập hoặc tạo tài khoản", en: "Sign in or create an account", ja: "ログインまたはアカウント作成"))
                        .font(.system(size: 15.5, weight: .bold, design: .rounded))
                        .foregroundStyle(buttonForeground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background {
                            Capsule()
                                .fill(buttonFill)
                        }
                }
                .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 22, tint: buttonForeground))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
        }
    }
}

private struct ManagementWalletRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let wallet: LedgerWallet
    let balance: Int64
    let action: () -> Void

    private var balanceColor: Color {
        let lowThreshold: Int64 = wallet.currencyCode == "VND" ? 100_000 : 1_000
        if balance < lowThreshold {
            return Color(red: 0.96, green: 0.36, blue: 0.49)
        } else {
            return colorScheme == .dark ? Color(red: 0.34, green: 0.82, blue: 1.0) : Color(red: 0.18, green: 0.67, blue: 0.62)
        }
    }
    let wallet: LedgerWallet
    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                ManagementIconTile(icon: wallet.iconSymbolName, color: wallet.iconColor)

                VStack(alignment: .leading, spacing: 3) {
                    Text(wallet.name)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)

                    if let subtitle = wallet.subtitleText {
                        Text(subtitle)
                            .font(.system(size: 12.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    if let footnote = wallet.footnoteText {
                        Text(footnote)
                            .font(.system(size: 12.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 8)

                Text(balance.formattedCurrency(code: wallet.currencyCode))
                    .font(.system(size: 15.5, weight: .bold, design: .rounded))
                    .foregroundStyle(balanceColor)
                    .padding(.top, 1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
        .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 16))
    }
}

private struct ManagementCategoryRow: View {
    let category: TransactionCategory
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ManagementIconTile(icon: category.iconSymbolName, color: category.iconColor)

                Text(category.localizedDisplayName)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                Spacer()

                ManagementChevron()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
        .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 16))
    }
}

private struct ManagementCategoryTile: View {
    @Environment(\.colorScheme) private var colorScheme

    let category: TransactionCategory
    let action: () -> Void

    private var tileFill: Color {
        colorScheme == .dark ? .white.opacity(0.05) : .black.opacity(0.035)
    }

    private var tileStroke: Color {
        colorScheme == .dark ? .white.opacity(0.08) : .white.opacity(0.22)
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .center, spacing: 10) {
                ManagementIconTile(icon: category.iconSymbolName, color: category.iconColor)

                Text(category.localizedDisplayName)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(tileFill)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(tileStroke, lineWidth: 0.8)
            }
        }
        .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 18))
    }
}

private struct ManagementActionRow: View {
    let action: ManagementDataActionKind
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ManagementIconTile(icon: action.iconSymbolName, color: action.tintColor)

                Text(action.title)
                    .font(.system(size: 15.5, weight: .medium, design: .rounded))
                    .foregroundStyle(action == .deleteAllData ? action.tintColor : .primary)

                Spacer()

                ManagementChevron()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
        }
        .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 16))
    }
}

private struct ManagementFooterAddButton: View {
    let title: String
    let accent: Color
    let action: () -> Void

    var body: some View {
        MistiaFooterAddButton(title: title, accent: accent, action: action)
    }
}

private struct ManagementEmptyState: View {
    let title: String
    let message: String
    let buttonTitle: String
    let accent: Color
    let symbols: [String]
    let action: () -> Void

    var body: some View {
        MistiaEmptyStateContent(
            title: title,
            message: message,
            buttonTitle: buttonTitle,
            accent: accent,
            symbols: symbols,
            action: action
        )
    }
}

private struct ManagementCategoryKindPicker: View {
    @Binding var selection: TransactionCategoryKind

    private var accentPurple: Color {
        Color(red: 0.43, green: 0.23, blue: 0.76)
    }

    var body: some View {
        MistiaNativeSegmentedControl(
            selection: $selection,
            options: TransactionCategoryKind.allCases,
            title: \.title,
            accent: accentPurple
        )
    }
}

private struct ManagementIconTile: View {
    let icon: String
    let color: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(color.opacity(0.14))

            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(color)
        }
        .frame(width: 30, height: 30)
    }
}

private struct ManagementChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.tertiary)
    }
}

private struct ManagementCardBackground: View {
    let tint: Color

    var body: some View {
        MistiaBlockCardBackground(tint: tint, cornerRadius: 20)
    }
}
