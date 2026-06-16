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
            L10n.core.ui.mistiacategorypicker.recent
        case .favorites:
            L10n.core.ui.mistiacategorypicker.favorites
        case .all:
            L10n.core.ui.mistiacategorypicker.all
        }
    }
}

enum MistiaCategoryPickerSupport {
    private static func normalizedSearchText(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    struct SearchIndex {
        private let normalizedValuesByCategoryID: [UUID: [String]]

        init(categories: [TransactionCategory], language: MistiaAppLanguage) {
            var valuesByID: [UUID: [String]] = [:]
            for category in categories {
                valuesByID[category.id] = Self.normalizedSearchableStrings(for: category, language: language)
            }
            normalizedValuesByCategoryID = valuesByID
        }

        func matches(_ category: TransactionCategory, normalizedQuery: String) -> Bool {
            guard !normalizedQuery.isEmpty else { return true }
            return normalizedValuesByCategoryID[category.id]?.contains { value in
                value.contains(normalizedQuery)
            } ?? false
        }

        private static func normalizedSearchableStrings(
            for category: TransactionCategory,
            language: MistiaAppLanguage
        ) -> [String] {
            var values: [String] = [
                category.name,
                category.localizedDisplayName(for: language)
            ]

            if let parent = category.parentCategory {
                values.append(parent.name)
                values.append(parent.localizedDisplayName(for: language))
            }

            if let systemKey = category.systemKey,
               let parsed = MistiaSystemCategoryRegistry.shared.category(for: systemKey) {
                values.append(contentsOf: parsed.knownDefaultNames())
            }

            if let parentCategory = category.parentCategory,
               let parentSystemKey = parentCategory.systemKey,
               let parsedParent = MistiaSystemCategoryRegistry.shared.category(for: parentSystemKey) {
                values.append(contentsOf: parsedParent.knownDefaultNames())
            } else if let systemKey = category.systemKey,
                      let parentId = MistiaSystemCategoryRegistry.shared.parentId(for: systemKey),
                      let parsedParent = MistiaSystemCategoryRegistry.shared.category(for: parentId) {
                values.append(contentsOf: parsedParent.knownDefaultNames())
            }

            return Array(Set(values.compactMap { value in
                let normalized = normalizedSearchText(value)
                return normalized.isEmpty ? nil : normalized
            }))
        }
    }

    static func normalizedSearchQuery(_ value: String) -> String {
        normalizedSearchText(value)
    }

    static func matchesSearch(
        _ category: TransactionCategory,
        query: String,
        language: MistiaAppLanguage = .current
    ) -> Bool {
        let normalizedQuery = normalizedSearchText(query)
        guard !normalizedQuery.isEmpty else { return true }

        return SearchIndex(categories: [category], language: language).matches(category, normalizedQuery: normalizedQuery)
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
                    && !$0.isBalanceAdjustmentSystemCategory
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
                && !$0.isBalanceAdjustmentSystemCategory
        }
        let allowedByID = Dictionary(
            allowedCategories.map { ($0.id, $0) },
            uniquingKeysWith: { lhs, rhs in lhs.updatedAt >= rhs.updatedAt ? lhs : rhs }
        )

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
            categories
            .filter {
                $0.deletedAt == nil
                    && !$0.isArchived
                    && $0.kind == .expense
                    && $0.isChildCategory
            }
            .compactMap { category in
                category.mistiaSystemCategoryKey.map { ($0, category) }
            },
            uniquingKeysWith: { lhs, rhs in lhs.updatedAt >= rhs.updatedAt ? lhs : rhs }
        )

        return MistiaSystemCategoryKey.recurringBillQuickPickDefaults.compactMap { key in
            categoriesByKey[key]
        }
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
    private let appLanguage: MistiaAppLanguage
    private let searchIndex: MistiaCategoryPickerSupport.SearchIndex

    @State private var mode: MistiaCategoryPickerMode
    @State private var searchText = ""
    @State private var expandedSectionIDs: Set<UUID> = []
    @FocusState private var isSearchFieldFocused: Bool

    private struct RenderSnapshot {
        let isSearching: Bool
        let filteredAllSections: [FilteredSection]
        let visibleFeaturedCategories: [TransactionCategory]
        let visibleRecentCategories: [TransactionCategory]
        let visibleFavoriteCategories: [TransactionCategory]
        let searchResults: [TransactionCategory]
        let isEmptyInCurrentMode: Bool
    }

    init(
        title: String,
        selectedCategoryID: UUID?,
        sections: [TransactionCategoryGroupSection],
        recentCategories: [TransactionCategory],
        favoriteCategories: [TransactionCategory],
        featuredSectionTitle: String? = nil,
        featuredCategories: [TransactionCategory] = [],
        initialMode: MistiaCategoryPickerMode = .recent,
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
        let appLanguage = MistiaAppLanguage.current
        self.appLanguage = appLanguage
        self.searchIndex = MistiaCategoryPickerSupport.SearchIndex(
            categories: Self.searchableCategories(
                sections: sections,
                recentCategories: recentCategories,
                favoriteCategories: favoriteCategories,
                featuredCategories: featuredCategories
            ),
            language: appLanguage
        )
        _mode = State(initialValue: initialMode)
    }

    private var accent: Color {
        Color(red: 0.43, green: 0.23, blue: 0.76)
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var normalizedSearchQuery: String {
        MistiaCategoryPickerSupport.normalizedSearchQuery(searchText)
    }

    var body: some View {
        let snapshot = renderSnapshot

        NavigationStack {
            VStack(spacing: 0) {
                headerControls

                if snapshot.isEmptyInCurrentMode {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 18) {
                            pickerContent(snapshot)
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
                    Button(L10n.core.ui.mistiacategorypicker.close) {
                        dismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func pickerContent(_ snapshot: RenderSnapshot) -> some View {
        if snapshot.isSearching {
            quickSection(
                title: L10n.core.ui.mistiacategorypicker.searchResults,
                categories: snapshot.searchResults,
                subtitleProvider: searchResultSubtitle
            )
        } else {
            switch mode {
            case .recent:
                if let featuredSectionTitle, !snapshot.visibleFeaturedCategories.isEmpty {
                    quickSection(
                        title: featuredSectionTitle,
                        categories: snapshot.visibleFeaturedCategories,
                        subtitleProvider: featuredSubtitle ?? quickModeSubtitle
                    )
                }

                if !snapshot.visibleRecentCategories.isEmpty {
                    quickSection(
                        title: L10n.core.ui.mistiacategorypicker.mostUsedInTheLastDays,
                        categories: snapshot.visibleRecentCategories,
                        subtitleProvider: quickModeSubtitle
                    )
                }
            case .favorites:
                if !snapshot.visibleFavoriteCategories.isEmpty {
                    quickSection(
                        title: L10n.core.ui.mistiacategorypicker.favoriteCategories,
                        categories: snapshot.visibleFavoriteCategories,
                        subtitleProvider: quickModeSubtitle
                    )
                }
            case .all:
                allSectionsContent(snapshot.filteredAllSections)
            }
        }
    }

    private var headerControls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField(
                    L10n.core.ui.mistiacategorypicker.searchCategories,
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

    private func allSectionsContent(_ filteredAllSections: [FilteredSection]) -> some View {
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
                                Text(displayName(for: section.parent))
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.primary)

                                Text(
                                    L10n.core.ui.mistiacategorypicker.valueChildCategories(String(describing: section.children.count))
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
                                    L10n.core.ui.mistiacategorypicker.noChildCategories
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
                Text(displayName(for: category))
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

    private var renderSnapshot: RenderSnapshot {
        let isSearching = self.isSearching
        let normalizedQuery = normalizedSearchQuery
        let filteredAllSections = filteredAllSections(normalizedQuery: normalizedQuery)
        let visibleFeaturedCategories: [TransactionCategory]
        if featuredSectionTitle != nil {
            visibleFeaturedCategories = filteredQuickCategories(
                from: featuredCategories,
                normalizedQuery: normalizedQuery
            )
        } else {
            visibleFeaturedCategories = []
        }
        let featuredIDs = Set(visibleFeaturedCategories.map(\.id))
        let visibleRecentCategories = filteredQuickCategories(
            from: recentCategories,
            normalizedQuery: normalizedQuery
        )
        .filter { !featuredIDs.contains($0.id) }
        let visibleFavoriteCategories = filteredQuickCategories(
            from: favoriteCategories,
            normalizedQuery: normalizedQuery
        )
        let searchResults = isSearching
            ? searchResults(from: filteredAllSections)
            : []
        let isEmptyInCurrentMode: Bool
        if isSearching {
            isEmptyInCurrentMode = searchResults.isEmpty
        } else {
            switch mode {
            case .recent:
                isEmptyInCurrentMode = visibleFeaturedCategories.isEmpty && visibleRecentCategories.isEmpty
            case .favorites:
                isEmptyInCurrentMode = visibleFavoriteCategories.isEmpty
            case .all:
                isEmptyInCurrentMode = filteredAllSections.isEmpty
            }
        }

        return RenderSnapshot(
            isSearching: isSearching,
            filteredAllSections: filteredAllSections,
            visibleFeaturedCategories: visibleFeaturedCategories,
            visibleRecentCategories: visibleRecentCategories,
            visibleFavoriteCategories: visibleFavoriteCategories,
            searchResults: searchResults,
            isEmptyInCurrentMode: isEmptyInCurrentMode
        )
    }

    private func filteredAllSections(normalizedQuery: String) -> [FilteredSection] {
        return sections.compactMap { section -> FilteredSection? in
            let parentMatches = searchIndex.matches(section.parent, normalizedQuery: normalizedQuery)
            let children = section.children.filter { child in
                normalizedQuery.isEmpty
                    || searchIndex.matches(child, normalizedQuery: normalizedQuery)
                    || parentMatches
            }

            let includesParent = allowsParentSelectionInAll && (normalizedQuery.isEmpty || parentMatches)

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

    private func filteredQuickCategories(
        from categories: [TransactionCategory],
        normalizedQuery: String
    ) -> [TransactionCategory] {
        return categories.filter { searchIndex.matches($0, normalizedQuery: normalizedQuery) }
    }

    private func searchResults(from filteredAllSections: [FilteredSection]) -> [TransactionCategory] {
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

        return category.parentCategory.map { displayName(for: $0) }
            ?? quickModeSubtitle(category)
            ?? allModeSubtitle(category)
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
            return L10n.core.ui.mistiacategorypicker.noCategoriesFound
        }

        return mode == .favorites
            ? L10n.core.ui.mistiacategorypicker.noFavoriteCategoriesYet
            : L10n.core.ui.mistiacategorypicker.noRecentCategoriesYet
    }

    private var emptyMessage: String {
        if !searchText.isEmpty {
            return L10n.core.ui.mistiacategorypicker.tryAnotherKeywordOrSwitchToAll
        }

        return mode == .favorites
            ? L10n.core.ui.mistiacategorypicker.starChildCategoriesInManageToAccess
            : L10n.core.ui.mistiacategorypicker.afterYouUseCategoriesAFewTimes
    }

    private struct FilteredSection: Identifiable {
        let parent: TransactionCategory
        let children: [TransactionCategory]
        let includesParent: Bool

        var id: UUID { parent.id }
    }

    private func displayName(for category: TransactionCategory) -> String {
        category.localizedDisplayName(for: appLanguage)
    }

    private static func searchableCategories(
        sections: [TransactionCategoryGroupSection],
        recentCategories: [TransactionCategory],
        favoriteCategories: [TransactionCategory],
        featuredCategories: [TransactionCategory]
    ) -> [TransactionCategory] {
        var categoriesByID: [UUID: TransactionCategory] = [:]
        for section in sections {
            categoriesByID[section.parent.id] = section.parent
            for child in section.children {
                categoriesByID[child.id] = child
            }
        }
        for category in recentCategories + favoriteCategories + featuredCategories {
            categoriesByID[category.id] = category
        }
        return Array(categoriesByID.values)
    }
}
