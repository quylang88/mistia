# Redesign First Sync Choice Modal

Redesign the first-sync option sheet to match Apple's native iOS 26 design style with glassmorphism, clean layouts, and professional copywriting.

## Proposed Changes

### Wording & Localization

#### [MODIFY] [Localizable.xcstrings](file:///Users/quylang/Projects/mistia/Mistia/Localizable.xcstrings)
Update the translations for keys under `management.managementauth.*` to use professional, production-ready language.

- **Merge Safely (`mergeSafely`):**
  - **Vietnamese Title:** `Hợp nhất dữ liệu`
  - **Vietnamese Subtitle:** `Kết hợp dữ liệu từ thiết bị này và đám mây, bảo toàn tất cả các giao dịch mà không ghi đè.`
  - **English Title:** `Merge Data`
  - **English Subtitle:** `Combine device and cloud records, preventing any data loss or duplicate transactions.`
  - **Japanese Title:** `データをマージする`
  - **Japanese Subtitle:** `端末とクラウドの両方のデータを統合し、データの消失や重複を防ぎます。`

- **Use This Device (`useThisDevice`):**
  - **Vietnamese Title:** `Sử dụng dữ liệu thiết bị`
  - **Vietnamese Subtitle:** `Ghi đè dữ liệu trên đám mây bằng dữ liệu hiện tại từ thiết bị này.`
  - **English Title:** `Use Device Data`
  - **English Subtitle:** `Replace cloud data with the current data from this device.`
  - **Japanese Title:** `端末のデータを使用`
  - **Japanese Subtitle:** `クラウド上のデータをこの端末のデータで上書きします。`

- **Use Cloud (`useCloud2`):**
  - **Vietnamese Title:** `Sử dụng dữ liệu đám mây`
  - **Vietnamese Subtitle:** `Ghi đè dữ liệu trên thiết bị này bằng dữ liệu tải về từ đám mây.`
  - **English Title:** `Use Cloud Data`
  - **English Subtitle:** `Replace this device's data with the data downloaded from the cloud.`
  - **Japanese Title:** `クラウドのデータを使用`
  - **Japanese Subtitle:** `この端末のデータをクラウドからダウンロードしたデータで上書きします。`

- **Description Headers:**
  - **No Cloud Data Yet (`theCloudHasNoDataYetExcept`):**
    - **Vietnamese:** `Đám mây hiện chưa có dữ liệu. Thiết bị này đang có %@ bản ghi. Vui lòng chọn cách bạn muốn bắt đầu đồng bộ.`
    - **English:** `The cloud has no data yet. This device has %@ records. Choose how you want to initialize synchronization.`
  - **Both Have Data (`thisDeviceHasValueRecordsAndThe`):**
    - **Vietnamese:** `Thiết bị này có %@ bản ghi và đám mây có %@ bản ghi. Vui lòng chọn phương án xử lý để bắt đầu đồng bộ.`
    - **English:** `This device has %@ records and the cloud has %@ records. Select an option to resolve and start syncing.`

---

### UI & Styling Redesign

#### [MODIFY] [ManagementAuthView.swift](file:///Users/quylang/Projects/mistia/Mistia/Features/Management/ManagementAuthView.swift)

1. **Add `ManagementInitialSyncChoiceButtonBackground`:**
   A custom background wrapper matching `ManagementPendingAuthenticationOptionBackground` supporting:
   - Rounded rectangle of corner radius 20
   - Proper dark/light mode background tint (subtle opacity-based)
   - `.glassEffect(...)` on iOS 26.0+
   - A stroke border (subtle border lines)

2. **Refactor `ManagementInitialSyncChoiceButton`:**
   - Change styling from custom plain boxes to elegant lists cards.
   - Accept an `iconName: String` to show a circular-styled symbol badge on the left side of the content.
   - Stack `title` (semibold, size 15.5) and `detail` (medium, size 13) vertically.
   - Align the recommended capsule badge next to the title or inside the card header.
   - Add a trailing `chevron.right` (or `arrow.right`) icon on the right end of the card.
   - Set `.buttonStyle(.plain)`.

3. **Refactor `ManagementInitialSyncChoiceSheet`:**
   - Remove redundant margins and raw vertical layouts.
   - Place a beautiful large sync symbol (`arrow.triangle.2.circlepath.icloud.fill`) at the top, centered.
   - Format the header description so it sits neatly in a centered layout.
   - Present the choices in a clean, scrollable card group.
   - Retain the top-left cancel toolbar item.

## Verification Plan

### Automated Tests
- Build the Mistia target to ensure there are no compilation errors or deprecated code syntax warnings.
  ```bash
  swift build
  ```

### Manual Verification
- Verify the layout matches standard native iOS bottom sheets in Xcode preview or on simulator device.
