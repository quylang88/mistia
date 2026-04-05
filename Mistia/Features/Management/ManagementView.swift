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
    @Query
    private var storedTransactions: [LedgerTransaction]

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
        storedWallets.filter { !$0.isArchived }
    }

    private var visibleCategories: [TransactionCategory] {
        storedCategories.filter { !$0.isArchived && $0.kind == selectedCategoryKind }
    }

    private var dataActions: [ManagementDataActionKind] {
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return ManagementDataActionKind.allCases
        }
        return ManagementDataActionKind.allCases.filter { $0 != .exportData && $0 != .importData && $0 != .backupRestore }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    syncSection

                    walletsSection

                    categoriesSection

                    dataSection
                }
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 32)
            }
            .navigationTitle(mistiaLocalized(vi: "Quản lý", en: "Manage", ja: "管理"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        destination = .settings
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 36, height: 36)
                            .background {
                                Circle().fill(colorScheme == .dark ? .white.opacity(0.12) : .black.opacity(0.06))
                            }
                    }
                    .buttonStyle(.plain)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if !hideQuickCreate {
                        Button {
                            // TODO: Add simple quick capture
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(colorScheme == .dark ? Color(red: 0.90, green: 0.74, blue: 1.00) : .white)
                                .frame(width: 36, height: 36)
                                .background {
                                    Circle().fill(accentPurple)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationDestination(item: $destination) { dest in
                switch dest {
                case .authPlaceholder:
                    ManagementAuthView()
                case .settings:
                    SettingsView()
                case .archivedItems:
                    ManagementArchivedItemsView()
                }
            }
            .sheet(item: $walletEditorTarget) { target in
                ManagementWalletEditorSheet(target: target)
            }
            .sheet(item: $categoryEditorTarget) { target in
                ManagementCategoryEditorSheet(target: target)
            }
            .alert(item: $infoAlert) { alert in
                Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text(mistiaLocalized(vi: "Đã hiểu", en: "Got it", ja: "了解"))))
            }
            .confirmationDialog(
                mistiaLocalized(vi: "Xóa tất cả dữ liệu?", en: "Delete all data?", ja: "すべてのデータを削除しますか？"),
                isPresented: $showsDeleteAllConfirmation,
                titleVisibility: .visible
            ) {
                Button(mistiaLocalized(vi: "Xóa vĩnh viễn", en: "Delete permanently", ja: "完全に削除"), role: .destructive) {
                    deleteAllData()
                }
                Button(mistiaLocalized(vi: "Hủy", en: "Cancel", ja: "キャンセル"), role: .cancel) {}
            } message: {
                Text(mistiaLocalized(vi: "Hành động này sẽ xóa toàn bộ ví, danh mục và giao dịch khỏi thiết bị. Dữ liệu trên server (nếu có) sẽ bị xóa trong lần đồng bộ tiếp theo.", en: "This will remove all wallets, categories, and transactions from this device. Server data (if any) will be deleted on the next sync.", ja: "これにより、このデバイスからすべてのウォレット、カテゴリ、取引が削除されます。サーバー上のデータ（ある場合）は次回の同期時に削除されます。"))
            }
        }
    }

    @ViewBuilder
    private var syncSection: some View {
        Group {
            if sessionStore.isUserSignedIn {
                ManagementSyncStatusCard(
                    accent: accentPurple,
                    tint: cardTint,
                    status: sessionStore.syncStatus,
                    lastSyncAt: sessionStore.lastSyncAt,
                    pendingCount: sessionStore.pendingOutboxItemsCount
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
                            ManagementWalletRow(wallet: wallet, balance: wallet.currentBalance(transactions: storedTransactions)) {
                                walletEditorTarget = ManagementWalletEditorTarget(wallet: wallet, defaultKind: wallet.kind)
                            }

                            if index < activeWallets.count - 1 {
                                Divider()
                                    .padding(.leading, 56)
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
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
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
                                ? ["cart.fill", "fork.knife", "car.fill", "house.fill"]
                                : ["briefcase.fill", "gift.fill", "chart.line.uptrend.xyaxis", "banknote.fill"]
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
                                .padding(.leading, 56)
                        }
                    }
                }
            }
        }
    }

    private func handleDataAction(_ action: ManagementDataActionKind) {
        switch action {
        case .archivedItems:
            destination = .archivedItems
        case .exportData:
            infoAlert = ManagementInfoAlert(
                title: mistiaLocalized(vi: "Sắp ra mắt", en: "Coming soon", ja: "近日公開"),
                message: mistiaLocalized(vi: "Tính năng xuất dữ liệu ra file CSV/JSON đang được phát triển.", en: "Exporting data to CSV/JSON is currently under development.", ja: "CSV/JSONへのデータエクスポート機能は現在開発中です。")
            )
        case .importData:
            infoAlert = ManagementInfoAlert(
                title: mistiaLocalized(vi: "Sắp ra mắt", en: "Coming soon", ja: "近日公開"),
                message: mistiaLocalized(vi: "Tính năng nhập dữ liệu từ hệ thống khác đang được phát triển.", en: "Importing data from other systems is currently under development.", ja: "他のシステムからのデータインポート機能は現在開発中です。")
            )
        case .backupRestore:
            infoAlert = ManagementInfoAlert(
                title: mistiaLocalized(vi: "Sắp ra mắt", en: "Coming soon", ja: "近日公開"),
                message: mistiaLocalized(vi: "Hệ thống backup mã hóa qua iCloud đang được hoàn thiện.", en: "Encrypted iCloud backup is currently being finalized.", ja: "暗号化されたiCloudバックアップシステムは現在最終調整中です。")
            )
        case .deleteAllData:
            showsDeleteAllConfirmation = true
        }
    }

    private func deleteAllData() {
        do {
            let now = Date()

            let wallets = try modelContext.fetch(FetchDescriptor<LedgerWallet>())
            let categories = try modelContext.fetch(FetchDescriptor<TransactionCategory>())
            let transactions = try modelContext.fetch(FetchDescriptor<LedgerTransaction>())

            if sessionStore.isUserSignedIn {
                let mutations: [MistiaSyncMutation] =
                wallets.map {
                    MistiaSyncMutation(entity: .wallet, recordID: $0.id, kind: .delete, modifiedAt: now)
                } +
                categories.map {
                    MistiaSyncMutation(entity: .category, recordID: $0.id, kind: .delete, modifiedAt: now)
                } +
                transactions.map {
                    MistiaSyncMutation(entity: .transaction, recordID: $0.id, kind: .delete, modifiedAt: now)
                }

                if !mutations.isEmpty {
                    sessionStore.recordMutations(mutations)
                }
            }

            for tx in transactions {
                modelContext.delete(tx)
            }

            for category in categories {
                modelContext.delete(category)
            }

            for wallet in wallets {
                modelContext.delete(wallet)
            }

            try modelContext.save()
        } catch {
            infoAlert = ManagementInfoAlert(
                title: mistiaLocalized(vi: "Lỗi", en: "Error", ja: "エラー"),
                message: mistiaLocalized(vi: "Không thể xóa dữ liệu.", en: "Could not delete data.", ja: "データを削除できませんでした。") + " \(error.localizedDescription)"
            )
        }
    }
}

private struct ManagementSection<Content: View>: View {
    let title: String
    let titleColor: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(titleColor)
                .textCase(.uppercase)
                .tracking(0.5)
                .padding(.leading, 4)

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

private struct ManagementSyncStatusCard: View {
    let accent: Color
    let tint: Color
    let status: MistiaSyncStatus
    let lastSyncAt: Date?
    let pendingCount: Int
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var statusIcon: String {
        switch status {
        case .idle: return "checkmark.icloud.fill"
        case .syncing: return "arrow.triangle.2.circlepath.icloud.fill"
        case .error: return "exclamationmark.icloud.fill"
        case .offline: return "xmark.icloud.fill"
        }
    }

    private var statusColor: Color {
        switch status {
        case .idle: return .green
        case .syncing: return accent
        case .error: return .red
        case .offline: return .orange
        }
    }

    private var syncStatusTitle: String {
        switch status {
        case .idle:
            if pendingCount > 0 {
                return mistiaLocalized(vi: "Chờ đồng bộ", en: "Pending sync", ja: "同期待ち")
            }
            return mistiaLocalized(vi: "Đã đồng bộ", en: "Synced", ja: "同期済み")
        case .syncing:
            return mistiaLocalized(vi: "Đang đồng bộ...", en: "Syncing...", ja: "同期中...")
        case .error:
            return mistiaLocalized(vi: "Đồng bộ lỗi", en: "Sync error", ja: "同期エラー")
        case .offline:
            return mistiaLocalized(vi: "Đang ngoại tuyến", en: "Offline", ja: "オフライン")
        }
    }

    private var syncStatusDetail: String {
        if status == .syncing {
            return mistiaLocalized(vi: "Đang cập nhật thay đổi mới nhất", en: "Updating latest changes", ja: "最新の変更を更新中")
        } else if let lastSyncAt {
            return mistiaLocalized(vi: "Cập nhật lần cuối: \(lastSyncAt.formatted(date: .omitted, time: .shortened))", en: "Last updated: \(lastSyncAt.formatted(date: .omitted, time: .shortened))", ja: "最終更新: \(lastSyncAt.formatted(date: .omitted, time: .shortened))")
        } else {
            return mistiaLocalized(vi: "Sẵn sàng đồng bộ", en: "Ready to sync", ja: "同期の準備が完了")
        }
    }

    var body: some View {
        ManagementCard(tint: tint) {
            Button(action: action) {
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(statusColor.opacity(0.12))

                        Image(systemName: statusIcon)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(statusColor)

                        if status == .syncing {
                            Circle()
                                .stroke(statusColor.opacity(0.3), lineWidth: 2)
                                .frame(width: 44, height: 44)
                        }
                    }
                    .frame(width: 40, height: 40)

                    VStack(alignment: .leading, spacing: 3) {
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

    private var badgeFill: Color {
        colorScheme == .dark ? .white.opacity(0.1) : .white
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
