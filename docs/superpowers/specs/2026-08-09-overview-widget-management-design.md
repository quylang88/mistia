# Overview Widget Management Design Spec

## Executive Summary
This spec defines the design for customizable Overview sections (widgets) in Mistia iOS application. Users will be able to show/hide sections below the top hero card, reorder them via drag-and-drop using an Apple-native customization sheet, and have their preferences persisted locally across app launches.

---

## Requirements & Default Rules

1. **Pinned Top Section:**
   - The main top card (`OverviewHeroCard`) remains pinned at the very top of the Overview screen. It is non-removable and non-reorderable.

2. **Manageable Sub-Sections:**
   The following 5 sub-sections can be toggled (show/hide) and reordered:
   - `preparingSettlements` (Quyết toán đang diễn ra) — **Default: Visible (ON)**
   - `budgetFocus` (Theo dõi ngân sách) — **Default: Visible (ON)**
   - `upcomingBills` (Hóa đơn & Khoản sắp đến hạn) — **Default: Visible (ON)**
   - `recentTransactions` (Giao dịch gần đây) — **Default: Visible (ON)**
   - `investment` (Đầu tư) — **Default: Hidden (OFF)**

3. **Entry Point:**
   - A sliders icon button (`slider.horizontal.3`) placed on the top right navigation bar of `OverviewView`, situated to the left of the notification bell (`MistiaNotificationBellLink`).

4. **Customization Sheet UI (Apple Native Style):**
   - Presented as a modal `.sheet` titled "Tùy chỉnh Tổng quan" (Customize Overview).
   - Top Bar Controls:
     - Leading: "Khôi phục" (Reset) button to restore default section order and visibility states.
     - Trailing: "Xong" (Done) button to dismiss the sheet.
   - List View:
     - Uses native SwiftUI `List` styled in inset grouped style with `EditMode.active`.
     - Supports drag-to-reorder (`onMove`).
     - Includes a `Toggle` switch for visibility state.
     - Displays icon, localized title, and clear row boundaries.

5. **Persistence & Real-time Update:**
   - Preference state stored in `@AppStorage(MistiaAppStorageKey.overviewSectionConfig)`.
   - `OverviewView` reads the ordered configuration and renders active, visible sections dynamically in real-time.

---

## Data Architecture

### Data Models (`OverviewSectionConfig.swift`)

```swift
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
}

public struct OverviewSectionItemConfig: Codable, Identifiable, Equatable, Sendable {
    public let kind: OverviewSectionKind
    public var isVisible: Bool

    public var id: String { kind.rawValue }

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
```

### Storage Persistence
- Standard storage key added to `MistiaAppStorageKey`:
  `static let overviewSectionConfig = "mistia.overview.section-config.v1"`
- Serialized to JSON string inside `UserDefaults` / `@AppStorage`.

---

## UI Components & Navigation

### 1. Header Trailing Button in `OverviewView`
Added to `trailingAccessory` of `MistiaPinnedTopBarScaffold`:
```swift
HStack(spacing: 12) {
    Button {
        isManagingWidgets = true
    } label: {
        Image(systemName: "slider.horizontal.3")
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.primary)
            .frame(width: 32, height: 32)
            .background(Color(uiColor: .tertiarySystemFill), in: Circle())
    }
    MistiaNotificationBellLink()
}
```

### 2. Sheet Presentation (`OverviewWidgetManagementSheet`)
A dedicated view `OverviewWidgetManagementSheet` presented via `.sheet(isPresented: $isManagingWidgets)`.
- Features `NavigationView` / `NavigationStack`, `List`, `onMove`, `Toggle`, and "Khôi phục" (Reset) functionality.

---

## Verification Plan

### Automated Build & Unit Tests
- Execute `swift test` or build scheme in Xcode/Swift CLI to ensure model serialization and `OverviewSectionItemConfig.defaultConfig` function correctly without breaking existing logic.

### Manual UI Verification
- Tap the top-bar slider button on Overview screen.
- Verify default states (Investment OFF, 4 other sections ON).
- Toggle Investment ON and move it to top position.
- Tap "Xong" (Done) and confirm Overview screen immediately shows Investment card below Hero card.
- Tap "Khôi phục" (Reset) and confirm default order & visibility is restored.
