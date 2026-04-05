# Hướng dẫn Quản lý Supabase Migration

Chào bạn,

Bạn đã tạo bảng trực tiếp trên Supabase và copy nội dung file migration ở local lên SQL Editor chạy tay 1 lần rồi. Việc này làm cho trạng thái database trên server và lịch sử migration dưới máy local của bạn bị lệch.

Bây giờ bạn muốn thiết lập lại quy trình chuẩn (dùng migration để quản lý từ nay về sau), bạn hãy làm theo các bước sau nhé:

## Bước 1: Cài đặt Supabase CLI

Vì bạn chưa cài Supabase CLI nên bạn cần cài đặt nó trước. Cách cài đặt phổ biến nhất là dùng Homebrew (nếu bạn dùng macOS/Linux) hoặc npm.

**Dùng Homebrew (macOS/Linux):**
```bash
brew install supabase/tap/supabase
```

**Dùng npm (Yêu cầu có Node.js):**
```bash
npm install -g supabase
```

Sau khi cài đặt xong, bạn gõ lệnh sau để kiểm tra:
```bash
supabase --version
```
(Nếu hiện ra phiên bản, ví dụ `1.x.x` là thành công).

---

## Bước 2: Đăng nhập và liên kết dự án (Link project)

Mở terminal, trỏ đường dẫn vào thư mục gốc của project của bạn.

**1. Đăng nhập vào tài khoản Supabase trên máy của bạn:**
```bash
supabase login
```
Lệnh này sẽ mở trình duyệt để bạn cấp quyền. Nếu bạn ở môi trường không có trình duyệt, nó sẽ yêu cầu bạn cấp một Access Token.

**2. Liên kết project của bạn với Supabase CLI:**
Bạn đã có lệnh này trên dashboard:
```bash
supabase link --project-ref wkbrtstnmoknmamddezg
```
Khi chạy lệnh này, Supabase CLI có thể hỏi mật khẩu database của dự án. Nếu bạn quên, bạn có thể vào Supabase Dashboard -> **Project Settings** -> **Database** -> **Database password** để reset.

---

## Bước 3: Đồng bộ lịch sử Migration (Sửa lỗi do lỡ chạy tay)

Hiện tại ở máy bạn đã có file migration (ví dụ `20260403000000_mistia_sync.sql`), và bạn **đã copy code trong đó lên SQL Editor chạy rồi**.

Nếu bây giờ bạn chạy `supabase db push`, CLI sẽ cố gắng chạy lại file đó một lần nữa. Tùy vào code SQL mà có thể báo lỗi "Table already exists" (bảng đã tồn tại) hoặc các lỗi khác.

**Để giải quyết, bạn cần nói cho Supabase biết rằng: "Tôi đã chạy file migration này rồi, đừng chạy lại nữa!"**.

Chạy lệnh sau:
```bash
# Đầu tiên lấy danh sách các file migration ở local (mục đích để biết tên/ID phiên bản)
ls -la supabase/migrations/
```

Sau đó chạy lệnh `supabase migration repair` và cung cấp chuỗi số (version) của file migration đó.
Ví dụ file của bạn tên là `20260403000000_mistia_sync.sql`:

```bash
# Đánh dấu migration này CÓ TRẠNG THÁI LÀ ĐÃ CHẠY (applied) trên server
supabase migration repair --status applied 20260403000000
```
*(Nếu bạn copy chạy tay nhiều file, hãy lặp lại lệnh này cho từng file với phần số phiên bản tương ứng).*

---

## Bước 4: Quy trình chuẩn từ nay về sau (Best Practice)

Kể từ bây giờ, bất cứ khi nào bạn muốn tạo bảng mới, thêm cột, xoá bảng... **tuyệt đối không làm trên giao diện Supabase (SQL Editor hay Table Editor) nữa**. Thay vào đó hãy làm theo luồng này:

**1. Tạo file migration mới:**
```bash
supabase migration new them_bang_users
```
Lệnh này sẽ tạo ra một file SQL rỗng trong thư mục `supabase/migrations/` (ví dụ: `20260405000000_them_bang_users.sql`).

**2. Viết SQL:**
Mở file vừa tạo ra và viết code SQL vào (ví dụ `CREATE TABLE users ...;`).

**3. Đẩy lên server Supabase:**
Chạy lệnh:
```bash
supabase db push
```
Supabase sẽ tự động tìm những file migration **chưa được chạy**, đẩy code SQL lên server thực thi, và ghi lại lịch sử.

### Tóm tắt nếu bạn muốn kéo code cũ trên server về máy:
Nếu lỡ trên server có thay đổi mà máy bạn không có, bạn có thể kéo thay đổi đó về thành file SQL bằng lệnh:
```bash
supabase db pull
```

Chúc bạn thành công! Nếu gặp lỗi ở bước nào, hãy copy lỗi đó cho mình xem nhé.
