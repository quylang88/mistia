import SwiftUI

enum MistiaCategoryPickerMode: String, CaseIterable, Identifiable {
    case recent
    case favorites
    case all

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .recent:
            "clock.fill"
        case .favorites:
            "star.fill"
        case .all:
            "square.grid.2x2.fill"
        }
    }

    var title: String {
        switch self {
        case .recent:
            mistiaLocalized(vi: "Gần đây", en: "Recent", ja: "最近")
        case .favorites:
            mistiaLocalized(vi: "Yêu thích", en: "Favorites", ja: "お気に入り")
        case .all:
            mistiaLocalized(vi: "Tất cả", en: "All", ja: "すべて")
        }
    }
}

enum MistiaCategoryPickerSupport {
    private static func normalizedSearchText(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func matchesSearch(_ category: TransactionCategory, query: String) -> Bool {
        let normalizedQuery = normalizedSearchText(query)
        guard !normalizedQuery.isEmpty else { return true }

        return searchableStrings(for: category).contains { candidate in
            normalizedSearchText(candidate).contains(normalizedQuery)
        }
    }

    static func favoriteCategories(
        from categories: [TransactionCategory],
        kind: TransactionCategoryKind
    ) -> [TransactionCategory] {
        categories
            .filter {
                $0.deletedAt == nil
                    && !$0.isArchived
                    && $0.kind == kind
                    && $0.isChildCategory
                    && $0.isFavorite
            }
            .sorted { lhs, rhs in
                MistiaCategoryHierarchy.categorySort(lhs: lhs, rhs: rhs)
            }
    }

    static func recentCategories(
        from transactions: [LedgerTransaction],
        categories: [TransactionCategory],
        kind: TransactionCategoryKind,
        now: Date = .now,
        dayWindow: Int = 90,
        limit: Int = 10
    ) -> [TransactionCategory] {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -dayWindow, to: now) ?? .distantPast
        let allowedCategories = categories.filter {
            $0.deletedAt == nil
                && !$0.isArchived
                && $0.kind == kind
                && $0.isChildCategory
        }
        let allowedByID = Dictionary(uniqueKeysWithValues: allowedCategories.map { ($0.id, $0) })

        struct Usage {
            var count: Int
            var latest: Date
        }

        var usageByCategoryID: [UUID: Usage] = [:]
        for transaction in transactions {
            guard transaction.deletedAt == nil, !transaction.isArchived else { continue }
            guard transaction.entryStatus == .posted else { continue }
            guard transaction.occurredAt >= cutoffDate else { continue }
            guard let categoryID = transaction.category?.id, allowedByID[categoryID] != nil else { continue }

            if let current = usageByCategoryID[categoryID] {
                usageByCategoryID[categoryID] = Usage(
                    count: current.count + 1,
                    latest: max(current.latest, transaction.occurredAt)
                )
            } else {
                usageByCategoryID[categoryID] = Usage(count: 1, latest: transaction.occurredAt)
            }
        }

        let rankedCategories: [(category: TransactionCategory, usage: Usage)] = usageByCategoryID.compactMap { entry in
            let (categoryID, usage) = entry
            guard let category = allowedByID[categoryID] else { return nil }
            return (category: category, usage: usage)
        }

        return rankedCategories
            .sorted { lhs, rhs in
                if lhs.usage.count != rhs.usage.count {
                    return lhs.usage.count > rhs.usage.count
                }
                if lhs.usage.latest != rhs.usage.latest {
                    return lhs.usage.latest > rhs.usage.latest
                }
                return MistiaCategoryHierarchy.categorySort(lhs: lhs.category, rhs: rhs.category)
            }
            .prefix(limit)
            .map(\.category)
    }

    static func billQuickPickCategories(
        from categories: [TransactionCategory]
    ) -> [TransactionCategory] {
        let categoriesByKey = Dictionary(
            uniqueKeysWithValues: categories
                .filter {
                    $0.deletedAt == nil
                        && !$0.isArchived
                        && $0.kind == .expense
                        && $0.isChildCategory
                }
                .compactMap { category in
                    category.mistiaSystemCategoryKey.map { ($0, category) }
                }
        )

        return MistiaSystemCategoryKey.recurringBillQuickPickDefaults.compactMap { key in
            categoriesByKey[key]
        }
    }

    private static func searchableStrings(for category: TransactionCategory) -> [String] {
        var values: [String] = [category.name, category.localizedDisplayName]

        if let parent = category.parentCategory {
            values.append(parent.name)
            values.append(parent.localizedDisplayName)
        }

        if let systemKey = category.mistiaSystemCategoryKey {
            values.append(contentsOf: systemKey.knownDefaultNames())
        }

        if let parentKey = category.mistiaSystemCategoryParentKey {
            values.append(contentsOf: parentKey.knownDefaultNames())
        }

        return Array(Set(values.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }))
    }
}

struct MistiaCategoryPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let selectedCategoryID: UUID?
    let sections: [TransactionCategoryGroupSection]
    let recentCategories: [TransactionCategory]
    let favoriteCategories: [TransactionCategory]
    let featuredSectionTitle: String?
    let featuredCategories: [TransactionCategory]
    let allowsParentSelectionInAll: Bool
    let allModeSubtitle: (TransactionCategory) -> String?
    let quickModeSubtitle: (TransactionCategory) -> String?
    let featuredSubtitle: ((TransactionCategory) -> String?)?
    let onSelect: (TransactionCategory) -> Void

    @State private var mode: MistiaCategoryPickerMode = .recent
    @State private var searchText = ""
    @State private var expandedSectionIDs: Set<UUID> = []
    @FocusState private var isSearchFieldFocused: Bool

    init(
        title: String,
        selectedCategoryID: UUID?,
        sections: [TransactionCategoryGroupSection],
        recentCategories: [TransactionCategory],
        favoriteCategories: [TransactionCategory],
        featuredSectionTitle: String? = nil,
        featuredCategories: [TransactionCategory] = [],
        allowsParentSelectionInAll: Bool,
        allModeSubtitle: @escaping (TransactionCategory) -> String?,
        quickModeSubtitle: @escaping (TransactionCategory) -> String?,
        featuredSubtitle: ((TransactionCategory) -> String?)? = nil,
        onSelect: @escaping (TransactionCategory) -> Void
    ) {
        self.title = title
        self.selectedCategoryID = selectedCategoryID
        self.sections = sections
        self.recentCategories = recentCategories
        self.favoriteCategories = favoriteCategories
        self.featuredSectionTitle = featuredSectionTitle
        self.featuredCategories = featuredCategories
        self.allowsParentSelectionInAll = allowsParentSelectionInAll
        self.allModeSubtitle = allModeSubtitle
        self.quickModeSubtitle = quickModeSubtitle
        self.featuredSubtitle = featuredSubtitle
        self.onSelect = onSelect
    }

    private var accent: Color {
        Color(red: 0.43, green: 0.23, blue: 0.76)
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                headerControls

                if isEmptyInCurrentMode {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 18) {
                            if isSearching {
                                quickSection(
                                    title: mistiaLocalized(vi: "Kết quả tìm kiếm", en: "Search results", ja: "検索結果"),
                                    categories: searchResults,
                                    subtitleProvider: searchResultSubtitle
                                )
                            } else {
                                switch mode {
                                case .recent:
                                    if let featuredSectionTitle, !visibleFeaturedCategories.isEmpty {
                                        quickSection(
                                            title: featuredSectionTitle,
                                            categories: visibleFeaturedCategories,
                                            subtitleProvider: featuredSubtitle ?? quickModeSubtitle
                                        )
                                    }

                                    if !visibleRecentCategories.isEmpty {
                                        quickSection(
                                            title: mistiaLocalized(vi: "Danh mục dùng nhiều trong 90 ngày", en: "Most used in the last 90 days", ja: "過去90日でよく使ったカテゴリ"),
                                            categories: visibleRecentCategories,
                                            subtitleProvider: quickModeSubtitle
                                        )
                                    }
                                case .favorites:
                                    if !visibleFavoriteCategories.isEmpty {
                                        quickSection(
                                            title: mistiaLocalized(vi: "Danh mục yêu thích", en: "Favorite categories", ja: "お気に入りカテゴリ"),
                                            categories: visibleFavoriteCategories,
                                            subtitleProvider: quickModeSubtitle
                                        )
                                    }
                                case .all:
                                    allSectionsContent
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                    }
                }
            }
            .onChange(of: mode) { _, newMode in
                if newMode == .all {
                    isSearchFieldFocused = false
                }
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(mistiaLocalized(vi: "Đóng", en: "Close", ja: "閉じる")) {
                        dismiss()
                    }
                }
            }
            .task {
                guard isSearchFieldFocused == false else { return }
                try? await Task.sleep(for: .milliseconds(150))
                isSearchFieldFocused = true
            }
        }
    }

    private var headerControls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField(
                    mistiaLocalized(vi: "Tìm danh mục", en: "Search categories", ja: "カテゴリを検索"),
                    text: $searchText
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($isSearchFieldFocused)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 20))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(UIColor.secondarySystemBackground))
            )

            HStack(spacing: 10) {
                ForEach(MistiaCategoryPickerMode.allCases) { candidate in
                    Button {
                        mode = candidate
                    } label: {
                        Image(systemName: candidate.systemImage)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(mode == candidate ? Color.white : .secondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                            .background {
                                Capsule(style: .continuous)
                                    .fill(mode == candidate ? accent : Color.clear)
                            }
                            .overlay {
                                Capsule(style: .continuous)
                                    .strokeBorder(
                                        mode == candidate
                                            ? accent.opacity(0.14)
                                            : Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.06),
                                        lineWidth: mode == candidate ? 0 : 0.8
                                    )
                            }
                    }
                    .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 20))
                    .accessibilityLabel(candidate.title)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(Color(UIColor.systemGroupedBackground))
    }

    private var allSectionsContent: some View {
        VStack(spacing: 0) {
            ForEach(Array(filteredAllSections.enumerated()), id: \.element.id) { index, section in
                VStack(spacing: 0) {
                    Button {
                        withAnimation(.snappy) {
                            if expandedSectionIDs.contains(section.id) {
                                expandedSectionIDs.remove(section.id)
                            } else {
                                expandedSectionIDs.insert(section.id)
                            }
                        }
                    } label: {
                        HStack(spacing: 12) {
                            MistiaFinanceIconView(
                                icon: section.parent.iconSymbolName,
                                fallbackColor: section.parent.iconColor,
                                size: 34
                            )

                            VStack(alignment: .leading, spacing: 4) {
                                Text(section.parent.localizedDisplayName)
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.primary)

                                Text(
                                    mistiaLocalized(
                                        vi: "\(section.children.count) danh mục con",
                                        en: "\(section.children.count) child categories",
                                        ja: "子カテゴリ \(section.children.count) 件"
                                    )
                                )
                                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: expandedSectionIDs.contains(section.id) ? "chevron.up" : "chevron.down")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 20))

                    if expandedSectionIDs.contains(section.id) {
                        VStack(spacing: 0) {
                            if section.children.isEmpty && (!allowsParentSelectionInAll || !section.includesParent) {
                                Text(
                                    mistiaLocalized(
                                        vi: "Chưa có danh mục con.",
                                        en: "No child categories.",
                                        ja: "子カテゴリがありません。"
                                    )
                                )
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)
                            } else {
                                if allowsParentSelectionInAll, section.includesParent {
                                    rowButton(
                                        category: section.parent,
                                        subtitle: allModeSubtitle(section.parent),
                                        showsBackground: false
                                    )
                                    
                                    if !section.children.isEmpty {
                                        Divider().padding(.leading, 52)
                                    }
                                }

                                ForEach(Array(section.children.enumerated()), id: \.element.id) { childIndex, category in
                                    rowButton(
                                        category: category,
                                        subtitle: allModeSubtitle(category),
                                        showsBackground: false,
                                        indentation: 38
                                    )
                                    
                                    if childIndex < section.children.count - 1 {
                                        Divider().padding(.leading, 52 + 38)
                                    }
                                }
                            }
                        }
                        .background(Color.primary.opacity(0.015)) // Subtle grouping
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                
                if index < filteredAllSections.count - 1 {
                    Divider().padding(.leading, 52)
                }
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(UIColor.secondarySystemBackground))
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func quickSection(
        title: String,
        categories: [TransactionCategory],
        subtitleProvider: @escaping (TransactionCategory) -> String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                ForEach(categories) { category in
                    rowButton(
                        category: category,
                        subtitle: subtitleProvider(category)
                    )
                }
            }
        }
    }

    private func rowButton(category: TransactionCategory, subtitle: String?, showsBackground: Bool = true, indentation: CGFloat = 0) -> some View {
        Group {
            if showsBackground {
                Button {
                    onSelect(category)
                    dismiss()
                } label: {
                    rowButtonContent(category: category, subtitle: subtitle, showsBackground: showsBackground, indentation: indentation)
                }
                .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 16, tint: accent))
            } else {
                Button {
                    onSelect(category)
                    dismiss()
                } label: {
                    rowButtonContent(category: category, subtitle: subtitle, showsBackground: showsBackground, indentation: indentation)
                }
                .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 16, tint: accent))
            }
        }
    }

    private func rowButtonContent(category: TransactionCategory, subtitle: String?, showsBackground: Bool, indentation: CGFloat) -> some View {
        HStack(spacing: 12) {
            MistiaFinanceIconView(
                icon: category.iconSymbolName,
                fallbackColor: category.iconColor,
                size: 34
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(category.localizedDisplayName)
                    .foregroundStyle(.primary)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            if category.id == selectedCategoryID {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.tint)
            }
        }
        .padding(.leading, 12 + indentation)
        .padding(.trailing, 12)
        .padding(.vertical, 10)
        .background {
            if showsBackground {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(UIColor.secondarySystemBackground))
            }
        }
        .contentShape(Rectangle())
    }

    private var filteredAllSections: [FilteredSection] {
        sections.compactMap { section in
            let parentMatches = MistiaCategoryPickerSupport.matchesSearch(section.parent, query: searchText)
            let children = section.children.filter { child in
                searchText.isEmpty
                    || MistiaCategoryPickerSupport.matchesSearch(child, query: searchText)
                    || parentMatches
            }

            let includesParent = allowsParentSelectionInAll && (searchText.isEmpty || parentMatches)

            if children.isEmpty && !includesParent {
                return nil
            }

            return FilteredSection(
                parent: section.parent,
                children: children,
                includesParent: includesParent
            )
        }
    }

    private func filteredQuickCategories(from categories: [TransactionCategory]) -> [TransactionCategory] {
        categories.filter { MistiaCategoryPickerSupport.matchesSearch($0, query: searchText) }
    }

    private var visibleFeaturedCategories: [TransactionCategory] {
        guard featuredSectionTitle != nil else { return [] }
        return filteredQuickCategories(from: featuredCategories)
    }

    private var visibleRecentCategories: [TransactionCategory] {
        let featuredIDs = Set(visibleFeaturedCategories.map(\.id))
        return filteredQuickCategories(from: recentCategories).filter { !featuredIDs.contains($0.id) }
    }

    private var visibleFavoriteCategories: [TransactionCategory] {
        filteredQuickCategories(from: favoriteCategories)
    }

    private var searchResults: [TransactionCategory] {
        var seenCategoryIDs: Set<UUID> = []

        return filteredAllSections.flatMap { section -> [TransactionCategory] in
            var items: [TransactionCategory] = []
            if section.includesParent {
                items.append(section.parent)
            }
            items.append(contentsOf: section.children)
            return items
        }
        .filter { category in
            seenCategoryIDs.insert(category.id).inserted
        }
    }

    private func searchResultSubtitle(for category: TransactionCategory) -> String? {
        if category.isParentCategory {
            return allModeSubtitle(category)
        }

        return category.parentCategory?.localizedDisplayName
            ?? quickModeSubtitle(category)
            ?? allModeSubtitle(category)
    }

    private var isEmptyInCurrentMode: Bool {
        if isSearching {
            return searchResults.isEmpty
        }

        switch mode {
        case .recent:
            return visibleFeaturedCategories.isEmpty && visibleRecentCategories.isEmpty
        case .favorites:
            return visibleFavoriteCategories.isEmpty
        case .all:
            return filteredAllSections.isEmpty
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 18)

            MistiaEmptyStateContent(
                title: emptyTitle,
                message: emptyMessage,
                buttonTitle: isSearching || mode == .all ? nil : MistiaCategoryPickerMode.all.title,
                accent: accent,
                symbols: isSearching
                    ? ["magnifyingglass", "square.grid.2x2.fill"]
                    : (mode == .favorites ? ["star.fill", "square.grid.2x2.fill"] : ["clock.fill", "square.grid.2x2.fill"]),
                action: isSearching || mode == .all ? nil : { mode = .all }
            )
            .padding(.horizontal, 16)

            Spacer()
        }
    }

    private var emptyTitle: String {
        if isSearching || mode == .all {
            return mistiaLocalized(vi: "Không tìm thấy danh mục", en: "No categories found", ja: "カテゴリが見つかりません")
        }

        return mode == .favorites
            ? mistiaLocalized(vi: "Chưa có danh mục yêu thích", en: "No favorite categories yet", ja: "お気に入りカテゴリはまだありません")
            : mistiaLocalized(vi: "Chưa có danh mục gần đây", en: "No recent categories yet", ja: "最近のカテゴリはまだありません")
    }

    private var emptyMessage: String {
        if !searchText.isEmpty {
            return mistiaLocalized(
                vi: "Thử từ khóa khác hoặc chuyển sang xem tất cả danh mục.",
                en: "Try another keyword or switch to all categories.",
                ja: "別のキーワードを試すか、すべてのカテゴリに切り替えてください。"
            )
        }

        return mode == .favorites
            ? mistiaLocalized(
                vi: "Đánh dấu sao ở danh mục con trong tab Quản lý để chọn nhanh hơn ở đây.",
                en: "Star child categories in Manage to access them quickly here.",
                ja: "管理タブで子カテゴリにスターを付けると、ここからすばやく選べます。"
            )
            : mistiaLocalized(
                vi: "Sau khi bạn dùng danh mục vài lần, Mistia sẽ đưa các mục xuất hiện nhiều nhất vào đây.",
                en: "After you use categories a few times, Mistia will surface the most-used ones here.",
                ja: "カテゴリを数回使うと、Mistia がよく使う項目をここに表示します。"
            )
    }

    private struct FilteredSection: Identifiable {
        let parent: TransactionCategory
        let children: [TransactionCategory]
        let includesParent: Bool

        var id: UUID { parent.id }
    }
}
