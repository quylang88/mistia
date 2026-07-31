# Design Spec: Redesign Màn Hình Sao Lưu & Khôi Phục (iOS 26 Native Minimalist)

**Ngày khởi tạo:** 2026-08-01  
**Mục tiêu:** Cải tiến lại giao diện `ManagementBackupRestoreView` trong ứng dụng Mistia theo phong cách tối giản (minimalist) chuẩn iOS Native, giảm bớt chi tiết rối mắt, tăng tính trực quan và nâng cao trải nghiệm người dùng.

---

## 1. Vấn Đề Hiện Tại

Màn hình `ManagementBackupRestoreView` hiện tại có một số hạn chế về mặt trải nghiệm và thẩm mỹ:
1. **Quá nhiều thẻ thông tin dồn dập (Information Clutter)**: Thẻ thông báo khẩn cấp (Emergency snapshot card) và thông tin tóm tắt bản sao lưu (`latestSummary`) hiển thị tràn lan 13 chỉ số thống kê dưới dạng văn bản thuần kéo dài.
2. **Cài đặt chế độ khôi phục bị phơi bày trực tiếp (Exposed Mode Picker)**: Đoạn segmented picker chọn chế độ (Gộp dữ liệu / Thay thế dữ liệu) nằm cố định ngay chính giữa màn hình kèm văn bản mô tả dài, làm phân tâm người dùng khi họ chỉ muốn tạo bản sao lưu.
3. **Thứ tự ưu tiên chưa hợp lý (Lack of Visual Hierarchy)**: Chưa có khu vực Hero nổi bật cho biết trạng thái sao lưu hiện tại của ứng dụng.

---

## 2. Giải Pháp Thiết Kế (Phương Án A: Hero Status & Native Grouped List)

### 2.1 Cấu Trúc Giao Diện Mới

Giao diện sẽ được tổ chức lại theo 3 khối chính trong `MistiaPinnedTopBarScaffold`:

1. **Khối Status Hero (Thẻ Trạng Thái Sao Lưu Top Card)**:
   - Đặt ở vị trí trên cùng của nội dung màn hình.
   - Hiển thị biểu tượng trạng thái trực quan (màu xanh lá khi có sao lưu / màu trung tính khi chưa sao lưu).
   - Dòng tiêu đề chính: **"Bản sao lưu gần nhất"** hoặc **"Trạng thái sao lưu"**.
   - Dòng phụ: Thời gian xuất gần nhất, phiên bản ứng dụng (`appVersion` / `appBuild`) và tổng số bản ghi.
   - Nút hành động phụ: Nút **"Chi tiết"** (kích hoạt Bottom Sheet hoặc Alert xem phân rã số liệu chi tiết `localizedBreakdown` thay vì hiển thị trực tiếp làm rối mắt).

2. **Khối Thao Tác Chính (Action Group Card - `ManagementProfileListCard`)**:
   - Chứa 2 hàng hành động chuẩn iOS Inset Grouped Row:
     - **Tạo bản sao lưu mới**: Biểu tượng `square.and.arrow.up.fill` (màu Blue), tiêu đề "Tạo bản sao lưu mới", phụ đề "Xuất toàn bộ dữ liệu hiện tại ra tệp .mistiabackup".
     - **Khôi phục từ tệp**: Biểu tượng `square.and.arrow.down.fill` (màu Mint), tiêu đề "Khôi phục từ tệp", phụ đề "Chọn tệp sao lưu để nhập dữ liệu vào ứng dụng".

3. **Khối Tùy Chọn Cấu Hình (Options Group Card - `ManagementProfileListCard`)**:
   - Dòng **Chế độ khôi phục**: Sử dụng dạng Menu Picker (`.pickerStyle(.menu)`) góc phải thay vì Segmented control chiếm nhiều không gian.
   - Mặc định chọn: **Gộp dữ liệu (Khuyên dùng)**.
   - Dòng phụ đề hiển thị ngắn gọn ý nghĩa của chế độ đang chọn (`restoreMode.localizedDescription`).

4. **Khối Cảnh Báo & An Toàn (Khi có sự kiện Restore)**:
   - Thẻ hiển thị bản sao lưu an toàn tự động (`internalSafetySnapshot`) nếu vừa thực hiện khôi phục thay thế.
   - Thẻ nhắc nhở đồng bộ Cloud nếu cờ `isManualSyncRequiredAfterRestore` bật.

---

## 3. Chi Tiết Kỹ Thuật (Technical Implementation)

### 3.1 Vị trí File Chỉnh Sửa
- `Mistia/Features/Management/ManagementAuthView.swift`: Thay thế & tái cấu trúc struct `ManagementBackupRestoreView`.

### 3.2 State Management
Giữ nguyên các biến state điều khiển logic backend:
- `@State private var restoreMode: MistiaBackupRestoreMode = .merge`
- `@State private var isImporting = false`
- `@State private var isRestoring = false`
- `@State private var shareItem: TransactionShareItem?`
- `@State private var latestSummary: MistiaBackupValidationSummary?`
- `@State private var latestRestoreResult: MistiaBackupRestoreResult?`
- `@State private var alert: ManagementBackupAlert?`
- **Thêm mới**: `@State private var showSummaryDetailSheet = false` để hiển thị trang/sheet chi tiết thông số thống kê bản sao lưu khi bấm vào nút "Chi tiết".

---

## 4. Kế Hoạch Kiểm Thử (Verification Plan)

1. **Kiểm thử Xuất Sao Lưu (Export Backup)**:
   - Thao tác bấm nút "Tạo bản sao lưu mới" -> Xác nhận file `.mistiabackup` được tạo và mở Share Sheet.
   - Thẻ Hero Card cập nhật trạng thái mới nhất ngay sau khi xuất.

2. **Kiểm thử Khôi Phục (Restore Backup)**:
   - Thao tác chuyển chế độ "Gộp dữ liệu" và "Thay thế dữ liệu" thông qua Menu Picker.
   - Bấm "Khôi phục từ tệp" -> Chọn file -> Kiểm tra thông báo hoàn tất và sự xuất hiện của Safety Snapshot Card (nếu replace).

3. **Kiểm thử Chi Tiết Thống Kê (Summary Details Sheet)**:
   - Thao tác bấm vào nút "Chi tiết" ở Hero Card -> Kiểm tra sheet hiển thị đầy đủ thông số thống kê bản ghi mà không làm rối màn hình chính.
