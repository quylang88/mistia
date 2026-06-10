# Design Doc: Category and Shortcut Icons Redesign

## Goal
Improve the user interface by replacing mismatched category icons with suitable Fluent UI icons, and redesign the tab bar shortcut icons to be line-art (outline) style with their own characteristic colors (matching the style of the "Scan Bill" shortcut).

---

## 1. Category Icons Redesign

### Target Mappings in `MistiaFinanceIcons.swift`
We will update the `fluentAssetNamesByToken` mapping to map category tokens to their new Fluent icons.

| Category ID | Vietnamese Name | Current Icon | New Icon Asset | Source / Style |
| :--- | :--- | :--- | :--- | :--- |
| `footwear` | Giày dép | `ic_fluent_premium_24_color` | `ic_fluent_person_walking_24_filled` | Fluent System Icon (Filled) |
| `diapers_milk` | Bỉm / tã | `ic_fluent_heart_24_color` | `ic_fluent_teddy_bear_24_color` | Fluent Emoji (Flat SVG) |
| `daily_supplies` | Đồ tiêu dùng | `ic_fluent_scan_type_24_color` | `ic_fluent_cart_24_filled` | Fluent System Icon (Filled) |
| `baby_food` | Sữa / đồ ăn dặm | `ic_fluent_food_24_color` | `ic_fluent_bowl_salad_24_filled` | Fluent System Icon (Filled) |
| `baby_gear` | Xe đẩy / nôi / đồ sơ sinh | `ic_fluent_home_24_color` | `ic_fluent_cube_24_filled` | Fluent System Icon (Filled) |
| `child_supplies` | Quần áo / đồ dùng cho bé | `ic_fluent_people_team_24_color` | `ic_fluent_backpack_24_filled` | Fluent System Icon (Filled) |
| `tolls` | Phí cầu đường | `ic_fluent_receipt_24_color` | `ic_fluent_road_24_filled` | Fluent System Icon (Filled) |
| `dental` | Nha khoa | `ic_fluent_clipboard_text_edit_24_color` | `ic_fluent_tooth_24_color` | Fluent Emoji (Flat SVG) |
| `supplements` | Thực phẩm bổ sung | `ic_fluent_reward_24_color` | `ic_fluent_pill_24_filled` | Fluent System Icon (Filled) |

### Asset Management
The following new assets will be added to `Mistia/Assets.xcassets`:
- `ic_fluent_person_walking_24_filled`
- `ic_fluent_teddy_bear_24_color` (from Microsoft Fluent Emoji `Teddy bear/Flat/teddy_bear_flat.svg`)
- `ic_fluent_cart_24_filled`
- `ic_fluent_bowl_salad_24_filled`
- `ic_fluent_cube_24_filled`
- `ic_fluent_backpack_24_filled`
- `ic_fluent_road_24_filled`
- `ic_fluent_tooth_24_color` (from Microsoft Fluent Emoji `Tooth/Flat/tooth_flat.svg`)
- `ic_fluent_pill_24_filled`

Each asset will have its own directory `.imageset` containing:
- The SVG file
- A `Contents.json` file configuring it as a universal vector image preserving vector representation.

---

## 2. Tab Bar Shortcut Icons Redesign

### Icon Style (Filled -> Outline)
We will modify the SF Symbol names inside `MistiaShortcutLogic.swift` for the shortcut presentation to use outline/line-art symbols instead of filled ones:

- `.backupRestore`: `externaldrive.badge.icloud` (from `externaldrive.fill.badge.icloud`)
- `.archivedItems`: `archivebox` (from `archivebox.fill`)
- `.familyOverview`: `shareplay` (from `person.2.fill`)
- `.syncNow`: `arrow.triangle.2.circlepath.icloud` (from `arrow.triangle.2.circlepath.icloud.fill`)

### Custom Rasterization Tints
We will update `MistiaNativeTabShell.swift` to rasterize all shortcut system images using their own characteristic colors rather than the default template mode.

We will define a `currentShortcutTint` property in `MistiaNativeTabBarController`:
- `.backupRestore` (Mint): Light: `#00a68c`, Dark: `#66d8bf`
- `.archivedItems` (Slate): Light: `#737b91`, Dark: `#a6adb0`
- `.familyOverview` (Indigo): Light: `#594dfc`, Dark: `#8c80ff`
- `.memberOverview` (Rose): Light: `#dc3375`, Dark: `#ff75a9`
- `.receiptScan` (Amber): Light: `#ed8529`, Dark: `#ffb847`
- `.syncNow` (Sky): Light: `#3394e6`, Dark: `#80c7ff`

And apply this tint dynamically when returning the shortcut tab image:
```swift
private func shortcutSystemImage(_ systemName: String) -> UIImage? {
  let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)
  let image = UIImage(systemName: systemName, withConfiguration: config)
  return image?.mistiaRasterized(with: currentShortcutTint)
}
```

---

## Verification Plan

### Automated Tests
- Run `swift build` and `swift test` to ensure there are no compilation errors in CoreLogic.

### Manual Verification
- Compile and run the app in the Simulator.
- Verify that the updated categories (Giày dép, Bỉm tã, Đồ tiêu dùng, Sữa/đồ ăn dặm, Xe đẩy, Quần áo bé, Phí cầu đường, Nha khoa, Thực phẩm bổ sung) display their new correct icons.
- Go to Settings -> Mistia Shortcut.
- Enable the shortcut and toggle different options (Receipt Scan, Family Overview, Backup & Restore, Archive, Sync Now).
- Verify that the tab bar icon updates immediately to the new outline style and uses its specific characteristic color in both light and dark mode.
