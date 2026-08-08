# Overview Widget Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow users to customize Overview screen sections (show/hide & reorder) via an Apple-native customization sheet with local persistence.

**Architecture:** Define `OverviewSectionKind` and `OverviewSectionItemConfig` in `OverviewSectionConfig.swift`, store JSON config in `@AppStorage(MistiaAppStorageKey.overviewSectionConfig)`, present `OverviewWidgetManagementSheet` from top bar slider icon, and dynamically render Overview sections based on user config.

**Tech Stack:** SwiftUI, SwiftData, AppStorage / UserDefaults, Swift CLI.

---

### Task 1: Storage Key & Data Models

**Files:**
- Modify: `Mistia/App/MistiaAppearance.swift`
- Create: `Mistia/Features/Overview/OverviewSectionConfig.swift`
- Test: `MistiaTests/OverviewSectionConfigTests.swift`

- [ ] **Step 1: Write failing unit test for OverviewSectionConfig**

Create `MistiaTests/OverviewSectionConfigTests.swift`:
```swift
import XCTest
@testable import Mistia

final class OverviewSectionConfigTests: XCTestCase {
    func testDefaultConfig() {
        let defaults = OverviewSectionItemConfig.defaultConfig
        XCTAssertEqual(defaults.count, 5)

        let investment = defaults.first { $0.kind == .investment }
        XCTAssertNotNil(investment)
        XCTAssertFalse(investment?.isVisible ?? true, "Investment should be hidden by default")

        let budget = defaults.first { $0.kind == .budgetFocus }
        XCTAssertNotNil(budget)
        XCTAssertTrue(budget?.isVisible ?? false, "Budget section should be visible by default")
    }

    func testEncodingAndDecoding() throws {
        var items = OverviewSectionItemConfig.defaultConfig
        items[4].isVisible = true

        let data = try OverviewSectionConfigStorage.encode(items)
        let decoded = OverviewSectionConfigStorage.decode(from: data)

        XCTAssertEqual(decoded.count, 5)
        XCTAssertTrue(decoded.first { $0.kind == .investment }?.isVisible ?? false)
    }

    func testSanitizeRestoresMissingSections() {
        let incompleteData = try! JSONEncoder().encode([
            OverviewSectionItemConfig(kind: .budgetFocus, isVisible: true)
        ])
        let sanitized = OverviewSectionConfigStorage.decode(from: incompleteData)
        XCTAssertEqual(sanitized.count, 5, "Sanitizing incomplete stored config should append missing sections")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter OverviewSectionConfigTests`
Expected: FAIL with compilation error (OverviewSectionConfig missing).

- [ ] **Step 3: Implement AppStorage key and OverviewSectionConfig models**

Modify `Mistia/App/MistiaAppearance.swift` to add key:
```swift
enum MistiaAppStorageKey {
    // ...
    static let overviewSectionConfig = "mistia.overview.section-config.v1"
}
```

Create `Mistia/Features/Overview/OverviewSectionConfig.swift`:
```swift
import SwiftUI

public enum OverviewSectionKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case preparingSettlements
    case budgetFocus
    case upcomingBills
    case recentTransactions
    case investment

    public var id: String { rawValue }

    public var iconSymbolName: String {
        switch self {
        case .preparingSettlements: return "person.2.fill"
        case .budgetFocus: return "chart.bar.fill"
        case .upcomingBills: return "calendar.badge.clock"
        case .recentTransactions: return "clock.arrow.circlepath"
        case .investment: return "chart.line.uptrend.xyaxis"
        }
    }

    public var localizedTitle: String {
        switch self {
        case .preparingSettlements:
            return L10n.transactions.settlement.ongoingEvents
        case .budgetFocus:
            return L10n.overview.overview.budgetWatchlist
        case .upcomingBills:
            return L10n.overview.overview.upcomingDueItems
        case .recentTransactions:
            return L10n.overview.overview.recentTransactions
        case .investment:
            return L10n.investment.title
        }
    }
}

public struct OverviewSectionItemConfig: Codable, Identifiable, Equatable, Sendable {
    public let kind: OverviewSectionKind
    public var isVisible: Bool

    public var id: String { kind.rawValue }

    public init(kind: OverviewSectionKind, isVisible: Bool) {
        self.kind = kind
        self.isVisible = isVisible
    }

    public static var defaultConfig: [OverviewSectionItemConfig] {
        [
            OverviewSectionItemConfig(kind: .preparingSettlements, isVisible: true),
            OverviewSectionItemConfig(kind: .budgetFocus, isVisible: true),
            OverviewSectionItemConfig(kind: .upcomingBills, isVisible: true),
            OverviewSectionItemConfig(kind: .recentTransactions, isVisible: true),
            OverviewSectionItemConfig(kind: .investment, isVisible: false)
        ]
    }
}

public enum OverviewSectionConfigStorage {
    public static func encode(_ configs: [OverviewSectionItemConfig]) throws -> Data {
        try JSONEncoder().encode(configs)
    }

    public static func decode(from data: Data) -> [OverviewSectionItemConfig] {
        guard !data.isEmpty,
              let items = try? JSONDecoder().decode([OverviewSectionItemConfig].self, from: data) else {
            return OverviewSectionItemConfig.defaultConfig
        }

        var result = items
        let existingKinds = Set(items.map(\.kind))
        for defaultItem in OverviewSectionItemConfig.defaultConfig {
            if !existingKinds.contains(defaultItem.kind) {
                result.append(defaultItem)
            }
        }
        return result
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter OverviewSectionConfigTests`
Expected: PASS.

- [ ] **Step 5: Commit changes**

```bash
git add Mistia/App/MistiaAppearance.swift Mistia/Features/Overview/OverviewSectionConfig.swift MistiaTests/OverviewSectionConfigTests.swift
git commit -m "feat: add OverviewSectionConfig model and storage utilities"
```

---

### Task 2: Build OverviewWidgetManagementSheet UI

**Files:**
- Create: `Mistia/Features/Overview/OverviewWidgetManagementSheet.swift`

- [ ] **Step 1: Create `OverviewWidgetManagementSheet.swift`**

Create `Mistia/Features/Overview/OverviewWidgetManagementSheet.swift`:
```swift
import SwiftUI

struct OverviewWidgetManagementSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var items: [OverviewSectionItemConfig]

    var onResetToDefault: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach($items) { $item in
                        HStack(spacing: 12) {
                            Image(systemName: item.kind.iconSymbolName)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.accentColor)
                                .frame(width: 28, height: 28)

                            Text(item.kind.localizedTitle)
                                .font(.body)
                                .foregroundColor(.primary)

                            Spacer()

                            Toggle("", isOn: $item.isVisible)
                                .labelsHidden()
                        }
                        .padding(.vertical, 4)
                    }
                    .onMove { from, to in
                        items.move(fromOffsets: from, toOffset: to)
                    }
                } header: {
                    Text("Bật/tắt và sắp xếp thứ tự hiển thị các section bên dưới màn hình Tổng quan.")
                        .textCase(nil)
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Tùy chỉnh Tổng quan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Khôi phục") {
                        onResetToDefault()
                    }
                    .foregroundColor(.secondary)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
```

- [ ] **Step 2: Build code to verify compilation**

Run: `swift build`
Expected: Build Succeeded.

- [ ] **Step 3: Commit changes**

```bash
git add Mistia/Features/Overview/OverviewWidgetManagementSheet.swift
git commit -m "feat: create OverviewWidgetManagementSheet view"
```

---

### Task 3: Integrate Widget Management into OverviewView

**Files:**
- Modify: `Mistia/Features/Overview/OverviewView.swift`

- [ ] **Step 1: Add `@AppStorage` and state to `OverviewView.swift`**

Inside `struct OverviewView`:
```swift
@AppStorage(MistiaAppStorageKey.overviewSectionConfig) private var sectionConfigData = Data()
@State private var isManagingWidgets = false

private var activeSectionConfigs: [OverviewSectionItemConfig] {
    OverviewSectionConfigStorage.decode(from: sectionConfigData)
}

private var sectionConfigsBinding: Binding<[OverviewSectionItemConfig]> {
    Binding(
        get: {
            OverviewSectionConfigStorage.decode(from: sectionConfigData)
        },
        set: { newItems in
            if let encoded = try? OverviewSectionConfigStorage.encode(newItems) {
                sectionConfigData = encoded
            }
        }
    )
}
```

- [ ] **Step 2: Update Header trailing accessory to add Slider Button**

In `MistiaPinnedTopBarScaffold`:
```swift
trailingAccessory: {
    HStack(spacing: 10) {
        Button {
            isManagingWidgets = true
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.primary)
                .frame(width: 32, height: 32)
                .background(Color(uiColor: .tertiarySystemFill), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Tùy chỉnh giao diện")

        MistiaNotificationBellLink()
    }
}
```

- [ ] **Step 3: Render sub-sections dynamically based on `activeSectionConfigs`**

Replace static section list in `OverviewView` body content with dynamic loop:
```swift
OverviewHeroCard(
    snapshot: renderSnapshot.dashboard.hero,
    isSheetPresented: selectedExpenseDay != nil,
    onOpenExpenseDay: { date in
        openExpenseDay(date, transactionsByDay: renderSnapshot.postedExpenseTransactionsByDay)
    }
)

ForEach(activeSectionConfigs.filter(\.isVisible)) { config in
    switch config.kind {
    case .investment:
        InvestmentOverviewCard(
            snapshot: investmentOverviewSnapshot(),
            canView: ownerUserIDForInvestment.map(canViewInvestment(ownerUserID:)) ?? false
        ) {
            destination = .investment
        }
    case .preparingSettlements:
        if !preparingEvents.isEmpty {
            OverviewPreparingSettlementSection(
                events: preparingEvents,
                onSelect: { event in
                    preparingSettlementTarget = PreparingSettlementEventSheetTarget(groupID: event.id)
                }
            )
        }
    case .budgetFocus:
        if !renderSnapshot.dashboard.budgetAlerts.isEmpty {
            BudgetFocusSection(rows: renderSnapshot.dashboard.budgetAlerts)
        }
    case .upcomingBills:
        if !renderSnapshot.dashboard.dueAlerts.isEmpty {
            UpcomingBillsSection(rows: renderSnapshot.dashboard.dueAlerts) { row in
                routeDueAlertTap(row)
            }
        }
    case .recentTransactions:
        RecentTransactionsSection(rows: renderSnapshot.dashboard.recentTransactions) { row in
            guard let transaction = renderSnapshot.transactionsByID[row.id] else { return }
            presentEditor(for: transaction, actionContext: actionContext)
        }
    }
}
```

- [ ] **Step 4: Attach `.sheet` modifier for widget management**

At the end of `OverviewView` sheet modifiers:
```swift
.sheet(isPresented: $isManagingWidgets) {
    OverviewWidgetManagementSheet(
        items: sectionConfigsBinding,
        onResetToDefault: {
            if let encoded = try? OverviewSectionConfigStorage.encode(OverviewSectionItemConfig.defaultConfig) {
                sectionConfigData = encoded
            }
        }
    )
}
```

- [ ] **Step 5: Verify build & tests**

Run: `swift test`
Expected: Build succeeded & all tests pass.

- [ ] **Step 6: Commit changes**

```bash
git add Mistia/Features/Overview/OverviewView.swift
git commit -m "feat: connect widget management sheet and dynamic section rendering to OverviewView"
```

---

### Task 4: Final Verification & Hand-off

- [ ] **Step 1: Execute all unit tests**

Run: `swift test`
Expected: All tests pass cleanly.

- [ ] **Step 2: Commit any remaining changes**

Verify `git status` clean.
