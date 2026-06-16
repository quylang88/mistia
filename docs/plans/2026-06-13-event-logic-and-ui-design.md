# Thiết kế logic và UI cho sự kiện chia chi phí (Shared Expense Event)

## 1. Tổng quan
Tài liệu này đặc tả thiết kế cải tiến cho các sự kiện chia chi phí (Shared Expense Event), logic hoàn tất sự kiện, giao diện theo dõi tiến độ thanh toán của từng thành viên, khóa chỉnh sửa các khoản nợ đã tất toán, bổ sung bộ lọc "Sự kiện" vào danh sách giao dịch, và đồng bộ hóa empty state của phần thông báo.

---

## 2. Các thay đổi đề xuất

### 2.1. Bộ lọc "Sự kiện" trong Danh sách Giao dịch
- **Vị trí**: Nằm trong menu bộ lọc Phân loại (Type) của danh sách giao dịch (`selectedSegment` ở `TransactionsView.swift`).
- **Logic hoạt động**:
  - Thêm case `.event` vào enum `TransactionSegment`.
  - Khi người dùng chọn phân loại "Sự kiện", danh sách sẽ hiển thị tất cả các sự kiện (`SettlementGroup` có `kind == .sharedExpense`, bao gồm cả đang chuẩn bị, đang thanh toán và đã hoàn tất).
  - Từng dòng sự kiện được biểu diễn bằng `EventCashflowRow` (tương tự như một giao dịch thông thường):
    - Left: Icon `"mistia.settlement.event"` màu tím (`MistiaAccent.purple.color`), tương ứng với Fluent Asset `"ic_fluent_people_team_24_color"` và fallback system icon `"person.2.fill"` (với badge `"calendar.badge.clock"`, đã được cấu hình trong `MistiaFinanceIcons.swift`).
    - Middle: Tiêu đề sự kiện, phụ đề hiển thị danh sách người tham gia và số lượng bill liên kết.
    - Right: Tổng số tiền của sự kiện (`totalPaidMinor`).
    - Tương tác: Chạm vào dòng sự kiện sẽ hiển thị modal chia chi phí (`SettlementSplitCalculatorSheet`).

### 2.2. Tiến độ Thanh toán Sự kiện & Điều kiện biến mất
- **Điều kiện biến mất**: Sự kiện chỉ biến mất khỏi danh mục "Sự kiện đang diễn ra" khi tất cả mọi người hoàn tất thanh toán (trạng thái group chuyển sang `.settled`).
  - Thay đổi logic lọc trong `SettlementLogic.preparingEventSnapshots` để trả về các sự kiện có trạng thái khác `.settled` (bao gồm `.preparing`, `.open`, `.partiallySettled`).
- **Giao diện tiến độ chia chi phí & tính lại**:
  - **Chuyển đổi trạng thái hiển thị tiến độ**: Khi người dùng ở màn hình nhập tiền cho từng người (trạng thái sự kiện là `.preparing`), sau khi nhập xong họ nhấn nút checkmark (lưu) ở góc trên bên phải. Nhấn nút này sẽ gọi hàm `finalizeSplit()`, tạo ra các giao dịch nợ tương ứng (`LedgerTransaction` với role `.sharedExpenseReceivable` hoặc `.sharedExpensePayable`) cho từng thành viên và cập nhật trạng thái sự kiện (`group.status`) thành `.open`.
  - Lúc này, vì `isFinalized == true`, giao diện sẽ ẩn phần nhập liệu số tiền và hiển thị danh sách tiến độ thanh toán của từng thành viên (`ParticipantSettlementProgressRow`):
    - Thành viên đã trả xong: Hiển thị icon check xanh lá, phụ đề `"Đã thanh toán xong"`, bên phải hiển thị chữ `"Đã xong"`.
    - Người còn nợ ta: Hiển thị icon nợ thu về (`arrow.down.left`), phụ đề `"Đã trả: X • Còn lại: Y"`. Nhấp vào sẽ mở modal thu nợ (`DebtSettlementSheet`).
    - Ta còn nợ người: Hiển thị icon nợ trả đi (`arrow.up.right`), phụ đề `"Bạn đã trả: X • Còn lại: Y"`. Nhấp vào sẽ mở modal trả nợ (`DebtSettlementSheet`).
  - **Sửa đổi số tiền đã nhập (Chia lại chi phí)**: Để chỉnh sửa hoặc tính toán lại số tiền đã nhập cho từng người sau khi đã chốt phân chia, người dùng có thể nhấp vào nút **"Chia lại chi phí"** (có icon `"arrow.counterclockwise"` màu đỏ/destructive) trong mục tổng quan ở trên đầu.
    - Khi nhấp vào, app sẽ hiển thị một confirmation alert để xác nhận hành động.
    - Nếu người dùng đồng ý, app sẽ chạy hàm `resetSplitToPreparing()`, xóa/hủy bỏ các giao dịch nợ/thanh toán cũ thuộc sự kiện này, đặt lại các trường số tiền thu/trả của sự kiện và đưa trạng thái sự kiện về `.preparing`.
    - Giao diện sẽ tự động chuyển ngược lại trạng thái nhập liệu thủ công để người dùng điều chỉnh số tiền và bấm checkmark lưu lại.

### 2.3. Khóa chỉnh sửa các khoản nợ đã hoàn tất
- **Phạm vi áp dụng**: `DebtSettlementSheet` (modal thu nợ/trả nợ của nhóm) và `SettlementDetailSheet` (modal của resale/khoản nợ đơn).
- **Hành vi**:
  - Khi khoản nợ đã tất toán hoàn toàn (số tiền còn lại bằng 0):
    - Ẩn ô nhập số tiền và nút chọn ví thanh toán.
    - Hiển thị dòng thông báo ở giữa: `"Khoản nợ này đã được thanh toán hoàn tất"` màu secondary.
    - Ẩn nút checkmark (lưu) trên thanh công cụ.

### 2.4. Đồng nhất Empty State cho Thông báo
- **Thay đổi**: Cập nhật `emptyState` trong `NotificationCenterView.swift` sử dụng component dùng chung `MistiaEmptyStateContent`.
- **Thông số**:
  - Title: `L10n.notifications.notificationcenter.noNotificationsYet`
  - Message: `L10n.notifications.notificationcenter.permissionRequestsAndFamilyActivityWillAppear`
  - Icons: `["bell.slash.fill", "bell.badge", "envelope.badge"]`
  - Accent color: `MistiaAccent.purple.color`

---

## 3. Kế hoạch xác minh

### 3.1. Xác minh tự động
- Đảm bảo dự án Swift build thành công và chạy bộ kiểm thử để xác nhận không lỗi biên dịch:
  ```bash
  swift build
  ```

### 3.2. Xác minh thủ công
- Mở danh sách giao dịch, chọn bộ lọc Phân loại -> Sự kiện, xác nhận danh sách sự kiện hiển thị đúng và chạm vào mở đúng modal chi tiết.
- Thực hiện chốt chia chi phí một sự kiện mới, xác nhận trạng thái chuyển thành đang thanh toán, hiển thị đầy đủ tiến độ thu/trả nợ của từng người tham gia.
- Ghi nhận thanh toán một khoản nợ cho đến khi tất toán hoàn toàn, xác nhận modal nợ chuyển sang trạng thái chỉ đọc và hiển thị thông tin tất toán.
- Kiểm tra mục thông báo trống hiển thị đúng Empty State mới đồng nhất.
