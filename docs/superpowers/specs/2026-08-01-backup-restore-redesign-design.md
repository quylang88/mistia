# Design Spec: Redesign Màn Hình Sao Lưu & Khôi Phục (iOS 26 Native Minimalist V2)

**Ngày cập nhật:** 2026-08-01  
**Mục tiêu:** Cải tiến lại giao diện `ManagementBackupRestoreView` trong ứng dụng Mistia theo chuẩn thiết kế tối giản tuyệt đối (Ultra-Minimalist) của Apple iOS 26, loại bỏ hoàn toàn chữ thừa, banner khẩn cấp gây rối mắt và tinh chỉnh khối tùy chọn Gộp/Thay thế chuẩn Apple Settings.

---

## 1. Các Thay Đổi V2 (Ultra-Minimalist)

### 1.1 Loại Bỏ Banner Khẩn Cấp & Tinh Chỉnh Hero Card Top
- **Xóa bỏ**: `ManagementInlineMessageCard` ("Ảnh chụp tức thì khẩn cấp").
- **Hero Card**:
  - Dạng card trung tâm với icon đám mây/bảo mật.
  - Dòng tiêu đề: **"Bản sao lưu thiết bị"**.
  - Dòng trạng thái phụ: `"Lần sao lưu gần nhất: HH:mm, DD/MM/YYYY"` (hoặc `"Chưa có bản sao lưu nào"`).
  - Pill badge nhỏ gọn: `"[X] bản ghi ℹ️"` để kích hoạt Bottom Sheet xem thông số chi tiết khi cần.

### 1.2 Rút Gọn Chữ Thao Tác (Action Group Card)
- **Tạo bản sao lưu ngay**: Loại bỏ subtitle dài dòng. Chỉ giữ tiêu đề hành động sắc nét.
- **Khôi phục từ tệp...**: Loại bỏ subtitle dài dòng. Chỉ giữ tiêu đề hành động sắc nét.

### 1.3 Tinh Chỉnh Khối Chế Độ Khôi Phục (Restore Mode Options)
- Thẻ tùy chọn `ManagementProfileListCard` chỉ chứa 1 hàng duy nhất:
  - Trái: **Chế độ nhập**
  - Phải: `Picker` dạng Menu (`.pickerStyle(.menu)`) chọn `Gộp dữ liệu` hoặc `Thay thế`.
- Đoạn văn bản mô tả ngắn (`restoreMode.localizedDescription`) được đặt **bên ngoài card** dưới dạng **Section Footer** (`font-size: 12.5px; color: secondary`) chuẩn Apple Inset Grouped List.

---

## 2. Kế Hoạch Kiểm Thử
1. Build dự án bằng `swift build`.
2. Kiểm tra giao diện hiển thị gọn gàng, thoáng mắt, đúng chuẩn Apple iOS HIG.
