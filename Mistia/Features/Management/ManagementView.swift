import SwiftData
import SwiftUI

private enum ManagementNavigationDestination: String, Identifiable {
    case authPlaceholder
    case settings

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

    @Query(sort: [SortDescriptor(\LedgerAccount.sortOrder), SortDescriptor(\LedgerAccount.createdAt)])
    private var storedAccounts: [LedgerAccount]
    @Query(sort: [SortDescriptor(\TransactionCategory.createdAt), SortDescriptor(\TransactionCategory.sortOrder)])
    private var storedCategories: [TransactionCategory]

    @State private var destination: ManagementNavigationDestination?
    @State private var accountEditorTarget: ManagementAccountEditorTarget?
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

    private var activeAccounts: [LedgerAccount] {
        storedAccounts
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
                title: "Quản lý",
                embedsInNavigationStack: false,
                showsLeadingAvatar: false,
                trailingSystemImage: "gearshape",
                onTrailingTap: { destination = .settings },
                contentSpacing: 20
            ) {
                profileSection
                accountsSection
                categoriesSection
                dataSection
            }
            .navigationDestination(item: $destination) { route in
                switch route {
                case .authPlaceholder:
                    ManagementAuthPlaceholderView()
                case .settings:
                    SettingsView()
                }
            }
        }
        .sheet(item: $accountEditorTarget) { target in
            ManagementAccountEditorSheet(target: target)
        }
        .sheet(item: $categoryEditorTarget) { target in
            ManagementCategoryEditorSheet(target: target)
        }
        .task {
            do {
                try MistiaBootstrap.seedDefaultCategoriesIfNeeded(modelContext: modelContext)
            } catch {
                infoAlert = ManagementInfoAlert(
                    title: "Không thể khởi tạo danh mục",
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
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .confirmationDialog(
            "Xóa toàn bộ dữ liệu quản lý?",
            isPresented: $showsDeleteAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Xóa tài khoản và danh mục", role: .destructive) {
                deleteAllManagementData()
            }

            Button("Hủy", role: .cancel) { }
        } message: {
            Text("Hành động này sẽ xóa tất cả tài khoản và danh mục đang lưu trên thiết bị.")
        }
    }

    private var profileSection: some View {
        Group {
            if let summary = sessionStore.summary {
                ManagementProfileCard(summary: summary, tint: cardTint)
            } else {
                ManagementSignedOutCard(accent: accentPurple, tint: cardTint) {
                    destination = .authPlaceholder
                }
            }
        }
    }

    private var accountsSection: some View {
        ManagementSection(title: "Tài khoản", titleColor: sectionLabelColor) {
            ManagementCard(tint: cardTint) {
                if activeAccounts.isEmpty {
                    ManagementEmptyState(
                        title: "Chưa có tài khoản nào",
                        message: "Thêm ví tiền mặt, PayPay, tài khoản ngân hàng hoặc credit card để bắt đầu quản lý nguồn tiền.",
                        buttonTitle: "Thêm tài khoản",
                        accent: accentPurple,
                        symbols: ["banknote.fill", "wallet.pass.fill", "building.columns.fill", "creditcard.fill"]
                    ) {
                        accountEditorTarget = ManagementAccountEditorTarget(account: nil, defaultKind: .cash)
                    }
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(activeAccounts.enumerated()), id: \.element.id) { index, account in
                            ManagementAccountRow(account: account) {
                                accountEditorTarget = ManagementAccountEditorTarget(account: account, defaultKind: account.kind)
                            }

                            if index < activeAccounts.count - 1 {
                                Divider()
                                    .padding(.leading, 52)
                            }
                        }

                        Divider()
                            .padding(.horizontal, 14)

                        ManagementFooterAddButton(
                            title: "Thêm tài khoản",
                            accent: accentPurple
                        ) {
                            accountEditorTarget = ManagementAccountEditorTarget(account: nil, defaultKind: .cash)
                        }
                    }
                }
            }
        }
    }

    private var categoriesSection: some View {
        ManagementSection(title: "Danh mục", titleColor: sectionLabelColor) {
            VStack(alignment: .leading, spacing: 12) {
                ManagementCategoryKindPicker(selection: $selectedCategoryKind)

                ManagementCard(tint: cardTint) {
                    if visibleCategories.isEmpty {
                        ManagementEmptyState(
                            title: selectedCategoryKind == .expense
                                ? "Chưa có danh mục chi tiêu"
                                : "Chưa có danh mục thu nhập",
                            message: selectedCategoryKind == .expense
                                ? "Tạo nhóm chi tiêu riêng để giao dịch và ngân sách bám sát cách bạn quản lý hằng ngày."
                                : "Tách riêng nguồn thu để nhìn rõ tiền lương, thưởng, freelance hay hoàn tiền.",
                            buttonTitle: "Thêm danh mục",
                            accent: accentPurple,
                            symbols: selectedCategoryKind == .expense
                                ? ["fork.knife", "bag.fill", "airplane", "plus"]
                                : ["briefcase.fill", "gift.fill", "chart.line.uptrend.xyaxis", "plus"]
                        ) {
                            categoryEditorTarget = ManagementCategoryEditorTarget(category: nil, defaultKind: selectedCategoryKind)
                        }
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(visibleCategories.enumerated()), id: \.element.id) { index, category in
                                ManagementCategoryRow(category: category) {
                                    categoryEditorTarget = ManagementCategoryEditorTarget(category: category, defaultKind: category.kind)
                                }

                                if index < visibleCategories.count - 1 {
                                    Divider()
                                        .padding(.leading, 52)
                                }
                            }

                            Divider()
                                .padding(.horizontal, 14)

                            ManagementFooterAddButton(
                                title: "Thêm danh mục",
                                accent: accentPurple
                            ) {
                                categoryEditorTarget = ManagementCategoryEditorTarget(category: nil, defaultKind: selectedCategoryKind)
                            }
                        }
                    }
                }
            }
        }
    }

    private var dataSection: some View {
        ManagementSection(title: "Dữ liệu", titleColor: sectionLabelColor) {
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
                message: "Flow export sẽ được nối ở pha sau. Dữ liệu quản lý hiện đã được lưu local bằng SwiftData."
            )
        case .importData:
            infoAlert = ManagementInfoAlert(
                title: action.title,
                message: "Flow import chưa được bật trong build này."
            )
        case .backupRestore:
            infoAlert = ManagementInfoAlert(
                title: action.title,
                message: "Backup & khôi phục sẽ được nối sau khi chốt chiến lược sync."
            )
        case .deleteAllData:
            showsDeleteAllConfirmation = true
        }
    }

    private func deleteAllManagementData() {
        do {
            let accounts = try modelContext.fetch(FetchDescriptor<LedgerAccount>())
            let categories = try modelContext.fetch(FetchDescriptor<TransactionCategory>())
            let creditProfiles = try modelContext.fetch(FetchDescriptor<CreditCardProfile>())
            let transactions = try modelContext.fetch(FetchDescriptor<LedgerTransaction>())

            for account in accounts {
                modelContext.delete(account)
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

            try modelContext.save()

            infoAlert = ManagementInfoAlert(
                title: "Đã xóa dữ liệu",
                message: "Tất cả tài khoản và danh mục đã được xóa khỏi thiết bị."
            )
        } catch {
            infoAlert = ManagementInfoAlert(
                title: "Không thể xóa dữ liệu",
                message: error.localizedDescription
            )
        }
    }
}

private struct ManagementSection<Content: View>: View {
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
    let tint: Color

    var body: some View {
        ManagementCard(tint: tint) {
            HStack(spacing: 14) {
                MistiaAvatarBadge(initials: summary.initials, size: 50, showsStatus: false)

                VStack(alignment: .leading, spacing: 5) {
                    Text(summary.displayName)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text(summary.email)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
        }
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
        colorScheme == .dark ? .white.opacity(0.96) : accent
    }

    private var buttonFill: Color {
        colorScheme == .dark ? .white.opacity(0.12) : .black.opacity(0.08)
    }

    private var buttonForeground: Color {
        colorScheme == .dark ? Color(red: 0.65, green: 0.45, blue: 0.98) : accent
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
                        Text("Đăng nhập để đồng bộ dữ liệu")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        Text("Lưu an toàn tài khoản, danh mục và sẵn sàng cho backup hoặc sync ở các bản sau.")
                            .font(.system(size: 13.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Button(action: action) {
                    Text("Đăng nhập hoặc tạo tài khoản")
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

private struct ManagementAccountRow: View {
    let account: LedgerAccount
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                ManagementIconTile(icon: account.iconSymbolName, color: account.iconColor)

                VStack(alignment: .leading, spacing: 3) {
                    Text(account.name)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)

                    if let subtitle = account.subtitleText {
                        Text(subtitle)
                            .font(.system(size: 12.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    if let footnote = account.footnoteText {
                        Text(footnote)
                            .font(.system(size: 12.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 8)

                Text(account.formattedAmount)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
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

                Text(category.name)
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
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let accent: Color
    let action: () -> Void

    private var buttonFill: Color {
        colorScheme == .dark ? .white.opacity(0.12) : .black.opacity(0.08)
    }

    private var buttonForeground: Color {
        colorScheme == .dark ? Color(red: 0.65, green: 0.45, blue: 0.98) : accent
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(buttonForeground)

                Text(title)
                    .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(buttonForeground)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 14)
            .padding(.vertical, 15)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(buttonFill)
            }
        }
        .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 16, tint: buttonForeground))
    }
}

private struct ManagementEmptyState: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let message: String
    let buttonTitle: String
    let accent: Color
    let symbols: [String]
    let action: () -> Void

    private var capsuleFill: Color {
        colorScheme == .dark ? .white.opacity(0.12) : .black.opacity(0.08)
    }

    private var buttonForeground: Color {
        colorScheme == .dark ? Color(red: 0.65, green: 0.45, blue: 0.98) : accent
    }

    private var symbolBackgroundOpacity: Double {
        colorScheme == .dark ? 0.24 : 0.10
    }

    var body: some View {
        VStack(alignment: .center, spacing: 14) {
            HStack(spacing: 10) {
                ForEach(Array(symbols.enumerated()), id: \.offset) { index, symbol in
                    ZStack {
                        Circle()
                            .fill(accent.opacity(symbolBackgroundOpacity + Double(index) * 0.025))

                        Image(systemName: symbol)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(buttonForeground)
                    }
                    .frame(width: 34, height: 34)
                    .overlay {
                        Circle()
                            .strokeBorder(.white.opacity(colorScheme == .dark ? 0.08 : 0), lineWidth: 0.8)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)

            VStack(alignment: .center, spacing: 6) {
                Text(title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.system(size: 13.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            Button(action: action) {
                Text(buttonTitle)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(buttonForeground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background {
                        Capsule()
                            .fill(capsuleFill)
                    }
            }
            .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 24, tint: buttonForeground))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
    }
}

private struct ManagementCategoryKindPicker: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selection: TransactionCategoryKind

    private var accentPurple: Color {
        Color(red: 0.43, green: 0.23, blue: 0.76)
    }

    private var idleCapsuleTint: Color {
        colorScheme == .dark ? .white.opacity(0.045) : .white.opacity(0.18)
    }

    private var activeCapsuleTint: Color {
        colorScheme == .dark ? accentPurple.opacity(0.42) : accentPurple.opacity(0.16)
    }

    private var activeForeground: Color {
        colorScheme == .dark ? .white.opacity(0.97) : accentPurple
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(TransactionCategoryKind.allCases) { kind in
                Button {
                    selection = kind
                } label: {
                    HStack(spacing: 7) {
                        if selection == kind {
                            Circle()
                                .fill(Color.white.opacity(colorScheme == .dark ? 0.92 : 0.16))
                                .frame(width: 6, height: 6)
                        }

                        Text(kind.title)
                            .font(.system(size: 12.5, weight: .bold, design: .rounded))
                    }
                        .foregroundStyle(selection == kind ? activeForeground : .secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background {
                            MistiaCapsuleGlassBackground(
                                tint: selection == kind
                                    ? activeCapsuleTint
                                    : idleCapsuleTint,
                                interactive: true
                            )
                        }
                        .overlay {
                            Capsule()
                                .strokeBorder(
                                    selection == kind
                                        ? accentPurple.opacity(colorScheme == .dark ? 0.48 : 0.14)
                                        : .clear,
                                    lineWidth: 0.9
                                )
                        }
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 8)
        }
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
    @Environment(\.colorScheme) private var colorScheme
    let tint: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Color.clear)
            .background {
                if #available(iOS 26, *) {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.clear)
                        .glassEffect(
                            Glass.regular
                                .tint(tint)
                                .interactive(false),
                            in: .rect(cornerRadius: 20)
                        )
                } else {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                .white.opacity(colorScheme == .dark ? 0.08 : 0.26),
                                .white.opacity(colorScheme == .dark ? 0.03 : 0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.8
                    )
            }
            .shadow(
                color: .black.opacity(colorScheme == .dark ? 0.14 : 0.035),
                radius: 10,
                y: 4
            )
    }
}

private struct ManagementAuthPlaceholderView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        MistiaPinnedTopBarScaffold(
            tone: .standard,
            title: "Đăng nhập",
            embedsInNavigationStack: false,
            showsLeadingAvatar: false,
            leadingSystemImage: "chevron.left",
            trailingSystemImage: nil,
            hidesSystemBackButton: true,
            onLeadingTap: { dismiss() },
            contentSpacing: 18
        ) {
            MistiaGlassCard(
                cornerRadius: 24,
                tint: Color(red: 0.43, green: 0.23, blue: 0.76).opacity(0.14)
            ) {
                VStack(spacing: 16) {
                    ZStack {
                        MistiaCircleGlassBackground(tint: Color(red: 0.43, green: 0.23, blue: 0.76).opacity(0.18))

                        Image(systemName: "person.crop.circle.badge.checkmark")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(Color(red: 0.43, green: 0.23, blue: 0.76))
                    }
                    .frame(width: 78, height: 78)

                    Text("Flow đăng nhập sẽ được nối ở pha auth riêng.")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)

                    Text("Tab Quản lý hiện đã chạy local-first bằng SwiftData, nên bạn vẫn có thể thêm tài khoản và danh mục ngay cả khi chưa đăng nhập.")
                        .font(.system(size: 14.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}
