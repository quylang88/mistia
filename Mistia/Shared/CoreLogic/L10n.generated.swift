// Generated file. Do not edit manually.
// Source: Mistia/Localizable.xcstrings

import Foundation

nonisolated enum L10n {
    fileprivate static func tr(_ key: String, vi: String, en: String, ja: String, language: MistiaAppLanguage = .current) -> String {
        switch language {
        case .vietnamese:
            return vi
        case .english:
            return en
        case .japanese:
            return ja
        }
    }

    fileprivate static func format(_ key: String, vi: String, en: String, ja: String, language: MistiaAppLanguage = .current, _ arguments: CVarArg...) -> String {
        let format = tr(key, vi: vi, en: en, ja: ja, language: language)
        return withVaList(arguments) { pointer in
            NSString(format: format, locale: language.locale as NSLocale, arguments: pointer) as String
        }
    }

    nonisolated enum app {

        nonisolated enum mistia {
            static var loadingYourData: String { L10n.tr("app.mistia.loadingYourData", vi: "Đang tải dữ liệu...", en: "Loading your data...", ja: "データを読み込み中...") }
            static func loadingYourData(language: MistiaAppLanguage) -> String { L10n.tr("app.mistia.loadingYourData", vi: "Đang tải dữ liệu...", en: "Loading your data...", ja: "データを読み込み中...", language: language) }
            static var localDataHasBeenKeptOnThis: String { L10n.tr("app.mistia.localDataHasBeenKeptOnThis", vi: "Dữ liệu local vẫn được giữ nguyên trên máy", en: "Local data has been kept on this device", ja: "ローカルデータはこの端末に保持されています") }
            static func localDataHasBeenKeptOnThis(language: MistiaAppLanguage) -> String { L10n.tr("app.mistia.localDataHasBeenKeptOnThis", vi: "Dữ liệu local vẫn được giữ nguyên trên máy", en: "Local data has been kept on this device", ja: "ローカルデータはこの端末に保持されています", language: language) }
            static var mistiaIsProtectingYourData: String { L10n.tr("app.mistia.mistiaIsProtectingYourData", vi: "Mistia đang bảo vệ dữ liệu của bạn", en: "Mistia is protecting your data", ja: "ミスティアはデータを保護しています") }
            static func mistiaIsProtectingYourData(language: MistiaAppLanguage) -> String { L10n.tr("app.mistia.mistiaIsProtectingYourData", vi: "Mistia đang bảo vệ dữ liệu của bạn", en: "Mistia is protecting your data", ja: "ミスティアはデータを保護しています", language: language) }
            static var switchingSession: String { L10n.tr("app.mistia.switchingSession", vi: "Đang chuyển phiên...", en: "Switching session...", ja: "セッションを切り替えています...") }
            static func switchingSession(language: MistiaAppLanguage) -> String { L10n.tr("app.mistia.switchingSession", vi: "Đang chuyển phiên...", en: "Switching session...", ja: "セッションを切り替えています...", language: language) }
            static var technicalDetails: String { L10n.tr("app.mistia.technicalDetails", vi: "Chi tiết kỹ thuật", en: "Technical details", ja: "技術的な詳細") }
            static func technicalDetails(language: MistiaAppLanguage) -> String { L10n.tr("app.mistia.technicalDetails", vi: "Chi tiết kỹ thuật", en: "Technical details", ja: "技術的な詳細", language: language) }
            static var theAppCouldnTOpenTheLocal: String { L10n.tr("app.mistia.theAppCouldnTOpenTheLocal", vi: "Ứng dụng không thể mở cơ sở dữ liệu cục bộ sau khi cập nhật. Mistia đã chuyển sang chế độ an toàn và không xóa dữ liệu trên máy.", en: "The app couldn't open the local database after the update. Mistia switched to safe mode and did not delete the data on this device.", ja: "アップデート後にローカルデータベースを開けなかったため、ミスティアはセーフモードに切り替わり、この端末のデータは削除していません。") }
            static func theAppCouldnTOpenTheLocal(language: MistiaAppLanguage) -> String { L10n.tr("app.mistia.theAppCouldnTOpenTheLocal", vi: "Ứng dụng không thể mở cơ sở dữ liệu cục bộ sau khi cập nhật. Mistia đã chuyển sang chế độ an toàn và không xóa dữ liệu trên máy.", en: "The app couldn't open the local database after the update. Mistia switched to safe mode and did not delete the data on this device.", ja: "アップデート後にローカルデータベースを開けなかったため、ミスティアはセーフモードに切り替わり、この端末のデータは削除していません。", language: language) }
            static var theAppWillNotCreateAReplacement: String { L10n.tr("app.mistia.theAppWillNotCreateAReplacement", vi: "App sẽ không tự tạo DB mới để tránh ghi đè hoặc đồng bộ nhầm", en: "The app will not create a replacement database that could overwrite or sync bad state", ja: "上書きや誤同期を防ぐため、代わりのデータベースは自動作成しません") }
            static func theAppWillNotCreateAReplacement(language: MistiaAppLanguage) -> String { L10n.tr("app.mistia.theAppWillNotCreateAReplacement", vi: "App sẽ không tự tạo DB mới để tránh ghi đè hoặc đồng bộ nhầm", en: "The app will not create a replacement database that could overwrite or sync bad state", ja: "上書きや誤同期を防ぐため、代わりのデータベースは自動作成しません", language: language) }
        }

        nonisolated enum mistianativetab {
            static var quickCreate: String { L10n.tr("app.mistianativetab.quickCreate", vi: "Tạo nhanh", en: "Quick create", ja: "クイック作成") }
            static func quickCreate(language: MistiaAppLanguage) -> String { L10n.tr("app.mistianativetab.quickCreate", vi: "Tạo nhanh", en: "Quick create", ja: "クイック作成", language: language) }
        }

        nonisolated enum roottab {
            static var captureAmountAndTypeFirstThenComplete: String { L10n.tr("app.roottab.captureAmountAndTypeFirstThenComplete", vi: "Chỉ nhập số tiền và loại để hoàn thiện sau.", en: "Capture amount and type first, then complete later.", ja: "金額と種類だけ先に入れて、あとで詳細を整えます。") }
            static func captureAmountAndTypeFirstThenComplete(language: MistiaAppLanguage) -> String { L10n.tr("app.roottab.captureAmountAndTypeFirstThenComplete", vi: "Chỉ nhập số tiền và loại để hoàn thiện sau.", en: "Capture amount and type first, then complete later.", ja: "金額と種類だけ先に入れて、あとで詳細を整えます。", language: language) }
            static var chooseAReceiptImageSourceForAI: String { L10n.tr("app.roottab.chooseAReceiptImageSourceForAI", vi: "Chọn nguồn ảnh bill để AI phân tích.", en: "Choose a receipt image source for AI analysis.", ja: "AI解析に使うレシート画像の取得方法を選択します。") }
            static func chooseAReceiptImageSourceForAI(language: MistiaAppLanguage) -> String { L10n.tr("app.roottab.chooseAReceiptImageSourceForAI", vi: "Chọn nguồn ảnh bill để AI phân tích.", en: "Choose a receipt image source for AI analysis.", ja: "AI解析に使うレシート画像の取得方法を選択します。", language: language) }
            static var chooseCameraOrPhotoUploadForAI: String { L10n.tr("app.roottab.chooseCameraOrPhotoUploadForAI", vi: "Chọn chụp hoặc tải ảnh bill để AI điền thu chi.", en: "Choose camera or photo upload for AI receipt fill.", ja: "撮影または写真選択でAIが取引を入力します。") }
            static func chooseCameraOrPhotoUploadForAI(language: MistiaAppLanguage) -> String { L10n.tr("app.roottab.chooseCameraOrPhotoUploadForAI", vi: "Chọn chụp hoặc tải ảnh bill để AI điền thu chi.", en: "Choose camera or photo upload for AI receipt fill.", ja: "撮影または写真選択でAIが取引を入力します。", language: language) }
            static var chooseFromPhotos: String { L10n.tr("app.roottab.chooseFromPhotos", vi: "Chọn từ ảnh", en: "Choose from Photos", ja: "写真から選択") }
            static func chooseFromPhotos(language: MistiaAppLanguage) -> String { L10n.tr("app.roottab.chooseFromPhotos", vi: "Chọn từ ảnh", en: "Choose from Photos", ja: "写真から選択", language: language) }
            static var expense: String { L10n.tr("app.roottab.expense", vi: "Chi tiêu", en: "Expense", ja: "支出") }
            static func expense(language: MistiaAppLanguage) -> String { L10n.tr("app.roottab.expense", vi: "Chi tiêu", en: "Expense", ja: "支出", language: language) }
            static var income: String { L10n.tr("app.roottab.income", vi: "Thu nhập", en: "Income", ja: "収入") }
            static func income(language: MistiaAppLanguage) -> String { L10n.tr("app.roottab.income", vi: "Thu nhập", en: "Income", ja: "収入", language: language) }
            static var manage: String { L10n.tr("app.roottab.manage", vi: "Quản lý", en: "Manage", ja: "マネジメント") }
            static func manage(language: MistiaAppLanguage) -> String { L10n.tr("app.roottab.manage", vi: "Quản lý", en: "Manage", ja: "マネジメント", language: language) }
            static var moveMoneyInternallyOrTrackDebt: String { L10n.tr("app.roottab.moveMoneyInternallyOrTrackDebt", vi: "Chuyển nội bộ hoặc theo dõi vay & cho vay.", en: "Move money internally or track loans.", ja: "内部振替や貸し借りを記録します。") }
            static func moveMoneyInternallyOrTrackDebt(language: MistiaAppLanguage) -> String { L10n.tr("app.roottab.moveMoneyInternallyOrTrackDebt", vi: "Chuyển nội bộ hoặc theo dõi vay & cho vay.", en: "Move money internally or track loans.", ja: "内部振替や貸し借りを記録します。", language: language) }
            static var noWalletUseAccess: String { L10n.tr("app.roottab.noWalletUseAccess", vi: "Chưa có quyền sử dụng ví", en: "No wallet use access", ja: "ウォレット使用権限がありません") }
            static func noWalletUseAccess(language: MistiaAppLanguage) -> String { L10n.tr("app.roottab.noWalletUseAccess", vi: "Chưa có quyền sử dụng ví", en: "No wallet use access", ja: "ウォレット使用権限がありません", language: language) }
            static var overview: String { L10n.tr("app.roottab.overview", vi: "Tổng quan", en: "Overview", ja: "ホーム") }
            static func overview(language: MistiaAppLanguage) -> String { L10n.tr("app.roottab.overview", vi: "Tổng quan", en: "Overview", ja: "ホーム", language: language) }
            static var planning: String { L10n.tr("app.roottab.planning", vi: "Sắp tới", en: "Upcoming", ja: "予定") }
            static func planning(language: MistiaAppLanguage) -> String { L10n.tr("app.roottab.planning", vi: "Sắp tới", en: "Upcoming", ja: "予定", language: language) }
            static var quickCaptureIsForUltraLightEntries: String { L10n.tr("app.roottab.quickCaptureIsForUltraLightEntries", vi: "Ghi nhanh sẽ dùng cho những entry cần capture thật gọn. Trước mắt đây là placeholder để bạn duyệt layout và nhịp mở menu.", en: "Quick capture is for ultra-light entries. For now this is a placeholder so you can review layout and menu timing.", ja: "クイック入力は最小限の記録向けです。今はレイアウトとメニューの開き方を確認するためのプレースホルダーです。") }
            static func quickCaptureIsForUltraLightEntries(language: MistiaAppLanguage) -> String { L10n.tr("app.roottab.quickCaptureIsForUltraLightEntries", vi: "Ghi nhanh sẽ dùng cho những entry cần capture thật gọn. Trước mắt đây là placeholder để bạn duyệt layout và nhịp mở menu.", en: "Quick capture is for ultra-light entries. For now this is a placeholder so you can review layout and menu timing.", ja: "クイック入力は最小限の記録向けです。今はレイアウトとメニューの開き方を確認するためのプレースホルダーです。", language: language) }
            static var quickNote: String { L10n.tr("app.roottab.quickNote", vi: "Ghi nhanh", en: "Quick note", ja: "クイック入力") }
            static func quickNote(language: MistiaAppLanguage) -> String { L10n.tr("app.roottab.quickNote", vi: "Ghi nhanh", en: "Quick note", ja: "クイック入力", language: language) }
            static var receiptScanOpensTheTransactionModalAnd: String { L10n.tr("app.roottab.receiptScanOpensTheTransactionModalAnd", vi: "Quét bill sẽ mở modal thu chi và tự điền thông tin đọc được từ ảnh.", en: "Receipt scan opens the cashflow item modal and fills details from the image.", ja: "レシート読取は取引モーダルを開き、画像から読み取った内容を入力します。") }
            static func receiptScanOpensTheTransactionModalAnd(language: MistiaAppLanguage) -> String { L10n.tr("app.roottab.receiptScanOpensTheTransactionModalAnd", vi: "Quét bill sẽ mở modal thu chi và tự điền thông tin đọc được từ ảnh.", en: "Receipt scan opens the cashflow item modal and fills details from the image.", ja: "レシート読取は取引モーダルを開き、画像から読み取った内容を入力します。", language: language) }
            static var recordIncomeToUpdateYourBalance: String { L10n.tr("app.roottab.recordIncomeToUpdateYourBalance", vi: "Ghi nhận nguồn thu để cập nhật số dư.", en: "Record income to update your balance.", ja: "残高を更新するための収入を記録します。") }
            static func recordIncomeToUpdateYourBalance(language: MistiaAppLanguage) -> String { L10n.tr("app.roottab.recordIncomeToUpdateYourBalance", vi: "Ghi nhận nguồn thu để cập nhật số dư.", en: "Record income to update your balance.", ja: "残高を更新するための収入を記録します。", language: language) }
            static var saveAnExpenseFromAPersonalWallet: String { L10n.tr("app.roottab.saveAnExpenseFromAPersonalWallet", vi: "Lưu lại khoản chi tiêu từ ví cá nhân.", en: "Save an expense from a personal wallet.", ja: "個人のウォレットから支出を記録します。") }
            static func saveAnExpenseFromAPersonalWallet(language: MistiaAppLanguage) -> String { L10n.tr("app.roottab.saveAnExpenseFromAPersonalWallet", vi: "Lưu lại khoản chi tiêu từ ví cá nhân.", en: "Save an expense from a personal wallet.", ja: "個人のウォレットから支出を記録します。", language: language) }
            static var scanReceipt: String { L10n.tr("app.roottab.scanReceipt", vi: "Quét bill", en: "Scan receipt", ja: "レシート読取") }
            static func scanReceipt(language: MistiaAppLanguage) -> String { L10n.tr("app.roottab.scanReceipt", vi: "Quét bill", en: "Scan receipt", ja: "レシート読取", language: language) }
            static var takePhoto: String { L10n.tr("app.roottab.takePhoto", vi: "Chụp ảnh", en: "Take photo", ja: "写真を撮る") }
            static func takePhoto(language: MistiaAppLanguage) -> String { L10n.tr("app.roottab.takePhoto", vi: "Chụp ảnh", en: "Take photo", ja: "写真を撮る", language: language) }
            static var theExpenseFlowWillConnectFromThis: String { L10n.tr("app.roottab.theExpenseFlowWillConnectFromThis", vi: "Flow tạo khoản chi sẽ đi từ menu popout này. Hiện tại mình đã chốt interaction để bạn duyệt UI trước.", en: "The expense flow will connect from this popout menu. The interaction is locked in for UI review first.", ja: "支出作成フローはこのポップアウトメニューから接続されます。まずは UI レビュー用に操作感を固定しています。") }
            static func theExpenseFlowWillConnectFromThis(language: MistiaAppLanguage) -> String { L10n.tr("app.roottab.theExpenseFlowWillConnectFromThis", vi: "Flow tạo khoản chi sẽ đi từ menu popout này. Hiện tại mình đã chốt interaction để bạn duyệt UI trước.", en: "The expense flow will connect from this popout menu. The interaction is locked in for UI review first.", ja: "支出作成フローはこのポップアウトメニューから接続されます。まずは UI レビュー用に操作感を固定しています。", language: language) }
            static var theIncomeFlowWillConnectFromThis: String { L10n.tr("app.roottab.theIncomeFlowWillConnectFromThis", vi: "Flow thêm thu nhập sẽ nối từ menu này. Hiện tại đang giữ chỗ bằng sheet riêng để state không phải làm lại.", en: "The income flow will connect from this menu. A separate placeholder sheet keeps the state wiring stable for now.", ja: "収入追加フローはこのメニューから接続されます。今は状態管理を崩さないためにプレースホルダーのシートを使っています。") }
            static func theIncomeFlowWillConnectFromThis(language: MistiaAppLanguage) -> String { L10n.tr("app.roottab.theIncomeFlowWillConnectFromThis", vi: "Flow thêm thu nhập sẽ nối từ menu này. Hiện tại đang giữ chỗ bằng sheet riêng để state không phải làm lại.", en: "The income flow will connect from this menu. A separate placeholder sheet keeps the state wiring stable for now.", ja: "収入追加フローはこのメニューから接続されます。今は状態管理を崩さないためにプレースホルダーのシートを使っています。", language: language) }
            static var transactions: String { L10n.tr("app.roottab.transactions", vi: "Thu chi", en: "Cashflow", ja: "収支") }
            static func transactions(language: MistiaAppLanguage) -> String { L10n.tr("app.roottab.transactions", vi: "Thu chi", en: "Cashflow", ja: "収支", language: language) }
            static var transfer: String { L10n.tr("app.roottab.transfer", vi: "Chuyển tiền", en: "Transfer", ja: "振替") }
            static func transfer(language: MistiaAppLanguage) -> String { L10n.tr("app.roottab.transfer", vi: "Chuyển tiền", en: "Transfer", ja: "振替", language: language) }
            static var transfersBetweenSourcesWillBeConnectedHere: String { L10n.tr("app.roottab.transfersBetweenSourcesWillBeConnectedHere", vi: "Flow chuyển tiền giữa các nguồn sẽ được nối tại đây sau. Menu popout mới đã tách sẵn action riêng cho màn này.", en: "Transfers between sources will be connected here next. The new popout menu already separates the action for this screen.", ja: "資金移動フローはここに後で接続されます。この画面用のアクションは新しいポップアウトメニューですでに分かれています。") }
            static func transfersBetweenSourcesWillBeConnectedHere(language: MistiaAppLanguage) -> String { L10n.tr("app.roottab.transfersBetweenSourcesWillBeConnectedHere", vi: "Flow chuyển tiền giữa các nguồn sẽ được nối tại đây sau. Menu popout mới đã tách sẵn action riêng cho màn này.", en: "Transfers between sources will be connected here next. The new popout menu already separates the action for this screen.", ja: "資金移動フローはここに後で接続されます。この画面用のアクションは新しいポップアウトメニューですでに分かれています。", language: language) }
            static var youDoNotHaveUseAccessTo: String { L10n.tr("app.roottab.youDoNotHaveUseAccessTo", vi: "Bạn chưa có quyền sử dụng ví của thành viên này.", en: "You do not have use access to this member's wallets.", ja: "このメンバーのウォレットを使用する権限がありません。") }
            static func youDoNotHaveUseAccessTo(language: MistiaAppLanguage) -> String { L10n.tr("app.roottab.youDoNotHaveUseAccessTo", vi: "Bạn chưa có quyền sử dụng ví của thành viên này.", en: "You do not have use access to this member's wallets.", ja: "このメンバーのウォレットを使用する権限がありません。", language: language) }
        }
    }

    nonisolated enum common {
        static var appName: String { L10n.tr("common.appName", vi: "Mistia", en: "Mistia", ja: "ミスティア") }
        static func appName(language: MistiaAppLanguage) -> String { L10n.tr("common.appName", vi: "Mistia", en: "Mistia", ja: "ミスティア", language: language) }
        static var archive: String { L10n.tr("common.archive", vi: "Lưu trữ", en: "Archive", ja: "アーカイブ") }
        static func archive(language: MistiaAppLanguage) -> String { L10n.tr("common.archive", vi: "Lưu trữ", en: "Archive", ja: "アーカイブ", language: language) }
        static var cancel: String { L10n.tr("common.cancel", vi: "Hủy", en: "Cancel", ja: "キャンセル") }
        static func cancel(language: MistiaAppLanguage) -> String { L10n.tr("common.cancel", vi: "Hủy", en: "Cancel", ja: "キャンセル", language: language) }
        static var close: String { L10n.tr("common.close", vi: "Đóng", en: "Close", ja: "閉じる") }
        static func close(language: MistiaAppLanguage) -> String { L10n.tr("common.close", vi: "Đóng", en: "Close", ja: "閉じる", language: language) }
        static var delete: String { L10n.tr("common.delete", vi: "Xóa", en: "Delete", ja: "削除") }
        static func delete(language: MistiaAppLanguage) -> String { L10n.tr("common.delete", vi: "Xóa", en: "Delete", ja: "削除", language: language) }
        static var error: String { L10n.tr("common.error", vi: "Lỗi", en: "Error", ja: "エラー") }
        static func error(language: MistiaAppLanguage) -> String { L10n.tr("common.error", vi: "Lỗi", en: "Error", ja: "エラー", language: language) }
        static var off: String { L10n.tr("common.off", vi: "Tắt", en: "Off", ja: "オフ") }
        static func off(language: MistiaAppLanguage) -> String { L10n.tr("common.off", vi: "Tắt", en: "Off", ja: "オフ", language: language) }
        static var ok: String { L10n.tr("common.ok", vi: "OK", en: "OK", ja: "OK") }
        static func ok(language: MistiaAppLanguage) -> String { L10n.tr("common.ok", vi: "OK", en: "OK", ja: "OK", language: language) }
        static var on: String { L10n.tr("common.on", vi: "Bật", en: "On", ja: "オン") }
        static func on(language: MistiaAppLanguage) -> String { L10n.tr("common.on", vi: "Bật", en: "On", ja: "オン", language: language) }
        static var save: String { L10n.tr("common.save", vi: "Lưu", en: "Save", ja: "保存") }
        static func save(language: MistiaAppLanguage) -> String { L10n.tr("common.save", vi: "Lưu", en: "Save", ja: "保存", language: language) }
        static var unknownError: String { L10n.tr("common.unknownError", vi: "Lỗi không xác định", en: "Unknown error", ja: "不明なエラー") }
        static func unknownError(language: MistiaAppLanguage) -> String { L10n.tr("common.unknownError", vi: "Lỗi không xác định", en: "Unknown error", ja: "不明なエラー", language: language) }
    }

    nonisolated enum core {

        nonisolated enum ui {

            nonisolated enum mistiacategorypicker {
                static var afterYouUseCategoriesAFewTimes: String { L10n.tr("core.ui.mistiacategorypicker.afterYouUseCategoriesAFewTimes", vi: "Sau khi bạn dùng danh mục vài lần, Mistia sẽ đưa các mục xuất hiện nhiều nhất vào đây.", en: "After you use categories a few times, Mistia will surface the most-used ones here.", ja: "カテゴリを数回使うと、ミスティアがよく使う項目をここに表示します。") }
                static func afterYouUseCategoriesAFewTimes(language: MistiaAppLanguage) -> String { L10n.tr("core.ui.mistiacategorypicker.afterYouUseCategoriesAFewTimes", vi: "Sau khi bạn dùng danh mục vài lần, Mistia sẽ đưa các mục xuất hiện nhiều nhất vào đây.", en: "After you use categories a few times, Mistia will surface the most-used ones here.", ja: "カテゴリを数回使うと、ミスティアがよく使う項目をここに表示します。", language: language) }
                static var all: String { L10n.tr("core.ui.mistiacategorypicker.all", vi: "Tất cả", en: "All", ja: "すべて") }
                static func all(language: MistiaAppLanguage) -> String { L10n.tr("core.ui.mistiacategorypicker.all", vi: "Tất cả", en: "All", ja: "すべて", language: language) }
                static var close: String { L10n.tr("core.ui.mistiacategorypicker.close", vi: "Đóng", en: "Close", ja: "閉じる") }
                static func close(language: MistiaAppLanguage) -> String { L10n.tr("core.ui.mistiacategorypicker.close", vi: "Đóng", en: "Close", ja: "閉じる", language: language) }
                static var favoriteCategories: String { L10n.tr("core.ui.mistiacategorypicker.favoriteCategories", vi: "Danh mục yêu thích", en: "Favorite categories", ja: "お気に入りカテゴリ") }
                static func favoriteCategories(language: MistiaAppLanguage) -> String { L10n.tr("core.ui.mistiacategorypicker.favoriteCategories", vi: "Danh mục yêu thích", en: "Favorite categories", ja: "お気に入りカテゴリ", language: language) }
                static var favorites: String { L10n.tr("core.ui.mistiacategorypicker.favorites", vi: "Yêu thích", en: "Favorites", ja: "お気に入り") }
                static func favorites(language: MistiaAppLanguage) -> String { L10n.tr("core.ui.mistiacategorypicker.favorites", vi: "Yêu thích", en: "Favorites", ja: "お気に入り", language: language) }
                static var mostUsedInTheLastDays: String { L10n.tr("core.ui.mistiacategorypicker.mostUsedInTheLastDays", vi: "Danh mục dùng nhiều trong 90 ngày", en: "Most used in the last 90 days", ja: "過去90日でよく使ったカテゴリ") }
                static func mostUsedInTheLastDays(language: MistiaAppLanguage) -> String { L10n.tr("core.ui.mistiacategorypicker.mostUsedInTheLastDays", vi: "Danh mục dùng nhiều trong 90 ngày", en: "Most used in the last 90 days", ja: "過去90日でよく使ったカテゴリ", language: language) }
                static var noCategoriesFound: String { L10n.tr("core.ui.mistiacategorypicker.noCategoriesFound", vi: "Không tìm thấy danh mục", en: "No categories found", ja: "カテゴリが見つかりません") }
                static func noCategoriesFound(language: MistiaAppLanguage) -> String { L10n.tr("core.ui.mistiacategorypicker.noCategoriesFound", vi: "Không tìm thấy danh mục", en: "No categories found", ja: "カテゴリが見つかりません", language: language) }
                static var noChildCategories: String { L10n.tr("core.ui.mistiacategorypicker.noChildCategories", vi: "Chưa có danh mục con.", en: "No child categories.", ja: "子カテゴリがありません。") }
                static func noChildCategories(language: MistiaAppLanguage) -> String { L10n.tr("core.ui.mistiacategorypicker.noChildCategories", vi: "Chưa có danh mục con.", en: "No child categories.", ja: "子カテゴリがありません。", language: language) }
                static var noFavoriteCategoriesYet: String { L10n.tr("core.ui.mistiacategorypicker.noFavoriteCategoriesYet", vi: "Chưa có danh mục yêu thích", en: "No favorite categories yet", ja: "お気に入りカテゴリはまだありません") }
                static func noFavoriteCategoriesYet(language: MistiaAppLanguage) -> String { L10n.tr("core.ui.mistiacategorypicker.noFavoriteCategoriesYet", vi: "Chưa có danh mục yêu thích", en: "No favorite categories yet", ja: "お気に入りカテゴリはまだありません", language: language) }
                static var noRecentCategoriesYet: String { L10n.tr("core.ui.mistiacategorypicker.noRecentCategoriesYet", vi: "Chưa có danh mục gần đây", en: "No recent categories yet", ja: "最近のカテゴリはまだありません") }
                static func noRecentCategoriesYet(language: MistiaAppLanguage) -> String { L10n.tr("core.ui.mistiacategorypicker.noRecentCategoriesYet", vi: "Chưa có danh mục gần đây", en: "No recent categories yet", ja: "最近のカテゴリはまだありません", language: language) }
                static var recent: String { L10n.tr("core.ui.mistiacategorypicker.recent", vi: "Gần đây", en: "Recent", ja: "最近") }
                static func recent(language: MistiaAppLanguage) -> String { L10n.tr("core.ui.mistiacategorypicker.recent", vi: "Gần đây", en: "Recent", ja: "最近", language: language) }
                static var searchCategories: String { L10n.tr("core.ui.mistiacategorypicker.searchCategories", vi: "Tìm danh mục", en: "Search categories", ja: "カテゴリを検索") }
                static func searchCategories(language: MistiaAppLanguage) -> String { L10n.tr("core.ui.mistiacategorypicker.searchCategories", vi: "Tìm danh mục", en: "Search categories", ja: "カテゴリを検索", language: language) }
                static var searchResults: String { L10n.tr("core.ui.mistiacategorypicker.searchResults", vi: "Kết quả tìm kiếm", en: "Search results", ja: "検索結果") }
                static func searchResults(language: MistiaAppLanguage) -> String { L10n.tr("core.ui.mistiacategorypicker.searchResults", vi: "Kết quả tìm kiếm", en: "Search results", ja: "検索結果", language: language) }
                static var starChildCategoriesInManageToAccess: String { L10n.tr("core.ui.mistiacategorypicker.starChildCategoriesInManageToAccess", vi: "Đánh dấu sao ở danh mục con trong tab Quản lý để chọn nhanh hơn ở đây.", en: "Star child categories in Manage to access them quickly here.", ja: "管理タブで子カテゴリにスターを付けると、ここからすばやく選べます。") }
                static func starChildCategoriesInManageToAccess(language: MistiaAppLanguage) -> String { L10n.tr("core.ui.mistiacategorypicker.starChildCategoriesInManageToAccess", vi: "Đánh dấu sao ở danh mục con trong tab Quản lý để chọn nhanh hơn ở đây.", en: "Star child categories in Manage to access them quickly here.", ja: "管理タブで子カテゴリにスターを付けると、ここからすばやく選べます。", language: language) }
                static var tryAnotherKeywordOrSwitchToAll: String { L10n.tr("core.ui.mistiacategorypicker.tryAnotherKeywordOrSwitchToAll", vi: "Thử từ khóa khác hoặc chuyển sang xem tất cả danh mục.", en: "Try another keyword or switch to all categories.", ja: "別のキーワードを試すか、すべてのカテゴリに切り替えてください。") }
                static func tryAnotherKeywordOrSwitchToAll(language: MistiaAppLanguage) -> String { L10n.tr("core.ui.mistiacategorypicker.tryAnotherKeywordOrSwitchToAll", vi: "Thử từ khóa khác hoặc chuyển sang xem tất cả danh mục.", en: "Try another keyword or switch to all categories.", ja: "別のキーワードを試すか、すべてのカテゴリに切り替えてください。", language: language) }
                static func valueChildCategories(_ value: String) -> String {
                    L10n.format("core.ui.mistiacategorypicker.valueChildCategories", vi: "%@ danh mục con", en: "%@ child categories", ja: "子カテゴリ %@ 件", value)
                }
                static func valueChildCategories(_ value: String, language: MistiaAppLanguage) -> String {
                    L10n.format("core.ui.mistiacategorypicker.valueChildCategories", vi: "%@ danh mục con", en: "%@ child categories", ja: "子カテゴリ %@ 件", language: language, value)
                }
            }

            nonisolated enum mistiacategoryspendingchart {
                static var changeTheTimeRangeToSeeMore: String { L10n.tr("core.ui.mistiacategoryspendingchart.changeTheTimeRangeToSeeMore", vi: "Đổi mốc thời gian để xem thêm.", en: "Change the time range to see more.", ja: "期間を変えると表示されます。") }
                static func changeTheTimeRangeToSeeMore(language: MistiaAppLanguage) -> String { L10n.tr("core.ui.mistiacategoryspendingchart.changeTheTimeRangeToSeeMore", vi: "Đổi mốc thời gian để xem thêm.", en: "Change the time range to see more.", ja: "期間を変えると表示されます。", language: language) }
                static var noSpendingYet: String { L10n.tr("core.ui.mistiacategoryspendingchart.noSpendingYet", vi: "Chưa có chi tiêu", en: "No spending yet", ja: "支出はまだありません") }
                static func noSpendingYet(language: MistiaAppLanguage) -> String { L10n.tr("core.ui.mistiacategoryspendingchart.noSpendingYet", vi: "Chưa có chi tiêu", en: "No spending yet", ja: "支出はまだありません", language: language) }
                static var other: String { L10n.tr("core.ui.mistiacategoryspendingchart.other", vi: "Khác", en: "Other", ja: "その他") }
                static func other(language: MistiaAppLanguage) -> String { L10n.tr("core.ui.mistiacategoryspendingchart.other", vi: "Khác", en: "Other", ja: "その他", language: language) }
            }

            nonisolated enum mistiafinanceicons {
                static var cardDebt: String { L10n.tr("core.ui.mistiafinanceicons.cardDebt", vi: "Dư nợ thẻ", en: "Card balance", ja: "カード利用残高") }
                static func cardDebt(language: MistiaAppLanguage) -> String { L10n.tr("core.ui.mistiafinanceicons.cardDebt", vi: "Dư nợ thẻ", en: "Card balance", ja: "カード利用残高", language: language) }
                static var classicCard: String { L10n.tr("core.ui.mistiafinanceicons.classicCard", vi: "Thẻ chuẩn", en: "Classic card", ja: "クラシックカード") }
                static func classicCard(language: MistiaAppLanguage) -> String { L10n.tr("core.ui.mistiafinanceicons.classicCard", vi: "Thẻ chuẩn", en: "Classic card", ja: "クラシックカード", language: language) }
                static var close: String { L10n.tr("core.ui.mistiafinanceicons.close", vi: "Đóng", en: "Close", ja: "閉じる") }
                static func close(language: MistiaAppLanguage) -> String { L10n.tr("core.ui.mistiafinanceicons.close", vi: "Đóng", en: "Close", ja: "閉じる", language: language) }
                static var emergencyWallet: String { L10n.tr("core.ui.mistiafinanceicons.emergencyWallet", vi: "Ví dự phòng", en: "Emergency wallet", ja: "緊急用ウォレット") }
                static func emergencyWallet(language: MistiaAppLanguage) -> String { L10n.tr("core.ui.mistiafinanceicons.emergencyWallet", vi: "Ví dự phòng", en: "Emergency wallet", ja: "緊急用ウォレット", language: language) }
                static var family: String { L10n.tr("core.ui.mistiafinanceicons.family", vi: "Gia đình", en: "Family", ja: "家族") }
                static func family(language: MistiaAppLanguage) -> String { L10n.tr("core.ui.mistiafinanceicons.family", vi: "Gia đình", en: "Family", ja: "家族", language: language) }
                static var familyWallet: String { L10n.tr("core.ui.mistiafinanceicons.familyWallet", vi: "Ví gia đình", en: "Family wallet", ja: "家族用ウォレット") }
                static func familyWallet(language: MistiaAppLanguage) -> String { L10n.tr("core.ui.mistiafinanceicons.familyWallet", vi: "Ví gia đình", en: "Family wallet", ja: "家族用ウォレット", language: language) }
                static var home: String { L10n.tr("core.ui.mistiafinanceicons.home", vi: "Nhà ở", en: "Home", ja: "ホーム") }
                static func home(language: MistiaAppLanguage) -> String { L10n.tr("core.ui.mistiafinanceicons.home", vi: "Nhà ở", en: "Home", ja: "ホーム", language: language) }
                static var installment: String { L10n.tr("core.ui.mistiafinanceicons.installment", vi: "Trả góp", en: "Installment", ja: "分割払い") }
                static func installment(language: MistiaAppLanguage) -> String { L10n.tr("core.ui.mistiafinanceicons.installment", vi: "Trả góp", en: "Installment", ja: "分割払い", language: language) }
                static var loan: String { L10n.tr("core.ui.mistiafinanceicons.loan", vi: "Vay", en: "Loan", ja: "ローン") }
                static func loan(language: MistiaAppLanguage) -> String { L10n.tr("core.ui.mistiafinanceicons.loan", vi: "Vay", en: "Loan", ja: "ローン", language: language) }
                static var premiumCard: String { L10n.tr("core.ui.mistiafinanceicons.premiumCard", vi: "Thẻ premium", en: "Premium card", ja: "プレミアムカード") }
                static func premiumCard(language: MistiaAppLanguage) -> String { L10n.tr("core.ui.mistiafinanceicons.premiumCard", vi: "Thẻ premium", en: "Premium card", ja: "プレミアムカード", language: language) }
                static var rewardsCard: String { L10n.tr("core.ui.mistiafinanceicons.rewardsCard", vi: "Thẻ tích điểm", en: "Rewards card", ja: "リワードカード") }
                static func rewardsCard(language: MistiaAppLanguage) -> String { L10n.tr("core.ui.mistiafinanceicons.rewardsCard", vi: "Thẻ tích điểm", en: "Rewards card", ja: "リワードカード", language: language) }
                static var save: String { L10n.tr("core.ui.mistiafinanceicons.save", vi: "Lưu", en: "Save", ja: "保存") }
                static func save(language: MistiaAppLanguage) -> String { L10n.tr("core.ui.mistiafinanceicons.save", vi: "Lưu", en: "Save", ja: "保存", language: language) }
                static var savings: String { L10n.tr("core.ui.mistiafinanceicons.savings", vi: "Tiết kiệm", en: "Savings", ja: "貯蓄") }
                static func savings(language: MistiaAppLanguage) -> String { L10n.tr("core.ui.mistiafinanceicons.savings", vi: "Tiết kiệm", en: "Savings", ja: "貯蓄", language: language) }
                static var savingsWallet: String { L10n.tr("core.ui.mistiafinanceicons.savingsWallet", vi: "Ví tiết kiệm", en: "Savings wallet", ja: "貯蓄用ウォレット") }
                static func savingsWallet(language: MistiaAppLanguage) -> String { L10n.tr("core.ui.mistiafinanceicons.savingsWallet", vi: "Ví tiết kiệm", en: "Savings wallet", ja: "貯蓄用ウォレット", language: language) }
                static var scheduledPayment: String { L10n.tr("core.ui.mistiafinanceicons.scheduledPayment", vi: "Thanh toán định kỳ", en: "Scheduled payment", ja: "支払い予定") }
                static func scheduledPayment(language: MistiaAppLanguage) -> String { L10n.tr("core.ui.mistiafinanceicons.scheduledPayment", vi: "Thanh toán định kỳ", en: "Scheduled payment", ja: "支払い予定", language: language) }
                static var study: String { L10n.tr("core.ui.mistiafinanceicons.study", vi: "Học tập", en: "Study", ja: "学習") }
                static func study(language: MistiaAppLanguage) -> String { L10n.tr("core.ui.mistiafinanceicons.study", vi: "Học tập", en: "Study", ja: "学習", language: language) }
                static var travel: String { L10n.tr("core.ui.mistiafinanceicons.travel", vi: "Du lịch", en: "Travel", ja: "旅行") }
                static func travel(language: MistiaAppLanguage) -> String { L10n.tr("core.ui.mistiafinanceicons.travel", vi: "Du lịch", en: "Travel", ja: "旅行", language: language) }
                static var travelWallet: String { L10n.tr("core.ui.mistiafinanceicons.travelWallet", vi: "Ví du lịch", en: "Travel wallet", ja: "旅行用ウォレット") }
                static func travelWallet(language: MistiaAppLanguage) -> String { L10n.tr("core.ui.mistiafinanceicons.travelWallet", vi: "Ví du lịch", en: "Travel wallet", ja: "旅行用ウォレット", language: language) }
                static var vehicle: String { L10n.tr("core.ui.mistiafinanceicons.vehicle", vi: "Xe cộ", en: "Vehicle", ja: "車両") }
                static func vehicle(language: MistiaAppLanguage) -> String { L10n.tr("core.ui.mistiafinanceicons.vehicle", vi: "Xe cộ", en: "Vehicle", ja: "車両", language: language) }
            }

            nonisolated enum mistiaiconpicker {
                static var billsUtilities: String { L10n.tr("core.ui.mistiaiconpicker.billsUtilities", vi: "Hóa đơn / tiện ích", en: "Bills / utilities", ja: "請求・公共料金") }
                static func billsUtilities(language: MistiaAppLanguage) -> String { L10n.tr("core.ui.mistiaiconpicker.billsUtilities", vi: "Hóa đơn / tiện ích", en: "Bills / utilities", ja: "請求・公共料金", language: language) }
                static func colorValue(_ value: String) -> String {
                    L10n.format("core.ui.mistiaiconpicker.colorValue", vi: "Màu %@", en: "Color %@", ja: "色 %@", value)
                }
                static func colorValue(_ value: String, language: MistiaAppLanguage) -> String {
                    L10n.format("core.ui.mistiaiconpicker.colorValue", vi: "Màu %@", en: "Color %@", ja: "色 %@", language: language, value)
                }
                static var current: String { L10n.tr("core.ui.mistiaiconpicker.current", vi: "Hiện tại", en: "Current", ja: "現在") }
                static func current(language: MistiaAppLanguage) -> String { L10n.tr("core.ui.mistiaiconpicker.current", vi: "Hiện tại", en: "Current", ja: "現在", language: language) }
                static func currentColorValue(_ value: String) -> String {
                    L10n.format("core.ui.mistiaiconpicker.currentColorValue", vi: "Màu hiện tại %@", en: "Current color %@", ja: "現在の色 %@", value)
                }
                static func currentColorValue(_ value: String, language: MistiaAppLanguage) -> String {
                    L10n.format("core.ui.mistiaiconpicker.currentColorValue", vi: "Màu hiện tại %@", en: "Current color %@", ja: "現在の色 %@", language: language, value)
                }
                static var entertainment: String { L10n.tr("core.ui.mistiaiconpicker.entertainment", vi: "Giải trí", en: "Entertainment", ja: "娯楽") }
                static func entertainment(language: MistiaAppLanguage) -> String { L10n.tr("core.ui.mistiaiconpicker.entertainment", vi: "Giải trí", en: "Entertainment", ja: "娯楽", language: language) }
                static var finance: String { L10n.tr("core.ui.mistiaiconpicker.finance", vi: "Tài chính", en: "Finance", ja: "金融") }
                static func finance(language: MistiaAppLanguage) -> String { L10n.tr("core.ui.mistiaiconpicker.finance", vi: "Tài chính", en: "Finance", ja: "金融", language: language) }
                static var food: String { L10n.tr("core.ui.mistiaiconpicker.food", vi: "Ăn uống", en: "Food", ja: "食事") }
                static func food(language: MistiaAppLanguage) -> String { L10n.tr("core.ui.mistiaiconpicker.food", vi: "Ăn uống", en: "Food", ja: "食事", language: language) }
                static var goalsPersonal: String { L10n.tr("core.ui.mistiaiconpicker.goalsPersonal", vi: "Mục tiêu / cá nhân", en: "Goals / personal", ja: "目標・個人") }
                static func goalsPersonal(language: MistiaAppLanguage) -> String { L10n.tr("core.ui.mistiaiconpicker.goalsPersonal", vi: "Mục tiêu / cá nhân", en: "Goals / personal", ja: "目標・個人", language: language) }
                static var health: String { L10n.tr("core.ui.mistiaiconpicker.health", vi: "Sức khỏe", en: "Health", ja: "健康") }
                static func health(language: MistiaAppLanguage) -> String { L10n.tr("core.ui.mistiaiconpicker.health", vi: "Sức khỏe", en: "Health", ja: "健康", language: language) }
                static var home: String { L10n.tr("core.ui.mistiaiconpicker.home", vi: "Nhà cửa", en: "Home", ja: "住まい") }
                static func home(language: MistiaAppLanguage) -> String { L10n.tr("core.ui.mistiaiconpicker.home", vi: "Nhà cửa", en: "Home", ja: "住まい", language: language) }
                static var iconPreview: String { L10n.tr("core.ui.mistiaiconpicker.iconPreview", vi: "Xem trước icon", en: "Icon preview", ja: "アイコンプレビュー") }
                static func iconPreview(language: MistiaAppLanguage) -> String { L10n.tr("core.ui.mistiaiconpicker.iconPreview", vi: "Xem trước icon", en: "Icon preview", ja: "アイコンプレビュー", language: language) }
                static var shopping: String { L10n.tr("core.ui.mistiaiconpicker.shopping", vi: "Mua sắm", en: "Shopping", ja: "買い物") }
                static func shopping(language: MistiaAppLanguage) -> String { L10n.tr("core.ui.mistiaiconpicker.shopping", vi: "Mua sắm", en: "Shopping", ja: "買い物", language: language) }
                static var transport: String { L10n.tr("core.ui.mistiaiconpicker.transport", vi: "Di chuyển", en: "Transport", ja: "移動") }
                static func transport(language: MistiaAppLanguage) -> String { L10n.tr("core.ui.mistiaiconpicker.transport", vi: "Di chuyển", en: "Transport", ja: "移動", language: language) }
                static var travel: String { L10n.tr("core.ui.mistiaiconpicker.travel", vi: "Du lịch", en: "Travel", ja: "旅行") }
                static func travel(language: MistiaAppLanguage) -> String { L10n.tr("core.ui.mistiaiconpicker.travel", vi: "Du lịch", en: "Travel", ja: "旅行", language: language) }
                static var workStudy: String { L10n.tr("core.ui.mistiaiconpicker.workStudy", vi: "Công việc / học tập", en: "Work / study", ja: "仕事・学習") }
                static func workStudy(language: MistiaAppLanguage) -> String { L10n.tr("core.ui.mistiaiconpicker.workStudy", vi: "Công việc / học tập", en: "Work / study", ja: "仕事・学習", language: language) }
            }

            nonisolated enum mistiamonthnavigation {
                static var chooseMonth: String { L10n.tr("core.ui.mistiamonthnavigation.chooseMonth", vi: "Chọn tháng", en: "Choose month", ja: "月を選択") }
                static func chooseMonth(language: MistiaAppLanguage) -> String { L10n.tr("core.ui.mistiamonthnavigation.chooseMonth", vi: "Chọn tháng", en: "Choose month", ja: "月を選択", language: language) }
                static var nextMonth: String { L10n.tr("core.ui.mistiamonthnavigation.nextMonth", vi: "Tháng sau", en: "Next month", ja: "翌月") }
                static func nextMonth(language: MistiaAppLanguage) -> String { L10n.tr("core.ui.mistiamonthnavigation.nextMonth", vi: "Tháng sau", en: "Next month", ja: "翌月", language: language) }
                static var previousMonth: String { L10n.tr("core.ui.mistiamonthnavigation.previousMonth", vi: "Tháng trước", en: "Previous month", ja: "前月") }
                static func previousMonth(language: MistiaAppLanguage) -> String { L10n.tr("core.ui.mistiamonthnavigation.previousMonth", vi: "Tháng trước", en: "Previous month", ja: "前月", language: language) }
            }
        }
    }

    nonisolated enum family {

        nonisolated enum family {
            static var aFamilyHasOneOwnerInviteA: String { L10n.tr("family.family.aFamilyHasOneOwnerInviteA", vi: "Gia đình chỉ có một chủ sở hữu. Hãy mời thành viên rồi nhượng quyền chủ sở hữu từ màn hình thông tin thành viên.", en: "A family has one owner. Invite a member, then transfer ownership from that member's info screen.", ja: "家族のオーナーは1人です。メンバーとして招待してから、メンバー情報画面でオーナーを譲渡します。") }
            static func aFamilyHasOneOwnerInviteA(language: MistiaAppLanguage) -> String { L10n.tr("family.family.aFamilyHasOneOwnerInviteA", vi: "Gia đình chỉ có một chủ sở hữu. Hãy mời thành viên rồi nhượng quyền chủ sở hữu từ màn hình thông tin thành viên.", en: "A family has one owner. Invite a member, then transfer ownership from that member's info screen.", ja: "家族のオーナーは1人です。メンバーとして招待してから、メンバー情報画面でオーナーを譲渡します。", language: language) }
            static var acceptedMember: String { L10n.tr("family.family.acceptedMember", vi: "Thành viên đã chấp nhận", en: "Accepted member", ja: "承認済みメンバー") }
            static func acceptedMember(language: MistiaAppLanguage) -> String { L10n.tr("family.family.acceptedMember", vi: "Thành viên đã chấp nhận", en: "Accepted member", ja: "承認済みメンバー", language: language) }
            static func acceptedValue(_ value: String) -> String {
                L10n.format("family.family.acceptedValue", vi: "Đã chấp nhận: %@", en: "Accepted: %@", ja: "承認: %@", value)
            }
            static func acceptedValue(_ value: String, language: MistiaAppLanguage) -> String {
                L10n.format("family.family.acceptedValue", vi: "Đã chấp nhận: %@", en: "Accepted: %@", ja: "承認: %@", language: language, value)
            }
            static var accounts: String { L10n.tr("family.family.accounts", vi: "Tài khoản", en: "Accounts", ja: "口座") }
            static func accounts(language: MistiaAppLanguage) -> String { L10n.tr("family.family.accounts", vi: "Tài khoản", en: "Accounts", ja: "口座", language: language) }
            static var allSharedDataAndFamilyConnectionsWill: String { L10n.tr("family.family.allSharedDataAndFamilyConnectionsWill", vi: "Tất cả dữ liệu chia sẻ và kết nối gia đình sẽ bị xóa vĩnh viễn. Hành động này không thể hoàn tác.", en: "All shared data and family connections will be permanently deleted. This cannot be undone.", ja: "共有データと家族のつながりはすべて完全に削除されます。この操作は取り消せません。") }
            static func allSharedDataAndFamilyConnectionsWill(language: MistiaAppLanguage) -> String { L10n.tr("family.family.allSharedDataAndFamilyConnectionsWill", vi: "Tất cả dữ liệu chia sẻ và kết nối gia đình sẽ bị xóa vĩnh viễn. Hành động này không thể hoàn tác.", en: "All shared data and family connections will be permanently deleted. This cannot be undone.", ja: "共有データと家族のつながりはすべて完全に削除されます。この操作は取り消せません。", language: language) }
            static var billList: String { L10n.tr("family.family.billList", vi: "Danh sách hóa đơn", en: "Bill list", ja: "請求一覧") }
            static func billList(language: MistiaAppLanguage) -> String { L10n.tr("family.family.billList", vi: "Danh sách hóa đơn", en: "Bill list", ja: "請求一覧", language: language) }
            static var bills: String { L10n.tr("family.family.bills", vi: "Hóa đơn", en: "Bills", ja: "請求書") }
            static func bills(language: MistiaAppLanguage) -> String { L10n.tr("family.family.bills", vi: "Hóa đơn", en: "Bills", ja: "請求書", language: language) }
            static var budgets: String { L10n.tr("family.family.budgets", vi: "Ngân sách", en: "Budgets", ja: "予算") }
            static func budgets(language: MistiaAppLanguage) -> String { L10n.tr("family.family.budgets", vi: "Ngân sách", en: "Budgets", ja: "予算", language: language) }
            static var categories: String { L10n.tr("family.family.categories", vi: "Danh mục", en: "Categories", ja: "カテゴリ") }
            static func categories(language: MistiaAppLanguage) -> String { L10n.tr("family.family.categories", vi: "Danh mục", en: "Categories", ja: "カテゴリ", language: language) }
            static var childSupervision: String { L10n.tr("family.family.childSupervision", vi: "Giám sát trẻ em", en: "Child supervision", ja: "キッズの管理") }
            static func childSupervision(language: MistiaAppLanguage) -> String { L10n.tr("family.family.childSupervision", vi: "Giám sát trẻ em", en: "Child supervision", ja: "キッズの管理", language: language) }
            static var close: String { L10n.tr("family.family.close", vi: "Đóng", en: "Close", ja: "閉じる") }
            static func close(language: MistiaAppLanguage) -> String { L10n.tr("family.family.close", vi: "Đóng", en: "Close", ja: "閉じる", language: language) }
            static var confirm: String { L10n.tr("family.family.confirm", vi: "Đồng ý", en: "Confirm", ja: "確認") }
            static func confirm(language: MistiaAppLanguage) -> String { L10n.tr("family.family.confirm", vi: "Đồng ý", en: "Confirm", ja: "確認", language: language) }
            static var confirmDataPersonalInformationUsage: String { L10n.tr("family.family.confirmDataPersonalInformationUsage", vi: "Xác nhận sử dụng dữ liệu & thông tin cá nhân", en: "Confirm data & personal information usage", ja: "データおよび個人情報の使用を確認する") }
            static func confirmDataPersonalInformationUsage(language: MistiaAppLanguage) -> String { L10n.tr("family.family.confirmDataPersonalInformationUsage", vi: "Xác nhận sử dụng dữ liệu & thông tin cá nhân", en: "Confirm data & personal information usage", ja: "データおよび個人情報の使用を確認する", language: language) }
            static var copied: String { L10n.tr("family.family.copied", vi: "Đã copy", en: "Copied", ja: "コピー済み") }
            static func copied(language: MistiaAppLanguage) -> String { L10n.tr("family.family.copied", vi: "Đã copy", en: "Copied", ja: "コピー済み", language: language) }
            static var copy: String { L10n.tr("family.family.copy", vi: "Sao chép", en: "Copy", ja: "コピー") }
            static func copy(language: MistiaAppLanguage) -> String { L10n.tr("family.family.copy", vi: "Sao chép", en: "Copy", ja: "コピー", language: language) }
            static var createAccess: String { L10n.tr("family.family.createAccess", vi: "Quyền thêm mới", en: "Create access", ja: "作成権限") }
            static func createAccess(language: MistiaAppLanguage) -> String { L10n.tr("family.family.createAccess", vi: "Quyền thêm mới", en: "Create access", ja: "作成権限", language: language) }
            static var createDebtTransfer: String { L10n.tr("family.family.createDebtTransfer", vi: "Chuyển tiền vay/cho vay", en: "Loan transfer", ja: "貸借の送金") }
            static func createDebtTransfer(language: MistiaAppLanguage) -> String { L10n.tr("family.family.createDebtTransfer", vi: "Chuyển tiền vay/cho vay", en: "Loan transfer", ja: "貸借の送金", language: language) }
            static var createFamily: String { L10n.tr("family.family.createFamily", vi: "Tạo gia đình", en: "Create family", ja: "家族を作成") }
            static func createFamily(language: MistiaAppLanguage) -> String { L10n.tr("family.family.createFamily", vi: "Tạo gia đình", en: "Create family", ja: "家族を作成", language: language) }
            static var createFamilyTransfer: String { L10n.tr("family.family.createFamilyTransfer", vi: "Chuyển tiền gia đình", en: "Family transfer", ja: "家族への送金") }
            static func createFamilyTransfer(language: MistiaAppLanguage) -> String { L10n.tr("family.family.createFamilyTransfer", vi: "Chuyển tiền gia đình", en: "Family transfer", ja: "家族への送金", language: language) }
            static var createLink: String { L10n.tr("family.family.createLink", vi: "Tạo link", en: "Create link", ja: "リンク作成") }
            static func createLink(language: MistiaAppLanguage) -> String { L10n.tr("family.family.createLink", vi: "Tạo link", en: "Create link", ja: "リンク作成", language: language) }
            static var createdLinksWillAppearHereWithPending: String { L10n.tr("family.family.createdLinksWillAppearHereWithPending", vi: "Các link đã tạo sẽ xuất hiện ở đây cùng trạng thái chờ, đã dùng, đã từ chối, hết hạn hoặc đã thu hồi.", en: "Created links will appear here with pending, used, declined, expired, or revoked states.", ja: "作成済みリンクは、待機中・使用済み・辞退済み・期限切れ・取り消し済みの状態でここに表示されます。") }
            static func createdLinksWillAppearHereWithPending(language: MistiaAppLanguage) -> String { L10n.tr("family.family.createdLinksWillAppearHereWithPending", vi: "Các link đã tạo sẽ xuất hiện ở đây cùng trạng thái chờ, đã dùng, đã từ chối, hết hạn hoặc đã thu hồi.", en: "Created links will appear here with pending, used, declined, expired, or revoked states.", ja: "作成済みリンクは、待機中・使用済み・辞退済み・期限切れ・取り消し済みの状態でここに表示されます。", language: language) }
            static var currentDebt: String { L10n.tr("family.family.currentDebt", vi: "Đang nợ", en: "Current debt", ja: "現在の負債") }
            static func currentDebt(language: MistiaAppLanguage) -> String { L10n.tr("family.family.currentDebt", vi: "Đang nợ", en: "Current debt", ja: "現在の負債", language: language) }
            static var declined: String { L10n.tr("family.family.declined", vi: "Đã từ chối", en: "Declined", ja: "辞退済み") }
            static func declined(language: MistiaAppLanguage) -> String { L10n.tr("family.family.declined", vi: "Đã từ chối", en: "Declined", ja: "辞退済み", language: language) }
            static func declinedValue(_ value: String) -> String {
                L10n.format("family.family.declinedValue", vi: "Đã từ chối: %@", en: "Declined: %@", ja: "辞退: %@", value)
            }
            static func declinedValue(_ value: String, language: MistiaAppLanguage) -> String {
                L10n.format("family.family.declinedValue", vi: "Đã từ chối: %@", en: "Declined: %@", ja: "辞退: %@", language: language, value)
            }
            static var deleteFamily: String { L10n.tr("family.family.deleteFamily", vi: "Xóa gia đình?", en: "Delete family?", ja: "家族を削除しますか？") }
            static func deleteFamily(language: MistiaAppLanguage) -> String { L10n.tr("family.family.deleteFamily", vi: "Xóa gia đình?", en: "Delete family?", ja: "家族を削除しますか？", language: language) }
            static var deleteFamily2: String { L10n.tr("family.family.deleteFamily2", vi: "Xóa gia đình", en: "Delete family", ja: "家族を削除") }
            static func deleteFamily2(language: MistiaAppLanguage) -> String { L10n.tr("family.family.deleteFamily2", vi: "Xóa gia đình", en: "Delete family", ja: "家族を削除", language: language) }
            static var deletePermanently: String { L10n.tr("family.family.deletePermanently", vi: "Xóa vĩnh viễn", en: "Delete permanently", ja: "完全に削除") }
            static func deletePermanently(language: MistiaAppLanguage) -> String { L10n.tr("family.family.deletePermanently", vi: "Xóa vĩnh viễn", en: "Delete permanently", ja: "完全に削除", language: language) }
            static var distribution: String { L10n.tr("family.family.distribution", vi: "Phân bổ", en: "Distribution", ja: "内訳") }
            static func distribution(language: MistiaAppLanguage) -> String { L10n.tr("family.family.distribution", vi: "Phân bổ", en: "Distribution", ja: "内訳", language: language) }
            static var done: String { L10n.tr("family.family.done", vi: "Xong", en: "Done", ja: "完了") }
            static func done(language: MistiaAppLanguage) -> String { L10n.tr("family.family.done", vi: "Xong", en: "Done", ja: "完了", language: language) }
            static var editAccess: String { L10n.tr("family.family.editAccess", vi: "Quyền chỉnh sửa", en: "Edit access", ja: "編集権限") }
            static func editAccess(language: MistiaAppLanguage) -> String { L10n.tr("family.family.editAccess", vi: "Quyền chỉnh sửa", en: "Edit access", ja: "編集権限", language: language) }
            static var editKids: String { L10n.tr("family.family.editKids", vi: "Quản lý dữ liệu của trẻ em", en: "Edit kids", ja: "kid を編集") }
            static func editKids(language: MistiaAppLanguage) -> String { L10n.tr("family.family.editKids", vi: "Quản lý dữ liệu của trẻ em", en: "Edit kids", ja: "kid を編集", language: language) }
            static var expired: String { L10n.tr("family.family.expired", vi: "Hết hạn", en: "Expired", ja: "期限切れ") }
            static func expired(language: MistiaAppLanguage) -> String { L10n.tr("family.family.expired", vi: "Hết hạn", en: "Expired", ja: "期限切れ", language: language) }
            static func expiresValue(_ value: String) -> String {
                L10n.format("family.family.expiresValue", vi: "Hết hạn: %@", en: "Expires: %@", ja: "期限: %@", value)
            }
            static func expiresValue(_ value: String, language: MistiaAppLanguage) -> String {
                L10n.format("family.family.expiresValue", vi: "Hết hạn: %@", en: "Expires: %@", ja: "期限: %@", language: language, value)
            }
            static var family: String { L10n.tr("family.family.family", vi: "Gia đình", en: "Family", ja: "家族") }
            static func family(language: MistiaAppLanguage) -> String { L10n.tr("family.family.family", vi: "Gia đình", en: "Family", ja: "家族", language: language) }
            static var family2: String { L10n.tr("family.family.family2", vi: "Cả nhà", en: "Family", ja: "家族") }
            static func family2(language: MistiaAppLanguage) -> String { L10n.tr("family.family.family2", vi: "Cả nhà", en: "Family", ja: "家族", language: language) }
            static var familyBudget: String { L10n.tr("family.family.familyBudget", vi: "Ngân sách gia đình", en: "Family budget", ja: "家族の予算") }
            static func familyBudget(language: MistiaAppLanguage) -> String { L10n.tr("family.family.familyBudget", vi: "Ngân sách gia đình", en: "Family budget", ja: "家族の予算", language: language) }
            static var familyGoals: String { L10n.tr("family.family.familyGoals", vi: "Mục tiêu gia đình", en: "Family goals", ja: "家族の目標") }
            static func familyGoals(language: MistiaAppLanguage) -> String { L10n.tr("family.family.familyGoals", vi: "Mục tiêu gia đình", en: "Family goals", ja: "家族の目標", language: language) }
            static var familyIsWaitingForTheConnection: String { L10n.tr("family.family.familyIsWaitingForTheConnection", vi: "Gia đình đang chờ kết nối", en: "Family is waiting for the connection", ja: "家族機能は接続待ちです") }
            static func familyIsWaitingForTheConnection(language: MistiaAppLanguage) -> String { L10n.tr("family.family.familyIsWaitingForTheConnection", vi: "Gia đình đang chờ kết nối", en: "Family is waiting for the connection", ja: "家族機能は接続待ちです", language: language) }
            static var familyName: String { L10n.tr("family.family.familyName", vi: "Tên gia đình", en: "Family name", ja: "家族名") }
            static func familyName(language: MistiaAppLanguage) -> String { L10n.tr("family.family.familyName", vi: "Tên gia đình", en: "Family name", ja: "家族名", language: language) }
            static var familyNeedsAttention: String { L10n.tr("family.family.familyNeedsAttention", vi: "Gia đình cần kiểm tra", en: "Family needs attention", ja: "家族設定の確認が必要です") }
            static func familyNeedsAttention(language: MistiaAppLanguage) -> String { L10n.tr("family.family.familyNeedsAttention", vi: "Gia đình cần kiểm tra", en: "Family needs attention", ja: "家族設定の確認が必要です", language: language) }
            static var familyOverview: String { L10n.tr("family.family.familyOverview", vi: "Tổng quan gia đình", en: "Family overview", ja: "家族の概要") }
            static func familyOverview(language: MistiaAppLanguage) -> String { L10n.tr("family.family.familyOverview", vi: "Tổng quan gia đình", en: "Family overview", ja: "家族の概要", language: language) }
            static var familyOverviewManagers: String { L10n.tr("family.family.familyOverviewManagers", vi: "Quản lý tổng quan gia đình", en: "Family overview managers", ja: "家族概要の管理者") }
            static func familyOverviewManagers(language: MistiaAppLanguage) -> String { L10n.tr("family.family.familyOverviewManagers", vi: "Quản lý tổng quan gia đình", en: "Family overview managers", ja: "家族概要の管理者", language: language) }
            static var filteredTransactions: String { L10n.tr("family.family.filteredTransactions", vi: "Danh sách thu chi đã lọc", en: "Filtered cashflow items", ja: "フィルター済み取引") }
            static func filteredTransactions(language: MistiaAppLanguage) -> String { L10n.tr("family.family.filteredTransactions", vi: "Danh sách thu chi đã lọc", en: "Filtered cashflow items", ja: "フィルター済み取引", language: language) }
            static var goals: String { L10n.tr("family.family.goals", vi: "Mục tiêu", en: "Goals", ja: "目標") }
            static func goals(language: MistiaAppLanguage) -> String { L10n.tr("family.family.goals", vi: "Mục tiêu", en: "Goals", ja: "目標", language: language) }
            static var ifYouVeCopiedAnInviteLink: String { L10n.tr("family.family.ifYouVeCopiedAnInviteLink", vi: "Nếu bạn đã copy link mời, hãy dán link ở đây. Mistia sẽ mở màn hình chào mừng và không tự tham gia cho đến khi bạn xác nhận.", en: "If you've copied an invite link, paste it here. Mistia will open the welcome screen and won't join until you confirm.", ja: "招待リンクをコピー済みの場合はここに貼り付けてください。確認するまで自動参加はしません。") }
            static func ifYouVeCopiedAnInviteLink(language: MistiaAppLanguage) -> String { L10n.tr("family.family.ifYouVeCopiedAnInviteLink", vi: "Nếu bạn đã copy link mời, hãy dán link ở đây. Mistia sẽ mở màn hình chào mừng và không tự tham gia cho đến khi bạn xác nhận.", en: "If you've copied an invite link, paste it here. Mistia will open the welcome screen and won't join until you confirm.", ja: "招待リンクをコピー済みの場合はここに貼り付けてください。確認するまで自動参加はしません。", language: language) }
            static var income: String { L10n.tr("family.family.income", vi: "Thu nhập", en: "Income", ja: "収入") }
            static func income(language: MistiaAppLanguage) -> String { L10n.tr("family.family.income", vi: "Thu nhập", en: "Income", ja: "収入", language: language) }
            static var installmentsLoans: String { L10n.tr("family.family.installmentsLoans", vi: "Trả góp / vay", en: "Installments / loans", ja: "分割払い・借入") }
            static func installmentsLoans(language: MistiaAppLanguage) -> String { L10n.tr("family.family.installmentsLoans", vi: "Trả góp / vay", en: "Installments / loans", ja: "分割払い・借入", language: language) }
            static var invalid: String { L10n.tr("family.family.invalid", vi: "Không hợp lệ", en: "Invalid", ja: "無効") }
            static func invalid(language: MistiaAppLanguage) -> String { L10n.tr("family.family.invalid", vi: "Không hợp lệ", en: "Invalid", ja: "無効", language: language) }
            static var invite: String { L10n.tr("family.family.invite", vi: "Thêm", en: "Invite", ja: "招待") }
            static func invite(language: MistiaAppLanguage) -> String { L10n.tr("family.family.invite", vi: "Thêm", en: "Invite", ja: "招待", language: language) }
            static var inviteLink: String { L10n.tr("family.family.inviteLink", vi: "Link mời", en: "Invite link", ja: "招待リンク") }
            static func inviteLink(language: MistiaAppLanguage) -> String { L10n.tr("family.family.inviteLink", vi: "Link mời", en: "Invite link", ja: "招待リンク", language: language) }
            static var inviteMember: String { L10n.tr("family.family.inviteMember", vi: "Mời thành viên", en: "Invite member", ja: "メンバーを招待") }
            static func inviteMember(language: MistiaAppLanguage) -> String { L10n.tr("family.family.inviteMember", vi: "Mời thành viên", en: "Invite member", ja: "メンバーを招待", language: language) }
            static var inviteRole: String { L10n.tr("family.family.inviteRole", vi: "Vai trò được mời", en: "Invite role", ja: "招待する役割") }
            static func inviteRole(language: MistiaAppLanguage) -> String { L10n.tr("family.family.inviteRole", vi: "Vai trò được mời", en: "Invite role", ja: "招待する役割", language: language) }
            static func inviteRoleValue(_ value: String) -> String {
                L10n.format("family.family.inviteRoleValue", vi: "Vai trò được mời: %@", en: "Invite role: %@", ja: "招待する役割: %@", value)
            }
            static func inviteRoleValue(_ value: String, language: MistiaAppLanguage) -> String {
                L10n.format("family.family.inviteRoleValue", vi: "Vai trò được mời: %@", en: "Invite role: %@", ja: "招待する役割: %@", language: language, value)
            }
            static var kid: String { L10n.tr("family.family.kid", vi: "Trẻ em", en: "Kid", ja: "キッズ") }
            static func kid(language: MistiaAppLanguage) -> String { L10n.tr("family.family.kid", vi: "Trẻ em", en: "Kid", ja: "キッズ", language: language) }
            static var kidsAreLimitedByDefaultAndCan: String { L10n.tr("family.family.kidsAreLimitedByDefaultAndCan", vi: "Trẻ em mặc định bị giới hạn và có thể chịu sự quản lý của phụ huynh hoặc chủ gia đình.", en: "Kids are limited by default and can be managed by a parent or family owner.", ja: "キッズは初期状態で制限され、保護者または所有者が管理できます。") }
            static func kidsAreLimitedByDefaultAndCan(language: MistiaAppLanguage) -> String { L10n.tr("family.family.kidsAreLimitedByDefaultAndCan", vi: "Trẻ em mặc định bị giới hạn và có thể chịu sự quản lý của phụ huynh hoặc chủ gia đình.", en: "Kids are limited by default and can be managed by a parent or family owner.", ja: "キッズは初期状態で制限され、保護者または所有者が管理できます。", language: language) }
            static var leave: String { L10n.tr("family.family.leave", vi: "Rời khỏi", en: "Leave", ja: "退会") }
            static func leave(language: MistiaAppLanguage) -> String { L10n.tr("family.family.leave", vi: "Rời khỏi", en: "Leave", ja: "退会", language: language) }
            static var leaveFamily: String { L10n.tr("family.family.leaveFamily", vi: "Rời khỏi gia đình?", en: "Leave family?", ja: "家族を退会しますか？") }
            static func leaveFamily(language: MistiaAppLanguage) -> String { L10n.tr("family.family.leaveFamily", vi: "Rời khỏi gia đình?", en: "Leave family?", ja: "家族を退会しますか？", language: language) }
            static var leaveFamily2: String { L10n.tr("family.family.leaveFamily2", vi: "Rời khỏi gia đình", en: "Leave family", ja: "家族を退会") }
            static func leaveFamily2(language: MistiaAppLanguage) -> String { L10n.tr("family.family.leaveFamily2", vi: "Rời khỏi gia đình", en: "Leave family", ja: "家族を退会", language: language) }
            static var manageFamilyBudgets: String { L10n.tr("family.family.manageFamilyBudgets", vi: "Quản lý ngân sách gia đình", en: "Manage family budgets", ja: "家族予算を管理") }
            static func manageFamilyBudgets(language: MistiaAppLanguage) -> String { L10n.tr("family.family.manageFamilyBudgets", vi: "Quản lý ngân sách gia đình", en: "Manage family budgets", ja: "家族予算を管理", language: language) }
            static var manageFamilyGoals: String { L10n.tr("family.family.manageFamilyGoals", vi: "Quản lý mục tiêu gia đình", en: "Manage family goals", ja: "家族目標を管理") }
            static func manageFamilyGoals(language: MistiaAppLanguage) -> String { L10n.tr("family.family.manageFamilyGoals", vi: "Quản lý mục tiêu gia đình", en: "Manage family goals", ja: "家族目標を管理", language: language) }
            static var manageInvites: String { L10n.tr("family.family.manageInvites", vi: "Quản lý lời mời", en: "Manage invites", ja: "招待を管理") }
            static func manageInvites(language: MistiaAppLanguage) -> String { L10n.tr("family.family.manageInvites", vi: "Quản lý lời mời", en: "Manage invites", ja: "招待を管理", language: language) }
            static var member: String { L10n.tr("family.family.member", vi: "Thành viên", en: "Member", ja: "メンバー") }
            static func member(language: MistiaAppLanguage) -> String { L10n.tr("family.family.member", vi: "Thành viên", en: "Member", ja: "メンバー", language: language) }
            static var memberComparison: String { L10n.tr("family.family.memberComparison", vi: "So sánh thành viên", en: "Member comparison", ja: "メンバー比較") }
            static func memberComparison(language: MistiaAppLanguage) -> String { L10n.tr("family.family.memberComparison", vi: "So sánh thành viên", en: "Member comparison", ja: "メンバー比較", language: language) }
            static var members: String { L10n.tr("family.family.members", vi: "Thành viên", en: "Members", ja: "メンバー") }
            static func members(language: MistiaAppLanguage) -> String { L10n.tr("family.family.members", vi: "Thành viên", en: "Members", ja: "メンバー", language: language) }
            static var membersCanViewFamilyDataByDefault: String { L10n.tr("family.family.membersCanViewFamilyDataByDefault", vi: "Thành viên có thể xem dữ liệu gia đình theo quyền xem mặc định, nhưng muốn sửa hoặc dùng ví thì cần được cấp quyền.", en: "Members can view family data by default, but editing or using wallets requires an explicit grant.", ja: "メンバーは既定で家族データを表示できますが、編集やウォレット利用には明示的な許可が必要です。") }
            static func membersCanViewFamilyDataByDefault(language: MistiaAppLanguage) -> String { L10n.tr("family.family.membersCanViewFamilyDataByDefault", vi: "Thành viên có thể xem dữ liệu gia đình theo quyền xem mặc định, nhưng muốn sửa hoặc dùng ví thì cần được cấp quyền.", en: "Members can view family data by default, but editing or using wallets requires an explicit grant.", ja: "メンバーは既定で家族データを表示できますが、編集やウォレット利用には明示的な許可が必要です。", language: language) }
            static var mergedAccounts: String { L10n.tr("family.family.mergedAccounts", vi: "Danh sách tài khoản gộp", en: "Merged accounts", ja: "統合口座リスト") }
            static func mergedAccounts(language: MistiaAppLanguage) -> String { L10n.tr("family.family.mergedAccounts", vi: "Danh sách tài khoản gộp", en: "Merged accounts", ja: "統合口座リスト", language: language) }
            static var mistiaWillUseDataToSecurelySync: String { L10n.tr("family.family.mistiaWillUseDataToSecurelySync", vi: "Mistia sẽ sử dụng dữ liệu để đồng bộ và hiển thị thông tin gia đình của bạn một cách an toàn.", en: "Mistia will use data to securely sync and display your family information.", ja: "ミスティアはデータを安全に同期し、家族情報を表示するために使用します。") }
            static func mistiaWillUseDataToSecurelySync(language: MistiaAppLanguage) -> String { L10n.tr("family.family.mistiaWillUseDataToSecurelySync", vi: "Mistia sẽ sử dụng dữ liệu để đồng bộ và hiển thị thông tin gia đình của bạn một cách an toàn.", en: "Mistia will use data to securely sync and display your family information.", ja: "ミスティアはデータを安全に同期し、家族情報を表示するために使用します。", language: language) }
            static var month: String { L10n.tr("family.family.month", vi: "Tháng", en: "Month", ja: "月") }
            static func month(language: MistiaAppLanguage) -> String { L10n.tr("family.family.month", vi: "Tháng", en: "Month", ja: "月", language: language) }
            static func needValueMoreThisMonth(_ value: String) -> String {
                L10n.format("family.family.needValueMoreThisMonth", vi: "Cần bù thêm %@ trong tháng này.", en: "Need %@ more this month.", ja: "今月あと %@ 必要です。", value)
            }
            static func needValueMoreThisMonth(_ value: String, language: MistiaAppLanguage) -> String {
                L10n.format("family.family.needValueMoreThisMonth", vi: "Cần bù thêm %@ trong tháng này.", en: "Need %@ more this month.", ja: "今月あと %@ 必要です。", language: language, value)
            }
            static var newFamily: String { L10n.tr("family.family.newFamily", vi: "Gia đình mới", en: "New family", ja: "新しい家族") }
            static func newFamily(language: MistiaAppLanguage) -> String { L10n.tr("family.family.newFamily", vi: "Gia đình mới", en: "New family", ja: "新しい家族", language: language) }
            static var noBillsForMonth: String { L10n.tr("family.family.noBillsForMonth", vi: "Không có hóa đơn có số tiền trong tháng này", en: "No bills with amounts this month", ja: "この月は金額のある請求がありません") }
            static func noBillsForMonth(language: MistiaAppLanguage) -> String { L10n.tr("family.family.noBillsForMonth", vi: "Không có hóa đơn có số tiền trong tháng này", en: "No bills with amounts this month", ja: "この月は金額のある請求がありません", language: language) }
            static var noBudgetsAreOverLimit: String { L10n.tr("family.family.noBudgetsAreOverLimit", vi: "Chưa có ngân sách nào đang toang", en: "No budgets are over limit", ja: "予算オーバーはありません") }
            static func noBudgetsAreOverLimit(language: MistiaAppLanguage) -> String { L10n.tr("family.family.noBudgetsAreOverLimit", vi: "Chưa có ngân sách nào đang toang", en: "No budgets are over limit", ja: "予算オーバーはありません", language: language) }
            static var noInvitesYet: String { L10n.tr("family.family.noInvitesYet", vi: "Chưa có lời mời nào", en: "No invites yet", ja: "招待はまだありません") }
            static func noInvitesYet(language: MistiaAppLanguage) -> String { L10n.tr("family.family.noInvitesYet", vi: "Chưa có lời mời nào", en: "No invites yet", ja: "招待はまだありません", language: language) }
            static var noUpcomingItems: String { L10n.tr("family.family.noUpcomingItems", vi: "Không có khoản nào sắp tới", en: "No upcoming items", ja: "間もなく期限の項目はありません") }
            static func noUpcomingItems(language: MistiaAppLanguage) -> String { L10n.tr("family.family.noUpcomingItems", vi: "Không có khoản nào sắp tới", en: "No upcoming items", ja: "間もなく期限の項目はありません", language: language) }
            static var other: String { L10n.tr("family.family.other", vi: "Khác", en: "Other", ja: "その他") }
            static func other(language: MistiaAppLanguage) -> String { L10n.tr("family.family.other", vi: "Khác", en: "Other", ja: "その他", language: language) }
            static var otherMemberData: String { L10n.tr("family.family.otherMemberData", vi: "Dữ liệu thành viên khác", en: "Other members' data", ja: "他メンバーのデータ") }
            static func otherMemberData(language: MistiaAppLanguage) -> String { L10n.tr("family.family.otherMemberData", vi: "Dữ liệu thành viên khác", en: "Other members' data", ja: "他メンバーのデータ", language: language) }
            static var owner: String { L10n.tr("family.family.owner", vi: "Chủ sở hữu", en: "Owner", ja: "オーナー") }
            static func owner(language: MistiaAppLanguage) -> String { L10n.tr("family.family.owner", vi: "Chủ sở hữu", en: "Owner", ja: "オーナー", language: language) }
            static var pending: String { L10n.tr("family.family.pending", vi: "Đang chờ", en: "Pending", ja: "待機中") }
            static func pending(language: MistiaAppLanguage) -> String { L10n.tr("family.family.pending", vi: "Đang chờ", en: "Pending", ja: "待機中", language: language) }
            static var permissions: String { L10n.tr("family.family.permissions", vi: "Quyền", en: "Permissions", ja: "権限") }
            static func permissions(language: MistiaAppLanguage) -> String { L10n.tr("family.family.permissions", vi: "Quyền", en: "Permissions", ja: "権限", language: language) }
            static var permissions2: String { L10n.tr("family.family.permissions2", vi: "Quyền hạn", en: "Permissions", ja: "権限") }
            static func permissions2(language: MistiaAppLanguage) -> String { L10n.tr("family.family.permissions2", vi: "Quyền hạn", en: "Permissions", ja: "権限", language: language) }
            static var reconnectToCreateAFamilyUseAn: String { L10n.tr("family.family.reconnectToCreateAFamilyUseAn", vi: "Kết nối lại mạng để tạo gia đình mới, dùng link mời hoặc đồng bộ lại dữ liệu gia đình.", en: "Reconnect to create a family, use an invite link, or sync family data again.", ja: "ネットワークに再接続すると、家族の作成、招待リンクの使用、家族データの再同期が行えます。") }
            static func reconnectToCreateAFamilyUseAn(language: MistiaAppLanguage) -> String { L10n.tr("family.family.reconnectToCreateAFamilyUseAn", vi: "Kết nối lại mạng để tạo gia đình mới, dùng link mời hoặc đồng bộ lại dữ liệu gia đình.", en: "Reconnect to create a family, use an invite link, or sync family data again.", ja: "ネットワークに再接続すると、家族の作成、招待リンクの使用、家族データの再同期が行えます。", language: language) }
            static var removeFromFamily: String { L10n.tr("family.family.removeFromFamily", vi: "Xóa khỏi gia đình", en: "Remove from family", ja: "家族から削除") }
            static func removeFromFamily(language: MistiaAppLanguage) -> String { L10n.tr("family.family.removeFromFamily", vi: "Xóa khỏi gia đình", en: "Remove from family", ja: "家族から削除", language: language) }
            static var removeMember: String { L10n.tr("family.family.removeMember", vi: "Xóa thành viên?", en: "Remove member?", ja: "メンバーを削除しますか？") }
            static func removeMember(language: MistiaAppLanguage) -> String { L10n.tr("family.family.removeMember", vi: "Xóa thành viên?", en: "Remove member?", ja: "メンバーを削除しますか？", language: language) }
            static func removeValue(_ value: String) -> String {
                L10n.format("family.family.removeValue", vi: "Xóa %@ khỏi gia đình", en: "Remove %@", ja: "%@を削除", value)
            }
            static func removeValue(_ value: String, language: MistiaAppLanguage) -> String {
                L10n.format("family.family.removeValue", vi: "Xóa %@ khỏi gia đình", en: "Remove %@", ja: "%@を削除", language: language, value)
            }
            static var revoke: String { L10n.tr("family.family.revoke", vi: "Thu hồi", en: "Revoke", ja: "取り消す") }
            static func revoke(language: MistiaAppLanguage) -> String { L10n.tr("family.family.revoke", vi: "Thu hồi", en: "Revoke", ja: "取り消す", language: language) }
            static var revoked: String { L10n.tr("family.family.revoked", vi: "Đã thu hồi", en: "Revoked", ja: "取り消し済み") }
            static func revoked(language: MistiaAppLanguage) -> String { L10n.tr("family.family.revoked", vi: "Đã thu hồi", en: "Revoked", ja: "取り消し済み", language: language) }
            static func revokedValue(_ value: String) -> String {
                L10n.format("family.family.revokedValue", vi: "Đã thu hồi: %@", en: "Revoked: %@", ja: "取り消し: %@", value)
            }
            static func revokedValue(_ value: String, language: MistiaAppLanguage) -> String {
                L10n.format("family.family.revokedValue", vi: "Đã thu hồi: %@", en: "Revoked: %@", ja: "取り消し: %@", language: language, value)
            }
            static var role: String { L10n.tr("family.family.role", vi: "Role", en: "Role", ja: "役割") }
            static func role(language: MistiaAppLanguage) -> String { L10n.tr("family.family.role", vi: "Role", en: "Role", ja: "役割", language: language) }
            static var rolePermissions: String { L10n.tr("family.family.rolePermissions", vi: "Role & quyền", en: "Role & permissions", ja: "役割と権限") }
            static func rolePermissions(language: MistiaAppLanguage) -> String { L10n.tr("family.family.rolePermissions", vi: "Role & quyền", en: "Role & permissions", ja: "役割と権限", language: language) }
            static func roleValue(_ value: String) -> String {
                L10n.format("family.family.roleValue", vi: "Vai trò: %@", en: "Role: %@", ja: "役割: %@", value)
            }
            static func roleValue(_ value: String, language: MistiaAppLanguage) -> String {
                L10n.format("family.family.roleValue", vi: "Vai trò: %@", en: "Role: %@", ja: "役割: %@", language: language, value)
            }
            static func sentValue(_ value: String) -> String {
                L10n.format("family.family.sentValue", vi: "Đã gửi: %@", en: "Sent: %@", ja: "送信: %@", value)
            }
            static func sentValue(_ value: String, language: MistiaAppLanguage) -> String {
                L10n.format("family.family.sentValue", vi: "Đã gửi: %@", en: "Sent: %@", ja: "送信: %@", language: language, value)
            }
            static var share: String { L10n.tr("family.family.share", vi: "Chia sẻ", en: "Share", ja: "共有") }
            static func share(language: MistiaAppLanguage) -> String { L10n.tr("family.family.share", vi: "Chia sẻ", en: "Share", ja: "共有", language: language) }
            static var sharing: String { L10n.tr("family.family.sharing", vi: "Đang chia sẻ", en: "Sharing", ja: "共有中") }
            static func sharing(language: MistiaAppLanguage) -> String { L10n.tr("family.family.sharing", vi: "Đang chia sẻ", en: "Sharing", ja: "共有中", language: language) }
            static var singleItemFillsTheChart: String { L10n.tr("family.family.singleItemFillsTheChart", vi: "Một mục chiếm toàn bộ", en: "Single item fills the chart", ja: "1つの項目が全体を占めています") }
            static func singleItemFillsTheChart(language: MistiaAppLanguage) -> String { L10n.tr("family.family.singleItemFillsTheChart", vi: "Một mục chiếm toàn bộ", en: "Single item fills the chart", ja: "1つの項目が全体を占めています", language: language) }
            static var spendableThisMonth: String { L10n.tr("family.family.spendableThisMonth", vi: "Có thể chi tháng này", en: "Spendable this month", ja: "今月使える金額") }
            static func spendableThisMonth(language: MistiaAppLanguage) -> String { L10n.tr("family.family.spendableThisMonth", vi: "Có thể chi tháng này", en: "Spendable this month", ja: "今月使える金額", language: language) }
            static var spending: String { L10n.tr("family.family.spending", vi: "Chi tiêu", en: "Spending", ja: "支出") }
            static func spending(language: MistiaAppLanguage) -> String { L10n.tr("family.family.spending", vi: "Chi tiêu", en: "Spending", ja: "支出", language: language) }
            static var syncingFamily: String { L10n.tr("family.family.syncingFamily", vi: "Đang đồng bộ gia đình", en: "Syncing family", ja: "家族データを同期中") }
            static func syncingFamily(language: MistiaAppLanguage) -> String { L10n.tr("family.family.syncingFamily", vi: "Đang đồng bộ gia đình", en: "Syncing family", ja: "家族データを同期中", language: language) }
            static var tapTheOwnerSSharedLinkOr: String { L10n.tr("family.family.tapTheOwnerSSharedLinkOr", vi: "Bấm link chủ sở hữu đã chia sẻ, hoặc dán link nếu bạn đã copy.", en: "Tap the owner's shared link, or paste the link if you've copied it.", ja: "オーナーが共有したリンクを開くか、コピー済みのリンクを貼り付けます。") }
            static func tapTheOwnerSSharedLinkOr(language: MistiaAppLanguage) -> String { L10n.tr("family.family.tapTheOwnerSSharedLinkOr", vi: "Bấm link chủ sở hữu đã chia sẻ, hoặc dán link nếu bạn đã copy.", en: "Tap the owner's shared link, or paste the link if you've copied it.", ja: "オーナーが共有したリンクを開くか、コピー済みのリンクを貼り付けます。", language: language) }
            static var thisInviteLinkIsnTValid: String { L10n.tr("family.family.thisInviteLinkIsnTValid", vi: "Link mời không hợp lệ.", en: "This invite link isn't valid.", ja: "招待リンクが無効です。") }
            static func thisInviteLinkIsnTValid(language: MistiaAppLanguage) -> String { L10n.tr("family.family.thisInviteLinkIsnTValid", vi: "Link mời không hợp lệ.", en: "This invite link isn't valid.", ja: "招待リンクが無効です。", language: language) }
            static var thisMemberWillBeRemovedAndLose: String { L10n.tr("family.family.thisMemberWillBeRemovedAndLose", vi: "Thành viên này sẽ bị xóa khỏi gia đình và không còn quyền truy cập dữ liệu chung.", en: "This member will be removed and lose access to shared data.", ja: "このメンバーは家族から削除され、共有データにアクセスできなくなります。") }
            static func thisMemberWillBeRemovedAndLose(language: MistiaAppLanguage) -> String { L10n.tr("family.family.thisMemberWillBeRemovedAndLose", vi: "Thành viên này sẽ bị xóa khỏi gia đình và không còn quyền truy cập dữ liệu chung.", en: "This member will be removed and lose access to shared data.", ja: "このメンバーは家族から削除され、共有データにアクセスできなくなります。", language: language) }
            static var totalAssets: String { L10n.tr("family.family.totalAssets", vi: "Tổng tài sản", en: "Total assets", ja: "総資産") }
            static func totalAssets(language: MistiaAppLanguage) -> String { L10n.tr("family.family.totalAssets", vi: "Tổng tài sản", en: "Total assets", ja: "総資産", language: language) }
            static var transactionFilteringIsComingSoon: String { L10n.tr("family.family.transactionFilteringIsComingSoon", vi: "Tính năng lọc thu chi đang được hoàn thiện.", en: "Cashflow filtering is coming soon.", ja: "取引フィルター機能は近日公開予定です。") }
            static func transactionFilteringIsComingSoon(language: MistiaAppLanguage) -> String { L10n.tr("family.family.transactionFilteringIsComingSoon", vi: "Tính năng lọc thu chi đang được hoàn thiện.", en: "Cashflow filtering is coming soon.", ja: "取引フィルター機能は近日公開予定です。", language: language) }
            static var transactions: String { L10n.tr("family.family.transactions", vi: "Thu chi", en: "Cashflow", ja: "収支") }
            static func transactions(language: MistiaAppLanguage) -> String { L10n.tr("family.family.transactions", vi: "Thu chi", en: "Cashflow", ja: "収支", language: language) }
            static var transferOwner: String { L10n.tr("family.family.transferOwner", vi: "Nhượng quyền chủ sở hữu", en: "Transfer owner", ja: "オーナーを譲渡") }
            static func transferOwner(language: MistiaAppLanguage) -> String { L10n.tr("family.family.transferOwner", vi: "Nhượng quyền chủ sở hữu", en: "Transfer owner", ja: "オーナーを譲渡", language: language) }
            static var transferOwner2: String { L10n.tr("family.family.transferOwner2", vi: "Nhượng quyền chủ sở hữu?", en: "Transfer owner?", ja: "オーナーを譲渡しますか？") }
            static func transferOwner2(language: MistiaAppLanguage) -> String { L10n.tr("family.family.transferOwner2", vi: "Nhượng quyền chủ sở hữu?", en: "Transfer owner?", ja: "オーナーを譲渡しますか？", language: language) }
            static var upcoming: String { L10n.tr("family.family.upcoming", vi: "Sắp đến hạn", en: "Due soon", ja: "間もなく支払") }
            static func upcoming(language: MistiaAppLanguage) -> String { L10n.tr("family.family.upcoming", vi: "Sắp đến hạn", en: "Due soon", ja: "間もなく支払", language: language) }
            static var useInviteLink: String { L10n.tr("family.family.useInviteLink", vi: "Dùng link mời", en: "Use invite link", ja: "招待リンクを使う") }
            static func useInviteLink(language: MistiaAppLanguage) -> String { L10n.tr("family.family.useInviteLink", vi: "Dùng link mời", en: "Use invite link", ja: "招待リンクを使う", language: language) }
            static var used: String { L10n.tr("family.family.used", vi: "Đã dùng", en: "Used", ja: "使用済み") }
            static func used(language: MistiaAppLanguage) -> String { L10n.tr("family.family.used", vi: "Đã dùng", en: "Used", ja: "使用済み", language: language) }
            static func valueMembers(_ value: String) -> String {
                L10n.format("family.family.valueMembers", vi: "%@ thành viên", en: "%@ members", ja: "%@ 人のメンバー", value)
            }
            static func valueMembers(_ value: String, language: MistiaAppLanguage) -> String {
                L10n.format("family.family.valueMembers", vi: "%@ thành viên", en: "%@ members", ja: "%@ 人のメンバー", language: language, value)
            }
            static func valueWillBeTheOnlyOwnerOf(_ value: String) -> String {
                L10n.format("family.family.valueWillBeTheOnlyOwnerOf", vi: "%@ sẽ là chủ sở hữu duy nhất của gia đình này. Bạn sẽ không còn quyền quản lý thành viên sau khi chuyển.", en: "%@ will be the only owner of this family. You will no longer manage members after transfer.", ja: "%@ がこの家族の唯一のオーナーになります。譲渡後、あなたはメンバー管理ができません。", value)
            }
            static func valueWillBeTheOnlyOwnerOf(_ value: String, language: MistiaAppLanguage) -> String {
                L10n.format("family.family.valueWillBeTheOnlyOwnerOf", vi: "%@ sẽ là chủ sở hữu duy nhất của gia đình này. Bạn sẽ không còn quyền quản lý thành viên sau khi chuyển.", en: "%@ will be the only owner of this family. You will no longer manage members after transfer.", ja: "%@ がこの家族の唯一のオーナーになります。譲渡後、あなたはメンバー管理ができません。", language: language, value)
            }
            static var viewDetails: String { L10n.tr("family.family.viewDetails", vi: "Xem chi tiết", en: "View details", ja: "詳細を見る") }
            static func viewDetails(language: MistiaAppLanguage) -> String { L10n.tr("family.family.viewDetails", vi: "Xem chi tiết", en: "View details", ja: "詳細を見る", language: language) }
            static var viewFamilyDashboard: String { L10n.tr("family.family.viewFamilyDashboard", vi: "Xem báo cáo tổng quan gia đình", en: "View family dashboard", ja: "家族ダッシュボードを見る") }
            static func viewFamilyDashboard(language: MistiaAppLanguage) -> String { L10n.tr("family.family.viewFamilyDashboard", vi: "Xem báo cáo tổng quan gia đình", en: "View family dashboard", ja: "家族ダッシュボードを見る", language: language) }
            static var viewKids: String { L10n.tr("family.family.viewKids", vi: "Xem dữ liệu của trẻ em", en: "View kids", ja: "kid を表示") }
            static func viewKids(language: MistiaAppLanguage) -> String { L10n.tr("family.family.viewKids", vi: "Xem dữ liệu của trẻ em", en: "View kids", ja: "kid を表示", language: language) }
            static var viewOthers: String { L10n.tr("family.family.viewOthers", vi: "Xem dữ liệu của thành viên khác", en: "View others", ja: "他メンバーを表示") }
            static func viewOthers(language: MistiaAppLanguage) -> String { L10n.tr("family.family.viewOthers", vi: "Xem dữ liệu của thành viên khác", en: "View others", ja: "他メンバーを表示", language: language) }
            static func viewValueSData(_ value: String) -> String {
                L10n.format("family.family.viewValueSData", vi: "Xem dữ liệu của %@", en: "View %@'s data", ja: "%@のデータを見る", value)
            }
            static func viewValueSData(_ value: String, language: MistiaAppLanguage) -> String {
                L10n.format("family.family.viewValueSData", vi: "Xem dữ liệu của %@", en: "View %@'s data", ja: "%@のデータを見る", language: language, value)
            }
            static var viewWallets: String { L10n.tr("family.family.viewWallets", vi: "Xem số dư ví và tài khoản", en: "View wallets", ja: "ウォレットを見る") }
            static func viewWallets(language: MistiaAppLanguage) -> String { L10n.tr("family.family.viewWallets", vi: "Xem số dư ví và tài khoản", en: "View wallets", ja: "ウォレットを見る", language: language) }
            static var walletEditAccess: String { L10n.tr("family.family.walletEditAccess", vi: "Quyền chỉnh sửa ví", en: "Wallet edit access", ja: "ウォレット編集権限") }
            static func walletEditAccess(language: MistiaAppLanguage) -> String { L10n.tr("family.family.walletEditAccess", vi: "Quyền chỉnh sửa ví", en: "Wallet edit access", ja: "ウォレット編集権限", language: language) }
            static var walletUseAccess: String { L10n.tr("family.family.walletUseAccess", vi: "Quyền sử dụng ví", en: "Wallet use access", ja: "ウォレット使用権限") }
            static func walletUseAccess(language: MistiaAppLanguage) -> String { L10n.tr("family.family.walletUseAccess", vi: "Quyền sử dụng ví", en: "Wallet use access", ja: "ウォレット使用権限", language: language) }
            static var walletsAndAccounts: String { L10n.tr("family.family.walletsAndAccounts", vi: "Ví và tài khoản", en: "Wallets and accounts", ja: "ウォレットとアカウント") }
            static func walletsAndAccounts(language: MistiaAppLanguage) -> String { L10n.tr("family.family.walletsAndAccounts", vi: "Ví và tài khoản", en: "Wallets and accounts", ja: "ウォレットとアカウント", language: language) }
            static var walletsCards: String { L10n.tr("family.family.walletsCards", vi: "Ví / thẻ", en: "Wallets / cards", ja: "ウォレット・カード") }
            static func walletsCards(language: MistiaAppLanguage) -> String { L10n.tr("family.family.walletsCards", vi: "Ví / thẻ", en: "Wallets / cards", ja: "ウォレット・カード", language: language) }
            static var week: String { L10n.tr("family.family.week", vi: "Tuần", en: "Week", ja: "週") }
            static func week(language: MistiaAppLanguage) -> String { L10n.tr("family.family.week", vi: "Tuần", en: "Week", ja: "週", language: language) }
            static var year: String { L10n.tr("family.family.year", vi: "Năm", en: "Year", ja: "年") }
            static func year(language: MistiaAppLanguage) -> String { L10n.tr("family.family.year", vi: "Năm", en: "Year", ja: "年", language: language) }
            static var you: String { L10n.tr("family.family.you", vi: "(Bạn)", en: "(You)", ja: "(自分)") }
            static func you(language: MistiaAppLanguage) -> String { L10n.tr("family.family.you", vi: "(Bạn)", en: "(You)", ja: "(自分)", language: language) }
            static var youAlreadyHavePendingInvitesYou: String { L10n.tr("family.family.youAlreadyHavePendingInvitesYou", vi: "Bạn đang có 2 lời mời chờ phản hồi. Khi một lời mời hết hạn, bị từ chối, được chấp nhận hoặc thu hồi, bạn có thể tạo link mới.", en: "You already have 2 pending invites. You can create another link after one expires, is declined, accepted, or revoked.", ja: "待機中の招待が2件あります。いずれかが期限切れ、辞退、承認、取り消しになると新しいリンクを作成できます。") }
            static func youAlreadyHavePendingInvitesYou(language: MistiaAppLanguage) -> String { L10n.tr("family.family.youAlreadyHavePendingInvitesYou", vi: "Bạn đang có 2 lời mời chờ phản hồi. Khi một lời mời hết hạn, bị từ chối, được chấp nhận hoặc thu hồi, bạn có thể tạo link mới.", en: "You already have 2 pending invites. You can create another link after one expires, is declined, accepted, or revoked.", ja: "待機中の招待が2件あります。いずれかが期限切れ、辞退、承認、取り消しになると新しいリンクを作成できます。", language: language) }
            static var youBecomeTheOwnerAndInviteOthers: String { L10n.tr("family.family.youBecomeTheOwnerAndInviteOthers", vi: "Bạn trở thành chủ sở hữu và mời thêm thành viên sau.", en: "You become the owner and invite others later.", ja: "作成者がオーナーになり、あとでメンバーを招待できます。") }
            static func youBecomeTheOwnerAndInviteOthers(language: MistiaAppLanguage) -> String { L10n.tr("family.family.youBecomeTheOwnerAndInviteOthers", vi: "Bạn trở thành chủ sở hữu và mời thêm thành viên sau.", en: "You become the owner and invite others later.", ja: "作成者がオーナーになり、あとでメンバーを招待できます。", language: language) }
            static var youCanCheckWhatFamilyMembersCan: String { L10n.tr("family.family.youCanCheckWhatFamilyMembersCan", vi: "Bạn có thể kiểm tra những gì các thành viên trong gia đình có thể truy cập hoặc chia sẻ, đồng thời quản lý cài đặt tài khoản của trẻ em và các kiểm soát của phụ huynh.", en: "You can check what family members can access or share, while managing child account settings and parental controls.", ja: "ファミリーメンバーがアクセスまたは共有できるもの確認でき、お子様のアカウント設定と保護者による制限を管理できます。") }
            static func youCanCheckWhatFamilyMembersCan(language: MistiaAppLanguage) -> String { L10n.tr("family.family.youCanCheckWhatFamilyMembersCan", vi: "Bạn có thể kiểm tra những gì các thành viên trong gia đình có thể truy cập hoặc chia sẻ, đồng thời quản lý cài đặt tài khoản của trẻ em và các kiểm soát của phụ huynh.", en: "You can check what family members can access or share, while managing child account settings and parental controls.", ja: "ファミリーメンバーがアクセスまたは共有できるもの確認でき、お子様のアカウント設定と保護者による制限を管理できます。", language: language) }
            static var youDoNotHaveWalletsToShare: String { L10n.tr("family.family.youDoNotHaveWalletsToShare", vi: "Bạn chưa có ví nào để chia sẻ quyền chỉnh sửa.", en: "You do not have wallets to share edit access for yet.", ja: "編集権限を共有できるウォレットはまだありません。") }
            static func youDoNotHaveWalletsToShare(language: MistiaAppLanguage) -> String { L10n.tr("family.family.youDoNotHaveWalletsToShare", vi: "Bạn chưa có ví nào để chia sẻ quyền chỉnh sửa.", en: "You do not have wallets to share edit access for yet.", ja: "編集権限を共有できるウォレットはまだありません。", language: language) }
            static var youDoNotHaveWalletsToShare2: String { L10n.tr("family.family.youDoNotHaveWalletsToShare2", vi: "Bạn chưa có ví nào để chia sẻ quyền sử dụng.", en: "You do not have wallets to share use access for yet.", ja: "使用権限を共有できるウォレットはまだありません。") }
            static func youDoNotHaveWalletsToShare2(language: MistiaAppLanguage) -> String { L10n.tr("family.family.youDoNotHaveWalletsToShare2", vi: "Bạn chưa có ví nào để chia sẻ quyền sử dụng.", en: "You do not have wallets to share use access for yet.", ja: "使用権限を共有できるウォレットはまだありません。", language: language) }
            static var youWillNoLongerHaveAccessTo: String { L10n.tr("family.family.youWillNoLongerHaveAccessTo", vi: "Bạn sẽ không còn quyền truy cập vào dữ liệu chung của gia đình này nữa.", en: "You will no longer have access to this family's shared data.", ja: "この家族の共有データにアクセスできなくなります。") }
            static func youWillNoLongerHaveAccessTo(language: MistiaAppLanguage) -> String { L10n.tr("family.family.youWillNoLongerHaveAccessTo", vi: "Bạn sẽ không còn quyền truy cập vào dữ liệu chung của gia đình này nữa.", en: "You will no longer have access to this family's shared data.", ja: "この家族の共有データにアクセスできなくなります。", language: language) }
        }

        nonisolated enum familyinviteacceptance {
            static var accept: String { L10n.tr("family.familyinviteacceptance.accept", vi: "Chấp nhận", en: "Accept", ja: "承認") }
            static func accept(language: MistiaAppLanguage) -> String { L10n.tr("family.familyinviteacceptance.accept", vi: "Chấp nhận", en: "Accept", ja: "承認", language: language) }
            static var acceptThisInvite: String { L10n.tr("family.familyinviteacceptance.acceptThisInvite", vi: "Chấp nhận lời mời?", en: "Accept this invite?", ja: "この招待を承認しますか？") }
            static func acceptThisInvite(language: MistiaAppLanguage) -> String { L10n.tr("family.familyinviteacceptance.acceptThisInvite", vi: "Chấp nhận lời mời?", en: "Accept this invite?", ja: "この招待を承認しますか？", language: language) }
            static var alreadyJoined: String { L10n.tr("family.familyinviteacceptance.alreadyJoined", vi: "Đã tham gia", en: "Already joined", ja: "参加済み") }
            static func alreadyJoined(language: MistiaAppLanguage) -> String { L10n.tr("family.familyinviteacceptance.alreadyJoined", vi: "Đã tham gia", en: "Already joined", ja: "参加済み", language: language) }
            static var alreadyUsed: String { L10n.tr("family.familyinviteacceptance.alreadyUsed", vi: "Đã được dùng", en: "Already used", ja: "使用済み") }
            static func alreadyUsed(language: MistiaAppLanguage) -> String { L10n.tr("family.familyinviteacceptance.alreadyUsed", vi: "Đã được dùng", en: "Already used", ja: "使用済み", language: language) }
            static var anotherFamily: String { L10n.tr("family.familyinviteacceptance.anotherFamily", vi: "Gia đình khác", en: "Another family", ja: "別の家族") }
            static func anotherFamily(language: MistiaAppLanguage) -> String { L10n.tr("family.familyinviteacceptance.anotherFamily", vi: "Gia đình khác", en: "Another family", ja: "別の家族", language: language) }
            static var checkingInvite: String { L10n.tr("family.familyinviteacceptance.checkingInvite", vi: "Đang kiểm tra lời mời", en: "Checking invite", ja: "招待を確認中") }
            static func checkingInvite(language: MistiaAppLanguage) -> String { L10n.tr("family.familyinviteacceptance.checkingInvite", vi: "Đang kiểm tra lời mời", en: "Checking invite", ja: "招待を確認中", language: language) }
            static var decline: String { L10n.tr("family.familyinviteacceptance.decline", vi: "Từ chối", en: "Decline", ja: "辞退") }
            static func decline(language: MistiaAppLanguage) -> String { L10n.tr("family.familyinviteacceptance.decline", vi: "Từ chối", en: "Decline", ja: "辞退", language: language) }
            static var declineThisInvite: String { L10n.tr("family.familyinviteacceptance.declineThisInvite", vi: "Từ chối lời mời?", en: "Decline this invite?", ja: "この招待を辞退しますか？") }
            static func declineThisInvite(language: MistiaAppLanguage) -> String { L10n.tr("family.familyinviteacceptance.declineThisInvite", vi: "Từ chối lời mời?", en: "Decline this invite?", ja: "この招待を辞退しますか？", language: language) }
            static var declined: String { L10n.tr("family.familyinviteacceptance.declined", vi: "Đã từ chối", en: "Declined", ja: "辞退済み") }
            static func declined(language: MistiaAppLanguage) -> String { L10n.tr("family.familyinviteacceptance.declined", vi: "Đã từ chối", en: "Declined", ja: "辞退済み", language: language) }
            static var expired: String { L10n.tr("family.familyinviteacceptance.expired", vi: "Hết hạn", en: "Expired", ja: "期限切れ") }
            static func expired(language: MistiaAppLanguage) -> String { L10n.tr("family.familyinviteacceptance.expired", vi: "Hết hạn", en: "Expired", ja: "期限切れ", language: language) }
            static var invalid: String { L10n.tr("family.familyinviteacceptance.invalid", vi: "Không hợp lệ", en: "Invalid", ja: "無効") }
            static func invalid(language: MistiaAppLanguage) -> String { L10n.tr("family.familyinviteacceptance.invalid", vi: "Không hợp lệ", en: "Invalid", ja: "無効", language: language) }
            static var mistiaCanTCheckThisInviteRight: String { L10n.tr("family.familyinviteacceptance.mistiaCanTCheckThisInviteRight", vi: "Không thể kiểm tra lời mời lúc này.", en: "Mistia can't check this invite right now.", ja: "現在この招待を確認できません。") }
            static func mistiaCanTCheckThisInviteRight(language: MistiaAppLanguage) -> String { L10n.tr("family.familyinviteacceptance.mistiaCanTCheckThisInviteRight", vi: "Không thể kiểm tra lời mời lúc này.", en: "Mistia can't check this invite right now.", ja: "現在この招待を確認できません。", language: language) }
            static var mistiaWillKeepThisInviteAndReopen: String { L10n.tr("family.familyinviteacceptance.mistiaWillKeepThisInviteAndReopen", vi: "Mistia sẽ giữ lời mời này và tự mở lại sau khi bạn đăng nhập.", en: "Mistia will keep this invite and reopen it after you sign in.", ja: "ログイン後、この招待を自動で再開します。") }
            static func mistiaWillKeepThisInviteAndReopen(language: MistiaAppLanguage) -> String { L10n.tr("family.familyinviteacceptance.mistiaWillKeepThisInviteAndReopen", vi: "Mistia sẽ giữ lời mời này và tự mở lại sau khi bạn đăng nhập.", en: "Mistia will keep this invite and reopen it after you sign in.", ja: "ログイン後、この招待を自動で再開します。", language: language) }
            static var notForYou: String { L10n.tr("family.familyinviteacceptance.notForYou", vi: "Không dành cho bạn", en: "Not for you", ja: "利用できません") }
            static func notForYou(language: MistiaAppLanguage) -> String { L10n.tr("family.familyinviteacceptance.notForYou", vi: "Không dành cho bạn", en: "Not for you", ja: "利用できません", language: language) }
            static var offline: String { L10n.tr("family.familyinviteacceptance.offline", vi: "Mất kết nối", en: "Offline", ja: "オフライン") }
            static func offline(language: MistiaAppLanguage) -> String { L10n.tr("family.familyinviteacceptance.offline", vi: "Mất kết nối", en: "Offline", ja: "オフライン", language: language) }
            static var ok: String { L10n.tr("family.familyinviteacceptance.ok", vi: "Đồng ý", en: "OK", ja: "OK") }
            static func ok(language: MistiaAppLanguage) -> String { L10n.tr("family.familyinviteacceptance.ok", vi: "Đồng ý", en: "OK", ja: "OK", language: language) }
            static var pleaseAskTheInviterToSendA: String { L10n.tr("family.familyinviteacceptance.pleaseAskTheInviterToSendA", vi: "Vui lòng yêu cầu người mời gửi lại link mới.", en: "Please ask the inviter to send a new link.", ja: "招待者に新しいリンクを送ってもらってください。") }
            static func pleaseAskTheInviterToSendA(language: MistiaAppLanguage) -> String { L10n.tr("family.familyinviteacceptance.pleaseAskTheInviterToSendA", vi: "Vui lòng yêu cầu người mời gửi lại link mới.", en: "Please ask the inviter to send a new link.", ja: "招待者に新しいリンクを送ってもらってください。", language: language) }
            static var revoked: String { L10n.tr("family.familyinviteacceptance.revoked", vi: "Đã thu hồi", en: "Revoked", ja: "取消済み") }
            static func revoked(language: MistiaAppLanguage) -> String { L10n.tr("family.familyinviteacceptance.revoked", vi: "Đã thu hồi", en: "Revoked", ja: "取消済み", language: language) }
            static var signInNow: String { L10n.tr("family.familyinviteacceptance.signInNow", vi: "Đăng nhập ngay", en: "Sign in now", ja: "今すぐログイン") }
            static func signInNow(language: MistiaAppLanguage) -> String { L10n.tr("family.familyinviteacceptance.signInNow", vi: "Đăng nhập ngay", en: "Sign in now", ja: "今すぐログイン", language: language) }
            static var signInToViewThisInvite: String { L10n.tr("family.familyinviteacceptance.signInToViewThisInvite", vi: "Đăng nhập để xem lời mời", en: "Sign in to view this invite", ja: "招待を確認するにはログイン") }
            static func signInToViewThisInvite(language: MistiaAppLanguage) -> String { L10n.tr("family.familyinviteacceptance.signInToViewThisInvite", vi: "Đăng nhập để xem lời mời", en: "Sign in to view this invite", ja: "招待を確認するにはログイン", language: language) }
            static var theOwnerNeedsToCreateANew: String { L10n.tr("family.familyinviteacceptance.theOwnerNeedsToCreateANew", vi: "Chủ sở hữu cần tạo link mới nếu muốn mời lại.", en: "The owner needs to create a new link to invite again.", ja: "再招待するにはオーナーが新しいリンクを作成する必要があります。") }
            static func theOwnerNeedsToCreateANew(language: MistiaAppLanguage) -> String { L10n.tr("family.familyinviteacceptance.theOwnerNeedsToCreateANew", vi: "Chủ sở hữu cần tạo link mới nếu muốn mời lại.", en: "The owner needs to create a new link to invite again.", ja: "再招待するにはオーナーが新しいリンクを作成する必要があります。", language: language) }
            static var theOwnerRevokedThisInvite: String { L10n.tr("family.familyinviteacceptance.theOwnerRevokedThisInvite", vi: "Chủ sở hữu đã thu hồi lời mời này.", en: "The owner revoked this invite.", ja: "オーナーがこの招待を取り消しました。") }
            static func theOwnerRevokedThisInvite(language: MistiaAppLanguage) -> String { L10n.tr("family.familyinviteacceptance.theOwnerRevokedThisInvite", vi: "Chủ sở hữu đã thu hồi lời mời này.", en: "The owner revoked this invite.", ja: "オーナーがこの招待を取り消しました。", language: language) }
            static var thisAccountCurrentlyBelongsToAnotherFamily: String { L10n.tr("family.familyinviteacceptance.thisAccountCurrentlyBelongsToAnotherFamily", vi: "Tài khoản này đang thuộc một gia đình khác.", en: "This account currently belongs to another family.", ja: "このアカウントは現在別の家族に参加しています。") }
            static func thisAccountCurrentlyBelongsToAnotherFamily(language: MistiaAppLanguage) -> String { L10n.tr("family.familyinviteacceptance.thisAccountCurrentlyBelongsToAnotherFamily", vi: "Tài khoản này đang thuộc một gia đình khác.", en: "This account currently belongs to another family.", ja: "このアカウントは現在別の家族に参加しています。", language: language) }
            static func thisAccountIsAlreadyInValue(_ value: String) -> String {
                L10n.format("family.familyinviteacceptance.thisAccountIsAlreadyInValue", vi: "Tài khoản này đã ở trong %@.", en: "This account is already in %@.", ja: "このアカウントはすでに %@ に参加しています。", value)
            }
            static func thisAccountIsAlreadyInValue(_ value: String, language: MistiaAppLanguage) -> String {
                L10n.format("family.familyinviteacceptance.thisAccountIsAlreadyInValue", vi: "Tài khoản này đã ở trong %@.", en: "This account is already in %@.", ja: "このアカウントはすでに %@ に参加しています。", language: language, value)
            }
            static var thisLinkCannotBeUsedAgain: String { L10n.tr("family.familyinviteacceptance.thisLinkCannotBeUsedAgain", vi: "Link này sẽ không dùng lại được.", en: "This link cannot be used again.", ja: "このリンクは再利用できません。") }
            static func thisLinkCannotBeUsedAgain(language: MistiaAppLanguage) -> String { L10n.tr("family.familyinviteacceptance.thisLinkCannotBeUsedAgain", vi: "Link này sẽ không dùng lại được.", en: "This link cannot be used again.", ja: "このリンクは再利用できません。", language: language) }
            static var thisLinkHasAlreadyBeenUsed: String { L10n.tr("family.familyinviteacceptance.thisLinkHasAlreadyBeenUsed", vi: "Link này đã được sử dụng.", en: "This link has already been used.", ja: "このリンクはすでに使用されています。") }
            static func thisLinkHasAlreadyBeenUsed(language: MistiaAppLanguage) -> String { L10n.tr("family.familyinviteacceptance.thisLinkHasAlreadyBeenUsed", vi: "Link này đã được sử dụng.", en: "This link has already been used.", ja: "このリンクはすでに使用されています。", language: language) }
            static var thisLinkIsNoLongerValid: String { L10n.tr("family.familyinviteacceptance.thisLinkIsNoLongerValid", vi: "Link này không còn hợp lệ.", en: "This link is no longer valid.", ja: "このリンクは無効です。") }
            static func thisLinkIsNoLongerValid(language: MistiaAppLanguage) -> String { L10n.tr("family.familyinviteacceptance.thisLinkIsNoLongerValid", vi: "Link này không còn hợp lệ.", en: "This link is no longer valid.", ja: "このリンクは無効です。", language: language) }
            static var toTheFamily: String { L10n.tr("family.familyinviteacceptance.toTheFamily", vi: "đến với gia đình", en: "to the family", ja: "ファミリーへ") }
            static func toTheFamily(language: MistiaAppLanguage) -> String { L10n.tr("family.familyinviteacceptance.toTheFamily", vi: "đến với gia đình", en: "to the family", ja: "ファミリーへ", language: language) }
            static var unavailable: String { L10n.tr("family.familyinviteacceptance.unavailable", vi: "Không khả dụng", en: "Unavailable", ja: "利用不可") }
            static func unavailable(language: MistiaAppLanguage) -> String { L10n.tr("family.familyinviteacceptance.unavailable", vi: "Không khả dụng", en: "Unavailable", ja: "利用不可", language: language) }
            static var youCreatedThisInvite: String { L10n.tr("family.familyinviteacceptance.youCreatedThisInvite", vi: "Bạn là người tạo lời mời này.", en: "You created this invite.", ja: "この招待を作成したアカウントです。") }
            static func youCreatedThisInvite(language: MistiaAppLanguage) -> String { L10n.tr("family.familyinviteacceptance.youCreatedThisInvite", vi: "Bạn là người tạo lời mời này.", en: "You created this invite.", ja: "この招待を作成したアカウントです。", language: language) }
            static var youWillJoinThisFamilyAfterConfirming: String { L10n.tr("family.familyinviteacceptance.youWillJoinThisFamilyAfterConfirming", vi: "Bạn sẽ tham gia gia đình này sau khi xác nhận.", en: "You will join this family after confirming.", ja: "確認するとこのファミリーに参加します。") }
            static func youWillJoinThisFamilyAfterConfirming(language: MistiaAppLanguage) -> String { L10n.tr("family.familyinviteacceptance.youWillJoinThisFamilyAfterConfirming", vi: "Bạn sẽ tham gia gia đình này sau khi xác nhận.", en: "You will join this family after confirming.", ja: "確認するとこのファミリーに参加します。", language: language) }
        }

        nonisolated enum invite {
            static var linkPlaceholder: String { L10n.tr("family.invite.linkPlaceholder", vi: "mistia://family-invite/...", en: "mistia://family-invite/...", ja: "mistia://family-invite/...") }
            static func linkPlaceholder(language: MistiaAppLanguage) -> String { L10n.tr("family.invite.linkPlaceholder", vi: "mistia://family-invite/...", en: "mistia://family-invite/...", ja: "mistia://family-invite/...", language: language) }
        }

        nonisolated enum mistiaprivacy {
            static var familySharingIsDesignedToProtectYour: String { L10n.tr("family.mistiaprivacy.familySharingIsDesignedToProtectYour", vi: "Chia sẻ gia đình được thiết kế để bảo vệ thông tin cá nhân của bạn và cho phép bạn chọn những gì mình muốn chia sẻ.", en: "Family Sharing is designed to protect your information and let you choose what you share.", ja: "ファミリー共有はあなたの個人情報を保護するように設計され、どの情報を共有するかを選択できるようになっています。") }
            static func familySharingIsDesignedToProtectYour(language: MistiaAppLanguage) -> String { L10n.tr("family.mistiaprivacy.familySharingIsDesignedToProtectYour", vi: "Chia sẻ gia đình được thiết kế để bảo vệ thông tin cá nhân của bạn và cho phép bạn chọn những gì mình muốn chia sẻ.", en: "Family Sharing is designed to protect your information and let you choose what you share.", ja: "ファミリー共有はあなたの個人情報を保護するように設計され、どの情報を共有するかを選択できるようになっています。", language: language) }
            static var familySharingPrivacy: String { L10n.tr("family.mistiaprivacy.familySharingPrivacy", vi: "Chia sẻ Gia đình & Quyền riêng tư", en: "Family Sharing & Privacy", ja: "ファミリー共有とプライバシーについて") }
            static func familySharingPrivacy(language: MistiaAppLanguage) -> String { L10n.tr("family.mistiaprivacy.familySharingPrivacy", vi: "Chia sẻ Gia đình & Quyền riêng tư", en: "Family Sharing & Privacy", ja: "ファミリー共有とプライバシーについて", language: language) }
            static var mistiaUsesDataAboutYourFamilyMembership: String { L10n.tr("family.mistiaprivacy.mistiaUsesDataAboutYourFamilyMembership", vi: "Mistia sử dụng dữ liệu về tư cách thành viên gia đình của bạn để cải thiện trải nghiệm và đảm bảo tính minh bạch trong quản lý chi tiêu chung.", en: "Mistia uses data about your family membership to improve the experience and ensure transparency in shared spending management.", ja: "ミスティアはファミリーメンバーシップに関するデータを使用して、体験を向上させ、共有支出管理の透明性を確保します。") }
            static func mistiaUsesDataAboutYourFamilyMembership(language: MistiaAppLanguage) -> String { L10n.tr("family.mistiaprivacy.mistiaUsesDataAboutYourFamilyMembership", vi: "Mistia sử dụng dữ liệu về tư cách thành viên gia đình của bạn để cải thiện trải nghiệm và đảm bảo tính minh bạch trong quản lý chi tiêu chung.", en: "Mistia uses data about your family membership to improve the experience and ensure transparency in shared spending management.", ja: "ミスティアはファミリーメンバーシップに関するデータを使用して、体験を向上させ、共有支出管理の透明性を確保します。", language: language) }
            static var theAgeAndCountryOrRegionAssociated: String { L10n.tr("family.mistiaprivacy.theAgeAndCountryOrRegionAssociated", vi: "Độ tuổi và quốc gia hoặc khu vực được liên kết với tài khoản của bạn được sử dụng để xác nhận xem bạn là người lớn, trẻ vị thành niên hay trẻ em.", en: "The age and country or region associated with your account are used to confirm whether you are an adult, a minor, or a child.", ja: "アカウントに関連付けられている年齢および国または地域は、あなたが成人、未成年、または子供であるかどうかを確認するために使用されます。") }
            static func theAgeAndCountryOrRegionAssociated(language: MistiaAppLanguage) -> String { L10n.tr("family.mistiaprivacy.theAgeAndCountryOrRegionAssociated", vi: "Độ tuổi và quốc gia hoặc khu vực được liên kết với tài khoản của bạn được sử dụng để xác nhận xem bạn là người lớn, trẻ vị thành niên hay trẻ em.", en: "The age and country or region associated with your account are used to confirm whether you are an adult, a minor, or a child.", ja: "アカウントに関連付けられている年齢および国または地域は、あなたが成人、未成年、または子供であるかどうかを確認するために使用されます。", language: language) }
            static var whenYouStartOrJoinAFamily: String { L10n.tr("family.mistiaprivacy.whenYouStartOrJoinAFamily", vi: "Khi bạn bắt đầu hoặc tham gia một nhóm gia đình, bạn và các thành viên gia đình có thể chia sẻ các đăng ký, thu chi và thông tin tài chính để cùng nhau quản lý hiệu quả.", en: "When you start or join a family group, you and family members can share subscriptions, cashflow items, and financial information to manage effectively together.", ja: "ファミリーグループを開始するかファミリーグループに参加すると、あなたとファミリーメンバーがサブスクリプション、取引、財務情報を共有して効果的に管理できるようになります。") }
            static func whenYouStartOrJoinAFamily(language: MistiaAppLanguage) -> String { L10n.tr("family.mistiaprivacy.whenYouStartOrJoinAFamily", vi: "Khi bạn bắt đầu hoặc tham gia một nhóm gia đình, bạn và các thành viên gia đình có thể chia sẻ các đăng ký, thu chi và thông tin tài chính để cùng nhau quản lý hiệu quả.", en: "When you start or join a family group, you and family members can share subscriptions, cashflow items, and financial information to manage effectively together.", ja: "ファミリーグループを開始するかファミリーグループに参加すると、あなたとファミリーメンバーがサブスクリプション、取引、財務情報を共有して効果的に管理できるようになります。", language: language) }
        }
    }

    nonisolated enum investment {

        nonisolated enum asset {
            static var addImage: String { L10n.tr("investment.asset.addImage", vi: "Thêm ảnh", en: "Add image", ja: "画像を追加") }
            static func addImage(language: MistiaAppLanguage) -> String { L10n.tr("investment.asset.addImage", vi: "Thêm ảnh", en: "Add image", ja: "画像を追加", language: language) }
            static var choosePhoto: String { L10n.tr("investment.asset.choosePhoto", vi: "Chọn từ thư viện", en: "Choose from library", ja: "ライブラリから選択") }
            static func choosePhoto(language: MistiaAppLanguage) -> String { L10n.tr("investment.asset.choosePhoto", vi: "Chọn từ thư viện", en: "Choose from library", ja: "ライブラリから選択", language: language) }
            static var currency: String { L10n.tr("investment.asset.currency", vi: "Tiền tệ giao dịch", en: "Trading currency", ja: "取引通貨") }
            static func currency(language: MistiaAppLanguage) -> String { L10n.tr("investment.asset.currency", vi: "Tiền tệ giao dịch", en: "Trading currency", ja: "取引通貨", language: language) }
            static var imageOptional: String { L10n.tr("investment.asset.imageOptional", vi: "Ảnh sản phẩm (không bắt buộc)", en: "Product image (optional)", ja: "商品画像（任意）") }
            static func imageOptional(language: MistiaAppLanguage) -> String { L10n.tr("investment.asset.imageOptional", vi: "Ảnh sản phẩm (không bắt buộc)", en: "Product image (optional)", ja: "商品画像（任意）", language: language) }
            static var name: String { L10n.tr("investment.asset.name", vi: "Tên sản phẩm", en: "Product name", ja: "商品名") }
            static func name(language: MistiaAppLanguage) -> String { L10n.tr("investment.asset.name", vi: "Tên sản phẩm", en: "Product name", ja: "商品名", language: language) }
            static var namePlaceholder: String { L10n.tr("investment.asset.namePlaceholder", vi: "Ví dụ: Vật phẩm A", en: "For example: Card A", ja: "例：カードA") }
            static func namePlaceholder(language: MistiaAppLanguage) -> String { L10n.tr("investment.asset.namePlaceholder", vi: "Ví dụ: Vật phẩm A", en: "For example: Card A", ja: "例：カードA", language: language) }
            static var newTitle: String { L10n.tr("investment.asset.newTitle", vi: "Sản phẩm", en: "Product", ja: "商品") }
            static func newTitle(language: MistiaAppLanguage) -> String { L10n.tr("investment.asset.newTitle", vi: "Sản phẩm", en: "Product", ja: "商品", language: language) }
            static var removeImage: String { L10n.tr("investment.asset.removeImage", vi: "Xóa ảnh", en: "Remove image", ja: "画像を削除") }
            static func removeImage(language: MistiaAppLanguage) -> String { L10n.tr("investment.asset.removeImage", vi: "Xóa ảnh", en: "Remove image", ja: "画像を削除", language: language) }
            static var replaceImage: String { L10n.tr("investment.asset.replaceImage", vi: "Thay ảnh", en: "Replace image", ja: "画像を変更") }
            static func replaceImage(language: MistiaAppLanguage) -> String { L10n.tr("investment.asset.replaceImage", vi: "Thay ảnh", en: "Replace image", ja: "画像を変更", language: language) }
            static var takePhoto: String { L10n.tr("investment.asset.takePhoto", vi: "Chụp ảnh", en: "Take photo", ja: "写真を撮る") }
            static func takePhoto(language: MistiaAppLanguage) -> String { L10n.tr("investment.asset.takePhoto", vi: "Chụp ảnh", en: "Take photo", ja: "写真を撮る", language: language) }
        }

        nonisolated enum channel {
            static var name: String { L10n.tr("investment.channel.name", vi: "Tên kênh", en: "Channel name", ja: "チャネル名") }
            static func name(language: MistiaAppLanguage) -> String { L10n.tr("investment.channel.name", vi: "Tên kênh", en: "Channel name", ja: "チャネル名", language: language) }
            static var namePlaceholder: String { L10n.tr("investment.channel.namePlaceholder", vi: "Ví dụ: Card Pokémon", en: "For example: Pokémon cards", ja: "例：ポケモンカード") }
            static func namePlaceholder(language: MistiaAppLanguage) -> String { L10n.tr("investment.channel.namePlaceholder", vi: "Ví dụ: Card Pokémon", en: "For example: Pokémon cards", ja: "例：ポケモンカード", language: language) }
            static var newTitle: String { L10n.tr("investment.channel.newTitle", vi: "Kênh đầu tư mới", en: "New investment channel", ja: "新しい投資チャネル") }
            static func newTitle(language: MistiaAppLanguage) -> String { L10n.tr("investment.channel.newTitle", vi: "Kênh đầu tư mới", en: "New investment channel", ja: "新しい投資チャネル", language: language) }
        }

        nonisolated enum error {
            static var cannotTransferIn: String { L10n.tr("investment.error.cannotTransferIn", vi: "Không thể chuyển tiền vào Ví Đầu tư.", en: "Money cannot be transferred into the Investment Wallet.", ja: "投資ウォレットへ入金することはできません。") }
            static func cannotTransferIn(language: MistiaAppLanguage) -> String { L10n.tr("investment.error.cannotTransferIn", vi: "Không thể chuyển tiền vào Ví Đầu tư.", en: "Money cannot be transferred into the Investment Wallet.", ja: "投資ウォレットへ入金することはできません。", language: language) }
            static var closePositionsBeforeArchive: String { L10n.tr("investment.error.closePositionsBeforeArchive", vi: "Hãy bán hết hàng còn lại trước khi lưu trữ.", en: "Sell all remaining stock before archiving.", ja: "アーカイブする前に残りの在庫をすべて販売してください。") }
            static func closePositionsBeforeArchive(language: MistiaAppLanguage) -> String { L10n.tr("investment.error.closePositionsBeforeArchive", vi: "Hãy bán hết hàng còn lại trước khi lưu trữ.", en: "Sell all remaining stock before archiving.", ja: "アーカイブする前に残りの在庫をすべて販売してください。", language: language) }
            static var imageTooLarge: String { L10n.tr("investment.error.imageTooLarge", vi: "Không thể giảm ảnh này xuống dưới 4 MB. Hãy chọn ảnh khác.", en: "This image could not be reduced below 4 MB. Choose another image.", ja: "画像を4 MB未満に縮小できませんでした。別の画像を選んでください。") }
            static func imageTooLarge(language: MistiaAppLanguage) -> String { L10n.tr("investment.error.imageTooLarge", vi: "Không thể giảm ảnh này xuống dưới 4 MB. Hãy chọn ảnh khác.", en: "This image could not be reduced below 4 MB. Choose another image.", ja: "画像を4 MB未満に縮小できませんでした。別の画像を選んでください。", language: language) }
            static var insufficientFunds: String { L10n.tr("investment.error.insufficientFunds", vi: "Ví đã chọn không có đủ số dư khả dụng.", en: "The selected wallet does not have enough available funds.", ja: "選択したウォレットの利用可能残高が不足しています。") }
            static func insufficientFunds(language: MistiaAppLanguage) -> String { L10n.tr("investment.error.insufficientFunds", vi: "Ví đã chọn không có đủ số dư khả dụng.", en: "The selected wallet does not have enough available funds.", ja: "選択したウォレットの利用可能残高が不足しています。", language: language) }
            static var invalidTradeInput: String { L10n.tr("investment.error.invalidTradeInput", vi: "Dữ liệu giao dịch đầu tư không hợp lệ hoặc không nhất quán.", en: "The investment transaction data is invalid or inconsistent.", ja: "投資取引のデータが無効または整合していません。") }
            static func invalidTradeInput(language: MistiaAppLanguage) -> String { L10n.tr("investment.error.invalidTradeInput", vi: "Dữ liệu giao dịch đầu tư không hợp lệ hoặc không nhất quán.", en: "The investment transaction data is invalid or inconsistent.", ja: "投資取引のデータが無効または整合していません。", language: language) }
            static var invalidWallet: String { L10n.tr("investment.error.invalidWallet", vi: "Ví này không thể dùng cho thao tác đầu tư đó.", en: "This wallet cannot be used for that investment operation.", ja: "このウォレットはその投資操作には使用できません。") }
            static func invalidWallet(language: MistiaAppLanguage) -> String { L10n.tr("investment.error.invalidWallet", vi: "Ví này không thể dùng cho thao tác đầu tư đó.", en: "This wallet cannot be used for that investment operation.", ja: "このウォレットはその投資操作には使用できません。", language: language) }
            static var missingAsset: String { L10n.tr("investment.error.missingAsset", vi: "Sản phẩm này không còn tồn tại.", en: "This product no longer exists.", ja: "この商品は存在しません。") }
            static func missingAsset(language: MistiaAppLanguage) -> String { L10n.tr("investment.error.missingAsset", vi: "Sản phẩm này không còn tồn tại.", en: "This product no longer exists.", ja: "この商品は存在しません。", language: language) }
            static var missingExchangeRate: String { L10n.tr("investment.error.missingExchangeRate", vi: "Giao dịch này cần snapshot tỷ giá.", en: "An exchange-rate snapshot is required for this transaction.", ja: "この取引には為替レートのスナップショットが必要です。") }
            static func missingExchangeRate(language: MistiaAppLanguage) -> String { L10n.tr("investment.error.missingExchangeRate", vi: "Giao dịch này cần snapshot tỷ giá.", en: "An exchange-rate snapshot is required for this transaction.", ja: "この取引には為替レートのスナップショットが必要です。", language: language) }
            static var missingWallet: String { L10n.tr("investment.error.missingWallet", vi: "Hãy chọn một ví khả dụng.", en: "Choose an available wallet.", ja: "利用可能なウォレットを選択してください。") }
            static func missingWallet(language: MistiaAppLanguage) -> String { L10n.tr("investment.error.missingWallet", vi: "Hãy chọn một ví khả dụng.", en: "Choose an available wallet.", ja: "利用可能なウォレットを選択してください。", language: language) }
            static var transferExceedsBalance: String { L10n.tr("investment.error.transferExceedsBalance", vi: "Chỉ có thể chuyển tối đa bằng số dư dương hiện tại.", en: "You can only transfer up to the current positive balance.", ja: "現在のプラス残高までしか振替できません。") }
            static func transferExceedsBalance(language: MistiaAppLanguage) -> String { L10n.tr("investment.error.transferExceedsBalance", vi: "Chỉ có thể chuyển tối đa bằng số dư dương hiện tại.", en: "You can only transfer up to the current positive balance.", ja: "現在のプラス残高までしか振替できません。", language: language) }
        }

        nonisolated enum family {
            static var createAccess: String { L10n.tr("investment.family.createAccess", vi: "Tạo giao dịch & thêm tài sản", en: "Create trades & add assets", ja: "取引の追加と資産登録") }
            static func createAccess(language: MistiaAppLanguage) -> String { L10n.tr("investment.family.createAccess", vi: "Tạo giao dịch & thêm tài sản", en: "Create trades & add assets", ja: "取引の追加と資産登録", language: language) }
            static var editAccess: String { L10n.tr("investment.family.editAccess", vi: "Quản lý & chỉnh sửa danh mục", en: "Manage & edit portfolio", ja: "ポートフォリオの管理と編集") }
            static func editAccess(language: MistiaAppLanguage) -> String { L10n.tr("investment.family.editAccess", vi: "Quản lý & chỉnh sửa danh mục", en: "Manage & edit portfolio", ja: "ポートフォリオの管理と編集", language: language) }
            static var viewAccess: String { L10n.tr("investment.family.viewAccess", vi: "Xem danh mục đầu tư", en: "View investment portfolio", ja: "投資ポートフォリオの閲覧") }
            static func viewAccess(language: MistiaAppLanguage) -> String { L10n.tr("investment.family.viewAccess", vi: "Xem danh mục đầu tư", en: "View investment portfolio", ja: "投資ポートフォリオの閲覧", language: language) }
        }

        nonisolated enum hub {
            static var activity: String { L10n.tr("investment.hub.activity", vi: "Lịch sử mua bán", en: "Purchase and sales history", ja: "仕入れ・販売履歴") }
            static func activity(language: MistiaAppLanguage) -> String { L10n.tr("investment.hub.activity", vi: "Lịch sử mua bán", en: "Purchase and sales history", ja: "仕入れ・販売履歴", language: language) }
            static func activityDetails(_ arg1: String, _ arg2: String) -> String {
                L10n.format("investment.hub.activityDetails", vi: "%@ đơn vị · %@", en: "%@ units · %@", ja: "%@単位・%@", arg1, arg2)
            }
            static func activityDetails(_ arg1: String, _ arg2: String, language: MistiaAppLanguage) -> String {
                L10n.format("investment.hub.activityDetails", vi: "%@ đơn vị · %@", en: "%@ units · %@", ja: "%@単位・%@", language: language, arg1, arg2)
            }
            static var addAsset: String { L10n.tr("investment.hub.addAsset", vi: "Thêm sản phẩm", en: "Add product", ja: "商品を追加") }
            static func addAsset(language: MistiaAppLanguage) -> String { L10n.tr("investment.hub.addAsset", vi: "Thêm sản phẩm", en: "Add product", ja: "商品を追加", language: language) }
            static var addChannel: String { L10n.tr("investment.hub.addChannel", vi: "Thêm kênh", en: "Add channel", ja: "チャネルを追加") }
            static func addChannel(language: MistiaAppLanguage) -> String { L10n.tr("investment.hub.addChannel", vi: "Thêm kênh", en: "Add channel", ja: "チャネルを追加", language: language) }
            static var allChannels: String { L10n.tr("investment.hub.allChannels", vi: "Tất cả kênh", en: "All channels", ja: "すべてのチャネル") }
            static func allChannels(language: MistiaAppLanguage) -> String { L10n.tr("investment.hub.allChannels", vi: "Tất cả kênh", en: "All channels", ja: "すべてのチャネル", language: language) }
            static var allTime: String { L10n.tr("investment.hub.allTime", vi: "Tất cả", en: "All time", ja: "全期間") }
            static func allTime(language: MistiaAppLanguage) -> String { L10n.tr("investment.hub.allTime", vi: "Tất cả", en: "All time", ja: "全期間", language: language) }
            static var buy: String { L10n.tr("investment.hub.buy", vi: "Mua", en: "Buy", ja: "購入") }
            static func buy(language: MistiaAppLanguage) -> String { L10n.tr("investment.hub.buy", vi: "Mua", en: "Buy", ja: "購入", language: language) }
            static var channels: String { L10n.tr("investment.hub.channels", vi: "Kênh đầu tư", en: "Channels", ja: "チャネル") }
            static func channels(language: MistiaAppLanguage) -> String { L10n.tr("investment.hub.channels", vi: "Kênh đầu tư", en: "Channels", ja: "チャネル", language: language) }
            static var costBasis: String { L10n.tr("investment.hub.costBasis", vi: "Giá vốn", en: "Cost", ja: "原価") }
            static func costBasis(language: MistiaAppLanguage) -> String { L10n.tr("investment.hub.costBasis", vi: "Giá vốn", en: "Cost", ja: "原価", language: language) }
            static var emptyMessage: String { L10n.tr("investment.hub.emptyMessage", vi: "Tách từng shop, nhóm sản phẩm hoặc hoạt động mua đi bán lại thành từng kênh riêng.", en: "Separate each shop, product group, or small resale activity into its own channel.", ja: "ショップ、商品グループ、小規模な再販売をチャネルごとに管理できます。") }
            static func emptyMessage(language: MistiaAppLanguage) -> String { L10n.tr("investment.hub.emptyMessage", vi: "Tách từng shop, nhóm sản phẩm hoặc hoạt động mua đi bán lại thành từng kênh riêng.", en: "Separate each shop, product group, or small resale activity into its own channel.", ja: "ショップ、商品グループ、小規模な再販売をチャネルごとに管理できます。", language: language) }
            static var emptyTitle: String { L10n.tr("investment.hub.emptyTitle", vi: "Bắt đầu kênh đầu tư đầu tiên", en: "Start your first investment channel", ja: "最初の投資チャネルを始めましょう") }
            static func emptyTitle(language: MistiaAppLanguage) -> String { L10n.tr("investment.hub.emptyTitle", vi: "Bắt đầu kênh đầu tư đầu tiên", en: "Start your first investment channel", ja: "最初の投資チャネルを始めましょう", language: language) }
            static var investedCapital: String { L10n.tr("investment.hub.investedCapital", vi: "Giá vốn hàng còn", en: "Remaining inventory cost", ja: "残存在庫原価") }
            static func investedCapital(language: MistiaAppLanguage) -> String { L10n.tr("investment.hub.investedCapital", vi: "Giá vốn hàng còn", en: "Remaining inventory cost", ja: "残存在庫原価", language: language) }
            static var month: String { L10n.tr("investment.hub.month", vi: "Tháng", en: "Month", ja: "月") }
            static func month(language: MistiaAppLanguage) -> String { L10n.tr("investment.hub.month", vi: "Tháng", en: "Month", ja: "月", language: language) }
            static var noActivityForPeriod: String { L10n.tr("investment.hub.noActivityForPeriod", vi: "Chưa có giao dịch trong thời gian này.", en: "No transactions in this period.", ja: "この期間の取引はありません。") }
            static func noActivityForPeriod(language: MistiaAppLanguage) -> String { L10n.tr("investment.hub.noActivityForPeriod", vi: "Chưa có giao dịch trong thời gian này.", en: "No transactions in this period.", ja: "この期間の取引はありません。", language: language) }
            static var outOfStock: String { L10n.tr("investment.hub.outOfStock", vi: "Hết hàng", en: "Out of stock", ja: "在庫切れ") }
            static func outOfStock(language: MistiaAppLanguage) -> String { L10n.tr("investment.hub.outOfStock", vi: "Hết hàng", en: "Out of stock", ja: "在庫切れ", language: language) }
            static func positionDetails(_ arg1: String, _ arg2: String) -> String {
                L10n.format("investment.hub.positionDetails", vi: "Còn %@ · %@ lô nhập", en: "Remaining %@ · %@ purchase lots", ja: "残り %@・仕入れ %@ ロット", arg1, arg2)
            }
            static func positionDetails(_ arg1: String, _ arg2: String, language: MistiaAppLanguage) -> String {
                L10n.format("investment.hub.positionDetails", vi: "Còn %@ · %@ lô nhập", en: "Remaining %@ · %@ purchase lots", ja: "残り %@・仕入れ %@ ロット", language: language, arg1, arg2)
            }
            static var positions: String { L10n.tr("investment.hub.positions", vi: "Sản phẩm", en: "Products", ja: "商品") }
            static func positions(language: MistiaAppLanguage) -> String { L10n.tr("investment.hub.positions", vi: "Sản phẩm", en: "Products", ja: "商品", language: language) }
            static func quantityOnly(_ value: String) -> String {
                L10n.format("investment.hub.quantityOnly", vi: "%@ đơn vị", en: "%@ units", ja: "%@単位", value)
            }
            static func quantityOnly(_ value: String, language: MistiaAppLanguage) -> String {
                L10n.format("investment.hub.quantityOnly", vi: "%@ đơn vị", en: "%@ units", ja: "%@単位", language: language, value)
            }
            static var realizedProfitLoss: String { L10n.tr("investment.hub.realizedProfitLoss", vi: "Lãi/lỗ đã bán", en: "Profit/loss on sold items", ja: "販売済み損益") }
            static func realizedProfitLoss(language: MistiaAppLanguage) -> String { L10n.tr("investment.hub.realizedProfitLoss", vi: "Lãi/lỗ đã bán", en: "Profit/loss on sold items", ja: "販売済み損益", language: language) }
            static var sell: String { L10n.tr("investment.hub.sell", vi: "Bán", en: "Sell", ja: "売却") }
            static func sell(language: MistiaAppLanguage) -> String { L10n.tr("investment.hub.sell", vi: "Bán", en: "Sell", ja: "売却", language: language) }
            static var walletBalance: String { L10n.tr("investment.hub.walletBalance", vi: "Ví Đầu tư còn lại", en: "Investment wallet balance", ja: "投資ウォレット残高") }
            static func walletBalance(language: MistiaAppLanguage) -> String { L10n.tr("investment.hub.walletBalance", vi: "Ví Đầu tư còn lại", en: "Investment wallet balance", ja: "投資ウォレット残高", language: language) }
        }

        nonisolated enum overview {
            static var cardTitle: String { L10n.tr("investment.overview.cardTitle", vi: "Tổng quan đầu tư", en: "Investment overview", ja: "投資概要") }
            static func cardTitle(language: MistiaAppLanguage) -> String { L10n.tr("investment.overview.cardTitle", vi: "Tổng quan đầu tư", en: "Investment overview", ja: "投資概要", language: language) }
            static var `open`: String { L10n.tr("investment.overview.open", vi: "Xem danh mục đầu tư", en: "View Investment Portfolio", ja: "ポートフォリオを表示") }
            static func `open`(language: MistiaAppLanguage) -> String { L10n.tr("investment.overview.open", vi: "Xem danh mục đầu tư", en: "View Investment Portfolio", ja: "ポートフォリオを表示", language: language) }
            static var privateMessage: String { L10n.tr("investment.overview.privateMessage", vi: "Danh mục đầu tư cá nhân của thành viên được bảo mật mặc định. Vui lòng gửi yêu cầu để xem thông tin.", en: "Personal investment portfolios are protected by default. Request view access to examine details.", ja: "メンバーの個人投資ポートフォリオはデフォルトで保護されています。閲覧するにはアクセス権限をリクエストしてください。") }
            static func privateMessage(language: MistiaAppLanguage) -> String { L10n.tr("investment.overview.privateMessage", vi: "Danh mục đầu tư cá nhân của thành viên được bảo mật mặc định. Vui lòng gửi yêu cầu để xem thông tin.", en: "Personal investment portfolios are protected by default. Request view access to examine details.", ja: "メンバーの個人投資ポートフォリオはデフォルトで保護されています。閲覧するにはアクセス権限をリクエストしてください。", language: language) }
            static var privateTitle: String { L10n.tr("investment.overview.privateTitle", vi: "Danh mục đầu tư cá nhân", en: "Personal Investment Portfolio", ja: "個人投資ポートフォリオ") }
            static func privateTitle(language: MistiaAppLanguage) -> String { L10n.tr("investment.overview.privateTitle", vi: "Danh mục đầu tư cá nhân", en: "Personal Investment Portfolio", ja: "個人投資ポートフォリオ", language: language) }
        }

        nonisolated enum permission {
            static var accessRequired: String { L10n.tr("investment.permission.accessRequired", vi: "Yêu cầu quyền truy cập danh mục đầu tư", en: "Investment Portfolio Access Required", ja: "投資ポートフォリオのアクセス権が必要です") }
            static func accessRequired(language: MistiaAppLanguage) -> String { L10n.tr("investment.permission.accessRequired", vi: "Yêu cầu quyền truy cập danh mục đầu tư", en: "Investment Portfolio Access Required", ja: "投資ポートフォリオのアクセス権が必要です", language: language) }
            static var pending: String { L10n.tr("investment.permission.pending", vi: "Đang chờ duyệt", en: "Request pending", ja: "リクエスト承認待ち") }
            static func pending(language: MistiaAppLanguage) -> String { L10n.tr("investment.permission.pending", vi: "Đang chờ duyệt", en: "Request pending", ja: "リクエスト承認待ち", language: language) }
            static var requestCreate: String { L10n.tr("investment.permission.requestCreate", vi: "Yêu cầu quyền khởi tạo", en: "Request Creation Access", ja: "新規作成権限をリクエスト") }
            static func requestCreate(language: MistiaAppLanguage) -> String { L10n.tr("investment.permission.requestCreate", vi: "Yêu cầu quyền khởi tạo", en: "Request Creation Access", ja: "新規作成権限をリクエスト", language: language) }
            static var requestEdit: String { L10n.tr("investment.permission.requestEdit", vi: "Yêu cầu quyền quản lý", en: "Request Management Access", ja: "管理権限をリクエスト") }
            static func requestEdit(language: MistiaAppLanguage) -> String { L10n.tr("investment.permission.requestEdit", vi: "Yêu cầu quyền quản lý", en: "Request Management Access", ja: "管理権限をリクエスト", language: language) }
            static var requestView: String { L10n.tr("investment.permission.requestView", vi: "Yêu cầu quyền xem", en: "Request View Access", ja: "閲覧権限をリクエスト") }
            static func requestView(language: MistiaAppLanguage) -> String { L10n.tr("investment.permission.requestView", vi: "Yêu cầu quyền xem", en: "Request View Access", ja: "閲覧権限をリクエスト", language: language) }
            static var viewMessage: String { L10n.tr("investment.permission.viewMessage", vi: "Danh mục này thuộc quyền riêng tư của thành viên. Chỉ tài khoản chủ sở hữu và các thành viên được cấp quyền mới có thể truy cập thông tin.", en: "This portfolio belongs to the member. Only the owner and authorized family members can access investment details.", ja: "このポートフォリオはメンバーの個人データです。所有者および承認されたファミリーメンバーのみが投資情報にアクセスできます。") }
            static func viewMessage(language: MistiaAppLanguage) -> String { L10n.tr("investment.permission.viewMessage", vi: "Danh mục này thuộc quyền riêng tư của thành viên. Chỉ tài khoản chủ sở hữu và các thành viên được cấp quyền mới có thể truy cập thông tin.", en: "This portfolio belongs to the member. Only the owner and authorized family members can access investment details.", ja: "このポートフォリオはメンバーの個人データです。所有者および承認されたファミリーメンバーのみが投資情報にアクセスできます。", language: language) }
        }
        static var title: String { L10n.tr("investment.title", vi: "Đầu tư", en: "Investments", ja: "投資") }
        static func title(language: MistiaAppLanguage) -> String { L10n.tr("investment.title", vi: "Đầu tư", en: "Investments", ja: "投資", language: language) }

        nonisolated enum trade {
            static var asset: String { L10n.tr("investment.trade.asset", vi: "Sản phẩm", en: "Product", ja: "商品") }
            static func asset(language: MistiaAppLanguage) -> String { L10n.tr("investment.trade.asset", vi: "Sản phẩm", en: "Product", ja: "商品", language: language) }
            static func availableQuantity(_ value: String) -> String {
                L10n.format("investment.trade.availableQuantity", vi: "Có thể bán: %@", en: "Available: %@", ja: "売却可能：%@", value)
            }
            static func availableQuantity(_ value: String, language: MistiaAppLanguage) -> String {
                L10n.format("investment.trade.availableQuantity", vi: "Có thể bán: %@", en: "Available: %@", ja: "売却可能：%@", language: language, value)
            }
            static var buyTotal: String { L10n.tr("investment.trade.buyTotal", vi: "Tổng tiền mua", en: "Total purchase amount", ja: "仕入れ総額") }
            static func buyTotal(language: MistiaAppLanguage) -> String { L10n.tr("investment.trade.buyTotal", vi: "Tổng tiền mua", en: "Total purchase amount", ja: "仕入れ総額", language: language) }
            static var capitalWallet: String { L10n.tr("investment.trade.capitalWallet", vi: "Ví nhận lại vốn", en: "Wallet receiving returned capital", ja: "元本返却先ウォレット") }
            static func capitalWallet(language: MistiaAppLanguage) -> String { L10n.tr("investment.trade.capitalWallet", vi: "Ví nhận lại vốn", en: "Wallet receiving returned capital", ja: "元本返却先ウォレット", language: language) }
            static var chooseAsset: String { L10n.tr("investment.trade.chooseAsset", vi: "Chọn sản phẩm", en: "Choose product", ja: "商品を選択") }
            static func chooseAsset(language: MistiaAppLanguage) -> String { L10n.tr("investment.trade.chooseAsset", vi: "Chọn sản phẩm", en: "Choose product", ja: "商品を選択", language: language) }
            static var clearSearch: String { L10n.tr("investment.trade.clearSearch", vi: "Xóa tìm kiếm", en: "Clear search", ja: "検索を消去") }
            static func clearSearch(language: MistiaAppLanguage) -> String { L10n.tr("investment.trade.clearSearch", vi: "Xóa tìm kiếm", en: "Clear search", ja: "検索を消去", language: language) }
            static var deleteAction: String { L10n.tr("investment.trade.deleteAction", vi: "Xóa giao dịch", en: "Delete transaction", ja: "取引を削除") }
            static func deleteAction(language: MistiaAppLanguage) -> String { L10n.tr("investment.trade.deleteAction", vi: "Xóa giao dịch", en: "Delete transaction", ja: "取引を削除", language: language) }
            static var deleteConfirmation: String { L10n.tr("investment.trade.deleteConfirmation", vi: "Giao dịch này sẽ bị xóa khỏi lịch sử đầu tư. Bạn có muốn tiếp tục?", en: "This transaction will be removed from investment history. Do you want to continue?", ja: "この取引を投資履歴から削除します。続けますか？") }
            static func deleteConfirmation(language: MistiaAppLanguage) -> String { L10n.tr("investment.trade.deleteConfirmation", vi: "Giao dịch này sẽ bị xóa khỏi lịch sử đầu tư. Bạn có muốn tiếp tục?", en: "This transaction will be removed from investment history. Do you want to continue?", ja: "この取引を投資履歴から削除します。続けますか？", language: language) }
            static var deleteDescription: String { L10n.tr("investment.trade.deleteDescription", vi: "Giao dịch đã xóa sẽ không còn hiển thị trong lịch sử đầu tư.", en: "Deleted transactions no longer appear in investment history.", ja: "削除した取引は投資履歴に表示されなくなります。") }
            static func deleteDescription(language: MistiaAppLanguage) -> String { L10n.tr("investment.trade.deleteDescription", vi: "Giao dịch đã xóa sẽ không còn hiển thị trong lịch sử đầu tư.", en: "Deleted transactions no longer appear in investment history.", ja: "削除した取引は投資履歴に表示されなくなります。", language: language) }
            static var fundingWallet: String { L10n.tr("investment.trade.fundingWallet", vi: "Ví trả tiền", en: "Payment wallet", ja: "支払いウォレット") }
            static func fundingWallet(language: MistiaAppLanguage) -> String { L10n.tr("investment.trade.fundingWallet", vi: "Ví trả tiền", en: "Payment wallet", ja: "支払いウォレット", language: language) }
            static var grossAmount: String { L10n.tr("investment.trade.grossAmount", vi: "Tổng tiền giao dịch", en: "Total order amount", ja: "注文総額") }
            static func grossAmount(language: MistiaAppLanguage) -> String { L10n.tr("investment.trade.grossAmount", vi: "Tổng tiền giao dịch", en: "Total order amount", ja: "注文総額", language: language) }
            static var newBuyTitle: String { L10n.tr("investment.trade.newBuyTitle", vi: "Ghi nhận mua", en: "Record purchase", ja: "購入を記録") }
            static func newBuyTitle(language: MistiaAppLanguage) -> String { L10n.tr("investment.trade.newBuyTitle", vi: "Ghi nhận mua", en: "Record purchase", ja: "購入を記録", language: language) }
            static var newSellTitle: String { L10n.tr("investment.trade.newSellTitle", vi: "Ghi nhận bán", en: "Record sale", ja: "売却を記録") }
            static func newSellTitle(language: MistiaAppLanguage) -> String { L10n.tr("investment.trade.newSellTitle", vi: "Ghi nhận bán", en: "Record sale", ja: "売却を記録", language: language) }
            static var note: String { L10n.tr("investment.trade.note", vi: "Ghi chú", en: "Note", ja: "メモ") }
            static func note(language: MistiaAppLanguage) -> String { L10n.tr("investment.trade.note", vi: "Ghi chú", en: "Note", ja: "メモ", language: language) }
            static var quantity: String { L10n.tr("investment.trade.quantity", vi: "Số lượng", en: "Quantity", ja: "数量") }
            static func quantity(language: MistiaAppLanguage) -> String { L10n.tr("investment.trade.quantity", vi: "Số lượng", en: "Quantity", ja: "数量", language: language) }
            static var searchAsset: String { L10n.tr("investment.trade.searchAsset", vi: "Tìm sản phẩm hoặc kênh", en: "Search products or channels", ja: "商品またはチャネルを検索") }
            static func searchAsset(language: MistiaAppLanguage) -> String { L10n.tr("investment.trade.searchAsset", vi: "Tìm sản phẩm hoặc kênh", en: "Search products or channels", ja: "商品またはチャネルを検索", language: language) }
            static var sellTotal: String { L10n.tr("investment.trade.sellTotal", vi: "Tổng tiền bán", en: "Total sale amount", ja: "販売総額") }
            static func sellTotal(language: MistiaAppLanguage) -> String { L10n.tr("investment.trade.sellTotal", vi: "Tổng tiền bán", en: "Total sale amount", ja: "販売総額", language: language) }
            static var time: String { L10n.tr("investment.trade.time", vi: "Thời gian", en: "Time", ja: "日時") }
            static func time(language: MistiaAppLanguage) -> String { L10n.tr("investment.trade.time", vi: "Thời gian", en: "Time", ja: "日時", language: language) }
        }

        nonisolated enum transfer {
            static var destination: String { L10n.tr("investment.transfer.destination", vi: "Ví nhận tiền", en: "Destination wallet", ja: "振替先ウォレット") }
            static func destination(language: MistiaAppLanguage) -> String { L10n.tr("investment.transfer.destination", vi: "Ví nhận tiền", en: "Destination wallet", ja: "振替先ウォレット", language: language) }
            static var destinationAmount: String { L10n.tr("investment.transfer.destinationAmount", vi: "Số tiền ví nhận", en: "Destination amount", ja: "振替先の金額") }
            static func destinationAmount(language: MistiaAppLanguage) -> String { L10n.tr("investment.transfer.destinationAmount", vi: "Số tiền ví nhận", en: "Destination amount", ja: "振替先の金額", language: language) }
            static var sourceAmount: String { L10n.tr("investment.transfer.sourceAmount", vi: "Số tiền từ Ví Đầu tư", en: "Amount from Investment Wallet", ja: "投資ウォレットからの金額") }
            static func sourceAmount(language: MistiaAppLanguage) -> String { L10n.tr("investment.transfer.sourceAmount", vi: "Số tiền từ Ví Đầu tư", en: "Amount from Investment Wallet", ja: "投資ウォレットからの金額", language: language) }
        }

        nonisolated enum wallet {
            static var detailTitle: String { L10n.tr("investment.wallet.detailTitle", vi: "Ví Đầu tư", en: "Investment Wallet", ja: "投資ウォレット") }
            static func detailTitle(language: MistiaAppLanguage) -> String { L10n.tr("investment.wallet.detailTitle", vi: "Ví Đầu tư", en: "Investment Wallet", ja: "投資ウォレット", language: language) }
            static var name: String { L10n.tr("investment.wallet.name", vi: "Ví Đầu tư", en: "Investment Wallet", ja: "投資ウォレット") }
            static func name(language: MistiaAppLanguage) -> String { L10n.tr("investment.wallet.name", vi: "Ví Đầu tư", en: "Investment Wallet", ja: "投資ウォレット", language: language) }
            static var noPositiveBalance: String { L10n.tr("investment.wallet.noPositiveBalance", vi: "Không có số dư dương để chuyển ra.", en: "There is no positive balance available to transfer.", ja: "振替可能なプラス残高がありません。") }
            static func noPositiveBalance(language: MistiaAppLanguage) -> String { L10n.tr("investment.wallet.noPositiveBalance", vi: "Không có số dư dương để chuyển ra.", en: "There is no positive balance available to transfer.", ja: "振替可能なプラス残高がありません。", language: language) }
            static var transferOut: String { L10n.tr("investment.wallet.transferOut", vi: "Chuyển tiền ra", en: "Transfer out", ja: "出金する") }
            static func transferOut(language: MistiaAppLanguage) -> String { L10n.tr("investment.wallet.transferOut", vi: "Chuyển tiền ra", en: "Transfer out", ja: "出金する", language: language) }
            static var transferTitle: String { L10n.tr("investment.wallet.transferTitle", vi: "Chuyển từ Ví Đầu tư", en: "Transfer from Investment Wallet", ja: "投資ウォレットから振替") }
            static func transferTitle(language: MistiaAppLanguage) -> String { L10n.tr("investment.wallet.transferTitle", vi: "Chuyển từ Ví Đầu tư", en: "Transfer from Investment Wallet", ja: "投資ウォレットから振替", language: language) }
        }
    }

    nonisolated enum management {

        nonisolated enum balanceEditor {
            static var actualBalanceTitle: String { L10n.tr("management.balanceEditor.actualBalanceTitle", vi: "Số dư thực tế", en: "Actual balance", ja: "実際の残高") }
            static func actualBalanceTitle(language: MistiaAppLanguage) -> String { L10n.tr("management.balanceEditor.actualBalanceTitle", vi: "Số dư thực tế", en: "Actual balance", ja: "実際の残高", language: language) }
            static var categoryPickerTitleExpense: String { L10n.tr("management.balanceEditor.categoryPickerTitleExpense", vi: "Chọn danh mục chi tiêu", en: "Select expense category", ja: "支出カテゴリを選択") }
            static func categoryPickerTitleExpense(language: MistiaAppLanguage) -> String { L10n.tr("management.balanceEditor.categoryPickerTitleExpense", vi: "Chọn danh mục chi tiêu", en: "Select expense category", ja: "支出カテゴリを選択", language: language) }
            static var categoryPickerTitleIncome: String { L10n.tr("management.balanceEditor.categoryPickerTitleIncome", vi: "Chọn danh mục thu nhập", en: "Select income category", ja: "収入カテゴリを選択") }
            static func categoryPickerTitleIncome(language: MistiaAppLanguage) -> String { L10n.tr("management.balanceEditor.categoryPickerTitleIncome", vi: "Chọn danh mục thu nhập", en: "Select income category", ja: "収入カテゴリを選択", language: language) }
            static var categorySectionTitle: String { L10n.tr("management.balanceEditor.categorySectionTitle", vi: "Tính vào danh mục", en: "Assign to category", ja: "カテゴリに割り当て") }
            static func categorySectionTitle(language: MistiaAppLanguage) -> String { L10n.tr("management.balanceEditor.categorySectionTitle", vi: "Tính vào danh mục", en: "Assign to category", ja: "カテゴリに割り当て", language: language) }
            static var currentBalancePlaceholder: String { L10n.tr("management.balanceEditor.currentBalancePlaceholder", vi: "Nhập số dư hiện tại", en: "Enter current balance", ja: "現在の残高を入力") }
            static func currentBalancePlaceholder(language: MistiaAppLanguage) -> String { L10n.tr("management.balanceEditor.currentBalancePlaceholder", vi: "Nhập số dư hiện tại", en: "Enter current balance", ja: "現在の残高を入力", language: language) }
        }

        nonisolated enum categoryEditor {
            static var editTitle: String { L10n.tr("management.categoryEditor.editTitle", vi: "Sửa danh mục", en: "Edit category", ja: "カテゴリを編集") }
            static func editTitle(language: MistiaAppLanguage) -> String { L10n.tr("management.categoryEditor.editTitle", vi: "Sửa danh mục", en: "Edit category", ja: "カテゴリを編集", language: language) }
            static var newTitle: String { L10n.tr("management.categoryEditor.newTitle", vi: "Danh mục mới", en: "New category", ja: "新しいカテゴリ") }
            static func newTitle(language: MistiaAppLanguage) -> String { L10n.tr("management.categoryEditor.newTitle", vi: "Danh mục mới", en: "New category", ja: "新しいカテゴリ", language: language) }
        }

        nonisolated enum dataAction {

            nonisolated enum archivedItems {
                static var title: String { L10n.tr("management.dataAction.archivedItems.title", vi: "Mục đã lưu trữ", en: "Archived items", ja: "アーカイブ済みアイテム") }
                static func title(language: MistiaAppLanguage) -> String { L10n.tr("management.dataAction.archivedItems.title", vi: "Mục đã lưu trữ", en: "Archived items", ja: "アーカイブ済みアイテム", language: language) }
            }

            nonisolated enum backupRestore {
                static var title: String { L10n.tr("management.dataAction.backupRestore.title", vi: "Sao lưu & khôi phục", en: "Backup & restore", ja: "バックアップ & 復元") }
                static func title(language: MistiaAppLanguage) -> String { L10n.tr("management.dataAction.backupRestore.title", vi: "Sao lưu & khôi phục", en: "Backup & restore", ja: "バックアップ & 復元", language: language) }
            }

            nonisolated enum deleteAllData {
                static var title: String { L10n.tr("management.dataAction.deleteAllData.title", vi: "Xóa tất cả dữ liệu", en: "Delete all data", ja: "すべてのデータを削除") }
                static func title(language: MistiaAppLanguage) -> String { L10n.tr("management.dataAction.deleteAllData.title", vi: "Xóa tất cả dữ liệu", en: "Delete all data", ja: "すべてのデータを削除", language: language) }
            }

            nonisolated enum exportData {
                static var title: String { L10n.tr("management.dataAction.exportData.title", vi: "Xuất dữ liệu", en: "Export data", ja: "データを書き出す") }
                static func title(language: MistiaAppLanguage) -> String { L10n.tr("management.dataAction.exportData.title", vi: "Xuất dữ liệu", en: "Export data", ja: "データを書き出す", language: language) }
            }

            nonisolated enum importData {
                static var title: String { L10n.tr("management.dataAction.importData.title", vi: "Nhập dữ liệu", en: "Import data", ja: "データを取り込む") }
                static func title(language: MistiaAppLanguage) -> String { L10n.tr("management.dataAction.importData.title", vi: "Nhập dữ liệu", en: "Import data", ja: "データを取り込む", language: language) }
            }
        }

        nonisolated enum management {
            static var accessRequested: String { L10n.tr("management.management.accessRequested", vi: "Đã yêu cầu quyền", en: "Access requested", ja: "権限をリクエスト済み") }
            static func accessRequested(language: MistiaAppLanguage) -> String { L10n.tr("management.management.accessRequested", vi: "Đã yêu cầu quyền", en: "Access requested", ja: "権限をリクエスト済み", language: language) }
            static var addCashPayPayBankOrCreditCard: String { L10n.tr("management.management.addCashPayPayBankOrCreditCard", vi: "Thêm ví tiền mặt, PayPay, ví ngân hàng hoặc credit card để bắt đầu quản lý nguồn tiền.", en: "Add cash, PayPay, bank, or credit card wallets to start managing your money sources.", ja: "現金、PayPay、銀行口座、クレジットカードのウォレットを追加して資金管理を始めましょう。") }
            static func addCashPayPayBankOrCreditCard(language: MistiaAppLanguage) -> String { L10n.tr("management.management.addCashPayPayBankOrCreditCard", vi: "Thêm ví tiền mặt, PayPay, ví ngân hàng hoặc credit card để bắt đầu quản lý nguồn tiền.", en: "Add cash, PayPay, bank, or credit card wallets to start managing your money sources.", ja: "現金、PayPay、銀行口座、クレジットカードのウォレットを追加して資金管理を始めましょう。", language: language) }
            static var addCategory: String { L10n.tr("management.management.addCategory", vi: "Thêm danh mục", en: "Add category", ja: "カテゴリを追加") }
            static func addCategory(language: MistiaAppLanguage) -> String { L10n.tr("management.management.addCategory", vi: "Thêm danh mục", en: "Add category", ja: "カテゴリを追加", language: language) }
            static var addChildCategory: String { L10n.tr("management.management.addChildCategory", vi: "Thêm danh mục con", en: "Add child category", ja: "子カテゴリを追加") }
            static func addChildCategory(language: MistiaAppLanguage) -> String { L10n.tr("management.management.addChildCategory", vi: "Thêm danh mục con", en: "Add child category", ja: "子カテゴリを追加", language: language) }
            static var addParentCategory: String { L10n.tr("management.management.addParentCategory", vi: "Thêm danh mục cha", en: "Add parent category", ja: "親カテゴリを追加") }
            static func addParentCategory(language: MistiaAppLanguage) -> String { L10n.tr("management.management.addParentCategory", vi: "Thêm danh mục cha", en: "Add parent category", ja: "親カテゴリを追加", language: language) }
            static var addWallet: String { L10n.tr("management.management.addWallet", vi: "Thêm ví", en: "Add wallet", ja: "ウォレットを追加") }
            static func addWallet(language: MistiaAppLanguage) -> String { L10n.tr("management.management.addWallet", vi: "Thêm ví", en: "Add wallet", ja: "ウォレットを追加", language: language) }
            static var adjustmentReason: String { L10n.tr("management.management.adjustmentReason", vi: "Lý do điều chỉnh", en: "Adjustment reason", ja: "調整の理由") }
            static func adjustmentReason(language: MistiaAppLanguage) -> String { L10n.tr("management.management.adjustmentReason", vi: "Lý do điều chỉnh", en: "Adjustment reason", ja: "調整の理由", language: language) }
            static var agree: String { L10n.tr("management.management.agree", vi: "Đồng ý", en: "Agree", ja: "同意する") }
            static func agree(language: MistiaAppLanguage) -> String { L10n.tr("management.management.agree", vi: "Đồng ý", en: "Agree", ja: "同意する", language: language) }
            static var archiveCategory: String { L10n.tr("management.management.archiveCategory", vi: "Lưu trữ danh mục", en: "Archive category", ja: "カテゴリをアーカイブ") }
            static func archiveCategory(language: MistiaAppLanguage) -> String { L10n.tr("management.management.archiveCategory", vi: "Lưu trữ danh mục", en: "Archive category", ja: "カテゴリをアーカイブ", language: language) }
            static var archiveWallet: String { L10n.tr("management.management.archiveWallet", vi: "Lưu trữ ví", en: "Archive wallet", ja: "ウォレットをアーカイブ") }
            static func archiveWallet(language: MistiaAppLanguage) -> String { L10n.tr("management.management.archiveWallet", vi: "Lưu trữ ví", en: "Archive wallet", ja: "ウォレットをアーカイブ", language: language) }
            static var archivedCategoriesWillNoLongerAppearIn: String { L10n.tr("management.management.archivedCategoriesWillNoLongerAppearIn", vi: "Danh mục lưu trữ sẽ không còn hiện trong tab quản lý. Mục này sẽ được tự động xóa vĩnh viễn sau 30 ngày.", en: "Archived categories will no longer appear in the manage tab. They will be automatically deleted permanently after 30 days.", ja: "アーカイブしたカテゴリは管理タブに表示されなくなります。これらは30日後に自動的に永久削除されます。") }
            static func archivedCategoriesWillNoLongerAppearIn(language: MistiaAppLanguage) -> String { L10n.tr("management.management.archivedCategoriesWillNoLongerAppearIn", vi: "Danh mục lưu trữ sẽ không còn hiện trong tab quản lý. Mục này sẽ được tự động xóa vĩnh viễn sau 30 ngày.", en: "Archived categories will no longer appear in the manage tab. They will be automatically deleted permanently after 30 days.", ja: "アーカイブしたカテゴリは管理タブに表示されなくなります。これらは30日後に自動的に永久削除されます。", language: language) }
            static var archivedWalletsWillNoLongerAppearIn: String { L10n.tr("management.management.archivedWalletsWillNoLongerAppearIn", vi: "Ví lưu trữ sẽ không còn hiện trong tab quản lý. Mục này sẽ được tự động xóa vĩnh viễn sau 30 ngày.", en: "Archived wallets will no longer appear in the manage tab. They will be automatically deleted permanently after 30 days.", ja: "アーカイブしたウォレットは管理タブに表示されなくなります。これらは30日後に自動的に永久削除されます。") }
            static func archivedWalletsWillNoLongerAppearIn(language: MistiaAppLanguage) -> String { L10n.tr("management.management.archivedWalletsWillNoLongerAppearIn", vi: "Ví lưu trữ sẽ không còn hiện trong tab quản lý. Mục này sẽ được tự động xóa vĩnh viễn sau 30 ngày.", en: "Archived wallets will no longer appear in the manage tab. They will be automatically deleted permanently after 30 days.", ja: "アーカイブしたウォレットは管理タブに表示されなくなります。これらは30日後に自動的に永久削除されます。", language: language) }
            static var available: String { L10n.tr("management.management.available", vi: "Khả dụng", en: "Available", ja: "利用可能") }
            static func available(language: MistiaAppLanguage) -> String { L10n.tr("management.management.available", vi: "Khả dụng", en: "Available", ja: "利用可能", language: language) }
            static var balanceAdjustment: String { L10n.tr("management.management.balanceAdjustment", vi: "Điều chỉnh số dư", en: "Balance Adjustment", ja: "残高調整") }
            static func balanceAdjustment(language: MistiaAppLanguage) -> String { L10n.tr("management.management.balanceAdjustment", vi: "Điều chỉnh số dư", en: "Balance Adjustment", ja: "残高調整", language: language) }
            static var balanceAdjustment2: String { L10n.tr("management.management.balanceAdjustment2", vi: "Điều chỉnh số dư", en: "Balance adjustment", ja: "残高調整") }
            static func balanceAdjustment2(language: MistiaAppLanguage) -> String { L10n.tr("management.management.balanceAdjustment2", vi: "Điều chỉnh số dư", en: "Balance adjustment", ja: "残高調整", language: language) }
            static var bank: String { L10n.tr("management.management.bank", vi: "Ngân hàng", en: "Bank", ja: "銀行") }
            static func bank(language: MistiaAppLanguage) -> String { L10n.tr("management.management.bank", vi: "Ngân hàng", en: "Bank", ja: "銀行", language: language) }
            static var basicDetails: String { L10n.tr("management.management.basicDetails", vi: "Thông tin cơ bản", en: "Basic details", ja: "基本情報") }
            static func basicDetails(language: MistiaAppLanguage) -> String { L10n.tr("management.management.basicDetails", vi: "Thông tin cơ bản", en: "Basic details", ja: "基本情報", language: language) }
            static var biUTNgDanhMC: String { L10n.tr("management.management.biUTNgDanhMC", vi: "Biểu tượng danh mục", en: "Category icon", ja: "カテゴリアイコン") }
            static func biUTNgDanhMC(language: MistiaAppLanguage) -> String { L10n.tr("management.management.biUTNgDanhMC", vi: "Biểu tượng danh mục", en: "Category icon", ja: "カテゴリアイコン", language: language) }
            static var biUTNgV: String { L10n.tr("management.management.biUTNgV", vi: "Biểu tượng ví", en: "Wallet icon", ja: "ウォレットアイコン") }
            static func biUTNgV(language: MistiaAppLanguage) -> String { L10n.tr("management.management.biUTNgV", vi: "Biểu tượng ví", en: "Wallet icon", ja: "ウォレットアイコン", language: language) }
            static var canTSaveYet: String { L10n.tr("management.management.canTSaveYet", vi: "Chưa thể lưu", en: "Can't save yet", ja: "まだ保存できません") }
            static func canTSaveYet(language: MistiaAppLanguage) -> String { L10n.tr("management.management.canTSaveYet", vi: "Chưa thể lưu", en: "Can't save yet", ja: "まだ保存できません", language: language) }
            static func cannotArchiveCreditCardWithOutstandingDebt(_ value: String) -> String {
                L10n.format("management.management.cannotArchiveCreditCardWithOutstandingDebt", vi: "Không thể lưu trữ thẻ tín dụng khi còn dư nợ chưa thanh toán (dư nợ hiện tại: %@).", en: "Cannot archive credit card with outstanding debt (current debt: %@).", ja: "未払いの債務があるためクレジットカードをアーカイブできません（現在の債務：%@）。", value)
            }
            static func cannotArchiveCreditCardWithOutstandingDebt(_ value: String, language: MistiaAppLanguage) -> String {
                L10n.format("management.management.cannotArchiveCreditCardWithOutstandingDebt", vi: "Không thể lưu trữ thẻ tín dụng khi còn dư nợ chưa thanh toán (dư nợ hiện tại: %@).", en: "Cannot archive credit card with outstanding debt (current debt: %@).", ja: "未払いの債務があるためクレジットカードをアーカイブできません（現在の債務：%@）。", language: language, value)
            }
            static var cannotArchiveCreditCardWithUnpaidStatements: String { L10n.tr("management.management.cannotArchiveCreditCardWithUnpaidStatements", vi: "Không thể lưu trữ thẻ tín dụng khi còn sao kê chưa thanh toán.", en: "Cannot archive credit card with unpaid statements.", ja: "未払いの明細があるためクレジットカードをアーカイブできません。") }
            static func cannotArchiveCreditCardWithUnpaidStatements(language: MistiaAppLanguage) -> String { L10n.tr("management.management.cannotArchiveCreditCardWithUnpaidStatements", vi: "Không thể lưu trữ thẻ tín dụng khi còn sao kê chưa thanh toán.", en: "Cannot archive credit card with unpaid statements.", ja: "未払いの明細があるためクレジットカードをアーカイブできません。", language: language) }
            static var cardNetwork: String { L10n.tr("management.management.cardNetwork", vi: "Mạng thẻ", en: "Card network", ja: "カードブランド") }
            static func cardNetwork(language: MistiaAppLanguage) -> String { L10n.tr("management.management.cardNetwork", vi: "Mạng thẻ", en: "Card network", ja: "カードブランド", language: language) }
            static var categories: String { L10n.tr("management.management.categories", vi: "danh mục", en: "categories", ja: "カテゴリ") }
            static func categories(language: MistiaAppLanguage) -> String { L10n.tr("management.management.categories", vi: "danh mục", en: "categories", ja: "カテゴリ", language: language) }
            static var categories2: String { L10n.tr("management.management.categories2", vi: "Danh mục", en: "Categories", ja: "カテゴリ") }
            static func categories2(language: MistiaAppLanguage) -> String { L10n.tr("management.management.categories2", vi: "Danh mục", en: "Categories", ja: "カテゴリ", language: language) }
            static var categoryArchiveBlockedHasBills: String { L10n.tr("management.management.categoryArchiveBlockedHasBills", vi: "Không thể lưu trữ danh mục này vì đang được liên kết với hóa đơn.", en: "Cannot archive this category because it is linked to bills.", ja: "請求書が関連付けられているため、このカテゴリをアーカイブできません。") }
            static func categoryArchiveBlockedHasBills(language: MistiaAppLanguage) -> String { L10n.tr("management.management.categoryArchiveBlockedHasBills", vi: "Không thể lưu trữ danh mục này vì đang được liên kết với hóa đơn.", en: "Cannot archive this category because it is linked to bills.", ja: "請求書が関連付けられているため、このカテゴリをアーカイブできません。", language: language) }
            static var categoryArchiveBlockedHasBudgets: String { L10n.tr("management.management.categoryArchiveBlockedHasBudgets", vi: "Không thể lưu trữ danh mục này vì đang được liên kết với ngân sách.", en: "Cannot archive this category because it is linked to budgets.", ja: "予算が関連付けられているため、このカテゴリをアーカイブできません。") }
            static func categoryArchiveBlockedHasBudgets(language: MistiaAppLanguage) -> String { L10n.tr("management.management.categoryArchiveBlockedHasBudgets", vi: "Không thể lưu trữ danh mục này vì đang được liên kết với ngân sách.", en: "Cannot archive this category because it is linked to budgets.", ja: "予算が関連付けられているため、このカテゴリをアーカイブできません。", language: language) }
            static var categoryArchiveBlockedHasChildren: String { L10n.tr("management.management.categoryArchiveBlockedHasChildren", vi: "Không thể lưu trữ danh mục này vì vẫn còn các danh mục con đang hoạt động.", en: "Cannot archive this category because it still has active subcategories.", ja: "有効なサブカテゴリがまだ存在するため、このカテゴリをアーカイブできません。") }
            static func categoryArchiveBlockedHasChildren(language: MistiaAppLanguage) -> String { L10n.tr("management.management.categoryArchiveBlockedHasChildren", vi: "Không thể lưu trữ danh mục này vì vẫn còn các danh mục con đang hoạt động.", en: "Cannot archive this category because it still has active subcategories.", ja: "有効なサブカテゴリがまだ存在するため、このカテゴリをアーカイブできません。", language: language) }
            static var categoryArchiveBlockedHasTransactions: String { L10n.tr("management.management.categoryArchiveBlockedHasTransactions", vi: "Không thể lưu trữ danh mục này vì đang được liên kết với các khoản thu chi.", en: "Cannot archive this category because it is linked to transactions.", ja: "取引が関連付けられているため、このカテゴリをアーカイブできません。") }
            static func categoryArchiveBlockedHasTransactions(language: MistiaAppLanguage) -> String { L10n.tr("management.management.categoryArchiveBlockedHasTransactions", vi: "Không thể lưu trữ danh mục này vì đang được liên kết với các khoản thu chi.", en: "Cannot archive this category because it is linked to transactions.", ja: "取引が関連付けられているため、このカテゴリをアーカイブできません。", language: language) }
            static var categoryBudgetBranchCurrentMonthBlock: String { L10n.tr("management.management.categoryBudgetBranchCurrentMonthBlock", vi: "Nhánh danh mục này đang được dùng bởi ngân sách tháng hiện tại. Hãy xóa các ngân sách tháng này trước khi đổi tên hoặc cấu trúc.", en: "This category branch is used by a current-month budget. Delete those budgets before changing the name or structure.", ja: "このカテゴリ枝は当月の予算で使用されています。名前や構造を変更する前に、その月の予算を削除してください。") }
            static func categoryBudgetBranchCurrentMonthBlock(language: MistiaAppLanguage) -> String { L10n.tr("management.management.categoryBudgetBranchCurrentMonthBlock", vi: "Nhánh danh mục này đang được dùng bởi ngân sách tháng hiện tại. Hãy xóa các ngân sách tháng này trước khi đổi tên hoặc cấu trúc.", en: "This category branch is used by a current-month budget. Delete those budgets before changing the name or structure.", ja: "このカテゴリ枝は当月の予算で使用されています。名前や構造を変更する前に、その月の予算を削除してください。", language: language) }
            static var categoryName: String { L10n.tr("management.management.categoryName", vi: "Tên danh mục", en: "Category name", ja: "カテゴリ名") }
            static func categoryName(language: MistiaAppLanguage) -> String { L10n.tr("management.management.categoryName", vi: "Tên danh mục", en: "Category name", ja: "カテゴリ名", language: language) }
            static var categoryNameAlreadyExists: String { L10n.tr("management.management.categoryNameAlreadyExists", vi: "Tên danh mục này đã tồn tại trong ứng dụng.", en: "This category name already exists in the app.", ja: "このカテゴリ名は既にアプリ内に存在します。") }
            static func categoryNameAlreadyExists(language: MistiaAppLanguage) -> String { L10n.tr("management.management.categoryNameAlreadyExists", vi: "Tên danh mục này đã tồn tại trong ứng dụng.", en: "This category name already exists in the app.", ja: "このカテゴリ名は既にアプリ内に存在します。", language: language) }
            static var categoryType: String { L10n.tr("management.management.categoryType", vi: "Loại danh mục", en: "Category type", ja: "カテゴリ種別") }
            static func categoryType(language: MistiaAppLanguage) -> String { L10n.tr("management.management.categoryType", vi: "Loại danh mục", en: "Category type", ja: "カテゴリ種別", language: language) }
            static var chooseACoordinatedFinanceIconForThis: String { L10n.tr("management.management.chooseACoordinatedFinanceIconForThis", vi: "Chọn icon tài chính đồng bộ cho danh mục", en: "Choose a coordinated finance icon for this category", ja: "カテゴリに統一感のある金融アイコンを選択") }
            static func chooseACoordinatedFinanceIconForThis(language: MistiaAppLanguage) -> String { L10n.tr("management.management.chooseACoordinatedFinanceIconForThis", vi: "Chọn icon tài chính đồng bộ cho danh mục", en: "Choose a coordinated finance icon for this category", ja: "カテゴリに統一感のある金融アイコンを選択", language: language) }
            static var chooseAParentCategoryForThisChild: String { L10n.tr("management.management.chooseAParentCategoryForThisChild", vi: "Chọn danh mục cha cho danh mục con này.", en: "Choose a parent category for this child category.", ja: "この子カテゴリの親カテゴリを選択してください。") }
            static func chooseAParentCategoryForThisChild(language: MistiaAppLanguage) -> String { L10n.tr("management.management.chooseAParentCategoryForThisChild", vi: "Chọn danh mục cha cho danh mục con này.", en: "Choose a parent category for this child category.", ja: "この子カテゴリの親カテゴリを選択してください。", language: language) }
            static var chooseAPopularBank: String { L10n.tr("management.management.chooseAPopularBank", vi: "Chọn ngân hàng phổ biến", en: "Choose a popular bank", ja: "よく使われる銀行を選択") }
            static func chooseAPopularBank(language: MistiaAppLanguage) -> String { L10n.tr("management.management.chooseAPopularBank", vi: "Chọn ngân hàng phổ biến", en: "Choose a popular bank", ja: "よく使われる銀行を選択", language: language) }
            static var chooseBank: String { L10n.tr("management.management.chooseBank", vi: "Chọn ngân hàng", en: "Choose bank", ja: "銀行を選択") }
            static func chooseBank(language: MistiaAppLanguage) -> String { L10n.tr("management.management.chooseBank", vi: "Chọn ngân hàng", en: "Choose bank", ja: "銀行を選択", language: language) }
            static var chooseLater: String { L10n.tr("management.management.chooseLater", vi: "Chọn sau", en: "Choose later", ja: "あとで選択") }
            static func chooseLater(language: MistiaAppLanguage) -> String { L10n.tr("management.management.chooseLater", vi: "Chọn sau", en: "Choose later", ja: "あとで選択", language: language) }
            static var chooseOrEnterABankNameFor: String { L10n.tr("management.management.chooseOrEnterABankNameFor", vi: "Chọn hoặc nhập tên ngân hàng cho ví này.", en: "Choose or enter a bank name for this wallet.", ja: "このウォレットの銀行名を選択または入力してください。") }
            static func chooseOrEnterABankNameFor(language: MistiaAppLanguage) -> String { L10n.tr("management.management.chooseOrEnterABankNameFor", vi: "Chọn hoặc nhập tên ngân hàng cho ví này.", en: "Choose or enter a bank name for this wallet.", ja: "このウォレットの銀行名を選択または入力してください。", language: language) }
            static var chooseParentCategory: String { L10n.tr("management.management.chooseParentCategory", vi: "Chọn danh mục cha", en: "Choose parent category", ja: "親カテゴリを選択") }
            static func chooseParentCategory(language: MistiaAppLanguage) -> String { L10n.tr("management.management.chooseParentCategory", vi: "Chọn danh mục cha", en: "Choose parent category", ja: "親カテゴリを選択", language: language) }
            static var close: String { L10n.tr("management.management.close", vi: "Đóng", en: "Close", ja: "閉じる") }
            static func close(language: MistiaAppLanguage) -> String { L10n.tr("management.management.close", vi: "Đóng", en: "Close", ja: "閉じる", language: language) }
            static var confirmPaymentSourceChange: String { L10n.tr("management.management.confirmPaymentSourceChange", vi: "Xác nhận thay đổi ví thanh toán", en: "Confirm payment source change", ja: "支払い元ウォレットの変更を確認") }
            static func confirmPaymentSourceChange(language: MistiaAppLanguage) -> String { L10n.tr("management.management.confirmPaymentSourceChange", vi: "Xác nhận thay đổi ví thanh toán", en: "Confirm payment source change", ja: "支払い元ウォレットの変更を確認", language: language) }
            static var `continue`: String { L10n.tr("management.management.continue", vi: "Tiếp tục", en: "Continue", ja: "続行") }
            static func `continue`(language: MistiaAppLanguage) -> String { L10n.tr("management.management.continue", vi: "Tiếp tục", en: "Continue", ja: "続行", language: language) }
            static var couldnTSaveTheArchiveState: String { L10n.tr("management.management.couldnTSaveTheArchiveState", vi: "Không thể lưu trạng thái lưu trữ.", en: "Couldn't save the archive state.", ja: "アーカイブ状態を保存できません。") }
            static func couldnTSaveTheArchiveState(language: MistiaAppLanguage) -> String { L10n.tr("management.management.couldnTSaveTheArchiveState", vi: "Không thể lưu trạng thái lưu trữ.", en: "Couldn't save the archive state.", ja: "アーカイブ状態を保存できません。", language: language) }
            static var couldnTSaveThisCategoryRightNow: String { L10n.tr("management.management.couldnTSaveThisCategoryRightNow", vi: "Không thể lưu danh mục lúc này.", en: "Couldn't save this category right now.", ja: "現在このカテゴリを保存できません。") }
            static func couldnTSaveThisCategoryRightNow(language: MistiaAppLanguage) -> String { L10n.tr("management.management.couldnTSaveThisCategoryRightNow", vi: "Không thể lưu danh mục lúc này.", en: "Couldn't save this category right now.", ja: "現在このカテゴリを保存できません。", language: language) }
            static var couldnTSaveThisWalletRightNow: String { L10n.tr("management.management.couldnTSaveThisWalletRightNow", vi: "Không thể lưu ví lúc này.", en: "Couldn't save this wallet right now.", ja: "現在このウォレットを保存できません。") }
            static func couldnTSaveThisWalletRightNow(language: MistiaAppLanguage) -> String { L10n.tr("management.management.couldnTSaveThisWalletRightNow", vi: "Không thể lưu ví lúc này.", en: "Couldn't save this wallet right now.", ja: "現在このウォレットを保存できません。", language: language) }
            static var couldnTSend: String { L10n.tr("management.management.couldnTSend", vi: "Chưa thể gửi", en: "Couldn't send", ja: "送信できませんでした") }
            static func couldnTSend(language: MistiaAppLanguage) -> String { L10n.tr("management.management.couldnTSend", vi: "Chưa thể gửi", en: "Couldn't send", ja: "送信できませんでした", language: language) }
            static var couldnTSendTheRequestRightNow: String { L10n.tr("management.management.couldnTSendTheRequestRightNow", vi: "Không thể gửi yêu cầu lúc này.", en: "Couldn't send the request right now.", ja: "現在リクエストは送信できません。") }
            static func couldnTSendTheRequestRightNow(language: MistiaAppLanguage) -> String { L10n.tr("management.management.couldnTSendTheRequestRightNow", vi: "Không thể gửi yêu cầu lúc này.", en: "Couldn't send the request right now.", ja: "現在リクエストは送信できません。", language: language) }
            static var couldnTUpdateFavorite: String { L10n.tr("management.management.couldnTUpdateFavorite", vi: "Không thể cập nhật yêu thích", en: "Couldn't update favorite", ja: "お気に入りを更新できませんでした") }
            static func couldnTUpdateFavorite(language: MistiaAppLanguage) -> String { L10n.tr("management.management.couldnTUpdateFavorite", vi: "Không thể cập nhật yêu thích", en: "Couldn't update favorite", ja: "お気に入りを更新できませんでした", language: language) }
            static var createExpenseGroupsSoYourTransactionsAnd: String { L10n.tr("management.management.createExpenseGroupsSoYourTransactionsAnd", vi: "Tạo nhóm chi tiêu riêng để thu chi và ngân sách bám sát cách bạn quản lý hằng ngày.", en: "Create expense groups so your cashflow items and budgets match how you manage money every day.", ja: "支出グループを作成すると、取引や予算を日々の管理方法に合わせやすくなります。") }
            static func createExpenseGroupsSoYourTransactionsAnd(language: MistiaAppLanguage) -> String { L10n.tr("management.management.createExpenseGroupsSoYourTransactionsAnd", vi: "Tạo nhóm chi tiêu riêng để thu chi và ngân sách bám sát cách bạn quản lý hằng ngày.", en: "Create expense groups so your cashflow items and budgets match how you manage money every day.", ja: "支出グループを作成すると、取引や予算を日々の管理方法に合わせやすくなります。", language: language) }
            static var createRequestApproved: String { L10n.tr("management.management.createRequestApproved", vi: "Đã chấp nhận yêu cầu thêm mới", en: "Create request approved", ja: "作成リクエストが承認済み") }
            static func createRequestApproved(language: MistiaAppLanguage) -> String { L10n.tr("management.management.createRequestApproved", vi: "Đã chấp nhận yêu cầu thêm mới", en: "Create request approved", ja: "作成リクエストが承認済み", language: language) }
            static var createRequestSent: String { L10n.tr("management.management.createRequestSent", vi: "Đã gửi yêu cầu thêm mới", en: "Create request sent", ja: "作成リクエスト送信済み") }
            static func createRequestSent(language: MistiaAppLanguage) -> String { L10n.tr("management.management.createRequestSent", vi: "Đã gửi yêu cầu thêm mới", en: "Create request sent", ja: "作成リクエスト送信済み", language: language) }
            static var createRequested: String { L10n.tr("management.management.createRequested", vi: "Đã yêu cầu thêm mới", en: "Create requested", ja: "作成権限をリクエスト済み") }
            static func createRequested(language: MistiaAppLanguage) -> String { L10n.tr("management.management.createRequested", vi: "Đã yêu cầu thêm mới", en: "Create requested", ja: "作成権限をリクエスト済み", language: language) }
            static var creditCard: String { L10n.tr("management.management.creditCard", vi: "Credit card", en: "Credit card", ja: "クレジットカード") }
            static func creditCard(language: MistiaAppLanguage) -> String { L10n.tr("management.management.creditCard", vi: "Credit card", en: "Credit card", ja: "クレジットカード", language: language) }
            static var creditCard2: String { L10n.tr("management.management.creditCard2", vi: "Thẻ tín dụng", en: "Credit card", ja: "クレジットカード") }
            static func creditCard2(language: MistiaAppLanguage) -> String { L10n.tr("management.management.creditCard2", vi: "Thẻ tín dụng", en: "Credit card", ja: "クレジットカード", language: language) }
            static var creditLimit: String { L10n.tr("management.management.creditLimit", vi: "Hạn mức tín dụng", en: "Credit limit", ja: "利用限度額") }
            static func creditLimit(language: MistiaAppLanguage) -> String { L10n.tr("management.management.creditLimit", vi: "Hạn mức tín dụng", en: "Credit limit", ja: "利用限度額", language: language) }
            static func creditLimitCannotBeLessThanCurrentDebt(_ value: String) -> String {
                L10n.format("management.management.creditLimitCannotBeLessThanCurrentDebt", vi: "Hạn mức không được nhỏ hơn dư nợ hiện tại (%@).", en: "Credit limit cannot be less than current debt (%@).", ja: "利用限度額は現在の負債（%@）より小さくできません。", value)
            }
            static func creditLimitCannotBeLessThanCurrentDebt(_ value: String, language: MistiaAppLanguage) -> String {
                L10n.format("management.management.creditLimitCannotBeLessThanCurrentDebt", vi: "Hạn mức không được nhỏ hơn dư nợ hiện tại (%@).", en: "Credit limit cannot be less than current debt (%@).", ja: "利用限度額は現在の負債（%@）より小さくできません。", language: language, value)
            }
            static var currency: String { L10n.tr("management.management.currency", vi: "Tiền tệ", en: "Currency", ja: "通貨") }
            static func currency(language: MistiaAppLanguage) -> String { L10n.tr("management.management.currency", vi: "Tiền tệ", en: "Currency", ja: "通貨", language: language) }
            static var currentBalance: String { L10n.tr("management.management.currentBalance", vi: "Số dư hiện tại", en: "Current balance", ja: "現在の残高") }
            static func currentBalance(language: MistiaAppLanguage) -> String { L10n.tr("management.management.currentBalance", vi: "Số dư hiện tại", en: "Current balance", ja: "現在の残高", language: language) }
            static func dayValue(_ value: String) -> String {
                L10n.format("management.management.dayValue", vi: "Ngày %@", en: "Day %@", ja: "%@ 日", value)
            }
            static func dayValue(_ value: String, language: MistiaAppLanguage) -> String {
                L10n.format("management.management.dayValue", vi: "Ngày %@", en: "Day %@", ja: "%@ 日", language: language, value)
            }
            static var details: String { L10n.tr("management.management.details", vi: "Thông tin", en: "Details", ja: "詳細") }
            static func details(language: MistiaAppLanguage) -> String { L10n.tr("management.management.details", vi: "Thông tin", en: "Details", ja: "詳細", language: language) }
            static var donTSeeItHere: String { L10n.tr("management.management.donTSeeItHere", vi: "Không thấy trong danh sách?", en: "Don't see it here?", ja: "一覧にありませんか？") }
            static func donTSeeItHere(language: MistiaAppLanguage) -> String { L10n.tr("management.management.donTSeeItHere", vi: "Không thấy trong danh sách?", en: "Don't see it here?", ja: "一覧にありませんか？", language: language) }
            static var eGAuditError: String { L10n.tr("management.management.eGAuditError", vi: "Ví dụ: Kiểm kê lại, sai sót...", en: "e.g. Audit, error...", ja: "例：棚卸し、入力ミスなど") }
            static func eGAuditError(language: MistiaAppLanguage) -> String { L10n.tr("management.management.eGAuditError", vi: "Ví dụ: Kiểm kê lại, sai sót...", en: "e.g. Audit, error...", ja: "例：棚卸し、入力ミスなど", language: language) }
            static var edit: String { L10n.tr("management.management.edit", vi: "Sửa", en: "Edit", ja: "編集") }
            static func edit(language: MistiaAppLanguage) -> String { L10n.tr("management.management.edit", vi: "Sửa", en: "Edit", ja: "編集", language: language) }
            static var editBalance: String { L10n.tr("management.management.editBalance", vi: "Sửa số dư", en: "Edit balance", ja: "残高を編集") }
            static func editBalance(language: MistiaAppLanguage) -> String { L10n.tr("management.management.editBalance", vi: "Sửa số dư", en: "Edit balance", ja: "残高を編集", language: language) }
            static var editRequestApproved: String { L10n.tr("management.management.editRequestApproved", vi: "Đã chấp nhận yêu cầu chỉnh sửa", en: "Edit request approved", ja: "編集リクエストが承認済み") }
            static func editRequestApproved(language: MistiaAppLanguage) -> String { L10n.tr("management.management.editRequestApproved", vi: "Đã chấp nhận yêu cầu chỉnh sửa", en: "Edit request approved", ja: "編集リクエストが承認済み", language: language) }
            static var editRequestSent: String { L10n.tr("management.management.editRequestSent", vi: "Đã gửi yêu cầu chỉnh sửa", en: "Edit request sent", ja: "編集リクエスト送信済み") }
            static func editRequestSent(language: MistiaAppLanguage) -> String { L10n.tr("management.management.editRequestSent", vi: "Đã gửi yêu cầu chỉnh sửa", en: "Edit request sent", ja: "編集リクエスト送信済み", language: language) }
            static var editRequested: String { L10n.tr("management.management.editRequested", vi: "Đã yêu cầu chỉnh sửa", en: "Edit requested", ja: "編集権限をリクエスト済み") }
            static func editRequested(language: MistiaAppLanguage) -> String { L10n.tr("management.management.editRequested", vi: "Đã yêu cầu chỉnh sửa", en: "Edit requested", ja: "編集権限をリクエスト済み", language: language) }
            static var enterACategoryNameBeforeSaving: String { L10n.tr("management.management.enterACategoryNameBeforeSaving", vi: "Nhập tên danh mục trước khi lưu.", en: "Enter a category name before saving.", ja: "保存する前にカテゴリ名を入力してください。") }
            static func enterACategoryNameBeforeSaving(language: MistiaAppLanguage) -> String { L10n.tr("management.management.enterACategoryNameBeforeSaving", vi: "Nhập tên danh mục trước khi lưu.", en: "Enter a category name before saving.", ja: "保存する前にカテゴリ名を入力してください。", language: language) }
            static var enterBankNameManually: String { L10n.tr("management.management.enterBankNameManually", vi: "Nhập thủ công tên ngân hàng", en: "Enter bank name manually", ja: "銀行名を手入力") }
            static func enterBankNameManually(language: MistiaAppLanguage) -> String { L10n.tr("management.management.enterBankNameManually", vi: "Nhập thủ công tên ngân hàng", en: "Enter bank name manually", ja: "銀行名を手入力", language: language) }
            static var family: String { L10n.tr("management.management.family", vi: "Gia đình", en: "Family", ja: "家族") }
            static func family(language: MistiaAppLanguage) -> String { L10n.tr("management.management.family", vi: "Gia đình", en: "Family", ja: "家族", language: language) }
            static var favorite: String { L10n.tr("management.management.favorite", vi: "Yêu thích", en: "Favorite", ja: "お気に入り") }
            static func favorite(language: MistiaAppLanguage) -> String { L10n.tr("management.management.favorite", vi: "Yêu thích", en: "Favorite", ja: "お気に入り", language: language) }
            static var icon: String { L10n.tr("management.management.icon", vi: "Biểu tượng", en: "Icon", ja: "アイコン") }
            static func icon(language: MistiaAppLanguage) -> String { L10n.tr("management.management.icon", vi: "Biểu tượng", en: "Icon", ja: "アイコン", language: language) }
            static var identity: String { L10n.tr("management.management.identity", vi: "Nhận diện", en: "Identity", ja: "識別情報") }
            static func identity(language: MistiaAppLanguage) -> String { L10n.tr("management.management.identity", vi: "Nhận diện", en: "Identity", ja: "識別情報", language: language) }
            static var issuerName: String { L10n.tr("management.management.issuerName", vi: "Tên đơn vị phát hành", en: "Issuer name", ja: "発行会社名") }
            static func issuerName(language: MistiaAppLanguage) -> String { L10n.tr("management.management.issuerName", vi: "Tên đơn vị phát hành", en: "Issuer name", ja: "発行会社名", language: language) }
            static var lastDigits: String { L10n.tr("management.management.lastDigits", vi: "4 số cuối", en: "Last 4 digits", ja: "下4桁") }
            static func lastDigits(language: MistiaAppLanguage) -> String { L10n.tr("management.management.lastDigits", vi: "4 số cuối", en: "Last 4 digits", ja: "下4桁", language: language) }
            static var manage: String { L10n.tr("management.management.manage", vi: "Quản lý", en: "Manage", ja: "マネジメント") }
            static func manage(language: MistiaAppLanguage) -> String { L10n.tr("management.management.manage", vi: "Quản lý", en: "Manage", ja: "マネジメント", language: language) }
            static var markAsFavorite: String { L10n.tr("management.management.markAsFavorite", vi: "Đánh dấu yêu thích", en: "Mark as favorite", ja: "お気に入りに追加") }
            static func markAsFavorite(language: MistiaAppLanguage) -> String { L10n.tr("management.management.markAsFavorite", vi: "Đánh dấu yêu thích", en: "Mark as favorite", ja: "お気に入りに追加", language: language) }
            static var noCategoryCreateAccess: String { L10n.tr("management.management.noCategoryCreateAccess", vi: "Chưa có quyền thêm mới danh mục", en: "No category create access", ja: "カテゴリ作成権限がありません") }
            static func noCategoryCreateAccess(language: MistiaAppLanguage) -> String { L10n.tr("management.management.noCategoryCreateAccess", vi: "Chưa có quyền thêm mới danh mục", en: "No category create access", ja: "カテゴリ作成権限がありません", language: language) }
            static var noCategoryEditAccess: String { L10n.tr("management.management.noCategoryEditAccess", vi: "Chưa có quyền chỉnh sửa danh mục", en: "No category edit access", ja: "カテゴリ編集権限がありません") }
            static func noCategoryEditAccess(language: MistiaAppLanguage) -> String { L10n.tr("management.management.noCategoryEditAccess", vi: "Chưa có quyền chỉnh sửa danh mục", en: "No category edit access", ja: "カテゴリ編集権限がありません", language: language) }
            static var noCreateAccess: String { L10n.tr("management.management.noCreateAccess", vi: "Chưa có quyền thêm mới", en: "No create access", ja: "作成権限がありません") }
            static func noCreateAccess(language: MistiaAppLanguage) -> String { L10n.tr("management.management.noCreateAccess", vi: "Chưa có quyền thêm mới", en: "No create access", ja: "作成権限がありません", language: language) }
            static var noExpenseCategoriesYet: String { L10n.tr("management.management.noExpenseCategoriesYet", vi: "Chưa có danh mục chi tiêu", en: "No expense categories yet", ja: "支出カテゴリはまだありません") }
            static func noExpenseCategoriesYet(language: MistiaAppLanguage) -> String { L10n.tr("management.management.noExpenseCategoriesYet", vi: "Chưa có danh mục chi tiêu", en: "No expense categories yet", ja: "支出カテゴリはまだありません", language: language) }
            static var noIncomeCategoriesYet: String { L10n.tr("management.management.noIncomeCategoriesYet", vi: "Chưa có danh mục thu nhập", en: "No income categories yet", ja: "収入カテゴリはまだありません") }
            static func noIncomeCategoriesYet(language: MistiaAppLanguage) -> String { L10n.tr("management.management.noIncomeCategoriesYet", vi: "Chưa có danh mục thu nhập", en: "No income categories yet", ja: "収入カテゴリはまだありません", language: language) }
            static var noWalletAccess: String { L10n.tr("management.management.noWalletAccess", vi: "Chưa có quyền thao tác ví", en: "No wallet access", ja: "ウォレット権限がありません") }
            static func noWalletAccess(language: MistiaAppLanguage) -> String { L10n.tr("management.management.noWalletAccess", vi: "Chưa có quyền thao tác ví", en: "No wallet access", ja: "ウォレット権限がありません", language: language) }
            static var noWalletsYet: String { L10n.tr("management.management.noWalletsYet", vi: "Chưa có ví nào", en: "No wallets yet", ja: "ウォレットはまだありません") }
            static func noWalletsYet(language: MistiaAppLanguage) -> String { L10n.tr("management.management.noWalletsYet", vi: "Chưa có ví nào", en: "No wallets yet", ja: "ウォレットはまだありません", language: language) }
            static var none: String { L10n.tr("management.management.none", vi: "Chưa có", en: "None", ja: "未設定") }
            static func none(language: MistiaAppLanguage) -> String { L10n.tr("management.management.none", vi: "Chưa có", en: "None", ja: "未設定", language: language) }
            static var notSelected: String { L10n.tr("management.management.notSelected", vi: "Chưa chọn", en: "Not selected", ja: "未選択") }
            static func notSelected(language: MistiaAppLanguage) -> String { L10n.tr("management.management.notSelected", vi: "Chưa chọn", en: "Not selected", ja: "未選択", language: language) }
            static var notes: String { L10n.tr("management.management.notes", vi: "Ghi chú", en: "Notes", ja: "メモ") }
            static func notes(language: MistiaAppLanguage) -> String { L10n.tr("management.management.notes", vi: "Ghi chú", en: "Notes", ja: "メモ", language: language) }
            static var notice: String { L10n.tr("management.management.notice", vi: "Lưu ý", en: "Notice", ja: "ご注意") }
            static func notice(language: MistiaAppLanguage) -> String { L10n.tr("management.management.notice", vi: "Lưu ý", en: "Notice", ja: "ご注意", language: language) }
            static var orEnterTheBankName: String { L10n.tr("management.management.orEnterTheBankName", vi: "Hoặc nhập tên ngân hàng", en: "Or enter the bank name", ja: "または銀行名を入力") }
            static func orEnterTheBankName(language: MistiaAppLanguage) -> String { L10n.tr("management.management.orEnterTheBankName", vi: "Hoặc nhập tên ngân hàng", en: "Or enter the bank name", ja: "または銀行名を入力", language: language) }
            static var parentCategory: String { L10n.tr("management.management.parentCategory", vi: "Danh mục cha", en: "Parent category", ja: "親カテゴリ") }
            static func parentCategory(language: MistiaAppLanguage) -> String { L10n.tr("management.management.parentCategory", vi: "Danh mục cha", en: "Parent category", ja: "親カテゴリ", language: language) }
            static var paymentDay: String { L10n.tr("management.management.paymentDay", vi: "Ngày thanh toán", en: "Payment day", ja: "支払い期限") }
            static func paymentDay(language: MistiaAppLanguage) -> String { L10n.tr("management.management.paymentDay", vi: "Ngày thanh toán", en: "Payment day", ja: "支払い期限", language: language) }
            static var paymentSource: String { L10n.tr("management.management.paymentSource", vi: "Nguồn thanh toán", en: "Payment source", ja: "支払い元") }
            static func paymentSource(language: MistiaAppLanguage) -> String { L10n.tr("management.management.paymentSource", vi: "Nguồn thanh toán", en: "Payment source", ja: "支払い元", language: language) }
            static var popularBanksInJapan: String { L10n.tr("management.management.popularBanksInJapan", vi: "Ngân hàng phổ biến tại Nhật", en: "Popular banks in Japan", ja: "日本でよく使われる銀行") }
            static func popularBanksInJapan(language: MistiaAppLanguage) -> String { L10n.tr("management.management.popularBanksInJapan", vi: "Ngân hàng phổ biến tại Nhật", en: "Popular banks in Japan", ja: "日本でよく使われる銀行", language: language) }
            static var removeFavorite: String { L10n.tr("management.management.removeFavorite", vi: "Bỏ yêu thích", en: "Remove favorite", ja: "お気に入り解除") }
            static func removeFavorite(language: MistiaAppLanguage) -> String { L10n.tr("management.management.removeFavorite", vi: "Bỏ yêu thích", en: "Remove favorite", ja: "お気に入り解除", language: language) }
            static var requestAccess: String { L10n.tr("management.management.requestAccess", vi: "Yêu cầu quyền", en: "Request access", ja: "権限をリクエスト") }
            static func requestAccess(language: MistiaAppLanguage) -> String { L10n.tr("management.management.requestAccess", vi: "Yêu cầu quyền", en: "Request access", ja: "権限をリクエスト", language: language) }
            static var requestApproved: String { L10n.tr("management.management.requestApproved", vi: "Đã chấp nhận yêu cầu", en: "Request approved", ja: "リクエストが承認済み") }
            static func requestApproved(language: MistiaAppLanguage) -> String { L10n.tr("management.management.requestApproved", vi: "Đã chấp nhận yêu cầu", en: "Request approved", ja: "リクエストが承認済み", language: language) }
            static var requestCategoryCreation: String { L10n.tr("management.management.requestCategoryCreation", vi: "Yêu cầu thêm mới danh mục", en: "Request category creation", ja: "カテゴリ作成をリクエスト") }
            static func requestCategoryCreation(language: MistiaAppLanguage) -> String { L10n.tr("management.management.requestCategoryCreation", vi: "Yêu cầu thêm mới danh mục", en: "Request category creation", ja: "カテゴリ作成をリクエスト", language: language) }
            static var requestCreate: String { L10n.tr("management.management.requestCreate", vi: "Yêu cầu thêm mới", en: "Request create", ja: "作成をリクエスト") }
            static func requestCreate(language: MistiaAppLanguage) -> String { L10n.tr("management.management.requestCreate", vi: "Yêu cầu thêm mới", en: "Request create", ja: "作成をリクエスト", language: language) }
            static var requestEdit: String { L10n.tr("management.management.requestEdit", vi: "Yêu cầu chỉnh sửa", en: "Request edit", ja: "編集をリクエスト") }
            static func requestEdit(language: MistiaAppLanguage) -> String { L10n.tr("management.management.requestEdit", vi: "Yêu cầu chỉnh sửa", en: "Request edit", ja: "編集をリクエスト", language: language) }
            static var requestEditAccess: String { L10n.tr("management.management.requestEditAccess", vi: "Yêu cầu quyền chỉnh sửa", en: "Request edit access", ja: "編集権限をリクエスト") }
            static func requestEditAccess(language: MistiaAppLanguage) -> String { L10n.tr("management.management.requestEditAccess", vi: "Yêu cầu quyền chỉnh sửa", en: "Request edit access", ja: "編集権限をリクエスト", language: language) }
            static var requestSent: String { L10n.tr("management.management.requestSent", vi: "Đã gửi yêu cầu", en: "Request sent", ja: "リクエストを送信しました") }
            static func requestSent(language: MistiaAppLanguage) -> String { L10n.tr("management.management.requestSent", vi: "Đã gửi yêu cầu", en: "Request sent", ja: "リクエストを送信しました", language: language) }
            static var requestSent2: String { L10n.tr("management.management.requestSent2", vi: "Đã gửi yêu cầu", en: "Request sent", ja: "リクエスト送信済み") }
            static func requestSent2(language: MistiaAppLanguage) -> String { L10n.tr("management.management.requestSent2", vi: "Đã gửi yêu cầu", en: "Request sent", ja: "リクエスト送信済み", language: language) }
            static var requestUse: String { L10n.tr("management.management.requestUse", vi: "Yêu cầu sử dụng", en: "Request use", ja: "使用をリクエスト") }
            static func requestUse(language: MistiaAppLanguage) -> String { L10n.tr("management.management.requestUse", vi: "Yêu cầu sử dụng", en: "Request use", ja: "使用をリクエスト", language: language) }
            static var requestWalletCardCreation: String { L10n.tr("management.management.requestWalletCardCreation", vi: "Yêu cầu thêm mới ví / thẻ", en: "Request wallet / card creation", ja: "ウォレット・カード作成をリクエスト") }
            static func requestWalletCardCreation(language: MistiaAppLanguage) -> String { L10n.tr("management.management.requestWalletCardCreation", vi: "Yêu cầu thêm mới ví / thẻ", en: "Request wallet / card creation", ja: "ウォレット・カード作成をリクエスト", language: language) }
            static var searchBanks: String { L10n.tr("management.management.searchBanks", vi: "Tìm ngân hàng", en: "Search banks", ja: "銀行を検索") }
            static func searchBanks(language: MistiaAppLanguage) -> String { L10n.tr("management.management.searchBanks", vi: "Tìm ngân hàng", en: "Search banks", ja: "銀行を検索", language: language) }
            static var separateYourIncomeSourcesToClearlyTrack: String { L10n.tr("management.management.separateYourIncomeSourcesToClearlyTrack", vi: "Tách riêng nguồn thu để nhìn rõ tiền lương, thưởng, freelance hay hoàn tiền.", en: "Separate your income sources to clearly track salary, bonuses, freelance work, or refunds.", ja: "収入源を分けておくと、給与、賞与、副業、返金などを分かりやすく把握できます。") }
            static func separateYourIncomeSourcesToClearlyTrack(language: MistiaAppLanguage) -> String { L10n.tr("management.management.separateYourIncomeSourcesToClearlyTrack", vi: "Tách riêng nguồn thu để nhìn rõ tiền lương, thưởng, freelance hay hoàn tiền.", en: "Separate your income sources to clearly track salary, bonuses, freelance work, or refunds.", ja: "収入源を分けておくと、給与、賞与、副業、返金などを分かりやすく把握できます。", language: language) }
            static var signInOrCreateAnAccount: String { L10n.tr("management.management.signInOrCreateAnAccount", vi: "Đăng nhập hoặc tạo tài khoản", en: "Sign in or create an account", ja: "ログインまたはアカウント作成") }
            static func signInOrCreateAnAccount(language: MistiaAppLanguage) -> String { L10n.tr("management.management.signInOrCreateAnAccount", vi: "Đăng nhập hoặc tạo tài khoản", en: "Sign in or create an account", ja: "ログインまたはアカウント作成", language: language) }
            static var signInToSyncYourData: String { L10n.tr("management.management.signInToSyncYourData", vi: "Đăng nhập để đồng bộ dữ liệu", en: "Sign in to sync your data", ja: "ログインしてデータを同期") }
            static func signInToSyncYourData(language: MistiaAppLanguage) -> String { L10n.tr("management.management.signInToSyncYourData", vi: "Đăng nhập để đồng bộ dữ liệu", en: "Sign in to sync your data", ja: "ログインしてデータを同期", language: language) }
            static var statementClosingDay: String { L10n.tr("management.management.statementClosingDay", vi: "Ngày chốt sao kê", en: "Statement closing day", ja: "締め日") }
            static func statementClosingDay(language: MistiaAppLanguage) -> String { L10n.tr("management.management.statementClosingDay", vi: "Ngày chốt sao kê", en: "Statement closing day", ja: "締め日", language: language) }
            static var statementClosingDayMustBeEarlierThan: String { L10n.tr("management.management.statementClosingDayMustBeEarlierThan", vi: "Ngày chốt sao kê phải trước ngày thanh toán.", en: "Statement closing day must be earlier than the payment day.", ja: "締め日は支払日より前である必要があります。") }
            static func statementClosingDayMustBeEarlierThan(language: MistiaAppLanguage) -> String { L10n.tr("management.management.statementClosingDayMustBeEarlierThan", vi: "Ngày chốt sao kê phải trước ngày thanh toán.", en: "Statement closing day must be earlier than the payment day.", ja: "締め日は支払日より前である必要があります。", language: language) }
            static var structure: String { L10n.tr("management.management.structure", vi: "Cấu trúc", en: "Structure", ja: "構造") }
            static func structure(language: MistiaAppLanguage) -> String { L10n.tr("management.management.structure", vi: "Cấu trúc", en: "Structure", ja: "構造", language: language) }
            static var tapToChangeTheWalletIcon: String { L10n.tr("management.management.tapToChangeTheWalletIcon", vi: "Chạm để đổi icon ví", en: "Tap to change the wallet icon", ja: "ウォレットアイコンを変更") }
            static func tapToChangeTheWalletIcon(language: MistiaAppLanguage) -> String { L10n.tr("management.management.tapToChangeTheWalletIcon", vi: "Chạm để đổi icon ví", en: "Tap to change the wallet icon", ja: "ウォレットアイコンを変更", language: language) }
            static var thePermissionRequestWasSentToThe: String { L10n.tr("management.management.thePermissionRequestWasSentToThe", vi: "Yêu cầu quyền đã được gửi tới chủ dữ liệu.", en: "The permission request was sent to the data owner.", ja: "権限リクエストをデータ所有者へ送信しました。") }
            static func thePermissionRequestWasSentToThe(language: MistiaAppLanguage) -> String { L10n.tr("management.management.thePermissionRequestWasSentToThe", vi: "Yêu cầu quyền đã được gửi tới chủ dữ liệu.", en: "The permission request was sent to the data owner.", ja: "権限リクエストをデータ所有者へ送信しました。", language: language) }
            static var theRequestIsWaitingForTheData: String { L10n.tr("management.management.theRequestIsWaitingForTheData", vi: "Yêu cầu đang chờ chủ dữ liệu phản hồi.", en: "The request is waiting for the data owner.", ja: "リクエストはデータ所有者の返答待ちです。") }
            static func theRequestIsWaitingForTheData(language: MistiaAppLanguage) -> String { L10n.tr("management.management.theRequestIsWaitingForTheData", vi: "Yêu cầu đang chờ chủ dữ liệu phản hồi.", en: "The request is waiting for the data owner.", ja: "リクエストはデータ所有者の返答待ちです。", language: language) }
            static var thereAreNoChildCategoriesInThis: String { L10n.tr("management.management.thereAreNoChildCategoriesInThis", vi: "Chưa có danh mục con nào trong nhánh này.", en: "There are no child categories in this branch yet.", ja: "この枝にはまだ子カテゴリがありません。") }
            static func thereAreNoChildCategoriesInThis(language: MistiaAppLanguage) -> String { L10n.tr("management.management.thereAreNoChildCategoriesInThis", vi: "Chưa có danh mục con nào trong nhánh này.", en: "There are no child categories in this branch yet.", ja: "この枝にはまだ子カテゴリがありません。", language: language) }
            static var thisAdjustmentCannotBeUndoneAreYou: String { L10n.tr("management.management.thisAdjustmentCannotBeUndoneAreYou", vi: "Hành động điều chỉnh này sẽ không thể hoàn tác. Bạn có chắc chắn muốn tiếp tục?", en: "This adjustment cannot be undone. Are you sure you want to proceed?", ja: "この調整は取り消すことができません。続行してもよろしいですか？") }
            static func thisAdjustmentCannotBeUndoneAreYou(language: MistiaAppLanguage) -> String { L10n.tr("management.management.thisAdjustmentCannotBeUndoneAreYou", vi: "Hành động điều chỉnh này sẽ không thể hoàn tác. Bạn có chắc chắn muốn tiếp tục?", en: "This adjustment cannot be undone. Are you sure you want to proceed?", ja: "この調整は取り消すことができません。続行してもよろしいですか？", language: language) }
            static var thisCategoryWillBeArchivedArchivedCategories: String { L10n.tr("management.management.thisCategoryWillBeArchivedArchivedCategories", vi: "Danh mục này sẽ bị lưu trữ. Các danh mục đã lưu trữ sẽ nằm trong \"Mục đã lưu trữ\" và được giữ lại trong 30 ngày.", en: "This category will be archived. Archived categories will remain in \"Archived items\" for 30 days.", ja: "このカテゴリはアーカイブされます。アーカイブされたカテゴリは「アーカイブ済みアイテム」に30日間保持されます。") }
            static func thisCategoryWillBeArchivedArchivedCategories(language: MistiaAppLanguage) -> String { L10n.tr("management.management.thisCategoryWillBeArchivedArchivedCategories", vi: "Danh mục này sẽ bị lưu trữ. Các danh mục đã lưu trữ sẽ nằm trong \"Mục đã lưu trữ\" và được giữ lại trong 30 ngày.", en: "This category will be archived. Archived categories will remain in \"Archived items\" for 30 days.", ja: "このカテゴリはアーカイブされます。アーカイブされたカテゴリは「アーカイブ済みアイテム」に30日間保持されます。", language: language) }
            static var thisCreditCardHasOutstandingDebtChanging: String { L10n.tr("management.management.thisCreditCardHasOutstandingDebtChanging", vi: "Thẻ tín dụng này đang có dư nợ chưa thanh toán. Thay đổi ví nguồn thanh toán có thể ảnh hưởng đến việc theo dõi sao kê. Bạn có chắc muốn tiếp tục?", en: "This credit card has outstanding debt. Changing the payment source wallet may affect statement tracking. Are you sure you want to continue?", ja: "このクレジットカードには未払いの債務があります。支払い元ウォレットを変更すると明細の追跡に影響する可能性があります。続行してもよろしいですか？") }
            static func thisCreditCardHasOutstandingDebtChanging(language: MistiaAppLanguage) -> String { L10n.tr("management.management.thisCreditCardHasOutstandingDebtChanging", vi: "Thẻ tín dụng này đang có dư nợ chưa thanh toán. Thay đổi ví nguồn thanh toán có thể ảnh hưởng đến việc theo dõi sao kê. Bạn có chắc muốn tiếp tục?", en: "This credit card has outstanding debt. Changing the payment source wallet may affect statement tracking. Are you sure you want to continue?", ja: "このクレジットカードには未払いの債務があります。支払い元ウォレットを変更すると明細の追跡に影響する可能性があります。続行してもよろしいですか？", language: language) }
            static var thisWalletWillBeArchivedArchivedWallets: String { L10n.tr("management.management.thisWalletWillBeArchivedArchivedWallets", vi: "Ví này sẽ bị lưu trữ. Các ví đã lưu trữ sẽ nằm trong \"Mục đã lưu trữ\" và được giữ lại trong 30 ngày.", en: "This wallet will be archived. Archived wallets will remain in \"Archived items\" for 30 days.", ja: "このウォレットはアーカイブされます。アーカイブされたウォレットは「アーカイブ済みアイテム」に30日間保持されます。") }
            static func thisWalletWillBeArchivedArchivedWallets(language: MistiaAppLanguage) -> String { L10n.tr("management.management.thisWalletWillBeArchivedArchivedWallets", vi: "Ví này sẽ bị lưu trữ. Các ví đã lưu trữ sẽ nằm trong \"Mục đã lưu trữ\" và được giữ lại trong 30 ngày.", en: "This wallet will be archived. Archived wallets will remain in \"Archived items\" for 30 days.", ja: "このウォレットはアーカイブされます。アーカイブされたウォレットは「アーカイブ済みアイテム」に30日間保持されます。", language: language) }
            static var useRequestApproved: String { L10n.tr("management.management.useRequestApproved", vi: "Đã chấp nhận yêu cầu sử dụng", en: "Use request approved", ja: "使用リクエストが承認済み") }
            static func useRequestApproved(language: MistiaAppLanguage) -> String { L10n.tr("management.management.useRequestApproved", vi: "Đã chấp nhận yêu cầu sử dụng", en: "Use request approved", ja: "使用リクエストが承認済み", language: language) }
            static var useRequested: String { L10n.tr("management.management.useRequested", vi: "Đã yêu cầu sử dụng", en: "Use requested", ja: "使用権限をリクエスト済み") }
            static func useRequested(language: MistiaAppLanguage) -> String { L10n.tr("management.management.useRequested", vi: "Đã yêu cầu sử dụng", en: "Use requested", ja: "使用権限をリクエスト済み", language: language) }
            static var useThisName: String { L10n.tr("management.management.useThisName", vi: "Dùng tên này", en: "Use this name", ja: "この名前を使う") }
            static func useThisName(language: MistiaAppLanguage) -> String { L10n.tr("management.management.useThisName", vi: "Dùng tên này", en: "Use this name", ja: "この名前を使う", language: language) }
            static func valueChildCategories(_ value: String) -> String {
                L10n.format("management.management.valueChildCategories", vi: "%@ danh mục con", en: "%@ child categories", ja: "子カテゴリ %@ 件", value)
            }
            static func valueChildCategories(_ value: String, language: MistiaAppLanguage) -> String {
                L10n.format("management.management.valueChildCategories", vi: "%@ danh mục con", en: "%@ child categories", ja: "子カテゴリ %@ 件", language: language, value)
            }
            static var walletName: String { L10n.tr("management.management.walletName", vi: "Tên ví", en: "Wallet name", ja: "ウォレット名") }
            static func walletName(language: MistiaAppLanguage) -> String { L10n.tr("management.management.walletName", vi: "Tên ví", en: "Wallet name", ja: "ウォレット名", language: language) }
            static var walletType: String { L10n.tr("management.management.walletType", vi: "Loại ví", en: "Wallet type", ja: "ウォレット種別") }
            static func walletType(language: MistiaAppLanguage) -> String { L10n.tr("management.management.walletType", vi: "Loại ví", en: "Wallet type", ja: "ウォレット種別", language: language) }
            static var wallets: String { L10n.tr("management.management.wallets", vi: "Ví", en: "Wallets", ja: "ウォレット") }
            static func wallets(language: MistiaAppLanguage) -> String { L10n.tr("management.management.wallets", vi: "Ví", en: "Wallets", ja: "ウォレット", language: language) }
            static var walletsCards: String { L10n.tr("management.management.walletsCards", vi: "ví / thẻ", en: "wallets / cards", ja: "ウォレット・カード") }
            static func walletsCards(language: MistiaAppLanguage) -> String { L10n.tr("management.management.walletsCards", vi: "ví / thẻ", en: "wallets / cards", ja: "ウォレット・カード", language: language) }
            static func youDoNotHaveEnoughAccessFor(_ value: String) -> String {
                L10n.format("management.management.youDoNotHaveEnoughAccessFor", vi: "Bạn chưa có đủ quyền với %@.", en: "You do not have enough access for %@.", ja: "%@ の権限が不足しています。", value)
            }
            static func youDoNotHaveEnoughAccessFor(_ value: String, language: MistiaAppLanguage) -> String {
                L10n.format("management.management.youDoNotHaveEnoughAccessFor", vi: "Bạn chưa có đủ quyền với %@.", en: "You do not have enough access for %@.", ja: "%@ の権限が不足しています。", language: language, value)
            }
            static var youDoNotHavePermissionToCreate: String { L10n.tr("management.management.youDoNotHavePermissionToCreate", vi: "Bạn chưa có quyền thêm mới danh mục cho thành viên này.", en: "You do not have permission to create categories for this member.", ja: "このメンバーのカテゴリを作成する権限がありません。") }
            static func youDoNotHavePermissionToCreate(language: MistiaAppLanguage) -> String { L10n.tr("management.management.youDoNotHavePermissionToCreate", vi: "Bạn chưa có quyền thêm mới danh mục cho thành viên này.", en: "You do not have permission to create categories for this member.", ja: "このメンバーのカテゴリを作成する権限がありません。", language: language) }
            static func youDoNotHavePermissionToCreate2(_ value: String) -> String {
                L10n.format("management.management.youDoNotHavePermissionToCreate2", vi: "Bạn chưa có quyền thêm mới %@ cho thành viên này.", en: "You do not have permission to create %@ for this member.", ja: "このメンバーの%@を作成する権限がありません。", value)
            }
            static func youDoNotHavePermissionToCreate2(_ value: String, language: MistiaAppLanguage) -> String {
                L10n.format("management.management.youDoNotHavePermissionToCreate2", vi: "Bạn chưa có quyền thêm mới %@ cho thành viên này.", en: "You do not have permission to create %@ for this member.", ja: "このメンバーの%@を作成する権限がありません。", language: language, value)
            }
            static var youDoNotHavePermissionToEdit: String { L10n.tr("management.management.youDoNotHavePermissionToEdit", vi: "Bạn chưa có quyền chỉnh sửa danh mục của thành viên này.", en: "You do not have permission to edit this member's categories.", ja: "このメンバーのカテゴリを編集する権限がありません。") }
            static func youDoNotHavePermissionToEdit(language: MistiaAppLanguage) -> String { L10n.tr("management.management.youDoNotHavePermissionToEdit", vi: "Bạn chưa có quyền chỉnh sửa danh mục của thành viên này.", en: "You do not have permission to edit this member's categories.", ja: "このメンバーのカテゴリを編集する権限がありません。", language: language) }
            static var yourWalletsCategoriesAndTransactionsAreReady: String { L10n.tr("management.management.yourWalletsCategoriesAndTransactionsAreReady", vi: "Sẵn sàng sao lưu, khôi phục và đồng bộ dữ liệu ví, danh mục và thu chi của bạn trên mọi thiết bị.", en: "Ready to backup, restore, and sync your wallets, categories, and cashflow items across all your devices.", ja: "ウォレット、カテゴリ、取引データのバックアップ、復元、全端末間での同期が可能です。") }
            static func yourWalletsCategoriesAndTransactionsAreReady(language: MistiaAppLanguage) -> String { L10n.tr("management.management.yourWalletsCategoriesAndTransactionsAreReady", vi: "Sẵn sàng sao lưu, khôi phục và đồng bộ dữ liệu ví, danh mục và thu chi của bạn trên mọi thiết bị.", en: "Ready to backup, restore, and sync your wallets, categories, and cashflow items across all your devices.", ja: "ウォレット、カテゴリ、取引データのバックアップ、復元、全端末間での同期が可能です。", language: language) }
        }

        nonisolated enum managementarchiveditems {
            static var archivedItems: String { L10n.tr("management.managementarchiveditems.archivedItems", vi: "Mục đã lưu trữ", en: "Archived items", ja: "アーカイブ済みアイテム") }
            static func archivedItems(language: MistiaAppLanguage) -> String { L10n.tr("management.managementarchiveditems.archivedItems", vi: "Mục đã lưu trữ", en: "Archived items", ja: "アーカイブ済みアイテム", language: language) }
            static var cannotRestore: String { L10n.tr("management.managementarchiveditems.cannotRestore", vi: "Chưa thể khôi phục", en: "Cannot restore", ja: "復元できません") }
            static func cannotRestore(language: MistiaAppLanguage) -> String { L10n.tr("management.managementarchiveditems.cannotRestore", vi: "Chưa thể khôi phục", en: "Cannot restore", ja: "復元できません", language: language) }
            static var categories: String { L10n.tr("management.managementarchiveditems.categories", vi: "Danh mục", en: "Categories", ja: "カテゴリ") }
            static func categories(language: MistiaAppLanguage) -> String { L10n.tr("management.managementarchiveditems.categories", vi: "Danh mục", en: "Categories", ja: "カテゴリ", language: language) }
            static func categoryDeleteBlockedWithCounts(_ arg1: String, _ arg2: String, _ arg3: String, _ arg4: String) -> String {
                L10n.format("management.managementarchiveditems.categoryDeleteBlockedWithCounts", vi: "Chưa thể xóa hẳn danh mục này. Còn %@ giao dịch, %@ hóa đơn, %@ ngân sách tháng hiện tại và %@ danh mục con đang tham chiếu.", en: "Can't permanently delete this category yet. It is still referenced by %@ transactions, %@ bills, %@ current-month budgets, and %@ child categories.", ja: "このカテゴリはまだ完全に削除できません。取引 %@ 件、請求 %@ 件、当月予算 %@ 件、子カテゴリ %@ 件が参照しています。", arg1, arg2, arg3, arg4)
            }
            static func categoryDeleteBlockedWithCounts(_ arg1: String, _ arg2: String, _ arg3: String, _ arg4: String, language: MistiaAppLanguage) -> String {
                L10n.format("management.managementarchiveditems.categoryDeleteBlockedWithCounts", vi: "Chưa thể xóa hẳn danh mục này. Còn %@ giao dịch, %@ hóa đơn, %@ ngân sách tháng hiện tại và %@ danh mục con đang tham chiếu.", en: "Can't permanently delete this category yet. It is still referenced by %@ transactions, %@ bills, %@ current-month budgets, and %@ child categories.", ja: "このカテゴリはまだ完全に削除できません。取引 %@ 件、請求 %@ 件、当月予算 %@ 件、子カテゴリ %@ 件が参照しています。", language: language, arg1, arg2, arg3, arg4)
            }
            static var debt: String { L10n.tr("management.managementarchiveditems.debt", vi: "Vay & cho vay", en: "Loans", ja: "貸し借り") }
            static func debt(language: MistiaAppLanguage) -> String { L10n.tr("management.managementarchiveditems.debt", vi: "Vay & cho vay", en: "Loans", ja: "貸し借り", language: language) }
            static var debtTransaction: String { L10n.tr("management.managementarchiveditems.debtTransaction", vi: "Vay & cho vay", en: "Loans", ja: "貸し借り取引") }
            static func debtTransaction(language: MistiaAppLanguage) -> String { L10n.tr("management.managementarchiveditems.debtTransaction", vi: "Vay & cho vay", en: "Loans", ja: "貸し借り取引", language: language) }
            static var deletePermanently: String { L10n.tr("management.managementarchiveditems.deletePermanently", vi: "Xóa vĩnh viễn", en: "Delete permanently", ja: "完全に削除") }
            static func deletePermanently(language: MistiaAppLanguage) -> String { L10n.tr("management.managementarchiveditems.deletePermanently", vi: "Xóa vĩnh viễn", en: "Delete permanently", ja: "完全に削除", language: language) }
            static var destination: String { L10n.tr("management.managementarchiveditems.destination", vi: "Đích", en: "Destination", ja: "入金先") }
            static func destination(language: MistiaAppLanguage) -> String { L10n.tr("management.managementarchiveditems.destination", vi: "Đích", en: "Destination", ja: "入金先", language: language) }
            static var events: String { L10n.tr("management.managementarchiveditems.events", vi: "Sự kiện", en: "Events", ja: "イベント") }
            static func events(language: MistiaAppLanguage) -> String { L10n.tr("management.managementarchiveditems.events", vi: "Sự kiện", en: "Events", ja: "イベント", language: language) }
            static var expense: String { L10n.tr("management.managementarchiveditems.expense", vi: "Chi tiêu", en: "Expense", ja: "支出") }
            static func expense(language: MistiaAppLanguage) -> String { L10n.tr("management.managementarchiveditems.expense", vi: "Chi tiêu", en: "Expense", ja: "支出", language: language) }
            static var income: String { L10n.tr("management.managementarchiveditems.income", vi: "Thu nhập", en: "Income", ja: "収入") }
            static func income(language: MistiaAppLanguage) -> String { L10n.tr("management.managementarchiveditems.income", vi: "Thu nhập", en: "Income", ja: "収入", language: language) }
            static var internalTransfer: String { L10n.tr("management.managementarchiveditems.internalTransfer", vi: "Chuyển tiền nội bộ", en: "Internal transfer", ja: "内部振替") }
            static func internalTransfer(language: MistiaAppLanguage) -> String { L10n.tr("management.managementarchiveditems.internalTransfer", vi: "Chuyển tiền nội bộ", en: "Internal transfer", ja: "内部振替", language: language) }
            static func monthValueAlreadyHasACardPayment(_ value: String) -> String {
                L10n.format("management.managementarchiveditems.monthValueAlreadyHasACardPayment", vi: "Tháng %@ đã có khoản thanh toán thẻ. Mỗi tháng chỉ được thanh toán một lần.", en: "Month %@ already has a card payment. Only one payment is allowed per month.", ja: "%@ は既にカード支払いがあります。毎月1回のみ支払いが可能です。", value)
            }
            static func monthValueAlreadyHasACardPayment(_ value: String, language: MistiaAppLanguage) -> String {
                L10n.format("management.managementarchiveditems.monthValueAlreadyHasACardPayment", vi: "Tháng %@ đã có khoản thanh toán thẻ. Mỗi tháng chỉ được thanh toán một lần.", en: "Month %@ already has a card payment. Only one payment is allowed per month.", ja: "%@ は既にカード支払いがあります。毎月1回のみ支払いが可能です。", language: language, value)
            }
            static var noArchivedItems: String { L10n.tr("management.managementarchiveditems.noArchivedItems", vi: "Không có mục lưu trữ", en: "No archived items", ja: "アーカイブなし") }
            static func noArchivedItems(language: MistiaAppLanguage) -> String { L10n.tr("management.managementarchiveditems.noArchivedItems", vi: "Không có mục lưu trữ", en: "No archived items", ja: "アーカイブなし", language: language) }
            static var noCategorySelected: String { L10n.tr("management.managementarchiveditems.noCategorySelected", vi: "Chưa chọn danh mục", en: "No category selected", ja: "カテゴリ未選択") }
            static func noCategorySelected(language: MistiaAppLanguage) -> String { L10n.tr("management.managementarchiveditems.noCategorySelected", vi: "Chưa chọn danh mục", en: "No category selected", ja: "カテゴリ未選択", language: language) }
            static var noWalletSelected: String { L10n.tr("management.managementarchiveditems.noWalletSelected", vi: "Chưa chọn ví", en: "No wallet selected", ja: "ウォレット未選択") }
            static func noWalletSelected(language: MistiaAppLanguage) -> String { L10n.tr("management.managementarchiveditems.noWalletSelected", vi: "Chưa chọn ví", en: "No wallet selected", ja: "ウォレット未選択", language: language) }
            static var restore: String { L10n.tr("management.managementarchiveditems.restore", vi: "Khôi phục", en: "Restore", ja: "復元") }
            static func restore(language: MistiaAppLanguage) -> String { L10n.tr("management.managementarchiveditems.restore", vi: "Khôi phục", en: "Restore", ja: "復元", language: language) }
            static var selectItems: String { L10n.tr("management.managementarchiveditems.selectItems", vi: "Chọn mục", en: "Select items", ja: "項目を選択") }
            static func selectItems(language: MistiaAppLanguage) -> String { L10n.tr("management.managementarchiveditems.selectItems", vi: "Chọn mục", en: "Select items", ja: "項目を選択", language: language) }
            static var source: String { L10n.tr("management.managementarchiveditems.source", vi: "Nguồn", en: "Source", ja: "出金元") }
            static func source(language: MistiaAppLanguage) -> String { L10n.tr("management.managementarchiveditems.source", vi: "Nguồn", en: "Source", ja: "出金元", language: language) }
            static var theSelectedItemsWillBeRestoredTo: String { L10n.tr("management.managementarchiveditems.theSelectedItemsWillBeRestoredTo", vi: "Các mục đã chọn sẽ được khôi phục về trạng thái hoạt động.", en: "The selected items will be restored to their active state.", ja: "選択した項目を元の状態に復元します。") }
            static func theSelectedItemsWillBeRestoredTo(language: MistiaAppLanguage) -> String { L10n.tr("management.managementarchiveditems.theSelectedItemsWillBeRestoredTo", vi: "Các mục đã chọn sẽ được khôi phục về trạng thái hoạt động.", en: "The selected items will be restored to their active state.", ja: "選択した項目を元の状態に復元します。", language: language) }
            static var theseItemsWillBeRemovedFromThe: String { L10n.tr("management.managementarchiveditems.theseItemsWillBeRemovedFromThe", vi: "Các mục này sẽ bị xóa khỏi lưu trữ và không thể hoàn tác.", en: "These items will be removed from the archive and can't be undone.", ja: "これらの項目はアーカイブから削除され、元に戻せません。") }
            static func theseItemsWillBeRemovedFromThe(language: MistiaAppLanguage) -> String { L10n.tr("management.managementarchiveditems.theseItemsWillBeRemovedFromThe", vi: "Các mục này sẽ bị xóa khỏi lưu trữ và không thể hoàn tác.", en: "These items will be removed from the archive and can't be undone.", ja: "これらの項目はアーカイブから削除され、元に戻せません。", language: language) }
            static var transactions: String { L10n.tr("management.managementarchiveditems.transactions", vi: "Thu chi", en: "Cashflow", ja: "収支") }
            static func transactions(language: MistiaAppLanguage) -> String { L10n.tr("management.managementarchiveditems.transactions", vi: "Thu chi", en: "Cashflow", ja: "収支", language: language) }
            static var transfer: String { L10n.tr("management.managementarchiveditems.transfer", vi: "Chuyển tiền", en: "Transfer", ja: "振替") }
            static func transfer(language: MistiaAppLanguage) -> String { L10n.tr("management.managementarchiveditems.transfer", vi: "Chuyển tiền", en: "Transfer", ja: "振替", language: language) }
            static var unknownName: String { L10n.tr("management.managementarchiveditems.unknownName", vi: "Không rõ tên", en: "Unknown name", ja: "名前未設定") }
            static func unknownName(language: MistiaAppLanguage) -> String { L10n.tr("management.managementarchiveditems.unknownName", vi: "Không rõ tên", en: "Unknown name", ja: "名前未設定", language: language) }
            static func valueDaysUntilPermanentDelete(_ value: String) -> String {
                L10n.format("management.managementarchiveditems.valueDaysUntilPermanentDelete", vi: "Còn lại %@ ngày", en: "%@ days left", ja: "あと%@日", value)
            }
            static func valueDaysUntilPermanentDelete(_ value: String, language: MistiaAppLanguage) -> String {
                L10n.format("management.managementarchiveditems.valueDaysUntilPermanentDelete", vi: "Còn lại %@ ngày", en: "%@ days left", ja: "あと%@日", language: language, value)
            }
            static func valueSelected(_ value: String) -> String {
                L10n.format("management.managementarchiveditems.valueSelected", vi: "Đã chọn %@ mục", en: "%@ selected", ja: "%@件を選択", value)
            }
            static func valueSelected(_ value: String, language: MistiaAppLanguage) -> String {
                L10n.format("management.managementarchiveditems.valueSelected", vi: "Đã chọn %@ mục", en: "%@ selected", ja: "%@件を選択", language: language, value)
            }
            static var wallets: String { L10n.tr("management.managementarchiveditems.wallets", vi: "Ví", en: "Wallets", ja: "ウォレット") }
            static func wallets(language: MistiaAppLanguage) -> String { L10n.tr("management.managementarchiveditems.wallets", vi: "Ví", en: "Wallets", ja: "ウォレット", language: language) }
            static var youDonTHaveAnyArchivedItems: String { L10n.tr("management.managementarchiveditems.youDonTHaveAnyArchivedItems", vi: "Bạn chưa có mục nào được lưu trữ. Các mục được lưu trữ sẽ tự động xoá sau 30 ngày.", en: "You don't have any archived items yet. Archived items are automatically deleted after 30 days.", ja: "アーカイブされたアイテムはまだありません。アーカイブされたアイテムは30日後に自動的に削除されます。") }
            static func youDonTHaveAnyArchivedItems(language: MistiaAppLanguage) -> String { L10n.tr("management.managementarchiveditems.youDonTHaveAnyArchivedItems", vi: "Bạn chưa có mục nào được lưu trữ. Các mục được lưu trữ sẽ tự động xoá sau 30 ngày.", en: "You don't have any archived items yet. Archived items are automatically deleted after 30 days.", ja: "アーカイブされたアイテムはまだありません。アーカイブされたアイテムは30日後に自動的に削除されます。", language: language) }
        }

        nonisolated enum managementauth {
            static func aboutValueMinutesLeft(_ value: String) -> String {
                L10n.format("management.managementauth.aboutValueMinutesLeft", vi: "Còn khoảng %@ phút", en: "About %@ minutes left", ja: "残り約 %@ 分", value)
            }
            static func aboutValueMinutesLeft(_ value: String, language: MistiaAppLanguage) -> String {
                L10n.format("management.managementauth.aboutValueMinutesLeft", vi: "Còn khoảng %@ phút", en: "About %@ minutes left", ja: "残り約 %@ 分", language: language, value)
            }
            static func aboutValueSecondsLeft(_ value: String) -> String {
                L10n.format("management.managementauth.aboutValueSecondsLeft", vi: "Còn khoảng %@ giây", en: "About %@ seconds left", ja: "残り約 %@ 秒", value)
            }
            static func aboutValueSecondsLeft(_ value: String, language: MistiaAppLanguage) -> String {
                L10n.format("management.managementauth.aboutValueSecondsLeft", vi: "Còn khoảng %@ giây", en: "About %@ seconds left", ja: "残り約 %@ 秒", language: language, value)
            }
            static var add: String { L10n.tr("management.managementauth.add", vi: "Thêm", en: "Add", ja: "追加") }
            static func add(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.add", vi: "Thêm", en: "Add", ja: "追加", language: language) }
            static var alreadyHaveAnAccount: String { L10n.tr("management.managementauth.alreadyHaveAnAccount", vi: "Đã có tài khoản?", en: "Already have an account?", ja: "すでにアカウントをお持ちですか？") }
            static func alreadyHaveAnAccount(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.alreadyHaveAnAccount", vi: "Đã có tài khoản?", en: "Already have an account?", ja: "すでにアカウントをお持ちですか？", language: language) }
            static var applyNewestToAll: String { L10n.tr("management.managementauth.applyNewestToAll", vi: "Áp dụng bản mới nhất cho tất cả", en: "Apply newest to all", ja: "すべて最新データに合わせる") }
            static func applyNewestToAll(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.applyNewestToAll", vi: "Áp dụng bản mới nhất cho tất cả", en: "Apply newest to all", ja: "すべて最新データに合わせる", language: language) }
            static var atLeastCharacters: String { L10n.tr("management.managementauth.atLeastCharacters", vi: "Ít nhất 8 ký tự", en: "At least 8 characters", ja: "8 文字以上") }
            static func atLeastCharacters(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.atLeastCharacters", vi: "Ít nhất 8 ký tự", en: "At least 8 characters", ja: "8 文字以上", language: language) }
            static var atLeastLowercaseLetter: String { L10n.tr("management.managementauth.atLeastLowercaseLetter", vi: "Ít nhất 1 chữ viết thường", en: "At least 1 lowercase letter", ja: "小文字を 1 文字以上") }
            static func atLeastLowercaseLetter(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.atLeastLowercaseLetter", vi: "Ít nhất 1 chữ viết thường", en: "At least 1 lowercase letter", ja: "小文字を 1 文字以上", language: language) }
            static var atLeastUppercaseLetter: String { L10n.tr("management.managementauth.atLeastUppercaseLetter", vi: "Ít nhất 1 chữ viết hoa", en: "At least 1 uppercase letter", ja: "大文字を 1 文字以上") }
            static func atLeastUppercaseLetter(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.atLeastUppercaseLetter", vi: "Ít nhất 1 chữ viết hoa", en: "At least 1 uppercase letter", ja: "大文字を 1 文字以上", language: language) }
            static var attachToThisAccount: String { L10n.tr("management.managementauth.attachToThisAccount", vi: "Gắn vào tài khoản này", en: "Attach to this account", ja: "このアカウントに紐づける") }
            static func attachToThisAccount(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.attachToThisAccount", vi: "Gắn vào tài khoản này", en: "Attach to this account", ja: "このアカウントに紐づける", language: language) }
            static var auto: String { L10n.tr("management.managementauth.auto", vi: "Tự động", en: "Auto", ja: "自動") }
            static func auto(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.auto", vi: "Tự động", en: "Auto", ja: "自動", language: language) }
            static var autoSync: String { L10n.tr("management.managementauth.autoSync", vi: "Tự động đồng bộ", en: "Auto sync", ja: "自動同期") }
            static func autoSync(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.autoSync", vi: "Tự động đồng bộ", en: "Auto sync", ja: "自動同期", language: language) }
            static var autoSyncIsOffYourDataWill: String { L10n.tr("management.managementauth.autoSyncIsOffYourDataWill", vi: "Tự động đồng bộ đang tắt. Dữ liệu của bạn sẽ chỉ được cập nhật khi bạn nhấn nút 'Đồng bộ ngay' một cách thủ công. Bật tính năng này để đảm bảo dữ liệu luôn được cập nhật mới nhất trên mọi thiết bị.", en: "Auto sync is off. Your data will only update when you manually tap the 'Sync now' button. Enable this feature to keep your data up to date across all your devices automatically.", ja: "自動同期はオフです。データは「今すぐ同期」ボタンを手動で押したときにのみ更新されます。すべてのデバイスでデータを最新の状態に保つには、この機能を有効にしてください。") }
            static func autoSyncIsOffYourDataWill(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.autoSyncIsOffYourDataWill", vi: "Tự động đồng bộ đang tắt. Dữ liệu của bạn sẽ chỉ được cập nhật khi bạn nhấn nút 'Đồng bộ ngay' một cách thủ công. Bật tính năng này để đảm bảo dữ liệu luôn được cập nhật mới nhất trên mọi thiết bị.", en: "Auto sync is off. Your data will only update when you manually tap the 'Sync now' button. Enable this feature to keep your data up to date across all your devices automatically.", ja: "自動同期はオフです。データは「今すぐ同期」ボタンを手動で押したときにのみ更新されます。すべてのデバイスでデータを最新の状態に保つには、この機能を有効にしてください。", language: language) }
            static var autoSyncIsPausedAfterTheRestore: String { L10n.tr("management.managementauth.autoSyncIsPausedAfterTheRestore", vi: "Tự động sync đang tạm dừng sau khi khôi phục snapshot. Khi bạn đã kiểm tra dữ liệu ổn, hãy vào Đồng bộ dữ liệu và nhấn Đồng bộ ngay.", en: "Auto sync is paused after the restore. Once you've reviewed the data, open Sync settings and tap Sync now.", ja: "スナップショット復元後は自動同期を停止しています。データ確認後に同期設定へ移動して「今すぐ同期」を押してください。") }
            static func autoSyncIsPausedAfterTheRestore(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.autoSyncIsPausedAfterTheRestore", vi: "Tự động sync đang tạm dừng sau khi khôi phục snapshot. Khi bạn đã kiểm tra dữ liệu ổn, hãy vào Đồng bộ dữ liệu và nhấn Đồng bộ ngay.", en: "Auto sync is paused after the restore. Once you've reviewed the data, open Sync settings and tap Sync now.", ja: "スナップショット復元後は自動同期を停止しています。データ確認後に同期設定へ移動して「今すぐ同期」を押してください。", language: language) }
            static var backToSignIn: String { L10n.tr("management.managementauth.backToSignIn", vi: "Quay lại đăng nhập", en: "Back to sign in", ja: "ログインへ戻る") }
            static func backToSignIn(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.backToSignIn", vi: "Quay lại đăng nhập", en: "Back to sign in", ja: "ログインへ戻る", language: language) }
            static var backupRestore: String { L10n.tr("management.managementauth.backupRestore", vi: "Sao lưu & Khôi phục", en: "Backup & Restore", ja: "バックアップ & 復元") }
            static func backupRestore(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.backupRestore", vi: "Sao lưu & Khôi phục", en: "Backup & Restore", ja: "バックアップ & 復元", language: language) }
            static var birthday: String { L10n.tr("management.managementauth.birthday", vi: "Ngày sinh", en: "Birthday", ja: "生年月日") }
            static func birthday(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.birthday", vi: "Ngày sinh", en: "Birthday", ja: "生年月日", language: language) }
            static var budget: String { L10n.tr("management.managementauth.budget", vi: "Ngân sách", en: "Budget", ja: "予算") }
            static func budget(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.budget", vi: "Ngân sách", en: "Budget", ja: "予算", language: language) }
            static var byContinuingYouAgreeToOurTerms: String { L10n.tr("management.managementauth.byContinuingYouAgreeToOurTerms", vi: "Bằng việc tiếp tục, bạn đồng ý với Điều khoản Dịch vụ và Chính sách Bảo mật của chúng tôi.", en: "By continuing, you agree to our Terms of Service and Privacy Policy.", ja: "続行することで、利用規約とプライバシーポリシーに同意したことになります。") }
            static func byContinuingYouAgreeToOurTerms(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.byContinuingYouAgreeToOurTerms", vi: "Bằng việc tiếp tục, bạn đồng ý với Điều khoản Dịch vụ và Chính sách Bảo mật của chúng tôi.", en: "By continuing, you agree to our Terms of Service and Privacy Policy.", ja: "続行することで、利用規約とプライバシーポリシーに同意したことになります。", language: language) }
            static var canTContinueYet: String { L10n.tr("management.managementauth.canTContinueYet", vi: "Chưa thể tiếp tục", en: "Can't continue yet", ja: "まだ続行できません") }
            static func canTContinueYet(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.canTContinueYet", vi: "Chưa thể tiếp tục", en: "Can't continue yet", ja: "まだ続行できません", language: language) }
            static var changePhoto: String { L10n.tr("management.managementauth.changePhoto", vi: "Đổi ảnh", en: "Change Photo", ja: "写真を変更") }
            static func changePhoto(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.changePhoto", vi: "Đổi ảnh", en: "Change Photo", ja: "写真を変更", language: language) }
            static var changeProfilePhoto: String { L10n.tr("management.managementauth.changeProfilePhoto", vi: "Đổi ảnh đại diện", en: "Change profile photo", ja: "プロフィール写真を変更") }
            static func changeProfilePhoto(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.changeProfilePhoto", vi: "Đổi ảnh đại diện", en: "Change profile photo", ja: "プロフィール写真を変更", language: language) }
            static var chooseAMistiabackupFileToContinue: String { L10n.tr("management.managementauth.chooseAMistiabackupFileToContinue", vi: "Hãy chọn một file `.mistiabackup` để tiếp tục.", en: "Choose a `.mistiabackup` file to continue.", ja: "続行するには `.mistiabackup` ファイルを選択してください。") }
            static func chooseAMistiabackupFileToContinue(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.chooseAMistiabackupFileToContinue", vi: "Hãy chọn một file `.mistiabackup` để tiếp tục.", en: "Choose a `.mistiabackup` file to continue.", ja: "続行するには `.mistiabackup` ファイルを選択してください。", language: language) }
            static var chooseFromLibrary: String { L10n.tr("management.managementauth.chooseFromLibrary", vi: "Chọn từ thư viện", en: "Choose from Library", ja: "ライブラリから選択") }
            static func chooseFromLibrary(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.chooseFromLibrary", vi: "Chọn từ thư viện", en: "Choose from Library", ja: "ライブラリから選択", language: language) }
            static var cloud: String { L10n.tr("management.managementauth.cloud", vi: "Cloud", en: "Cloud", ja: "クラウド") }
            static func cloud(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.cloud", vi: "Cloud", en: "Cloud", ja: "クラウド", language: language) }
            static var cloudChangedRefreshAction: String { L10n.tr("management.managementauth.cloudChangedRefreshAction", vi: "Làm mới ngay", en: "Refresh now", ja: "今すぐ更新") }
            static func cloudChangedRefreshAction(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.cloudChangedRefreshAction", vi: "Làm mới ngay", en: "Refresh now", ja: "今すぐ更新", language: language) }
            static var cloudChangedRefreshMessage: String { L10n.tr("management.managementauth.cloudChangedRefreshMessage", vi: "Một số mục đã có bản mới hơn trên cloud, nên chỉ các chỉnh sửa đang chờ của những mục đó cần làm mới trước khi thử lại. Các thay đổi khác vẫn tiếp tục được đẩy bình thường.", en: "Some items already have a newer cloud version, so only those pending edits need a refresh before you try again. Other changes continue to upload normally.", ja: "一部の項目はクラウド側に新しい版があるため、その未送信の編集だけ更新してから再試行する必要があります。他の変更は通常どおりアップロードされます。") }
            static func cloudChangedRefreshMessage(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.cloudChangedRefreshMessage", vi: "Một số mục đã có bản mới hơn trên cloud, nên chỉ các chỉnh sửa đang chờ của những mục đó cần làm mới trước khi thử lại. Các thay đổi khác vẫn tiếp tục được đẩy bình thường.", en: "Some items already have a newer cloud version, so only those pending edits need a refresh before you try again. Other changes continue to upload normally.", ja: "一部の項目はクラウド側に新しい版があるため、その未送信の編集だけ更新してから再試行する必要があります。他の変更は通常どおりアップロードされます。", language: language) }
            static var cloudChangedRefreshTitle: String { L10n.tr("management.managementauth.cloudChangedRefreshTitle", vi: "Làm mới dữ liệu đã đổi trên cloud", en: "Refresh changed cloud data", ja: "クラウドで変わったデータを更新") }
            static func cloudChangedRefreshTitle(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.cloudChangedRefreshTitle", vi: "Làm mới dữ liệu đã đổi trên cloud", en: "Refresh changed cloud data", ja: "クラウドで変わったデータを更新", language: language) }
            static var cloudChangedRefreshing: String { L10n.tr("management.managementauth.cloudChangedRefreshing", vi: "Đang làm mới", en: "Refreshing", ja: "更新中") }
            static func cloudChangedRefreshing(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.cloudChangedRefreshing", vi: "Đang làm mới", en: "Refreshing", ja: "更新中", language: language) }
            static var confirmPassword: String { L10n.tr("management.managementauth.confirmPassword", vi: "Nhập lại mật khẩu", en: "Confirm password", ja: "パスワードを再入力") }
            static func confirmPassword(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.confirmPassword", vi: "Nhập lại mật khẩu", en: "Confirm password", ja: "パスワードを再入力", language: language) }
            static var confirmYourEmail: String { L10n.tr("management.managementauth.confirmYourEmail", vi: "Xác nhận email", en: "Confirm your email", ja: "メール確認") }
            static func confirmYourEmail(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.confirmYourEmail", vi: "Xác nhận email", en: "Confirm your email", ja: "メール確認", language: language) }
            static var conflictInUpdateTiming: String { L10n.tr("management.managementauth.conflictInUpdateTiming", vi: "Conflict ở thời điểm cập nhật.", en: "Conflict in update timing.", ja: "更新タイミングで競合しています。") }
            static func conflictInUpdateTiming(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.conflictInUpdateTiming", vi: "Conflict ở thời điểm cập nhật.", en: "Conflict in update timing.", ja: "更新タイミングで競合しています。", language: language) }
            static var continueWithEmail: String { L10n.tr("management.managementauth.continueWithEmail", vi: "Tiếp tục bằng Email", en: "Continue with Email", ja: "メールで続行") }
            static func continueWithEmail(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.continueWithEmail", vi: "Tiếp tục bằng Email", en: "Continue with Email", ja: "メールで続行", language: language) }
            static var continueWithGoogle: String { L10n.tr("management.managementauth.continueWithGoogle", vi: "Tiếp tục với Google", en: "Continue with Google", ja: "Google で続行") }
            static func continueWithGoogle(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.continueWithGoogle", vi: "Tiếp tục với Google", en: "Continue with Google", ja: "Google で続行", language: language) }
            static var couldnTCreateSnapshot: String { L10n.tr("management.managementauth.couldnTCreateSnapshot", vi: "Không thể tạo snapshot", en: "Couldn't create snapshot", ja: "スナップショットを作成できませんでした") }
            static func couldnTCreateSnapshot(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.couldnTCreateSnapshot", vi: "Không thể tạo snapshot", en: "Couldn't create snapshot", ja: "スナップショットを作成できませんでした", language: language) }
            static var couldnTImportSnapshot: String { L10n.tr("management.managementauth.couldnTImportSnapshot", vi: "Không thể nhập snapshot", en: "Couldn't import snapshot", ja: "スナップショットを読み込めませんでした") }
            static func couldnTImportSnapshot(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.couldnTImportSnapshot", vi: "Không thể nhập snapshot", en: "Couldn't import snapshot", ja: "スナップショットを読み込めませんでした", language: language) }
            static var couldnTOpenFile: String { L10n.tr("management.managementauth.couldnTOpenFile", vi: "Không thể mở file", en: "Couldn't open file", ja: "ファイルを開けませんでした") }
            static func couldnTOpenFile(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.couldnTOpenFile", vi: "Không thể mở file", en: "Couldn't open file", ja: "ファイルを開けませんでした", language: language) }
            static var couldnTProcessTheSelectedImage: String { L10n.tr("management.managementauth.couldnTProcessTheSelectedImage", vi: "Không xử lý được ảnh đã chọn.", en: "Couldn't process the selected image.", ja: "選択した画像を処理できませんでした。") }
            static func couldnTProcessTheSelectedImage(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.couldnTProcessTheSelectedImage", vi: "Không xử lý được ảnh đã chọn.", en: "Couldn't process the selected image.", ja: "選択した画像を処理できませんでした。", language: language) }
            static var couldnTUpdateProfile: String { L10n.tr("management.managementauth.couldnTUpdateProfile", vi: "Chưa thể cập nhật hồ sơ", en: "Couldn't update profile", ja: "プロフィールを更新できませんでした") }
            static func couldnTUpdateProfile(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.couldnTUpdateProfile", vi: "Chưa thể cập nhật hồ sơ", en: "Couldn't update profile", ja: "プロフィールを更新できませんでした", language: language) }
            static var createAccount: String { L10n.tr("management.managementauth.createAccount", vi: "Tạo tài khoản", en: "Create account", ja: "アカウント作成") }
            static func createAccount(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.createAccount", vi: "Tạo tài khoản", en: "Create account", ja: "アカウント作成", language: language) }
            static var createSnapshot: String { L10n.tr("management.managementauth.createSnapshot", vi: "Tạo bản sao lưu ngay", en: "Create snapshot", ja: "スナップショットを作成") }
            static func createSnapshot(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.createSnapshot", vi: "Tạo bản sao lưu ngay", en: "Create snapshot", ja: "スナップショットを作成", language: language) }
            static var currentDeviceBadge: String { L10n.tr("management.managementauth.currentDeviceBadge", vi: "iPhone này", en: "This iPhone", ja: "このiPhone") }
            static func currentDeviceBadge(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.currentDeviceBadge", vi: "iPhone này", en: "This iPhone", ja: "このiPhone", language: language) }
            static var dataControls: String { L10n.tr("management.managementauth.dataControls", vi: "Quyền kiểm soát dữ liệu", en: "Data controls", ja: "データ管理") }
            static func dataControls(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.dataControls", vi: "Quyền kiểm soát dữ liệu", en: "Data controls", ja: "データ管理", language: language) }
            static var dataIsOptimized: String { L10n.tr("management.managementauth.dataIsOptimized", vi: "Dữ liệu đã tối ưu", en: "Data is optimized", ja: "データは最適化されています") }
            static func dataIsOptimized(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.dataIsOptimized", vi: "Dữ liệu đã tối ưu", en: "Data is optimized", ja: "データは最適化されています", language: language) }
            static var deleteAccount: String { L10n.tr("management.managementauth.deleteAccount", vi: "Xóa tài khoản", en: "Delete account", ja: "アカウントを削除") }
            static func deleteAccount(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.deleteAccount", vi: "Xóa tài khoản", en: "Delete account", ja: "アカウントを削除", language: language) }
            static var deleteGuestData: String { L10n.tr("management.managementauth.deleteGuestData", vi: "Xóa dữ liệu guest", en: "Delete guest data", ja: "ゲストデータを削除") }
            static func deleteGuestData(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.deleteGuestData", vi: "Xóa dữ liệu guest", en: "Delete guest data", ja: "ゲストデータを削除", language: language) }
            static var deleteTheCurrentGuestLocalDataBefore: String { L10n.tr("management.managementauth.deleteTheCurrentGuestLocalDataBefore", vi: "Xóa local guest hiện tại trước khi tiếp tục với tài khoản này.", en: "Delete the current guest local data before continuing with this account.", ja: "このアカウントを続ける前に、現在のゲストローカルデータを削除します。") }
            static func deleteTheCurrentGuestLocalDataBefore(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.deleteTheCurrentGuestLocalDataBefore", vi: "Xóa local guest hiện tại trước khi tiếp tục với tài khoản này.", en: "Delete the current guest local data before continuing with this account.", ja: "このアカウントを続ける前に、現在のゲストローカルデータを削除します。", language: language) }
            static var deleteTheCurrentGuestLocalDataBefore2: String { L10n.tr("management.managementauth.deleteTheCurrentGuestLocalDataBefore2", vi: "Xóa local guest hiện tại rồi mở tài khoản này với trạng thái sạch.", en: "Delete the current guest local data before opening this account cleanly.", ja: "現在のゲストローカルデータを削除してから、このアカウントをクリーンに開きます。") }
            static func deleteTheCurrentGuestLocalDataBefore2(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.deleteTheCurrentGuestLocalDataBefore2", vi: "Xóa local guest hiện tại rồi mở tài khoản này với trạng thái sạch.", en: "Delete the current guest local data before opening this account cleanly.", ja: "現在のゲストローカルデータを削除してから、このアカウントをクリーンに開きます。", language: language) }
            static var deviceActionsAccessibility: String { L10n.tr("management.managementauth.deviceActionsAccessibility", vi: "Tùy chọn thiết bị", en: "Device actions", ja: "デバイスの操作") }
            static func deviceActionsAccessibility(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.deviceActionsAccessibility", vi: "Tùy chọn thiết bị", en: "Device actions", ja: "デバイスの操作", language: language) }
            static func deviceLastSeenValue(_ value: String) -> String {
                L10n.format("management.managementauth.deviceLastSeenValue", vi: "Lần cuối: %@", en: "Last seen: %@", ja: "最終使用: %@", value)
            }
            static func deviceLastSeenValue(_ value: String, language: MistiaAppLanguage) -> String {
                L10n.format("management.managementauth.deviceLastSeenValue", vi: "Lần cuối: %@", en: "Last seen: %@", ja: "最終使用: %@", language: language, value)
            }
            static func deviceMetadataValue(_ arg1: String, _ arg2: String) -> String {
                L10n.format("management.managementauth.deviceMetadataValue", vi: "%@ • %@", en: "%@ • %@", ja: "%@ • %@", arg1, arg2)
            }
            static func deviceMetadataValue(_ arg1: String, _ arg2: String, language: MistiaAppLanguage) -> String {
                L10n.format("management.managementauth.deviceMetadataValue", vi: "%@ • %@", en: "%@ • %@", ja: "%@ • %@", language: language, arg1, arg2)
            }
            static var deviceStatusForgotten: String { L10n.tr("management.managementauth.deviceStatusForgotten", vi: "Đã quên", en: "Forgotten", ja: "削除済み") }
            static func deviceStatusForgotten(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.deviceStatusForgotten", vi: "Đã quên", en: "Forgotten", ja: "削除済み", language: language) }
            static var deviceStatusSignedIn: String { L10n.tr("management.managementauth.deviceStatusSignedIn", vi: "Đang đăng nhập", en: "Signed in", ja: "サインイン中") }
            static func deviceStatusSignedIn(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.deviceStatusSignedIn", vi: "Đang đăng nhập", en: "Signed in", ja: "サインイン中", language: language) }
            static var deviceStatusSignedOut: String { L10n.tr("management.managementauth.deviceStatusSignedOut", vi: "Đã đăng xuất", en: "Signed out", ja: "サインアウト済み") }
            static func deviceStatusSignedOut(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.deviceStatusSignedOut", vi: "Đã đăng xuất", en: "Signed out", ja: "サインアウト済み", language: language) }
            static var deviceStatusUnknown: String { L10n.tr("management.managementauth.deviceStatusUnknown", vi: "Không rõ", en: "Unknown", ja: "不明") }
            static func deviceStatusUnknown(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.deviceStatusUnknown", vi: "Không rõ", en: "Unknown", ja: "不明", language: language) }
            static var deviceUnknownMetadata: String { L10n.tr("management.managementauth.deviceUnknownMetadata", vi: "Không có thông tin thiết bị", en: "Device details unavailable", ja: "デバイス情報なし") }
            static func deviceUnknownMetadata(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.deviceUnknownMetadata", vi: "Không có thông tin thiết bị", en: "Device details unavailable", ja: "デバイス情報なし", language: language) }
            static var displayName: String { L10n.tr("management.managementauth.displayName", vi: "Tên hiển thị", en: "Display name", ja: "表示名") }
            static func displayName(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.displayName", vi: "Tên hiển thị", en: "Display name", ja: "表示名", language: language) }
            static var displayNameCanTBeEmpty: String { L10n.tr("management.managementauth.displayNameCanTBeEmpty", vi: "Tên hiển thị không được để trống.", en: "Display name can't be empty.", ja: "表示名は空にできません。") }
            static func displayNameCanTBeEmpty(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.displayNameCanTBeEmpty", vi: "Tên hiển thị không được để trống.", en: "Display name can't be empty.", ja: "表示名は空にできません。", language: language) }
            static var donTHaveAnAccount: String { L10n.tr("management.managementauth.donTHaveAnAccount", vi: "Chưa có tài khoản?", en: "Don't have an account?", ja: "アカウントがありませんか？") }
            static func donTHaveAnAccount(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.donTHaveAnAccount", vi: "Chưa có tài khoản?", en: "Don't have an account?", ja: "アカウントがありませんか？", language: language) }
            static var dueOccurrence: String { L10n.tr("management.managementauth.dueOccurrence", vi: "Kỳ thanh toán", en: "Payment occurrence", ja: "支払いが必要") }
            static func dueOccurrence(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.dueOccurrence", vi: "Kỳ thanh toán", en: "Payment occurrence", ja: "支払いが必要", language: language) }
            static var editProfile: String { L10n.tr("management.managementauth.editProfile", vi: "Sửa hồ sơ", en: "Edit profile", ja: "プロフィールを編集") }
            static func editProfile(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.editProfile", vi: "Sửa hồ sơ", en: "Edit profile", ja: "プロフィールを編集", language: language) }
            static var editingYourProfileNeedsTheNetwork: String { L10n.tr("management.managementauth.editingYourProfileNeedsTheNetwork", vi: "Chỉnh sửa hồ sơ cần mạng", en: "Editing your profile needs the network", ja: "プロフィール編集にはネットワークが必要です") }
            static func editingYourProfileNeedsTheNetwork(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.editingYourProfileNeedsTheNetwork", vi: "Chỉnh sửa hồ sơ cần mạng", en: "Editing your profile needs the network", ja: "プロフィール編集にはネットワークが必要です", language: language) }
            static var email: String { L10n.tr("management.managementauth.email", vi: "Email", en: "Email", ja: "メール") }
            static func email(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.email", vi: "Email", en: "Email", ja: "メール", language: language) }
            static var email2: String { L10n.tr("management.managementauth.email2", vi: "Email", en: "Email", ja: "メールアドレス") }
            static func email2(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.email2", vi: "Email", en: "Email", ja: "メールアドレス", language: language) }
            static var enterTheEmailYouUseWithMistia: String { L10n.tr("management.managementauth.enterTheEmailYouUseWithMistia", vi: "Nhập email bạn dùng với Mistia. Nếu hợp lệ, hệ thống sẽ gửi email đặt lại mật khẩu.", en: "Enter the email you use with Mistia. If it's valid, the system will send a reset email.", ja: "ミスティアで使っているメールアドレスを入力してください。有効であればシステムが再設定メールを送信します。") }
            static func enterTheEmailYouUseWithMistia(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.enterTheEmailYouUseWithMistia", vi: "Nhập email bạn dùng với Mistia. Nếu hợp lệ, hệ thống sẽ gửi email đặt lại mật khẩu.", en: "Enter the email you use with Mistia. If it's valid, the system will send a reset email.", ja: "ミスティアで使っているメールアドレスを入力してください。有効であればシステムが再設定メールを送信します。", language: language) }
            static var enterYourPasswordToContinue: String { L10n.tr("management.managementauth.enterYourPasswordToContinue", vi: "Nhập mật khẩu để tiếp tục.", en: "Enter your password to continue.", ja: "続行するにはパスワードを入力してください。") }
            static func enterYourPasswordToContinue(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.enterYourPasswordToContinue", vi: "Nhập mật khẩu để tiếp tục.", en: "Enter your password to continue.", ja: "続行するにはパスワードを入力してください。", language: language) }
            static var family: String { L10n.tr("management.managementauth.family", vi: "Gia đình", en: "Family", ja: "家族") }
            static func family(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.family", vi: "Gia đình", en: "Family", ja: "家族", language: language) }
            static var firstName: String { L10n.tr("management.managementauth.firstName", vi: "Tên", en: "First name", ja: "名") }
            static func firstName(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.firstName", vi: "Tên", en: "First name", ja: "名", language: language) }
            static var firstSync: String { L10n.tr("management.managementauth.firstSync", vi: "Đồng bộ lần đầu", en: "First sync", ja: "初回同期") }
            static func firstSync(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.firstSync", vi: "Đồng bộ lần đầu", en: "First sync", ja: "初回同期", language: language) }
            static var forgetDevice: String { L10n.tr("management.managementauth.forgetDevice", vi: "Quên thiết bị", en: "Forget device", ja: "デバイスを削除") }
            static func forgetDevice(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.forgetDevice", vi: "Quên thiết bị", en: "Forget device", ja: "デバイスを削除", language: language) }
            static var forgetDeviceConfirmationTitle: String { L10n.tr("management.managementauth.forgetDeviceConfirmationTitle", vi: "Quên thiết bị?", en: "Forget device?", ja: "デバイスを削除しますか？") }
            static func forgetDeviceConfirmationTitle(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.forgetDeviceConfirmationTitle", vi: "Quên thiết bị?", en: "Forget device?", ja: "デバイスを削除しますか？", language: language) }
            static var forgetSignedInDeviceConfirmationMessage: String { L10n.tr("management.managementauth.forgetSignedInDeviceConfirmationMessage", vi: "Thiết bị đang đăng nhập sẽ được yêu cầu đăng xuất, rồi bị xóa khỏi danh sách thiết bị.", en: "Mistia will ask this signed-in device to sign out, then remove it from the device list.", ja: "サインイン中のこのデバイスにサインアウトを要求し、その後デバイス一覧から削除します。") }
            static func forgetSignedInDeviceConfirmationMessage(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.forgetSignedInDeviceConfirmationMessage", vi: "Thiết bị đang đăng nhập sẽ được yêu cầu đăng xuất, rồi bị xóa khỏi danh sách thiết bị.", en: "Mistia will ask this signed-in device to sign out, then remove it from the device list.", ja: "サインイン中のこのデバイスにサインアウトを要求し、その後デバイス一覧から削除します。", language: language) }
            static var forgetSignedOutDeviceConfirmationMessage: String { L10n.tr("management.managementauth.forgetSignedOutDeviceConfirmationMessage", vi: "Thiết bị này sẽ bị xóa khỏi danh sách thiết bị.", en: "Mistia will remove this device from the device list.", ja: "このデバイスをデバイス一覧から削除します。") }
            static func forgetSignedOutDeviceConfirmationMessage(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.forgetSignedOutDeviceConfirmationMessage", vi: "Thiết bị này sẽ bị xóa khỏi danh sách thiết bị.", en: "Mistia will remove this device from the device list.", ja: "このデバイスをデバイス一覧から削除します。", language: language) }
            static var forgotPassword: String { L10n.tr("management.managementauth.forgotPassword", vi: "Quên mật khẩu?", en: "Forgot password?", ja: "パスワードをお忘れですか？") }
            static func forgotPassword(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.forgotPassword", vi: "Quên mật khẩu?", en: "Forgot password?", ja: "パスワードをお忘れですか？", language: language) }
            static var forgotPassword2: String { L10n.tr("management.managementauth.forgotPassword2", vi: "Quên mật khẩu", en: "Forgot password", ja: "パスワードをお忘れですか") }
            static func forgotPassword2(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.forgotPassword2", vi: "Quên mật khẩu", en: "Forgot password", ja: "パスワードをお忘れですか", language: language) }
            static var fullName: String { L10n.tr("management.managementauth.fullName", vi: "Họ và tên", en: "Full name", ja: "氏名") }
            static func fullName(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.fullName", vi: "Họ và tên", en: "Full name", ja: "氏名", language: language) }
            static var hidePassword: String { L10n.tr("management.managementauth.hidePassword", vi: "Ẩn mật khẩu", en: "Hide password", ja: "パスワードを隠す") }
            static func hidePassword(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.hidePassword", vi: "Ẩn mật khẩu", en: "Hide password", ja: "パスワードを隠す", language: language) }
            static var importSnapshot: String { L10n.tr("management.managementauth.importSnapshot", vi: "Khôi phục từ tệp...", en: "Import snapshot", ja: "スナップショットを読み込む") }
            static func importSnapshot(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.importSnapshot", vi: "Khôi phục từ tệp...", en: "Import snapshot", ja: "スナップショットを読み込む", language: language) }
            static var internalSafetySnapshot: String { L10n.tr("management.managementauth.internalSafetySnapshot", vi: "Safety snapshot nội bộ", en: "Internal safety snapshot", ja: "内部安全スナップショット") }
            static func internalSafetySnapshot(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.internalSafetySnapshot", vi: "Safety snapshot nội bộ", en: "Internal safety snapshot", ja: "内部安全スナップショット", language: language) }
            static var keepBothSidesMergeByRecordID: String { L10n.tr("management.managementauth.keepBothSidesMergeByRecordID", vi: "Kết hợp dữ liệu từ thiết bị này và đám mây, bảo toàn tất cả các giao dịch mà không ghi đè.", en: "Combine device and cloud records, preventing any data loss or duplicate transactions.", ja: "端末とクラウドの両方のデータを統合し、データの消失や重複を防ぎます。") }
            static func keepBothSidesMergeByRecordID(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.keepBothSidesMergeByRecordID", vi: "Kết hợp dữ liệu từ thiết bị này và đám mây, bảo toàn tất cả các giao dịch mà không ghi đè.", en: "Combine device and cloud records, preventing any data loss or duplicate transactions.", ja: "端末とクラウドの両方のデータを統合し、データの消失や重複を防ぎます。", language: language) }
            static var keepGuestSeparate: String { L10n.tr("management.managementauth.keepGuestSeparate", vi: "Giữ guest riêng", en: "Keep guest separate", ja: "ゲストを分離したまま保持") }
            static func keepGuestSeparate(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.keepGuestSeparate", vi: "Giữ guest riêng", en: "Keep guest separate", ja: "ゲストを分離したまま保持", language: language) }
            static var keepTheCurrentGuestLocalDataAs: String { L10n.tr("management.managementauth.keepTheCurrentGuestLocalDataAs", vi: "Giữ luôn dữ liệu local guest hiện tại như dữ liệu của tài khoản này.", en: "Keep the current guest local data as part of this account.", ja: "現在のゲストローカルデータをこのアカウントのデータとして引き継ぎます。") }
            static func keepTheCurrentGuestLocalDataAs(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.keepTheCurrentGuestLocalDataAs", vi: "Giữ luôn dữ liệu local guest hiện tại như dữ liệu của tài khoản này.", en: "Keep the current guest local data as part of this account.", ja: "現在のゲストローカルデータをこのアカウントのデータとして引き継ぎます。", language: language) }
            static var keepUnrelatedLocalRecordsButIfThe: String { L10n.tr("management.managementauth.keepUnrelatedLocalRecordsButIfThe", vi: "Gộp dữ liệu từ tệp sao lưu vào dữ liệu hiện có trên thiết bị.", en: "Merge data from the backup file into existing data on this device.", ja: "バックアップファイルの内容を、端末上の既存データへ統合します。") }
            static func keepUnrelatedLocalRecordsButIfThe(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.keepUnrelatedLocalRecordsButIfThe", vi: "Gộp dữ liệu từ tệp sao lưu vào dữ liệu hiện có trên thiết bị.", en: "Merge data from the backup file into existing data on this device.", ja: "バックアップファイルの内容を、端末上の既存データへ統合します。", language: language) }
            static var lastName: String { L10n.tr("management.managementauth.lastName", vi: "Họ", en: "Last name", ja: "姓") }
            static func lastName(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.lastName", vi: "Họ", en: "Last name", ja: "姓", language: language) }
            static var latestIssue: String { L10n.tr("management.managementauth.latestIssue", vi: "Lỗi gần nhất", en: "Latest issue", ja: "直近の問題") }
            static func latestIssue(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.latestIssue", vi: "Lỗi gần nhất", en: "Latest issue", ja: "直近の問題", language: language) }
            static var latestSnapshotSummary: String { L10n.tr("management.managementauth.latestSnapshotSummary", vi: "Nội dung snapshot gần nhất", en: "Latest snapshot summary", ja: "直近のスナップショット概要") }
            static func latestSnapshotSummary(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.latestSnapshotSummary", vi: "Nội dung snapshot gần nhất", en: "Latest snapshot summary", ja: "直近のスナップショット概要", language: language) }
            static var learnHowMistiaUsesPersonalInformation: String { L10n.tr("management.managementauth.learnHowMistiaUsesPersonalInformation", vi: "Tìm hiểu cách Mistia sử dụng thông tin cá nhân", en: "Learn how Mistia uses personal information", ja: "ミスティアの個人情報の利用方法を確認する") }
            static func learnHowMistiaUsesPersonalInformation(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.learnHowMistiaUsesPersonalInformation", vi: "Tìm hiểu cách Mistia sử dụng thông tin cá nhân", en: "Learn how Mistia uses personal information", ja: "ミスティアの個人情報の利用方法を確認する", language: language) }
            static var manageSyncedData: String { L10n.tr("management.managementauth.manageSyncedData", vi: "Kiểm tra dữ liệu chưa đồng nhất", en: "Data Review", ja: "データの確認") }
            static func manageSyncedData(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.manageSyncedData", vi: "Kiểm tra dữ liệu chưa đồng nhất", en: "Data Review", ja: "データの確認", language: language) }
            static var manual: String { L10n.tr("management.managementauth.manual", vi: "Thủ công", en: "Manual", ja: "手動") }
            static func manual(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.manual", vi: "Thủ công", en: "Manual", ja: "手動", language: language) }
            static var merge: String { L10n.tr("management.managementauth.merge", vi: "Gộp", en: "Merge", ja: "統合") }
            static func merge(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.merge", vi: "Gộp", en: "Merge", ja: "統合", language: language) }
            static var mergeSafely: String { L10n.tr("management.managementauth.mergeSafely", vi: "Hợp nhất dữ liệu", en: "Merge Data", ja: "データをマージする") }
            static func mergeSafely(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.mergeSafely", vi: "Hợp nhất dữ liệu", en: "Merge Data", ja: "データをマージする", language: language) }
            static var mistiaAlreadyHasTheSignInAnd: String { L10n.tr("management.managementauth.mistiaAlreadyHasTheSignInAnd", vi: "Mistia đã có sẵn flow đăng nhập và đồng bộ, nhưng bạn cần điền URL cùng public key của dịch vụ cloud trước khi dùng.", en: "Mistia already has the sign-in and sync flow, but you need to fill in the cloud service URL and public key first.", ja: "ミスティアにはログインと同期の流れがありますが、使う前にクラウドサービスの URL と公開キーを設定する必要があります。") }
            static func mistiaAlreadyHasTheSignInAnd(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.mistiaAlreadyHasTheSignInAnd", vi: "Mistia đã có sẵn flow đăng nhập và đồng bộ, nhưng bạn cần điền URL cùng public key của dịch vụ cloud trước khi dùng.", en: "Mistia already has the sign-in and sync flow, but you need to fill in the cloud service URL and public key first.", ja: "ミスティアにはログインと同期の流れがありますが、使う前にクラウドサービスの URL と公開キーを設定する必要があります。", language: language) }
            static var mistiaCreatedASafetySnapshotBeforeReplacing: String { L10n.tr("management.managementauth.mistiaCreatedASafetySnapshotBeforeReplacing", vi: "Mistia đã tạo một snapshot an toàn trước khi thay toàn bộ dữ liệu local. Bạn có thể share file này ra ngoài nếu muốn giữ thêm một lớp dự phòng.", en: "Mistia created a safety snapshot before replacing local data. You can share that file if you want an extra fallback copy.", ja: "ローカルデータを置き換える前に、安全用スナップショットを作成しました。追加の予備として外部共有することもできます。") }
            static func mistiaCreatedASafetySnapshotBeforeReplacing(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.mistiaCreatedASafetySnapshotBeforeReplacing", vi: "Mistia đã tạo một snapshot an toàn trước khi thay toàn bộ dữ liệu local. Bạn có thể share file này ra ngoài nếu muốn giữ thêm một lớp dự phòng.", en: "Mistia created a safety snapshot before replacing local data. You can share that file if you want an extra fallback copy.", ja: "ローカルデータを置き換える前に、安全用スナップショットを作成しました。追加の予備として外部共有することもできます。", language: language) }
            static var mistiaFirstCreatesAnInternalSafetySnapshot: String { L10n.tr("management.managementauth.mistiaFirstCreatesAnInternalSafetySnapshot", vi: "Mistia sẽ khôi phục dữ liệu từ tệp sao lưu đã chọn, thay thế dữ liệu hiện có trên thiết bị.", en: "Mistia will restore data from the selected backup file, replacing existing data on this device.", ja: "選択したバックアップファイルからデータを復元し、端末上の既存データを置き換えます。") }
            static func mistiaFirstCreatesAnInternalSafetySnapshot(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.mistiaFirstCreatesAnInternalSafetySnapshot", vi: "Mistia sẽ khôi phục dữ liệu từ tệp sao lưu đã chọn, thay thế dữ liệu hiện có trên thiết bị.", en: "Mistia will restore data from the selected backup file, replacing existing data on this device.", ja: "選択したバックアップファイルからデータを復元し、端末上の既存データを置き換えます。", language: language) }
            static var mistiaIsAutomaticallyCheckingAndSyncingData: String { L10n.tr("management.managementauth.mistiaIsAutomaticallyCheckingAndSyncingData", vi: "Mistia đang tự động kiểm tra và đồng bộ dữ liệu. Để đạt hiệu quả tốt nhất, hãy đảm bảo iPhone của bạn được kết nối Wi-Fi và cắm sạc khi có thể. Hệ thống sẽ ưu tiên chạy ngầm khi bạn không sử dụng ứng dụng.", en: "Mistia is automatically checking and syncing data. For best performance, ensure your iPhone is connected to Wi-Fi and charging when possible. The system prioritizes background sync when you're not using the app.", ja: "ミスティアはデータを自動的に確認して同期しています。最高のパフォーマンスを得るために、可能であれば iPhone を Wi-Fi に接続し、充電状態にしてください。アプリを使用していない間のバックグラウンド同期が優先されます。") }
            static func mistiaIsAutomaticallyCheckingAndSyncingData(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.mistiaIsAutomaticallyCheckingAndSyncingData", vi: "Mistia đang tự động kiểm tra và đồng bộ dữ liệu. Để đạt hiệu quả tốt nhất, hãy đảm bảo iPhone của bạn được kết nối Wi-Fi và cắm sạc khi có thể. Hệ thống sẽ ưu tiên chạy ngầm khi bạn không sử dụng ứng dụng.", en: "Mistia is automatically checking and syncing data. For best performance, ensure your iPhone is connected to Wi-Fi and charging when possible. The system prioritizes background sync when you're not using the app.", ja: "ミスティアはデータを自動的に確認して同期しています。最高のパフォーマンスを得るために、可能であれば iPhone を Wi-Fi に接続し、充電状態にしてください。アプリを使用していない間のバックグラウンド同期が優先されます。", language: language) }
            static var mistiaIsSyncingYourDataWithThe: String { L10n.tr("management.managementauth.mistiaIsSyncingYourDataWithThe", vi: "Mistia đang thực hiện đồng bộ dữ liệu của bạn với hệ thống đám mây để đảm bảo mọi thay đổi được lưu trữ an toàn. Quá trình này giúp bạn có thể truy cập dữ liệu mới nhất trên tất cả các thiết bị của mình.", en: "Mistia is syncing your data with the cloud to ensure all changes are stored safely. This process allows you to access the latest data across all your devices.", ja: "ミスティアはデータをクラウドと同期して, すべての変更が安全に保存されるようにしています。このプロセスにより, すべてのデバイスで最新のデータにアクセスできるようになります。") }
            static func mistiaIsSyncingYourDataWithThe(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.mistiaIsSyncingYourDataWithThe", vi: "Mistia đang thực hiện đồng bộ dữ liệu của bạn với hệ thống đám mây để đảm bảo mọi thay đổi được lưu trữ an toàn. Quá trình này giúp bạn có thể truy cập dữ liệu mới nhất trên tất cả các thiết bị của mình.", en: "Mistia is syncing your data with the cloud to ensure all changes are stored safely. This process allows you to access the latest data across all your devices.", ja: "ミスティアはデータをクラウドと同期して, すべての変更が安全に保存されるようにしています。このプロセスにより, すべてのデバイスで最新のデータにアクセスできるようになります。", language: language) }
            static var mistiaMergedTheSnapshotIntoLocalData: String { L10n.tr("management.managementauth.mistiaMergedTheSnapshotIntoLocalData", vi: "Mistia đã merge dữ liệu từ snapshot vào local. Hãy kiểm tra lại rồi tự bấm Đồng bộ ngay nếu bạn muốn cập nhật cloud.", en: "Mistia merged the snapshot into local data. Review it, then manually tap Sync now if you want to update the cloud.", ja: "スナップショットをローカルデータへマージしました。内容を確認してから、必要に応じて手動で「今すぐ同期」を押してください。") }
            static func mistiaMergedTheSnapshotIntoLocalData(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.mistiaMergedTheSnapshotIntoLocalData", vi: "Mistia đã merge dữ liệu từ snapshot vào local. Hãy kiểm tra lại rồi tự bấm Đồng bộ ngay nếu bạn muốn cập nhật cloud.", en: "Mistia merged the snapshot into local data. Review it, then manually tap Sync now if you want to update the cloud.", ja: "スナップショットをローカルデータへマージしました。内容を確認してから、必要に応じて手動で「今すぐ同期」を押してください。", language: language) }
            static var mistiaReplacedLocalDataWithTheSelected: String { L10n.tr("management.managementauth.mistiaReplacedLocalDataWithTheSelected", vi: "Mistia đã thay dữ liệu local bằng snapshot đã chọn và giữ lại một safety snapshot nội bộ trước đó.", en: "Mistia replaced local data with the selected snapshot and kept an internal safety snapshot beforehand.", ja: "選択したスナップショットでローカルデータを置き換え、事前に内部の安全用スナップショットも保存しました。") }
            static func mistiaReplacedLocalDataWithTheSelected(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.mistiaReplacedLocalDataWithTheSelected", vi: "Mistia đã thay dữ liệu local bằng snapshot đã chọn và giữ lại một safety snapshot nội bộ trước đó.", en: "Mistia replaced local data with the selected snapshot and kept an internal safety snapshot beforehand.", ja: "選択したスナップショットでローカルデータを置き換え、事前に内部の安全用スナップショットも保存しました。", language: language) }
            static var mistiaUsesYourNameAndProfilePhoto: String { L10n.tr("management.managementauth.mistiaUsesYourNameAndProfilePhoto", vi: "Mistia dùng tên và ảnh đại diện để hiển thị hồ sơ của bạn trên thiết bị đã đăng nhập và trong các vùng liên quan đến tài khoản.", en: "Mistia uses your name and profile photo to present your account consistently across signed-in devices and account-related surfaces.", ja: "ミスティアは、サインイン済みデバイスやアカウント関連画面でプロフィールを一貫して表示するために、名前とプロフィール写真を使用します。") }
            static func mistiaUsesYourNameAndProfilePhoto(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.mistiaUsesYourNameAndProfilePhoto", vi: "Mistia dùng tên và ảnh đại diện để hiển thị hồ sơ của bạn trên thiết bị đã đăng nhập và trong các vùng liên quan đến tài khoản.", en: "Mistia uses your name and profile photo to present your account consistently across signed-in devices and account-related surfaces.", ja: "ミスティアは、サインイン済みデバイスやアカウント関連画面でプロフィールを一貫して表示するために、名前とプロフィール写真を使用します。", language: language) }
            static var nameAndProfilePhoto: String { L10n.tr("management.managementauth.nameAndProfilePhoto", vi: "Tên và ảnh đại diện", en: "Name and profile photo", ja: "名前とプロフィール写真") }
            static func nameAndProfilePhoto(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.nameAndProfilePhoto", vi: "Tên và ảnh đại diện", en: "Name and profile photo", ja: "名前とプロフィール写真", language: language) }
            static var nameUnavailable: String { L10n.tr("management.managementauth.nameUnavailable", vi: "Không tìm thấy tên", en: "Name unavailable", ja: "名前なし") }
            static func nameUnavailable(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.nameUnavailable", vi: "Không tìm thấy tên", en: "Name unavailable", ja: "名前なし", language: language) }
            static var newer: String { L10n.tr("management.managementauth.newer", vi: "Mới hơn", en: "Newer", ja: "最新") }
            static func newer(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.newer", vi: "Mới hơn", en: "Newer", ja: "最新", language: language) }
            static var noConflictsYet: String { L10n.tr("management.managementauth.noConflictsYet", vi: "Dữ liệu đã đồng bộ hoàn tất", en: "Everything is Up to Date", ja: "データは最新です") }
            static func noConflictsYet(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.noConflictsYet", vi: "Dữ liệu đã đồng bộ hoàn tất", en: "Everything is Up to Date", ja: "データは最新です", language: language) }
            static var noFileSelected: String { L10n.tr("management.managementauth.noFileSelected", vi: "Không có file nào được chọn", en: "No file selected", ja: "ファイルが選択されていません") }
            static func noFileSelected(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.noFileSelected", vi: "Không có file nào được chọn", en: "No file selected", ja: "ファイルが選択されていません", language: language) }
            static var none: String { L10n.tr("management.managementauth.none", vi: "Chưa có", en: "None", ja: "未設定") }
            static func none(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.none", vi: "Chưa có", en: "None", ja: "未設定", language: language) }
            static var normal: String { L10n.tr("management.managementauth.normal", vi: "Ổn", en: "Normal", ja: "普通") }
            static func normal(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.normal", vi: "Ổn", en: "Normal", ja: "普通", language: language) }
            static var notConfigured: String { L10n.tr("management.managementauth.notConfigured", vi: "Chưa cấu hình", en: "Not configured", ja: "未設定") }
            static func notConfigured(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.notConfigured", vi: "Chưa cấu hình", en: "Not configured", ja: "未設定", language: language) }
            static var offline: String { L10n.tr("management.managementauth.offline", vi: "Đang ngoại tuyến", en: "Offline", ja: "オフライン") }
            static func offline(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.offline", vi: "Đang ngoại tuyến", en: "Offline", ja: "オフライン", language: language) }
            static var openThisAccountInItsOwnProfile: String { L10n.tr("management.managementauth.openThisAccountInItsOwnProfile", vi: "Mở tài khoản này bằng profile riêng, không chuyển dữ liệu guest cũ sang.", en: "Open this account in its own profile without moving over the old guest data.", ja: "古いゲストデータを移さず、このアカウント専用のプロファイルで開きます。") }
            static func openThisAccountInItsOwnProfile(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.openThisAccountInItsOwnProfile", vi: "Mở tài khoản này bằng profile riêng, không chuyển dữ liệu guest cũ sang.", en: "Open this account in its own profile without moving over the old guest data.", ja: "古いゲストデータを移さず、このアカウント専用のプロファイルで開きます。", language: language) }
            static var or: String { L10n.tr("management.managementauth.or", vi: "hoặc", en: "or", ja: "または") }
            static func or(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.or", vi: "hoặc", en: "or", ja: "または", language: language) }
            static var password: String { L10n.tr("management.managementauth.password", vi: "Mật khẩu", en: "Password", ja: "パスワード") }
            static func password(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.password", vi: "Mật khẩu", en: "Password", ja: "パスワード", language: language) }
            static var passwordMustBeAtLeastCharacters: String { L10n.tr("management.managementauth.passwordMustBeAtLeastCharacters", vi: "Mật khẩu cần ít nhất 8 ký tự.", en: "Password must be at least 8 characters.", ja: "パスワードは 8 文字以上である必要があります。") }
            static func passwordMustBeAtLeastCharacters(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.passwordMustBeAtLeastCharacters", vi: "Mật khẩu cần ít nhất 8 ký tự.", en: "Password must be at least 8 characters.", ja: "パスワードは 8 文字以上である必要があります。", language: language) }
            static var passwordNeedsAtLeastLowercaseLetter: String { L10n.tr("management.managementauth.passwordNeedsAtLeastLowercaseLetter", vi: "Mật khẩu cần ít nhất 1 chữ viết thường.", en: "Password needs at least 1 lowercase letter.", ja: "パスワードには小文字を 1 文字以上含めてください。") }
            static func passwordNeedsAtLeastLowercaseLetter(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.passwordNeedsAtLeastLowercaseLetter", vi: "Mật khẩu cần ít nhất 1 chữ viết thường.", en: "Password needs at least 1 lowercase letter.", ja: "パスワードには小文字を 1 文字以上含めてください。", language: language) }
            static var passwordNeedsAtLeastUppercaseLetter: String { L10n.tr("management.managementauth.passwordNeedsAtLeastUppercaseLetter", vi: "Mật khẩu cần ít nhất 1 chữ viết hoa.", en: "Password needs at least 1 uppercase letter.", ja: "パスワードには大文字を 1 文字以上含めてください。") }
            static func passwordNeedsAtLeastUppercaseLetter(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.passwordNeedsAtLeastUppercaseLetter", vi: "Mật khẩu cần ít nhất 1 chữ viết hoa.", en: "Password needs at least 1 uppercase letter.", ja: "パスワードには大文字を 1 文字以上含めてください。", language: language) }
            static var personalInformation: String { L10n.tr("management.managementauth.personalInformation", vi: "Thông tin cá nhân", en: "Personal information", ja: "個人情報") }
            static func personalInformation(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.personalInformation", vi: "Thông tin cá nhân", en: "Personal information", ja: "個人情報", language: language) }
            static var profile: String { L10n.tr("management.managementauth.profile", vi: "Hồ sơ", en: "Profile", ja: "プロフィール") }
            static func profile(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.profile", vi: "Hồ sơ", en: "Profile", ja: "プロフィール", language: language) }
            static var reEnterYourPasswordToConfirmIt: String { L10n.tr("management.managementauth.reEnterYourPasswordToConfirmIt", vi: "Nhập lại mật khẩu để xác nhận.", en: "Re-enter your password to confirm it.", ja: "確認のためパスワードを再入力してください。") }
            static func reEnterYourPasswordToConfirmIt(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.reEnterYourPasswordToConfirmIt", vi: "Nhập lại mật khẩu để xác nhận.", en: "Re-enter your password to confirm it.", ja: "確認のためパスワードを再入力してください。", language: language) }
            static var recommended: String { L10n.tr("management.managementauth.recommended", vi: "Khuyên dùng", en: "Recommended", ja: "おすすめ") }
            static func recommended(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.recommended", vi: "Khuyên dùng", en: "Recommended", ja: "おすすめ", language: language) }
            static var replaceLocal: String { L10n.tr("management.managementauth.replaceLocal", vi: "Thay thế", en: "Replace", ja: "置換") }
            static func replaceLocal(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.replaceLocal", vi: "Thay thế", en: "Replace", ja: "置換", language: language) }
            static var replaceTheCurrentLocalSnapshotWithThe: String { L10n.tr("management.managementauth.replaceTheCurrentLocalSnapshotWithThe", vi: "Ghi đè dữ liệu trên thiết bị này bằng dữ liệu tải về từ đám mây.", en: "Replace this device's data with the data downloaded from the cloud.", ja: "この端末のデータをクラウドからダウンロードしたデータで上書きします。") }
            static func replaceTheCurrentLocalSnapshotWithThe(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.replaceTheCurrentLocalSnapshotWithThe", vi: "Ghi đè dữ liệu trên thiết bị này bằng dữ liệu tải về từ đám mây.", en: "Replace this device's data with the data downloaded from the cloud.", ja: "この端末のデータをクラウドからダウンロードしたデータで上書きします。", language: language) }
            static var resendConfirmationEmail: String { L10n.tr("management.managementauth.resendConfirmationEmail", vi: "Gửi lại email xác nhận", en: "Resend confirmation email", ja: "確認メールを再送") }
            static func resendConfirmationEmail(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.resendConfirmationEmail", vi: "Gửi lại email xác nhận", en: "Resend confirmation email", ja: "確認メールを再送", language: language) }
            static var resolvingConflictsNeedsTheNetwork: String { L10n.tr("management.managementauth.resolvingConflictsNeedsTheNetwork", vi: "Cần mạng để xử lý conflict", en: "Resolving conflicts needs the network", ja: "競合の解決にはネットワークが必要です") }
            static func resolvingConflictsNeedsTheNetwork(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.resolvingConflictsNeedsTheNetwork", vi: "Cần mạng để xử lý conflict", en: "Resolving conflicts needs the network", ja: "競合の解決にはネットワークが必要です", language: language) }
            static var restoreMode: String { L10n.tr("management.managementauth.restoreMode", vi: "Chế độ khôi phục", en: "Restore mode", ja: "復元モード") }
            static func restoreMode(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.restoreMode", vi: "Chế độ khôi phục", en: "Restore mode", ja: "復元モード", language: language) }
            static var sendResetEmail: String { L10n.tr("management.managementauth.sendResetEmail", vi: "Gửi email đặt lại mật khẩu", en: "Send reset email", ja: "再設定メールを送信") }
            static func sendResetEmail(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.sendResetEmail", vi: "Gửi email đặt lại mật khẩu", en: "Send reset email", ja: "再設定メールを送信", language: language) }
            static var shareSafetySnapshot: String { L10n.tr("management.managementauth.shareSafetySnapshot", vi: "Chia sẻ safety snapshot", en: "Share safety snapshot", ja: "安全スナップショットを共有") }
            static func shareSafetySnapshot(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.shareSafetySnapshot", vi: "Chia sẻ safety snapshot", en: "Share safety snapshot", ja: "安全スナップショットを共有", language: language) }
            static var showPassword: String { L10n.tr("management.managementauth.showPassword", vi: "Hiện mật khẩu", en: "Show password", ja: "パスワードを表示") }
            static func showPassword(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.showPassword", vi: "Hiện mật khẩu", en: "Show password", ja: "パスワードを表示", language: language) }
            static var signIn: String { L10n.tr("management.managementauth.signIn", vi: "Đăng nhập", en: "Sign in", ja: "ログイン") }
            static func signIn(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.signIn", vi: "Đăng nhập", en: "Sign in", ja: "ログイン", language: language) }
            static var signInToThisAccountWithoutMixing: String { L10n.tr("management.managementauth.signInToThisAccountWithoutMixing", vi: "Đăng nhập tài khoản này nhưng không trộn với dữ liệu guest hiện tại.", en: "Sign in to this account without mixing in the current guest data.", ja: "現在のゲストデータとは分けたまま、このアカウントでログインします。") }
            static func signInToThisAccountWithoutMixing(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.signInToThisAccountWithoutMixing", vi: "Đăng nhập tài khoản này nhưng không trộn với dữ liệu guest hiện tại.", en: "Sign in to this account without mixing in the current guest data.", ja: "現在のゲストデータとは分けたまま、このアカウントでログインします。", language: language) }
            static var signOutAndDeleteLocal: String { L10n.tr("management.managementauth.signOutAndDeleteLocal", vi: "Đăng xuất & xóa dữ liệu", en: "Sign out & delete data", ja: "サインアウト（データ削除）") }
            static func signOutAndDeleteLocal(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.signOutAndDeleteLocal", vi: "Đăng xuất & xóa dữ liệu", en: "Sign out & delete data", ja: "サインアウト（データ削除）", language: language) }
            static var signOutAndKeepLocal: String { L10n.tr("management.managementauth.signOutAndKeepLocal", vi: "Đăng xuất & giữ dữ liệu", en: "Sign out & keep data", ja: "サインアウト（データ保持）") }
            static func signOutAndKeepLocal(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.signOutAndKeepLocal", vi: "Đăng xuất & giữ dữ liệu", en: "Sign out & keep data", ja: "サインアウト（データ保持）", language: language) }
            static var signOutDevice: String { L10n.tr("management.managementauth.signOutDevice", vi: "Đăng xuất khỏi thiết bị", en: "Sign out of device", ja: "デバイスからサインアウト") }
            static func signOutDevice(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.signOutDevice", vi: "Đăng xuất khỏi thiết bị", en: "Sign out of device", ja: "デバイスからサインアウト", language: language) }
            static var signOutDeviceConfirmationMessage: String { L10n.tr("management.managementauth.signOutDeviceConfirmationMessage", vi: "Mistia sẽ yêu cầu thiết bị này đăng xuất ở lần mở app, đồng bộ hoặc kiểm tra phiên tiếp theo.", en: "Mistia will ask this device to sign out the next time it opens the app, syncs, or checks the session.", ja: "次にアプリを開く、同期する、またはセッション確認を行うタイミングで、このデバイスにサインアウトを要求します。") }
            static func signOutDeviceConfirmationMessage(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.signOutDeviceConfirmationMessage", vi: "Mistia sẽ yêu cầu thiết bị này đăng xuất ở lần mở app, đồng bộ hoặc kiểm tra phiên tiếp theo.", en: "Mistia will ask this device to sign out the next time it opens the app, syncs, or checks the session.", ja: "次にアプリを開く、同期する、またはセッション確認を行うタイミングで、このデバイスにサインアウトを要求します。", language: language) }
            static var signOutDeviceConfirmationTitle: String { L10n.tr("management.managementauth.signOutDeviceConfirmationTitle", vi: "Đăng xuất thiết bị?", en: "Sign out device?", ja: "デバイスからサインアウトしますか？") }
            static func signOutDeviceConfirmationTitle(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.signOutDeviceConfirmationTitle", vi: "Đăng xuất thiết bị?", en: "Sign out device?", ja: "デバイスからサインアウトしますか？", language: language) }
            static var signOutThisDevice: String { L10n.tr("management.managementauth.signOutThisDevice", vi: "Đăng xuất khỏi thiết bị này", en: "Sign out of this device", ja: "このデバイスからサインアウト") }
            static func signOutThisDevice(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.signOutThisDevice", vi: "Đăng xuất khỏi thiết bị này", en: "Sign out of this device", ja: "このデバイスからサインアウト", language: language) }
            static var signOutThisDeviceConfirmationMessage: String { L10n.tr("management.managementauth.signOutThisDeviceConfirmationMessage", vi: "Mistia sẽ đăng xuất tài khoản khỏi thiết bị hiện tại. Dữ liệu cục bộ vẫn được giữ như thao tác đăng xuất thông thường.", en: "Mistia will sign the account out of this device. Local data is kept, matching the normal sign-out flow.", ja: "このデバイスからアカウントをサインアウトします。通常のサインアウトと同じくローカルデータは保持されます。") }
            static func signOutThisDeviceConfirmationMessage(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.signOutThisDeviceConfirmationMessage", vi: "Mistia sẽ đăng xuất tài khoản khỏi thiết bị hiện tại. Dữ liệu cục bộ vẫn được giữ như thao tác đăng xuất thông thường.", en: "Mistia will sign the account out of this device. Local data is kept, matching the normal sign-out flow.", ja: "このデバイスからアカウントをサインアウトします。通常のサインアウトと同じくローカルデータは保持されます。", language: language) }
            static var signUpNow: String { L10n.tr("management.managementauth.signUpNow", vi: "Đăng ký ngay", en: "Sign up now", ja: "今すぐ登録") }
            static func signUpNow(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.signUpNow", vi: "Đăng ký ngay", en: "Sign up now", ja: "今すぐ登録", language: language) }
            static var signedInDevices: String { L10n.tr("management.managementauth.signedInDevices", vi: "Thiết bị đã đăng nhập", en: "Signed-in devices", ja: "サインイン済みデバイス") }
            static func signedInDevices(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.signedInDevices", vi: "Thiết bị đã đăng nhập", en: "Signed-in devices", ja: "サインイン済みデバイス", language: language) }
            static var signedInDevicesEmptyMessage: String { L10n.tr("management.managementauth.signedInDevicesEmptyMessage", vi: "Thiết bị sẽ xuất hiện ở đây sau khi tài khoản đăng nhập và đồng bộ.", en: "Devices appear here after the account signs in and syncs.", ja: "アカウントがサインインして同期すると、ここにデバイスが表示されます。") }
            static func signedInDevicesEmptyMessage(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.signedInDevicesEmptyMessage", vi: "Thiết bị sẽ xuất hiện ở đây sau khi tài khoản đăng nhập và đồng bộ.", en: "Devices appear here after the account signs in and syncs.", ja: "アカウントがサインインして同期すると、ここにデバイスが表示されます。", language: language) }
            static var signedInDevicesEmptyTitle: String { L10n.tr("management.managementauth.signedInDevicesEmptyTitle", vi: "Chưa có thiết bị", en: "No devices yet", ja: "デバイスはまだありません") }
            static func signedInDevicesEmptyTitle(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.signedInDevicesEmptyTitle", vi: "Chưa có thiết bị", en: "No devices yet", ja: "デバイスはまだありません", language: language) }
            static var signedInDevicesLoading: String { L10n.tr("management.managementauth.signedInDevicesLoading", vi: "Đang tải thiết bị", en: "Loading devices", ja: "デバイスを読み込み中") }
            static func signedInDevicesLoading(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.signedInDevicesLoading", vi: "Đang tải thiết bị", en: "Loading devices", ja: "デバイスを読み込み中", language: language) }
            static var snapshotRestored: String { L10n.tr("management.managementauth.snapshotRestored", vi: "Đã khôi phục snapshot", en: "Snapshot restored", ja: "スナップショットを復元しました") }
            static func snapshotRestored(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.snapshotRestored", vi: "Đã khôi phục snapshot", en: "Snapshot restored", ja: "スナップショットを復元しました", language: language) }
            static var strong: String { L10n.tr("management.managementauth.strong", vi: "Mạnh", en: "Strong", ja: "強い") }
            static func strong(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.strong", vi: "Mạnh", en: "Strong", ja: "強い", language: language) }
            static var syncConflictCloud: String { L10n.tr("management.managementauth.syncConflictCloud", vi: "Trên cloud", en: "Cloud", ja: "クラウド") }
            static func syncConflictCloud(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.syncConflictCloud", vi: "Trên cloud", en: "Cloud", ja: "クラウド", language: language) }
            static var syncConflictKeepCloud: String { L10n.tr("management.managementauth.syncConflictKeepCloud", vi: "Dùng dữ liệu trên Cloud", en: "Keep data on Cloud", ja: "クラウドのデータを使用") }
            static func syncConflictKeepCloud(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.syncConflictKeepCloud", vi: "Dùng dữ liệu trên Cloud", en: "Keep data on Cloud", ja: "クラウドのデータを使用", language: language) }
            static var syncConflictKeepThisDevice: String { L10n.tr("management.managementauth.syncConflictKeepThisDevice", vi: "Dùng dữ liệu trên máy này", en: "Keep data on this device", ja: "このデバイスのデータを使用") }
            static func syncConflictKeepThisDevice(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.syncConflictKeepThisDevice", vi: "Dùng dữ liệu trên máy này", en: "Keep data on this device", ja: "このデバイスのデータを使用", language: language) }
            static var syncConflictReviewSubtitle: String { L10n.tr("management.managementauth.syncConflictReviewSubtitle", vi: "Mistia phát hiện thông tin trên máy và Cloud chưa thống nhất. Hãy chọn bản dữ liệu bạn muốn lưu giữ.", en: "Data on this device and Cloud are different. Choose which version to keep.", ja: "この端末とクラウドの情報が一致していません。残すデータを選択してください。") }
            static func syncConflictReviewSubtitle(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.syncConflictReviewSubtitle", vi: "Mistia phát hiện thông tin trên máy và Cloud chưa thống nhất. Hãy chọn bản dữ liệu bạn muốn lưu giữ.", en: "Data on this device and Cloud are different. Choose which version to keep.", ja: "この端末とクラウドの情報が一致していません。残すデータを選択してください。", language: language) }
            static var syncConflictReviewTitle: String { L10n.tr("management.managementauth.syncConflictReviewTitle", vi: "Chọn dữ liệu bạn muốn lưu giữ", en: "Review Data Differences", ja: "データ内容の確認") }
            static func syncConflictReviewTitle(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.syncConflictReviewTitle", vi: "Chọn dữ liệu bạn muốn lưu giữ", en: "Review Data Differences", ja: "データ内容の確認", language: language) }
            static var syncConflictThisDevice: String { L10n.tr("management.managementauth.syncConflictThisDevice", vi: "Máy này", en: "This device", ja: "この端末") }
            static func syncConflictThisDevice(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.syncConflictThisDevice", vi: "Máy này", en: "This device", ja: "この端末", language: language) }
            static var syncIsOff: String { L10n.tr("management.managementauth.syncIsOff", vi: "Chưa đồng bộ", en: "Sync is off", ja: "同期はオフです") }
            static func syncIsOff(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.syncIsOff", vi: "Chưa đồng bộ", en: "Sync is off", ja: "同期はオフです", language: language) }
            static var syncNow: String { L10n.tr("management.managementauth.syncNow", vi: "Đồng bộ ngay", en: "Sync now", ja: "今すぐ同期") }
            static func syncNow(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.syncNow", vi: "Đồng bộ ngay", en: "Sync now", ja: "今すぐ同期", language: language) }
            static var syncSettings: String { L10n.tr("management.managementauth.syncSettings", vi: "Cài đặt đồng bộ", en: "Sync settings", ja: "同期設定") }
            static func syncSettings(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.syncSettings", vi: "Cài đặt đồng bộ", en: "Sync settings", ja: "同期設定", language: language) }
            static var syncSettings2: String { L10n.tr("management.managementauth.syncSettings2", vi: "Đồng bộ dữ liệu", en: "Sync settings", ja: "同期設定") }
            static func syncSettings2(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.syncSettings2", vi: "Đồng bộ dữ liệu", en: "Sync settings", ja: "同期設定", language: language) }
            static func syncedAtValue(_ value: String) -> String {
                L10n.format("management.managementauth.syncedAtValue", vi: "Đã đồng bộ lúc %@", en: "Synced at %@", ja: "%@ に同期済み", value)
            }
            static func syncedAtValue(_ value: String, language: MistiaAppLanguage) -> String {
                L10n.format("management.managementauth.syncedAtValue", vi: "Đã đồng bộ lúc %@", en: "Synced at %@", ja: "%@ に同期済み", language: language, value)
            }
            static var takePhoto: String { L10n.tr("management.managementauth.takePhoto", vi: "Chụp ảnh", en: "Take Photo", ja: "写真を撮る") }
            static func takePhoto(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.takePhoto", vi: "Chụp ảnh", en: "Take Photo", ja: "写真を撮る", language: language) }
            static func theCloudHasNoDataYetExcept(_ value: String) -> String {
                L10n.format("management.managementauth.theCloudHasNoDataYetExcept", vi: "Đám mây hiện chưa có dữ liệu. Thiết bị này đang có %@ bản ghi. Vui lòng chọn cách bạn muốn bắt đầu đồng bộ.", en: "The cloud has no data yet. This device has %@ records. Choose how you want to initialize synchronization.", ja: "クラウドにデータがありません。この端末には %@ 件のレコードがあります。同期の開始方法を選択してください。", value)
            }
            static func theCloudHasNoDataYetExcept(_ value: String, language: MistiaAppLanguage) -> String {
                L10n.format("management.managementauth.theCloudHasNoDataYetExcept", vi: "Đám mây hiện chưa có dữ liệu. Thiết bị này đang có %@ bản ghi. Vui lòng chọn cách bạn muốn bắt đầu đồng bộ.", en: "The cloud has no data yet. This device has %@ records. Choose how you want to initialize synchronization.", ja: "クラウドにデータがありません。この端末には %@ 件のレコードがあります。同期の開始方法を選択してください。", language: language, value)
            }
            static var theConfirmationPasswordDoesnTMatchYet: String { L10n.tr("management.managementauth.theConfirmationPasswordDoesnTMatchYet", vi: "Mật khẩu nhập lại chưa khớp.", en: "The confirmation password doesn't match yet.", ja: "確認用パスワードがまだ一致していません。") }
            static func theConfirmationPasswordDoesnTMatchYet(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.theConfirmationPasswordDoesnTMatchYet", vi: "Mật khẩu nhập lại chưa khớp.", en: "The confirmation password doesn't match yet.", ja: "確認用パスワードがまだ一致していません。", language: language) }
            static var theEmailFormatDoesnTLookRight: String { L10n.tr("management.managementauth.theEmailFormatDoesnTLookRight", vi: "Email chưa đúng định dạng.", en: "The email format doesn't look right.", ja: "メールアドレスの形式が正しくありません。") }
            static func theEmailFormatDoesnTLookRight(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.theEmailFormatDoesnTLookRight", vi: "Email chưa đúng định dạng.", en: "The email format doesn't look right.", ja: "メールアドレスの形式が正しくありません。", language: language) }
            static var theProfileIsnTReadyToEdit: String { L10n.tr("management.managementauth.theProfileIsnTReadyToEdit", vi: "Hồ sơ hiện chưa sẵn sàng để chỉnh sửa vì phiên đăng nhập chưa được khôi phục.", en: "The profile isn't ready to edit yet because the signed-in session hasn't been restored.", ja: "ログイン状態の復元がまだ完了していないため、プロフィールを編集できません。") }
            static func theProfileIsnTReadyToEdit(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.theProfileIsnTReadyToEdit", vi: "Hồ sơ hiện chưa sẵn sàng để chỉnh sửa vì phiên đăng nhập chưa được khôi phục.", en: "The profile isn't ready to edit yet because the signed-in session hasn't been restored.", ja: "ログイン状態の復元がまだ完了していないため、プロフィールを編集できません。", language: language) }
            static func thisDeviceHasValueRecordsAndThe(_ arg1: String, _ arg2: String) -> String {
                L10n.format("management.managementauth.thisDeviceHasValueRecordsAndThe", vi: "Thiết bị này có %@ bản ghi và đám mây có %@ bản ghi. Vui lòng chọn phương án xử lý để bắt đầu đồng bộ.", en: "This device has %@ records and the cloud has %@ records. Select an option to resolve and start syncing.", ja: "この端末には %@ 件、クラウドには %@ 件のレコードがあります。同期を開始するための解決方法を選択してください。", arg1, arg2)
            }
            static func thisDeviceHasValueRecordsAndThe(_ arg1: String, _ arg2: String, language: MistiaAppLanguage) -> String {
                L10n.format("management.managementauth.thisDeviceHasValueRecordsAndThe", vi: "Thiết bị này có %@ bản ghi và đám mây có %@ bản ghi. Vui lòng chọn phương án xử lý để bắt đầu đồng bộ.", en: "This device has %@ records and the cloud has %@ records. Select an option to resolve and start syncing.", ja: "この端末には %@ 件、クラウドには %@ 件のレコードがあります。同期を開始するための解決方法を選択してください。", language: language, arg1, arg2)
            }
            static var unnamedTransaction: String { L10n.tr("management.managementauth.unnamedTransaction", vi: "Thu chi không tên", en: "Unnamed cashflow item", ja: "無名取引") }
            static func unnamedTransaction(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.unnamedTransaction", vi: "Thu chi không tên", en: "Unnamed cashflow item", ja: "無名取引", language: language) }
            static var uploadLocalDataToTheCloudAnd: String { L10n.tr("management.managementauth.uploadLocalDataToTheCloudAnd", vi: "Ghi đè dữ liệu trên đám mây bằng dữ liệu hiện tại từ thiết bị này.", en: "Replace cloud data with the current data from this device.", ja: "クラウド上のデータをこの端末のデータで上書きします。") }
            static func uploadLocalDataToTheCloudAnd(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.uploadLocalDataToTheCloudAnd", vi: "Ghi đè dữ liệu trên đám mây bằng dữ liệu hiện tại từ thiết bị này.", en: "Replace cloud data with the current data from this device.", ja: "クラウド上のデータをこの端末のデータで上書きします。", language: language) }
            static var useCloud: String { L10n.tr("management.managementauth.useCloud", vi: "Dùng cloud", en: "Use cloud", ja: "Cloud を使用") }
            static func useCloud(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.useCloud", vi: "Dùng cloud", en: "Use cloud", ja: "Cloud を使用", language: language) }
            static var useCloud2: String { L10n.tr("management.managementauth.useCloud2", vi: "Sử dụng dữ liệu đám mây", en: "Use Cloud Data", ja: "クラウドのデータを使用") }
            static func useCloud2(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.useCloud2", vi: "Sử dụng dữ liệu đám mây", en: "Use Cloud Data", ja: "クラウドのデータを使用", language: language) }
            static var useTheSameMistiaAccountToSync: String { L10n.tr("management.managementauth.useTheSameMistiaAccountToSync", vi: "Dùng cùng một tài khoản Mistia để đồng bộ ví, danh mục, thu chi và các mục sắp tới sang thiết bị khác.", en: "Use the same Mistia account to sync wallets, categories, cashflow items, and upcoming items across devices.", ja: "同じミスティアアカウントでウォレット、カテゴリ、取引、計画を別の端末へ同期できます。") }
            static func useTheSameMistiaAccountToSync(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.useTheSameMistiaAccountToSync", vi: "Dùng cùng một tài khoản Mistia để đồng bộ ví, danh mục, thu chi và các mục sắp tới sang thiết bị khác.", en: "Use the same Mistia account to sync wallets, categories, cashflow items, and upcoming items across devices.", ja: "同じミスティアアカウントでウォレット、カテゴリ、取引、計画を別の端末へ同期できます。", language: language) }
            static var useThisDevice: String { L10n.tr("management.managementauth.useThisDevice", vi: "Sử dụng dữ liệu thiết bị", en: "Use Device Data", ja: "端末のデータを使用") }
            static func useThisDevice(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.useThisDevice", vi: "Sử dụng dữ liệu thiết bị", en: "Use Device Data", ja: "端末のデータを使用", language: language) }
            static func valueDataRecordsTotalWalletsValueCards(_ arg1: String, _ arg2: String, _ arg3: String, _ arg4: String, _ arg5: String, _ arg6: String, _ arg7: String, _ arg8: String, _ arg9: String, _ arg10: String, _ arg11: String, _ arg12: String, _ arg13: String) -> String {
                L10n.format("management.managementauth.valueDataRecordsTotalWalletsValueCards", vi: "Tổng %@ bản ghi dữ liệu • Ví %@ • Thẻ %@ • Danh mục %@ • Thu chi %@ • Ngân sách %@ • Mục tiêu %@ • Hóa đơn định kỳ %@ • Trả góp %@ • Kỳ hạn %@ • Hồ sơ %@ • Quyền sở hữu %@ • Audit %@", en: "%@ data records total • Wallets %@ • Cards %@ • Categories %@ • Cashflow %@ • Budgets %@ • Goals %@ • Recurring bills %@ • Installments %@ • To pay occurrences %@ • Profiles %@ • Ownership scopes %@ • Audits %@", ja: "データ %@ 件 • ウォレット %@ • カード %@ • カテゴリ %@ • 取引 %@ • 予算 %@ • 目標 %@ • 定期請求 %@ • 分割払い %@ • 支払予定 %@ • プロフィール %@ • 所有スコープ %@ • 監査 %@", arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10, arg11, arg12, arg13)
            }
            static func valueDataRecordsTotalWalletsValueCards(_ arg1: String, _ arg2: String, _ arg3: String, _ arg4: String, _ arg5: String, _ arg6: String, _ arg7: String, _ arg8: String, _ arg9: String, _ arg10: String, _ arg11: String, _ arg12: String, _ arg13: String, language: MistiaAppLanguage) -> String {
                L10n.format("management.managementauth.valueDataRecordsTotalWalletsValueCards", vi: "Tổng %@ bản ghi dữ liệu • Ví %@ • Thẻ %@ • Danh mục %@ • Thu chi %@ • Ngân sách %@ • Mục tiêu %@ • Hóa đơn định kỳ %@ • Trả góp %@ • Kỳ hạn %@ • Hồ sơ %@ • Quyền sở hữu %@ • Audit %@", en: "%@ data records total • Wallets %@ • Cards %@ • Categories %@ • Cashflow %@ • Budgets %@ • Goals %@ • Recurring bills %@ • Installments %@ • To pay occurrences %@ • Profiles %@ • Ownership scopes %@ • Audits %@", ja: "データ %@ 件 • ウォレット %@ • カード %@ • カテゴリ %@ • 取引 %@ • 予算 %@ • 目標 %@ • 定期請求 %@ • 分割払い %@ • 支払予定 %@ • プロフィール %@ • 所有スコープ %@ • 監査 %@", language: language, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10, arg11, arg12, arg13)
            }
            static var veryStrong: String { L10n.tr("management.managementauth.veryStrong", vi: "Rất mạnh", en: "Very strong", ja: "とても強い") }
            static func veryStrong(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.veryStrong", vi: "Rất mạnh", en: "Very strong", ja: "とても強い", language: language) }
            static var veryWeak: String { L10n.tr("management.managementauth.veryWeak", vi: "Rất yếu", en: "Very weak", ja: "とても弱い") }
            static func veryWeak(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.veryWeak", vi: "Rất yếu", en: "Very weak", ja: "とても弱い", language: language) }
            static var waitingForYourReviewBeforeSync: String { L10n.tr("management.managementauth.waitingForYourReviewBeforeSync", vi: "Đang chờ bạn kiểm tra rồi sync", en: "Waiting for your review before sync", ja: "確認後の手動同期待ち") }
            static func waitingForYourReviewBeforeSync(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.waitingForYourReviewBeforeSync", vi: "Đang chờ bạn kiểm tra rồi sync", en: "Waiting for your review before sync", ja: "確認後の手動同期待ち", language: language) }
            static var weak: String { L10n.tr("management.managementauth.weak", vi: "Yếu", en: "Weak", ja: "弱い") }
            static func weak(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.weak", vi: "Yếu", en: "Weak", ja: "弱い", language: language) }
            static var welcomeToMistia: String { L10n.tr("management.managementauth.welcomeToMistia", vi: "Chào mừng đến với Mistia", en: "Welcome to Mistia", ja: "ミスティアへようこそ") }
            static func welcomeToMistia(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.welcomeToMistia", vi: "Chào mừng đến với Mistia", en: "Welcome to Mistia", ja: "ミスティアへようこそ", language: language) }
            static var whenSyncConflictsOrReviewNeededData: String { L10n.tr("management.managementauth.whenSyncConflictsOrReviewNeededData", vi: "Tất cả thông tin tài chính và thu chi trên các thiết bị của bạn đã hoàn toàn thống nhất.", en: "All your financial records across your devices are fully synchronized.", ja: "すべての端末でデータが正常に同期されています。") }
            static func whenSyncConflictsOrReviewNeededData(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.whenSyncConflictsOrReviewNeededData", vi: "Tất cả thông tin tài chính và thu chi trên các thiết bị của bạn đã hoàn toàn thống nhất.", en: "All your financial records across your devices are fully synchronized.", ja: "すべての端末でデータが正常に同期されています。", language: language) }
            static var youCanAlwaysSignOutDisableSync: String { L10n.tr("management.managementauth.youCanAlwaysSignOutDisableSync", vi: "Bạn luôn có thể đăng xuất, tắt đồng bộ, hoặc xóa tài khoản cloud trong phần Hồ sơ. Dữ liệu local trên thiết bị vẫn được kiểm soát riêng theo các lựa chọn đó.", en: "You can always sign out, disable sync, or delete your cloud account from Profile. Local data on your device remains under the control of those choices.", ja: "プロフィール画面から、ログアウト、同期の無効化、クラウドアカウントの削除をいつでも行えます。ローカルデータはその選択に応じて管理されます。") }
            static func youCanAlwaysSignOutDisableSync(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.youCanAlwaysSignOutDisableSync", vi: "Bạn luôn có thể đăng xuất, tắt đồng bộ, hoặc xóa tài khoản cloud trong phần Hồ sơ. Dữ liệu local trên thiết bị vẫn được kiểm soát riêng theo các lựa chọn đó.", en: "You can always sign out, disable sync, or delete your cloud account from Profile. Local data on your device remains under the control of those choices.", ja: "プロフィール画面から、ログアウト、同期の無効化、クラウドアカウントの削除をいつでも行えます。ローカルデータはその選択に応じて管理されます。", language: language) }
            static var youWillBeSignedOutAndThe: String { L10n.tr("management.managementauth.youWillBeSignedOutAndThe", vi: "Bạn sẽ đăng xuất và toàn bộ dữ liệu của hồ sơ hiện tại trên thiết bị này sẽ bị xóa. Các hồ sơ khác trên thiết bị (nếu có) không bị ảnh hưởng.", en: "You will be signed out and all data for the current profile on this device will be deleted. Other profiles on this device will remain unaffected.", ja: "サインアウトし、この端末にある現在のプロフィールのデータをすべて削除します。端末上の他のプロフィールには影響しません。") }
            static func youWillBeSignedOutAndThe(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.youWillBeSignedOutAndThe", vi: "Bạn sẽ đăng xuất và toàn bộ dữ liệu của hồ sơ hiện tại trên thiết bị này sẽ bị xóa. Các hồ sơ khác trên thiết bị (nếu có) không bị ảnh hưởng.", en: "You will be signed out and all data for the current profile on this device will be deleted. Other profiles on this device will remain unaffected.", ja: "サインアウトし、この端末にある現在のプロフィールのデータをすべて削除します。端末上の他のプロフィールには影響しません。", language: language) }
            static var youWillBeSignedOutOfMistia: String { L10n.tr("management.managementauth.youWillBeSignedOutOfMistia", vi: "Bạn sẽ đăng xuất khỏi tài khoản trên thiết bị này. Dữ liệu hiện có trên thiết bị vẫn được giữ nguyên.", en: "You will be signed out of your account on this device. Existing data on this device will be preserved.", ja: "この端末からアカウントをサインアウトします。端末に保存されているデータはそのまま保持されます。") }
            static func youWillBeSignedOutOfMistia(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.youWillBeSignedOutOfMistia", vi: "Bạn sẽ đăng xuất khỏi tài khoản trên thiết bị này. Dữ liệu hiện có trên thiết bị vẫn được giữ nguyên.", en: "You will be signed out of your account on this device. Existing data on this device will be preserved.", ja: "この端末からアカウントをサインアウトします。端末に保存されているデータはそのまま保持されます。", language: language) }
            static var yourAccountIsWaitingForEmailConfirmation: String { L10n.tr("management.managementauth.yourAccountIsWaitingForEmailConfirmation", vi: "Tài khoản của bạn đang chờ xác nhận email trước khi có thể đăng nhập và bật đồng bộ.", en: "Your account is waiting for email confirmation before it can sign in and start syncing.", ja: "このアカウントはメール確認が完了するまでログインと同期を開始できません。") }
            static func yourAccountIsWaitingForEmailConfirmation(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.yourAccountIsWaitingForEmailConfirmation", vi: "Tài khoản của bạn đang chờ xác nhận email trước khi có thể đăng nhập và bật đồng bộ.", en: "Your account is waiting for email confirmation before it can sign in and start syncing.", ja: "このアカウントはメール確認が完了するまでログインと同期を開始できません。", language: language) }
            static var yourBirthdayCanHelpPersonalizeFutureExperiences: String { L10n.tr("management.managementauth.yourBirthdayCanHelpPersonalizeFutureExperiences", vi: "Ngày sinh giúp cá nhân hóa trải nghiệm trong tương lai, ví dụ các nhắc nhở hoặc thiết lập phù hợp với độ tuổi. Bạn có thể cập nhật lại bất kỳ lúc nào.", en: "Your birthday can help personalize future experiences such as reminders or age-appropriate settings. You can update it anytime.", ja: "生年月日は、将来のリマインダーや年齢に応じた設定などを個人化するために利用される場合があります。いつでも変更できます。") }
            static func yourBirthdayCanHelpPersonalizeFutureExperiences(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.yourBirthdayCanHelpPersonalizeFutureExperiences", vi: "Ngày sinh giúp cá nhân hóa trải nghiệm trong tương lai, ví dụ các nhắc nhở hoặc thiết lập phù hợp với độ tuổi. Bạn có thể cập nhật lại bất kỳ lúc nào.", en: "Your birthday can help personalize future experiences such as reminders or age-appropriate settings. You can update it anytime.", ja: "生年月日は、将来のリマインダーや年齢に応じた設定などを個人化するために利用される場合があります。いつでも変更できます。", language: language) }
            static var yourCloudAccountAndSyncedServerData: String { L10n.tr("management.managementauth.yourCloudAccountAndSyncedServerData", vi: "Tài khoản và dữ liệu đồng bộ trên cloud sẽ bị xóa vĩnh viễn. Dữ liệu local trên máy này vẫn được giữ lại.", en: "Your cloud account and synced server data will be permanently deleted. Local data on this device will remain.", ja: "クラウドアカウントと同期済みサーバーデータは完全に削除されます。この端末のローカルデータは保持されます。") }
            static func yourCloudAccountAndSyncedServerData(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.yourCloudAccountAndSyncedServerData", vi: "Tài khoản và dữ liệu đồng bộ trên cloud sẽ bị xóa vĩnh viễn. Dữ liệu local trên máy này vẫn được giữ lại.", en: "Your cloud account and synced server data will be permanently deleted. Local data on this device will remain.", ja: "クラウドアカウントと同期済みサーバーデータは完全に削除されます。この端末のローカルデータは保持されます。", language: language) }
            static var yourDataIsCurrentlyFullySyncedNo: String { L10n.tr("management.managementauth.yourDataIsCurrentlyFullySyncedNo", vi: "Hiện tại dữ liệu của bạn đã được đồng bộ hoàn toàn, không có bất đồng bộ nào cần xử lý.", en: "Your data is currently fully synced, no conflicts need attention.", ja: "現在、データは完全に同期されており、解決が必要な競合はありません。") }
            static func yourDataIsCurrentlyFullySyncedNo(language: MistiaAppLanguage) -> String { L10n.tr("management.managementauth.yourDataIsCurrentlyFullySyncedNo", vi: "Hiện tại dữ liệu của bạn đã được đồng bộ hoàn toàn, không có bất đồng bộ nào cần xử lý.", en: "Your data is currently fully synced, no conflicts need attention.", ja: "現在、データは完全に同期されており、解決が必要な競合はありません。", language: language) }
        }

        nonisolated enum managementcreditcardstatement {
            static var chargesInCycle: String { L10n.tr("management.managementcreditcardstatement.chargesInCycle", vi: "Chi tiêu trong kỳ", en: "Charges in cycle", ja: "期間内の利用") }
            static func chargesInCycle(language: MistiaAppLanguage) -> String { L10n.tr("management.managementcreditcardstatement.chargesInCycle", vi: "Chi tiêu trong kỳ", en: "Charges in cycle", ja: "期間内の利用", language: language) }
            static var closingDate: String { L10n.tr("management.managementcreditcardstatement.closingDate", vi: "Ngày chốt", en: "Closing date", ja: "締め日") }
            static func closingDate(language: MistiaAppLanguage) -> String { L10n.tr("management.managementcreditcardstatement.closingDate", vi: "Ngày chốt", en: "Closing date", ja: "締め日", language: language) }
            static var due: String { L10n.tr("management.managementcreditcardstatement.due", vi: "Hạn", en: "To pay", ja: "支払") }
            static func due(language: MistiaAppLanguage) -> String { L10n.tr("management.managementcreditcardstatement.due", vi: "Hạn", en: "To pay", ja: "支払", language: language) }
            static var dueDate: String { L10n.tr("management.managementcreditcardstatement.dueDate", vi: "Hạn thanh toán", en: "Due date", ja: "支払期限") }
            static func dueDate(language: MistiaAppLanguage) -> String { L10n.tr("management.managementcreditcardstatement.dueDate", vi: "Hạn thanh toán", en: "Due date", ja: "支払期限", language: language) }
            static var linkedWallet: String { L10n.tr("management.managementcreditcardstatement.linkedWallet", vi: "Ví liên kết", en: "Linked wallet", ja: "連携ウォレット") }
            static func linkedWallet(language: MistiaAppLanguage) -> String { L10n.tr("management.managementcreditcardstatement.linkedWallet", vi: "Ví liên kết", en: "Linked wallet", ja: "連携ウォレット", language: language) }
            static var noChargesInThisCycle: String { L10n.tr("management.managementcreditcardstatement.noChargesInThisCycle", vi: "Không có chi tiêu nào trong kỳ này", en: "No charges in this cycle", ja: "この期間の利用はありません") }
            static func noChargesInThisCycle(language: MistiaAppLanguage) -> String { L10n.tr("management.managementcreditcardstatement.noChargesInThisCycle", vi: "Không có chi tiêu nào trong kỳ này", en: "No charges in this cycle", ja: "この期間の利用はありません", language: language) }
            static var noLinkedWallet: String { L10n.tr("management.managementcreditcardstatement.noLinkedWallet", vi: "Chưa chọn ví liên kết", en: "No linked wallet", ja: "連携ウォレット未設定") }
            static func noLinkedWallet(language: MistiaAppLanguage) -> String { L10n.tr("management.managementcreditcardstatement.noLinkedWallet", vi: "Chưa chọn ví liên kết", en: "No linked wallet", ja: "連携ウォレット未設定", language: language) }
            static var noStatementYet: String { L10n.tr("management.managementcreditcardstatement.noStatementYet", vi: "Chưa có sao kê", en: "No statement yet", ja: "明細はまだありません") }
            static func noStatementYet(language: MistiaAppLanguage) -> String { L10n.tr("management.managementcreditcardstatement.noStatementYet", vi: "Chưa có sao kê", en: "No statement yet", ja: "明細はまだありません", language: language) }
            static var notClosedYet: String { L10n.tr("management.managementcreditcardstatement.notClosedYet", vi: "Chưa chốt", en: "Not closed yet", ja: "未締め") }
            static func notClosedYet(language: MistiaAppLanguage) -> String { L10n.tr("management.managementcreditcardstatement.notClosedYet", vi: "Chưa chốt", en: "Not closed yet", ja: "未締め", language: language) }
            static var notice: String { L10n.tr("management.managementcreditcardstatement.notice", vi: "Thông báo", en: "Notice", ja: "お知らせ") }
            static func notice(language: MistiaAppLanguage) -> String { L10n.tr("management.managementcreditcardstatement.notice", vi: "Thông báo", en: "Notice", ja: "お知らせ", language: language) }
            static var overdue: String { L10n.tr("management.managementcreditcardstatement.overdue", vi: "Quá hạn", en: "Overdue", ja: "延滞") }
            static func overdue(language: MistiaAppLanguage) -> String { L10n.tr("management.managementcreditcardstatement.overdue", vi: "Quá hạn", en: "Overdue", ja: "延滞", language: language) }
            static var paid: String { L10n.tr("management.managementcreditcardstatement.paid", vi: "Đã thanh toán", en: "Paid", ja: "支払い済み") }
            static func paid(language: MistiaAppLanguage) -> String { L10n.tr("management.managementcreditcardstatement.paid", vi: "Đã thanh toán", en: "Paid", ja: "支払い済み", language: language) }
            static var payNow: String { L10n.tr("management.managementcreditcardstatement.payNow", vi: "Thanh toán ngay", en: "Pay now", ja: "今すぐ支払う") }
            static func payNow(language: MistiaAppLanguage) -> String { L10n.tr("management.managementcreditcardstatement.payNow", vi: "Thanh toán ngay", en: "Pay now", ja: "今すぐ支払う", language: language) }
            static var payable: String { L10n.tr("management.managementcreditcardstatement.payable", vi: "Cần thanh toán", en: "Payable", ja: "支払い可能") }
            static func payable(language: MistiaAppLanguage) -> String { L10n.tr("management.managementcreditcardstatement.payable", vi: "Cần thanh toán", en: "Payable", ja: "支払い可能", language: language) }
            static var pleaseSetALinkedPaymentWalletFor: String { L10n.tr("management.managementcreditcardstatement.pleaseSetALinkedPaymentWalletFor", vi: "Vui lòng thiết lập ví liên kết cho thẻ này.", en: "Please set a linked payment wallet for this card.", ja: "このカードの連携支払いウォレットを設定してください。") }
            static func pleaseSetALinkedPaymentWalletFor(language: MistiaAppLanguage) -> String { L10n.tr("management.managementcreditcardstatement.pleaseSetALinkedPaymentWalletFor", vi: "Vui lòng thiết lập ví liên kết cho thẻ này.", en: "Please set a linked payment wallet for this card.", ja: "このカードの連携支払いウォレットを設定してください。", language: language) }
            static var statementPaid: String { L10n.tr("management.managementcreditcardstatement.statementPaid", vi: "Đã thanh toán sao kê.", en: "Statement paid.", ja: "明細を支払いました。") }
            static func statementPaid(language: MistiaAppLanguage) -> String { L10n.tr("management.managementcreditcardstatement.statementPaid", vi: "Đã thanh toán sao kê.", en: "Statement paid.", ja: "明細を支払いました。", language: language) }
            static var statementPeriod: String { L10n.tr("management.managementcreditcardstatement.statementPeriod", vi: "Kỳ sao kê", en: "Statement period", ja: "明細期間") }
            static func statementPeriod(language: MistiaAppLanguage) -> String { L10n.tr("management.managementcreditcardstatement.statementPeriod", vi: "Kỳ sao kê", en: "Statement period", ja: "明細期間", language: language) }
            static var theLinkedWalletBalanceIsNotEnough: String { L10n.tr("management.managementcreditcardstatement.theLinkedWalletBalanceIsNotEnough", vi: "Số dư ví liên kết không đủ để thanh toán sao kê này.", en: "The linked wallet balance is not enough for this statement.", ja: "連携ウォレットの残高がこの明細の支払いに不足しています。") }
            static func theLinkedWalletBalanceIsNotEnough(language: MistiaAppLanguage) -> String { L10n.tr("management.managementcreditcardstatement.theLinkedWalletBalanceIsNotEnough", vi: "Số dư ví liên kết không đủ để thanh toán sao kê này.", en: "The linked wallet balance is not enough for this statement.", ja: "連携ウォレットの残高がこの明細の支払いに不足しています。", language: language) }
            static var thisCardHasNoSpendingDataFor: String { L10n.tr("management.managementcreditcardstatement.thisCardHasNoSpendingDataFor", vi: "Thẻ này chưa có dữ liệu chi tiêu trong tháng đã chọn.", en: "This card has no spending data for the selected month.", ja: "選択した月の利用データはありません。") }
            static func thisCardHasNoSpendingDataFor(language: MistiaAppLanguage) -> String { L10n.tr("management.managementcreditcardstatement.thisCardHasNoSpendingDataFor", vi: "Thẻ này chưa có dữ liệu chi tiêu trong tháng đã chọn.", en: "This card has no spending data for the selected month.", ja: "選択した月の利用データはありません。", language: language) }
            static var totalDue: String { L10n.tr("management.managementcreditcardstatement.totalDue", vi: "Tổng cần trả", en: "Total to pay", ja: "支払い合計") }
            static func totalDue(language: MistiaAppLanguage) -> String { L10n.tr("management.managementcreditcardstatement.totalDue", vi: "Tổng cần trả", en: "Total to pay", ja: "支払い合計", language: language) }
        }

        nonisolated enum profilePrivacy {
            static var mistiaUsesThisInformationToShow: String { L10n.tr("management.profilePrivacy.mistiaUsesThisInformationToShow", vi: "Thông tin này được dùng để hiển thị hồ sơ trong màn quản lý, các form liên quan đến tài khoản, quyền truy cập và những khu vực cần biết ai đang thao tác. Việc sử dụng dữ liệu được giới hạn trong phạm vi cần thiết cho trải nghiệm quản lý tài khoản và không yêu cầu thêm thông tin ngoài mục đích bạn đang thực hiện.", en: "This information is used to show your profile in management screens, account-related forms, access controls, and places where the app needs to identify who is acting. Data use is limited to what is necessary for the account experience and does not require extra information beyond the task you are performing.", ja: "この情報は、管理画面、アカウント関連フォーム、アクセス権、誰が操作しているかを示す必要がある場所でプロフィールを表示するために使用されます。データの利用はアカウント体験に必要な範囲に限られ、実行中の目的を超える追加情報は求めません。") }
            static func mistiaUsesThisInformationToShow(language: MistiaAppLanguage) -> String { L10n.tr("management.profilePrivacy.mistiaUsesThisInformationToShow", vi: "Thông tin này được dùng để hiển thị hồ sơ trong màn quản lý, các form liên quan đến tài khoản, quyền truy cập và những khu vực cần biết ai đang thao tác. Việc sử dụng dữ liệu được giới hạn trong phạm vi cần thiết cho trải nghiệm quản lý tài khoản và không yêu cầu thêm thông tin ngoài mục đích bạn đang thực hiện.", en: "This information is used to show your profile in management screens, account-related forms, access controls, and places where the app needs to identify who is acting. Data use is limited to what is necessary for the account experience and does not require extra information beyond the task you are performing.", ja: "この情報は、管理画面、アカウント関連フォーム、アクセス権、誰が操作しているかを示す必要がある場所でプロフィールを表示するために使用されます。データの利用はアカウント体験に必要な範囲に限られ、実行中の目的を超える追加情報は求めません。", language: language) }
            static var personalInformationPrivacy: String { L10n.tr("management.profilePrivacy.personalInformationPrivacy", vi: "Thông tin cá nhân & Bảo mật", en: "Personal Information & Privacy", ja: "個人情報とプライバシー") }
            static func personalInformationPrivacy(language: MistiaAppLanguage) -> String { L10n.tr("management.profilePrivacy.personalInformationPrivacy", vi: "Thông tin cá nhân & Bảo mật", en: "Personal Information & Privacy", ja: "個人情報とプライバシー", language: language) }
            static var profileChangesUseYourSignedIn: String { L10n.tr("management.profilePrivacy.profileChangesUseYourSignedIn", vi: "Thay đổi hồ sơ được thực hiện trong phiên đăng nhập của bạn và nên được bảo vệ bằng các cơ chế bảo mật của iOS như khóa thiết bị, quyền truy cập ảnh hoặc camera và xác thực tài khoản. Khi bạn chọn ảnh đại diện, chỉ ảnh bạn chọn mới được dùng cho hồ sơ; Mistia không cần xem toàn bộ thư viện ngoài quyền bạn cấp tại thời điểm chọn.", en: "Profile changes happen inside your signed-in session and should be protected by iOS security controls such as device lock, photo or camera permissions, and account authentication. When you choose a profile photo, only the photo you select is used for the profile; Mistia does not need broad access to your library beyond the permission you grant at the moment you choose it.", ja: "プロフィールの変更はサインイン中のセッション内で行われ、デバイスロック、写真またはカメラの権限、アカウント認証などの iOS の保護機能で守られるべきものです。プロフィール写真を選ぶ場合、使用されるのは選択した写真だけで、選択時に許可した範囲を超えてライブラリ全体を見る必要はありません。") }
            static func profileChangesUseYourSignedIn(language: MistiaAppLanguage) -> String { L10n.tr("management.profilePrivacy.profileChangesUseYourSignedIn", vi: "Thay đổi hồ sơ được thực hiện trong phiên đăng nhập của bạn và nên được bảo vệ bằng các cơ chế bảo mật của iOS như khóa thiết bị, quyền truy cập ảnh hoặc camera và xác thực tài khoản. Khi bạn chọn ảnh đại diện, chỉ ảnh bạn chọn mới được dùng cho hồ sơ; Mistia không cần xem toàn bộ thư viện ngoài quyền bạn cấp tại thời điểm chọn.", en: "Profile changes happen inside your signed-in session and should be protected by iOS security controls such as device lock, photo or camera permissions, and account authentication. When you choose a profile photo, only the photo you select is used for the profile; Mistia does not need broad access to your library beyond the permission you grant at the moment you choose it.", ja: "プロフィールの変更はサインイン中のセッション内で行われ、デバイスロック、写真またはカメラの権限、アカウント認証などの iOS の保護機能で守られるべきものです。プロフィール写真を選ぶ場合、使用されるのは選択した写真だけで、選択時に許可した範囲を超えてライブラリ全体を見る必要はありません。", language: language) }
            static var profileInformationHelpsMistiaKeepYour: String { L10n.tr("management.profilePrivacy.profileInformationHelpsMistiaKeepYour", vi: "Hồ sơ giúp hiển thị đúng tên, ảnh đại diện và thông tin tài khoản cơ bản của bạn. Dữ liệu hồ sơ được dùng để nhận diện bạn trong ứng dụng, bảo vệ quyền kiểm soát của bạn và giải thích rõ nơi thông tin có thể xuất hiện.", en: "Your profile helps show the right name, avatar, and basic account information. Profile data is used to identify you in the app, protect your control, and explain clearly where that information may appear.", ja: "プロフィールは、正しい名前、アバター、基本的なアカウント情報を表示するために使われます。プロフィールデータは、アプリ内であなたを識別し、利用者のコントロールを守り、どこに情報が表示されるかを明確にするために使用されます。") }
            static func profileInformationHelpsMistiaKeepYour(language: MistiaAppLanguage) -> String { L10n.tr("management.profilePrivacy.profileInformationHelpsMistiaKeepYour", vi: "Hồ sơ giúp hiển thị đúng tên, ảnh đại diện và thông tin tài khoản cơ bản của bạn. Dữ liệu hồ sơ được dùng để nhận diện bạn trong ứng dụng, bảo vệ quyền kiểm soát của bạn và giải thích rõ nơi thông tin có thể xuất hiện.", en: "Your profile helps show the right name, avatar, and basic account information. Profile data is used to identify you in the app, protect your control, and explain clearly where that information may appear.", ja: "プロフィールは、正しい名前、アバター、基本的なアカウント情報を表示するために使われます。プロフィールデータは、アプリ内であなたを識別し、利用者のコントロールを守り、どこに情報が表示されるかを明確にするために使用されます。", language: language) }
            static var sensitivePersonalDetailsShouldOnlyBe: String { L10n.tr("management.profilePrivacy.sensitivePersonalDetailsShouldOnlyBe", vi: "Các thông tin nhạy cảm hơn, như ngày sinh, chỉ nên được cung cấp khi cần cho trải nghiệm tài khoản, độ tuổi hoặc quyền truy cập. Bạn có thể để trống các mục không bắt buộc; những gì bạn không nhập sẽ không được dùng để cá nhân hóa hoặc hiển thị trong hồ sơ.", en: "More sensitive details, such as birthday, should be provided only when needed for the account experience, age handling, or access rules. You can leave optional fields blank; information you do not enter is not used for personalization or profile display.", ja: "誕生日など、より慎重に扱うべき情報は、アカウント体験、年齢に関する扱い、アクセス権に必要な場合だけ入力するものです。任意項目は空のままにでき、入力しない情報がパーソナライズやプロフィール表示に使われることはありません。") }
            static func sensitivePersonalDetailsShouldOnlyBe(language: MistiaAppLanguage) -> String { L10n.tr("management.profilePrivacy.sensitivePersonalDetailsShouldOnlyBe", vi: "Các thông tin nhạy cảm hơn, như ngày sinh, chỉ nên được cung cấp khi cần cho trải nghiệm tài khoản, độ tuổi hoặc quyền truy cập. Bạn có thể để trống các mục không bắt buộc; những gì bạn không nhập sẽ không được dùng để cá nhân hóa hoặc hiển thị trong hồ sơ.", en: "More sensitive details, such as birthday, should be provided only when needed for the account experience, age handling, or access rules. You can leave optional fields blank; information you do not enter is not used for personalization or profile display.", ja: "誕生日など、より慎重に扱うべき情報は、アカウント体験、年齢に関する扱い、アクセス権に必要な場合だけ入力するものです。任意項目は空のままにでき、入力しない情報がパーソナライズやプロフィール表示に使われることはありません。", language: language) }
            static var youStayInControlOfProfile: String { L10n.tr("management.profilePrivacy.youStayInControlOfProfile", vi: "Bạn vẫn kiểm soát hồ sơ của mình: có thể sửa tên, đổi ảnh, đăng xuất hoặc xóa tài khoản theo các lựa chọn trong ứng dụng. Nếu một thông tin xuất hiện ở nơi có người khác cùng sử dụng Mistia, màn hình đó chỉ nên hiển thị phần cần thiết như tên hoặc avatar để nhận biết đúng người, không phải toàn bộ thông tin cá nhân.", en: "You stay in control of your profile: you can edit your name, change your photo, sign out, or delete the account using the choices in the app. If information appears where another Mistia user may see it, that screen should show only what is needed to recognize the right person, such as name or avatar, not the full set of personal details.", ja: "プロフィールの管理は利用者自身が行えます。アプリ内の選択肢から名前の編集、写真の変更、サインアウト、アカウント削除ができます。他のミスティア利用者が見る可能性のある場所に情報が表示される場合も、正しい人を識別するために必要な名前やアバターなどに限り、個人情報全体を表示しないことを前提にしています。") }
            static func youStayInControlOfProfile(language: MistiaAppLanguage) -> String { L10n.tr("management.profilePrivacy.youStayInControlOfProfile", vi: "Bạn vẫn kiểm soát hồ sơ của mình: có thể sửa tên, đổi ảnh, đăng xuất hoặc xóa tài khoản theo các lựa chọn trong ứng dụng. Nếu một thông tin xuất hiện ở nơi có người khác cùng sử dụng Mistia, màn hình đó chỉ nên hiển thị phần cần thiết như tên hoặc avatar để nhận biết đúng người, không phải toàn bộ thông tin cá nhân.", en: "You stay in control of your profile: you can edit your name, change your photo, sign out, or delete the account using the choices in the app. If information appears where another Mistia user may see it, that screen should show only what is needed to recognize the right person, such as name or avatar, not the full set of personal details.", ja: "プロフィールの管理は利用者自身が行えます。アプリ内の選択肢から名前の編集、写真の変更、サインアウト、アカウント削除ができます。他のミスティア利用者が見る可能性のある場所に情報が表示される場合も、正しい人を識別するために必要な名前やアバターなどに限り、個人情報全体を表示しないことを前提にしています。", language: language) }
            static var yourNameProfilePhotoEmailAnd: String { L10n.tr("management.profilePrivacy.yourNameProfilePhotoEmailAnd", vi: "Tên, ảnh đại diện, email và ngày sinh (nếu bạn thêm) là thông tin có thể liên kết với tài khoản của bạn. Những dữ liệu này được dùng để nhận diện hồ sơ, hỗ trợ đăng nhập, hiển thị thông tin tài khoản và giúp bạn phân biệt dữ liệu của mình với dữ liệu của người khác trên cùng thiết bị.", en: "Your name, profile photo, email, and birthday if you add one are information that can be linked to your account. These details are used to identify the profile, support sign-in, show account information, and help separate your data from other people's data on the same device.", ja: "名前、プロフィール写真、メールアドレス、入力した場合の誕生日は、アカウントに紐づく可能性のある情報です。これらはプロフィールの識別、サインインの補助、アカウント情報の表示、同じデバイス上の他の人のデータとの区別に使われます。") }
            static func yourNameProfilePhotoEmailAnd(language: MistiaAppLanguage) -> String { L10n.tr("management.profilePrivacy.yourNameProfilePhotoEmailAnd", vi: "Tên, ảnh đại diện, email và ngày sinh (nếu bạn thêm) là thông tin có thể liên kết với tài khoản của bạn. Những dữ liệu này được dùng để nhận diện hồ sơ, hỗ trợ đăng nhập, hiển thị thông tin tài khoản và giúp bạn phân biệt dữ liệu của mình với dữ liệu của người khác trên cùng thiết bị.", en: "Your name, profile photo, email, and birthday if you add one are information that can be linked to your account. These details are used to identify the profile, support sign-in, show account information, and help separate your data from other people's data on the same device.", ja: "名前、プロフィール写真、メールアドレス、入力した場合の誕生日は、アカウントに紐づく可能性のある情報です。これらはプロフィールの識別、サインインの補助、アカウント情報の表示、同じデバイス上の他の人のデータとの区別に使われます。", language: language) }
        }

        nonisolated enum walletEditor {
            static var editTitle: String { L10n.tr("management.walletEditor.editTitle", vi: "Sửa ví", en: "Edit wallet", ja: "ウォレットを編集") }
            static func editTitle(language: MistiaAppLanguage) -> String { L10n.tr("management.walletEditor.editTitle", vi: "Sửa ví", en: "Edit wallet", ja: "ウォレットを編集", language: language) }
            static var newTitle: String { L10n.tr("management.walletEditor.newTitle", vi: "Ví mới", en: "New wallet", ja: "新しいウォレット") }
            static func newTitle(language: MistiaAppLanguage) -> String { L10n.tr("management.walletEditor.newTitle", vi: "Ví mới", en: "New wallet", ja: "新しいウォレット", language: language) }
        }
    }

    nonisolated enum notifications {

        nonisolated enum creditCard {
            static func autoPaymentFailedBody(_ arg1: String, _ arg2: String, _ arg3: String) -> String {
                L10n.format("notifications.creditCard.autoPaymentFailedBody", vi: "Không thể tự động thanh toán sao kê tháng %@ của thẻ %@ vì %@. Vui lòng nạp thêm tiền hoặc thanh toán thủ công.", en: "Mistia could not auto-pay %@ statement for %@ because %@. Please add funds or pay manually.", ja: "%@ の %@ は %@ のため自動支払いできませんでした。入金するか手動で支払ってください。", arg1, arg2, arg3)
            }
            static func autoPaymentFailedBody(_ arg1: String, _ arg2: String, _ arg3: String, language: MistiaAppLanguage) -> String {
                L10n.format("notifications.creditCard.autoPaymentFailedBody", vi: "Không thể tự động thanh toán sao kê tháng %@ của thẻ %@ vì %@. Vui lòng nạp thêm tiền hoặc thanh toán thủ công.", en: "Mistia could not auto-pay %@ statement for %@ because %@. Please add funds or pay manually.", ja: "%@ の %@ は %@ のため自動支払いできませんでした。入金するか手動で支払ってください。", language: language, arg1, arg2, arg3)
            }
            static func statementReadyBody(_ arg1: String, _ arg2: String, _ arg3: String, _ arg4: String) -> String {
                L10n.format("notifications.creditCard.statementReadyBody", vi: "Số tiền cần trả tháng %@ của thẻ %@ là %@. Hạn %@.", en: "%@ statement for %@ needs %@ by %@.", ja: "%@ の %@ は %@ までに %@ の支払いが必要です。", arg1, arg2, arg3, arg4)
            }
            static func statementReadyBody(_ arg1: String, _ arg2: String, _ arg3: String, _ arg4: String, language: MistiaAppLanguage) -> String {
                L10n.format("notifications.creditCard.statementReadyBody", vi: "Số tiền cần trả tháng %@ của thẻ %@ là %@. Hạn %@.", en: "%@ statement for %@ needs %@ by %@.", ja: "%@ の %@ は %@ までに %@ の支払いが必要です。", language: language, arg1, arg2, arg3, arg4)
            }
        }

        nonisolated enum notificationcenter {
            static var aMember: String { L10n.tr("notifications.notificationcenter.aMember", vi: "Một thành viên", en: "A member", ja: "メンバー") }
            static func aMember(language: MistiaAppLanguage) -> String { L10n.tr("notifications.notificationcenter.aMember", vi: "Một thành viên", en: "A member", ja: "メンバー", language: language) }
            static var access: String { L10n.tr("notifications.notificationcenter.access", vi: "truy cập", en: "access", ja: "アクセス") }
            static func access(language: MistiaAppLanguage) -> String { L10n.tr("notifications.notificationcenter.access", vi: "truy cập", en: "access", ja: "アクセス", language: language) }
            static var approve: String { L10n.tr("notifications.notificationcenter.approve", vi: "Chấp thuận", en: "Approve", ja: "承認") }
            static func approve(language: MistiaAppLanguage) -> String { L10n.tr("notifications.notificationcenter.approve", vi: "Chấp thuận", en: "Approve", ja: "承認", language: language) }
            static var approved: String { L10n.tr("notifications.notificationcenter.approved", vi: "Đã chấp thuận", en: "Approved", ja: "承認済み") }
            static func approved(language: MistiaAppLanguage) -> String { L10n.tr("notifications.notificationcenter.approved", vi: "Đã chấp thuận", en: "Approved", ja: "承認済み", language: language) }
            static var approved2: String { L10n.tr("notifications.notificationcenter.approved2", vi: "đã chấp thuận", en: "approved", ja: "が承認しました") }
            static func approved2(language: MistiaAppLanguage) -> String { L10n.tr("notifications.notificationcenter.approved2", vi: "đã chấp thuận", en: "approved", ja: "が承認しました", language: language) }
            static var approved3: String { L10n.tr("notifications.notificationcenter.approved3", vi: "đã được chấp thuận", en: "approved", ja: "が承認されました") }
            static func approved3(language: MistiaAppLanguage) -> String { L10n.tr("notifications.notificationcenter.approved3", vi: "đã được chấp thuận", en: "approved", ja: "が承認されました", language: language) }
            static var changed: String { L10n.tr("notifications.notificationcenter.changed", vi: "vừa thay đổi", en: "changed", ja: "変更") }
            static func changed(language: MistiaAppLanguage) -> String { L10n.tr("notifications.notificationcenter.changed", vi: "vừa thay đổi", en: "changed", ja: "変更", language: language) }
            static var couldnTRespond: String { L10n.tr("notifications.notificationcenter.couldnTRespond", vi: "Chưa thể phản hồi", en: "Couldn't respond", ja: "返信できませんでした") }
            static func couldnTRespond(language: MistiaAppLanguage) -> String { L10n.tr("notifications.notificationcenter.couldnTRespond", vi: "Chưa thể phản hồi", en: "Couldn't respond", ja: "返信できませんでした", language: language) }
            static var created: String { L10n.tr("notifications.notificationcenter.created", vi: "vừa tạo mới", en: "created", ja: "作成") }
            static func created(language: MistiaAppLanguage) -> String { L10n.tr("notifications.notificationcenter.created", vi: "vừa tạo mới", en: "created", ja: "作成", language: language) }
            static var deleted: String { L10n.tr("notifications.notificationcenter.deleted", vi: "vừa xóa", en: "deleted", ja: "削除") }
            static func deleted(language: MistiaAppLanguage) -> String { L10n.tr("notifications.notificationcenter.deleted", vi: "vừa xóa", en: "deleted", ja: "削除", language: language) }

            nonisolated enum group {
                static var access: String { L10n.tr("notifications.notificationcenter.group.access", vi: "Quyền truy cập", en: "Access", ja: "アクセス権") }
                static func access(language: MistiaAppLanguage) -> String { L10n.tr("notifications.notificationcenter.group.access", vi: "Quyền truy cập", en: "Access", ja: "アクセス権", language: language) }
                static var actionRequests: String { L10n.tr("notifications.notificationcenter.group.actionRequests", vi: "Yêu cầu cần xử lý", en: "Requests to review", ja: "確認が必要な依頼") }
                static func actionRequests(language: MistiaAppLanguage) -> String { L10n.tr("notifications.notificationcenter.group.actionRequests", vi: "Yêu cầu cần xử lý", en: "Requests to review", ja: "確認が必要な依頼", language: language) }
                static var bills: String { L10n.tr("notifications.notificationcenter.group.bills", vi: "Hóa đơn & khoản trả", en: "Bills & payments", ja: "請求と支払い") }
                static func bills(language: MistiaAppLanguage) -> String { L10n.tr("notifications.notificationcenter.group.bills", vi: "Hóa đơn & khoản trả", en: "Bills & payments", ja: "請求と支払い", language: language) }
                static var budgets: String { L10n.tr("notifications.notificationcenter.group.budgets", vi: "Ngân sách", en: "Budgets", ja: "予算") }
                static func budgets(language: MistiaAppLanguage) -> String { L10n.tr("notifications.notificationcenter.group.budgets", vi: "Ngân sách", en: "Budgets", ja: "予算", language: language) }
                static var creditCards: String { L10n.tr("notifications.notificationcenter.group.creditCards", vi: "Thẻ tín dụng", en: "Credit cards", ja: "クレジットカード") }
                static func creditCards(language: MistiaAppLanguage) -> String { L10n.tr("notifications.notificationcenter.group.creditCards", vi: "Thẻ tín dụng", en: "Credit cards", ja: "クレジットカード", language: language) }
                static var familyCashflow: String { L10n.tr("notifications.notificationcenter.group.familyCashflow", vi: "Thu chi gia đình", en: "Family cashflow", ja: "家族の収支") }
                static func familyCashflow(language: MistiaAppLanguage) -> String { L10n.tr("notifications.notificationcenter.group.familyCashflow", vi: "Thu chi gia đình", en: "Family cashflow", ja: "家族の収支", language: language) }
                static var familyData: String { L10n.tr("notifications.notificationcenter.group.familyData", vi: "Dữ liệu gia đình", en: "Family data", ja: "家族データ") }
                static func familyData(language: MistiaAppLanguage) -> String { L10n.tr("notifications.notificationcenter.group.familyData", vi: "Dữ liệu gia đình", en: "Family data", ja: "家族データ", language: language) }
                static var wallets: String { L10n.tr("notifications.notificationcenter.group.wallets", vi: "Ví", en: "Wallets", ja: "ウォレット") }
                static func wallets(language: MistiaAppLanguage) -> String { L10n.tr("notifications.notificationcenter.group.wallets", vi: "Ví", en: "Wallets", ja: "ウォレット", language: language) }
            }
            static var markAllAsRead: String { L10n.tr("notifications.notificationcenter.markAllAsRead", vi: "Đọc hết", en: "Mark all as read", ja: "すべて既読") }
            static func markAllAsRead(language: MistiaAppLanguage) -> String { L10n.tr("notifications.notificationcenter.markAllAsRead", vi: "Đọc hết", en: "Mark all as read", ja: "すべて既読", language: language) }
            static var member: String { L10n.tr("notifications.notificationcenter.member", vi: "Thành viên", en: "Member", ja: "メンバー") }
            static func member(language: MistiaAppLanguage) -> String { L10n.tr("notifications.notificationcenter.member", vi: "Thành viên", en: "Member", ja: "メンバー", language: language) }
            static var mistiaCouldnTSendThisResponseYet: String { L10n.tr("notifications.notificationcenter.mistiaCouldnTSendThisResponseYet", vi: "Mistia chưa gửi được phản hồi. Hãy thử lại sau khi đồng bộ ổn định.", en: "Mistia couldn't send this response yet. Try again when sync is stable.", ja: "まだ返信を送信できません。同期が安定してからもう一度お試しください。") }
            static func mistiaCouldnTSendThisResponseYet(language: MistiaAppLanguage) -> String { L10n.tr("notifications.notificationcenter.mistiaCouldnTSendThisResponseYet", vi: "Mistia chưa gửi được phản hồi. Hãy thử lại sau khi đồng bộ ổn định.", en: "Mistia couldn't send this response yet. Try again when sync is stable.", ja: "まだ返信を送信できません。同期が安定してからもう一度お試しください。", language: language) }
            static var newMember: String { L10n.tr("notifications.notificationcenter.newMember", vi: "Thành viên mới", en: "New member", ja: "新しいメンバー") }
            static func newMember(language: MistiaAppLanguage) -> String { L10n.tr("notifications.notificationcenter.newMember", vi: "Thành viên mới", en: "New member", ja: "新しいメンバー", language: language) }
            static var noNotificationsYet: String { L10n.tr("notifications.notificationcenter.noNotificationsYet", vi: "Chưa có thông báo", en: "No notifications yet", ja: "通知はまだありません") }
            static func noNotificationsYet(language: MistiaAppLanguage) -> String { L10n.tr("notifications.notificationcenter.noNotificationsYet", vi: "Chưa có thông báo", en: "No notifications yet", ja: "通知はまだありません", language: language) }
            static var notificationActions: String { L10n.tr("notifications.notificationcenter.notificationActions", vi: "Tác vụ thông báo", en: "Notification actions", ja: "通知アクション") }
            static func notificationActions(language: MistiaAppLanguage) -> String { L10n.tr("notifications.notificationcenter.notificationActions", vi: "Tác vụ thông báo", en: "Notification actions", ja: "通知アクション", language: language) }
            static var notifications: String { L10n.tr("notifications.notificationcenter.notifications", vi: "Thông báo", en: "Notifications", ja: "通知") }
            static func notifications(language: MistiaAppLanguage) -> String { L10n.tr("notifications.notificationcenter.notifications", vi: "Thông báo", en: "Notifications", ja: "通知", language: language) }
            static var permissionRequestApprovedBody: String { L10n.tr("notifications.notificationcenter.permissionRequestApprovedBody", vi: "Yêu cầu đã được chấp nhận. Quyền của thành viên đã được cập nhật.", en: "The request was approved. This member's access has been updated.", ja: "リクエストを承認しました。このメンバーのアクセス権が更新されました。") }
            static func permissionRequestApprovedBody(language: MistiaAppLanguage) -> String { L10n.tr("notifications.notificationcenter.permissionRequestApprovedBody", vi: "Yêu cầu đã được chấp nhận. Quyền của thành viên đã được cập nhật.", en: "The request was approved. This member's access has been updated.", ja: "リクエストを承認しました。このメンバーのアクセス権が更新されました。", language: language) }
            static var permissionRequestRejectedBody: String { L10n.tr("notifications.notificationcenter.permissionRequestRejectedBody", vi: "Yêu cầu đã bị từ chối. Quyền của thành viên không thay đổi.", en: "The request was rejected. This member's access was not changed.", ja: "リクエストを拒否しました。このメンバーのアクセス権は変更されていません。") }
            static func permissionRequestRejectedBody(language: MistiaAppLanguage) -> String { L10n.tr("notifications.notificationcenter.permissionRequestRejectedBody", vi: "Yêu cầu đã bị từ chối. Quyền của thành viên không thay đổi.", en: "The request was rejected. This member's access was not changed.", ja: "リクエストを拒否しました。このメンバーのアクセス権は変更されていません。", language: language) }
            static var permissionRequestsAndFamilyActivityWillAppear: String { L10n.tr("notifications.notificationcenter.permissionRequestsAndFamilyActivityWillAppear", vi: "Yêu cầu quyền và hoạt động gia đình sẽ xuất hiện tại đây sau khi đồng bộ.", en: "Permission requests and family activity will appear here after sync.", ja: "権限リクエストと家族のアクティビティは同期後にここに表示されます。") }
            static func permissionRequestsAndFamilyActivityWillAppear(language: MistiaAppLanguage) -> String { L10n.tr("notifications.notificationcenter.permissionRequestsAndFamilyActivityWillAppear", vi: "Yêu cầu quyền và hoạt động gia đình sẽ xuất hiện tại đây sau khi đồng bộ.", en: "Permission requests and family activity will appear here after sync.", ja: "権限リクエストと家族のアクティビティは同期後にここに表示されます。", language: language) }
            static var reject: String { L10n.tr("notifications.notificationcenter.reject", vi: "Từ chối", en: "Reject", ja: "拒否") }
            static func reject(language: MistiaAppLanguage) -> String { L10n.tr("notifications.notificationcenter.reject", vi: "Từ chối", en: "Reject", ja: "拒否", language: language) }
            static var rejected: String { L10n.tr("notifications.notificationcenter.rejected", vi: "Đã từ chối", en: "Rejected", ja: "拒否済み") }
            static func rejected(language: MistiaAppLanguage) -> String { L10n.tr("notifications.notificationcenter.rejected", vi: "Đã từ chối", en: "Rejected", ja: "拒否済み", language: language) }
            static var rejected2: String { L10n.tr("notifications.notificationcenter.rejected2", vi: "đã từ chối", en: "rejected", ja: "が拒否しました") }
            static func rejected2(language: MistiaAppLanguage) -> String { L10n.tr("notifications.notificationcenter.rejected2", vi: "đã từ chối", en: "rejected", ja: "が拒否しました", language: language) }
            static var rejected3: String { L10n.tr("notifications.notificationcenter.rejected3", vi: "bị từ chối", en: "rejected", ja: "が拒否されました") }
            static func rejected3(language: MistiaAppLanguage) -> String { L10n.tr("notifications.notificationcenter.rejected3", vi: "bị từ chối", en: "rejected", ja: "が拒否されました", language: language) }
            static func revokedValueAccess(_ value: String) -> String {
                L10n.format("notifications.notificationcenter.revokedValueAccess", vi: "Đã thu hồi quyền %@", en: "Revoked %@ access", ja: "%@の権限が取り消されました", value)
            }
            static func revokedValueAccess(_ value: String, language: MistiaAppLanguage) -> String {
                L10n.format("notifications.notificationcenter.revokedValueAccess", vi: "Đã thu hồi quyền %@", en: "Revoked %@ access", ja: "%@の権限が取り消されました", language: language, value)
            }
            static var tapToAddFundsToWallet: String { L10n.tr("notifications.notificationcenter.tapToAddFundsToWallet", vi: "Chạm vào để nạp tiền vào ví", en: "Tap to add funds to wallet", ja: "タップしてウォレットに入金") }
            static func tapToAddFundsToWallet(language: MistiaAppLanguage) -> String { L10n.tr("notifications.notificationcenter.tapToAddFundsToWallet", vi: "Chạm vào để nạp tiền vào ví", en: "Tap to add funds to wallet", ja: "タップしてウォレットに入金", language: language) }
            static var tapToOpenTheStatementAndPay: String { L10n.tr("notifications.notificationcenter.tapToOpenTheStatementAndPay", vi: "Chạm để mở sao kê và thanh toán", en: "Tap to open the statement and pay", ja: "タップして明細を開いて支払う") }
            static func tapToOpenTheStatementAndPay(language: MistiaAppLanguage) -> String { L10n.tr("notifications.notificationcenter.tapToOpenTheStatementAndPay", vi: "Chạm để mở sao kê và thanh toán", en: "Tap to open the statement and pay", ja: "タップして明細を開いて支払う", language: language) }
            static var tapToPay: String { L10n.tr("notifications.notificationcenter.tapToPay", vi: "Chạm để thanh toán", en: "Tap to pay", ja: "タップして支払う") }
            static func tapToPay(language: MistiaAppLanguage) -> String { L10n.tr("notifications.notificationcenter.tapToPay", vi: "Chạm để thanh toán", en: "Tap to pay", ja: "タップして支払う", language: language) }
            static var theOwner: String { L10n.tr("notifications.notificationcenter.theOwner", vi: "Chủ sở hữu", en: "The owner", ja: "所有者") }
            static func theOwner(language: MistiaAppLanguage) -> String { L10n.tr("notifications.notificationcenter.theOwner", vi: "Chủ sở hữu", en: "The owner", ja: "所有者", language: language) }
            static var thisMember: String { L10n.tr("notifications.notificationcenter.thisMember", vi: "thành viên", en: "this member", ja: "このメンバー") }
            static func thisMember(language: MistiaAppLanguage) -> String { L10n.tr("notifications.notificationcenter.thisMember", vi: "thành viên", en: "this member", ja: "このメンバー", language: language) }
            static var updated: String { L10n.tr("notifications.notificationcenter.updated", vi: "vừa cập nhật", en: "updated", ja: "更新") }
            static func updated(language: MistiaAppLanguage) -> String { L10n.tr("notifications.notificationcenter.updated", vi: "vừa cập nhật", en: "updated", ja: "更新", language: language) }
            static func valueJoinedTheFamily(_ value: String) -> String {
                L10n.format("notifications.notificationcenter.valueJoinedTheFamily", vi: "%@ vừa tham gia gia đình.", en: "%@ joined the family.", ja: "%@がファミリーに参加しました。", value)
            }
            static func valueJoinedTheFamily(_ value: String, language: MistiaAppLanguage) -> String {
                L10n.format("notifications.notificationcenter.valueJoinedTheFamily", vi: "%@ vừa tham gia gia đình.", en: "%@ joined the family.", ja: "%@がファミリーに参加しました。", language: language, value)
            }
            static func valueJustTransferredMoneyIntoYourValue(_ arg1: String, _ arg2: String) -> String {
                L10n.format("notifications.notificationcenter.valueJustTransferredMoneyIntoYourValue", vi: "%@ vừa chuyển tiền vào %@ của bạn.", en: "%@ just transferred money into your %@.", ja: "%@があなたの%@へ送金しました。", arg1, arg2)
            }
            static func valueJustTransferredMoneyIntoYourValue(_ arg1: String, _ arg2: String, language: MistiaAppLanguage) -> String {
                L10n.format("notifications.notificationcenter.valueJustTransferredMoneyIntoYourValue", vi: "%@ vừa chuyển tiền vào %@ của bạn.", en: "%@ just transferred money into your %@.", ja: "%@があなたの%@へ送金しました。", language: language, arg1, arg2)
            }
            static func valueJustTransferredValueIntoYourValue(_ arg1: String, _ arg2: String, _ arg3: String) -> String {
                L10n.format("notifications.notificationcenter.valueJustTransferredValueIntoYourValue", vi: "%@ vừa chuyển %@ vào %@ của bạn.", en: "%@ just transferred %@ into your %@.", ja: "%@が%@をあなたの%@へ送金しました。", arg1, arg2, arg3)
            }
            static func valueJustTransferredValueIntoYourValue(_ arg1: String, _ arg2: String, _ arg3: String, language: MistiaAppLanguage) -> String {
                L10n.format("notifications.notificationcenter.valueJustTransferredValueIntoYourValue", vi: "%@ vừa chuyển %@ vào %@ của bạn.", en: "%@ just transferred %@ into your %@.", ja: "%@が%@をあなたの%@へ送金しました。", language: language, arg1, arg2, arg3)
            }
            static func valueJustTransferredValueToYou(_ arg1: String, _ arg2: String) -> String {
                L10n.format("notifications.notificationcenter.valueJustTransferredValueToYou", vi: "%@ vừa chuyển %@ cho bạn.", en: "%@ just transferred %@ to you.", ja: "%@が%@をあなたへ送金しました。", arg1, arg2)
            }
            static func valueJustTransferredValueToYou(_ arg1: String, _ arg2: String, language: MistiaAppLanguage) -> String {
                L10n.format("notifications.notificationcenter.valueJustTransferredValueToYou", vi: "%@ vừa chuyển %@ cho bạn.", en: "%@ just transferred %@ to you.", ja: "%@が%@をあなたへ送金しました。", language: language, arg1, arg2)
            }
            static func valueRequestValue(_ arg1: String, _ arg2: String) -> String {
                L10n.format("notifications.notificationcenter.valueRequestValue", vi: "Yêu cầu %@ %@", en: "%@ request %@", ja: "%@のリクエスト%@", arg1, arg2)
            }
            static func valueRequestValue(_ arg1: String, _ arg2: String, language: MistiaAppLanguage) -> String {
                L10n.format("notifications.notificationcenter.valueRequestValue", vi: "Yêu cầu %@ %@", en: "%@ request %@", ja: "%@のリクエスト%@", language: language, arg1, arg2)
            }
            static func valueRevokedYourAccessToValueValue(_ arg1: String, _ arg2: String, _ arg3: String) -> String {
                L10n.format("notifications.notificationcenter.valueRevokedYourAccessToValueValue", vi: "%@ đã thu hồi quyền sử dụng %@ (%@) của bạn.", en: "%@ revoked your access to %@ (%@).", ja: "%@があなたの%@ (%@) の使用権限を取り消しました。", arg1, arg2, arg3)
            }
            static func valueRevokedYourAccessToValueValue(_ arg1: String, _ arg2: String, _ arg3: String, language: MistiaAppLanguage) -> String {
                L10n.format("notifications.notificationcenter.valueRevokedYourAccessToValueValue", vi: "%@ đã thu hồi quyền sử dụng %@ (%@) của bạn.", en: "%@ revoked your access to %@ (%@).", ja: "%@があなたの%@ (%@) の使用権限を取り消しました。", language: language, arg1, arg2, arg3)
            }
            static func valueSentMoneyToYou(_ value: String) -> String {
                L10n.format("notifications.notificationcenter.valueSentMoneyToYou", vi: "%@ vừa chuyển tiền cho bạn.", en: "%@ sent money to you.", ja: "%@があなたへ送金しました。", value)
            }
            static func valueSentMoneyToYou(_ value: String, language: MistiaAppLanguage) -> String {
                L10n.format("notifications.notificationcenter.valueSentMoneyToYou", vi: "%@ vừa chuyển tiền cho bạn.", en: "%@ sent money to you.", ja: "%@があなたへ送金しました。", language: language, value)
            }
            static func valueUnreadNotifications(_ value: String) -> String {
                L10n.format("notifications.notificationcenter.valueUnreadNotifications", vi: "%@ thông báo chưa đọc", en: "%@ unread notifications", ja: "未読通知 %@ 件", value)
            }
            static func valueUnreadNotifications(_ value: String, language: MistiaAppLanguage) -> String {
                L10n.format("notifications.notificationcenter.valueUnreadNotifications", vi: "%@ thông báo chưa đọc", en: "%@ unread notifications", ja: "未読通知 %@ 件", language: language, value)
            }
            static func valueValueRequestValue(_ arg1: String, _ arg2: String, _ arg3: String) -> String {
                L10n.format("notifications.notificationcenter.valueValueRequestValue", vi: "Yêu cầu %@ %@ %@", en: "%@ %@ request %@", ja: "%@の%@リクエスト%@", arg1, arg2, arg3)
            }
            static func valueValueRequestValue(_ arg1: String, _ arg2: String, _ arg3: String, language: MistiaAppLanguage) -> String {
                L10n.format("notifications.notificationcenter.valueValueRequestValue", vi: "Yêu cầu %@ %@ %@", en: "%@ %@ request %@", ja: "%@の%@リクエスト%@", language: language, arg1, arg2, arg3)
            }
            static func valueValueSValueRequest(_ arg1: String, _ arg2: String, _ arg3: String) -> String {
                L10n.format("notifications.notificationcenter.valueValueSValueRequest", vi: "%@ yêu cầu %@ của %@", en: "%@ %@'s %@ request", ja: "%@さんの%@のリクエストを%@しました", arg1, arg2, arg3)
            }
            static func valueValueSValueRequest(_ arg1: String, _ arg2: String, _ arg3: String, language: MistiaAppLanguage) -> String {
                L10n.format("notifications.notificationcenter.valueValueSValueRequest", vi: "%@ yêu cầu %@ của %@", en: "%@ %@'s %@ request", ja: "%@さんの%@のリクエストを%@しました", language: language, arg1, arg2, arg3)
            }
            static func valueValueSValueValueRequest(_ arg1: String, _ arg2: String, _ arg3: String, _ arg4: String) -> String {
                L10n.format("notifications.notificationcenter.valueValueSValueValueRequest", vi: "%@ yêu cầu %@ %@ của %@", en: "%@ %@'s %@ %@ request", ja: "%@さんの%@の%@リクエストを%@しました", arg1, arg2, arg3, arg4)
            }
            static func valueValueSValueValueRequest(_ arg1: String, _ arg2: String, _ arg3: String, _ arg4: String, language: MistiaAppLanguage) -> String {
                L10n.format("notifications.notificationcenter.valueValueSValueValueRequest", vi: "%@ yêu cầu %@ %@ của %@", en: "%@ %@'s %@ %@ request", ja: "%@さんの%@の%@リクエストを%@しました", language: language, arg1, arg2, arg3, arg4)
            }
            static func valueValueValueWorthValue(_ arg1: String, _ arg2: String, _ arg3: String, _ arg4: String) -> String {
                L10n.format("notifications.notificationcenter.valueValueValueWorthValue", vi: "%@ %@ %@ trị giá %@.", en: "%@ %@ %@ worth %@.", ja: "%@が %@ の %@ を%@しました。", arg1, arg2, arg3, arg4)
            }
            static func valueValueValueWorthValue(_ arg1: String, _ arg2: String, _ arg3: String, _ arg4: String, language: MistiaAppLanguage) -> String {
                L10n.format("notifications.notificationcenter.valueValueValueWorthValue", vi: "%@ %@ %@ trị giá %@.", en: "%@ %@ %@ worth %@.", ja: "%@が %@ の %@ を%@しました。", language: language, arg1, arg2, arg3, arg4)
            }
            static func valueValueYourValue(_ arg1: String, _ arg2: String, _ arg3: String) -> String {
                L10n.format("notifications.notificationcenter.valueValueYourValue", vi: "%@ %@ %@ của bạn.", en: "%@ %@ your %@.", ja: "%@があなたの %@ を%@しました。", arg1, arg2, arg3)
            }
            static func valueValueYourValue(_ arg1: String, _ arg2: String, _ arg3: String, language: MistiaAppLanguage) -> String {
                L10n.format("notifications.notificationcenter.valueValueYourValue", vi: "%@ %@ %@ của bạn.", en: "%@ %@ your %@.", ja: "%@があなたの %@ を%@しました。", language: language, arg1, arg2, arg3)
            }
            static func valueValueYourValueRequest(_ arg1: String, _ arg2: String, _ arg3: String) -> String {
                L10n.format("notifications.notificationcenter.valueValueYourValueRequest", vi: "%@ %@ yêu cầu %@ của bạn.", en: "%@ %@ your %@ request.", ja: "%@があなたの%@のリクエスト%@。", arg1, arg2, arg3)
            }
            static func valueValueYourValueRequest(_ arg1: String, _ arg2: String, _ arg3: String, language: MistiaAppLanguage) -> String {
                L10n.format("notifications.notificationcenter.valueValueYourValueRequest", vi: "%@ %@ yêu cầu %@ của bạn.", en: "%@ %@ your %@ request.", ja: "%@があなたの%@のリクエスト%@。", language: language, arg1, arg2, arg3)
            }
            static func valueValueYourValueValueRequest(_ arg1: String, _ arg2: String, _ arg3: String, _ arg4: String) -> String {
                L10n.format("notifications.notificationcenter.valueValueYourValueValueRequest", vi: "%@ %@ yêu cầu %@ %@ của bạn.", en: "%@ %@ your %@ %@ request.", ja: "%@があなたの%@ %@のリクエスト%@。", arg1, arg2, arg3, arg4)
            }
            static func valueValueYourValueValueRequest(_ arg1: String, _ arg2: String, _ arg3: String, _ arg4: String, language: MistiaAppLanguage) -> String {
                L10n.format("notifications.notificationcenter.valueValueYourValueValueRequest", vi: "%@ %@ yêu cầu %@ %@ của bạn.", en: "%@ %@ your %@ %@ request.", ja: "%@があなたの%@ %@のリクエスト%@。", language: language, arg1, arg2, arg3, arg4)
            }
        }
    }

    nonisolated enum overview {

        nonisolated enum overview {
            static var availableAssets: String { L10n.tr("overview.overview.availableAssets", vi: "Tài sản khả dụng", en: "Available assets", ja: "利用可能資産") }
            static func availableAssets(language: MistiaAppLanguage) -> String { L10n.tr("overview.overview.availableAssets", vi: "Tài sản khả dụng", en: "Available assets", ja: "利用可能資産", language: language) }
            static var budgetWatchlist: String { L10n.tr("overview.overview.budgetWatchlist", vi: "Ngân sách cần chú ý", en: "Budget watchlist", ja: "注意が必要な予算") }
            static func budgetWatchlist(language: MistiaAppLanguage) -> String { L10n.tr("overview.overview.budgetWatchlist", vi: "Ngân sách cần chú ý", en: "Budget watchlist", ja: "注意が必要な予算", language: language) }
            static var category: String { L10n.tr("overview.overview.category", vi: "Danh mục", en: "Category", ja: "カテゴリ") }
            static func category(language: MistiaAppLanguage) -> String { L10n.tr("overview.overview.category", vi: "Danh mục", en: "Category", ja: "カテゴリ", language: language) }
            static var couldnTSend: String { L10n.tr("overview.overview.couldnTSend", vi: "Chưa thể gửi", en: "Couldn't send", ja: "送信できませんでした") }
            static func couldnTSend(language: MistiaAppLanguage) -> String { L10n.tr("overview.overview.couldnTSend", vi: "Chưa thể gửi", en: "Couldn't send", ja: "送信できませんでした", language: language) }
            static var couldnTSendTheRequestRightNow: String { L10n.tr("overview.overview.couldnTSendTheRequestRightNow", vi: "Không thể gửi yêu cầu lúc này.", en: "Couldn't send the request right now.", ja: "現在リクエストは送信できません。") }
            static func couldnTSendTheRequestRightNow(language: MistiaAppLanguage) -> String { L10n.tr("overview.overview.couldnTSendTheRequestRightNow", vi: "Không thể gửi yêu cầu lúc này.", en: "Couldn't send the request right now.", ja: "現在リクエストは送信できません。", language: language) }
            static var customizeOverview: String { L10n.tr("overview.overview.customizeOverview", vi: "Tùy chỉnh Tổng quan", en: "Customize Overview", ja: "ホームのカスタマイズ") }
            static func customizeOverview(language: MistiaAppLanguage) -> String { L10n.tr("overview.overview.customizeOverview", vi: "Tùy chỉnh Tổng quan", en: "Customize Overview", ja: "ホームのカスタマイズ", language: language) }
            static var customizeOverviewDescription: String { L10n.tr("overview.overview.customizeOverviewDescription", vi: "Tùy chỉnh danh sách và thứ tự hiển thị các thẻ thông tin trên màn hình Tổng quan.", en: "Customize the display and order of information cards on the Overview screen.", ja: "ホーム画面に表示する情報カードの表示・非表示および並び順を設定します。") }
            static func customizeOverviewDescription(language: MistiaAppLanguage) -> String { L10n.tr("overview.overview.customizeOverviewDescription", vi: "Tùy chỉnh danh sách và thứ tự hiển thị các thẻ thông tin trên màn hình Tổng quan.", en: "Customize the display and order of information cards on the Overview screen.", ja: "ホーム画面に表示する情報カードの表示・非表示および並び順を設定します。", language: language) }
            static var dailyExpenses: String { L10n.tr("overview.overview.dailyExpenses", vi: "Chi tiêu trong ngày", en: "Daily expenses", ja: "その日の支出") }
            static func dailyExpenses(language: MistiaAppLanguage) -> String { L10n.tr("overview.overview.dailyExpenses", vi: "Chi tiêu trong ngày", en: "Daily expenses", ja: "その日の支出", language: language) }
            static var dailySpending: String { L10n.tr("overview.overview.dailySpending", vi: "Chi tiêu theo ngày", en: "Daily spending", ja: "日別支出") }
            static func dailySpending(language: MistiaAppLanguage) -> String { L10n.tr("overview.overview.dailySpending", vi: "Chi tiêu theo ngày", en: "Daily spending", ja: "日別支出", language: language) }
            static var day: String { L10n.tr("overview.overview.day", vi: "Ngày", en: "Day", ja: "日") }
            static func day(language: MistiaAppLanguage) -> String { L10n.tr("overview.overview.day", vi: "Ngày", en: "Day", ja: "日", language: language) }
            static var dayDetails: String { L10n.tr("overview.overview.dayDetails", vi: "Chi tiết ngày", en: "Day details", ja: "日別詳細") }
            static func dayDetails(language: MistiaAppLanguage) -> String { L10n.tr("overview.overview.dayDetails", vi: "Chi tiết ngày", en: "Day details", ja: "日別詳細", language: language) }
            static var dueToday: String { L10n.tr("overview.overview.dueToday", vi: "Cần trả hôm nay", en: "To pay today", ja: "本日支払いが必要") }
            static func dueToday(language: MistiaAppLanguage) -> String { L10n.tr("overview.overview.dueToday", vi: "Cần trả hôm nay", en: "To pay today", ja: "本日支払いが必要", language: language) }
            static var editRequestSent: String { L10n.tr("overview.overview.editRequestSent", vi: "Đã gửi yêu cầu chỉnh sửa", en: "Edit request sent", ja: "編集リクエスト送信済み") }
            static func editRequestSent(language: MistiaAppLanguage) -> String { L10n.tr("overview.overview.editRequestSent", vi: "Đã gửi yêu cầu chỉnh sửa", en: "Edit request sent", ja: "編集リクエスト送信済み", language: language) }
            static var expense: String { L10n.tr("overview.overview.expense", vi: "Chi tiêu", en: "Expense", ja: "支出") }
            static func expense(language: MistiaAppLanguage) -> String { L10n.tr("overview.overview.expense", vi: "Chi tiêu", en: "Expense", ja: "支出", language: language) }
            static func expenseMonthValue(_ value: String) -> String {
                L10n.format("overview.overview.expenseMonthValue", vi: "Chi tháng %@", en: "Expense month %@", ja: "%@月の支出", value)
            }
            static func expenseMonthValue(_ value: String, language: MistiaAppLanguage) -> String {
                L10n.format("overview.overview.expenseMonthValue", vi: "Chi tháng %@", en: "Expense month %@", ja: "%@月の支出", language: language, value)
            }
            static var expenseThisMonth: String { L10n.tr("overview.overview.expenseThisMonth", vi: "Chi tháng này", en: "Expense this month", ja: "今月の支出") }
            static func expenseThisMonth(language: MistiaAppLanguage) -> String { L10n.tr("overview.overview.expenseThisMonth", vi: "Chi tháng này", en: "Expense this month", ja: "今月の支出", language: language) }
            static func incomeMonthValue(_ value: String) -> String {
                L10n.format("overview.overview.incomeMonthValue", vi: "Thu tháng %@", en: "Income month %@", ja: "%@月の収入", value)
            }
            static func incomeMonthValue(_ value: String, language: MistiaAppLanguage) -> String {
                L10n.format("overview.overview.incomeMonthValue", vi: "Thu tháng %@", en: "Income month %@", ja: "%@月の収入", language: language, value)
            }
            static var incomeThisMonth: String { L10n.tr("overview.overview.incomeThisMonth", vi: "Thu tháng này", en: "Income this month", ja: "今月の収入") }
            static func incomeThisMonth(language: MistiaAppLanguage) -> String { L10n.tr("overview.overview.incomeThisMonth", vi: "Thu tháng này", en: "Income this month", ja: "今月の収入", language: language) }
            static var noAmountYet: String { L10n.tr("overview.overview.noAmountYet", vi: "Chưa có số tiền", en: "No amount yet", ja: "金額未入力") }
            static func noAmountYet(language: MistiaAppLanguage) -> String { L10n.tr("overview.overview.noAmountYet", vi: "Chưa có số tiền", en: "No amount yet", ja: "金額未入力", language: language) }
            static var noBillsLoansOrCreditPaymentsAre: String { L10n.tr("overview.overview.noBillsLoansOrCreditPaymentsAre", vi: "Không có hóa đơn, khoản vay hoặc thẻ nào cần trả trong 7 ngày tới.", en: "No bills, loans, or credit payments need payment in the next 7 days.", ja: "今後 7 日以内に期限を迎える請求、ローン、カード支払いはありません。") }
            static func noBillsLoansOrCreditPaymentsAre(language: MistiaAppLanguage) -> String { L10n.tr("overview.overview.noBillsLoansOrCreditPaymentsAre", vi: "Không có hóa đơn, khoản vay hoặc thẻ nào cần trả trong 7 ngày tới.", en: "No bills, loans, or credit payments need payment in the next 7 days.", ja: "今後 7 日以内に期限を迎える請求、ローン、カード支払いはありません。", language: language) }
            static var noCategoriesHaveExceededOfTheir: String { L10n.tr("overview.overview.noCategoriesHaveExceededOfTheir", vi: "Chưa có danh mục nào vượt quá 50% ngân sách trong tháng này.", en: "No categories have exceeded 50% of their budget this month.", ja: "今月の予算消化が 50% を超えたカテゴリはまだありません。") }
            static func noCategoriesHaveExceededOfTheir(language: MistiaAppLanguage) -> String { L10n.tr("overview.overview.noCategoriesHaveExceededOfTheir", vi: "Chưa có danh mục nào vượt quá 50% ngân sách trong tháng này.", en: "No categories have exceeded 50% of their budget this month.", ja: "今月の予算消化が 50% を超えたカテゴリはまだありません。", language: language) }
            static var noTransactionEditAccess: String { L10n.tr("overview.overview.noTransactionEditAccess", vi: "Chưa có quyền chỉnh sửa thu chi", en: "No cashflow edit access", ja: "収支編集権限がありません") }
            static func noTransactionEditAccess(language: MistiaAppLanguage) -> String { L10n.tr("overview.overview.noTransactionEditAccess", vi: "Chưa có quyền chỉnh sửa thu chi", en: "No cashflow edit access", ja: "収支編集権限がありません", language: language) }
            static var noTransactionsHaveBeenRecordedRecently: String { L10n.tr("overview.overview.noTransactionsHaveBeenRecordedRecently", vi: "Chưa có thu chi nào được ghi nhận gần đây.", en: "No cashflow items have been recorded recently.", ja: "最近記録された取引はまだありません。") }
            static func noTransactionsHaveBeenRecordedRecently(language: MistiaAppLanguage) -> String { L10n.tr("overview.overview.noTransactionsHaveBeenRecordedRecently", vi: "Chưa có thu chi nào được ghi nhận gần đây.", en: "No cashflow items have been recorded recently.", ja: "最近記録された取引はまだありません。", language: language) }
            static var noWalletSelected: String { L10n.tr("overview.overview.noWalletSelected", vi: "Chưa chọn ví", en: "No wallet selected", ja: "ウォレット未選択") }
            static func noWalletSelected(language: MistiaAppLanguage) -> String { L10n.tr("overview.overview.noWalletSelected", vi: "Chưa chọn ví", en: "No wallet selected", ja: "ウォレット未選択", language: language) }
            static var overview: String { L10n.tr("overview.overview.overview", vi: "Tổng quan", en: "Overview", ja: "ホーム") }
            static func overview(language: MistiaAppLanguage) -> String { L10n.tr("overview.overview.overview", vi: "Tổng quan", en: "Overview", ja: "ホーム", language: language) }
            static var recentTransactions: String { L10n.tr("overview.overview.recentTransactions", vi: "Thu chi gần đây", en: "Recent cashflow", ja: "最近の収支") }
            static func recentTransactions(language: MistiaAppLanguage) -> String { L10n.tr("overview.overview.recentTransactions", vi: "Thu chi gần đây", en: "Recent cashflow", ja: "最近の収支", language: language) }
            static var requestEditAccess: String { L10n.tr("overview.overview.requestEditAccess", vi: "Yêu cầu quyền chỉnh sửa", en: "Request edit access", ja: "編集権限をリクエスト") }
            static func requestEditAccess(language: MistiaAppLanguage) -> String { L10n.tr("overview.overview.requestEditAccess", vi: "Yêu cầu quyền chỉnh sửa", en: "Request edit access", ja: "編集権限をリクエスト", language: language) }
            static var requestSent: String { L10n.tr("overview.overview.requestSent", vi: "Đã gửi yêu cầu", en: "Request sent", ja: "リクエストを送信しました") }
            static func requestSent(language: MistiaAppLanguage) -> String { L10n.tr("overview.overview.requestSent", vi: "Đã gửi yêu cầu", en: "Request sent", ja: "リクエストを送信しました", language: language) }
            static var resetToDefault: String { L10n.tr("overview.overview.resetToDefault", vi: "Khôi phục mặc định", en: "Reset to default", ja: "デフォルトに戻す") }
            static func resetToDefault(language: MistiaAppLanguage) -> String { L10n.tr("overview.overview.resetToDefault", vi: "Khôi phục mặc định", en: "Reset to default", ja: "デフォルトに戻す", language: language) }
            static var spendingByCategory: String { L10n.tr("overview.overview.spendingByCategory", vi: "Chi tiêu theo danh mục", en: "Spending by category", ja: "カテゴリ別支出") }
            static func spendingByCategory(language: MistiaAppLanguage) -> String { L10n.tr("overview.overview.spendingByCategory", vi: "Chi tiêu theo danh mục", en: "Spending by category", ja: "カテゴリ別支出", language: language) }
            static var thePermissionRequestWasSentToThe: String { L10n.tr("overview.overview.thePermissionRequestWasSentToThe", vi: "Yêu cầu quyền đã được gửi tới chủ dữ liệu.", en: "The permission request was sent to the data owner.", ja: "権限リクエストをデータ所有者へ送信しました。") }
            static func thePermissionRequestWasSentToThe(language: MistiaAppLanguage) -> String { L10n.tr("overview.overview.thePermissionRequestWasSentToThe", vi: "Yêu cầu quyền đã được gửi tới chủ dữ liệu.", en: "The permission request was sent to the data owner.", ja: "権限リクエストをデータ所有者へ送信しました。", language: language) }
            static var thisWeek: String { L10n.tr("overview.overview.thisWeek", vi: "Tuần này", en: "This week", ja: "今週") }
            static func thisWeek(language: MistiaAppLanguage) -> String { L10n.tr("overview.overview.thisWeek", vi: "Tuần này", en: "This week", ja: "今週", language: language) }
            static var totalSpent: String { L10n.tr("overview.overview.totalSpent", vi: "Tổng chi", en: "Total spent", ja: "合計支出") }
            static func totalSpent(language: MistiaAppLanguage) -> String { L10n.tr("overview.overview.totalSpent", vi: "Tổng chi", en: "Total spent", ja: "合計支出", language: language) }
            static var transactions: String { L10n.tr("overview.overview.transactions", vi: "Thu chi", en: "Cashflow", ja: "収支") }
            static func transactions(language: MistiaAppLanguage) -> String { L10n.tr("overview.overview.transactions", vi: "Thu chi", en: "Cashflow", ja: "収支", language: language) }
            static var transactions2: String { L10n.tr("overview.overview.transactions2", vi: "thu chi", en: "cashflow items", ja: "収支") }
            static func transactions2(language: MistiaAppLanguage) -> String { L10n.tr("overview.overview.transactions2", vi: "thu chi", en: "cashflow items", ja: "収支", language: language) }
            static var upcomingDueItems: String { L10n.tr("overview.overview.upcomingDueItems", vi: "Khoản sắp tới", en: "Upcoming items", ja: "今後の項目") }
            static func upcomingDueItems(language: MistiaAppLanguage) -> String { L10n.tr("overview.overview.upcomingDueItems", vi: "Khoản sắp tới", en: "Upcoming items", ja: "今後の項目", language: language) }
            static func valueDaysLeft(_ value: String) -> String {
                L10n.format("overview.overview.valueDaysLeft", vi: "Còn %@ ngày", en: "%@ days left", ja: "あと %@ 日", value)
            }
            static func valueDaysLeft(_ value: String, language: MistiaAppLanguage) -> String {
                L10n.format("overview.overview.valueDaysLeft", vi: "Còn %@ ngày", en: "%@ days left", ja: "あと %@ 日", language: language, value)
            }
            static var youDoNotHavePermissionToEdit: String { L10n.tr("overview.overview.youDoNotHavePermissionToEdit", vi: "Bạn chưa có quyền chỉnh sửa thu chi của thành viên này.", en: "You do not have permission to edit this member's cashflow items.", ja: "このメンバーの取引を編集する権限がありません。") }
            static func youDoNotHavePermissionToEdit(language: MistiaAppLanguage) -> String { L10n.tr("overview.overview.youDoNotHavePermissionToEdit", vi: "Bạn chưa có quyền chỉnh sửa thu chi của thành viên này.", en: "You do not have permission to edit this member's cashflow items.", ja: "このメンバーの取引を編集する権限がありません。", language: language) }
        }
    }

    nonisolated enum placeholder {

        nonisolated enum placeholdertab {
            static var thisTabIsIntentionallyEmptyWhileWe: String { L10n.tr("placeholder.placeholdertab.thisTabIsIntentionallyEmptyWhileWe", vi: "Tab này đang để trống để ưu tiên hoàn thiện giao diện Tổng quan trước.", en: "This tab is intentionally empty while we prioritize finishing the Overview screen first.", ja: "まずホーム画面の仕上げを優先しているため、このタブは現在空になっています。") }
            static func thisTabIsIntentionallyEmptyWhileWe(language: MistiaAppLanguage) -> String { L10n.tr("placeholder.placeholdertab.thisTabIsIntentionallyEmptyWhileWe", vi: "Tab này đang để trống để ưu tiên hoàn thiện giao diện Tổng quan trước.", en: "This tab is intentionally empty while we prioritize finishing the Overview screen first.", ja: "まずホーム画面の仕上げを優先しているため、このタブは現在空になっています。", language: language) }
        }
    }

    nonisolated enum planning {

        nonisolated enum duepayment {
            static var billSkipped: String { L10n.tr("planning.duepayment.billSkipped", vi: "Đã bỏ qua", en: "Skipped", ja: "スキップ済み") }
            static func billSkipped(language: MistiaAppLanguage) -> String { L10n.tr("planning.duepayment.billSkipped", vi: "Đã bỏ qua", en: "Skipped", ja: "スキップ済み", language: language) }
            static var cancel: String { L10n.tr("planning.duepayment.cancel", vi: "Hủy", en: "Cancel", ja: "キャンセル") }
            static func cancel(language: MistiaAppLanguage) -> String { L10n.tr("planning.duepayment.cancel", vi: "Hủy", en: "Cancel", ja: "キャンセル", language: language) }
            static var chooseWallet: String { L10n.tr("planning.duepayment.chooseWallet", vi: "Chọn ví", en: "Choose wallet", ja: "ウォレットを選択") }
            static func chooseWallet(language: MistiaAppLanguage) -> String { L10n.tr("planning.duepayment.chooseWallet", vi: "Chọn ví", en: "Choose wallet", ja: "ウォレットを選択", language: language) }
            static var couldNotFindTheDueItem: String { L10n.tr("planning.duepayment.couldNotFindTheDueItem", vi: "Không tìm thấy khoản cần trả.", en: "Could not find the payment item.", ja: "期限項目が見つかりませんでした。") }
            static func couldNotFindTheDueItem(language: MistiaAppLanguage) -> String { L10n.tr("planning.duepayment.couldNotFindTheDueItem", vi: "Không tìm thấy khoản cần trả.", en: "Could not find the payment item.", ja: "期限項目が見つかりませんでした。", language: language) }
            static var dismiss: String { L10n.tr("planning.duepayment.dismiss", vi: "Đóng", en: "Dismiss", ja: "閉じる") }
            static func dismiss(language: MistiaAppLanguage) -> String { L10n.tr("planning.duepayment.dismiss", vi: "Đóng", en: "Dismiss", ja: "閉じる", language: language) }
            static var enterAmount: String { L10n.tr("planning.duepayment.enterAmount", vi: "Nhập số tiền", en: "Enter amount", ja: "金額を入力") }
            static func enterAmount(language: MistiaAppLanguage) -> String { L10n.tr("planning.duepayment.enterAmount", vi: "Nhập số tiền", en: "Enter amount", ja: "金額を入力", language: language) }
            static var payBill: String { L10n.tr("planning.duepayment.payBill", vi: "Thanh toán hóa đơn", en: "Pay bill", ja: "請求の支払い") }
            static func payBill(language: MistiaAppLanguage) -> String { L10n.tr("planning.duepayment.payBill", vi: "Thanh toán hóa đơn", en: "Pay bill", ja: "請求の支払い", language: language) }
            static var payNow: String { L10n.tr("planning.duepayment.payNow", vi: "Thanh toán ngay", en: "Pay now", ja: "今すぐ支払う") }
            static func payNow(language: MistiaAppLanguage) -> String { L10n.tr("planning.duepayment.payNow", vi: "Thanh toán ngay", en: "Pay now", ja: "今すぐ支払う", language: language) }
            static func paymentCycleMonth(_ value: String) -> String {
                L10n.format("planning.duepayment.paymentCycleMonth", vi: "Thanh toán kỳ tháng %@", en: "Paying cycle %@", ja: "%@分を支払い", value)
            }
            static func paymentCycleMonth(_ value: String, language: MistiaAppLanguage) -> String {
                L10n.format("planning.duepayment.paymentCycleMonth", vi: "Thanh toán kỳ tháng %@", en: "Paying cycle %@", ja: "%@分を支払い", language: language, value)
            }
            static var paymentFailed: String { L10n.tr("planning.duepayment.paymentFailed", vi: "Không thể thanh toán", en: "Payment failed", ja: "支払いに失敗しました") }
            static func paymentFailed(language: MistiaAppLanguage) -> String { L10n.tr("planning.duepayment.paymentFailed", vi: "Không thể thanh toán", en: "Payment failed", ja: "支払いに失敗しました", language: language) }
            static var paymentWallet: String { L10n.tr("planning.duepayment.paymentWallet", vi: "Ví thanh toán", en: "Payment wallet", ja: "支払いウォレット") }
            static func paymentWallet(language: MistiaAppLanguage) -> String { L10n.tr("planning.duepayment.paymentWallet", vi: "Ví thanh toán", en: "Payment wallet", ja: "支払いウォレット", language: language) }
            static var skipConfirmationMessage: String { L10n.tr("planning.duepayment.skipConfirmationMessage", vi: "Bạn có chắc chắn muốn bỏ qua hóa đơn này cho kỳ tháng này không?", en: "Are you sure you want to skip this bill for this month?", ja: "今月のこの請求をスキップしてもよろしいですか？") }
            static func skipConfirmationMessage(language: MistiaAppLanguage) -> String { L10n.tr("planning.duepayment.skipConfirmationMessage", vi: "Bạn có chắc chắn muốn bỏ qua hóa đơn này cho kỳ tháng này không?", en: "Are you sure you want to skip this bill for this month?", ja: "今月のこの請求をスキップしてもよろしいですか？", language: language) }
            static var skipThisMonth: String { L10n.tr("planning.duepayment.skipThisMonth", vi: "Bỏ qua", en: "Skip", ja: "スキップ") }
            static func skipThisMonth(language: MistiaAppLanguage) -> String { L10n.tr("planning.duepayment.skipThisMonth", vi: "Bỏ qua", en: "Skip", ja: "スキップ", language: language) }
            static var thisBillHasNoDefaultAmount: String { L10n.tr("planning.duepayment.thisBillHasNoDefaultAmount", vi: "Hóa đơn này chưa có số tiền mặc định.", en: "This bill has no default amount.", ja: "この請求にはデフォルトの金額がありません。") }
            static func thisBillHasNoDefaultAmount(language: MistiaAppLanguage) -> String { L10n.tr("planning.duepayment.thisBillHasNoDefaultAmount", vi: "Hóa đơn này chưa có số tiền mặc định.", en: "This bill has no default amount.", ja: "この請求にはデフォルトの金額がありません。", language: language) }
            static var undo: String { L10n.tr("planning.duepayment.undo", vi: "Hoàn tác", en: "Undo", ja: "元に戻す") }
            static func undo(language: MistiaAppLanguage) -> String { L10n.tr("planning.duepayment.undo", vi: "Hoàn tác", en: "Undo", ja: "元に戻す", language: language) }
            static var undoPayment: String { L10n.tr("planning.duepayment.undoPayment", vi: "Hoàn tác thanh toán", en: "Undo payment", ja: "支払いを取り消す") }
            static func undoPayment(language: MistiaAppLanguage) -> String { L10n.tr("planning.duepayment.undoPayment", vi: "Hoàn tác thanh toán", en: "Undo payment", ja: "支払いを取り消す", language: language) }
            static var undoPaymentMessage: String { L10n.tr("planning.duepayment.undoPaymentMessage", vi: "Bạn có chắc chắn muốn hoàn tác thanh toán cho hóa đơn này không? Giao dịch thanh toán liên quan sẽ bị xóa.", en: "Are you sure you want to undo payment for this bill? The linked payment transaction will be deleted.", ja: "この請求の支払いを取り消しますか？関連する支払い取引が削除されます。") }
            static func undoPaymentMessage(language: MistiaAppLanguage) -> String { L10n.tr("planning.duepayment.undoPaymentMessage", vi: "Bạn có chắc chắn muốn hoàn tác thanh toán cho hóa đơn này không? Giao dịch thanh toán liên quan sẽ bị xóa.", en: "Are you sure you want to undo payment for this bill? The linked payment transaction will be deleted.", ja: "この請求の支払いを取り消しますか？関連する支払い取引が削除されます。", language: language) }
            static var undoSkip: String { L10n.tr("planning.duepayment.undoSkip", vi: "Hoàn tác bỏ qua", en: "Undo skip", ja: "スキップを取り消す") }
            static func undoSkip(language: MistiaAppLanguage) -> String { L10n.tr("planning.duepayment.undoSkip", vi: "Hoàn tác bỏ qua", en: "Undo skip", ja: "スキップを取り消す", language: language) }
            static var undoSkipMessage: String { L10n.tr("planning.duepayment.undoSkipMessage", vi: "Bạn có chắc chắn muốn hoàn tác bỏ qua hóa đơn này không? Hóa đơn sẽ quay trở lại trạng thái cần thanh toán.", en: "Are you sure you want to undo skipping this bill? It will return to pending status.", ja: "この請求のスキップを取り消しますか？未払い状態に戻ります。") }
            static func undoSkipMessage(language: MistiaAppLanguage) -> String { L10n.tr("planning.duepayment.undoSkipMessage", vi: "Bạn có chắc chắn muốn hoàn tác bỏ qua hóa đơn này không? Hóa đơn sẽ quay trở lại trạng thái cần thanh toán.", en: "Are you sure you want to undo skipping this bill? It will return to pending status.", ja: "この請求のスキップを取り消しますか？未払い状態に戻ります。", language: language) }
        }

        nonisolated enum planning {
            static var aMatchingPaymentWalletCouldNotBe: String { L10n.tr("planning.planning.aMatchingPaymentWalletCouldNotBe", vi: "Không tìm thấy ví thanh toán phù hợp.", en: "A matching payment wallet could not be found.", ja: "支払いに使うウォレットが見つかりません。") }
            static func aMatchingPaymentWalletCouldNotBe(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.aMatchingPaymentWalletCouldNotBe", vi: "Không tìm thấy ví thanh toán phù hợp.", en: "A matching payment wallet could not be found.", ja: "支払いに使うウォレットが見つかりません。", language: language) }
            static var accessRequested: String { L10n.tr("planning.planning.accessRequested", vi: "Đã yêu cầu quyền", en: "Access requested", ja: "権限をリクエスト済み") }
            static func accessRequested(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.accessRequested", vi: "Đã yêu cầu quyền", en: "Access requested", ja: "権限をリクエスト済み", language: language) }
            static var activeGoals: String { L10n.tr("planning.planning.activeGoals", vi: "Mục tiêu đang hoạt động", en: "Active goals", ja: "進行中の目標") }
            static func activeGoals(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.activeGoals", vi: "Mục tiêu đang hoạt động", en: "Active goals", ja: "進行中の目標", language: language) }
            static var addAnEmergencyFundTripOrBig: String { L10n.tr("planning.planning.addAnEmergencyFundTripOrBig", vi: "Thêm quỹ khẩn cấp, du lịch hay món đồ lớn để theo dõi số tiền cần tích lũy mỗi tháng.", en: "Add an emergency fund, trip, or big purchase to track how much you need to save each month.", ja: "緊急資金や旅行、大きな買い物の目標を追加して、毎月どれだけ貯める必要があるか確認できます。") }
            static func addAnEmergencyFundTripOrBig(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.addAnEmergencyFundTripOrBig", vi: "Thêm quỹ khẩn cấp, du lịch hay món đồ lớn để theo dõi số tiền cần tích lũy mỗi tháng.", en: "Add an emergency fund, trip, or big purchase to track how much you need to save each month.", ja: "緊急資金や旅行、大きな買い物の目標を追加して、毎月どれだけ貯める必要があるか確認できます。", language: language) }
            static var addBill: String { L10n.tr("planning.planning.addBill", vi: "Thêm hóa đơn", en: "Add bill", ja: "請求を追加") }
            static func addBill(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.addBill", vi: "Thêm hóa đơn", en: "Add bill", ja: "請求を追加", language: language) }
            static var addBudget: String { L10n.tr("planning.planning.addBudget", vi: "Thêm ngân sách", en: "Add budget", ja: "予算を追加") }
            static func addBudget(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.addBudget", vi: "Thêm ngân sách", en: "Add budget", ja: "予算を追加", language: language) }
            static var addCreditCard: String { L10n.tr("planning.planning.addCreditCard", vi: "Thêm credit card", en: "Add credit card", ja: "カードを追加") }
            static func addCreditCard(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.addCreditCard", vi: "Thêm credit card", en: "Add credit card", ja: "カードを追加", language: language) }
            static var addGoal: String { L10n.tr("planning.planning.addGoal", vi: "Thêm mục tiêu", en: "Add goal", ja: "目標を追加") }
            static func addGoal(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.addGoal", vi: "Thêm mục tiêu", en: "Add goal", ja: "目標を追加", language: language) }
            static var addInstallmentLoan: String { L10n.tr("planning.planning.addInstallmentLoan", vi: "Thêm trả góp / vay", en: "Add installment / loan", ja: "分割払い・借入を追加") }
            static func addInstallmentLoan(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.addInstallmentLoan", vi: "Thêm trả góp / vay", en: "Add installment / loan", ja: "分割払い・借入を追加", language: language) }
            static var addInstallmentOrLoanPaymentsAndCreate: String { L10n.tr("planning.planning.addInstallmentOrLoanPaymentsAndCreate", vi: "Thêm các khoản cần trả theo kỳ và tạo thu chi khi thanh toán trước.", en: "Add installment or loan payments and create cashflow items when you pay early.", ja: "分割払いやローンを追加すると、繰上げ支払い時に取引も作成できます。") }
            static func addInstallmentOrLoanPaymentsAndCreate(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.addInstallmentOrLoanPaymentsAndCreate", vi: "Thêm các khoản cần trả theo kỳ và tạo thu chi khi thanh toán trước.", en: "Add installment or loan payments and create cashflow items when you pay early.", ja: "分割払いやローンを追加すると、繰上げ支払い時に取引も作成できます。", language: language) }
            static var addInternetUtilitiesOrRecurringBillsTo: String { L10n.tr("planning.planning.addInternetUtilitiesOrRecurringBillsTo", vi: "Thêm tiền Internet, điện nước hoặc hóa đơn định kỳ vào lịch sắp tới.", en: "Add internet, utilities, or recurring bills to your upcoming schedule.", ja: "ネット料金や光熱費、定期請求を追加して支払予定を管理できます。") }
            static func addInternetUtilitiesOrRecurringBillsTo(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.addInternetUtilitiesOrRecurringBillsTo", vi: "Thêm tiền Internet, điện nước hoặc hóa đơn định kỳ vào lịch sắp tới.", en: "Add internet, utilities, or recurring bills to your upcoming schedule.", ja: "ネット料金や光熱費、定期請求を追加して支払予定を管理できます。", language: language) }
            static var amountOptional: String { L10n.tr("planning.planning.amountOptional", vi: "Số tiền (có thể để trống)", en: "Amount (optional)", ja: "金額（任意）") }
            static func amountOptional(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.amountOptional", vi: "Số tiền (có thể để trống)", en: "Amount (optional)", ja: "金額（任意）", language: language) }
            static var amountPerCycle: String { L10n.tr("planning.planning.amountPerCycle", vi: "Số tiền mỗi kỳ", en: "Amount per cycle", ja: "各回の金額") }
            static func amountPerCycle(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.amountPerCycle", vi: "Số tiền mỗi kỳ", en: "Amount per cycle", ja: "各回の金額", language: language) }
            static var archive: String { L10n.tr("planning.planning.archive", vi: "Lưu trữ", en: "Archive", ja: "アーカイブ") }
            static func archive(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.archive", vi: "Lưu trữ", en: "Archive", ja: "アーカイブ", language: language) }
            static var archiveBill: String { L10n.tr("planning.planning.archiveBill", vi: "Lưu trữ hóa đơn", en: "Archive bill", ja: "請求をアーカイブ") }
            static func archiveBill(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.archiveBill", vi: "Lưu trữ hóa đơn", en: "Archive bill", ja: "請求をアーカイブ", language: language) }
            static var archiveBudget: String { L10n.tr("planning.planning.archiveBudget", vi: "Lưu trữ ngân sách", en: "Archive budget", ja: "予算をアーカイブ") }
            static func archiveBudget(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.archiveBudget", vi: "Lưu trữ ngân sách", en: "Archive budget", ja: "予算をアーカイブ", language: language) }
            static var archiveCard: String { L10n.tr("planning.planning.archiveCard", vi: "Lưu trữ thẻ", en: "Archive card", ja: "カードをアーカイブ") }
            static func archiveCard(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.archiveCard", vi: "Lưu trữ thẻ", en: "Archive card", ja: "カードをアーカイブ", language: language) }
            static var archivedBillsWillNoLongerAppearIn: String { L10n.tr("planning.planning.archivedBillsWillNoLongerAppearIn", vi: "Hóa đơn lưu trữ sẽ không còn hiện trong tab Sắp tới. Mục này sẽ được tự động xóa vĩnh viễn sau 30 ngày.", en: "Archived bills will no longer appear in Upcoming. They will be automatically deleted permanently after 30 days.", ja: "アーカイブした請求はプラン画面に表示されなくなり、30日後に自動で完全削除されます。") }
            static func archivedBillsWillNoLongerAppearIn(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.archivedBillsWillNoLongerAppearIn", vi: "Hóa đơn lưu trữ sẽ không còn hiện trong tab Sắp tới. Mục này sẽ được tự động xóa vĩnh viễn sau 30 ngày.", en: "Archived bills will no longer appear in Upcoming. They will be automatically deleted permanently after 30 days.", ja: "アーカイブした請求はプラン画面に表示されなくなり、30日後に自動で完全削除されます。", language: language) }
            static var archivedBudgetsWillNoLongerAppearIn: String { L10n.tr("planning.planning.archivedBudgetsWillNoLongerAppearIn", vi: "Ngân sách lưu trữ sẽ không còn hiện trong tab Sắp tới. Mục này sẽ được tự động xóa vĩnh viễn sau 30 ngày.", en: "Archived budgets will no longer appear in Upcoming. They will be automatically deleted permanently after 30 days.", ja: "アーカイブした予算はプラン画面に表示されなくなり、30日後に自動で完全削除されます。") }
            static func archivedBudgetsWillNoLongerAppearIn(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.archivedBudgetsWillNoLongerAppearIn", vi: "Ngân sách lưu trữ sẽ không còn hiện trong tab Sắp tới. Mục này sẽ được tự động xóa vĩnh viễn sau 30 ngày.", en: "Archived budgets will no longer appear in Upcoming. They will be automatically deleted permanently after 30 days.", ja: "アーカイブした予算はプラン画面に表示されなくなり、30日後に自動で完全削除されます。", language: language) }
            static var archivedCardsWillNoLongerAppearIn: String { L10n.tr("planning.planning.archivedCardsWillNoLongerAppearIn", vi: "Thẻ lưu trữ sẽ không còn hiện trong tab Sắp tới. Mục này sẽ được tự động xóa vĩnh viễn sau 30 ngày.", en: "Archived cards will no longer appear in the upcoming tab. They will be automatically deleted permanently after 30 days.", ja: "アーカイブしたカードは計画タブに表示されなくなります。これらは30日後に自動的に永久削除されます。") }
            static func archivedCardsWillNoLongerAppearIn(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.archivedCardsWillNoLongerAppearIn", vi: "Thẻ lưu trữ sẽ không còn hiện trong tab Sắp tới. Mục này sẽ được tự động xóa vĩnh viễn sau 30 ngày.", en: "Archived cards will no longer appear in the upcoming tab. They will be automatically deleted permanently after 30 days.", ja: "アーカイブしたカードは計画タブに表示されなくなります。これらは30日後に自動的に永久削除されます。", language: language) }
            static var autoPay: String { L10n.tr("planning.planning.autoPay", vi: "Tự động thanh toán", en: "Auto pay", ja: "自動支払い") }
            static func autoPay(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.autoPay", vi: "Tự động thanh toán", en: "Auto pay", ja: "自動支払い", language: language) }
            static var autoPayDate: String { L10n.tr("planning.planning.autoPayDate", vi: "Ngày tự thanh toán", en: "Auto-pay date", ja: "自動支払日") }
            static func autoPayDate(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.autoPayDate", vi: "Ngày tự thanh toán", en: "Auto-pay date", ja: "自動支払日", language: language) }
            static var autoPayDay: String { L10n.tr("planning.planning.autoPayDay", vi: "Ngày tự động thanh toán", en: "Auto-pay day", ja: "自動支払日") }
            static func autoPayDay(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.autoPayDay", vi: "Ngày tự động thanh toán", en: "Auto-pay day", ja: "自動支払日", language: language) }
            static var available: String { L10n.tr("planning.planning.available", vi: "Khả dụng", en: "Available", ja: "利用可能") }
            static func available(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.available", vi: "Khả dụng", en: "Available", ja: "利用可能", language: language) }
            static var availableCredit: String { L10n.tr("planning.planning.availableCredit", vi: "Số tiền khả dụng", en: "Available credit", ja: "利用可能額") }
            static func availableCredit(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.availableCredit", vi: "Số tiền khả dụng", en: "Available credit", ja: "利用可能額", language: language) }
            static var availablePerDay: String { L10n.tr("planning.planning.availablePerDay", vi: "Có thể chi mỗi ngày", en: "Available per day", ja: "1日あたり利用可能") }
            static func availablePerDay(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.availablePerDay", vi: "Có thể chi mỗi ngày", en: "Available per day", ja: "1日あたり利用可能", language: language) }
            static var biUTNgTh: String { L10n.tr("planning.planning.biUTNgTh", vi: "Biểu tượng thẻ", en: "Card icon", ja: "カードアイコン") }
            static func biUTNgTh(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.biUTNgTh", vi: "Biểu tượng thẻ", en: "Card icon", ja: "カードアイコン", language: language) }
            static var bill: String { L10n.tr("planning.planning.bill", vi: "Hóa đơn", en: "Bill", ja: "請求") }
            static func bill(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.bill", vi: "Hóa đơn", en: "Bill", ja: "請求", language: language) }
            static var billName: String { L10n.tr("planning.planning.billName", vi: "Tên hóa đơn", en: "Bill name", ja: "請求名") }
            static func billName(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.billName", vi: "Tên hóa đơn", en: "Bill name", ja: "請求名", language: language) }
            static var billType: String { L10n.tr("planning.planning.billType", vi: "Loại hóa đơn", en: "Bill type", ja: "請求タイプ") }
            static func billType(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.billType", vi: "Loại hóa đơn", en: "Bill type", ja: "請求タイプ", language: language) }
            static var bills: String { L10n.tr("planning.planning.bills", vi: "hóa đơn", en: "bills", ja: "請求書") }
            static func bills(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.bills", vi: "hóa đơn", en: "bills", ja: "請求書", language: language) }
            static var bills2: String { L10n.tr("planning.planning.bills2", vi: "Hóa đơn", en: "Bills", ja: "請求書") }
            static func bills2(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.bills2", vi: "Hóa đơn", en: "Bills", ja: "請求書", language: language) }
            static var budget: String { L10n.tr("planning.planning.budget", vi: "Ngân sách", en: "Budget", ja: "予算") }
            static func budget(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.budget", vi: "Ngân sách", en: "Budget", ja: "予算", language: language) }
            static var budget2: String { L10n.tr("planning.planning.budget2", vi: "Ngân sách", en: "Budget", ja: "予算") }
            static func budget2(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.budget2", vi: "Ngân sách", en: "Budget", ja: "予算", language: language) }
            static var budgetAmount: String { L10n.tr("planning.planning.budgetAmount", vi: "Số tiền ngân sách", en: "Budget amount", ja: "予算金額") }
            static func budgetAmount(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.budgetAmount", vi: "Số tiền ngân sách", en: "Budget amount", ja: "予算金額", language: language) }
            static var budgets: String { L10n.tr("planning.planning.budgets", vi: "ngân sách", en: "budgets", ja: "予算") }
            static func budgets(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.budgets", vi: "ngân sách", en: "budgets", ja: "予算", language: language) }
            static var canTCompleteYet: String { L10n.tr("planning.planning.canTCompleteYet", vi: "Chưa thể thực hiện", en: "Can't complete yet", ja: "まだ実行できません") }
            static func canTCompleteYet(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.canTCompleteYet", vi: "Chưa thể thực hiện", en: "Can't complete yet", ja: "まだ実行できません", language: language) }
            static var cardDetails: String { L10n.tr("planning.planning.cardDetails", vi: "Thông tin thẻ", en: "Card details", ja: "カード情報") }
            static func cardDetails(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.cardDetails", vi: "Thông tin thẻ", en: "Card details", ja: "カード情報", language: language) }
            static var cardName: String { L10n.tr("planning.planning.cardName", vi: "Tên thẻ", en: "Card name", ja: "カード名") }
            static func cardName(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.cardName", vi: "Tên thẻ", en: "Card name", ja: "カード名", language: language) }
            static var cardNetwork: String { L10n.tr("planning.planning.cardNetwork", vi: "Mạng thẻ", en: "Card network", ja: "カードブランド") }
            static func cardNetwork(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.cardNetwork", vi: "Mạng thẻ", en: "Card network", ja: "カードブランド", language: language) }
            static var category: String { L10n.tr("planning.planning.category", vi: "Danh mục", en: "Category", ja: "カテゴリ") }
            static func category(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.category", vi: "Danh mục", en: "Category", ja: "カテゴリ", language: language) }
            static var chMIIcon: String { L10n.tr("planning.planning.chMIIcon", vi: "Chạm để đổi icon", en: "Tap to change icon", ja: "タップしてアイコンを変更") }
            static func chMIIcon(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.chMIIcon", vi: "Chạm để đổi icon", en: "Tap to change icon", ja: "タップしてアイコンを変更", language: language) }
            static var childBudget: String { L10n.tr("planning.planning.childBudget", vi: "Ngân sách con", en: "Child budget", ja: "子予算") }
            static func childBudget(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.childBudget", vi: "Ngân sách con", en: "Child budget", ja: "子予算", language: language) }
            static var childBudgets: String { L10n.tr("planning.planning.childBudgets", vi: "Ngân sách con", en: "Child budgets", ja: "子カテゴリ予算") }
            static func childBudgets(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.childBudgets", vi: "Ngân sách con", en: "Child budgets", ja: "子カテゴリ予算", language: language) }
            static func childBudgetsTotalValueAboveTheParent(_ arg1: String, _ arg2: String) -> String {
                L10n.format("planning.planning.childBudgetsTotalValueAboveTheParent", vi: "Tổng ngân sách con %@ vượt ngân sách cha %@.", en: "Child budgets total %@, above the parent budget %@.", ja: "子予算の合計 %@ が親予算 %@ を超えています。", arg1, arg2)
            }
            static func childBudgetsTotalValueAboveTheParent(_ arg1: String, _ arg2: String, language: MistiaAppLanguage) -> String {
                L10n.format("planning.planning.childBudgetsTotalValueAboveTheParent", vi: "Tổng ngân sách con %@ vượt ngân sách cha %@.", en: "Child budgets total %@, above the parent budget %@.", ja: "子予算の合計 %@ が親予算 %@ を超えています。", language: language, arg1, arg2)
            }
            static var chooseACategoryBeforeSaving: String { L10n.tr("planning.planning.chooseACategoryBeforeSaving", vi: "Chọn danh mục trước khi lưu.", en: "Choose a category before saving.", ja: "保存する前にカテゴリを選択してください。") }
            static func chooseACategoryBeforeSaving(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.chooseACategoryBeforeSaving", vi: "Chọn danh mục trước khi lưu.", en: "Choose a category before saving.", ja: "保存する前にカテゴリを選択してください。", language: language) }
            static var chooseAPaymentWalletForThisBill: String { L10n.tr("planning.planning.chooseAPaymentWalletForThisBill", vi: "Chọn ví thanh toán cho hóa đơn.", en: "Choose a payment wallet for this bill.", ja: "この請求の支払いウォレットを選択してください。") }
            static func chooseAPaymentWalletForThisBill(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.chooseAPaymentWalletForThisBill", vi: "Chọn ví thanh toán cho hóa đơn.", en: "Choose a payment wallet for this bill.", ja: "この請求の支払いウォレットを選択してください。", language: language) }
            static var chooseAPaymentWalletForThisItem: String { L10n.tr("planning.planning.chooseAPaymentWalletForThisItem", vi: "Chọn ví thanh toán cho khoản này.", en: "Choose a payment wallet for this item.", ja: "この項目の支払いウォレットを選択してください。") }
            static func chooseAPaymentWalletForThisItem(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.chooseAPaymentWalletForThisItem", vi: "Chọn ví thanh toán cho khoản này.", en: "Choose a payment wallet for this item.", ja: "この項目の支払いウォレットを選択してください。", language: language) }
            static var chooseAnExpenseChildCategoryForThis: String { L10n.tr("planning.planning.chooseAnExpenseChildCategoryForThis", vi: "Chọn danh mục con cho hóa đơn này.", en: "Choose an expense child category for this bill.", ja: "この請求に使う支出カテゴリを選択してください。") }
            static func chooseAnExpenseChildCategoryForThis(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.chooseAnExpenseChildCategoryForThis", vi: "Chọn danh mục con cho hóa đơn này.", en: "Choose an expense child category for this bill.", ja: "この請求に使う支出カテゴリを選択してください。", language: language) }
            static var chooseCategory: String { L10n.tr("planning.planning.chooseCategory", vi: "Chọn danh mục", en: "Choose category", ja: "カテゴリを選択") }
            static func chooseCategory(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.chooseCategory", vi: "Chọn danh mục", en: "Choose category", ja: "カテゴリを選択", language: language) }
            static var chooseChildCategory: String { L10n.tr("planning.planning.chooseChildCategory", vi: "Chọn danh mục con", en: "Choose child category", ja: "子カテゴリを選択") }
            static func chooseChildCategory(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.chooseChildCategory", vi: "Chọn danh mục con", en: "Choose child category", ja: "子カテゴリを選択", language: language) }
            static var chooseMonth: String { L10n.tr("planning.planning.chooseMonth", vi: "Chọn tháng", en: "Choose month", ja: "月を選択") }
            static func chooseMonth(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.chooseMonth", vi: "Chọn tháng", en: "Choose month", ja: "月を選択", language: language) }
            static var chooseWallet: String { L10n.tr("planning.planning.chooseWallet", vi: "Chọn ví", en: "Choose wallet", ja: "ウォレットを選択") }
            static func chooseWallet(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.chooseWallet", vi: "Chọn ví", en: "Choose wallet", ja: "ウォレットを選択", language: language) }
            static var close: String { L10n.tr("planning.planning.close", vi: "Chốt", en: "Close", ja: "締め") }
            static func close(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.close", vi: "Chốt", en: "Close", ja: "締め", language: language) }
            static var closestToGoal: String { L10n.tr("planning.planning.closestToGoal", vi: "Gần đạt nhất", en: "Closest to goal", ja: "達成まであと少し") }
            static func closestToGoal(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.closestToGoal", vi: "Gần đạt nhất", en: "Closest to goal", ja: "達成まであと少し", language: language) }
            static var completed: String { L10n.tr("planning.planning.completed", vi: "Hoàn tất", en: "Completed", ja: "完了") }
            static func completed(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.completed", vi: "Hoàn tất", en: "Completed", ja: "完了", language: language) }
            static var couldnTArchiveThisBillRightNow: String { L10n.tr("planning.planning.couldnTArchiveThisBillRightNow", vi: "Không thể lưu trữ hóa đơn lúc này.", en: "Couldn't archive this bill right now.", ja: "現在この請求をアーカイブできません。") }
            static func couldnTArchiveThisBillRightNow(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.couldnTArchiveThisBillRightNow", vi: "Không thể lưu trữ hóa đơn lúc này.", en: "Couldn't archive this bill right now.", ja: "現在この請求をアーカイブできません。", language: language) }
            static var couldnTArchiveThisBudgetRightNow: String { L10n.tr("planning.planning.couldnTArchiveThisBudgetRightNow", vi: "Không thể lưu trữ ngân sách lúc này.", en: "Couldn't archive this budget right now.", ja: "現在この予算をアーカイブできません。") }
            static func couldnTArchiveThisBudgetRightNow(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.couldnTArchiveThisBudgetRightNow", vi: "Không thể lưu trữ ngân sách lúc này.", en: "Couldn't archive this budget right now.", ja: "現在この予算をアーカイブできません。", language: language) }
            static var couldnTDeleteThisBudgetRightNow: String { L10n.tr("planning.planning.couldnTDeleteThisBudgetRightNow", vi: "Không thể xóa ngân sách này lúc này.", en: "Couldn't delete this budget right now.", ja: "現在、この予算を削除できません。") }
            static func couldnTDeleteThisBudgetRightNow(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.couldnTDeleteThisBudgetRightNow", vi: "Không thể xóa ngân sách này lúc này.", en: "Couldn't delete this budget right now.", ja: "現在、この予算を削除できません。", language: language) }
            static var couldnTDeleteThisGoalRightNow: String { L10n.tr("planning.planning.couldnTDeleteThisGoalRightNow", vi: "Không thể xóa mục tiêu lúc này.", en: "Couldn't delete this goal right now.", ja: "現在この目標を削除できません。") }
            static func couldnTDeleteThisGoalRightNow(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.couldnTDeleteThisGoalRightNow", vi: "Không thể xóa mục tiêu lúc này.", en: "Couldn't delete this goal right now.", ja: "現在この目標を削除できません。", language: language) }
            static var couldnTDeleteThisItemRightNow: String { L10n.tr("planning.planning.couldnTDeleteThisItemRightNow", vi: "Không thể xóa khoản này lúc này.", en: "Couldn't delete this item right now.", ja: "現在この項目を削除できません。") }
            static func couldnTDeleteThisItemRightNow(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.couldnTDeleteThisItemRightNow", vi: "Không thể xóa khoản này lúc này.", en: "Couldn't delete this item right now.", ja: "現在この項目を削除できません。", language: language) }
            static var couldnTPauseThisBillRightNow: String { L10n.tr("planning.planning.couldnTPauseThisBillRightNow", vi: "Không thể tạm dừng hóa đơn lúc này.", en: "Couldn't pause this bill right now.", ja: "現在この請求を一時停止できません。") }
            static func couldnTPauseThisBillRightNow(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.couldnTPauseThisBillRightNow", vi: "Không thể tạm dừng hóa đơn lúc này.", en: "Couldn't pause this bill right now.", ja: "現在この請求を一時停止できません。", language: language) }
            static var couldnTResumeThisBillRightNow: String { L10n.tr("planning.planning.couldnTResumeThisBillRightNow", vi: "Không thể bắt đầu lại hóa đơn lúc này.", en: "Couldn't resume this bill right now.", ja: "現在この請求を再開できません。") }
            static func couldnTResumeThisBillRightNow(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.couldnTResumeThisBillRightNow", vi: "Không thể bắt đầu lại hóa đơn lúc này.", en: "Couldn't resume this bill right now.", ja: "現在この請求を再開できません。", language: language) }
            static var couldnTSaveTheArchiveStateFor: String { L10n.tr("planning.planning.couldnTSaveTheArchiveStateFor", vi: "Không thể lưu trạng thái lưu trữ của thẻ.", en: "Couldn't save the archive state for this card.", ja: "このカードのアーカイブ状態を保存できません。") }
            static func couldnTSaveTheArchiveStateFor(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.couldnTSaveTheArchiveStateFor", vi: "Không thể lưu trạng thái lưu trữ của thẻ.", en: "Couldn't save the archive state for this card.", ja: "このカードのアーカイブ状態を保存できません。", language: language) }
            static var couldnTSaveThisBillRightNow: String { L10n.tr("planning.planning.couldnTSaveThisBillRightNow", vi: "Không thể lưu hóa đơn lúc này.", en: "Couldn't save this bill right now.", ja: "現在この請求を保存できません。") }
            static func couldnTSaveThisBillRightNow(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.couldnTSaveThisBillRightNow", vi: "Không thể lưu hóa đơn lúc này.", en: "Couldn't save this bill right now.", ja: "現在この請求を保存できません。", language: language) }
            static var couldnTSaveThisBudgetRightNow: String { L10n.tr("planning.planning.couldnTSaveThisBudgetRightNow", vi: "Không thể lưu ngân sách lúc này.", en: "Couldn't save this budget right now.", ja: "現在この予算を保存できません。") }
            static func couldnTSaveThisBudgetRightNow(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.couldnTSaveThisBudgetRightNow", vi: "Không thể lưu ngân sách lúc này.", en: "Couldn't save this budget right now.", ja: "現在この予算を保存できません。", language: language) }
            static var couldnTSaveThisCardRightNow: String { L10n.tr("planning.planning.couldnTSaveThisCardRightNow", vi: "Không thể lưu thẻ lúc này.", en: "Couldn't save this card right now.", ja: "現在このカードを保存できません。") }
            static func couldnTSaveThisCardRightNow(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.couldnTSaveThisCardRightNow", vi: "Không thể lưu thẻ lúc này.", en: "Couldn't save this card right now.", ja: "現在このカードを保存できません。", language: language) }
            static var couldnTSaveThisGoalRightNow: String { L10n.tr("planning.planning.couldnTSaveThisGoalRightNow", vi: "Không thể lưu mục tiêu lúc này.", en: "Couldn't save this goal right now.", ja: "現在この目標を保存できません。") }
            static func couldnTSaveThisGoalRightNow(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.couldnTSaveThisGoalRightNow", vi: "Không thể lưu mục tiêu lúc này.", en: "Couldn't save this goal right now.", ja: "現在この目標を保存できません。", language: language) }
            static var couldnTSaveThisItemRightNow: String { L10n.tr("planning.planning.couldnTSaveThisItemRightNow", vi: "Không thể lưu khoản này lúc này.", en: "Couldn't save this item right now.", ja: "現在この項目を保存できません。") }
            static func couldnTSaveThisItemRightNow(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.couldnTSaveThisItemRightNow", vi: "Không thể lưu khoản này lúc này.", en: "Couldn't save this item right now.", ja: "現在この項目を保存できません。", language: language) }
            static var couldnTSend: String { L10n.tr("planning.planning.couldnTSend", vi: "Chưa thể gửi", en: "Couldn't send", ja: "送信できませんでした") }
            static func couldnTSend(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.couldnTSend", vi: "Chưa thể gửi", en: "Couldn't send", ja: "送信できませんでした", language: language) }
            static var couldnTSendTheRequestRightNow: String { L10n.tr("planning.planning.couldnTSendTheRequestRightNow", vi: "Không thể gửi yêu cầu lúc này.", en: "Couldn't send the request right now.", ja: "現在リクエストは送信できません。") }
            static func couldnTSendTheRequestRightNow(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.couldnTSendTheRequestRightNow", vi: "Không thể gửi yêu cầu lúc này.", en: "Couldn't send the request right now.", ja: "現在リクエストは送信できません。", language: language) }
            static var createCategoryBudgetsToTrackWhatYou: String { L10n.tr("planning.planning.createCategoryBudgetsToTrackWhatYou", vi: "Tạo ngân sách theo từng danh mục để theo dõi số tiền đã dùng và số ngày còn lại trong tháng.", en: "Create category budgets to track what you've spent and how many days are left in the month.", ja: "カテゴリごとに予算を作成すると、使った金額と月末までの残り日数を追跡できます。") }
            static func createCategoryBudgetsToTrackWhatYou(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.createCategoryBudgetsToTrackWhatYou", vi: "Tạo ngân sách theo từng danh mục để theo dõi số tiền đã dùng và số ngày còn lại trong tháng.", en: "Create category budgets to track what you've spent and how many days are left in the month.", ja: "カテゴリごとに予算を作成すると、使った金額と月末までの残り日数を追跡できます。", language: language) }
            static var createRequestApproved: String { L10n.tr("planning.planning.createRequestApproved", vi: "Đã chấp nhận yêu cầu thêm mới", en: "Create request approved", ja: "作成リクエストが承認済み") }
            static func createRequestApproved(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.createRequestApproved", vi: "Đã chấp nhận yêu cầu thêm mới", en: "Create request approved", ja: "作成リクエストが承認済み", language: language) }
            static var createRequestSent: String { L10n.tr("planning.planning.createRequestSent", vi: "Đã gửi yêu cầu thêm mới", en: "Create request sent", ja: "作成リクエスト送信済み") }
            static func createRequestSent(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.createRequestSent", vi: "Đã gửi yêu cầu thêm mới", en: "Create request sent", ja: "作成リクエスト送信済み", language: language) }
            static var createRequested: String { L10n.tr("planning.planning.createRequested", vi: "Đã yêu cầu thêm mới", en: "Create requested", ja: "作成権限をリクエスト済み") }
            static func createRequested(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.createRequested", vi: "Đã yêu cầu thêm mới", en: "Create requested", ja: "作成権限をリクエスト済み", language: language) }
            static var creditCard: String { L10n.tr("planning.planning.creditCard", vi: "thẻ tín dụng", en: "credit card", ja: "クレジットカード") }
            static func creditCard(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.creditCard", vi: "thẻ tín dụng", en: "credit card", ja: "クレジットカード", language: language) }
            static var creditCards: String { L10n.tr("planning.planning.creditCards", vi: "Thẻ tín dụng", en: "Credit cards", ja: "クレジットカード") }
            static func creditCards(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.creditCards", vi: "Thẻ tín dụng", en: "Credit cards", ja: "クレジットカード", language: language) }
            static var creditLimit: String { L10n.tr("planning.planning.creditLimit", vi: "Hạn mức", en: "Credit limit", ja: "利用限度額") }
            static func creditLimit(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.creditLimit", vi: "Hạn mức", en: "Credit limit", ja: "利用限度額", language: language) }
            static var currentAmount: String { L10n.tr("planning.planning.currentAmount", vi: "Số tiền hiện tại", en: "Current amount", ja: "現在額") }
            static func currentAmount(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.currentAmount", vi: "Số tiền hiện tại", en: "Current amount", ja: "現在額", language: language) }
            static var currentDebt: String { L10n.tr("planning.planning.currentDebt", vi: "Dư nợ hiện tại", en: "Current debt", ja: "現在の利用額") }
            static func currentDebt(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.currentDebt", vi: "Dư nợ hiện tại", en: "Current debt", ja: "現在の利用額", language: language) }
            static var currentMonth: String { L10n.tr("planning.planning.currentMonth", vi: "Tháng hiện tại", en: "Current month", ja: "今月") }
            static func currentMonth(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.currentMonth", vi: "Tháng hiện tại", en: "Current month", ja: "今月", language: language) }
            static var cycle: String { L10n.tr("planning.planning.cycle", vi: "Chu kỳ", en: "Cycle", ja: "周期") }
            static func cycle(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.cycle", vi: "Chu kỳ", en: "Cycle", ja: "周期", language: language) }
            static func dayValue(_ value: String) -> String {
                L10n.format("planning.planning.dayValue", vi: "Ngày %@", en: "Day %@", ja: "%@ 日", value)
            }
            static func dayValue(_ value: String, language: MistiaAppLanguage) -> String {
                L10n.format("planning.planning.dayValue", vi: "Ngày %@", en: "Day %@", ja: "%@ 日", language: language, value)
            }
            static func dayValueNextMonth(_ value: String) -> String {
                L10n.format("planning.planning.dayValueNextMonth", vi: "Ngày %@ tháng sau", en: "Day %@ next month", ja: "翌月 %@ 日", value)
            }
            static func dayValueNextMonth(_ value: String, language: MistiaAppLanguage) -> String {
                L10n.format("planning.planning.dayValueNextMonth", vi: "Ngày %@ tháng sau", en: "Day %@ next month", ja: "翌月 %@ 日", language: language, value)
            }
            static var deadline: String { L10n.tr("planning.planning.deadline", vi: "Hạn cuối", en: "Deadline", ja: "期限日") }
            static func deadline(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.deadline", vi: "Hạn cuối", en: "Deadline", ja: "期限日", language: language) }
            static var deadlineCannotBeBeforeThePaymentDate: String { L10n.tr("planning.planning.deadlineCannotBeBeforeThePaymentDate", vi: "Hạn cuối không được trước ngày thanh toán.", en: "Deadline cannot be before the payment date.", ja: "期限日は支払開始日より前にできません。") }
            static func deadlineCannotBeBeforeThePaymentDate(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.deadlineCannotBeBeforeThePaymentDate", vi: "Hạn cuối không được trước ngày thanh toán.", en: "Deadline cannot be before the payment date.", ja: "期限日は支払開始日より前にできません。", language: language) }
            static var deleteBudget: String { L10n.tr("planning.planning.deleteBudget", vi: "Xóa ngân sách", en: "Delete budget", ja: "予算を削除") }
            static func deleteBudget(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.deleteBudget", vi: "Xóa ngân sách", en: "Delete budget", ja: "予算を削除", language: language) }
            static var deleteBudgetMessage: String { L10n.tr("planning.planning.deleteBudgetMessage", vi: "Ngân sách này sẽ bị xóa.", en: "This budget will be deleted.", ja: "この予算を削除します。") }
            static func deleteBudgetMessage(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.deleteBudgetMessage", vi: "Ngân sách này sẽ bị xóa.", en: "This budget will be deleted.", ja: "この予算を削除します。", language: language) }
            static var deleteCurrentBudgetMessage: String { L10n.tr("planning.planning.deleteCurrentBudgetMessage", vi: "Ngân sách tháng hiện tại sẽ bị xóa. Nếu đây là ngân sách cuối cùng trong nhánh, dữ liệu gia đình của nhánh sẽ tắt.", en: "The current-month budget will be deleted. If it is the last budget in this branch, family data for the branch will turn off.", ja: "当月の予算を削除します。この枝の最後の予算の場合、枝の家族データはオフになります。") }
            static func deleteCurrentBudgetMessage(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.deleteCurrentBudgetMessage", vi: "Ngân sách tháng hiện tại sẽ bị xóa. Nếu đây là ngân sách cuối cùng trong nhánh, dữ liệu gia đình của nhánh sẽ tắt.", en: "The current-month budget will be deleted. If it is the last budget in this branch, family data for the branch will turn off.", ja: "当月の予算を削除します。この枝の最後の予算の場合、枝の家族データはオフになります。", language: language) }
            static var deleteGoal: String { L10n.tr("planning.planning.deleteGoal", vi: "Xóa mục tiêu", en: "Delete goal", ja: "目標を削除") }
            static func deleteGoal(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.deleteGoal", vi: "Xóa mục tiêu", en: "Delete goal", ja: "目標を削除", language: language) }
            static var deleteThisGoal: String { L10n.tr("planning.planning.deleteThisGoal", vi: "Xóa mục tiêu này?", en: "Delete this goal?", ja: "この目標を削除しますか？") }
            static func deleteThisGoal(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.deleteThisGoal", vi: "Xóa mục tiêu này?", en: "Delete this goal?", ja: "この目標を削除しますか？", language: language) }
            static var deleteThisItem: String { L10n.tr("planning.planning.deleteThisItem", vi: "Xóa khoản này?", en: "Delete this item?", ja: "この項目を削除しますか？") }
            static func deleteThisItem(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.deleteThisItem", vi: "Xóa khoản này?", en: "Delete this item?", ja: "この項目を削除しますか？", language: language) }
            static var deleteThisItem2: String { L10n.tr("planning.planning.deleteThisItem2", vi: "Xóa khoản này", en: "Delete this item", ja: "この項目を削除") }
            static func deleteThisItem2(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.deleteThisItem2", vi: "Xóa khoản này", en: "Delete this item", ja: "この項目を削除", language: language) }
            static var deletedCategory: String { L10n.tr("planning.planning.deletedCategory", vi: "Danh mục đã xóa", en: "Deleted category", ja: "削除されたカテゴリ") }
            static func deletedCategory(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.deletedCategory", vi: "Danh mục đã xóa", en: "Deleted category", ja: "削除されたカテゴリ", language: language) }
            static var due: String { L10n.tr("planning.planning.due", vi: "Hạn", en: "To pay", ja: "支払") }
            static func due(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.due", vi: "Hạn", en: "To pay", ja: "支払", language: language) }
            static var due2: String { L10n.tr("planning.planning.due2", vi: "Cần trả", en: "To pay", ja: "支払いが必要") }
            static func due2(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.due2", vi: "Cần trả", en: "To pay", ja: "支払いが必要", language: language) }
            static var dueDay: String { L10n.tr("planning.planning.dueDay", vi: "Hạn trả", en: "Payment deadline", ja: "支払い期限") }
            static func dueDay(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.dueDay", vi: "Hạn trả", en: "Payment deadline", ja: "支払い期限", language: language) }
            static var dueToday: String { L10n.tr("planning.planning.dueToday", vi: "Cần trả hôm nay", en: "To pay today", ja: "本日支払いが必要") }
            static func dueToday(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.dueToday", vi: "Cần trả hôm nay", en: "To pay today", ja: "本日支払いが必要", language: language) }
            static var earlyPayment: String { L10n.tr("planning.planning.earlyPayment", vi: "Thanh toán trước", en: "Early payment", ja: "前倒し支払い") }
            static func earlyPayment(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.earlyPayment", vi: "Thanh toán trước", en: "Early payment", ja: "前倒し支払い", language: language) }
            static var editRequestApproved: String { L10n.tr("planning.planning.editRequestApproved", vi: "Đã chấp nhận yêu cầu chỉnh sửa", en: "Edit request approved", ja: "編集リクエストが承認済み") }
            static func editRequestApproved(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.editRequestApproved", vi: "Đã chấp nhận yêu cầu chỉnh sửa", en: "Edit request approved", ja: "編集リクエストが承認済み", language: language) }
            static var editRequestSent: String { L10n.tr("planning.planning.editRequestSent", vi: "Đã gửi yêu cầu chỉnh sửa", en: "Edit request sent", ja: "編集リクエスト送信済み") }
            static func editRequestSent(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.editRequestSent", vi: "Đã gửi yêu cầu chỉnh sửa", en: "Edit request sent", ja: "編集リクエスト送信済み", language: language) }
            static var editRequested: String { L10n.tr("planning.planning.editRequested", vi: "Đã yêu cầu chỉnh sửa", en: "Edit requested", ja: "編集権限をリクエスト済み") }
            static func editRequested(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.editRequested", vi: "Đã yêu cầu chỉnh sửa", en: "Edit requested", ja: "編集権限をリクエスト済み", language: language) }
            static var enableFamilyBudgetDataCancel: String { L10n.tr("planning.planning.enableFamilyBudgetDataCancel", vi: "Hủy", en: "Cancel", ja: "キャンセル") }
            static func enableFamilyBudgetDataCancel(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.enableFamilyBudgetDataCancel", vi: "Hủy", en: "Cancel", ja: "キャンセル", language: language) }
            static var enableFamilyBudgetDataConfirm: String { L10n.tr("planning.planning.enableFamilyBudgetDataConfirm", vi: "Bật", en: "Turn on", ja: "オンにする") }
            static func enableFamilyBudgetDataConfirm(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.enableFamilyBudgetDataConfirm", vi: "Bật", en: "Turn on", ja: "オンにする", language: language) }
            static var enableFamilyBudgetDataMessage: String { L10n.tr("planning.planning.enableFamilyBudgetDataMessage", vi: "Từ bây giờ, mọi ngân sách trong nhánh này sẽ tính cả chi tiêu gia đình cùng danh mục. Muốn tắt, bạn phải xóa ngân sách tháng hiện tại của nhánh.", en: "From now on, every budget in this branch will include family spending in matching categories. To turn it off, you must delete the current-month budgets in this branch.", ja: "今後、この枝のすべての予算は一致するカテゴリの家族支出も集計します。オフにするには、この枝の当月予算を削除する必要があります。") }
            static func enableFamilyBudgetDataMessage(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.enableFamilyBudgetDataMessage", vi: "Từ bây giờ, mọi ngân sách trong nhánh này sẽ tính cả chi tiêu gia đình cùng danh mục. Muốn tắt, bạn phải xóa ngân sách tháng hiện tại của nhánh.", en: "From now on, every budget in this branch will include family spending in matching categories. To turn it off, you must delete the current-month budgets in this branch.", ja: "今後、この枝のすべての予算は一致するカテゴリの家族支出も集計します。オフにするには、この枝の当月予算を削除する必要があります。", language: language) }
            static var enableFamilyBudgetDataTitle: String { L10n.tr("planning.planning.enableFamilyBudgetDataTitle", vi: "Bật dữ liệu gia đình?", en: "Turn on family data?", ja: "家族データをオンにしますか？") }
            static func enableFamilyBudgetDataTitle(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.enableFamilyBudgetDataTitle", vi: "Bật dữ liệu gia đình?", en: "Turn on family data?", ja: "家族データをオンにしますか？", language: language) }
            static var enterABillNameBeforeSaving: String { L10n.tr("planning.planning.enterABillNameBeforeSaving", vi: "Nhập tên hóa đơn trước khi lưu.", en: "Enter a bill name before saving.", ja: "保存する前に請求名を入力してください。") }
            static func enterABillNameBeforeSaving(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.enterABillNameBeforeSaving", vi: "Nhập tên hóa đơn trước khi lưu.", en: "Enter a bill name before saving.", ja: "保存する前に請求名を入力してください。", language: language) }
            static var enterABudgetAmountGreaterThan: String { L10n.tr("planning.planning.enterABudgetAmountGreaterThan", vi: "Nhập số tiền ngân sách lớn hơn 0.", en: "Enter a budget amount greater than 0.", ja: "0 より大きい予算金額を入力してください。") }
            static func enterABudgetAmountGreaterThan(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.enterABudgetAmountGreaterThan", vi: "Nhập số tiền ngân sách lớn hơn 0.", en: "Enter a budget amount greater than 0.", ja: "0 より大きい予算金額を入力してください。", language: language) }
            static var enterACardNameBeforeSaving: String { L10n.tr("planning.planning.enterACardNameBeforeSaving", vi: "Nhập tên thẻ trước khi lưu.", en: "Enter a card name before saving.", ja: "保存する前にカード名を入力してください。") }
            static func enterACardNameBeforeSaving(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.enterACardNameBeforeSaving", vi: "Nhập tên thẻ trước khi lưu.", en: "Enter a card name before saving.", ja: "保存する前にカード名を入力してください。", language: language) }
            static var enterAGoalNameBeforeSaving: String { L10n.tr("planning.planning.enterAGoalNameBeforeSaving", vi: "Nhập tên mục tiêu trước khi lưu.", en: "Enter a goal name before saving.", ja: "保存する前に目標名を入力してください。") }
            static func enterAGoalNameBeforeSaving(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.enterAGoalNameBeforeSaving", vi: "Nhập tên mục tiêu trước khi lưu.", en: "Enter a goal name before saving.", ja: "保存する前に目標名を入力してください。", language: language) }
            static var enterANameBeforeSaving: String { L10n.tr("planning.planning.enterANameBeforeSaving", vi: "Nhập tên khoản trước khi lưu.", en: "Enter a name before saving.", ja: "保存する前に名前を入力してください。") }
            static func enterANameBeforeSaving(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.enterANameBeforeSaving", vi: "Nhập tên khoản trước khi lưu.", en: "Enter a name before saving.", ja: "保存する前に名前を入力してください。", language: language) }
            static var enterATargetAmountGreaterThan: String { L10n.tr("planning.planning.enterATargetAmountGreaterThan", vi: "Nhập số tiền mục tiêu lớn hơn 0.", en: "Enter a target amount greater than 0.", ja: "0 より大きい目標金額を入力してください。") }
            static func enterATargetAmountGreaterThan(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.enterATargetAmountGreaterThan", vi: "Nhập số tiền mục tiêu lớn hơn 0.", en: "Enter a target amount greater than 0.", ja: "0 より大きい目標金額を入力してください。", language: language) }
            static var enterAnAmountPerCycleGreaterThan: String { L10n.tr("planning.planning.enterAnAmountPerCycleGreaterThan", vi: "Nhập số tiền mỗi kỳ lớn hơn 0.", en: "Enter an amount per cycle greater than 0.", ja: "各回の金額は 0 より大きくしてください。") }
            static func enterAnAmountPerCycleGreaterThan(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.enterAnAmountPerCycleGreaterThan", vi: "Nhập số tiền mỗi kỳ lớn hơn 0.", en: "Enter an amount per cycle greater than 0.", ja: "各回の金額は 0 より大きくしてください。", language: language) }
            static var familyBudgetDataNeedsInternet: String { L10n.tr("planning.planning.familyBudgetDataNeedsInternet", vi: "Cần có internet để bật dữ liệu gia đình cho ngân sách.", en: "Internet is required to turn on family data for budgets.", ja: "予算で家族データをオンにするにはインターネット接続が必要です。") }
            static func familyBudgetDataNeedsInternet(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.familyBudgetDataNeedsInternet", vi: "Cần có internet để bật dữ liệu gia đình cho ngân sách.", en: "Internet is required to turn on family data for budgets.", ja: "予算で家族データをオンにするにはインターネット接続が必要です。", language: language) }
            static var familyBudgetDataRefreshFailed: String { L10n.tr("planning.planning.familyBudgetDataRefreshFailed", vi: "Không thể làm mới dữ liệu gia đình lúc này. Hãy thử lại khi kết nối ổn định.", en: "Could not refresh family data right now. Try again when the connection is stable.", ja: "現在、家族データを更新できません。接続が安定してからもう一度お試しください。") }
            static func familyBudgetDataRefreshFailed(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.familyBudgetDataRefreshFailed", vi: "Không thể làm mới dữ liệu gia đình lúc này. Hãy thử lại khi kết nối ổn định.", en: "Could not refresh family data right now. Try again when the connection is stable.", ja: "現在、家族データを更新できません。接続が安定してからもう一度お試しください。", language: language) }
            static func frequencyEveryValueMonthS(_ value: String) -> String {
                L10n.format("planning.planning.frequencyEveryValueMonthS", vi: "Tần suất: %@ tháng", en: "Frequency: every %@ month(s)", ja: "頻度: %@ か月ごと", value)
            }
            static func frequencyEveryValueMonthS(_ value: String, language: MistiaAppLanguage) -> String {
                L10n.format("planning.planning.frequencyEveryValueMonthS", vi: "Tần suất: %@ tháng", en: "Frequency: every %@ month(s)", ja: "頻度: %@ か月ごと", language: language, value)
            }
            static var goal: String { L10n.tr("planning.planning.goal", vi: "Mục tiêu", en: "Goal", ja: "目標") }
            static func goal(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.goal", vi: "Mục tiêu", en: "Goal", ja: "目標", language: language) }
            static var goalName: String { L10n.tr("planning.planning.goalName", vi: "Tên mục tiêu", en: "Goal name", ja: "目標名") }
            static func goalName(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.goalName", vi: "Tên mục tiêu", en: "Goal name", ja: "目標名", language: language) }
            static var goals: String { L10n.tr("planning.planning.goals", vi: "mục tiêu", en: "goals", ja: "目標") }
            static func goals(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.goals", vi: "mục tiêu", en: "goals", ja: "目標", language: language) }
            static var goals2: String { L10n.tr("planning.planning.goals2", vi: "Mục tiêu", en: "Goals", ja: "目標") }
            static func goals2(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.goals2", vi: "Mục tiêu", en: "Goals", ja: "目標", language: language) }
            static var hANMI: String { L10n.tr("planning.planning.hANMI", vi: "Hóa đơn mới", en: "New bill", ja: "新しい請求書") }
            static func hANMI(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.hANMI", vi: "Hóa đơn mới", en: "New bill", ja: "新しい請求書", language: language) }
            static var hasDeadline: String { L10n.tr("planning.planning.hasDeadline", vi: "Có hạn cuối", en: "Has deadline", ja: "期限日あり") }
            static func hasDeadline(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.hasDeadline", vi: "Có hạn cuối", en: "Has deadline", ja: "期限日あり", language: language) }
            static var iconKhoNTrGPVay: String { L10n.tr("planning.planning.iconKhoNTrGPVay", vi: "Icon khoản trả góp / vay", en: "Installment / loan icon", ja: "分割払い／ローンアイコン") }
            static func iconKhoNTrGPVay(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.iconKhoNTrGPVay", vi: "Icon khoản trả góp / vay", en: "Installment / loan icon", ja: "分割払い／ローンアイコン", language: language) }
            static var iconMCTiU: String { L10n.tr("planning.planning.iconMCTiU", vi: "Icon mục tiêu", en: "Goal icon", ja: "目標アイコン") }
            static func iconMCTiU(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.iconMCTiU", vi: "Icon mục tiêu", en: "Goal icon", ja: "目標アイコン", language: language) }
            static var identity: String { L10n.tr("planning.planning.identity", vi: "Nhận diện", en: "Identity", ja: "識別情報") }
            static func identity(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.identity", vi: "Nhận diện", en: "Identity", ja: "識別情報", language: language) }
            static var includeFamilySpending: String { L10n.tr("planning.planning.includeFamilySpending", vi: "Tính cả chi tiêu gia đình", en: "Include family spending", ja: "家族の支出も含める") }
            static func includeFamilySpending(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.includeFamilySpending", vi: "Tính cả chi tiêu gia đình", en: "Include family spending", ja: "家族の支出も含める", language: language) }
            static var installmentLoan: String { L10n.tr("planning.planning.installmentLoan", vi: "Khoản trả góp / vay", en: "Installment / loan", ja: "分割払い・借入") }
            static func installmentLoan(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.installmentLoan", vi: "Khoản trả góp / vay", en: "Installment / loan", ja: "分割払い・借入", language: language) }
            static var installmentLoan2: String { L10n.tr("planning.planning.installmentLoan2", vi: "Trả góp / vay", en: "Installment / loan", ja: "分割払い・借入") }
            static func installmentLoan2(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.installmentLoan2", vi: "Trả góp / vay", en: "Installment / loan", ja: "分割払い・借入", language: language) }
            static var installmentsLoans: String { L10n.tr("planning.planning.installmentsLoans", vi: "trả góp / vay", en: "installments / loans", ja: "分割払い・借入") }
            static func installmentsLoans(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.installmentsLoans", vi: "trả góp / vay", en: "installments / loans", ja: "分割払い・借入", language: language) }
            static var installmentsLoans2: String { L10n.tr("planning.planning.installmentsLoans2", vi: "Trả góp / vay", en: "Installments / loans", ja: "分割払い・借入") }
            static func installmentsLoans2(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.installmentsLoans2", vi: "Trả góp / vay", en: "Installments / loans", ja: "分割払い・借入", language: language) }
            static var issuerName: String { L10n.tr("planning.planning.issuerName", vi: "Tên đơn vị phát hành", en: "Issuer name", ja: "発行会社名") }
            static func issuerName(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.issuerName", vi: "Tên đơn vị phát hành", en: "Issuer name", ja: "発行会社名", language: language) }
            static var khoNMI: String { L10n.tr("planning.planning.khoNMI", vi: "Khoản mới", en: "New item", ja: "新しい項目") }
            static func khoNMI(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.khoNMI", vi: "Khoản mới", en: "New item", ja: "新しい項目", language: language) }
            static var lastDigits: String { L10n.tr("planning.planning.lastDigits", vi: "4 số cuối", en: "Last 4 digits", ja: "下4桁") }
            static func lastDigits(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.lastDigits", vi: "4 số cuối", en: "Last 4 digits", ja: "下4桁", language: language) }
            static var linkOrAddCardsHereToShow: String { L10n.tr("planning.planning.linkOrAddCardsHereToShow", vi: "Liên kết hoặc thêm thẻ ngay tại đây để hiển thị credit card và theo dõi ngày thanh toán.", en: "Link or add cards here to show your credit cards and track payment dates.", ja: "ここでカードを追加または連携すると、クレジットカードと支払日を管理できます。") }
            static func linkOrAddCardsHereToShow(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.linkOrAddCardsHereToShow", vi: "Liên kết hoặc thêm thẻ ngay tại đây để hiển thị credit card và theo dõi ngày thanh toán.", en: "Link or add cards here to show your credit cards and track payment dates.", ja: "ここでカードを追加または連携すると、クレジットカードと支払日を管理できます。", language: language) }
            static var linkedWallet: String { L10n.tr("planning.planning.linkedWallet", vi: "Ví liên kết", en: "Linked wallet", ja: "連携ウォレット") }
            static func linkedWallet(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.linkedWallet", vi: "Ví liên kết", en: "Linked wallet", ja: "連携ウォレット", language: language) }
            static func linkedWalletValue(_ value: String) -> String {
                L10n.format("planning.planning.linkedWalletValue", vi: "Ví liên kết: %@", en: "Linked wallet: %@", ja: "連携ウォレット: %@", value)
            }
            static func linkedWalletValue(_ value: String, language: MistiaAppLanguage) -> String {
                L10n.format("planning.planning.linkedWalletValue", vi: "Ví liên kết: %@", en: "Linked wallet: %@", ja: "連携ウォレット: %@", language: language, value)
            }
            static var mCTiUMI: String { L10n.tr("planning.planning.mCTiUMI", vi: "Mục tiêu mới", en: "New goal", ja: "新しい目標") }
            static func mCTiUMI(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.mCTiUMI", vi: "Mục tiêu mới", en: "New goal", ja: "新しい目標", language: language) }
            static var month: String { L10n.tr("planning.planning.month", vi: "Tháng", en: "Month", ja: "月") }
            static func month(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.month", vi: "Tháng", en: "Month", ja: "月", language: language) }
            static var monthEnded: String { L10n.tr("planning.planning.monthEnded", vi: "Tháng đã kết thúc", en: "Month ended", ja: "月が終了しました") }
            static func monthEnded(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.monthEnded", vi: "Tháng đã kết thúc", en: "Month ended", ja: "月が終了しました", language: language) }
            static func monthValue(_ value: String) -> String {
                L10n.format("planning.planning.monthValue", vi: "Tháng %@", en: "Month %@", ja: "%@月", value)
            }
            static func monthValue(_ value: String, language: MistiaAppLanguage) -> String {
                L10n.format("planning.planning.monthValue", vi: "Tháng %@", en: "Month %@", ja: "%@月", language: language, value)
            }
            static var monthly: String { L10n.tr("planning.planning.monthly", vi: "Theo tháng", en: "Monthly", ja: "毎月") }
            static func monthly(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.monthly", vi: "Theo tháng", en: "Monthly", ja: "毎月", language: language) }
            static func monthlyBudgetTotalForMonth(_ value: String) -> String {
                L10n.format("planning.planning.monthlyBudgetTotalForMonth", vi: "Tổng ngân sách %@", en: "Total budget for %@", ja: "%@ の予算合計", value)
            }
            static func monthlyBudgetTotalForMonth(_ value: String, language: MistiaAppLanguage) -> String {
                L10n.format("planning.planning.monthlyBudgetTotalForMonth", vi: "Tổng ngân sách %@", en: "Total budget for %@", ja: "%@ の予算合計", language: language, value)
            }
            static var name: String { L10n.tr("planning.planning.name", vi: "Tên khoản", en: "Name", ja: "名称") }
            static func name(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.name", vi: "Tên khoản", en: "Name", ja: "名称", language: language) }
            static func needValueMonth(_ value: String) -> String {
                L10n.format("planning.planning.needValueMonth", vi: "Cần thêm %@/tháng", en: "Need %@/month", ja: "毎月あと %@ 必要", value)
            }
            static func needValueMonth(_ value: String, language: MistiaAppLanguage) -> String {
                L10n.format("planning.planning.needValueMonth", vi: "Cần thêm %@/tháng", en: "Need %@/month", ja: "毎月あと %@ 必要", language: language, value)
            }
            static var nextMonth: String { L10n.tr("planning.planning.nextMonth", vi: "Tháng sau", en: "Next month", ja: "翌月") }
            static func nextMonth(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.nextMonth", vi: "Tháng sau", en: "Next month", ja: "翌月", language: language) }
            static var ngNSChMI: String { L10n.tr("planning.planning.ngNSChMI", vi: "Ngân sách mới", en: "New budget", ja: "新しい予算") }
            static func ngNSChMI(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.ngNSChMI", vi: "Ngân sách mới", en: "New budget", ja: "新しい予算", language: language) }
            static var noAmountYet: String { L10n.tr("planning.planning.noAmountYet", vi: "Chưa nhập số tiền", en: "No amount yet", ja: "金額未入力") }
            static func noAmountYet(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.noAmountYet", vi: "Chưa nhập số tiền", en: "No amount yet", ja: "金額未入力", language: language) }
            static var noBillsYet: String { L10n.tr("planning.planning.noBillsYet", vi: "Chưa có hóa đơn nào", en: "No bills yet", ja: "請求はまだありません") }
            static func noBillsYet(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.noBillsYet", vi: "Chưa có hóa đơn nào", en: "No bills yet", ja: "請求はまだありません", language: language) }
            static var noBudgetsYet: String { L10n.tr("planning.planning.noBudgetsYet", vi: "Chưa có ngân sách nào", en: "No budgets yet", ja: "予算はまだありません") }
            static func noBudgetsYet(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.noBudgetsYet", vi: "Chưa có ngân sách nào", en: "No budgets yet", ja: "予算はまだありません", language: language) }
            static var noCreateAccess: String { L10n.tr("planning.planning.noCreateAccess", vi: "Chưa có quyền thêm mới", en: "No create access", ja: "作成権限がありません") }
            static func noCreateAccess(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.noCreateAccess", vi: "Chưa có quyền thêm mới", en: "No create access", ja: "作成権限がありません", language: language) }
            static var noCreditCardsYet: String { L10n.tr("planning.planning.noCreditCardsYet", vi: "Chưa có thẻ tín dụng", en: "No credit cards yet", ja: "クレジットカードはまだありません") }
            static func noCreditCardsYet(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.noCreditCardsYet", vi: "Chưa có thẻ tín dụng", en: "No credit cards yet", ja: "クレジットカードはまだありません", language: language) }
            static var noEditAccess: String { L10n.tr("planning.planning.noEditAccess", vi: "Chưa có quyền chỉnh sửa", en: "No edit access", ja: "編集権限がありません") }
            static func noEditAccess(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.noEditAccess", vi: "Chưa có quyền chỉnh sửa", en: "No edit access", ja: "編集権限がありません", language: language) }
            static var noGoalsYet: String { L10n.tr("planning.planning.noGoalsYet", vi: "Chưa có mục tiêu nào", en: "No goals yet", ja: "目標はまだありません") }
            static func noGoalsYet(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.noGoalsYet", vi: "Chưa có mục tiêu nào", en: "No goals yet", ja: "目標はまだありません", language: language) }
            static var noInstallmentsOrLoansYet: String { L10n.tr("planning.planning.noInstallmentsOrLoansYet", vi: "Chưa có khoản trả góp / vay", en: "No installments or loans yet", ja: "分割払い・借入はまだありません") }
            static func noInstallmentsOrLoansYet(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.noInstallmentsOrLoansYet", vi: "Chưa có khoản trả góp / vay", en: "No installments or loans yet", ja: "分割払い・借入はまだありません", language: language) }
            static var noLinkedWallet: String { L10n.tr("planning.planning.noLinkedWallet", vi: "Chưa chọn ví liên kết", en: "No linked wallet", ja: "連携ウォレット未設定") }
            static func noLinkedWallet(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.noLinkedWallet", vi: "Chưa chọn ví liên kết", en: "No linked wallet", ja: "連携ウォレット未設定", language: language) }
            static var noWalletAccess: String { L10n.tr("planning.planning.noWalletAccess", vi: "Chưa có quyền thao tác ví", en: "No wallet access", ja: "ウォレット権限がありません") }
            static func noWalletAccess(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.noWalletAccess", vi: "Chưa có quyền thao tác ví", en: "No wallet access", ja: "ウォレット権限がありません", language: language) }
            static var noneYet: String { L10n.tr("planning.planning.noneYet", vi: "Chưa có", en: "None yet", ja: "まだありません") }
            static func noneYet(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.noneYet", vi: "Chưa có", en: "None yet", ja: "まだありません", language: language) }
            static var notLinked: String { L10n.tr("planning.planning.notLinked", vi: "Không liên kết", en: "Not linked", ja: "未連携") }
            static func notLinked(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.notLinked", vi: "Không liên kết", en: "Not linked", ja: "未連携", language: language) }
            static var notes: String { L10n.tr("planning.planning.notes", vi: "Ghi chú", en: "Notes", ja: "メモ") }
            static func notes(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.notes", vi: "Ghi chú", en: "Notes", ja: "メモ", language: language) }
            static var oneTime: String { L10n.tr("planning.planning.oneTime", vi: "Thanh toán 1 lần", en: "One-time", ja: "1回のみ") }
            static func oneTime(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.oneTime", vi: "Thanh toán 1 lần", en: "One-time", ja: "1回のみ", language: language) }
            static var over: String { L10n.tr("planning.planning.over", vi: "vượt", en: "over", ja: "超過") }
            static func over(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.over", vi: "vượt", en: "over", ja: "超過", language: language) }
            static var overdue: String { L10n.tr("planning.planning.overdue", vi: "Quá hạn", en: "Overdue", ja: "延滞") }
            static func overdue(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.overdue", vi: "Quá hạn", en: "Overdue", ja: "延滞", language: language) }
            static func overdueByValueDays(_ value: String) -> String {
                L10n.format("planning.planning.overdueByValueDays", vi: "Quá hạn %@ ngày", en: "Overdue by %@ days", ja: "%@ 日延滞", value)
            }
            static func overdueByValueDays(_ value: String, language: MistiaAppLanguage) -> String {
                L10n.format("planning.planning.overdueByValueDays", vi: "Quá hạn %@ ngày", en: "Overdue by %@ days", ja: "%@ 日延滞", language: language, value)
            }
            static var paid: String { L10n.tr("planning.planning.paid", vi: "Đã thanh toán", en: "Paid", ja: "支払い済み") }
            static func paid(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.paid", vi: "Đã thanh toán", en: "Paid", ja: "支払い済み", language: language) }
            static var parentBudget: String { L10n.tr("planning.planning.parentBudget", vi: "Ngân sách cha", en: "Parent budget", ja: "親予算") }
            static func parentBudget(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.parentBudget", vi: "Ngân sách cha", en: "Parent budget", ja: "親予算", language: language) }
            static func parentBudgetValueMustBeAtLeast(_ arg1: String, _ arg2: String) -> String {
                L10n.format("planning.planning.parentBudgetValueMustBeAtLeast", vi: "Ngân sách cha %@ phải lớn hơn hoặc bằng tổng ngân sách con %@.", en: "Parent budget %@ must be at least the child budget total %@.", ja: "親予算 %@ は子予算合計 %@ 以上にしてください。", arg1, arg2)
            }
            static func parentBudgetValueMustBeAtLeast(_ arg1: String, _ arg2: String, language: MistiaAppLanguage) -> String {
                L10n.format("planning.planning.parentBudgetValueMustBeAtLeast", vi: "Ngân sách cha %@ phải lớn hơn hoặc bằng tổng ngân sách con %@.", en: "Parent budget %@ must be at least the child budget total %@.", ja: "親予算 %@ は子予算合計 %@ 以上にしてください。", language: language, arg1, arg2)
            }
            static var pastBudgetReadOnlyReference: String { L10n.tr("planning.planning.pastBudgetReadOnlyReference", vi: "Ngân sách tháng cũ là bản tham chiếu chỉ đọc.", en: "Past-month budgets are read-only reference records.", ja: "過去月の予算は参照用の読み取り専用レコードです。") }
            static func pastBudgetReadOnlyReference(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.pastBudgetReadOnlyReference", vi: "Ngân sách tháng cũ là bản tham chiếu chỉ đọc.", en: "Past-month budgets are read-only reference records.", ja: "過去月の予算は参照用の読み取り専用レコードです。", language: language) }
            static var pauseBill: String { L10n.tr("planning.planning.pauseBill", vi: "Tạm dừng hóa đơn", en: "Pause bill", ja: "請求を一時停止") }
            static func pauseBill(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.pauseBill", vi: "Tạm dừng hóa đơn", en: "Pause bill", ja: "請求を一時停止", language: language) }
            static var pauseBillAction: String { L10n.tr("planning.planning.pauseBillAction", vi: "Tạm dừng", en: "Pause", ja: "一時停止") }
            static func pauseBillAction(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.pauseBillAction", vi: "Tạm dừng", en: "Pause", ja: "一時停止", language: language) }
            static var pauseBillMessage: String { L10n.tr("planning.planning.pauseBillMessage", vi: "Hóa đơn này sẽ tạm dừng. Hóa đơn tạm dừng sẽ không xuất hiện trong khoản cần thanh toán, thông báo hoặc tự động thanh toán cho đến khi bắt đầu lại.", en: "This bill will be paused. Paused bills will not appear in due items, notifications, or auto-pay until resumed.", ja: "この請求は一時停止されます。再開するまで支払い予定、通知、自動支払いに表示されません。") }
            static func pauseBillMessage(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.pauseBillMessage", vi: "Hóa đơn này sẽ tạm dừng. Hóa đơn tạm dừng sẽ không xuất hiện trong khoản cần thanh toán, thông báo hoặc tự động thanh toán cho đến khi bắt đầu lại.", en: "This bill will be paused. Paused bills will not appear in due items, notifications, or auto-pay until resumed.", ja: "この請求は一時停止されます。再開するまで支払い予定、通知、自動支払いに表示されません。", language: language) }
            static var pausedBills: String { L10n.tr("planning.planning.pausedBills", vi: "Hóa đơn tạm dừng", en: "Paused bills", ja: "一時停止中の請求") }
            static func pausedBills(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.pausedBills", vi: "Hóa đơn tạm dừng", en: "Paused bills", ja: "一時停止中の請求", language: language) }
            static var pay: String { L10n.tr("planning.planning.pay", vi: "Thanh toán", en: "Pay", ja: "支払う") }
            static func pay(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.pay", vi: "Thanh toán", en: "Pay", ja: "支払う", language: language) }
            static var payEarly: String { L10n.tr("planning.planning.payEarly", vi: "Thanh toán trước", en: "Pay early", ja: "先に支払う") }
            static func payEarly(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.payEarly", vi: "Thanh toán trước", en: "Pay early", ja: "先に支払う", language: language) }
            static var paymentAmount: String { L10n.tr("planning.planning.paymentAmount", vi: "Số tiền thanh toán", en: "Payment amount", ja: "支払い金額") }
            static func paymentAmount(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.paymentAmount", vi: "Số tiền thanh toán", en: "Payment amount", ja: "支払い金額", language: language) }
            static var paymentCategory: String { L10n.tr("planning.planning.paymentCategory", vi: "Danh mục thanh toán", en: "Payment category", ja: "支払いカテゴリ") }
            static func paymentCategory(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.paymentCategory", vi: "Danh mục thanh toán", en: "Payment category", ja: "支払いカテゴリ", language: language) }
            static var paymentDate: String { L10n.tr("planning.planning.paymentDate", vi: "Ngày thanh toán", en: "Payment date", ja: "支払開始日") }
            static func paymentDate(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.paymentDate", vi: "Ngày thanh toán", en: "Payment date", ja: "支払開始日", language: language) }
            static var paymentDay: String { L10n.tr("planning.planning.paymentDay", vi: "Ngày thanh toán", en: "Payment day", ja: "支払開始日") }
            static func paymentDay(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.paymentDay", vi: "Ngày thanh toán", en: "Payment day", ja: "支払開始日", language: language) }
            static var paymentWallet: String { L10n.tr("planning.planning.paymentWallet", vi: "Ví thanh toán", en: "Payment wallet", ja: "支払いウォレット") }
            static func paymentWallet(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.paymentWallet", vi: "Ví thanh toán", en: "Payment wallet", ja: "支払いウォレット", language: language) }
            static var planning: String { L10n.tr("planning.planning.planning", vi: "Sắp tới", en: "Upcoming", ja: "予定") }
            static func planning(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.planning", vi: "Sắp tới", en: "Upcoming", ja: "予定", language: language) }
            static var projectedEndOfMonth: String { L10n.tr("planning.planning.projectedEndOfMonth", vi: "Dự báo cuối tháng", en: "Projected month-end", ja: "月末予測") }
            static func projectedEndOfMonth(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.projectedEndOfMonth", vi: "Dự báo cuối tháng", en: "Projected month-end", ja: "月末予測", language: language) }
            static var recurring: String { L10n.tr("planning.planning.recurring", vi: "Định kỳ", en: "Recurring", ja: "定期") }
            static func recurring(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.recurring", vi: "Định kỳ", en: "Recurring", ja: "定期", language: language) }
            static var remaining: String { L10n.tr("planning.planning.remaining", vi: "Còn lại", en: "Remaining", ja: "残り") }
            static func remaining(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.remaining", vi: "Còn lại", en: "Remaining", ja: "残り", language: language) }
            static var requestAccess: String { L10n.tr("planning.planning.requestAccess", vi: "Yêu cầu quyền", en: "Request access", ja: "権限をリクエスト") }
            static func requestAccess(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.requestAccess", vi: "Yêu cầu quyền", en: "Request access", ja: "権限をリクエスト", language: language) }
            static var requestApproved: String { L10n.tr("planning.planning.requestApproved", vi: "Đã chấp nhận yêu cầu", en: "Request approved", ja: "リクエストが承認済み") }
            static func requestApproved(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.requestApproved", vi: "Đã chấp nhận yêu cầu", en: "Request approved", ja: "リクエストが承認済み", language: language) }
            static var requestCreate: String { L10n.tr("planning.planning.requestCreate", vi: "Yêu cầu thêm mới", en: "Request create", ja: "作成をリクエスト") }
            static func requestCreate(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.requestCreate", vi: "Yêu cầu thêm mới", en: "Request create", ja: "作成をリクエスト", language: language) }
            static var requestCreateAccess: String { L10n.tr("planning.planning.requestCreateAccess", vi: "Yêu cầu quyền thêm mới", en: "Request create access", ja: "作成権限をリクエスト") }
            static func requestCreateAccess(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.requestCreateAccess", vi: "Yêu cầu quyền thêm mới", en: "Request create access", ja: "作成権限をリクエスト", language: language) }
            static var requestEdit: String { L10n.tr("planning.planning.requestEdit", vi: "Yêu cầu chỉnh sửa", en: "Request edit", ja: "編集をリクエスト") }
            static func requestEdit(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.requestEdit", vi: "Yêu cầu chỉnh sửa", en: "Request edit", ja: "編集をリクエスト", language: language) }
            static var requestEditAccess: String { L10n.tr("planning.planning.requestEditAccess", vi: "Yêu cầu quyền chỉnh sửa", en: "Request edit access", ja: "編集権限をリクエスト") }
            static func requestEditAccess(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.requestEditAccess", vi: "Yêu cầu quyền chỉnh sửa", en: "Request edit access", ja: "編集権限をリクエスト", language: language) }
            static var requestSent: String { L10n.tr("planning.planning.requestSent", vi: "Đã gửi yêu cầu", en: "Request sent", ja: "リクエストを送信しました") }
            static func requestSent(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.requestSent", vi: "Đã gửi yêu cầu", en: "Request sent", ja: "リクエストを送信しました", language: language) }
            static var requestSent2: String { L10n.tr("planning.planning.requestSent2", vi: "Đã gửi yêu cầu", en: "Request sent", ja: "リクエスト送信済み") }
            static func requestSent2(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.requestSent2", vi: "Đã gửi yêu cầu", en: "Request sent", ja: "リクエスト送信済み", language: language) }
            static var requestUse: String { L10n.tr("planning.planning.requestUse", vi: "Yêu cầu sử dụng", en: "Request use", ja: "使用をリクエスト") }
            static func requestUse(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.requestUse", vi: "Yêu cầu sử dụng", en: "Request use", ja: "使用をリクエスト", language: language) }
            static var resumeBill: String { L10n.tr("planning.planning.resumeBill", vi: "Bắt đầu lại", en: "Resume bill", ja: "請求を再開") }
            static func resumeBill(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.resumeBill", vi: "Bắt đầu lại", en: "Resume bill", ja: "請求を再開", language: language) }
            static var resumeBillMessage: String { L10n.tr("planning.planning.resumeBillMessage", vi: "Hóa đơn này sẽ được tính trở lại từ tháng hiện tại.", en: "This bill will be counted again from the current month.", ja: "この請求は今月から再び計算されます。") }
            static func resumeBillMessage(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.resumeBillMessage", vi: "Hóa đơn này sẽ được tính trở lại từ tháng hiện tại.", en: "This bill will be counted again from the current month.", ja: "この請求は今月から再び計算されます。", language: language) }
            static var rollover: String { L10n.tr("planning.planning.rollover", vi: "Rollover", en: "Rollover", ja: "繰り越し") }
            static func rollover(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.rollover", vi: "Rollover", en: "Rollover", ja: "繰り越し", language: language) }
            static var sAHAN: String { L10n.tr("planning.planning.sAHAN", vi: "Sửa hóa đơn", en: "Edit bill", ja: "請求書を編集") }
            static func sAHAN(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.sAHAN", vi: "Sửa hóa đơn", en: "Edit bill", ja: "請求書を編集", language: language) }
            static var sAKhoN: String { L10n.tr("planning.planning.sAKhoN", vi: "Sửa khoản", en: "Edit item", ja: "項目を編集") }
            static func sAKhoN(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.sAKhoN", vi: "Sửa khoản", en: "Edit item", ja: "項目を編集", language: language) }
            static var sAMCTiU: String { L10n.tr("planning.planning.sAMCTiU", vi: "Sửa mục tiêu", en: "Edit goal", ja: "目標を編集") }
            static func sAMCTiU(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.sAMCTiU", vi: "Sửa mục tiêu", en: "Edit goal", ja: "目標を編集", language: language) }
            static var sANgNSCh: String { L10n.tr("planning.planning.sANgNSCh", vi: "Sửa ngân sách", en: "Edit budget", ja: "予算を編集") }
            static func sANgNSCh(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.sANgNSCh", vi: "Sửa ngân sách", en: "Edit budget", ja: "予算を編集", language: language) }
            static var sATh: String { L10n.tr("planning.planning.sATh", vi: "Sửa thẻ", en: "Edit card", ja: "カードを編集") }
            static func sATh(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.sATh", vi: "Sửa thẻ", en: "Edit card", ja: "カードを編集", language: language) }
            static var saved: String { L10n.tr("planning.planning.saved", vi: "Đã tích lũy", en: "Saved", ja: "積み立て済み") }
            static func saved(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.saved", vi: "Đã tích lũy", en: "Saved", ja: "積み立て済み", language: language) }
            static var spent: String { L10n.tr("planning.planning.spent", vi: "Đã dùng", en: "Spent", ja: "使用済み") }
            static func spent(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.spent", vi: "Đã dùng", en: "Spent", ja: "使用済み", language: language) }
            static var startCounting: String { L10n.tr("planning.planning.startCounting", vi: "Bắt đầu tính", en: "Start counting", ja: "開始月") }
            static func startCounting(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.startCounting", vi: "Bắt đầu tính", en: "Start counting", ja: "開始月", language: language) }
            static var statement: String { L10n.tr("planning.planning.statement", vi: "Sao kê", en: "Statement", ja: "明細") }
            static func statement(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.statement", vi: "Sao kê", en: "Statement", ja: "明細", language: language) }
            static var statementClosingDay: String { L10n.tr("planning.planning.statementClosingDay", vi: "Ngày chốt sao kê", en: "Statement closing day", ja: "締め日") }
            static func statementClosingDay(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.statementClosingDay", vi: "Ngày chốt sao kê", en: "Statement closing day", ja: "締め日", language: language) }
            static var statementClosingDayMustBeEarlierThan: String { L10n.tr("planning.planning.statementClosingDayMustBeEarlierThan", vi: "Ngày chốt sao kê phải trước hạn trả.", en: "Statement closing day must be earlier than the payment due day.", ja: "締め日は支払日より前である必要があります。") }
            static func statementClosingDayMustBeEarlierThan(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.statementClosingDayMustBeEarlierThan", vi: "Ngày chốt sao kê phải trước hạn trả.", en: "Statement closing day must be earlier than the payment due day.", ja: "締め日は支払日より前である必要があります。", language: language) }
            static var summary: String { L10n.tr("planning.planning.summary", vi: "Tóm tắt", en: "Summary", ja: "概要") }
            static func summary(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.summary", vi: "Tóm tắt", en: "Summary", ja: "概要", language: language) }
            static var targetAmount: String { L10n.tr("planning.planning.targetAmount", vi: "Số tiền mục tiêu", en: "Target amount", ja: "目標金額") }
            static func targetAmount(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.targetAmount", vi: "Số tiền mục tiêu", en: "Target amount", ja: "目標金額", language: language) }
            static var targetDate: String { L10n.tr("planning.planning.targetDate", vi: "Ngày mục tiêu", en: "Target date", ja: "目標日") }
            static func targetDate(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.targetDate", vi: "Ngày mục tiêu", en: "Target date", ja: "目標日", language: language) }
            static var thMI: String { L10n.tr("planning.planning.thMI", vi: "Thẻ mới", en: "New card", ja: "新しいカード") }
            static func thMI(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.thMI", vi: "Thẻ mới", en: "New card", ja: "新しいカード", language: language) }
            static var theDestinationCreditCardCouldNotBe: String { L10n.tr("planning.planning.theDestinationCreditCardCouldNotBe", vi: "Không tìm thấy thẻ tín dụng đích.", en: "The destination credit card could not be found.", ja: "振替先のクレジットカードが見つかりません。") }
            static func theDestinationCreditCardCouldNotBe(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.theDestinationCreditCardCouldNotBe", vi: "Không tìm thấy thẻ tín dụng đích.", en: "The destination credit card could not be found.", ja: "振替先のクレジットカードが見つかりません。", language: language) }
            static var thePermissionRequestWasSentToThe: String { L10n.tr("planning.planning.thePermissionRequestWasSentToThe", vi: "Yêu cầu quyền đã được gửi tới chủ dữ liệu.", en: "The permission request was sent to the data owner.", ja: "権限リクエストをデータ所有者へ送信しました。") }
            static func thePermissionRequestWasSentToThe(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.thePermissionRequestWasSentToThe", vi: "Yêu cầu quyền đã được gửi tới chủ dữ liệu.", en: "The permission request was sent to the data owner.", ja: "権限リクエストをデータ所有者へ送信しました。", language: language) }
            static var theRequestIsWaitingForTheData: String { L10n.tr("planning.planning.theRequestIsWaitingForTheData", vi: "Yêu cầu đang chờ chủ dữ liệu phản hồi.", en: "The request is waiting for the data owner.", ja: "リクエストはデータ所有者の返答待ちです。") }
            static func theRequestIsWaitingForTheData(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.theRequestIsWaitingForTheData", vi: "Yêu cầu đang chờ chủ dữ liệu phản hồi.", en: "The request is waiting for the data owner.", ja: "リクエストはデータ所有者の返答待ちです。", language: language) }
            static var theSystemCategoryForThisPaymentCould: String { L10n.tr("planning.planning.theSystemCategoryForThisPaymentCould", vi: "Không thể xác định danh mục hệ thống cho khoản thanh toán này.", en: "The system category for this payment could not be resolved.", ja: "この支払いに使うシステムカテゴリを特定できません。") }
            static func theSystemCategoryForThisPaymentCould(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.theSystemCategoryForThisPaymentCould", vi: "Không thể xác định danh mục hệ thống cho khoản thanh toán này.", en: "The system category for this payment could not be resolved.", ja: "この支払いに使うシステムカテゴリを特定できません。", language: language) }
            static var thisBillWillBeArchivedArchivedBills: String { L10n.tr("planning.planning.thisBillWillBeArchivedArchivedBills", vi: "Hóa đơn này sẽ bị lưu trữ. Hóa đơn đã lưu trữ sẽ nằm trong \"Mục đã lưu trữ\" và được giữ lại trong 30 ngày.", en: "This bill will be archived. Archived bills remain in \"Archived items\" for 30 days.", ja: "この請求はアーカイブされます。アーカイブ済みの請求は「アーカイブ済みアイテム」に30日間保持されます。") }
            static func thisBillWillBeArchivedArchivedBills(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.thisBillWillBeArchivedArchivedBills", vi: "Hóa đơn này sẽ bị lưu trữ. Hóa đơn đã lưu trữ sẽ nằm trong \"Mục đã lưu trữ\" và được giữ lại trong 30 ngày.", en: "This bill will be archived. Archived bills remain in \"Archived items\" for 30 days.", ja: "この請求はアーカイブされます。アーカイブ済みの請求は「アーカイブ済みアイテム」に30日間保持されます。", language: language) }
            static var thisBudgetWillBeArchivedArchivedBudgets: String { L10n.tr("planning.planning.thisBudgetWillBeArchivedArchivedBudgets", vi: "Ngân sách này sẽ bị lưu trữ. Ngân sách đã lưu trữ sẽ nằm trong \"Mục đã lưu trữ\" và được giữ lại trong 30 ngày.", en: "This budget will be archived. Archived budgets remain in \"Archived items\" for 30 days.", ja: "この予算はアーカイブされます。アーカイブ済みの予算は「アーカイブ済みアイテム」に30日間保持されます。") }
            static func thisBudgetWillBeArchivedArchivedBudgets(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.thisBudgetWillBeArchivedArchivedBudgets", vi: "Ngân sách này sẽ bị lưu trữ. Ngân sách đã lưu trữ sẽ nằm trong \"Mục đã lưu trữ\" và được giữ lại trong 30 ngày.", en: "This budget will be archived. Archived budgets remain in \"Archived items\" for 30 days.", ja: "この予算はアーカイブされます。アーカイブ済みの予算は「アーカイブ済みアイテム」に30日間保持されます。", language: language) }
            static var thisCardWillBeArchivedArchivedCards: String { L10n.tr("planning.planning.thisCardWillBeArchivedArchivedCards", vi: "Thẻ này sẽ bị lưu trữ. Các thẻ đã lưu trữ sẽ nằm trong \"Mục đã lưu trữ\" và được giữ lại trong 30 ngày.", en: "This card will be archived. Archived cards will remain in \"Archived items\" for 30 days.", ja: "このカードはアーカイブされます。アーカイブされたカードは「アーカイブ済みアイテム」に30日間保持されます。") }
            static func thisCardWillBeArchivedArchivedCards(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.thisCardWillBeArchivedArchivedCards", vi: "Thẻ này sẽ bị lưu trữ. Các thẻ đã lưu trữ sẽ nằm trong \"Mục đã lưu trữ\" và được giữ lại trong 30 ngày.", en: "This card will be archived. Archived cards will remain in \"Archived items\" for 30 days.", ja: "このカードはアーカイブされます。アーカイブされたカードは「アーカイブ済みアイテム」に30日間保持されます。", language: language) }
            static var thisCategoryAlreadyHasABudgetIn: String { L10n.tr("planning.planning.thisCategoryAlreadyHasABudgetIn", vi: "Danh mục này đã có ngân sách trong tháng đang xem.", en: "This category already has a budget in the selected month.", ja: "このカテゴリには表示中の月ですでに予算があります。") }
            static func thisCategoryAlreadyHasABudgetIn(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.thisCategoryAlreadyHasABudgetIn", vi: "Danh mục này đã có ngân sách trong tháng đang xem.", en: "This category already has a budget in the selected month.", ja: "このカテゴリには表示中の月ですでに予算があります。", language: language) }
            static var thisPaymentWillBeRecordedAsA: String { L10n.tr("planning.planning.thisPaymentWillBeRecordedAsA", vi: "Khoản này sẽ được ghi nhận thành khoản chi thật.", en: "This payment will be recorded as a real expense.", ja: "この支払いは実際の支出取引として記録されます。") }
            static func thisPaymentWillBeRecordedAsA(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.thisPaymentWillBeRecordedAsA", vi: "Khoản này sẽ được ghi nhận thành khoản chi thật.", en: "This payment will be recorded as a real expense.", ja: "この支払いは実際の支出取引として記録されます。", language: language) }
            static var totalAmount: String { L10n.tr("planning.planning.totalAmount", vi: "Tổng tiền", en: "Total amount", ja: "合計金額") }
            static func totalAmount(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.totalAmount", vi: "Tổng tiền", en: "Total amount", ja: "合計金額", language: language) }
            static var totalCyclesOptional: String { L10n.tr("planning.planning.totalCyclesOptional", vi: "Tổng số kỳ (không bắt buộc)", en: "Total cycles (optional)", ja: "支払い回数（任意）") }
            static func totalCyclesOptional(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.totalCyclesOptional", vi: "Tổng số kỳ (không bắt buộc)", en: "Total cycles (optional)", ja: "支払い回数（任意）", language: language) }
            static var totalDue: String { L10n.tr("planning.planning.totalDue", vi: "Tổng cần trả", en: "Total to pay", ja: "支払合計") }
            static func totalDue(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.totalDue", vi: "Tổng cần trả", en: "Total to pay", ja: "支払合計", language: language) }
            static var upcoming: String { L10n.tr("planning.planning.upcoming", vi: "Sắp tới", en: "Upcoming", ja: "まもなく") }
            static func upcoming(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.upcoming", vi: "Sắp tới", en: "Upcoming", ja: "まもなく", language: language) }
            static var upcoming2: String { L10n.tr("planning.planning.upcoming2", vi: "Sắp tới", en: "Upcoming", ja: "まもなく期限") }
            static func upcoming2(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.upcoming2", vi: "Sắp tới", en: "Upcoming", ja: "まもなく期限", language: language) }
            static var useRequestApproved: String { L10n.tr("planning.planning.useRequestApproved", vi: "Đã chấp nhận yêu cầu sử dụng", en: "Use request approved", ja: "使用リクエストが承認済み") }
            static func useRequestApproved(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.useRequestApproved", vi: "Đã chấp nhận yêu cầu sử dụng", en: "Use request approved", ja: "使用リクエストが承認済み", language: language) }
            static var useRequested: String { L10n.tr("planning.planning.useRequested", vi: "Đã yêu cầu sử dụng", en: "Use requested", ja: "使用権限をリクエスト済み") }
            static func useRequested(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.useRequested", vi: "Đã yêu cầu sử dụng", en: "Use requested", ja: "使用権限をリクエスト済み", language: language) }
            static func valueDaysLeft(_ value: String) -> String {
                L10n.format("planning.planning.valueDaysLeft", vi: "Còn %@ ngày", en: "%@ days left", ja: "あと %@ 日", value)
            }
            static func valueDaysLeft(_ value: String, language: MistiaAppLanguage) -> String {
                L10n.format("planning.planning.valueDaysLeft", vi: "Còn %@ ngày", en: "%@ days left", ja: "あと %@ 日", language: language, value)
            }
            static func valueGoals(_ value: String) -> String {
                L10n.format("planning.planning.valueGoals", vi: "%@ mục tiêu", en: "%@ goals", ja: "%@ 件の目標", value)
            }
            static func valueGoals(_ value: String, language: MistiaAppLanguage) -> String {
                L10n.format("planning.planning.valueGoals", vi: "%@ mục tiêu", en: "%@ goals", ja: "%@ 件の目標", language: language, value)
            }
            static var walletsCards: String { L10n.tr("planning.planning.walletsCards", vi: "ví / thẻ", en: "wallets / cards", ja: "ウォレット・カード") }
            static func walletsCards(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.walletsCards", vi: "ví / thẻ", en: "wallets / cards", ja: "ウォレット・カード", language: language) }
            static var year: String { L10n.tr("planning.planning.year", vi: "Năm", en: "Year", ja: "年") }
            static func year(language: MistiaAppLanguage) -> String { L10n.tr("planning.planning.year", vi: "Năm", en: "Year", ja: "年", language: language) }
            static func yearValue(_ value: String) -> String {
                L10n.format("planning.planning.yearValue", vi: "Năm %@", en: "Year %@", ja: "%@年", value)
            }
            static func yearValue(_ value: String, language: MistiaAppLanguage) -> String {
                L10n.format("planning.planning.yearValue", vi: "Năm %@", en: "Year %@", ja: "%@年", language: language, value)
            }
            static func youDoNotHaveEnoughAccessFor(_ value: String) -> String {
                L10n.format("planning.planning.youDoNotHaveEnoughAccessFor", vi: "Bạn chưa có đủ quyền với %@.", en: "You do not have enough access for %@.", ja: "%@ の権限が不足しています。", value)
            }
            static func youDoNotHaveEnoughAccessFor(_ value: String, language: MistiaAppLanguage) -> String {
                L10n.format("planning.planning.youDoNotHaveEnoughAccessFor", vi: "Bạn chưa có đủ quyền với %@.", en: "You do not have enough access for %@.", ja: "%@ の権限が不足しています。", language: language, value)
            }
            static func youDoNotHavePermissionToCreate(_ value: String) -> String {
                L10n.format("planning.planning.youDoNotHavePermissionToCreate", vi: "Bạn chưa có quyền thêm mới %@ cho thành viên này.", en: "You do not have permission to create %@ for this member.", ja: "このメンバーの%@を作成する権限がありません。", value)
            }
            static func youDoNotHavePermissionToCreate(_ value: String, language: MistiaAppLanguage) -> String {
                L10n.format("planning.planning.youDoNotHavePermissionToCreate", vi: "Bạn chưa có quyền thêm mới %@ cho thành viên này.", en: "You do not have permission to create %@ for this member.", ja: "このメンバーの%@を作成する権限がありません。", language: language, value)
            }
            static func youDoNotHavePermissionToEdit(_ value: String) -> String {
                L10n.format("planning.planning.youDoNotHavePermissionToEdit", vi: "Bạn chưa có quyền chỉnh sửa %@ của thành viên này.", en: "You do not have permission to edit this member's %@.", ja: "このメンバーの%@を編集する権限がありません。", value)
            }
            static func youDoNotHavePermissionToEdit(_ value: String, language: MistiaAppLanguage) -> String {
                L10n.format("planning.planning.youDoNotHavePermissionToEdit", vi: "Bạn chưa có quyền chỉnh sửa %@ của thành viên này.", en: "You do not have permission to edit this member's %@.", ja: "このメンバーの%@を編集する権限がありません。", language: language, value)
            }
        }
    }

    nonisolated enum session {

        nonisolated enum auth {
            static var cantResendEmailTitle: String { L10n.tr("session.auth.cantResendEmailTitle", vi: "Chưa thể gửi lại email", en: "Can't resend the email yet", ja: "メールを再送できません") }
            static func cantResendEmailTitle(language: MistiaAppLanguage) -> String { L10n.tr("session.auth.cantResendEmailTitle", vi: "Chưa thể gửi lại email", en: "Can't resend the email yet", ja: "メールを再送できません", language: language) }
            static var cantSendEmailTitle: String { L10n.tr("session.auth.cantSendEmailTitle", vi: "Chưa thể gửi email", en: "Can't send the email yet", ja: "メールを送信できません") }
            static func cantSendEmailTitle(language: MistiaAppLanguage) -> String { L10n.tr("session.auth.cantSendEmailTitle", vi: "Chưa thể gửi email", en: "Can't send the email yet", ja: "メールを送信できません", language: language) }
            static var confirmationEmailDeliveryMessage: String { L10n.tr("session.auth.confirmationEmailDeliveryMessage", vi: "Nếu tài khoản đang chờ xác nhận, hệ thống sẽ tiếp tục gửi email xác nhận đến đúng hộp thư.", en: "If the account is pending confirmation, the system will still deliver the confirmation email to the right inbox.", ja: "アカウントが確認待ちであれば、システムが正しい受信箱へ確認メールを送信します。") }
            static func confirmationEmailDeliveryMessage(language: MistiaAppLanguage) -> String { L10n.tr("session.auth.confirmationEmailDeliveryMessage", vi: "Nếu tài khoản đang chờ xác nhận, hệ thống sẽ tiếp tục gửi email xác nhận đến đúng hộp thư.", en: "If the account is pending confirmation, the system will still deliver the confirmation email to the right inbox.", ja: "アカウントが確認待ちであれば、システムが正しい受信箱へ確認メールを送信します。", language: language) }
            static var emailRequestProcessingTitle: String { L10n.tr("session.auth.emailRequestProcessingTitle", vi: "Email đang được xử lý", en: "The email request is being processed", ja: "メール再送を処理中です") }
            static func emailRequestProcessingTitle(language: MistiaAppLanguage) -> String { L10n.tr("session.auth.emailRequestProcessingTitle", vi: "Email đang được xử lý", en: "The email request is being processed", ja: "メール再送を処理中です", language: language) }
            static var requestProcessingTitle: String { L10n.tr("session.auth.requestProcessingTitle", vi: "Yêu cầu đang được xử lý", en: "The request is being processed", ja: "リクエストを処理中です") }
            static func requestProcessingTitle(language: MistiaAppLanguage) -> String { L10n.tr("session.auth.requestProcessingTitle", vi: "Yêu cầu đang được xử lý", en: "The request is being processed", ja: "リクエストを処理中です", language: language) }
            static var resetEmailDeliveryMessage: String { L10n.tr("session.auth.resetEmailDeliveryMessage", vi: "Nếu email hợp lệ, hệ thống sẽ tiếp tục gửi email đặt lại mật khẩu đến đúng hộp thư.", en: "If the email is valid, the system will still deliver the reset email to the right inbox.", ja: "有効なメールアドレスであれば、システムが正しい受信箱へ再設定メールを送信します。") }
            static func resetEmailDeliveryMessage(language: MistiaAppLanguage) -> String { L10n.tr("session.auth.resetEmailDeliveryMessage", vi: "Nếu email hợp lệ, hệ thống sẽ tiếp tục gửi email đặt lại mật khẩu đến đúng hộp thư.", en: "If the email is valid, the system will still deliver the reset email to the right inbox.", ja: "有効なメールアドレスであれば、システムが正しい受信箱へ再設定メールを送信します。", language: language) }
        }

        nonisolated enum guest {
            static var cleanDataDetail: String { L10n.tr("session.guest.cleanDataDetail", vi: "Thiết bị hiện chưa gắn với dữ liệu local của tài khoản nào. Đăng nhập để tải dữ liệu tài khoản của bạn hoặc bắt đầu dùng local mới.", en: "This device isn't attached to any saved account data right now. Sign in to load your account, or start fresh with new local data.", ja: "この端末は現在どの保存済みアカウントデータにも紐づいていません。ログインしてアカウントデータを読み込むか、新しいローカルデータから始められます。") }
            static func cleanDataDetail(language: MistiaAppLanguage) -> String { L10n.tr("session.guest.cleanDataDetail", vi: "Thiết bị hiện chưa gắn với dữ liệu local của tài khoản nào. Đăng nhập để tải dữ liệu tài khoản của bạn hoặc bắt đầu dùng local mới.", en: "This device isn't attached to any saved account data right now. Sign in to load your account, or start fresh with new local data.", ja: "この端末は現在どの保存済みアカウントデータにも紐づいていません。ログインしてアカウントデータを読み込むか、新しいローカルデータから始められます。", language: language) }
            static var cleanTitle: String { L10n.tr("session.guest.cleanTitle", vi: "Guest sạch", en: "Clean guest", ja: "クリーンゲスト") }
            static func cleanTitle(language: MistiaAppLanguage) -> String { L10n.tr("session.guest.cleanTitle", vi: "Guest sạch", en: "Clean guest", ja: "クリーンゲスト", language: language) }
            static var localDataSeparateDetail: String { L10n.tr("session.guest.localDataSeparateDetail", vi: "Dữ liệu local guest trên máy này đang tách riêng. Bạn có thể tiếp tục chỉnh sửa và quyết định sau sẽ gắn nó với tài khoản nào.", en: "This device has separate guest local data. You can keep editing it now and decide later whether it should stay separate or attach to an account.", ja: "この端末には独立したゲストのローカルデータがあります。今のまま編集を続け、後でどのアカウントに紐づけるか決められます。") }
            static func localDataSeparateDetail(language: MistiaAppLanguage) -> String { L10n.tr("session.guest.localDataSeparateDetail", vi: "Dữ liệu local guest trên máy này đang tách riêng. Bạn có thể tiếp tục chỉnh sửa và quyết định sau sẽ gắn nó với tài khoản nào.", en: "This device has separate guest local data. You can keep editing it now and decide later whether it should stay separate or attach to an account.", ja: "この端末には独立したゲストのローカルデータがあります。今のまま編集を続け、後でどのアカウントに紐づけるか決められます。", language: language) }
            static var localTitle: String { L10n.tr("session.guest.localTitle", vi: "Guest local", en: "Guest local", ja: "ゲストローカル") }
            static func localTitle(language: MistiaAppLanguage) -> String { L10n.tr("session.guest.localTitle", vi: "Guest local", en: "Guest local", ja: "ゲストローカル", language: language) }
        }

        nonisolated enum sync {
            static var sessionRestoredDetail: String { L10n.tr("session.sync.sessionRestoredDetail", vi: "Phiên đã được khôi phục. Nhấn Sync ngay khi bạn muốn đồng bộ với cloud.", en: "Your session has been restored. Tap Sync now when you want to sync with the cloud.", ja: "セッションを復元しました。クラウドと同期するには「今すぐ同期」を押してください。") }
            static func sessionRestoredDetail(language: MistiaAppLanguage) -> String { L10n.tr("session.sync.sessionRestoredDetail", vi: "Phiên đã được khôi phục. Nhấn Sync ngay khi bạn muốn đồng bộ với cloud.", en: "Your session has been restored. Tap Sync now when you want to sync with the cloud.", ja: "セッションを復元しました。クラウドと同期するには「今すぐ同期」を押してください。", language: language) }
            static var signInSucceededDetail: String { L10n.tr("session.sync.signInSucceededDetail", vi: "Đăng nhập thành công. Nhấn Sync ngay để bắt đầu đồng bộ dữ liệu.", en: "Sign-in succeeded. Tap Sync now to start syncing your data.", ja: "ログインに成功しました。データ同期を始めるには「今すぐ同期」を押してください。") }
            static func signInSucceededDetail(language: MistiaAppLanguage) -> String { L10n.tr("session.sync.signInSucceededDetail", vi: "Đăng nhập thành công. Nhấn Sync ngay để bắt đầu đồng bộ dữ liệu.", en: "Sign-in succeeded. Tap Sync now to start syncing your data.", ja: "ログインに成功しました。データ同期を始めるには「今すぐ同期」を押してください。", language: language) }
        }
    }

    nonisolated enum settings {

        nonisolated enum appearance {

            nonisolated enum mode {

                nonisolated enum automatic {
                    static var subtitle: String { L10n.tr("settings.appearance.mode.automatic.subtitle", vi: "Theo giao diện hệ thống", en: "Follow system appearance", ja: "システム設定に合わせる") }
                    static func subtitle(language: MistiaAppLanguage) -> String { L10n.tr("settings.appearance.mode.automatic.subtitle", vi: "Theo giao diện hệ thống", en: "Follow system appearance", ja: "システム設定に合わせる", language: language) }
                    static var title: String { L10n.tr("settings.appearance.mode.automatic.title", vi: "Tự động", en: "Automatic", ja: "自動") }
                    static func title(language: MistiaAppLanguage) -> String { L10n.tr("settings.appearance.mode.automatic.title", vi: "Tự động", en: "Automatic", ja: "自動", language: language) }
                }

                nonisolated enum dark {
                    static var subtitle: String { L10n.tr("settings.appearance.mode.dark.subtitle", vi: "Luôn dùng nền tối", en: "Always use dark mode", ja: "常にダークモードを使う") }
                    static func subtitle(language: MistiaAppLanguage) -> String { L10n.tr("settings.appearance.mode.dark.subtitle", vi: "Luôn dùng nền tối", en: "Always use dark mode", ja: "常にダークモードを使う", language: language) }
                    static var title: String { L10n.tr("settings.appearance.mode.dark.title", vi: "Tối", en: "Dark", ja: "ダーク") }
                    static func title(language: MistiaAppLanguage) -> String { L10n.tr("settings.appearance.mode.dark.title", vi: "Tối", en: "Dark", ja: "ダーク", language: language) }
                }

                nonisolated enum light {
                    static var subtitle: String { L10n.tr("settings.appearance.mode.light.subtitle", vi: "Luôn dùng nền sáng", en: "Always use light mode", ja: "常にライトモードを使う") }
                    static func subtitle(language: MistiaAppLanguage) -> String { L10n.tr("settings.appearance.mode.light.subtitle", vi: "Luôn dùng nền sáng", en: "Always use light mode", ja: "常にライトモードを使う", language: language) }
                    static var title: String { L10n.tr("settings.appearance.mode.light.title", vi: "Sáng", en: "Light", ja: "ライト") }
                    static func title(language: MistiaAppLanguage) -> String { L10n.tr("settings.appearance.mode.light.title", vi: "Sáng", en: "Light", ja: "ライト", language: language) }
                }
            }
            static var title: String { L10n.tr("settings.appearance.title", vi: "Giao diện", en: "Appearance", ja: "表示") }
            static func title(language: MistiaAppLanguage) -> String { L10n.tr("settings.appearance.title", vi: "Giao diện", en: "Appearance", ja: "表示", language: language) }
        }

        nonisolated enum currency {
            static var autoUpdateRates: String { L10n.tr("settings.currency.autoUpdateRates", vi: "Tự động cập nhật tỷ giá", en: "Auto-update exchange rates", ja: "為替レートを自動更新") }
            static func autoUpdateRates(language: MistiaAppLanguage) -> String { L10n.tr("settings.currency.autoUpdateRates", vi: "Tự động cập nhật tỷ giá", en: "Auto-update exchange rates", ja: "為替レートを自動更新", language: language) }
            static var currencyNameJPY: String { L10n.tr("settings.currency.currencyNameJPY", vi: "Yên Nhật", en: "Japanese yen", ja: "日本円") }
            static func currencyNameJPY(language: MistiaAppLanguage) -> String { L10n.tr("settings.currency.currencyNameJPY", vi: "Yên Nhật", en: "Japanese yen", ja: "日本円", language: language) }
            static var currencyNameVND: String { L10n.tr("settings.currency.currencyNameVND", vi: "Việt Nam Đồng", en: "Vietnamese dong", ja: "ベトナムドン") }
            static func currencyNameVND(language: MistiaAppLanguage) -> String { L10n.tr("settings.currency.currencyNameVND", vi: "Việt Nam Đồng", en: "Vietnamese dong", ja: "ベトナムドン", language: language) }
            static var enabledDescription: String { L10n.tr("settings.currency.enabledDescription", vi: "Tiền tệ đã bật có thể sử dụng cho ví.", en: "Enabled currencies can be used for wallets.", ja: "有効な通貨はウォレットで使えます。") }
            static func enabledDescription(language: MistiaAppLanguage) -> String { L10n.tr("settings.currency.enabledDescription", vi: "Tiền tệ đã bật có thể sử dụng cho ví.", en: "Enabled currencies can be used for wallets.", ja: "有効な通貨はウォレットで使えます。", language: language) }
            static func lastUpdatedValue(_ value: String) -> String {
                L10n.format("settings.currency.lastUpdatedValue", vi: "Cập nhật lần cuối: %@", en: "Last updated: %@", ja: "最終更新: %@", value)
            }
            static func lastUpdatedValue(_ value: String, language: MistiaAppLanguage) -> String {
                L10n.format("settings.currency.lastUpdatedValue", vi: "Cập nhật lần cuối: %@", en: "Last updated: %@", ja: "最終更新: %@", language: language, value)
            }
            static var notUpdatedYet: String { L10n.tr("settings.currency.notUpdatedYet", vi: "Chưa cập nhật tỷ giá tự động.", en: "Automatic rates have not been updated yet.", ja: "自動レートはまだ更新されていません。") }
            static func notUpdatedYet(language: MistiaAppLanguage) -> String { L10n.tr("settings.currency.notUpdatedYet", vi: "Chưa cập nhật tỷ giá tự động.", en: "Automatic rates have not been updated yet.", ja: "自動レートはまだ更新されていません。", language: language) }
            static var primaryCurrency: String { L10n.tr("settings.currency.primaryCurrency", vi: "Tiền tệ hiển thị", en: "Display currency", ja: "表示通貨") }
            static func primaryCurrency(language: MistiaAppLanguage) -> String { L10n.tr("settings.currency.primaryCurrency", vi: "Tiền tệ hiển thị", en: "Display currency", ja: "表示通貨", language: language) }
            static var primaryDescription: String { L10n.tr("settings.currency.primaryDescription", vi: "Tổng quan, Sắp tới và Gia đình sẽ hiển thị tổng hợp theo tiền tệ này. Thu chi và ví vẫn giữ tiền tệ riêng.", en: "Overview, Upcoming, and Family totals use this currency. Cashflow and wallets keep their own currencies.", ja: "概要、プラン、家族の集計はこの通貨で表示します。取引とウォレットはそれぞれの通貨を保持します。") }
            static func primaryDescription(language: MistiaAppLanguage) -> String { L10n.tr("settings.currency.primaryDescription", vi: "Tổng quan, Sắp tới và Gia đình sẽ hiển thị tổng hợp theo tiền tệ này. Thu chi và ví vẫn giữ tiền tệ riêng.", en: "Overview, Upcoming, and Family totals use this currency. Cashflow and wallets keep their own currencies.", ja: "概要、プラン、家族の集計はこの通貨で表示します。取引とウォレットはそれぞれの通貨を保持します。", language: language) }
            static var rateDescription: String { L10n.tr("settings.currency.rateDescription", vi: "Khi bật tự động, Mistia cập nhật tỷ giá sau 7:00 sáng hoặc khi bạn bấm cập nhật. Khi tắt, Mistia dùng tỷ giá bạn nhập.", en: "When auto-update is on, Mistia refreshes rates after 7:00 AM or when you tap refresh. When it is off, Mistia uses the rate you enter.", ja: "自動更新をオンにすると、ミスティアは午前7時以降または更新ボタンを押したときにレートを更新します。オフのときは入力したレートを使います。") }
            static func rateDescription(language: MistiaAppLanguage) -> String { L10n.tr("settings.currency.rateDescription", vi: "Khi bật tự động, Mistia cập nhật tỷ giá sau 7:00 sáng hoặc khi bạn bấm cập nhật. Khi tắt, Mistia dùng tỷ giá bạn nhập.", en: "When auto-update is on, Mistia refreshes rates after 7:00 AM or when you tap refresh. When it is off, Mistia uses the rate you enter.", ja: "自動更新をオンにすると、ミスティアは午前7時以降または更新ボタンを押したときにレートを更新します。オフのときは入力したレートを使います。", language: language) }
            static func ratePairValue(_ arg1: String, _ arg2: String) -> String {
                L10n.format("settings.currency.ratePairValue", vi: "1 %@ sang %@", en: "1 %@ to %@", ja: "1 %@ から %@", arg1, arg2)
            }
            static func ratePairValue(_ arg1: String, _ arg2: String, language: MistiaAppLanguage) -> String {
                L10n.format("settings.currency.ratePairValue", vi: "1 %@ sang %@", en: "1 %@ to %@", ja: "1 %@ から %@", language: language, arg1, arg2)
            }
            static var rateValue: String { L10n.tr("settings.currency.rateValue", vi: "Tỷ giá", en: "Rate", ja: "レート") }
            static func rateValue(language: MistiaAppLanguage) -> String { L10n.tr("settings.currency.rateValue", vi: "Tỷ giá", en: "Rate", ja: "レート", language: language) }
            static var refreshRates: String { L10n.tr("settings.currency.refreshRates", vi: "Cập nhật tỷ giá", en: "Refresh rates", ja: "レートを更新") }
            static func refreshRates(language: MistiaAppLanguage) -> String { L10n.tr("settings.currency.refreshRates", vi: "Cập nhật tỷ giá", en: "Refresh rates", ja: "レートを更新", language: language) }
            static var refreshingRates: String { L10n.tr("settings.currency.refreshingRates", vi: "Đang cập nhật", en: "Refreshing", ja: "更新中") }
            static func refreshingRates(language: MistiaAppLanguage) -> String { L10n.tr("settings.currency.refreshingRates", vi: "Đang cập nhật", en: "Refreshing", ja: "更新中", language: language) }
            static var title: String { L10n.tr("settings.currency.title", vi: "Tiền tệ", en: "Currency", ja: "通貨") }
            static func title(language: MistiaAppLanguage) -> String { L10n.tr("settings.currency.title", vi: "Tiền tệ", en: "Currency", ja: "通貨", language: language) }
        }

        nonisolated enum feedback {
            static var addMore: String { L10n.tr("settings.feedback.addMore", vi: "Thêm", en: "Add", ja: "追加") }
            static func addMore(language: MistiaAppLanguage) -> String { L10n.tr("settings.feedback.addMore", vi: "Thêm", en: "Add", ja: "追加", language: language) }
            static var addPhoto: String { L10n.tr("settings.feedback.addPhoto", vi: "Thêm ảnh đính kèm (tối đa 5)", en: "Add photos (max 5)", ja: "写真を添付（最大5枚）") }
            static func addPhoto(language: MistiaAppLanguage) -> String { L10n.tr("settings.feedback.addPhoto", vi: "Thêm ảnh đính kèm (tối đa 5)", en: "Add photos (max 5)", ja: "写真を添付（最大5枚）", language: language) }
            static var categoryBug: String { L10n.tr("settings.feedback.categoryBug", vi: "Báo lỗi", en: "Report Bug", ja: "バグ報告") }
            static func categoryBug(language: MistiaAppLanguage) -> String { L10n.tr("settings.feedback.categoryBug", vi: "Báo lỗi", en: "Report Bug", ja: "バグ報告", language: language) }
            static var categoryFeature: String { L10n.tr("settings.feedback.categoryFeature", vi: "Góp ý tính năng", en: "Feature Request", ja: "機能リクエスト") }
            static func categoryFeature(language: MistiaAppLanguage) -> String { L10n.tr("settings.feedback.categoryFeature", vi: "Góp ý tính năng", en: "Feature Request", ja: "機能リクエスト", language: language) }
            static var categoryGeneral: String { L10n.tr("settings.feedback.categoryGeneral", vi: "Ý kiến chung", en: "General Feedback", ja: "一般的な意見") }
            static func categoryGeneral(language: MistiaAppLanguage) -> String { L10n.tr("settings.feedback.categoryGeneral", vi: "Ý kiến chung", en: "General Feedback", ja: "一般的な意見", language: language) }
            static var categoryTitle: String { L10n.tr("settings.feedback.categoryTitle", vi: "Phân loại", en: "Category", ja: "分類") }
            static func categoryTitle(language: MistiaAppLanguage) -> String { L10n.tr("settings.feedback.categoryTitle", vi: "Phân loại", en: "Category", ja: "分類", language: language) }
            static var contentPlaceholder: String { L10n.tr("settings.feedback.contentPlaceholder", vi: "Chia sẻ với chúng tôi cảm nhận hoặc vấn đề bạn gặp phải...", en: "Share your thoughts or issues you encountered with us...", ja: "ご意見や遭遇した問題をお聞かせください...") }
            static func contentPlaceholder(language: MistiaAppLanguage) -> String { L10n.tr("settings.feedback.contentPlaceholder", vi: "Chia sẻ với chúng tôi cảm nhận hoặc vấn đề bạn gặp phải...", en: "Share your thoughts or issues you encountered with us...", ja: "ご意見や遭遇した問題をお聞かせください...", language: language) }
            static var contentTitle: String { L10n.tr("settings.feedback.contentTitle", vi: "Nội dung phản hồi", en: "Feedback Content", ja: "フィードバック内容") }
            static func contentTitle(language: MistiaAppLanguage) -> String { L10n.tr("settings.feedback.contentTitle", vi: "Nội dung phản hồi", en: "Feedback Content", ja: "フィードバック内容", language: language) }
            static var includeDeviceInfoTitle: String { L10n.tr("settings.feedback.includeDeviceInfoTitle", vi: "Kèm thông tin thiết bị", en: "Include device info", ja: "端末情報を含める") }
            static func includeDeviceInfoTitle(language: MistiaAppLanguage) -> String { L10n.tr("settings.feedback.includeDeviceInfoTitle", vi: "Kèm thông tin thiết bị", en: "Include device info", ja: "端末情報を含める", language: language) }
            static var photoSectionTitle: String { L10n.tr("settings.feedback.photoSectionTitle", vi: "Hình ảnh đính kèm", en: "Attached Photos", ja: "添付画像") }
            static func photoSectionTitle(language: MistiaAppLanguage) -> String { L10n.tr("settings.feedback.photoSectionTitle", vi: "Hình ảnh đính kèm", en: "Attached Photos", ja: "添付画像", language: language) }
            static var submit: String { L10n.tr("settings.feedback.submit", vi: "Gửi phản hồi", en: "Submit Feedback", ja: "送信") }
            static func submit(language: MistiaAppLanguage) -> String { L10n.tr("settings.feedback.submit", vi: "Gửi phản hồi", en: "Submit Feedback", ja: "送信", language: language) }
            static var successMessage: String { L10n.tr("settings.feedback.successMessage", vi: "Ý kiến của bạn đã được ghi nhận. Chúng tôi sẽ liên tục cải thiện Mistia.", en: "Your feedback has been received. We will continuously improve Mistia.", ja: "ご意見を受領しました。ミスティアの改善に役立ててまいります。") }
            static func successMessage(language: MistiaAppLanguage) -> String { L10n.tr("settings.feedback.successMessage", vi: "Ý kiến của bạn đã được ghi nhận. Chúng tôi sẽ liên tục cải thiện Mistia.", en: "Your feedback has been received. We will continuously improve Mistia.", ja: "ご意見を受領しました。ミスティアの改善に役立ててまいります。", language: language) }
            static var successTitle: String { L10n.tr("settings.feedback.successTitle", vi: "Cảm ơn bạn!", en: "Thank you!", ja: "ありがとうございます！") }
            static func successTitle(language: MistiaAppLanguage) -> String { L10n.tr("settings.feedback.successTitle", vi: "Cảm ơn bạn!", en: "Thank you!", ja: "ありがとうございます！", language: language) }
            static var title: String { L10n.tr("settings.feedback.title", vi: "Gửi feedback", en: "Send feedback", ja: "フィードバック") }
            static func title(language: MistiaAppLanguage) -> String { L10n.tr("settings.feedback.title", vi: "Gửi feedback", en: "Send feedback", ja: "フィードバック", language: language) }
        }

        nonisolated enum language {

            nonisolated enum option {
                static var english: String { L10n.tr("settings.language.option.english", vi: "English", en: "English", ja: "英語") }
                static func english(language: MistiaAppLanguage) -> String { L10n.tr("settings.language.option.english", vi: "English", en: "English", ja: "英語", language: language) }
                static var japanese: String { L10n.tr("settings.language.option.japanese", vi: "日本語", en: "日本語", ja: "日本語") }
                static func japanese(language: MistiaAppLanguage) -> String { L10n.tr("settings.language.option.japanese", vi: "日本語", en: "日本語", ja: "日本語", language: language) }
                static var vietnamese: String { L10n.tr("settings.language.option.vietnamese", vi: "Tiếng Việt", en: "Vietnamese", ja: "ベトナム語") }
                static func vietnamese(language: MistiaAppLanguage) -> String { L10n.tr("settings.language.option.vietnamese", vi: "Tiếng Việt", en: "Vietnamese", ja: "ベトナム語", language: language) }
            }
            static var title: String { L10n.tr("settings.language.title", vi: "Ngôn ngữ", en: "Language", ja: "言語") }
            static func title(language: MistiaAppLanguage) -> String { L10n.tr("settings.language.title", vi: "Ngôn ngữ", en: "Language", ja: "言語", language: language) }
        }

        nonisolated enum notifications {

            nonisolated enum enable {
                static var description: String { L10n.tr("settings.notifications.enable.description", vi: "Khi bật, Mistia có thể gửi thông báo nhắc nhở quan trọng.", en: "When enabled, Mistia can send important reminders.", ja: "有効にすると、ミスティアから重要なリマインダー通知が届きます。") }
                static func description(language: MistiaAppLanguage) -> String { L10n.tr("settings.notifications.enable.description", vi: "Khi bật, Mistia có thể gửi thông báo nhắc nhở quan trọng.", en: "When enabled, Mistia can send important reminders.", ja: "有効にすると、ミスティアから重要なリマインダー通知が届きます。", language: language) }
                static var title: String { L10n.tr("settings.notifications.enable.title", vi: "Bật thông báo", en: "Enable notifications", ja: "通知を有効にする") }
                static func title(language: MistiaAppLanguage) -> String { L10n.tr("settings.notifications.enable.title", vi: "Bật thông báo", en: "Enable notifications", ja: "通知を有効にする", language: language) }
            }

            nonisolated enum family {
                static var description: String { L10n.tr("settings.notifications.family.description", vi: "Thông báo gia đình gồm yêu cầu quyền, thay đổi quyền và hoạt động tài chính từ các thành viên được chia sẻ.", en: "Family notifications include permission requests, permission changes, and shared financial activity from members.", ja: "家族通知には、権限リクエスト、権限変更、共有された家族の財務アクティビティが含まれます。") }
                static func description(language: MistiaAppLanguage) -> String { L10n.tr("settings.notifications.family.description", vi: "Thông báo gia đình gồm yêu cầu quyền, thay đổi quyền và hoạt động tài chính từ các thành viên được chia sẻ.", en: "Family notifications include permission requests, permission changes, and shared financial activity from members.", ja: "家族通知には、権限リクエスト、権限変更、共有された家族の財務アクティビティが含まれます。", language: language) }
                static var title: String { L10n.tr("settings.notifications.family.title", vi: "Gia đình", en: "Family", ja: "家族") }
                static func title(language: MistiaAppLanguage) -> String { L10n.tr("settings.notifications.family.title", vi: "Gia đình", en: "Family", ja: "家族", language: language) }
            }

            nonisolated enum reminders {
                static var bills: String { L10n.tr("settings.notifications.reminders.bills", vi: "Hóa đơn", en: "Bills", ja: "請求") }
                static func bills(language: MistiaAppLanguage) -> String { L10n.tr("settings.notifications.reminders.bills", vi: "Hóa đơn", en: "Bills", ja: "請求", language: language) }
                static var budget: String { L10n.tr("settings.notifications.reminders.budget", vi: "Ngân sách", en: "Budget", ja: "予算") }
                static func budget(language: MistiaAppLanguage) -> String { L10n.tr("settings.notifications.reminders.budget", vi: "Ngân sách", en: "Budget", ja: "予算", language: language) }
                static var creditCards: String { L10n.tr("settings.notifications.reminders.creditCards", vi: "Thẻ tín dụng", en: "Credit cards", ja: "クレジットカード") }
                static func creditCards(language: MistiaAppLanguage) -> String { L10n.tr("settings.notifications.reminders.creditCards", vi: "Thẻ tín dụng", en: "Credit cards", ja: "クレジットカード", language: language) }
                static var description: String { L10n.tr("settings.notifications.reminders.description", vi: "Mistia sẽ nhắc khi ngân sách sắp vượt mức, hóa đơn cần trả hoặc quá hạn, sao kê thẻ cần trả và ví sắp hết tiền.", en: "Mistia reminds you when budgets are near the limit, bills are due or overdue, credit card statements need payment, and wallets run low.", ja: "予算が上限に近いとき、請求の期限や延滞、カード明細の支払い、ウォレット残高不足を通知します。") }
                static func description(language: MistiaAppLanguage) -> String { L10n.tr("settings.notifications.reminders.description", vi: "Mistia sẽ nhắc khi ngân sách sắp vượt mức, hóa đơn cần trả hoặc quá hạn, sao kê thẻ cần trả và ví sắp hết tiền.", en: "Mistia reminds you when budgets are near the limit, bills are due or overdue, credit card statements need payment, and wallets run low.", ja: "予算が上限に近いとき、請求の期限や延滞、カード明細の支払い、ウォレット残高不足を通知します。", language: language) }
                static var title: String { L10n.tr("settings.notifications.reminders.title", vi: "Nhắc nhở", en: "Reminders", ja: "リマインダー") }
                static func title(language: MistiaAppLanguage) -> String { L10n.tr("settings.notifications.reminders.title", vi: "Nhắc nhở", en: "Reminders", ja: "リマインダー", language: language) }
                static var wallets: String { L10n.tr("settings.notifications.reminders.wallets", vi: "Ví", en: "Wallets", ja: "ウォレット") }
                static func wallets(language: MistiaAppLanguage) -> String { L10n.tr("settings.notifications.reminders.wallets", vi: "Ví", en: "Wallets", ja: "ウォレット", language: language) }
            }
            static var title: String { L10n.tr("settings.notifications.title", vi: "Thông báo", en: "Notifications", ja: "通知") }
            static func title(language: MistiaAppLanguage) -> String { L10n.tr("settings.notifications.title", vi: "Thông báo", en: "Notifications", ja: "通知", language: language) }
        }

        nonisolated enum resetData {
            static func categoriesArchivedMessage(_ count: Int) -> String {
                L10n.format("settings.resetData.categoriesArchivedMessage", vi: "%lld danh mục tự tạo đã được lưu trữ.", en: "%lld custom categories were archived.", ja: "作成したカテゴリ %lld 件をアーカイブしました。", Int64(count))
            }
            static func categoriesArchivedMessage(_ count: Int, language: MistiaAppLanguage) -> String {
                L10n.format("settings.resetData.categoriesArchivedMessage", vi: "%lld danh mục tự tạo đã được lưu trữ.", en: "%lld custom categories were archived.", ja: "作成したカテゴリ %lld 件をアーカイブしました。", language: language, Int64(count))
            }
            static var categoriesResetFailedTitle: String { L10n.tr("settings.resetData.categoriesResetFailedTitle", vi: "Không thể reset danh mục", en: "Couldn't reset categories", ja: "カテゴリをリセットできませんでした") }
            static func categoriesResetFailedTitle(language: MistiaAppLanguage) -> String { L10n.tr("settings.resetData.categoriesResetFailedTitle", vi: "Không thể reset danh mục", en: "Couldn't reset categories", ja: "カテゴリをリセットできませんでした", language: language) }
            static var categoriesResetMessage: String { L10n.tr("settings.resetData.categoriesResetMessage", vi: "Danh mục system trên thiết bị này đã về trạng thái ban đầu.", en: "System categories on this device are back to defaults.", ja: "この端末のシステムカテゴリを初期状態に戻しました。") }
            static func categoriesResetMessage(language: MistiaAppLanguage) -> String { L10n.tr("settings.resetData.categoriesResetMessage", vi: "Danh mục system trên thiết bị này đã về trạng thái ban đầu.", en: "System categories on this device are back to defaults.", ja: "この端末のシステムカテゴリを初期状態に戻しました。", language: language) }
            static var categoriesResetTitle: String { L10n.tr("settings.resetData.categoriesResetTitle", vi: "Đã reset danh mục", en: "Categories reset", ja: "カテゴリをリセットしました") }
            static func categoriesResetTitle(language: MistiaAppLanguage) -> String { L10n.tr("settings.resetData.categoriesResetTitle", vi: "Đã reset danh mục", en: "Categories reset", ja: "カテゴリをリセットしました", language: language) }

            nonisolated enum deleteAllData {
                static var confirmationMessage: String { L10n.tr("settings.resetData.deleteAllData.confirmationMessage", vi: "Mistia chỉ xóa dữ liệu local trên thiết bị này. Đăng nhập, hồ sơ cloud và gia đình vẫn được giữ.", en: "Mistia will only clear local data on this device. Sign-in, cloud profile, and family are preserved.", ja: "この端末のローカルデータのみを削除します。ログイン、クラウドプロフィール、家族は保持されます。") }
                static func confirmationMessage(language: MistiaAppLanguage) -> String { L10n.tr("settings.resetData.deleteAllData.confirmationMessage", vi: "Mistia chỉ xóa dữ liệu local trên thiết bị này. Đăng nhập, hồ sơ cloud và gia đình vẫn được giữ.", en: "Mistia will only clear local data on this device. Sign-in, cloud profile, and family are preserved.", ja: "この端末のローカルデータのみを削除します。ログイン、クラウドプロフィール、家族は保持されます。", language: language) }
                static var confirmationTitle: String { L10n.tr("settings.resetData.deleteAllData.confirmationTitle", vi: "Xóa tất cả dữ liệu?", en: "Delete all data?", ja: "すべてのデータを削除しますか？") }
                static func confirmationTitle(language: MistiaAppLanguage) -> String { L10n.tr("settings.resetData.deleteAllData.confirmationTitle", vi: "Xóa tất cả dữ liệu?", en: "Delete all data?", ja: "すべてのデータを削除しますか？", language: language) }
                static var title: String { L10n.tr("settings.resetData.deleteAllData.title", vi: "Xóa tất cả dữ liệu", en: "Delete all data", ja: "すべてのデータを削除") }
                static func title(language: MistiaAppLanguage) -> String { L10n.tr("settings.resetData.deleteAllData.title", vi: "Xóa tất cả dữ liệu", en: "Delete all data", ja: "すべてのデータを削除", language: language) }
            }
            static var deleteDataFailedTitle: String { L10n.tr("settings.resetData.deleteDataFailedTitle", vi: "Không thể xóa dữ liệu", en: "Couldn't delete data", ja: "データを削除できませんでした") }
            static func deleteDataFailedTitle(language: MistiaAppLanguage) -> String { L10n.tr("settings.resetData.deleteDataFailedTitle", vi: "Không thể xóa dữ liệu", en: "Couldn't delete data", ja: "データを削除できませんでした", language: language) }
            static var localDataDeletedMessage: String { L10n.tr("settings.resetData.localDataDeletedMessage", vi: "Thiết bị này đã về trạng thái dữ liệu ban đầu. Cloud, đăng nhập và gia đình vẫn được giữ.", en: "This device is back to a clean local data state. Cloud, sign-in, and family are preserved.", ja: "この端末のデータを初期状態に戻しました。クラウド、ログイン、家族は保持されています。") }
            static func localDataDeletedMessage(language: MistiaAppLanguage) -> String { L10n.tr("settings.resetData.localDataDeletedMessage", vi: "Thiết bị này đã về trạng thái dữ liệu ban đầu. Cloud, đăng nhập và gia đình vẫn được giữ.", en: "This device is back to a clean local data state. Cloud, sign-in, and family are preserved.", ja: "この端末のデータを初期状態に戻しました。クラウド、ログイン、家族は保持されています。", language: language) }
            static var localDataDeletedTitle: String { L10n.tr("settings.resetData.localDataDeletedTitle", vi: "Đã xóa dữ liệu local", en: "Local data deleted", ja: "ローカルデータを削除しました") }
            static func localDataDeletedTitle(language: MistiaAppLanguage) -> String { L10n.tr("settings.resetData.localDataDeletedTitle", vi: "Đã xóa dữ liệu local", en: "Local data deleted", ja: "ローカルデータを削除しました", language: language) }
            static var notificationsResetFailedTitle: String { L10n.tr("settings.resetData.notificationsResetFailedTitle", vi: "Không thể reset thông báo", en: "Couldn't reset notifications", ja: "通知をリセットできませんでした") }
            static func notificationsResetFailedTitle(language: MistiaAppLanguage) -> String { L10n.tr("settings.resetData.notificationsResetFailedTitle", vi: "Không thể reset thông báo", en: "Couldn't reset notifications", ja: "通知をリセットできませんでした", language: language) }
            static var notificationsResetMessage: String { L10n.tr("settings.resetData.notificationsResetMessage", vi: "Trung tâm thông báo trên thiết bị này đã về 0 row.", en: "The notification center on this device is now empty.", ja: "この端末の通知センターを空にしました。") }
            static func notificationsResetMessage(language: MistiaAppLanguage) -> String { L10n.tr("settings.resetData.notificationsResetMessage", vi: "Trung tâm thông báo trên thiết bị này đã về 0 row.", en: "The notification center on this device is now empty.", ja: "この端末の通知センターを空にしました。", language: language) }
            static var notificationsResetTitle: String { L10n.tr("settings.resetData.notificationsResetTitle", vi: "Đã reset thông báo", en: "Notifications reset", ja: "通知をリセットしました") }
            static func notificationsResetTitle(language: MistiaAppLanguage) -> String { L10n.tr("settings.resetData.notificationsResetTitle", vi: "Đã reset thông báo", en: "Notifications reset", ja: "通知をリセットしました", language: language) }

            nonisolated enum reset {
                static var categoriesConfirmationMessage: String { L10n.tr("settings.resetData.reset.categoriesConfirmationMessage", vi: "Danh mục system sẽ về mặc định. Danh mục tự tạo được chuyển vào lưu trữ.", en: "System categories return to defaults. Custom categories move to archived items.", ja: "システムカテゴリを初期状態に戻し、作成したカテゴリはアーカイブに移動します。") }
                static func categoriesConfirmationMessage(language: MistiaAppLanguage) -> String { L10n.tr("settings.resetData.reset.categoriesConfirmationMessage", vi: "Danh mục system sẽ về mặc định. Danh mục tự tạo được chuyển vào lưu trữ.", en: "System categories return to defaults. Custom categories move to archived items.", ja: "システムカテゴリを初期状態に戻し、作成したカテゴリはアーカイブに移動します。", language: language) }
                static var categoriesConfirmationTitle: String { L10n.tr("settings.resetData.reset.categoriesConfirmationTitle", vi: "Reset danh mục?", en: "Reset categories?", ja: "カテゴリをリセットしますか？") }
                static func categoriesConfirmationTitle(language: MistiaAppLanguage) -> String { L10n.tr("settings.resetData.reset.categoriesConfirmationTitle", vi: "Reset danh mục?", en: "Reset categories?", ja: "カテゴリをリセットしますか？", language: language) }
                static var categoriesTitle: String { L10n.tr("settings.resetData.reset.categoriesTitle", vi: "Reset danh mục", en: "Reset categories", ja: "カテゴリをリセット") }
                static func categoriesTitle(language: MistiaAppLanguage) -> String { L10n.tr("settings.resetData.reset.categoriesTitle", vi: "Reset danh mục", en: "Reset categories", ja: "カテゴリをリセット", language: language) }
                static var notificationsTitle: String { L10n.tr("settings.resetData.reset.notificationsTitle", vi: "Reset thông báo", en: "Reset notifications", ja: "通知をリセット") }
                static func notificationsTitle(language: MistiaAppLanguage) -> String { L10n.tr("settings.resetData.reset.notificationsTitle", vi: "Reset thông báo", en: "Reset notifications", ja: "通知をリセット", language: language) }
                static var optionsMessage: String { L10n.tr("settings.resetData.reset.optionsMessage", vi: "Chọn phần bạn muốn đưa về trạng thái ban đầu.", en: "Choose what you want to return to its default state.", ja: "初期状態に戻す項目を選んでください。") }
                static func optionsMessage(language: MistiaAppLanguage) -> String { L10n.tr("settings.resetData.reset.optionsMessage", vi: "Chọn phần bạn muốn đưa về trạng thái ban đầu.", en: "Choose what you want to return to its default state.", ja: "初期状態に戻す項目を選んでください。", language: language) }
                static var settingsTitle: String { L10n.tr("settings.resetData.reset.settingsTitle", vi: "Reset cài đặt", en: "Reset settings", ja: "設定をリセット") }
                static func settingsTitle(language: MistiaAppLanguage) -> String { L10n.tr("settings.resetData.reset.settingsTitle", vi: "Reset cài đặt", en: "Reset settings", ja: "設定をリセット", language: language) }
                static var title: String { L10n.tr("settings.resetData.reset.title", vi: "Reset", en: "Reset", ja: "リセット") }
                static func title(language: MistiaAppLanguage) -> String { L10n.tr("settings.resetData.reset.title", vi: "Reset", en: "Reset", ja: "リセット", language: language) }
            }
            static var settingsResetMessage: String { L10n.tr("settings.resetData.settingsResetMessage", vi: "Cài đặt app đã về mặc định. Dữ liệu, đăng nhập và gia đình không bị thay đổi.", en: "App settings are back to defaults. Data, sign-in, and family were not changed.", ja: "アプリ設定を初期状態に戻しました。データ、ログイン、家族は変更していません。") }
            static func settingsResetMessage(language: MistiaAppLanguage) -> String { L10n.tr("settings.resetData.settingsResetMessage", vi: "Cài đặt app đã về mặc định. Dữ liệu, đăng nhập và gia đình không bị thay đổi.", en: "App settings are back to defaults. Data, sign-in, and family were not changed.", ja: "アプリ設定を初期状態に戻しました。データ、ログイン、家族は変更していません。", language: language) }
            static var settingsResetTitle: String { L10n.tr("settings.resetData.settingsResetTitle", vi: "Đã reset cài đặt", en: "Settings reset", ja: "設定をリセットしました") }
            static func settingsResetTitle(language: MistiaAppLanguage) -> String { L10n.tr("settings.resetData.settingsResetTitle", vi: "Đã reset cài đặt", en: "Settings reset", ja: "設定をリセットしました", language: language) }
            static var title: String { L10n.tr("settings.resetData.title", vi: "Đặt lại & dữ liệu", en: "Reset & data", ja: "リセットとデータ") }
            static func title(language: MistiaAppLanguage) -> String { L10n.tr("settings.resetData.title", vi: "Đặt lại & dữ liệu", en: "Reset & data", ja: "リセットとデータ", language: language) }
        }

        nonisolated enum security {

            nonisolated enum appLock {
                static var description: String { L10n.tr("settings.security.appLock.description", vi: "Yêu cầu mã của app khi mở lại Mistia hoặc quay lại từ nền.", en: "Require an app code when Mistia opens or returns from the background.", ja: "Mistiaを開くとき、またはバックグラウンドから戻るときにアプリのコードを要求します。") }
                static func description(language: MistiaAppLanguage) -> String { L10n.tr("settings.security.appLock.description", vi: "Yêu cầu mã của app khi mở lại Mistia hoặc quay lại từ nền.", en: "Require an app code when Mistia opens or returns from the background.", ja: "Mistiaを開くとき、またはバックグラウンドから戻るときにアプリのコードを要求します。", language: language) }
                static var title: String { L10n.tr("settings.security.appLock.title", vi: "Khóa app", en: "App lock", ja: "アプリロック") }
                static func title(language: MistiaAppLanguage) -> String { L10n.tr("settings.security.appLock.title", vi: "Khóa app", en: "App lock", ja: "アプリロック", language: language) }
            }

            nonisolated enum biometric {
                static var faceID: String { L10n.tr("settings.security.biometric.faceID", vi: "Face ID", en: "Face ID", ja: "Face ID") }
                static func faceID(language: MistiaAppLanguage) -> String { L10n.tr("settings.security.biometric.faceID", vi: "Face ID", en: "Face ID", ja: "Face ID", language: language) }
                static var generic: String { L10n.tr("settings.security.biometric.generic", vi: "Sinh trắc học", en: "Biometric unlock", ja: "生体認証ロック解除") }
                static func generic(language: MistiaAppLanguage) -> String { L10n.tr("settings.security.biometric.generic", vi: "Sinh trắc học", en: "Biometric unlock", ja: "生体認証ロック解除", language: language) }
                static var opticID: String { L10n.tr("settings.security.biometric.opticID", vi: "Optic ID", en: "Optic ID", ja: "Optic ID") }
                static func opticID(language: MistiaAppLanguage) -> String { L10n.tr("settings.security.biometric.opticID", vi: "Optic ID", en: "Optic ID", ja: "Optic ID", language: language) }
                static var touchID: String { L10n.tr("settings.security.biometric.touchID", vi: "Touch ID", en: "Touch ID", ja: "Touch ID") }
                static func touchID(language: MistiaAppLanguage) -> String { L10n.tr("settings.security.biometric.touchID", vi: "Touch ID", en: "Touch ID", ja: "Touch ID", language: language) }
                static var unavailable: String { L10n.tr("settings.security.biometric.unavailable", vi: "Thiết bị này chưa có Face ID hoặc Touch ID khả dụng.", en: "Face ID or Touch ID is not available on this device.", ja: "このデバイスではFace IDまたはTouch IDを利用できません。") }
                static func unavailable(language: MistiaAppLanguage) -> String { L10n.tr("settings.security.biometric.unavailable", vi: "Thiết bị này chưa có Face ID hoặc Touch ID khả dụng.", en: "Face ID or Touch ID is not available on this device.", ja: "このデバイスではFace IDまたはTouch IDを利用できません。", language: language) }
            }

            nonisolated enum biometricPrompt {
                static func confirm(_ value: String) -> String {
                    L10n.format("settings.security.biometricPrompt.confirm", vi: "Dùng %@", en: "Use %@", ja: "%@を使う", value)
                }
                static func confirm(_ value: String, language: MistiaAppLanguage) -> String {
                    L10n.format("settings.security.biometricPrompt.confirm", vi: "Dùng %@", en: "Use %@", ja: "%@を使う", language: language, value)
                }
                static func message(_ value: String) -> String {
                    L10n.format("settings.security.biometricPrompt.message", vi: "Từ lần mở sau, Mistia sẽ xác thực bằng %@. Mã khóa vẫn dùng làm mã dự phòng.", en: "Next time, Mistia will unlock with %@. Your app code stays available as backup.", ja: "次回からMistiaは%@でロック解除します。アプリコードはバックアップとして引き続き使えます。", value)
                }
                static func message(_ value: String, language: MistiaAppLanguage) -> String {
                    L10n.format("settings.security.biometricPrompt.message", vi: "Từ lần mở sau, Mistia sẽ xác thực bằng %@. Mã khóa vẫn dùng làm mã dự phòng.", en: "Next time, Mistia will unlock with %@. Your app code stays available as backup.", ja: "次回からMistiaは%@でロック解除します。アプリコードはバックアップとして引き続き使えます。", language: language, value)
                }
                static var notNow: String { L10n.tr("settings.security.biometricPrompt.notNow", vi: "Để sau", en: "Not now", ja: "あとで") }
                static func notNow(language: MistiaAppLanguage) -> String { L10n.tr("settings.security.biometricPrompt.notNow", vi: "Để sau", en: "Not now", ja: "あとで", language: language) }
                static func title(_ value: String) -> String {
                    L10n.format("settings.security.biometricPrompt.title", vi: "Sử dụng %@?", en: "Use %@?", ja: "%@を使いますか？", value)
                }
                static func title(_ value: String, language: MistiaAppLanguage) -> String {
                    L10n.format("settings.security.biometricPrompt.title", vi: "Sử dụng %@?", en: "Use %@?", ja: "%@を使いますか？", language: language, value)
                }
            }

            nonisolated enum forgotCode {
                static var description: String { L10n.tr("settings.security.forgotCode.description", vi: "Tùy chọn khôi phục sẽ được bổ sung sau.", en: "Recovery options will be added later.", ja: "復旧オプションは今後追加されます。") }
                static func description(language: MistiaAppLanguage) -> String { L10n.tr("settings.security.forgotCode.description", vi: "Tùy chọn khôi phục sẽ được bổ sung sau.", en: "Recovery options will be added later.", ja: "復旧オプションは今後追加されます。", language: language) }
                static var title: String { L10n.tr("settings.security.forgotCode.title", vi: "Quên mã?", en: "Forgot code?", ja: "コードを忘れましたか？") }
                static func title(language: MistiaAppLanguage) -> String { L10n.tr("settings.security.forgotCode.title", vi: "Quên mã?", en: "Forgot code?", ja: "コードを忘れましたか？", language: language) }
            }

            nonisolated enum secretKind {

                nonisolated enum customPassword {
                    static var subtitle: String { L10n.tr("settings.security.secretKind.customPassword.subtitle", vi: "Dùng mật khẩu riêng cho app.", en: "Use a custom app password.", ja: "アプリ専用のパスワードを使います。") }
                    static func subtitle(language: MistiaAppLanguage) -> String { L10n.tr("settings.security.secretKind.customPassword.subtitle", vi: "Dùng mật khẩu riêng cho app.", en: "Use a custom app password.", ja: "アプリ専用のパスワードを使います。", language: language) }
                    static var title: String { L10n.tr("settings.security.secretKind.customPassword.title", vi: "Mật khẩu tùy chỉnh", en: "Custom password", ja: "カスタムパスワード") }
                    static func title(language: MistiaAppLanguage) -> String { L10n.tr("settings.security.secretKind.customPassword.title", vi: "Mật khẩu tùy chỉnh", en: "Custom password", ja: "カスタムパスワード", language: language) }
                }

                nonisolated enum pin4 {
                    static var subtitle: String { L10n.tr("settings.security.secretKind.pin4.subtitle", vi: "Nhanh để mở khóa hằng ngày.", en: "Fast for everyday unlocks.", ja: "毎日のロック解除をすばやく行えます。") }
                    static func subtitle(language: MistiaAppLanguage) -> String { L10n.tr("settings.security.secretKind.pin4.subtitle", vi: "Nhanh để mở khóa hằng ngày.", en: "Fast for everyday unlocks.", ja: "毎日のロック解除をすばやく行えます。", language: language) }
                    static var title: String { L10n.tr("settings.security.secretKind.pin4.title", vi: "PIN 4 số", en: "4-digit PIN", ja: "4桁PIN") }
                    static func title(language: MistiaAppLanguage) -> String { L10n.tr("settings.security.secretKind.pin4.title", vi: "PIN 4 số", en: "4-digit PIN", ja: "4桁PIN", language: language) }
                }

                nonisolated enum pin6 {
                    static var subtitle: String { L10n.tr("settings.security.secretKind.pin6.subtitle", vi: "Thêm hai số cho lớp bảo vệ chặt hơn.", en: "Add two digits for stronger protection.", ja: "2桁追加して保護を強化します。") }
                    static func subtitle(language: MistiaAppLanguage) -> String { L10n.tr("settings.security.secretKind.pin6.subtitle", vi: "Thêm hai số cho lớp bảo vệ chặt hơn.", en: "Add two digits for stronger protection.", ja: "2桁追加して保護を強化します。", language: language) }
                    static var title: String { L10n.tr("settings.security.secretKind.pin6.title", vi: "PIN 6 số", en: "6-digit PIN", ja: "6桁PIN") }
                    static func title(language: MistiaAppLanguage) -> String { L10n.tr("settings.security.secretKind.pin6.title", vi: "PIN 6 số", en: "6-digit PIN", ja: "6桁PIN", language: language) }
                }
                static var title: String { L10n.tr("settings.security.secretKind.title", vi: "Kiểu mã khóa", en: "Code type", ja: "コードの種類") }
                static func title(language: MistiaAppLanguage) -> String { L10n.tr("settings.security.secretKind.title", vi: "Kiểu mã khóa", en: "Code type", ja: "コードの種類", language: language) }
            }

            nonisolated enum status {
                static func biometricDisabledMessage(_ value: String) -> String {
                    L10n.format("settings.security.status.biometricDisabledMessage", vi: "Mở khóa bằng %@ đã tắt. Bạn vẫn có thể dùng mã của app.", en: "%@ unlock is off. You can still use the app code.", ja: "%@ロック解除はオフです。引き続きアプリのコードを使えます。", value)
                }
                static func biometricDisabledMessage(_ value: String, language: MistiaAppLanguage) -> String {
                    L10n.format("settings.security.status.biometricDisabledMessage", vi: "Mở khóa bằng %@ đã tắt. Bạn vẫn có thể dùng mã của app.", en: "%@ unlock is off. You can still use the app code.", ja: "%@ロック解除はオフです。引き続きアプリのコードを使えます。", language: language, value)
                }
                static func biometricDisabledTitle(_ value: String) -> String {
                    L10n.format("settings.security.status.biometricDisabledTitle", vi: "Đã tắt %@", en: "%@ unlock off", ja: "%@がオフになりました", value)
                }
                static func biometricDisabledTitle(_ value: String, language: MistiaAppLanguage) -> String {
                    L10n.format("settings.security.status.biometricDisabledTitle", vi: "Đã tắt %@", en: "%@ unlock off", ja: "%@がオフになりました", language: language, value)
                }
                static func biometricEnabledMessage(_ value: String) -> String {
                    L10n.format("settings.security.status.biometricEnabledMessage", vi: "Mistia có thể mở khóa bằng %@ hoặc mã dự phòng.", en: "Mistia can unlock with %@ or your backup code.", ja: "%@またはバックアップコードでMistiaをロック解除できます。", value)
                }
                static func biometricEnabledMessage(_ value: String, language: MistiaAppLanguage) -> String {
                    L10n.format("settings.security.status.biometricEnabledMessage", vi: "Mistia có thể mở khóa bằng %@ hoặc mã dự phòng.", en: "Mistia can unlock with %@ or your backup code.", ja: "%@またはバックアップコードでMistiaをロック解除できます。", language: language, value)
                }
                static func biometricEnabledTitle(_ value: String) -> String {
                    L10n.format("settings.security.status.biometricEnabledTitle", vi: "Đã bật %@", en: "%@ unlock on", ja: "%@がオンになりました", value)
                }
                static func biometricEnabledTitle(_ value: String, language: MistiaAppLanguage) -> String {
                    L10n.format("settings.security.status.biometricEnabledTitle", vi: "Đã bật %@", en: "%@ unlock on", ja: "%@がオンになりました", language: language, value)
                }
                static var changedMessage: String { L10n.tr("settings.security.status.changedMessage", vi: "Mã khóa mới sẽ được dùng từ lần khóa tiếp theo.", en: "The new code will be used from the next lock.", ja: "次回のロックから新しいコードが使われます。") }
                static func changedMessage(language: MistiaAppLanguage) -> String { L10n.tr("settings.security.status.changedMessage", vi: "Mã khóa mới sẽ được dùng từ lần khóa tiếp theo.", en: "The new code will be used from the next lock.", ja: "次回のロックから新しいコードが使われます。", language: language) }
                static var changedTitle: String { L10n.tr("settings.security.status.changedTitle", vi: "Đã cập nhật mã khóa", en: "Code updated", ja: "コードを更新しました") }
                static func changedTitle(language: MistiaAppLanguage) -> String { L10n.tr("settings.security.status.changedTitle", vi: "Đã cập nhật mã khóa", en: "Code updated", ja: "コードを更新しました", language: language) }
                static var disabledMessage: String { L10n.tr("settings.security.status.disabledMessage", vi: "Mistia sẽ không yêu cầu mã khi mở lại app.", en: "Mistia will no longer ask for a code when the app opens again.", ja: "Mistiaを再度開くときにコードは要求されません。") }
                static func disabledMessage(language: MistiaAppLanguage) -> String { L10n.tr("settings.security.status.disabledMessage", vi: "Mistia sẽ không yêu cầu mã khi mở lại app.", en: "Mistia will no longer ask for a code when the app opens again.", ja: "Mistiaを再度開くときにコードは要求されません。", language: language) }
                static var disabledTitle: String { L10n.tr("settings.security.status.disabledTitle", vi: "Đã tắt khóa app", en: "App lock off", ja: "アプリロックがオフになりました") }
                static func disabledTitle(language: MistiaAppLanguage) -> String { L10n.tr("settings.security.status.disabledTitle", vi: "Đã tắt khóa app", en: "App lock off", ja: "アプリロックがオフになりました", language: language) }
                static var enabledMessage: String { L10n.tr("settings.security.status.enabledMessage", vi: "Mistia sẽ khóa khi mở app hoặc quay lại từ nền.", en: "Mistia will lock when the app opens or returns from the background.", ja: "アプリを開くとき、またはバックグラウンドから戻るときにMistiaがロックされます。") }
                static func enabledMessage(language: MistiaAppLanguage) -> String { L10n.tr("settings.security.status.enabledMessage", vi: "Mistia sẽ khóa khi mở app hoặc quay lại từ nền.", en: "Mistia will lock when the app opens or returns from the background.", ja: "アプリを開くとき、またはバックグラウンドから戻るときにMistiaがロックされます。", language: language) }
                static var enabledTitle: String { L10n.tr("settings.security.status.enabledTitle", vi: "Đã bật khóa app", en: "App lock on", ja: "アプリロックがオンになりました") }
                static func enabledTitle(language: MistiaAppLanguage) -> String { L10n.tr("settings.security.status.enabledTitle", vi: "Đã bật khóa app", en: "App lock on", ja: "アプリロックがオンになりました", language: language) }
                static var errorTitle: String { L10n.tr("settings.security.status.errorTitle", vi: "Không thể cập nhật", en: "Unable to update", ja: "更新できません") }
                static func errorTitle(language: MistiaAppLanguage) -> String { L10n.tr("settings.security.status.errorTitle", vi: "Không thể cập nhật", en: "Unable to update", ja: "更新できません", language: language) }
                static var unavailableTitle: String { L10n.tr("settings.security.status.unavailableTitle", vi: "Không khả dụng", en: "Unavailable", ja: "利用できません") }
                static func unavailableTitle(language: MistiaAppLanguage) -> String { L10n.tr("settings.security.status.unavailableTitle", vi: "Không khả dụng", en: "Unavailable", ja: "利用できません", language: language) }
            }
            static var title: String { L10n.tr("settings.security.title", vi: "Bảo mật", en: "Security", ja: "セキュリティ") }
            static func title(language: MistiaAppLanguage) -> String { L10n.tr("settings.security.title", vi: "Bảo mật", en: "Security", ja: "セキュリティ", language: language) }
        }

        nonisolated enum shortcut {
            static var description: String { L10n.tr("settings.shortcut.description", vi: "Bật Lối tắt Mistia để hiện nút pinned ở tab bar. Nút này sẽ mở thẳng mục bạn chọn.", en: "Enable the Mistia shortcut to show a pinned button in the tab bar. It opens the destination you choose.", ja: "ショートカットを有効にするとタブバーに固定ボタンが表示されます。選んだ項目を直接開きます。") }
            static func description(language: MistiaAppLanguage) -> String { L10n.tr("settings.shortcut.description", vi: "Bật Lối tắt Mistia để hiện nút pinned ở tab bar. Nút này sẽ mở thẳng mục bạn chọn.", en: "Enable the Mistia shortcut to show a pinned button in the tab bar. It opens the destination you choose.", ja: "ショートカットを有効にするとタブバーに固定ボタンが表示されます。選んだ項目を直接開きます。", language: language) }
            static var enablePinnedButton: String { L10n.tr("settings.shortcut.enablePinnedButton", vi: "Bật nút pinned", en: "Enable pinned button", ja: "固定ボタンを有効にする") }
            static func enablePinnedButton(language: MistiaAppLanguage) -> String { L10n.tr("settings.shortcut.enablePinnedButton", vi: "Bật nút pinned", en: "Enable pinned button", ja: "固定ボタンを有効にする", language: language) }
            static var familySection: String { L10n.tr("settings.shortcut.familySection", vi: "Gia đình", en: "Family", ja: "家族") }
            static func familySection(language: MistiaAppLanguage) -> String { L10n.tr("settings.shortcut.familySection", vi: "Gia đình", en: "Family", ja: "家族", language: language) }

            nonisolated enum member {
                static func quickViewAccessibility(_ value: String) -> String {
                    L10n.format("settings.shortcut.member.quickViewAccessibility", vi: "Xem nhanh %@", en: "Quick view %@", ja: "%@ をすぐ見る", value)
                }
                static func quickViewAccessibility(_ value: String, language: MistiaAppLanguage) -> String {
                    L10n.format("settings.shortcut.member.quickViewAccessibility", vi: "Xem nhanh %@", en: "Quick view %@", ja: "%@ をすぐ見る", language: language, value)
                }
            }
            static var offStatus: String { L10n.tr("settings.shortcut.offStatus", vi: "Đang tắt", en: "Off", ja: "オフ") }
            static func offStatus(language: MistiaAppLanguage) -> String { L10n.tr("settings.shortcut.offStatus", vi: "Đang tắt", en: "Off", ja: "オフ", language: language) }

            nonisolated enum option {

                nonisolated enum archivedItems {
                    static var accessibility: String { L10n.tr("settings.shortcut.option.archivedItems.accessibility", vi: "Mở Mục đã lưu trữ", en: "Open archived items", ja: "アーカイブ済みアイテムを開く") }
                    static func accessibility(language: MistiaAppLanguage) -> String { L10n.tr("settings.shortcut.option.archivedItems.accessibility", vi: "Mở Mục đã lưu trữ", en: "Open archived items", ja: "アーカイブ済みアイテムを開く", language: language) }
                    static var subtitle: String { L10n.tr("settings.shortcut.option.archivedItems.subtitle", vi: "Mở các ví, danh mục và thu chi đã lưu trữ.", en: "Open archived wallets, categories, and cashflow items.", ja: "アーカイブ済みのウォレット、カテゴリ、取引を開きます。") }
                    static func subtitle(language: MistiaAppLanguage) -> String { L10n.tr("settings.shortcut.option.archivedItems.subtitle", vi: "Mở các ví, danh mục và thu chi đã lưu trữ.", en: "Open archived wallets, categories, and cashflow items.", ja: "アーカイブ済みのウォレット、カテゴリ、取引を開きます。", language: language) }
                    static var title: String { L10n.tr("settings.shortcut.option.archivedItems.title", vi: "Mục đã lưu trữ", en: "Archived items", ja: "アーカイブ済みアイテム") }
                    static func title(language: MistiaAppLanguage) -> String { L10n.tr("settings.shortcut.option.archivedItems.title", vi: "Mục đã lưu trữ", en: "Archived items", ja: "アーカイブ済みアイテム", language: language) }
                }

                nonisolated enum backupRestore {
                    static var accessibility: String { L10n.tr("settings.shortcut.option.backupRestore.accessibility", vi: "Mở Sao lưu & Khôi phục", en: "Open backup and restore", ja: "バックアップと復元を開く") }
                    static func accessibility(language: MistiaAppLanguage) -> String { L10n.tr("settings.shortcut.option.backupRestore.accessibility", vi: "Mở Sao lưu & Khôi phục", en: "Open backup and restore", ja: "バックアップと復元を開く", language: language) }
                    static var subtitle: String { L10n.tr("settings.shortcut.option.backupRestore.subtitle", vi: "Mở sao lưu cục bộ và khôi phục dữ liệu.", en: "Open local backup and restore.", ja: "ローカルのバックアップと復元を開きます。") }
                    static func subtitle(language: MistiaAppLanguage) -> String { L10n.tr("settings.shortcut.option.backupRestore.subtitle", vi: "Mở sao lưu cục bộ và khôi phục dữ liệu.", en: "Open local backup and restore.", ja: "ローカルのバックアップと復元を開きます。", language: language) }
                    static var title: String { L10n.tr("settings.shortcut.option.backupRestore.title", vi: "Sao lưu & Khôi phục", en: "Backup & Restore", ja: "バックアップ & 復元") }
                    static func title(language: MistiaAppLanguage) -> String { L10n.tr("settings.shortcut.option.backupRestore.title", vi: "Sao lưu & Khôi phục", en: "Backup & Restore", ja: "バックアップ & 復元", language: language) }
                }

                nonisolated enum familyOverview {
                    static var accessibility: String { L10n.tr("settings.shortcut.option.familyOverview.accessibility", vi: "Mở tổng quan gia đình", en: "Open family overview", ja: "家族の概要を開く") }
                    static func accessibility(language: MistiaAppLanguage) -> String { L10n.tr("settings.shortcut.option.familyOverview.accessibility", vi: "Mở tổng quan gia đình", en: "Open family overview", ja: "家族の概要を開く", language: language) }
                    static var subtitle: String { L10n.tr("settings.shortcut.option.familyOverview.subtitle", vi: "Mở thẳng màn tổng quan tài chính của cả gia đình.", en: "Open the family financial overview directly.", ja: "家族全体の財務概要を直接開きます。") }
                    static func subtitle(language: MistiaAppLanguage) -> String { L10n.tr("settings.shortcut.option.familyOverview.subtitle", vi: "Mở thẳng màn tổng quan tài chính của cả gia đình.", en: "Open the family financial overview directly.", ja: "家族全体の財務概要を直接開きます。", language: language) }
                    static var title: String { L10n.tr("settings.shortcut.option.familyOverview.title", vi: "Tổng quan gia đình", en: "Family overview", ja: "家族の概要") }
                    static func title(language: MistiaAppLanguage) -> String { L10n.tr("settings.shortcut.option.familyOverview.title", vi: "Tổng quan gia đình", en: "Family overview", ja: "家族の概要", language: language) }
                }

                nonisolated enum investment {
                    static var accessibility: String { L10n.tr("settings.shortcut.option.investment.accessibility", vi: "Mở đầu tư", en: "Open investments", ja: "投資を開く") }
                    static func accessibility(language: MistiaAppLanguage) -> String { L10n.tr("settings.shortcut.option.investment.accessibility", vi: "Mở đầu tư", en: "Open investments", ja: "投資を開く", language: language) }
                    static var subtitle: String { L10n.tr("settings.shortcut.option.investment.subtitle", vi: "Mở nhanh trung tâm đầu tư", en: "Open your investment hub", ja: "投資ハブを開く") }
                    static func subtitle(language: MistiaAppLanguage) -> String { L10n.tr("settings.shortcut.option.investment.subtitle", vi: "Mở nhanh trung tâm đầu tư", en: "Open your investment hub", ja: "投資ハブを開く", language: language) }
                    static var title: String { L10n.tr("settings.shortcut.option.investment.title", vi: "Đầu tư", en: "Investments", ja: "投資") }
                    static func title(language: MistiaAppLanguage) -> String { L10n.tr("settings.shortcut.option.investment.title", vi: "Đầu tư", en: "Investments", ja: "投資", language: language) }
                }

                nonisolated enum memberOverview {
                    static var subtitle: String { L10n.tr("settings.shortcut.option.memberOverview.subtitle", vi: "Chuyển ngay sang chế độ xem dữ liệu của thành viên này trong tab Tổng quan.", en: "Jump straight into this member's data in Overview.", ja: "概要タブでこのメンバーのデータへすぐ移動します。") }
                    static func subtitle(language: MistiaAppLanguage) -> String { L10n.tr("settings.shortcut.option.memberOverview.subtitle", vi: "Chuyển ngay sang chế độ xem dữ liệu của thành viên này trong tab Tổng quan.", en: "Jump straight into this member's data in Overview.", ja: "概要タブでこのメンバーのデータへすぐ移動します。", language: language) }
                }

                nonisolated enum receiptScan {
                    static var accessibility: String { L10n.tr("settings.shortcut.option.receiptScan.accessibility", vi: "Mở quét bill", en: "Open receipt scan", ja: "レシート読取を開く") }
                    static func accessibility(language: MistiaAppLanguage) -> String { L10n.tr("settings.shortcut.option.receiptScan.accessibility", vi: "Mở quét bill", en: "Open receipt scan", ja: "レシート読取を開く", language: language) }
                    static var subtitle: String { L10n.tr("settings.shortcut.option.receiptScan.subtitle", vi: "Mở camera chụp bill ngay để AI điền thu chi.", en: "Open the camera immediately so AI can fill the cashflow item.", ja: "カメラをすぐ開き、AIで取引を入力します。") }
                    static func subtitle(language: MistiaAppLanguage) -> String { L10n.tr("settings.shortcut.option.receiptScan.subtitle", vi: "Mở camera chụp bill ngay để AI điền thu chi.", en: "Open the camera immediately so AI can fill the cashflow item.", ja: "カメラをすぐ開き、AIで取引を入力します。", language: language) }
                    static var title: String { L10n.tr("settings.shortcut.option.receiptScan.title", vi: "Quét bill", en: "Scan receipt", ja: "レシート読取") }
                    static func title(language: MistiaAppLanguage) -> String { L10n.tr("settings.shortcut.option.receiptScan.title", vi: "Quét bill", en: "Scan receipt", ja: "レシート読取", language: language) }
                }

                nonisolated enum syncNow {
                    static var accessibility: String { L10n.tr("settings.shortcut.option.syncNow.accessibility", vi: "Đồng bộ ngay", en: "Sync now", ja: "今すぐ同期") }
                    static func accessibility(language: MistiaAppLanguage) -> String { L10n.tr("settings.shortcut.option.syncNow.accessibility", vi: "Đồng bộ ngay", en: "Sync now", ja: "今すぐ同期", language: language) }
                    static var subtitle: String { L10n.tr("settings.shortcut.option.syncNow.subtitle", vi: "Đồng bộ dữ liệu ngay lập tức với cloud.", en: "Sync data immediately with cloud.", ja: "すぐにクラウドとデータを同期します。") }
                    static func subtitle(language: MistiaAppLanguage) -> String { L10n.tr("settings.shortcut.option.syncNow.subtitle", vi: "Đồng bộ dữ liệu ngay lập tức với cloud.", en: "Sync data immediately with cloud.", ja: "すぐにクラウドとデータを同期します。", language: language) }
                    static var title: String { L10n.tr("settings.shortcut.option.syncNow.title", vi: "Đồng bộ ngay", en: "Sync now", ja: "今すぐ同期") }
                    static func title(language: MistiaAppLanguage) -> String { L10n.tr("settings.shortcut.option.syncNow.title", vi: "Đồng bộ ngay", en: "Sync now", ja: "今すぐ同期", language: language) }
                }
            }
            static var personalUtilitiesSection: String { L10n.tr("settings.shortcut.personalUtilitiesSection", vi: "Tiện ích cá nhân", en: "Personal utilities", ja: "個人ユーティリティ") }
            static func personalUtilitiesSection(language: MistiaAppLanguage) -> String { L10n.tr("settings.shortcut.personalUtilitiesSection", vi: "Tiện ích cá nhân", en: "Personal utilities", ja: "個人ユーティリティ", language: language) }
            static var title: String { L10n.tr("settings.shortcut.title", vi: "Lối tắt Mistia", en: "Mistia shortcut", ja: "ショートカット") }
            static func title(language: MistiaAppLanguage) -> String { L10n.tr("settings.shortcut.title", vi: "Lối tắt Mistia", en: "Mistia shortcut", ja: "ショートカット", language: language) }
        }
        static var title: String { L10n.tr("settings.title", vi: "Cài đặt", en: "Settings", ja: "設定") }
        static func title(language: MistiaAppLanguage) -> String { L10n.tr("settings.title", vi: "Cài đặt", en: "Settings", ja: "設定", language: language) }
    }

    nonisolated enum shared {

        nonisolated enum amountCalculator {
            static var divisionByZero: String { L10n.tr("shared.amountCalculator.divisionByZero", vi: "Không thể chia cho 0", en: "Cannot divide by 0", ja: "0で割ることはできません") }
            static func divisionByZero(language: MistiaAppLanguage) -> String { L10n.tr("shared.amountCalculator.divisionByZero", vi: "Không thể chia cho 0", en: "Cannot divide by 0", ja: "0で割ることはできません", language: language) }
            static var expression: String { L10n.tr("shared.amountCalculator.expression", vi: "Phép tính", en: "Expression", ja: "計算式") }
            static func expression(language: MistiaAppLanguage) -> String { L10n.tr("shared.amountCalculator.expression", vi: "Phép tính", en: "Expression", ja: "計算式", language: language) }
            static var integerPositiveRequired: String { L10n.tr("shared.amountCalculator.integerPositiveRequired", vi: "Kết quả phải là số nguyên dương", en: "Result must be a positive integer", ja: "結果は正の整数にしてください") }
            static func integerPositiveRequired(language: MistiaAppLanguage) -> String { L10n.tr("shared.amountCalculator.integerPositiveRequired", vi: "Kết quả phải là số nguyên dương", en: "Result must be a positive integer", ja: "結果は正の整数にしてください", language: language) }
            static var openCalculator: String { L10n.tr("shared.amountCalculator.openCalculator", vi: "Mở máy tính nhanh", en: "Open quick calculator", ja: "クイック計算機を開く") }
            static func openCalculator(language: MistiaAppLanguage) -> String { L10n.tr("shared.amountCalculator.openCalculator", vi: "Mở máy tính nhanh", en: "Open quick calculator", ja: "クイック計算機を開く", language: language) }
            static var result: String { L10n.tr("shared.amountCalculator.result", vi: "Kết quả", en: "Result", ja: "結果") }
            static func result(language: MistiaAppLanguage) -> String { L10n.tr("shared.amountCalculator.result", vi: "Kết quả", en: "Result", ja: "結果", language: language) }
            static var resultTooLarge: String { L10n.tr("shared.amountCalculator.resultTooLarge", vi: "Kết quả quá lớn", en: "Result is too large", ja: "結果が大きすぎます") }
            static func resultTooLarge(language: MistiaAppLanguage) -> String { L10n.tr("shared.amountCalculator.resultTooLarge", vi: "Kết quả quá lớn", en: "Result is too large", ja: "結果が大きすぎます", language: language) }
            static var title: String { L10n.tr("shared.amountCalculator.title", vi: "Máy tính", en: "Calculator", ja: "計算機") }
            static func title(language: MistiaAppLanguage) -> String { L10n.tr("shared.amountCalculator.title", vi: "Máy tính", en: "Calculator", ja: "計算機", language: language) }
        }

        nonisolated enum appLock {
            static var biometricReason: String { L10n.tr("shared.appLock.biometricReason", vi: "Mở khóa Mistia", en: "Unlock Mistia", ja: "Mistiaをロック解除") }
            static func biometricReason(language: MistiaAppLanguage) -> String { L10n.tr("shared.appLock.biometricReason", vi: "Mở khóa Mistia", en: "Unlock Mistia", ja: "Mistiaをロック解除", language: language) }
            static var codeMismatch: String { L10n.tr("shared.appLock.codeMismatch", vi: "Mã xác nhận chưa khớp.", en: "The confirmation code does not match.", ja: "確認コードが一致しません。") }
            static func codeMismatch(language: MistiaAppLanguage) -> String { L10n.tr("shared.appLock.codeMismatch", vi: "Mã xác nhận chưa khớp.", en: "The confirmation code does not match.", ja: "確認コードが一致しません。", language: language) }
            static var confirmPassword: String { L10n.tr("shared.appLock.confirmPassword", vi: "Nhập lại mật khẩu", en: "Confirm password", ja: "パスワードを確認") }
            static func confirmPassword(language: MistiaAppLanguage) -> String { L10n.tr("shared.appLock.confirmPassword", vi: "Nhập lại mật khẩu", en: "Confirm password", ja: "パスワードを確認", language: language) }
            static var confirmPasswordPlaceholder: String { L10n.tr("shared.appLock.confirmPasswordPlaceholder", vi: "Nhập lại mật khẩu", en: "Confirm password", ja: "パスワードを再入力") }
            static func confirmPasswordPlaceholder(language: MistiaAppLanguage) -> String { L10n.tr("shared.appLock.confirmPasswordPlaceholder", vi: "Nhập lại mật khẩu", en: "Confirm password", ja: "パスワードを再入力", language: language) }
            static var confirmPin: String { L10n.tr("shared.appLock.confirmPin", vi: "Nhập lại PIN", en: "Confirm PIN", ja: "PINを確認") }
            static func confirmPin(language: MistiaAppLanguage) -> String { L10n.tr("shared.appLock.confirmPin", vi: "Nhập lại PIN", en: "Confirm PIN", ja: "PINを確認", language: language) }
            static var continueButton: String { L10n.tr("shared.appLock.continueButton", vi: "Tiếp tục", en: "Continue", ja: "続ける") }
            static func continueButton(language: MistiaAppLanguage) -> String { L10n.tr("shared.appLock.continueButton", vi: "Tiếp tục", en: "Continue", ja: "続ける", language: language) }
            static var enterCurrentCodeTitle: String { L10n.tr("shared.appLock.enterCurrentCodeTitle", vi: "Nhập mã khóa", en: "Enter app code", ja: "アプリコードを入力") }
            static func enterCurrentCodeTitle(language: MistiaAppLanguage) -> String { L10n.tr("shared.appLock.enterCurrentCodeTitle", vi: "Nhập mã khóa", en: "Enter app code", ja: "アプリコードを入力", language: language) }
            static var optionPassword: String { L10n.tr("shared.appLock.optionPassword", vi: "Mật khẩu", en: "Password", ja: "パスワード") }
            static func optionPassword(language: MistiaAppLanguage) -> String { L10n.tr("shared.appLock.optionPassword", vi: "Mật khẩu", en: "Password", ja: "パスワード", language: language) }
            static var optionPin4: String { L10n.tr("shared.appLock.optionPin4", vi: "PIN 4", en: "PIN 4", ja: "PIN 4") }
            static func optionPin4(language: MistiaAppLanguage) -> String { L10n.tr("shared.appLock.optionPin4", vi: "PIN 4", en: "PIN 4", ja: "PIN 4", language: language) }
            static var optionPin6: String { L10n.tr("shared.appLock.optionPin6", vi: "PIN 6", en: "PIN 6", ja: "PIN 6") }
            static func optionPin6(language: MistiaAppLanguage) -> String { L10n.tr("shared.appLock.optionPin6", vi: "PIN 6", en: "PIN 6", ja: "PIN 6", language: language) }
            static var passwordHelper: String { L10n.tr("shared.appLock.passwordHelper", vi: "Dài hơn 6 ký tự, có chữ hoa, chữ thường và số.", en: "Use more than 6 characters with uppercase, lowercase, and a number.", ja: "6文字より長くし、大文字・小文字・数字を含めてください。") }
            static func passwordHelper(language: MistiaAppLanguage) -> String { L10n.tr("shared.appLock.passwordHelper", vi: "Dài hơn 6 ký tự, có chữ hoa, chữ thường và số.", en: "Use more than 6 characters with uppercase, lowercase, and a number.", ja: "6文字より長くし、大文字・小文字・数字を含めてください。", language: language) }
            static var passwordMissingDigitValidation: String { L10n.tr("shared.appLock.passwordMissingDigitValidation", vi: "Mật khẩu cần có ít nhất 1 số.", en: "Password needs at least one number.", ja: "パスワードには数字を1文字以上含めてください。") }
            static func passwordMissingDigitValidation(language: MistiaAppLanguage) -> String { L10n.tr("shared.appLock.passwordMissingDigitValidation", vi: "Mật khẩu cần có ít nhất 1 số.", en: "Password needs at least one number.", ja: "パスワードには数字を1文字以上含めてください。", language: language) }
            static var passwordMissingLetterValidation: String { L10n.tr("shared.appLock.passwordMissingLetterValidation", vi: "Mật khẩu cần có chữ cái.", en: "Password needs at least one letter.", ja: "パスワードには文字を1文字以上含めてください。") }
            static func passwordMissingLetterValidation(language: MistiaAppLanguage) -> String { L10n.tr("shared.appLock.passwordMissingLetterValidation", vi: "Mật khẩu cần có chữ cái.", en: "Password needs at least one letter.", ja: "パスワードには文字を1文字以上含めてください。", language: language) }
            static var passwordMissingLowercaseValidation: String { L10n.tr("shared.appLock.passwordMissingLowercaseValidation", vi: "Mật khẩu cần có ít nhất 1 chữ viết thường.", en: "Password needs at least one lowercase letter.", ja: "パスワードには小文字を1文字以上含めてください。") }
            static func passwordMissingLowercaseValidation(language: MistiaAppLanguage) -> String { L10n.tr("shared.appLock.passwordMissingLowercaseValidation", vi: "Mật khẩu cần có ít nhất 1 chữ viết thường.", en: "Password needs at least one lowercase letter.", ja: "パスワードには小文字を1文字以上含めてください。", language: language) }
            static var passwordMissingUppercaseValidation: String { L10n.tr("shared.appLock.passwordMissingUppercaseValidation", vi: "Mật khẩu cần có ít nhất 1 chữ viết hoa.", en: "Password needs at least one uppercase letter.", ja: "パスワードには大文字を1文字以上含めてください。") }
            static func passwordMissingUppercaseValidation(language: MistiaAppLanguage) -> String { L10n.tr("shared.appLock.passwordMissingUppercaseValidation", vi: "Mật khẩu cần có ít nhất 1 chữ viết hoa.", en: "Password needs at least one uppercase letter.", ja: "パスワードには大文字を1文字以上含めてください。", language: language) }
            static var passwordPlaceholder: String { L10n.tr("shared.appLock.passwordPlaceholder", vi: "Mật khẩu", en: "Password", ja: "パスワード") }
            static func passwordPlaceholder(language: MistiaAppLanguage) -> String { L10n.tr("shared.appLock.passwordPlaceholder", vi: "Mật khẩu", en: "Password", ja: "パスワード", language: language) }
            static var passwordValidation: String { L10n.tr("shared.appLock.passwordValidation", vi: "Mật khẩu cần dài hơn 6 ký tự.", en: "Password must be longer than 6 characters.", ja: "パスワードは6文字より長くしてください。") }
            static func passwordValidation(language: MistiaAppLanguage) -> String { L10n.tr("shared.appLock.passwordValidation", vi: "Mật khẩu cần dài hơn 6 ký tự.", en: "Password must be longer than 6 characters.", ja: "パスワードは6文字より長くしてください。", language: language) }
            static var pin4Validation: String { L10n.tr("shared.appLock.pin4Validation", vi: "PIN cần đủ 4 số.", en: "PIN must be exactly 4 digits.", ja: "PINは4桁の数字にしてください。") }
            static func pin4Validation(language: MistiaAppLanguage) -> String { L10n.tr("shared.appLock.pin4Validation", vi: "PIN cần đủ 4 số.", en: "PIN must be exactly 4 digits.", ja: "PINは4桁の数字にしてください。", language: language) }
            static var pin6Validation: String { L10n.tr("shared.appLock.pin6Validation", vi: "PIN cần đủ 6 số.", en: "PIN must be exactly 6 digits.", ja: "PINは6桁の数字にしてください。") }
            static func pin6Validation(language: MistiaAppLanguage) -> String { L10n.tr("shared.appLock.pin6Validation", vi: "PIN cần đủ 6 số.", en: "PIN must be exactly 6 digits.", ja: "PINは6桁の数字にしてください。", language: language) }
            static var retryBiometric: String { L10n.tr("shared.appLock.retryBiometric", vi: "Thử lại", en: "Try again", ja: "もう一度試す") }
            static func retryBiometric(language: MistiaAppLanguage) -> String { L10n.tr("shared.appLock.retryBiometric", vi: "Thử lại", en: "Try again", ja: "もう一度試す", language: language) }
            static var setupCodeSubtitle: String { L10n.tr("shared.appLock.setupCodeSubtitle", vi: "Chọn PIN hoặc mật khẩu để mở khóa Mistia.", en: "Choose a PIN or password to unlock Mistia.", ja: "Mistiaのロック解除に使うPINまたはパスワードを選択します。") }
            static func setupCodeSubtitle(language: MistiaAppLanguage) -> String { L10n.tr("shared.appLock.setupCodeSubtitle", vi: "Chọn PIN hoặc mật khẩu để mở khóa Mistia.", en: "Choose a PIN or password to unlock Mistia.", ja: "Mistiaのロック解除に使うPINまたはパスワードを選択します。", language: language) }
            static var setupCodeTitle: String { L10n.tr("shared.appLock.setupCodeTitle", vi: "Thiết lập mã khóa", en: "Set app code", ja: "アプリコードを設定") }
            static func setupCodeTitle(language: MistiaAppLanguage) -> String { L10n.tr("shared.appLock.setupCodeTitle", vi: "Thiết lập mã khóa", en: "Set app code", ja: "アプリコードを設定", language: language) }
            static var title: String { L10n.tr("shared.appLock.title", vi: "Mistia bị khóa", en: "Mistia is locked", ja: "Mistiaはロックされています") }
            static func title(language: MistiaAppLanguage) -> String { L10n.tr("shared.appLock.title", vi: "Mistia bị khóa", en: "Mistia is locked", ja: "Mistiaはロックされています", language: language) }
            static func tryAgainInMinutes(_ value: String) -> String {
                L10n.format("shared.appLock.tryAgainInMinutes", vi: "Thử lại sau %@ phút", en: "Try again in %@ min", ja: "%@分後に再試行", value)
            }
            static func tryAgainInMinutes(_ value: String, language: MistiaAppLanguage) -> String {
                L10n.format("shared.appLock.tryAgainInMinutes", vi: "Thử lại sau %@ phút", en: "Try again in %@ min", ja: "%@分後に再試行", language: language, value)
            }
            static func tryAgainInSeconds(_ value: String) -> String {
                L10n.format("shared.appLock.tryAgainInSeconds", vi: "Thử lại sau %@ giây", en: "Try again in %@ seconds", ja: "%@秒後に再試行", value)
            }
            static func tryAgainInSeconds(_ value: String, language: MistiaAppLanguage) -> String {
                L10n.format("shared.appLock.tryAgainInSeconds", vi: "Thử lại sau %@ giây", en: "Try again in %@ seconds", ja: "%@秒後に再試行", language: language, value)
            }
            static var unlock: String { L10n.tr("shared.appLock.unlock", vi: "Mở khóa", en: "Unlock", ja: "ロック解除") }
            static func unlock(language: MistiaAppLanguage) -> String { L10n.tr("shared.appLock.unlock", vi: "Mở khóa", en: "Unlock", ja: "ロック解除", language: language) }
            static var useAppCode: String { L10n.tr("shared.appLock.useAppCode", vi: "Mã khóa", en: "App code", ja: "アプリコード") }
            static func useAppCode(language: MistiaAppLanguage) -> String { L10n.tr("shared.appLock.useAppCode", vi: "Mã khóa", en: "App code", ja: "アプリコード", language: language) }
            static var wrongCode: String { L10n.tr("shared.appLock.wrongCode", vi: "Mã chưa đúng.", en: "Incorrect code.", ja: "コードが正しくありません。") }
            static func wrongCode(language: MistiaAppLanguage) -> String { L10n.tr("shared.appLock.wrongCode", vi: "Mã chưa đúng.", en: "Incorrect code.", ja: "コードが正しくありません。", language: language) }
        }

        nonisolated enum corelogic {

            nonisolated enum financeenums {
                static var all: String { L10n.tr("shared.corelogic.financeenums.all", vi: "Tất cả", en: "All", ja: "すべて") }
                static func all(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.financeenums.all", vi: "Tất cả", en: "All", ja: "すべて", language: language) }
                static var bank: String { L10n.tr("shared.corelogic.financeenums.bank", vi: "Ngân hàng", en: "Bank", ja: "銀行") }
                static func bank(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.financeenums.bank", vi: "Ngân hàng", en: "Bank", ja: "銀行", language: language) }
                static var borrow: String { L10n.tr("shared.corelogic.financeenums.borrow", vi: "Nợ phải trả", en: "Payable", ja: "未払金") }
                static func borrow(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.financeenums.borrow", vi: "Nợ phải trả", en: "Payable", ja: "未払金", language: language) }
                static var cash: String { L10n.tr("shared.corelogic.financeenums.cash", vi: "Tiền mặt", en: "Cash", ja: "現金") }
                static func cash(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.financeenums.cash", vi: "Tiền mặt", en: "Cash", ja: "現金", language: language) }
                static var childCategory: String { L10n.tr("shared.corelogic.financeenums.childCategory", vi: "Danh mục con", en: "Child category", ja: "子カテゴリ") }
                static func childCategory(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.financeenums.childCategory", vi: "Danh mục con", en: "Child category", ja: "子カテゴリ", language: language) }
                static var collectDebt: String { L10n.tr("shared.corelogic.financeenums.collectDebt", vi: "Thu nợ", en: "Collect debt", ja: "回収") }
                static func collectDebt(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.financeenums.collectDebt", vi: "Thu nợ", en: "Collect debt", ja: "回収", language: language) }
                static var creditCard: String { L10n.tr("shared.corelogic.financeenums.creditCard", vi: "Credit card", en: "Credit card", ja: "クレジットカード") }
                static func creditCard(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.financeenums.creditCard", vi: "Credit card", en: "Credit card", ja: "クレジットカード", language: language) }
                static var cryptoDigitalAssets: String { L10n.tr("shared.corelogic.financeenums.cryptoDigitalAssets", vi: "Tiền ảo / Crypto", en: "Crypto / Digital Assets", ja: "仮想通貨 / クリプト") }
                static func cryptoDigitalAssets(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.financeenums.cryptoDigitalAssets", vi: "Tiền ảo / Crypto", en: "Crypto / Digital Assets", ja: "仮想通貨 / クリプト", language: language) }
                static var currentDebt: String { L10n.tr("shared.corelogic.financeenums.currentDebt", vi: "Dư nợ hiện tại", en: "Current debt", ja: "現在の利用残高") }
                static func currentDebt(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.financeenums.currentDebt", vi: "Dư nợ hiện tại", en: "Current debt", ja: "現在の利用残高", language: language) }
                static var debt: String { L10n.tr("shared.corelogic.financeenums.debt", vi: "Vay & cho vay", en: "Loans", ja: "貸し借り") }
                static func debt(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.financeenums.debt", vi: "Vay & cho vay", en: "Loans", ja: "貸し借り", language: language) }
                static var draft: String { L10n.tr("shared.corelogic.financeenums.draft", vi: "Bản nháp", en: "Draft", ja: "下書き") }
                static func draft(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.financeenums.draft", vi: "Bản nháp", en: "Draft", ja: "下書き", language: language) }
                static var eWalletBarcode: String { L10n.tr("shared.corelogic.financeenums.eWalletBarcode", vi: "Ví điện tử / Barcode", en: "E-Wallet / Barcode", ja: "電子マネー / バーコード決済") }
                static func eWalletBarcode(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.financeenums.eWalletBarcode", vi: "Ví điện tử / Barcode", en: "E-Wallet / Barcode", ja: "電子マネー / バーコード決済", language: language) }
                static var expense: String { L10n.tr("shared.corelogic.financeenums.expense", vi: "Chi tiêu", en: "Expense", ja: "支出") }
                static func expense(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.financeenums.expense", vi: "Chi tiêu", en: "Expense", ja: "支出", language: language) }
                static var family: String { L10n.tr("shared.corelogic.financeenums.family", vi: "Gia đình", en: "Family", ja: "家族") }
                static func family(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.financeenums.family", vi: "Gia đình", en: "Family", ja: "家族", language: language) }
                static var finance: String { L10n.tr("shared.corelogic.financeenums.finance", vi: "Tài chính", en: "Finance", ja: "金融") }
                static func finance(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.financeenums.finance", vi: "Tài chính", en: "Finance", ja: "金融", language: language) }
                static var food: String { L10n.tr("shared.corelogic.financeenums.food", vi: "Ăn uống", en: "Food", ja: "食事") }
                static func food(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.financeenums.food", vi: "Ăn uống", en: "Food", ja: "食事", language: language) }
                static var health: String { L10n.tr("shared.corelogic.financeenums.health", vi: "Sức khỏe", en: "Health", ja: "健康") }
                static func health(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.financeenums.health", vi: "Sức khỏe", en: "Health", ja: "健康", language: language) }
                static var home: String { L10n.tr("shared.corelogic.financeenums.home", vi: "Nhà ở", en: "Home", ja: "住まい") }
                static func home(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.financeenums.home", vi: "Nhà ở", en: "Home", ja: "住まい", language: language) }
                static var income: String { L10n.tr("shared.corelogic.financeenums.income", vi: "Thu nhập", en: "Income", ja: "収入") }
                static func income(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.financeenums.income", vi: "Thu nhập", en: "Income", ja: "収入", language: language) }
                static var `internal`: String { L10n.tr("shared.corelogic.financeenums.internal", vi: "Nội bộ", en: "Internal", ja: "内部") }
                static func `internal`(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.financeenums.internal", vi: "Nội bộ", en: "Internal", ja: "内部", language: language) }
                static var investmentStocks: String { L10n.tr("shared.corelogic.financeenums.investmentStocks", vi: "Đầu tư / Chứng khoán", en: "Investment / Stocks", ja: "投資 / 証券") }
                static func investmentStocks(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.financeenums.investmentStocks", vi: "Đầu tư / Chứng khoán", en: "Investment / Stocks", ja: "投資 / 証券", language: language) }
                static var leisure: String { L10n.tr("shared.corelogic.financeenums.leisure", vi: "Giải trí", en: "Leisure", ja: "娯楽") }
                static func leisure(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.financeenums.leisure", vi: "Giải trí", en: "Leisure", ja: "娯楽", language: language) }
                static var lend: String { L10n.tr("shared.corelogic.financeenums.lend", vi: "Cho vay", en: "Lend", ja: "貸す") }
                static func lend(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.financeenums.lend", vi: "Cho vay", en: "Lend", ja: "貸す", language: language) }
                static var mobility: String { L10n.tr("shared.corelogic.financeenums.mobility", vi: "Đi lại", en: "Mobility", ja: "移動") }
                static func mobility(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.financeenums.mobility", vi: "Đi lại", en: "Mobility", ja: "移動", language: language) }
                static var openingBalance: String { L10n.tr("shared.corelogic.financeenums.openingBalance", vi: "Số dư ban đầu", en: "Opening balance", ja: "初期残高") }
                static func openingBalance(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.financeenums.openingBalance", vi: "Số dư ban đầu", en: "Opening balance", ja: "初期残高", language: language) }
                static var other: String { L10n.tr("shared.corelogic.financeenums.other", vi: "Khác", en: "Other", ja: "その他") }
                static func other(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.financeenums.other", vi: "Khác", en: "Other", ja: "その他", language: language) }
                static var other2: String { L10n.tr("shared.corelogic.financeenums.other2", vi: "Khác", en: "Other", ja: "その他") }
                static func other2(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.financeenums.other2", vi: "Khác", en: "Other", ja: "その他", language: language) }
                static var otherWallet: String { L10n.tr("shared.corelogic.financeenums.otherWallet", vi: "Loại ví khác", en: "Other wallet", ja: "その他のウォレット") }
                static func otherWallet(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.financeenums.otherWallet", vi: "Loại ví khác", en: "Other wallet", ja: "その他のウォレット", language: language) }
                static var parentCategory: String { L10n.tr("shared.corelogic.financeenums.parentCategory", vi: "Danh mục cha", en: "Parent category", ja: "親カテゴリ") }
                static func parentCategory(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.financeenums.parentCategory", vi: "Danh mục cha", en: "Parent category", ja: "親カテゴリ", language: language) }
                static var personal: String { L10n.tr("shared.corelogic.financeenums.personal", vi: "Cá nhân", en: "Personal", ja: "個人") }
                static func personal(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.financeenums.personal", vi: "Cá nhân", en: "Personal", ja: "個人", language: language) }
                static var planning: String { L10n.tr("shared.corelogic.financeenums.planning", vi: "Sắp tới", en: "Upcoming", ja: "予定") }
                static func planning(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.financeenums.planning", vi: "Sắp tới", en: "Upcoming", ja: "予定", language: language) }
                static var prepaidICCard: String { L10n.tr("shared.corelogic.financeenums.prepaidICCard", vi: "Thẻ trả trước / IC", en: "Prepaid / IC Card", ja: "プリペイド / ICカード") }
                static func prepaidICCard(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.financeenums.prepaidICCard", vi: "Thẻ trả trước / IC", en: "Prepaid / IC Card", ja: "プリペイド / ICカード", language: language) }
                static var recorded: String { L10n.tr("shared.corelogic.financeenums.recorded", vi: "Đã ghi nhận", en: "Recorded", ja: "記録済み") }
                static func recorded(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.financeenums.recorded", vi: "Đã ghi nhận", en: "Recorded", ja: "記録済み", language: language) }
                static var repay: String { L10n.tr("shared.corelogic.financeenums.repay", vi: "Trả nợ", en: "Repay", ja: "返済") }
                static func repay(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.financeenums.repay", vi: "Trả nợ", en: "Repay", ja: "返済", language: language) }
                static var thisMonth: String { L10n.tr("shared.corelogic.financeenums.thisMonth", vi: "Tháng này", en: "This month", ja: "今月") }
                static func thisMonth(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.financeenums.thisMonth", vi: "Tháng này", en: "This month", ja: "今月", language: language) }
                static var today: String { L10n.tr("shared.corelogic.financeenums.today", vi: "Hôm nay", en: "Today", ja: "今日") }
                static func today(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.financeenums.today", vi: "Hôm nay", en: "Today", ja: "今日", language: language) }
                static var transfer: String { L10n.tr("shared.corelogic.financeenums.transfer", vi: "Chuyển tiền", en: "Transfer", ja: "振替") }
                static func transfer(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.financeenums.transfer", vi: "Chuyển tiền", en: "Transfer", ja: "振替", language: language) }
                static var wallets: String { L10n.tr("shared.corelogic.financeenums.wallets", vi: "Ví", en: "Wallets", ja: "ウォレット") }
                static func wallets(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.financeenums.wallets", vi: "Ví", en: "Wallets", ja: "ウォレット", language: language) }
                static var work: String { L10n.tr("shared.corelogic.financeenums.work", vi: "Công việc", en: "Work", ja: "仕事") }
                static func work(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.financeenums.work", vi: "Công việc", en: "Work", ja: "仕事", language: language) }
                static var yesterday: String { L10n.tr("shared.corelogic.financeenums.yesterday", vi: "Hôm qua", en: "Yesterday", ja: "昨日") }
                static func yesterday(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.financeenums.yesterday", vi: "Hôm qua", en: "Yesterday", ja: "昨日", language: language) }
            }

            nonisolated enum mistialocalization {
                static var daysAgo: String { L10n.tr("shared.corelogic.mistialocalization.daysAgo", vi: "Hôm kia", en: "2 days ago", ja: "一昨日") }
                static func daysAgo(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.mistialocalization.daysAgo", vi: "Hôm kia", en: "2 days ago", ja: "一昨日", language: language) }
                static func thisWeekValue(_ value: String) -> String {
                    L10n.format("shared.corelogic.mistialocalization.thisWeekValue", vi: "Tuần này • %@", en: "This week • %@", ja: "今週 • %@", value)
                }
                static func thisWeekValue(_ value: String, language: MistiaAppLanguage) -> String {
                    L10n.format("shared.corelogic.mistialocalization.thisWeekValue", vi: "Tuần này • %@", en: "This week • %@", ja: "今週 • %@", language: language, value)
                }
                static var today: String { L10n.tr("shared.corelogic.mistialocalization.today", vi: "Hôm nay", en: "Today", ja: "今日") }
                static func today(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.mistialocalization.today", vi: "Hôm nay", en: "Today", ja: "今日", language: language) }
                static func valueHrAgo(_ value: String) -> String {
                    L10n.format("shared.corelogic.mistialocalization.valueHrAgo", vi: "%@ tiếng trước", en: "%@ hr ago", ja: "%@時間前", value)
                }
                static func valueHrAgo(_ value: String, language: MistiaAppLanguage) -> String {
                    L10n.format("shared.corelogic.mistialocalization.valueHrAgo", vi: "%@ tiếng trước", en: "%@ hr ago", ja: "%@時間前", language: language, value)
                }
                static func valueMinAgo(_ value: String) -> String {
                    L10n.format("shared.corelogic.mistialocalization.valueMinAgo", vi: "%@ phút trước", en: "%@ min ago", ja: "%@分前", value)
                }
                static func valueMinAgo(_ value: String, language: MistiaAppLanguage) -> String {
                    L10n.format("shared.corelogic.mistialocalization.valueMinAgo", vi: "%@ phút trước", en: "%@ min ago", ja: "%@分前", language: language, value)
                }
                static var yesterday: String { L10n.tr("shared.corelogic.mistialocalization.yesterday", vi: "Hôm qua", en: "Yesterday", ja: "昨日") }
                static func yesterday(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.mistialocalization.yesterday", vi: "Hôm qua", en: "Yesterday", ja: "昨日", language: language) }
            }

            nonisolated enum overview {
                static var debt: String { L10n.tr("shared.corelogic.overview.debt", vi: "Vay & cho vay", en: "Loans", ja: "貸し借り") }
                static func debt(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.overview.debt", vi: "Vay & cho vay", en: "Loans", ja: "貸し借り", language: language) }
                static var expense: String { L10n.tr("shared.corelogic.overview.expense", vi: "Chi tiêu", en: "Expense", ja: "支出") }
                static func expense(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.overview.expense", vi: "Chi tiêu", en: "Expense", ja: "支出", language: language) }
                static var income: String { L10n.tr("shared.corelogic.overview.income", vi: "Thu nhập", en: "Income", ja: "収入") }
                static func income(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.overview.income", vi: "Thu nhập", en: "Income", ja: "収入", language: language) }
                static var internalTransfer: String { L10n.tr("shared.corelogic.overview.internalTransfer", vi: "Chuyển tiền nội bộ", en: "Internal transfer", ja: "内部振替") }
                static func internalTransfer(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.overview.internalTransfer", vi: "Chuyển tiền nội bộ", en: "Internal transfer", ja: "内部振替", language: language) }
                static var transfer: String { L10n.tr("shared.corelogic.overview.transfer", vi: "Chuyển tiền", en: "Transfer", ja: "振替") }
                static func transfer(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.overview.transfer", vi: "Chuyển tiền", en: "Transfer", ja: "振替", language: language) }
                static var uncategorized: String { L10n.tr("shared.corelogic.overview.uncategorized", vi: "Chưa phân loại", en: "Uncategorized", ja: "未分類") }
                static func uncategorized(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.overview.uncategorized", vi: "Chưa phân loại", en: "Uncategorized", ja: "未分類", language: language) }
            }

            nonisolated enum planning {
                static var chooseAPaymentWalletBeforeContinuing: String { L10n.tr("shared.corelogic.planning.chooseAPaymentWalletBeforeContinuing", vi: "Chọn ví thanh toán trước khi tiếp tục.", en: "Choose a payment wallet before continuing.", ja: "続行する前に支払いウォレットを選択してください。") }
                static func chooseAPaymentWalletBeforeContinuing(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.planning.chooseAPaymentWalletBeforeContinuing", vi: "Chọn ví thanh toán trước khi tiếp tục.", en: "Choose a payment wallet before continuing.", ja: "続行する前に支払いウォレットを選択してください。", language: language) }
                static var enterAPaymentAmountBeforeContinuing: String { L10n.tr("shared.corelogic.planning.enterAPaymentAmountBeforeContinuing", vi: "Nhập số tiền thanh toán trước khi tiếp tục.", en: "Enter a payment amount before continuing.", ja: "続行する前に支払い金額を入力してください。") }
                static func enterAPaymentAmountBeforeContinuing(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.planning.enterAPaymentAmountBeforeContinuing", vi: "Nhập số tiền thanh toán trước khi tiếp tục.", en: "Enter a payment amount before continuing.", ja: "続行する前に支払い金額を入力してください。", language: language) }
                static var exceeded: String { L10n.tr("shared.corelogic.planning.exceeded", vi: "Vượt dự chi", en: "Over planned amount", ja: "超過") }
                static func exceeded(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.planning.exceeded", vi: "Vượt dự chi", en: "Over planned amount", ja: "超過", language: language) }
                static var needsAttention: String { L10n.tr("shared.corelogic.planning.needsAttention", vi: "Cần chú ý", en: "Needs attention", ja: "注意") }
                static func needsAttention(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.planning.needsAttention", vi: "Cần chú ý", en: "Needs attention", ja: "注意", language: language) }
                static var stable: String { L10n.tr("shared.corelogic.planning.stable", vi: "Ổn định", en: "Stable", ja: "安定") }
                static func stable(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.planning.stable", vi: "Ổn định", en: "Stable", ja: "安定", language: language) }
                static var theDestinationWalletForThisPaymentCould: String { L10n.tr("shared.corelogic.planning.theDestinationWalletForThisPaymentCould", vi: "Không tìm thấy ví đích cho khoản thanh toán này.", en: "The destination wallet for this payment could not be found.", ja: "この支払いの振替先ウォレットが見つかりません。") }
                static func theDestinationWalletForThisPaymentCould(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.planning.theDestinationWalletForThisPaymentCould", vi: "Không tìm thấy ví đích cho khoản thanh toán này.", en: "The destination wallet for this payment could not be found.", ja: "この支払いの振替先ウォレットが見つかりません。", language: language) }
            }

            nonisolated enum transaction {
                static var needsCompletion: String { L10n.tr("shared.corelogic.transaction.needsCompletion", vi: "Cần hoàn thiện", en: "Needs completion", ja: "要確認") }
                static func needsCompletion(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.transaction.needsCompletion", vi: "Cần hoàn thiện", en: "Needs completion", ja: "要確認", language: language) }
                static var unknownName: String { L10n.tr("shared.corelogic.transaction.unknownName", vi: "Không rõ tên", en: "Unknown name", ja: "名前未設定") }
                static func unknownName(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.transaction.unknownName", vi: "Không rõ tên", en: "Unknown name", ja: "名前未設定", language: language) }
            }

            nonisolated enum transactionlogicstatement {
                static var aSummaryOfActiveCardsInMistia: String { L10n.tr("shared.corelogic.transactionlogicstatement.aSummaryOfActiveCardsInMistia", vi: "Bản tổng hợp cho các thẻ đang hoạt động trong Mistia.", en: "A summary of active cards in Mistia.", ja: "ミスティアで利用中のカードをまとめた明細です。") }
                static func aSummaryOfActiveCardsInMistia(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.transactionlogicstatement.aSummaryOfActiveCardsInMistia", vi: "Bản tổng hợp cho các thẻ đang hoạt động trong Mistia.", en: "A summary of active cards in Mistia.", ja: "ミスティアで利用中のカードをまとめた明細です。", language: language) }
                static var aSummaryOfAssetsCashflowAndTransactions: String { L10n.tr("shared.corelogic.transactionlogicstatement.aSummaryOfAssetsCashflowAndTransactions", vi: "Tổng hợp tài sản, dòng tiền và thu chi tháng hiện tại", en: "A summary of assets, cashflow, and cashflow items for the current month", ja: "今月の資産、キャッシュフロー、取引のサマリー") }
                static func aSummaryOfAssetsCashflowAndTransactions(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.transactionlogicstatement.aSummaryOfAssetsCashflowAndTransactions", vi: "Tổng hợp tài sản, dòng tiền và thu chi tháng hiện tại", en: "A summary of assets, cashflow, and cashflow items for the current month", ja: "今月の資産、キャッシュフロー、取引のサマリー", language: language) }
                static var aSummaryOfDebtCreditLimitsAnd: String { L10n.tr("shared.corelogic.transactionlogicstatement.aSummaryOfDebtCreditLimitsAnd", vi: "Tổng hợp dư nợ, hạn mức và thu chi trong kỳ sao kê hiện tại", en: "A summary of debt, credit limits, and cashflow items in the current cycle", ja: "現在の締め期間における残高、利用枠、取引のサマリー") }
                static func aSummaryOfDebtCreditLimitsAnd(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.transactionlogicstatement.aSummaryOfDebtCreditLimitsAnd", vi: "Tổng hợp dư nợ, hạn mức và thu chi trong kỳ sao kê hiện tại", en: "A summary of debt, credit limits, and cashflow items in the current cycle", ja: "現在の締め期間における残高、利用枠、取引のサマリー", language: language) }
                static var account: String { L10n.tr("shared.corelogic.transactionlogicstatement.account", vi: "Tài khoản", en: "Account", ja: "口座") }
                static func account(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.transactionlogicstatement.account", vi: "Tài khoản", en: "Account", ja: "口座", language: language) }
                static var amount: String { L10n.tr("shared.corelogic.transactionlogicstatement.amount", vi: "Số tiền", en: "Amount", ja: "金額") }
                static func amount(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.transactionlogicstatement.amount", vi: "Số tiền", en: "Amount", ja: "金額", language: language) }
                static var assetWallets: String { L10n.tr("shared.corelogic.transactionlogicstatement.assetWallets", vi: "Ví tài sản", en: "Asset wallets", ja: "資産ウォレット") }
                static func assetWallets(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.transactionlogicstatement.assetWallets", vi: "Ví tài sản", en: "Asset wallets", ja: "資産ウォレット", language: language) }
                static var availableAssets: String { L10n.tr("shared.corelogic.transactionlogicstatement.availableAssets", vi: "Tài sản khả dụng", en: "Available assets", ja: "利用可能資産") }
                static func availableAssets(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.transactionlogicstatement.availableAssets", vi: "Tài sản khả dụng", en: "Available assets", ja: "利用可能資産", language: language) }
                static var availableCredit: String { L10n.tr("shared.corelogic.transactionlogicstatement.availableCredit", vi: "Hạn mức còn lại", en: "Available credit", ja: "利用可能額") }
                static func availableCredit(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.transactionlogicstatement.availableCredit", vi: "Hạn mức còn lại", en: "Available credit", ja: "利用可能額", language: language) }
                static var cards: String { L10n.tr("shared.corelogic.transactionlogicstatement.cards", vi: "thẻ", en: "cards", ja: "枚") }
                static func cards(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.transactionlogicstatement.cards", vi: "thẻ", en: "cards", ja: "枚", language: language) }
                static var chargesInCycle: String { L10n.tr("shared.corelogic.transactionlogicstatement.chargesInCycle", vi: "Chi tiêu trong kỳ", en: "Charges in cycle", ja: "期間内の利用") }
                static func chargesInCycle(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.transactionlogicstatement.chargesInCycle", vi: "Chi tiêu trong kỳ", en: "Charges in cycle", ja: "期間内の利用", language: language) }
                static var creditCard: String { L10n.tr("shared.corelogic.transactionlogicstatement.creditCard", vi: "Thẻ tín dụng", en: "Credit card", ja: "クレジットカード") }
                static func creditCard(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.transactionlogicstatement.creditCard", vi: "Thẻ tín dụng", en: "Credit card", ja: "クレジットカード", language: language) }
                static var creditCardStatement: String { L10n.tr("shared.corelogic.transactionlogicstatement.creditCardStatement", vi: "Sao kê thẻ tín dụng", en: "Credit card statement", ja: "クレジットカード明細") }
                static func creditCardStatement(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.transactionlogicstatement.creditCardStatement", vi: "Sao kê thẻ tín dụng", en: "Credit card statement", ja: "クレジットカード明細", language: language) }
                static var creditLimit: String { L10n.tr("shared.corelogic.transactionlogicstatement.creditLimit", vi: "Hạn mức", en: "Credit limit", ja: "利用限度額") }
                static func creditLimit(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.transactionlogicstatement.creditLimit", vi: "Hạn mức", en: "Credit limit", ja: "利用限度額", language: language) }
                static var currentBalance: String { L10n.tr("shared.corelogic.transactionlogicstatement.currentBalance", vi: "Số dư hiện tại", en: "Current balance", ja: "現在残高") }
                static func currentBalance(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.transactionlogicstatement.currentBalance", vi: "Số dư hiện tại", en: "Current balance", ja: "現在残高", language: language) }
                static var currentCycle: String { L10n.tr("shared.corelogic.transactionlogicstatement.currentCycle", vi: "Kỳ sao kê hiện tại", en: "Current cycle", ja: "現在の締め期間") }
                static func currentCycle(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.transactionlogicstatement.currentCycle", vi: "Kỳ sao kê hiện tại", en: "Current cycle", ja: "現在の締め期間", language: language) }
                static var currentDebt: String { L10n.tr("shared.corelogic.transactionlogicstatement.currentDebt", vi: "Dư nợ hiện tại", en: "Current debt", ja: "現在の利用残高") }
                static func currentDebt(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.transactionlogicstatement.currentDebt", vi: "Dư nợ hiện tại", en: "Current debt", ja: "現在の利用残高", language: language) }
                static var dateTime: String { L10n.tr("shared.corelogic.transactionlogicstatement.dateTime", vi: "Ngày giờ", en: "Date & time", ja: "日時") }
                static func dateTime(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.transactionlogicstatement.dateTime", vi: "Ngày giờ", en: "Date & time", ja: "日時", language: language) }
                static func dayValueEachMonth(_ value: String) -> String {
                    L10n.format("shared.corelogic.transactionlogicstatement.dayValueEachMonth", vi: "%@ hằng tháng", en: "Day %@ each month", ja: "毎月 %@ 日", value)
                }
                static func dayValueEachMonth(_ value: String, language: MistiaAppLanguage) -> String {
                    L10n.format("shared.corelogic.transactionlogicstatement.dayValueEachMonth", vi: "%@ hằng tháng", en: "Day %@ each month", ja: "毎月 %@ 日", language: language, value)
                }
                static var debt: String { L10n.tr("shared.corelogic.transactionlogicstatement.debt", vi: "Vay & cho vay", en: "Loans", ja: "貸し借り") }
                static func debt(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.transactionlogicstatement.debt", vi: "Vay & cho vay", en: "Loans", ja: "貸し借り", language: language) }
                static var destination: String { L10n.tr("shared.corelogic.transactionlogicstatement.destination", vi: "Đích", en: "Destination", ja: "入金先") }
                static func destination(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.transactionlogicstatement.destination", vi: "Đích", en: "Destination", ja: "入金先", language: language) }
                static var expenseThisMonth: String { L10n.tr("shared.corelogic.transactionlogicstatement.expenseThisMonth", vi: "Chi tháng này", en: "Expense this month", ja: "今月の支出") }
                static func expenseThisMonth(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.transactionlogicstatement.expenseThisMonth", vi: "Chi tháng này", en: "Expense this month", ja: "今月の支出", language: language) }
                static var generatedAt: String { L10n.tr("shared.corelogic.transactionlogicstatement.generatedAt", vi: "Xuất lúc", en: "Generated at", ja: "出力日時") }
                static func generatedAt(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.transactionlogicstatement.generatedAt", vi: "Xuất lúc", en: "Generated at", ja: "出力日時", language: language) }
                static var incomeThisMonth: String { L10n.tr("shared.corelogic.transactionlogicstatement.incomeThisMonth", vi: "Thu tháng này", en: "Income this month", ja: "今月の収入") }
                static func incomeThisMonth(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.transactionlogicstatement.incomeThisMonth", vi: "Thu tháng này", en: "Income this month", ja: "今月の収入", language: language) }
                static var items: String { L10n.tr("shared.corelogic.transactionlogicstatement.items", vi: "mục", en: "items", ja: "件") }
                static func items(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.transactionlogicstatement.items", vi: "mục", en: "items", ja: "件", language: language) }
                static var mistiaCreditCardStatement: String { L10n.tr("shared.corelogic.transactionlogicstatement.mistiaCreditCardStatement", vi: "Mistia Sao kê thẻ tín dụng", en: "Mistia Credit Card Statement", ja: "ミスティアクレジットカード明細") }
                static func mistiaCreditCardStatement(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.transactionlogicstatement.mistiaCreditCardStatement", vi: "Mistia Sao kê thẻ tín dụng", en: "Mistia Credit Card Statement", ja: "ミスティアクレジットカード明細", language: language) }
                static var mistiaMonthlySummary: String { L10n.tr("shared.corelogic.transactionlogicstatement.mistiaMonthlySummary", vi: "Mistia Sao kê tổng hợp", en: "Mistia Monthly Summary", ja: "ミスティア月次サマリー") }
                static func mistiaMonthlySummary(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.transactionlogicstatement.mistiaMonthlySummary", vi: "Mistia Sao kê tổng hợp", en: "Mistia Monthly Summary", ja: "ミスティア月次サマリー", language: language) }
                static var monthlySummaryStatement: String { L10n.tr("shared.corelogic.transactionlogicstatement.monthlySummaryStatement", vi: "Sao kê tổng hợp tháng", en: "Monthly summary statement", ja: "月次サマリーステートメント") }
                static func monthlySummaryStatement(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.transactionlogicstatement.monthlySummaryStatement", vi: "Sao kê tổng hợp tháng", en: "Monthly summary statement", ja: "月次サマリーステートメント", language: language) }
                static var netCashflow: String { L10n.tr("shared.corelogic.transactionlogicstatement.netCashflow", vi: "Chênh lệch dòng tiền", en: "Net cashflow", ja: "キャッシュフロー差額") }
                static func netCashflow(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.transactionlogicstatement.netCashflow", vi: "Chênh lệch dòng tiền", en: "Net cashflow", ja: "キャッシュフロー差額", language: language) }
                static var nextPaymentDate: String { L10n.tr("shared.corelogic.transactionlogicstatement.nextPaymentDate", vi: "Ngày thanh toán tiếp theo", en: "Next payment date", ja: "次回支払日") }
                static func nextPaymentDate(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.transactionlogicstatement.nextPaymentDate", vi: "Ngày thanh toán tiếp theo", en: "Next payment date", ja: "次回支払日", language: language) }
                static var noCreditCardsYet: String { L10n.tr("shared.corelogic.transactionlogicstatement.noCreditCardsYet", vi: "Chưa có thẻ tín dụng", en: "No credit cards yet", ja: "クレジットカードはまだありません") }
                static func noCreditCardsYet(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.transactionlogicstatement.noCreditCardsYet", vi: "Chưa có thẻ tín dụng", en: "No credit cards yet", ja: "クレジットカードはまだありません", language: language) }
                static var noTransactionsInThisMonthYet: String { L10n.tr("shared.corelogic.transactionlogicstatement.noTransactionsInThisMonthYet", vi: "Chưa có thu chi nào trong tháng này.", en: "No cashflow items in this month yet.", ja: "今月の取引はまだありません。") }
                static func noTransactionsInThisMonthYet(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.transactionlogicstatement.noTransactionsInThisMonthYet", vi: "Chưa có thu chi nào trong tháng này.", en: "No cashflow items in this month yet.", ja: "今月の取引はまだありません。", language: language) }
                static var noWalletSelected: String { L10n.tr("shared.corelogic.transactionlogicstatement.noWalletSelected", vi: "Chưa chọn ví", en: "No wallet selected", ja: "ウォレット未選択") }
                static func noWalletSelected(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.transactionlogicstatement.noWalletSelected", vi: "Chưa chọn ví", en: "No wallet selected", ja: "ウォレット未選択", language: language) }
                static var notSet: String { L10n.tr("shared.corelogic.transactionlogicstatement.notSet", vi: "Chưa cài đặt", en: "Not set", ja: "未設定") }
                static func notSet(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.transactionlogicstatement.notSet", vi: "Chưa cài đặt", en: "Not set", ja: "未設定", language: language) }
                static var openingBalance: String { L10n.tr("shared.corelogic.transactionlogicstatement.openingBalance", vi: "Số dư đầu kỳ", en: "Opening balance", ja: "期首残高") }
                static func openingBalance(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.transactionlogicstatement.openingBalance", vi: "Số dư đầu kỳ", en: "Opening balance", ja: "期首残高", language: language) }
                static var paymentDueDay: String { L10n.tr("shared.corelogic.transactionlogicstatement.paymentDueDay", vi: "Ngày thanh toán", en: "Payment due day", ja: "支払い期限") }
                static func paymentDueDay(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.transactionlogicstatement.paymentDueDay", vi: "Ngày thanh toán", en: "Payment due day", ja: "支払い期限", language: language) }
                static var paymentWallet: String { L10n.tr("shared.corelogic.transactionlogicstatement.paymentWallet", vi: "Ví thanh toán", en: "Payment wallet", ja: "支払い元ウォレット") }
                static func paymentWallet(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.transactionlogicstatement.paymentWallet", vi: "Ví thanh toán", en: "Payment wallet", ja: "支払い元ウォレット", language: language) }
                static var paymentsToCard: String { L10n.tr("shared.corelogic.transactionlogicstatement.paymentsToCard", vi: "Thanh toán vào thẻ", en: "Payments to card", ja: "カードへの支払い") }
                static func paymentsToCard(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.transactionlogicstatement.paymentsToCard", vi: "Thanh toán vào thẻ", en: "Payments to card", ja: "カードへの支払い", language: language) }
                static var source: String { L10n.tr("shared.corelogic.transactionlogicstatement.source", vi: "Nguồn", en: "Source", ja: "出金元") }
                static func source(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.transactionlogicstatement.source", vi: "Nguồn", en: "Source", ja: "出金元", language: language) }
                static var statementClosingDay: String { L10n.tr("shared.corelogic.transactionlogicstatement.statementClosingDay", vi: "Ngày chốt sao kê", en: "Statement closing day", ja: "締め日") }
                static func statementClosingDay(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.transactionlogicstatement.statementClosingDay", vi: "Ngày chốt sao kê", en: "Statement closing day", ja: "締め日", language: language) }
                static var statementPeriod: String { L10n.tr("shared.corelogic.transactionlogicstatement.statementPeriod", vi: "Kỳ sao kê", en: "Statement period", ja: "対象期間") }
                static func statementPeriod(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.transactionlogicstatement.statementPeriod", vi: "Kỳ sao kê", en: "Statement period", ja: "対象期間", language: language) }
                static var status: String { L10n.tr("shared.corelogic.transactionlogicstatement.status", vi: "Trạng thái", en: "Status", ja: "状態") }
                static func status(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.transactionlogicstatement.status", vi: "Trạng thái", en: "Status", ja: "状態", language: language) }
                static var thereAreNoAssetWalletsYet: String { L10n.tr("shared.corelogic.transactionlogicstatement.thereAreNoAssetWalletsYet", vi: "Chưa có ví tài sản nào.", en: "There are no asset wallets yet.", ja: "資産ウォレットはまだありません。") }
                static func thereAreNoAssetWalletsYet(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.transactionlogicstatement.thereAreNoAssetWalletsYet", vi: "Chưa có ví tài sản nào.", en: "There are no asset wallets yet.", ja: "資産ウォレットはまだありません。", language: language) }
                static var thereAreNoCardPaymentsInThis: String { L10n.tr("shared.corelogic.transactionlogicstatement.thereAreNoCardPaymentsInThis", vi: "Chưa có khoản thanh toán vào thẻ trong kỳ.", en: "There are no card payments in this cycle.", ja: "この期間のカード支払いはありません。") }
                static func thereAreNoCardPaymentsInThis(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.transactionlogicstatement.thereAreNoCardPaymentsInThis", vi: "Chưa có khoản thanh toán vào thẻ trong kỳ.", en: "There are no card payments in this cycle.", ja: "この期間のカード支払いはありません。", language: language) }
                static var thereAreNoChargesInThisCycle: String { L10n.tr("shared.corelogic.transactionlogicstatement.thereAreNoChargesInThisCycle", vi: "Không có chi tiêu nào trong kỳ sao kê này.", en: "There are no charges in this cycle.", ja: "この締め期間の利用はありません。") }
                static func thereAreNoChargesInThisCycle(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.transactionlogicstatement.thereAreNoChargesInThisCycle", vi: "Không có chi tiêu nào trong kỳ sao kê này.", en: "There are no charges in this cycle.", ja: "この締め期間の利用はありません。", language: language) }
                static var transaction: String { L10n.tr("shared.corelogic.transactionlogicstatement.transaction", vi: "Thu chi", en: "Cashflow", ja: "収支") }
                static func transaction(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.transactionlogicstatement.transaction", vi: "Thu chi", en: "Cashflow", ja: "収支", language: language) }
                static var transactionsThisMonth: String { L10n.tr("shared.corelogic.transactionlogicstatement.transactionsThisMonth", vi: "Thu chi tháng hiện tại", en: "Cashflow this month", ja: "今月の取引") }
                static func transactionsThisMonth(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.transactionlogicstatement.transactionsThisMonth", vi: "Thu chi tháng hiện tại", en: "Cashflow this month", ja: "今月の取引", language: language) }
                static var type: String { L10n.tr("shared.corelogic.transactionlogicstatement.type", vi: "Loại", en: "Type", ja: "種類") }
                static func type(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.transactionlogicstatement.type", vi: "Loại", en: "Type", ja: "種類", language: language) }
                static var utilization: String { L10n.tr("shared.corelogic.transactionlogicstatement.utilization", vi: "Tỷ lệ sử dụng", en: "Utilization", ja: "利用率") }
                static func utilization(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.transactionlogicstatement.utilization", vi: "Tỷ lệ sử dụng", en: "Utilization", ja: "利用率", language: language) }
                static var wallet: String { L10n.tr("shared.corelogic.transactionlogicstatement.wallet", vi: "Ví", en: "Wallet", ja: "ウォレット") }
                static func wallet(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.transactionlogicstatement.wallet", vi: "Ví", en: "Wallet", ja: "ウォレット", language: language) }
                static var wallets: String { L10n.tr("shared.corelogic.transactionlogicstatement.wallets", vi: "ví", en: "wallets", ja: "件") }
                static func wallets(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.transactionlogicstatement.wallets", vi: "ví", en: "wallets", ja: "件", language: language) }
                static var youHaveNotAddedAnyCardsTo: String { L10n.tr("shared.corelogic.transactionlogicstatement.youHaveNotAddedAnyCardsTo", vi: "Hiện tại bạn chưa thêm thẻ nào vào Mistia nên không có sao kê để xuất.", en: "You have not added any cards to Mistia yet, so there is no statement to export.", ja: "ミスティアにカードがまだ追加されていないため、書き出せる明細がありません。") }
                static func youHaveNotAddedAnyCardsTo(language: MistiaAppLanguage) -> String { L10n.tr("shared.corelogic.transactionlogicstatement.youHaveNotAddedAnyCardsTo", vi: "Hiện tại bạn chưa thêm thẻ nào vào Mistia nên không có sao kê để xuất.", en: "You have not added any cards to Mistia yet, so there is no statement to export.", ja: "ミスティアにカードがまだ追加されていないため、書き出せる明細がありません。", language: language) }
            }
        }

        nonisolated enum family {

            nonisolated enum familycontext {
                static var aFamilyMember: String { L10n.tr("shared.family.familycontext.aFamilyMember", vi: "Một thành viên", en: "A family member", ja: "家族メンバー") }
                static func aFamilyMember(language: MistiaAppLanguage) -> String { L10n.tr("shared.family.familycontext.aFamilyMember", vi: "Một thành viên", en: "A family member", ja: "家族メンバー", language: language) }
                static var canTCheckThisInviteBecauseThe: String { L10n.tr("shared.family.familycontext.canTCheckThisInviteBecauseThe", vi: "Không thể kiểm tra lời mời do mất kết nối. Vui lòng thử lại.", en: "Can't check this invite because the connection is unavailable. Please try again.", ja: "接続できないため招待を確認できません。もう一度お試しください。") }
                static func canTCheckThisInviteBecauseThe(language: MistiaAppLanguage) -> String { L10n.tr("shared.family.familycontext.canTCheckThisInviteBecauseThe", vi: "Không thể kiểm tra lời mời do mất kết nối. Vui lòng thử lại.", en: "Can't check this invite because the connection is unavailable. Please try again.", ja: "接続できないため招待を確認できません。もう一度お試しください。", language: language) }
                static var familyDataHasNotLoadedYetSync: String { L10n.tr("shared.family.familycontext.familyDataHasNotLoadedYetSync", vi: "Chưa tải được thông tin gia đình. Vui lòng đồng bộ lại rồi thử lần nữa.", en: "Family data has not loaded yet. Sync again and try once more.", ja: "ファミリー情報がまだ読み込まれていません。同期してからもう一度お試しください。") }
                static func familyDataHasNotLoadedYetSync(language: MistiaAppLanguage) -> String { L10n.tr("shared.family.familycontext.familyDataHasNotLoadedYetSync", vi: "Chưa tải được thông tin gia đình. Vui lòng đồng bộ lại rồi thử lần nữa.", en: "Family data has not loaded yet. Sync again and try once more.", ja: "ファミリー情報がまだ読み込まれていません。同期してからもう一度お試しください。", language: language) }
                static var onMistia: String { L10n.tr("shared.family.familycontext.onMistia", vi: "trên Mistia.", en: "on Mistia.", ja: "にミスティアで参加できます。") }
                static func onMistia(language: MistiaAppLanguage) -> String { L10n.tr("shared.family.familycontext.onMistia", vi: "trên Mistia.", en: "on Mistia.", ja: "にミスティアで参加できます。", language: language) }
                static var openTheLinkBelowToJoinNow: String { L10n.tr("shared.family.familycontext.openTheLinkBelowToJoinNow", vi: "Hãy mở link dưới để tham gia ngay!", en: "Open the link below to join now!", ja: "下のリンクを開いて今すぐ参加してください！") }
                static func openTheLinkBelowToJoinNow(language: MistiaAppLanguage) -> String { L10n.tr("shared.family.familycontext.openTheLinkBelowToJoinNow", vi: "Hãy mở link dưới để tham gia ngay!", en: "Open the link below to join now!", ja: "下のリンクを開いて今すぐ参加してください！", language: language) }
                static func requestToValueValue(_ arg1: String, _ arg2: String) -> String {
                    L10n.format("shared.family.familycontext.requestToValueValue", vi: "Yêu cầu %@ %@", en: "Request to %@ %@", ja: "%@の%@リクエスト", arg1, arg2)
                }
                static func requestToValueValue(_ arg1: String, _ arg2: String, language: MistiaAppLanguage) -> String {
                    L10n.format("shared.family.familycontext.requestToValueValue", vi: "Yêu cầu %@ %@", en: "Request to %@ %@", ja: "%@の%@リクエスト", language: language, arg1, arg2)
                }
                static var signInAndEnableCloudSyncTo: String { L10n.tr("shared.family.familycontext.signInAndEnableCloudSyncTo", vi: "Bạn cần đăng nhập và bật cloud sync để gửi yêu cầu quyền.", en: "Sign in and enable cloud sync to send permission requests.", ja: "権限リクエストを送るには、サインインしてクラウド同期を有効にしてください。") }
                static func signInAndEnableCloudSyncTo(language: MistiaAppLanguage) -> String { L10n.tr("shared.family.familycontext.signInAndEnableCloudSyncTo", vi: "Bạn cần đăng nhập và bật cloud sync để gửi yêu cầu quyền.", en: "Sign in and enable cloud sync to send permission requests.", ja: "権限リクエストを送るには、サインインしてクラウド同期を有効にしてください。", language: language) }
                static func valueWantsToValueYourValue(_ arg1: String, _ arg2: String, _ arg3: String) -> String {
                    L10n.format("shared.family.familycontext.valueWantsToValueYourValue", vi: "%@ muốn %@ %@ của bạn.", en: "%@ wants to %@ your %@.", ja: "%@ があなたの%@を%@したいとリクエストしています。", arg1, arg2, arg3)
                }
                static func valueWantsToValueYourValue(_ arg1: String, _ arg2: String, _ arg3: String, language: MistiaAppLanguage) -> String {
                    L10n.format("shared.family.familycontext.valueWantsToValueYourValue", vi: "%@ muốn %@ %@ của bạn.", en: "%@ wants to %@ your %@.", ja: "%@ があなたの%@を%@したいとリクエストしています。", language: language, arg1, arg2, arg3)
                }
                static var youCanOnlyHaveUpTo: String { L10n.tr("shared.family.familycontext.youCanOnlyHaveUpTo", vi: "Bạn chỉ có thể có tối đa 2 lời mời đang chờ.", en: "You can only have up to 2 pending invites.", ja: "待機中の招待は最大2件までです。") }
                static func youCanOnlyHaveUpTo(language: MistiaAppLanguage) -> String { L10n.tr("shared.family.familycontext.youCanOnlyHaveUpTo", vi: "Bạn chỉ có thể có tối đa 2 lời mời đang chờ.", en: "You can only have up to 2 pending invites.", ja: "待機中の招待は最大2件までです。", language: language) }
                static var youVeBeenInvitedToJoinThe: String { L10n.tr("shared.family.familycontext.youVeBeenInvitedToJoinThe", vi: "Bạn đã được mời tham gia gia đình", en: "You've been invited to join the family", ja: "家族への招待が届いています") }
                static func youVeBeenInvitedToJoinThe(language: MistiaAppLanguage) -> String { L10n.tr("shared.family.familycontext.youVeBeenInvitedToJoinThe", vi: "Bạn đã được mời tham gia gia đình", en: "You've been invited to join the family", ja: "家族への招待が届いています", language: language) }
            }

            nonisolated enum familyremote {
                static var inviteCodeDoesNotExistOrHas: String { L10n.tr("shared.family.familyremote.inviteCodeDoesNotExistOrHas", vi: "Mã mời không tồn tại hoặc đã bị xóa.", en: "Invite code does not exist or has been deleted.", ja: "招待コードが存在しないか、削除されました。") }
                static func inviteCodeDoesNotExistOrHas(language: MistiaAppLanguage) -> String { L10n.tr("shared.family.familyremote.inviteCodeDoesNotExistOrHas", vi: "Mã mời không tồn tại hoặc đã bị xóa.", en: "Invite code does not exist or has been deleted.", ja: "招待コードが存在しないか、削除されました。", language: language) }
                static var inviteCodeHasExpired: String { L10n.tr("shared.family.familyremote.inviteCodeHasExpired", vi: "Mã mời đã hết hạn.", en: "Invite code has expired.", ja: "招待コードの期限が切れました。") }
                static func inviteCodeHasExpired(language: MistiaAppLanguage) -> String { L10n.tr("shared.family.familyremote.inviteCodeHasExpired", vi: "Mã mời đã hết hạn.", en: "Invite code has expired.", ja: "招待コードの期限が切れました。", language: language) }
                static var thisInviteCodeIsNoLongerValid: String { L10n.tr("shared.family.familyremote.thisInviteCodeIsNoLongerValid", vi: "Mã mời này không còn hiệu lực.", en: "This invite code is no longer valid.", ja: "この招待コードはもう有効ではありません。") }
                static func thisInviteCodeIsNoLongerValid(language: MistiaAppLanguage) -> String { L10n.tr("shared.family.familyremote.thisInviteCodeIsNoLongerValid", vi: "Mã mời này không còn hiệu lực.", en: "This invite code is no longer valid.", ja: "この招待コードはもう有効ではありません。", language: language) }
            }

            nonisolated enum memberViewing {
                static func avatarAccessibility(_ value: String) -> String {
                    L10n.format("shared.family.memberViewing.avatarAccessibility", vi: "Đang xem dữ liệu của %@", en: "Viewing %@'s data", ja: "%@のデータを表示中", value)
                }
                static func avatarAccessibility(_ value: String, language: MistiaAppLanguage) -> String {
                    L10n.format("shared.family.memberViewing.avatarAccessibility", vi: "Đang xem dữ liệu của %@", en: "Viewing %@'s data", ja: "%@のデータを表示中", language: language, value)
                }
                static var confirmExit: String { L10n.tr("shared.family.memberViewing.confirmExit", vi: "Đồng ý", en: "Confirm", ja: "同意") }
                static func confirmExit(language: MistiaAppLanguage) -> String { L10n.tr("shared.family.memberViewing.confirmExit", vi: "Đồng ý", en: "Confirm", ja: "同意", language: language) }
                static func exitMessage(_ value: String) -> String {
                    L10n.format("shared.family.memberViewing.exitMessage", vi: "Bạn có muốn thoát khỏi dữ liệu của %@ và quay lại dữ liệu của bạn không?", en: "Do you want to leave %@'s data and return to your data?", ja: "%@のデータ表示を終了して、自分のデータに戻りますか？", value)
                }
                static func exitMessage(_ value: String, language: MistiaAppLanguage) -> String {
                    L10n.format("shared.family.memberViewing.exitMessage", vi: "Bạn có muốn thoát khỏi dữ liệu của %@ và quay lại dữ liệu của bạn không?", en: "Do you want to leave %@'s data and return to your data?", ja: "%@のデータ表示を終了して、自分のデータに戻りますか？", language: language, value)
                }
                static var exitTitle: String { L10n.tr("shared.family.memberViewing.exitTitle", vi: "Thoát khỏi chế độ xem dữ liệu?", en: "Leave data view?", ja: "データ表示を終了しますか？") }
                static func exitTitle(language: MistiaAppLanguage) -> String { L10n.tr("shared.family.memberViewing.exitTitle", vi: "Thoát khỏi chế độ xem dữ liệu?", en: "Leave data view?", ja: "データ表示を終了しますか？", language: language) }
            }

            nonisolated enum permissionRequest {
                static var sendingMessage: String { L10n.tr("shared.family.permissionRequest.sendingMessage", vi: "Mistia đang gửi yêu cầu. Bạn có thể tiếp tục sử dụng ứng dụng.", en: "Mistia is sending your request. You can keep using the app.", ja: "リクエストを送信しています。このままアプリをお使いいただけます。") }
                static func sendingMessage(language: MistiaAppLanguage) -> String { L10n.tr("shared.family.permissionRequest.sendingMessage", vi: "Mistia đang gửi yêu cầu. Bạn có thể tiếp tục sử dụng ứng dụng.", en: "Mistia is sending your request. You can keep using the app.", ja: "リクエストを送信しています。このままアプリをお使いいただけます。", language: language) }
                static var sendingTitle: String { L10n.tr("shared.family.permissionRequest.sendingTitle", vi: "Đang gửi yêu cầu...", en: "Sending request...", ja: "リクエストを送信中...") }
                static func sendingTitle(language: MistiaAppLanguage) -> String { L10n.tr("shared.family.permissionRequest.sendingTitle", vi: "Đang gửi yêu cầu...", en: "Sending request...", ja: "リクエストを送信中...", language: language) }
            }
        }

        nonisolated enum notifications {

            nonisolated enum mistiacreditcardstatementmaintenance {
                static var autoPaymentComplete: String { L10n.tr("shared.notifications.mistiacreditcardstatementmaintenance.autoPaymentComplete", vi: "Đã tự động thanh toán", en: "Auto payment complete", ja: "自動支払いが完了しました") }
                static func autoPaymentComplete(language: MistiaAppLanguage) -> String { L10n.tr("shared.notifications.mistiacreditcardstatementmaintenance.autoPaymentComplete", vi: "Đã tự động thanh toán", en: "Auto payment complete", ja: "自動支払いが完了しました", language: language) }
                static var autoPaymentFailed: String { L10n.tr("shared.notifications.mistiacreditcardstatementmaintenance.autoPaymentFailed", vi: "Tự động thanh toán thất bại", en: "Auto payment failed", ja: "自動支払いに失敗しました") }
                static func autoPaymentFailed(language: MistiaAppLanguage) -> String { L10n.tr("shared.notifications.mistiacreditcardstatementmaintenance.autoPaymentFailed", vi: "Tự động thanh toán thất bại", en: "Auto payment failed", ja: "自動支払いに失敗しました", language: language) }
                static func autoPaymentForValue(_ value: String) -> String {
                    L10n.format("shared.notifications.mistiacreditcardstatementmaintenance.autoPaymentForValue", vi: "Tự động thanh toán thẻ %@", en: "Auto payment for %@", ja: "%@ の自動支払い", value)
                }
                static func autoPaymentForValue(_ value: String, language: MistiaAppLanguage) -> String {
                    L10n.format("shared.notifications.mistiacreditcardstatementmaintenance.autoPaymentForValue", vi: "Tự động thanh toán thẻ %@", en: "Auto payment for %@", ja: "%@ の自動支払い", language: language, value)
                }
                static func mistiaPaidValueForValue(_ arg1: String, _ arg2: String) -> String {
                    L10n.format("shared.notifications.mistiacreditcardstatementmaintenance.mistiaPaidValueForValue", vi: "Mistia đã thanh toán %@ cho thẻ %@.", en: "Mistia paid %@ for %@.", ja: "ミスティアは %@ に %@ を支払いました。", arg1, arg2)
                }
                static func mistiaPaidValueForValue(_ arg1: String, _ arg2: String, language: MistiaAppLanguage) -> String {
                    L10n.format("shared.notifications.mistiacreditcardstatementmaintenance.mistiaPaidValueForValue", vi: "Mistia đã thanh toán %@ cho thẻ %@.", en: "Mistia paid %@ for %@.", ja: "ミスティアは %@ に %@ を支払いました。", language: language, arg1, arg2)
                }
                static var noLinkedWalletIsSet: String { L10n.tr("shared.notifications.mistiacreditcardstatementmaintenance.noLinkedWalletIsSet", vi: "chưa thiết lập ví liên kết", en: "no linked wallet is set", ja: "連携ウォレットが未設定です") }
                static func noLinkedWalletIsSet(language: MistiaAppLanguage) -> String { L10n.tr("shared.notifications.mistiacreditcardstatementmaintenance.noLinkedWalletIsSet", vi: "chưa thiết lập ví liên kết", en: "no linked wallet is set", ja: "連携ウォレットが未設定です", language: language) }
                static var statementReady: String { L10n.tr("shared.notifications.mistiacreditcardstatementmaintenance.statementReady", vi: "Sao kê đã chốt", en: "Statement ready", ja: "明細が確定しました") }
                static func statementReady(language: MistiaAppLanguage) -> String { L10n.tr("shared.notifications.mistiacreditcardstatementmaintenance.statementReady", vi: "Sao kê đã chốt", en: "Statement ready", ja: "明細が確定しました", language: language) }
                static var theLinkedWalletHasInsufficientFunds: String { L10n.tr("shared.notifications.mistiacreditcardstatementmaintenance.theLinkedWalletHasInsufficientFunds", vi: "ví liên kết không đủ số dư", en: "the linked wallet has insufficient funds", ja: "連携ウォレットの残高が不足しています") }
                static func theLinkedWalletHasInsufficientFunds(language: MistiaAppLanguage) -> String { L10n.tr("shared.notifications.mistiacreditcardstatementmaintenance.theLinkedWalletHasInsufficientFunds", vi: "ví liên kết không đủ số dư", en: "the linked wallet has insufficient funds", ja: "連携ウォレットの残高が不足しています", language: language) }
            }

            nonisolated enum mistiaduemaintenance {
                static var budgetOverLimit: String { L10n.tr("shared.notifications.mistiaduemaintenance.budgetOverLimit", vi: "Ngân sách đã vượt mức", en: "Budget over limit", ja: "予算を超過しました") }
                static func budgetOverLimit(language: MistiaAppLanguage) -> String { L10n.tr("shared.notifications.mistiaduemaintenance.budgetOverLimit", vi: "Ngân sách đã vượt mức", en: "Budget over limit", ja: "予算を超過しました", language: language) }
                static var budgetSpendingTooFast: String { L10n.tr("shared.notifications.mistiaduemaintenance.budgetSpendingTooFast", vi: "Chi tiêu đang nhanh hơn kế hoạch", en: "Spending is ahead of plan", ja: "支出ペースが計画を上回っています") }
                static func budgetSpendingTooFast(language: MistiaAppLanguage) -> String { L10n.tr("shared.notifications.mistiaduemaintenance.budgetSpendingTooFast", vi: "Chi tiêu đang nhanh hơn kế hoạch", en: "Spending is ahead of plan", ja: "支出ペースが計画を上回っています", language: language) }
                static func budgetSpendingTooFastBody(_ arg1: String, _ arg2: String, _ arg3: String) -> String {
                    L10n.format("shared.notifications.mistiaduemaintenance.budgetSpendingTooFastBody", vi: "%@ đang chi nhanh hơn kế hoạch. Dự báo cuối tháng %@; còn có thể chi %@ mỗi ngày.", en: "%@ is spending ahead of plan. Projected month-end spend is %@; %@ remains available per day.", ja: "%@ の支出ペースが計画を上回っています。月末予測は %@、1日あたり %@ 利用できます。", arg1, arg2, arg3)
                }
                static func budgetSpendingTooFastBody(_ arg1: String, _ arg2: String, _ arg3: String, language: MistiaAppLanguage) -> String {
                    L10n.format("shared.notifications.mistiaduemaintenance.budgetSpendingTooFastBody", vi: "%@ đang chi nhanh hơn kế hoạch. Dự báo cuối tháng %@; còn có thể chi %@ mỗi ngày.", en: "%@ is spending ahead of plan. Projected month-end spend is %@; %@ remains available per day.", ja: "%@ の支出ペースが計画を上回っています。月末予測は %@、1日あたり %@ 利用できます。", language: language, arg1, arg2, arg3)
                }
                static func valueUsedValueValueValue(_ arg1: String, _ arg2: String, _ arg3: String, _ arg4: String) -> String {
                    L10n.format("shared.notifications.mistiaduemaintenance.valueUsedValueValueValue", vi: "%@ đã dùng %@ / %@ (%@).", en: "%@ used %@ / %@ (%@).", ja: "%@ は %@ / %@（%@）を使用しました。", arg1, arg2, arg3, arg4)
                }
                static func valueUsedValueValueValue(_ arg1: String, _ arg2: String, _ arg3: String, _ arg4: String, language: MistiaAppLanguage) -> String {
                    L10n.format("shared.notifications.mistiaduemaintenance.valueUsedValueValueValue", vi: "%@ đã dùng %@ / %@ (%@).", en: "%@ used %@ / %@ (%@).", ja: "%@ は %@ / %@（%@）を使用しました。", language: language, arg1, arg2, arg3, arg4)
                }
            }

            nonisolated enum mistialocalnotificationscheduler {
                static var lowWalletBalance: String { L10n.tr("shared.notifications.mistialocalnotificationscheduler.lowWalletBalance", vi: "Ví sắp hết tiền", en: "Low wallet balance", ja: "残高が少ない") }
                static func lowWalletBalance(language: MistiaAppLanguage) -> String { L10n.tr("shared.notifications.mistialocalnotificationscheduler.lowWalletBalance", vi: "Ví sắp hết tiền", en: "Low wallet balance", ja: "残高が少ない", language: language) }
            }

            nonisolated enum mistiarecurringbillmaintenance {
                static func autoPaidValue(_ value: String) -> String {
                    L10n.format("shared.notifications.mistiarecurringbillmaintenance.autoPaidValue", vi: "Tự động thanh toán %@", en: "Auto-paid %@", ja: "%@ を自動支払いしました", value)
                }
                static func autoPaidValue(_ value: String, language: MistiaAppLanguage) -> String {
                    L10n.format("shared.notifications.mistiarecurringbillmaintenance.autoPaidValue", vi: "Tự động thanh toán %@", en: "Auto-paid %@", ja: "%@ を自動支払いしました", language: language, value)
                }
                static var autoPaymentComplete: String { L10n.tr("shared.notifications.mistiarecurringbillmaintenance.autoPaymentComplete", vi: "Đã tự động thanh toán", en: "Auto payment complete", ja: "自動支払いが完了しました") }
                static func autoPaymentComplete(language: MistiaAppLanguage) -> String { L10n.tr("shared.notifications.mistiarecurringbillmaintenance.autoPaymentComplete", vi: "Đã tự động thanh toán", en: "Auto payment complete", ja: "自動支払いが完了しました", language: language) }
                static var autoPaymentFailed: String { L10n.tr("shared.notifications.mistiarecurringbillmaintenance.autoPaymentFailed", vi: "Không thể tự động thanh toán", en: "Auto payment failed", ja: "自動支払いに失敗しました") }
                static func autoPaymentFailed(language: MistiaAppLanguage) -> String { L10n.tr("shared.notifications.mistiarecurringbillmaintenance.autoPaymentFailed", vi: "Không thể tự động thanh toán", en: "Auto payment failed", ja: "自動支払いに失敗しました", language: language) }
                static var billDueToday: String { L10n.tr("shared.notifications.mistiarecurringbillmaintenance.billDueToday", vi: "Hóa đơn cần trả hôm nay", en: "Bill due today", ja: "請求の支払期限日です") }
                static func billDueToday(language: MistiaAppLanguage) -> String { L10n.tr("shared.notifications.mistiarecurringbillmaintenance.billDueToday", vi: "Hóa đơn cần trả hôm nay", en: "Bill due today", ja: "請求の支払期限日です", language: language) }
                static var billOverdue: String { L10n.tr("shared.notifications.mistiarecurringbillmaintenance.billOverdue", vi: "Hóa đơn quá hạn", en: "Bill overdue", ja: "請求が延滞しています") }
                static func billOverdue(language: MistiaAppLanguage) -> String { L10n.tr("shared.notifications.mistiarecurringbillmaintenance.billOverdue", vi: "Hóa đơn quá hạn", en: "Bill overdue", ja: "請求が延滞しています", language: language) }
                static func failedToAutoPayValueValue(_ arg1: String, _ arg2: String) -> String {
                    L10n.format("shared.notifications.mistiarecurringbillmaintenance.failedToAutoPayValueValue", vi: "Lỗi khi thanh toán %@: %@", en: "Failed to auto-pay %@: %@", ja: "%@ の自動支払いに失敗しました: %@", arg1, arg2)
                }
                static func failedToAutoPayValueValue(_ arg1: String, _ arg2: String, language: MistiaAppLanguage) -> String {
                    L10n.format("shared.notifications.mistiarecurringbillmaintenance.failedToAutoPayValueValue", vi: "Lỗi khi thanh toán %@: %@", en: "Failed to auto-pay %@: %@", ja: "%@ の自動支払いに失敗しました: %@", language: language, arg1, arg2)
                }
                static func insufficientBalanceToAutoPayValuePlease(_ value: String) -> String {
                    L10n.format("shared.notifications.mistiarecurringbillmaintenance.insufficientBalanceToAutoPayValuePlease", vi: "Ví không đủ số dư để thanh toán %@. Vui lòng nạp thêm hoặc thanh toán thủ công.", en: "Insufficient balance to auto-pay %@. Please top up or pay manually.", ja: "%@ の自動支払いに必要な残高がありません。入金するか手動で支払ってください。", value)
                }
                static func insufficientBalanceToAutoPayValuePlease(_ value: String, language: MistiaAppLanguage) -> String {
                    L10n.format("shared.notifications.mistiarecurringbillmaintenance.insufficientBalanceToAutoPayValuePlease", vi: "Ví không đủ số dư để thanh toán %@. Vui lòng nạp thêm hoặc thanh toán thủ công.", en: "Insufficient balance to auto-pay %@. Please top up or pay manually.", ja: "%@ の自動支払いに必要な残高がありません。入金するか手動で支払ってください。", language: language, value)
                }
                static func mistiaPaidValueForValue(_ arg1: String, _ arg2: String) -> String {
                    L10n.format("shared.notifications.mistiarecurringbillmaintenance.mistiaPaidValueForValue", vi: "Mistia đã thanh toán %@ cho %@.", en: "Mistia paid %@ for %@.", ja: "ミスティアは %@ に %@ を支払いました。", arg1, arg2)
                }
                static func mistiaPaidValueForValue(_ arg1: String, _ arg2: String, language: MistiaAppLanguage) -> String {
                    L10n.format("shared.notifications.mistiarecurringbillmaintenance.mistiaPaidValueForValue", vi: "Mistia đã thanh toán %@ cho %@.", en: "Mistia paid %@ for %@.", ja: "ミスティアは %@ に %@ を支払いました。", language: language, arg1, arg2)
                }
                static var paymentDate: String { L10n.tr("shared.notifications.mistiarecurringbillmaintenance.paymentDate", vi: "Đến ngày thanh toán", en: "Payment date", ja: "支払開始日です") }
                static func paymentDate(language: MistiaAppLanguage) -> String { L10n.tr("shared.notifications.mistiarecurringbillmaintenance.paymentDate", vi: "Đến ngày thanh toán", en: "Payment date", ja: "支払開始日です", language: language) }
                static func valueIsDueByValue(_ arg1: String, _ arg2: String) -> String {
                    L10n.format("shared.notifications.mistiarecurringbillmaintenance.valueIsDueByValue", vi: "%@ cần được thanh toán trước %@.", en: "%@ is due by %@.", ja: "%@ は %@ までに支払いが必要です。", arg1, arg2)
                }
                static func valueIsDueByValue(_ arg1: String, _ arg2: String, language: MistiaAppLanguage) -> String {
                    L10n.format("shared.notifications.mistiarecurringbillmaintenance.valueIsDueByValue", vi: "%@ cần được thanh toán trước %@.", en: "%@ is due by %@.", ja: "%@ は %@ までに支払いが必要です。", language: language, arg1, arg2)
                }
                static func valueIsMissingAnAmountOrPayment(_ value: String) -> String {
                    L10n.format("shared.notifications.mistiarecurringbillmaintenance.valueIsMissingAnAmountOrPayment", vi: "%@ thiếu số tiền hoặc ví thanh toán để tự động thanh toán.", en: "%@ is missing an amount or payment wallet for auto payment.", ja: "%@ の自動支払いに必要な金額またはウォレットが不足しています。", value)
                }
                static func valueIsMissingAnAmountOrPayment(_ value: String, language: MistiaAppLanguage) -> String {
                    L10n.format("shared.notifications.mistiarecurringbillmaintenance.valueIsMissingAnAmountOrPayment", vi: "%@ thiếu số tiền hoặc ví thanh toán để tự động thanh toán.", en: "%@ is missing an amount or payment wallet for auto payment.", ja: "%@ の自動支払いに必要な金額またはウォレットが不足しています。", language: language, value)
                }
                static func valueIsPastItsDueDate(_ value: String) -> String {
                    L10n.format("shared.notifications.mistiarecurringbillmaintenance.valueIsPastItsDueDate", vi: "%@ đã quá hạn trả.", en: "%@ is past its due date.", ja: "%@ の支払い期限を過ぎています。", value)
                }
                static func valueIsPastItsDueDate(_ value: String, language: MistiaAppLanguage) -> String {
                    L10n.format("shared.notifications.mistiarecurringbillmaintenance.valueIsPastItsDueDate", vi: "%@ đã quá hạn trả.", en: "%@ is past its due date.", ja: "%@ の支払い期限を過ぎています。", language: language, value)
                }
                static func valueIsReadyToPayToday(_ value: String) -> String {
                    L10n.format("shared.notifications.mistiarecurringbillmaintenance.valueIsReadyToPayToday", vi: "%@ cần được thanh toán hôm nay.", en: "%@ is ready to pay today.", ja: "%@ は本日支払いが必要です。", value)
                }
                static func valueIsReadyToPayToday(_ value: String, language: MistiaAppLanguage) -> String {
                    L10n.format("shared.notifications.mistiarecurringbillmaintenance.valueIsReadyToPayToday", vi: "%@ cần được thanh toán hôm nay.", en: "%@ is ready to pay today.", ja: "%@ は本日支払いが必要です。", language: language, value)
                }
                static func valueValueIsDueByValue(_ arg1: String, _ arg2: String, _ arg3: String) -> String {
                    L10n.format("shared.notifications.mistiarecurringbillmaintenance.valueValueIsDueByValue", vi: "%@ (%@) cần được thanh toán trước %@.", en: "%@ (%@) is due by %@.", ja: "%@ は %@ までに %@ の支払いが必要です。", arg1, arg2, arg3)
                }
                static func valueValueIsDueByValue(_ arg1: String, _ arg2: String, _ arg3: String, language: MistiaAppLanguage) -> String {
                    L10n.format("shared.notifications.mistiarecurringbillmaintenance.valueValueIsDueByValue", vi: "%@ (%@) cần được thanh toán trước %@.", en: "%@ (%@) is due by %@.", ja: "%@ は %@ までに %@ の支払いが必要です。", language: language, arg1, arg2, arg3)
                }
                static func valueValueIsPastItsDueDate(_ arg1: String, _ arg2: String) -> String {
                    L10n.format("shared.notifications.mistiarecurringbillmaintenance.valueValueIsPastItsDueDate", vi: "%@ (%@) đã quá hạn trả.", en: "%@ (%@) is past its due date.", ja: "%@ (%@) の支払い期限を過ぎています。", arg1, arg2)
                }
                static func valueValueIsPastItsDueDate(_ arg1: String, _ arg2: String, language: MistiaAppLanguage) -> String {
                    L10n.format("shared.notifications.mistiarecurringbillmaintenance.valueValueIsPastItsDueDate", vi: "%@ (%@) đã quá hạn trả.", en: "%@ (%@) is past its due date.", ja: "%@ (%@) の支払い期限を過ぎています。", language: language, arg1, arg2)
                }
                static func valueValueIsReadyToPayToday(_ arg1: String, _ arg2: String) -> String {
                    L10n.format("shared.notifications.mistiarecurringbillmaintenance.valueValueIsReadyToPayToday", vi: "%@ (%@) cần được thanh toán hôm nay.", en: "%@ (%@) is ready to pay today.", ja: "%@ は本日 %@ の支払いが必要です。", arg1, arg2)
                }
                static func valueValueIsReadyToPayToday(_ arg1: String, _ arg2: String, language: MistiaAppLanguage) -> String {
                    L10n.format("shared.notifications.mistiarecurringbillmaintenance.valueValueIsReadyToPayToday", vi: "%@ (%@) cần được thanh toán hôm nay.", en: "%@ (%@) is ready to pay today.", ja: "%@ は本日 %@ の支払いが必要です。", language: language, arg1, arg2)
                }
            }
        }

        nonisolated enum persistence {

            nonisolated enum notification {
                static var bill: String { L10n.tr("shared.persistence.notification.bill", vi: "Hóa đơn", en: "Bill", ja: "請求書") }
                static func bill(language: MistiaAppLanguage) -> String { L10n.tr("shared.persistence.notification.bill", vi: "Hóa đơn", en: "Bill", ja: "請求書", language: language) }
                static var budget: String { L10n.tr("shared.persistence.notification.budget", vi: "Ngân sách", en: "Budget", ja: "予算") }
                static func budget(language: MistiaAppLanguage) -> String { L10n.tr("shared.persistence.notification.budget", vi: "Ngân sách", en: "Budget", ja: "予算", language: language) }
                static var card: String { L10n.tr("shared.persistence.notification.card", vi: "Thẻ", en: "Card", ja: "カード") }
                static func card(language: MistiaAppLanguage) -> String { L10n.tr("shared.persistence.notification.card", vi: "Thẻ", en: "Card", ja: "カード", language: language) }
                static var category: String { L10n.tr("shared.persistence.notification.category", vi: "Danh mục", en: "Category", ja: "カテゴリ") }
                static func category(language: MistiaAppLanguage) -> String { L10n.tr("shared.persistence.notification.category", vi: "Danh mục", en: "Category", ja: "カテゴリ", language: language) }
                static var create: String { L10n.tr("shared.persistence.notification.create", vi: "thêm mới", en: "create", ja: "作成") }
                static func create(language: MistiaAppLanguage) -> String { L10n.tr("shared.persistence.notification.create", vi: "thêm mới", en: "create", ja: "作成", language: language) }
                static var debt: String { L10n.tr("shared.persistence.notification.debt", vi: "Khoản nợ", en: "Debt", ja: "借金") }
                static func debt(language: MistiaAppLanguage) -> String { L10n.tr("shared.persistence.notification.debt", vi: "Khoản nợ", en: "Debt", ja: "借金", language: language) }
                static var edit: String { L10n.tr("shared.persistence.notification.edit", vi: "chỉnh sửa", en: "edit", ja: "編集") }
                static func edit(language: MistiaAppLanguage) -> String { L10n.tr("shared.persistence.notification.edit", vi: "chỉnh sửa", en: "edit", ja: "編集", language: language) }
                static var event: String { L10n.tr("shared.persistence.notification.event", vi: "Sự kiện", en: "Event", ja: "イベント") }
                static func event(language: MistiaAppLanguage) -> String { L10n.tr("shared.persistence.notification.event", vi: "Sự kiện", en: "Event", ja: "イベント", language: language) }
                static var familyTransfer: String { L10n.tr("shared.persistence.notification.familyTransfer", vi: "Chuyển tiền gia đình", en: "Family transfer", ja: "ファミリー送金") }
                static func familyTransfer(language: MistiaAppLanguage) -> String { L10n.tr("shared.persistence.notification.familyTransfer", vi: "Chuyển tiền gia đình", en: "Family transfer", ja: "ファミリー送金", language: language) }
                static var goal: String { L10n.tr("shared.persistence.notification.goal", vi: "Mục tiêu", en: "Goal", ja: "目標") }
                static func goal(language: MistiaAppLanguage) -> String { L10n.tr("shared.persistence.notification.goal", vi: "Mục tiêu", en: "Goal", ja: "目標", language: language) }
                static var installment: String { L10n.tr("shared.persistence.notification.installment", vi: "Trả góp", en: "Installment", ja: "分割払い") }
                static func installment(language: MistiaAppLanguage) -> String { L10n.tr("shared.persistence.notification.installment", vi: "Trả góp", en: "Installment", ja: "分割払い", language: language) }
                static var investment: String { L10n.tr("shared.persistence.notification.investment", vi: "Đầu tư", en: "Investments", ja: "投資") }
                static func investment(language: MistiaAppLanguage) -> String { L10n.tr("shared.persistence.notification.investment", vi: "Đầu tư", en: "Investments", ja: "投資", language: language) }
                static var paymentPlan: String { L10n.tr("shared.persistence.notification.paymentPlan", vi: "Khoản sắp tới", en: "Upcoming item", ja: "今後の項目") }
                static func paymentPlan(language: MistiaAppLanguage) -> String { L10n.tr("shared.persistence.notification.paymentPlan", vi: "Khoản sắp tới", en: "Upcoming item", ja: "今後の項目", language: language) }
                static var permission: String { L10n.tr("shared.persistence.notification.permission", vi: "Quyền hạn", en: "Permission", ja: "権限") }
                static func permission(language: MistiaAppLanguage) -> String { L10n.tr("shared.persistence.notification.permission", vi: "Quyền hạn", en: "Permission", ja: "権限", language: language) }
                static var transaction: String { L10n.tr("shared.persistence.notification.transaction", vi: "Thu chi", en: "Cashflow", ja: "収支") }
                static func transaction(language: MistiaAppLanguage) -> String { L10n.tr("shared.persistence.notification.transaction", vi: "Thu chi", en: "Cashflow", ja: "収支", language: language) }
                static var use: String { L10n.tr("shared.persistence.notification.use", vi: "sử dụng", en: "use", ja: "使用") }
                static func use(language: MistiaAppLanguage) -> String { L10n.tr("shared.persistence.notification.use", vi: "sử dụng", en: "use", ja: "使用", language: language) }
                static var view: String { L10n.tr("shared.persistence.notification.view", vi: "xem", en: "view", ja: "閲覧") }
                static func view(language: MistiaAppLanguage) -> String { L10n.tr("shared.persistence.notification.view", vi: "xem", en: "view", ja: "閲覧", language: language) }
                static var wallet: String { L10n.tr("shared.persistence.notification.wallet", vi: "Ví", en: "Wallet", ja: "ウォレット") }
                static func wallet(language: MistiaAppLanguage) -> String { L10n.tr("shared.persistence.notification.wallet", vi: "Ví", en: "Wallet", ja: "ウォレット", language: language) }
            }
        }

        nonisolated enum session {

            nonisolated enum session {
                static var aRequestWasJustSent: String { L10n.tr("shared.session.session.aRequestWasJustSent", vi: "Bạn vừa yêu cầu gần đây", en: "A request was just sent", ja: "直前にリクエストされました") }
                static func aRequestWasJustSent(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.aRequestWasJustSent", vi: "Bạn vừa yêu cầu gần đây", en: "A request was just sent", ja: "直前にリクエストされました", language: language) }
                static var accessDeniedErrorPleaseCheckYour: String { L10n.tr("shared.session.session.accessDeniedErrorPleaseCheckYour", vi: "Bị từ chối truy cập (Lỗi 403). Kiểm tra lại quyền hạn (RLS) trên database Supabase nhé.", en: "Access denied (Error 403). Please check your database Row Level Security (RLS) policies.", ja: "アクセスが拒否されました (Error 403)。Supabase のデータベース権限 (RLS) を確認してください。") }
                static func accessDeniedErrorPleaseCheckYour(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.accessDeniedErrorPleaseCheckYour", vi: "Bị từ chối truy cập (Lỗi 403). Kiểm tra lại quyền hạn (RLS) trên database Supabase nhé.", en: "Access denied (Error 403). Please check your database Row Level Security (RLS) policies.", ja: "アクセスが拒否されました (Error 403)。Supabase のデータベース権限 (RLS) を確認してください。", language: language) }
                static func addTheGoogleURLSchemeValueTo(_ value: String) -> String {
                    L10n.format("shared.session.session.addTheGoogleURLSchemeValueTo", vi: "Thêm URL scheme Google `%@` vào MistiaInfo.plist rồi build lại app.", en: "Add the Google URL scheme `%@` to MistiaInfo.plist, then rebuild the app.", ja: "Google の URL スキーム `%@` をミスティアInfo.plist に追加してから再ビルドしてください。", value)
                }
                static func addTheGoogleURLSchemeValueTo(_ value: String, language: MistiaAppLanguage) -> String {
                    L10n.format("shared.session.session.addTheGoogleURLSchemeValueTo", vi: "Thêm URL scheme Google `%@` vào MistiaInfo.plist rồi build lại app.", en: "Add the Google URL scheme `%@` to MistiaInfo.plist, then rebuild the app.", ja: "Google の URL スキーム `%@` をミスティアInfo.plist に追加してから再ビルドしてください。", language: language, value)
                }
                static var bothThisDeviceAndTheCloudAlready: String { L10n.tr("shared.session.session.bothThisDeviceAndTheCloudAlready", vi: "Cloud và máy này đều đã có dữ liệu. Chọn cách hợp nhất an toàn trước khi tiếp tục.", en: "Both this device and the cloud already have data. Choose the safest way to continue.", ja: "この端末とクラウドの両方にデータがあります。続行方法を選択してください。") }
                static func bothThisDeviceAndTheCloudAlready(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.bothThisDeviceAndTheCloudAlready", vi: "Cloud và máy này đều đã có dữ liệu. Chọn cách hợp nhất an toàn trước khi tiếp tục.", en: "Both this device and the cloud already have data. Choose the safest way to continue.", ja: "この端末とクラウドの両方にデータがあります。続行方法を選択してください。", language: language) }
                static var canTConnectRightNow: String { L10n.tr("shared.session.session.canTConnectRightNow", vi: "Chưa thể kết nối", en: "Can't connect right now", ja: "現在接続できません") }
                static func canTConnectRightNow(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.canTConnectRightNow", vi: "Chưa thể kết nối", en: "Can't connect right now", ja: "現在接続できません", language: language) }
                static var canTCreateTheAccountRightNow: String { L10n.tr("shared.session.session.canTCreateTheAccountRightNow", vi: "Chưa thể tạo tài khoản", en: "Can't create the account right now", ja: "現在アカウントを作成できません") }
                static func canTCreateTheAccountRightNow(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.canTCreateTheAccountRightNow", vi: "Chưa thể tạo tài khoản", en: "Can't create the account right now", ja: "現在アカウントを作成できません", language: language) }
                static var checkYourEmail: String { L10n.tr("shared.session.session.checkYourEmail", vi: "Kiểm tra email của bạn", en: "Check your email", ja: "メールを確認してください") }
                static func checkYourEmail(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.checkYourEmail", vi: "Kiểm tra email của bạn", en: "Check your email", ja: "メールを確認してください", language: language) }
                static var checkYourEmailToConfirm: String { L10n.tr("shared.session.session.checkYourEmailToConfirm", vi: "Kiểm tra email để xác nhận", en: "Check your email to confirm", ja: "確認メールをチェックしてください") }
                static func checkYourEmailToConfirm(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.checkYourEmailToConfirm", vi: "Kiểm tra email để xác nhận", en: "Check your email to confirm", ja: "確認メールをチェックしてください", language: language) }
                static var chooseHowToRunTheFirstSync: String { L10n.tr("shared.session.session.chooseHowToRunTheFirstSync", vi: "Cần chọn cách đồng bộ lần đầu", en: "Choose how to run the first sync", ja: "初回同期の方法を選んでください") }
                static func chooseHowToRunTheFirstSync(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.chooseHowToRunTheFirstSync", vi: "Cần chọn cách đồng bộ lần đầu", en: "Choose how to run the first sync", ja: "初回同期の方法を選んでください", language: language) }
                static var chooseHowToUseTheGuestLocal: String { L10n.tr("shared.session.session.chooseHowToUseTheGuestLocal", vi: "Chọn cách dùng dữ liệu local guest", en: "Choose how to use the guest local data", ja: "ゲストのローカルデータの使い方を選択してください") }
                static func chooseHowToUseTheGuestLocal(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.chooseHowToUseTheGuestLocal", vi: "Chọn cách dùng dữ liệu local guest", en: "Choose how to use the guest local data", ja: "ゲストのローカルデータの使い方を選択してください", language: language) }
                static var cloudAccountDeleted: String { L10n.tr("shared.session.session.cloudAccountDeleted", vi: "Đã xóa tài khoản cloud", en: "Cloud account deleted", ja: "クラウドアカウントを削除しました") }
                static func cloudAccountDeleted(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.cloudAccountDeleted", vi: "Đã xóa tài khoản cloud", en: "Cloud account deleted", ja: "クラウドアカウントを削除しました", language: language) }
                static var cloudSyncIsnTConfigured: String { L10n.tr("shared.session.session.cloudSyncIsnTConfigured", vi: "Chưa cấu hình dịch vụ đồng bộ", en: "Cloud sync isn't configured", ja: "クラウド同期が未設定です") }
                static func cloudSyncIsnTConfigured(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.cloudSyncIsnTConfigured", vi: "Chưa cấu hình dịch vụ đồng bộ", en: "Cloud sync isn't configured", ja: "クラウド同期が未設定です", language: language) }
                static var confirmationEmailSentAgain: String { L10n.tr("shared.session.session.confirmationEmailSentAgain", vi: "Đã gửi lại email xác nhận", en: "Confirmation email sent again", ja: "確認メールを再送しました") }
                static func confirmationEmailSentAgain(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.confirmationEmailSentAgain", vi: "Đã gửi lại email xác nhận", en: "Confirmation email sent again", ja: "確認メールを再送しました", language: language) }
                static var conflictResolved: String { L10n.tr("shared.session.session.conflictResolved", vi: "Conflict đã được xử lý", en: "Conflict resolved", ja: "競合を解決しました") }
                static func conflictResolved(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.conflictResolved", vi: "Conflict đã được xử lý", en: "Conflict resolved", ja: "競合を解決しました", language: language) }
                static var couldnTCreateTheAccount: String { L10n.tr("shared.session.session.couldnTCreateTheAccount", vi: "Tạo tài khoản chưa thành công", en: "Couldn't create the account", ja: "アカウントを作成できませんでした") }
                static func couldnTCreateTheAccount(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.couldnTCreateTheAccount", vi: "Tạo tài khoản chưa thành công", en: "Couldn't create the account", ja: "アカウントを作成できませんでした", language: language) }
                static var couldnTFinishSigningIn: String { L10n.tr("shared.session.session.couldnTFinishSigningIn", vi: "Chưa thể hoàn tất đăng nhập", en: "Couldn't finish signing in", ja: "ログインを完了できませんでした") }
                static func couldnTFinishSigningIn(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.couldnTFinishSigningIn", vi: "Chưa thể hoàn tất đăng nhập", en: "Couldn't finish signing in", ja: "ログインを完了できませんでした", language: language) }
                static var couldnTReadTheSavedSession: String { L10n.tr("shared.session.session.couldnTReadTheSavedSession", vi: "Chưa thể đọc phiên đã lưu", en: "Couldn't read the saved session", ja: "保存済みセッションを読み取れませんでした") }
                static func couldnTReadTheSavedSession(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.couldnTReadTheSavedSession", vi: "Chưa thể đọc phiên đã lưu", en: "Couldn't read the saved session", ja: "保存済みセッションを読み取れませんでした", language: language) }
                static var couldnTSignIn: String { L10n.tr("shared.session.session.couldnTSignIn", vi: "Đăng nhập chưa thành công", en: "Couldn't sign in", ja: "ログインできませんでした") }
                static func couldnTSignIn(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.couldnTSignIn", vi: "Đăng nhập chưa thành công", en: "Couldn't sign in", ja: "ログインできませんでした", language: language) }
                static var fillInTheGoogleIOSClientID: String { L10n.tr("shared.session.session.fillInTheGoogleIOSClientID", vi: "Điền Google iOS client ID và Google web client ID trong MistiaInfo.plist rồi build lại app.", en: "Fill in the Google iOS client ID and Google web client ID in MistiaInfo.plist, then rebuild the app.", ja: "ミスティアInfo.plist に Google iOS client ID と Google web client ID を設定してから再ビルドしてください。") }
                static func fillInTheGoogleIOSClientID(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.fillInTheGoogleIOSClientID", vi: "Điền Google iOS client ID và Google web client ID trong MistiaInfo.plist rồi build lại app.", en: "Fill in the Google iOS client ID and Google web client ID in MistiaInfo.plist, then rebuild the app.", ja: "ミスティアInfo.plist に Google iOS client ID と Google web client ID を設定してから再ビルドしてください。", language: language) }
                static var fillInTheServiceURLAndPublic: String { L10n.tr("shared.session.session.fillInTheServiceURLAndPublic", vi: "Điền URL dịch vụ và public key trong MistiaSyncConfig.plist rồi build lại app.", en: "Fill in the service URL and public key in MistiaSyncConfig.plist, then rebuild the app.", ja: "ミスティアSyncConfig.plist にサービス URL と公開キーを設定してから再ビルドしてください。") }
                static func fillInTheServiceURLAndPublic(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.fillInTheServiceURLAndPublic", vi: "Điền URL dịch vụ và public key trong MistiaSyncConfig.plist rồi build lại app.", en: "Fill in the service URL and public key in MistiaSyncConfig.plist, then rebuild the app.", ja: "ミスティアSyncConfig.plist にサービス URL と公開キーを設定してから再ビルドしてください。", language: language) }
                static var fillInTheServiceURLAndPublic2: String { L10n.tr("shared.session.session.fillInTheServiceURLAndPublic2", vi: "Điền URL dịch vụ và public key trong MistiaSyncConfig.plist để bật đăng nhập và đồng bộ.", en: "Fill in the service URL and public key in MistiaSyncConfig.plist to enable sign-in and sync.", ja: "ログインと同期を有効にするにはミスティアSyncConfig.plist にサービス URL と公開キーを設定してください。") }
                static func fillInTheServiceURLAndPublic2(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.fillInTheServiceURLAndPublic2", vi: "Điền URL dịch vụ và public key trong MistiaSyncConfig.plist để bật đăng nhập và đồng bộ.", en: "Fill in the service URL and public key in MistiaSyncConfig.plist to enable sign-in and sync.", ja: "ログインと同期を有効にするにはミスティアSyncConfig.plist にサービス URL と公開キーを設定してください。", language: language) }
                static var googleSignInCanTConnectRight: String { L10n.tr("shared.session.session.googleSignInCanTConnectRight", vi: "Google chưa thể kết nối", en: "Google sign-in can't connect right now", ja: "現在 Google ログインに接続できません") }
                static func googleSignInCanTConnectRight(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.googleSignInCanTConnectRight", vi: "Google chưa thể kết nối", en: "Google sign-in can't connect right now", ja: "現在 Google ログインに接続できません", language: language) }
                static var googleSignInCouldnTFinish: String { L10n.tr("shared.session.session.googleSignInCouldnTFinish", vi: "Google đăng nhập chưa thành công", en: "Google sign-in couldn't finish", ja: "Google ログインを完了できませんでした") }
                static func googleSignInCouldnTFinish(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.googleSignInCouldnTFinish", vi: "Google đăng nhập chưa thành công", en: "Google sign-in couldn't finish", ja: "Google ログインを完了できませんでした", language: language) }
                static var googleSignInIsnTReadyYet: String { L10n.tr("shared.session.session.googleSignInIsnTReadyYet", vi: "Google Sign-In chưa sẵn sàng", en: "Google sign-in isn't ready yet", ja: "Google ログインの設定がまだ完了していません") }
                static func googleSignInIsnTReadyYet(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.googleSignInIsnTReadyYet", vi: "Google Sign-In chưa sẵn sàng", en: "Google sign-in isn't ready yet", ja: "Google ログインの設定がまだ完了していません", language: language) }
                static var googleSignInRequestIsInvalidError: String { L10n.tr("shared.session.session.googleSignInRequestIsInvalidError", vi: "Yêu cầu đăng nhập Google không hợp lệ (Lỗi 400). Kiểm tra lại Client ID và URL Scheme của Google nhé.", en: "Google sign-in request is invalid (Error 400). Please check your Google Client ID and URL Scheme configuration.", ja: "Google ログインのリクエストが不正です (Error 400)。Google の Client ID と URL スキームの設定を確認してください。") }
                static func googleSignInRequestIsInvalidError(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.googleSignInRequestIsInvalidError", vi: "Yêu cầu đăng nhập Google không hợp lệ (Lỗi 400). Kiểm tra lại Client ID và URL Scheme của Google nhé.", en: "Google sign-in request is invalid (Error 400). Please check your Google Client ID and URL Scheme configuration.", ja: "Google ログインのリクエストが不正です (Error 400)。Google の Client ID と URL スキームの設定を確認してください。", language: language) }
                static var googleSignInWasCancelled: String { L10n.tr("shared.session.session.googleSignInWasCancelled", vi: "Đã hủy đăng nhập Google", en: "Google sign-in was cancelled", ja: "Google ログインはキャンセルされました") }
                static func googleSignInWasCancelled(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.googleSignInWasCancelled", vi: "Đã hủy đăng nhập Google", en: "Google sign-in was cancelled", ja: "Google ログインはキャンセルされました", language: language) }
                static var guestLocalDataIsSeparate: String { L10n.tr("shared.session.session.guestLocalDataIsSeparate", vi: "Dữ liệu local guest đang tách riêng", en: "Guest local data is separate", ja: "ゲストのローカルデータは分離されています") }
                static func guestLocalDataIsSeparate(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.guestLocalDataIsSeparate", vi: "Dữ liệu local guest đang tách riêng", en: "Guest local data is separate", ja: "ゲストのローカルデータは分離されています", language: language) }
                static var ifTheEmailIsValidMistiaWill: String { L10n.tr("shared.session.session.ifTheEmailIsValidMistiaWill", vi: "Nếu email hợp lệ, Mistia sẽ gửi một email đặt lại mật khẩu trong giây lát.", en: "If the email is valid, Mistia will send a password reset email shortly.", ja: "有効なメールアドレスであれば、まもなくパスワード再設定メールが送信されます。") }
                static func ifTheEmailIsValidMistiaWill(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.ifTheEmailIsValidMistiaWill", vi: "Nếu email hợp lệ, Mistia sẽ gửi một email đặt lại mật khẩu trong giây lát.", en: "If the email is valid, Mistia will send a password reset email shortly.", ja: "有効なメールアドレスであれば、まもなくパスワード再設定メールが送信されます。", language: language) }
                static var ifThisAccountIsPendingConfirmationThe: String { L10n.tr("shared.session.session.ifThisAccountIsPendingConfirmationThe", vi: "Nếu email đang chờ xác nhận, hệ thống sẽ gửi lại email mới đến hộp thư của bạn.", en: "If this account is pending confirmation, the system will send a fresh email to your inbox.", ja: "このアカウントが確認待ちの場合、システムが新しい確認メールを再送します。") }
                static func ifThisAccountIsPendingConfirmationThe(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.ifThisAccountIsPendingConfirmationThe", vi: "Nếu email đang chờ xác nhận, hệ thống sẽ gửi lại email mới đến hộp thư của bạn.", en: "If this account is pending confirmation, the system will send a fresh email to your inbox.", ja: "このアカウントが確認待ちの場合、システムが新しい確認メールを再送します。", language: language) }
                static var initialSyncPostponed: String { L10n.tr("shared.session.session.initialSyncPostponed", vi: "Đã tạm hoãn đồng bộ lần đầu", en: "Initial sync postponed", ja: "初回同期を保留しました") }
                static func initialSyncPostponed(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.initialSyncPostponed", vi: "Đã tạm hoãn đồng bộ lần đầu", en: "Initial sync postponed", ja: "初回同期を保留しました", language: language) }
                static var localDataCleared: String { L10n.tr("shared.session.session.localDataCleared", vi: "Đã xóa dữ liệu local", en: "Local data cleared", ja: "ローカルデータを削除しました") }
                static func localDataCleared(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.localDataCleared", vi: "Đã xóa dữ liệu local", en: "Local data cleared", ja: "ローカルデータを削除しました", language: language) }
                static var localMode: String { L10n.tr("shared.session.session.localMode", vi: "Đang dùng local", en: "Local mode", ja: "ローカルモード") }
                static func localMode(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.localMode", vi: "Đang dùng local", en: "Local mode", ja: "ローカルモード", language: language) }
                static var mistiaCanTConfirmYetWhetherThe: String { L10n.tr("shared.session.session.mistiaCanTConfirmYetWhetherThe", vi: "Mistia chưa thể xác định chắc dữ liệu local guest có nên gắn vào tài khoản này hay không. Bạn có thể gắn vào tài khoản hoặc giữ tách riêng.", en: "Mistia can't confirm yet whether the current guest local data should attach to this account. You can attach it now or keep it separate.", ja: "現在のゲストローカルデータをこのアカウントへ紐づけるべきか、ミスティアがまだ確定できません。今すぐ紐づけるか、分離したまま保持できます。") }
                static func mistiaCanTConfirmYetWhetherThe(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.mistiaCanTConfirmYetWhetherThe", vi: "Mistia chưa thể xác định chắc dữ liệu local guest có nên gắn vào tài khoản này hay không. Bạn có thể gắn vào tài khoản hoặc giữ tách riêng.", en: "Mistia can't confirm yet whether the current guest local data should attach to this account. You can attach it now or keep it separate.", ja: "現在のゲストローカルデータをこのアカウントへ紐づけるべきか、ミスティアがまだ確定できません。今すぐ紐づけるか、分離したまま保持できます。", language: language) }
                static var mistiaCanTReachTheSyncService: String { L10n.tr("shared.session.session.mistiaCanTReachTheSyncService", vi: "Mistia chưa thể kết nối đến dịch vụ đồng bộ. Kiểm tra mạng rồi thử lại nhé.", en: "Mistia can't reach the sync service right now. Check your connection and try again.", ja: "現在ミスティアは同期サービスに接続できません。通信状況を確認してから再度お試しください。") }
                static func mistiaCanTReachTheSyncService(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.mistiaCanTReachTheSyncService", vi: "Mistia chưa thể kết nối đến dịch vụ đồng bộ. Kiểm tra mạng rồi thử lại nhé.", en: "Mistia can't reach the sync service right now. Check your connection and try again.", ja: "現在ミスティアは同期サービスに接続できません。通信状況を確認してから再度お試しください。", language: language) }
                static var mistiaCouldnTFindTheSavedCloud: String { L10n.tr("shared.session.session.mistiaCouldnTFindTheSavedCloud", vi: "Mistia không thấy phiên cloud đã lưu, nhưng tài khoản vẫn được giữ đăng nhập trên thiết bị này.", en: "Mistia couldn't find the saved cloud session, but the account is still kept signed in on this device.", ja: "保存済みのクラウドセッションは見つかりませんでしたが、この端末ではアカウントをログイン状態のまま保持しています。") }
                static func mistiaCouldnTFindTheSavedCloud(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.mistiaCouldnTFindTheSavedCloud", vi: "Mistia không thấy phiên cloud đã lưu, nhưng tài khoản vẫn được giữ đăng nhập trên thiết bị này.", en: "Mistia couldn't find the saved cloud session, but the account is still kept signed in on this device.", ja: "保存済みのクラウドセッションは見つかりませんでしたが、この端末ではアカウントをログイン状態のまま保持しています。", language: language) }
                static var mistiaIsCheckingForAPreviouslySigned: String { L10n.tr("shared.session.session.mistiaIsCheckingForAPreviouslySigned", vi: "Mistia đang kiểm tra tài khoản đã đăng nhập trước đó.", en: "Mistia is checking for a previously signed-in account.", ja: "以前のログイン状態を確認しています。") }
                static func mistiaIsCheckingForAPreviouslySigned(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.mistiaIsCheckingForAPreviouslySigned", vi: "Mistia đang kiểm tra tài khoản đã đăng nhập trước đó.", en: "Mistia is checking for a previously signed-in account.", ja: "以前のログイン状態を確認しています。", language: language) }
                static var mistiaIsComparingLocalAndCloudData: String { L10n.tr("shared.session.session.mistiaIsComparingLocalAndCloudData", vi: "Mistia đang kiểm tra local và cloud rồi áp dụng chiến lược đồng bộ an toàn.", en: "Mistia is comparing local and cloud data, then applying the safest sync strategy.", ja: "ローカルとクラウドを比較して、安全な同期方法を適用しています。") }
                static func mistiaIsComparingLocalAndCloudData(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.mistiaIsComparingLocalAndCloudData", vi: "Mistia đang kiểm tra local và cloud rồi áp dụng chiến lược đồng bộ an toàn.", en: "Mistia is comparing local and cloud data, then applying the safest sync strategy.", ja: "ローカルとクラウドを比較して、安全な同期方法を適用しています。", language: language) }
                static var mistiaIsPushingLocalChangesAndPulling: String { L10n.tr("shared.session.session.mistiaIsPushingLocalChangesAndPulling", vi: "Mistia đang đẩy thay đổi local và kéo dữ liệu mới từ cloud.", en: "Mistia is pushing local changes and pulling the latest cloud data.", ja: "ローカル変更を送信し、最新のクラウドデータを取得しています。") }
                static func mistiaIsPushingLocalChangesAndPulling(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.mistiaIsPushingLocalChangesAndPulling", vi: "Mistia đang đẩy thay đổi local và kéo dữ liệu mới từ cloud.", en: "Mistia is pushing local changes and pulling the latest cloud data.", ja: "ローカル変更を送信し、最新のクラウドデータを取得しています。", language: language) }
                static var mistiaRestoredLocalDataFromTheSelected: String { L10n.tr("shared.session.session.mistiaRestoredLocalDataFromTheSelected", vi: "Mistia đã khôi phục dữ liệu local từ snapshot đã chọn.", en: "Mistia restored local data from the selected snapshot.", ja: "選択したスナップショットからローカルデータを復元しました。") }
                static func mistiaRestoredLocalDataFromTheSelected(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.mistiaRestoredLocalDataFromTheSelected", vi: "Mistia đã khôi phục dữ liệu local từ snapshot đã chọn.", en: "Mistia restored local data from the selected snapshot.", ja: "選択したスナップショットからローカルデータを復元しました。", language: language) }
                static var mistiaRestoredYourLocalDataReviewIt: String { L10n.tr("shared.session.session.mistiaRestoredYourLocalDataReviewIt", vi: "Mistia đã khôi phục dữ liệu local. Hãy kiểm tra dữ liệu rồi nhấn Đồng bộ ngay khi bạn sẵn sàng cập nhật cloud.", en: "Mistia restored your local data. Review it first, then tap Sync now when you're ready to update the cloud.", ja: "ローカルデータを復元しました。内容を確認してから、クラウドを更新する準備ができた時点で「今すぐ同期」を押してください。") }
                static func mistiaRestoredYourLocalDataReviewIt(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.mistiaRestoredYourLocalDataReviewIt", vi: "Mistia đã khôi phục dữ liệu local. Hãy kiểm tra dữ liệu rồi nhấn Đồng bộ ngay khi bạn sẵn sàng cập nhật cloud.", en: "Mistia restored your local data. Review it first, then tap Sync now when you're ready to update the cloud.", ja: "ローカルデータを復元しました。内容を確認してから、クラウドを更新する準備ができた時点で「今すぐ同期」を押してください。", language: language) }
                static var mistiaUpdatedTheRecordWithYourSelected: String { L10n.tr("shared.session.session.mistiaUpdatedTheRecordWithYourSelected", vi: "Mistia đã cập nhật lại bản ghi theo lựa chọn của bạn.", en: "Mistia updated the record with your selected resolution.", ja: "選択した内容でレコードを更新しました。") }
                static func mistiaUpdatedTheRecordWithYourSelected(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.mistiaUpdatedTheRecordWithYourSelected", vi: "Mistia đã cập nhật lại bản ghi theo lựa chọn của bạn.", en: "Mistia updated the record with your selected resolution.", ja: "選択した内容でレコードを更新しました。", language: language) }
                static var noInternetConnectionCheckYourWiFi: String { L10n.tr("shared.session.session.noInternetConnectionCheckYourWiFi", vi: "Không có kết nối mạng. Kiểm tra wifi hoặc 4G rồi thử lại nhé.", en: "No internet connection. Check your Wi-Fi or cellular data and try again.", ja: "ネットワーク接続がありません. Wi-Fi またはデータ通信を確認してもう一度お試しください。") }
                static func noInternetConnectionCheckYourWiFi(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.noInternetConnectionCheckYourWiFi", vi: "Không có kết nối mạng. Kiểm tra wifi hoặc 4G rồi thử lại nhé.", en: "No internet connection. Check your Wi-Fi or cellular data and try again.", ja: "ネットワーク接続がありません. Wi-Fi またはデータ通信を確認してもう一度お試しください。", language: language) }
                static var noNetworkConnectionReconnectToSyncEdit: String { L10n.tr("shared.session.session.noNetworkConnectionReconnectToSyncEdit", vi: "Không có kết nối mạng. Hãy kết nối lại để đồng bộ, chỉnh sửa hồ sơ hoặc quản lý gia đình.", en: "No network connection. Reconnect to sync, edit your profile, or manage family features.", ja: "ネットワーク接続がありません。同期、プロフィール編集、家族機能の管理を行うには再接続してください。") }
                static func noNetworkConnectionReconnectToSyncEdit(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.noNetworkConnectionReconnectToSyncEdit", vi: "Không có kết nối mạng. Hãy kết nối lại để đồng bộ, chỉnh sửa hồ sơ hoặc quản lý gia đình.", en: "No network connection. Reconnect to sync, edit your profile, or manage family features.", ja: "ネットワーク接続がありません。同期、プロフィール編集、家族機能の管理を行うには再接続してください。", language: language) }
                static var offline: String { L10n.tr("shared.session.session.offline", vi: "Đang ngoại tuyến", en: "Offline", ja: "オフライン") }
                static func offline(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.offline", vi: "Đang ngoại tuyến", en: "Offline", ja: "オフライン", language: language) }
                static var pleaseWaitABitBeforeTryingAgain: String { L10n.tr("shared.session.session.pleaseWaitABitBeforeTryingAgain", vi: "Chờ một chút rồi thử lại để tránh gửi email quá dày.", en: "Please wait a bit before trying again to avoid sending too many emails.", ja: "メール送信が多すぎないよう、少し待ってからもう一度お試しください。") }
                static func pleaseWaitABitBeforeTryingAgain(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.pleaseWaitABitBeforeTryingAgain", vi: "Chờ một chút rồi thử lại để tránh gửi email quá dày.", en: "Please wait a bit before trying again to avoid sending too many emails.", ja: "メール送信が多すぎないよう、少し待ってからもう一度お試しください。", language: language) }
                static func pushedMemberWalletChangesToCloudValue(_ value: String) -> String {
                    L10n.format("shared.session.session.pushedMemberWalletChangesToCloudValue", vi: "Đã đẩy thay đổi ví thành viên lên cloud. %@", en: "Pushed member wallet changes to cloud. %@", ja: "メンバーのウォレット変更をクラウドへ反映しました。%@", value)
                }
                static func pushedMemberWalletChangesToCloudValue(_ value: String, language: MistiaAppLanguage) -> String {
                    L10n.format("shared.session.session.pushedMemberWalletChangesToCloudValue", vi: "Đã đẩy thay đổi ví thành viên lên cloud. %@", en: "Pushed member wallet changes to cloud. %@", ja: "メンバーのウォレット変更をクラウドへ反映しました。%@", language: language, value)
                }
                static var restoringSession: String { L10n.tr("shared.session.session.restoringSession", vi: "Đang khôi phục phiên", en: "Restoring session", ja: "セッションを復元中") }
                static func restoringSession(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.restoringSession", vi: "Đang khôi phục phiên", en: "Restoring session", ja: "セッションを復元中", language: language) }
                static var runningInitialSync: String { L10n.tr("shared.session.session.runningInitialSync", vi: "Đang đồng bộ lần đầu", en: "Running initial sync", ja: "初回同期を実行中") }
                static func runningInitialSync(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.runningInitialSync", vi: "Đang đồng bộ lần đầu", en: "Running initial sync", ja: "初回同期を実行中", language: language) }
                static var serverNotReadyErrorYouMight: String { L10n.tr("shared.session.session.serverNotReadyErrorYouMight", vi: "Máy chủ chưa sẵn sàng (Lỗi 404). Có thể bạn chưa chạy database migrations trên Supabase.", en: "Server not ready (Error 404). You might need to run database migrations on Supabase.", ja: "サーバーの準備ができていません (Error 404)。Supabase でデータベースのマイグレーションを実行する必要があるかもしれません。") }
                static func serverNotReadyErrorYouMight(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.serverNotReadyErrorYouMight", vi: "Máy chủ chưa sẵn sàng (Lỗi 404). Có thể bạn chưa chạy database migrations trên Supabase.", en: "Server not ready (Error 404). You might need to run database migrations on Supabase.", ja: "サーバーの準備ができていません (Error 404)。Supabase でデータベースのマイグレーションを実行する必要があるかもしれません。", language: language) }
                static var signInToSyncMistiaDataAcross: String { L10n.tr("shared.session.session.signInToSyncMistiaDataAcross", vi: "Đăng nhập để đồng bộ dữ liệu Mistia giữa các thiết bị.", en: "Sign in to sync Mistia data across devices.", ja: "ログインするとミスティアのデータを端末間で同期できます。") }
                static func signInToSyncMistiaDataAcross(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.signInToSyncMistiaDataAcross", vi: "Đăng nhập để đồng bộ dữ liệu Mistia giữa các thiết bị.", en: "Sign in to sync Mistia data across devices.", ja: "ログインするとミスティアのデータを端末間で同期できます。", language: language) }
                static var signInToSyncWalletsCategoriesTransactions: String { L10n.tr("shared.session.session.signInToSyncWalletsCategoriesTransactions", vi: "Đăng nhập để đồng bộ ví, danh mục, thu chi và các mục sắp tới giữa các thiết bị.", en: "Sign in to sync wallets, categories, cashflow items, and upcoming data across devices.", ja: "ログインするとウォレット、カテゴリ、取引、計画データを端末間で同期できます。") }
                static func signInToSyncWalletsCategoriesTransactions(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.signInToSyncWalletsCategoriesTransactions", vi: "Đăng nhập để đồng bộ ví, danh mục, thu chi và các mục sắp tới giữa các thiết bị.", en: "Sign in to sync wallets, categories, cashflow items, and upcoming data across devices.", ja: "ログインするとウォレット、カテゴリ、取引、計画データを端末間で同期できます。", language: language) }
                static var signedIn: String { L10n.tr("shared.session.session.signedIn", vi: "Đã đăng nhập", en: "Signed in", ja: "ログイン済み") }
                static func signedIn(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.signedIn", vi: "Đã đăng nhập", en: "Signed in", ja: "ログイン済み", language: language) }
                static var signedInOnThisDevice: String { L10n.tr("shared.session.session.signedInOnThisDevice", vi: "Đã giữ đăng nhập trên máy này", en: "Signed in on this device", ja: "この端末ではログイン済みです") }
                static func signedInOnThisDevice(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.signedInOnThisDevice", vi: "Đã giữ đăng nhập trên máy này", en: "Signed in on this device", ja: "この端末ではログイン済みです", language: language) }
                static var signedInOnThisDevice2: String { L10n.tr("shared.session.session.signedInOnThisDevice2", vi: "Đã đăng nhập trên máy này", en: "Signed in on this device", ja: "この端末ではログイン済みです") }
                static func signedInOnThisDevice2(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.signedInOnThisDevice2", vi: "Đã đăng nhập trên máy này", en: "Signed in on this device", ja: "この端末ではログイン済みです", language: language) }
                static var signedOut: String { L10n.tr("shared.session.session.signedOut", vi: "Chưa đăng nhập", en: "Signed out", ja: "未ログイン") }
                static func signedOut(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.signedOut", vi: "Chưa đăng nhập", en: "Signed out", ja: "未ログイン", language: language) }
                static var snapshotRestored: String { L10n.tr("shared.session.session.snapshotRestored", vi: "Đã khôi phục snapshot", en: "Snapshot restored", ja: "スナップショットを復元しました") }
                static func snapshotRestored(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.snapshotRestored", vi: "Đã khôi phục snapshot", en: "Snapshot restored", ja: "スナップショットを復元しました", language: language) }
                static func supabaseIsReturningDataWithoutTheValue(_ value: String) -> String {
                    L10n.format("shared.session.session.supabaseIsReturningDataWithoutTheValue", vi: "Supabase đang trả về dữ liệu thiếu trường `%@`. Có thể schema cloud chưa khớp với app hiện tại.", en: "Supabase is returning data without the `%@` field. The cloud schema may be out of sync with this app build.", ja: "Supabase が `%@` フィールドのないデータを返しています。クラウドスキーマがこのアプリのビルドと一致していない可能性があります。", value)
                }
                static func supabaseIsReturningDataWithoutTheValue(_ value: String, language: MistiaAppLanguage) -> String {
                    L10n.format("shared.session.session.supabaseIsReturningDataWithoutTheValue", vi: "Supabase đang trả về dữ liệu thiếu trường `%@`. Có thể schema cloud chưa khớp với app hiện tại.", en: "Supabase is returning data without the `%@` field. The cloud schema may be out of sync with this app build.", ja: "Supabase が `%@` フィールドのないデータを返しています。クラウドスキーマがこのアプリのビルドと一致していない可能性があります。", language: language, value)
                }
                static var syncAccessDenied: String { L10n.tr("shared.session.session.syncAccessDenied", vi: "Đồng bộ bị từ chối", en: "Sync access denied", ja: "同期アクセスが拒否されました") }
                static func syncAccessDenied(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.syncAccessDenied", vi: "Đồng bộ bị từ chối", en: "Sync access denied", ja: "同期アクセスが拒否されました", language: language) }
                static var syncCompleted: String { L10n.tr("shared.session.session.syncCompleted", vi: "Đồng bộ đã hoàn tất", en: "Sync completed", ja: "同期が完了しました") }
                static func syncCompleted(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.syncCompleted", vi: "Đồng bộ đã hoàn tất", en: "Sync completed", ja: "同期が完了しました", language: language) }
                static var syncIsWaitingForTheNetwork: String { L10n.tr("shared.session.session.syncIsWaitingForTheNetwork", vi: "Đồng bộ đang chờ mạng", en: "Sync is waiting for the network", ja: "同期はネットワーク待ちです") }
                static func syncIsWaitingForTheNetwork(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.syncIsWaitingForTheNetwork", vi: "Đồng bộ đang chờ mạng", en: "Sync is waiting for the network", ja: "同期はネットワーク待ちです", language: language) }
                static var syncNeedsConfigurationChecks: String { L10n.tr("shared.session.session.syncNeedsConfigurationChecks", vi: "Đồng bộ cần kiểm tra cấu hình", en: "Sync needs configuration checks", ja: "同期設定の確認が必要です") }
                static func syncNeedsConfigurationChecks(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.syncNeedsConfigurationChecks", vi: "Đồng bộ cần kiểm tra cấu hình", en: "Sync needs configuration checks", ja: "同期設定の確認が必要です", language: language) }
                static func syncRequestIsInvalidErrorDetails(_ value: String) -> String {
                    L10n.format("shared.session.session.syncRequestIsInvalidErrorDetails", vi: "Yêu cầu sync không hợp lệ (Lỗi 400). Chi tiết: %@", en: "Sync request is invalid (Error 400). Details: %@", ja: "同期リクエストが不正です (Error 400)。詳細: %@", value)
                }
                static func syncRequestIsInvalidErrorDetails(_ value: String, language: MistiaAppLanguage) -> String {
                    L10n.format("shared.session.session.syncRequestIsInvalidErrorDetails", vi: "Yêu cầu sync không hợp lệ (Lỗi 400). Chi tiết: %@", en: "Sync request is invalid (Error 400). Details: %@", ja: "同期リクエストが不正です (Error 400)。詳細: %@", language: language, value)
                }
                static var syncSessionInvalid: String { L10n.tr("shared.session.session.syncSessionInvalid", vi: "Phiên sync không hợp lệ", en: "Sync session invalid", ja: "同期セッションが無効です") }
                static func syncSessionInvalid(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.syncSessionInvalid", vi: "Phiên sync không hợp lệ", en: "Sync session invalid", ja: "同期セッションが無効です", language: language) }
                static var syncTablesMissing: String { L10n.tr("shared.session.session.syncTablesMissing", vi: "Thiếu bảng đồng bộ", en: "Sync tables missing", ja: "同期テーブルが見つかりません") }
                static func syncTablesMissing(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.syncTablesMissing", vi: "Thiếu bảng đồng bộ", en: "Sync tables missing", ja: "同期テーブルが見つかりません", language: language) }
                static var syncing: String { L10n.tr("shared.session.session.syncing", vi: "Đang đồng bộ", en: "Syncing", ja: "同期中") }
                static func syncing(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.syncing", vi: "Đang đồng bộ", en: "Syncing", ja: "同期中", language: language) }
                static var tapSyncNowWhenYouReReady: String { L10n.tr("shared.session.session.tapSyncNowWhenYouReReady", vi: "Nhấn Đồng bộ ngay khi bạn sẵn sàng chọn cách đồng bộ dữ liệu với cloud.", en: "Tap Sync now when you're ready to choose how to sync with the cloud.", ja: "クラウドとの同期方法を選ぶ準備ができたら「今すぐ同期」を押してください。") }
                static func tapSyncNowWhenYouReReady(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.tapSyncNowWhenYouReReady", vi: "Nhấn Đồng bộ ngay khi bạn sẵn sàng chọn cách đồng bộ dữ liệu với cloud.", en: "Tap Sync now when you're ready to choose how to sync with the cloud.", ja: "クラウドとの同期方法を選ぶ準備ができたら「今すぐ同期」を押してください。", language: language) }
                static var theAuthenticationServiceIsTemporarilyBusyPlease: String { L10n.tr("shared.session.session.theAuthenticationServiceIsTemporarilyBusyPlease", vi: "Hệ thống xác thực đang tạm bận. Thử lại sau ít phút nhé.", en: "The authentication service is temporarily busy. Please try again in a moment.", ja: "認証サービスが一時的に混み合っています。少し待ってからお試しください。") }
                static func theAuthenticationServiceIsTemporarilyBusyPlease(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.theAuthenticationServiceIsTemporarilyBusyPlease", vi: "Hệ thống xác thực đang tạm bận. Thử lại sau ít phút nhé.", en: "The authentication service is temporarily busy. Please try again in a moment.", ja: "認証サービスが一時的に混み合っています。少し待ってからお試しください。", language: language) }
                static var theCloudSessionNeedsToReconnectThe: String { L10n.tr("shared.session.session.theCloudSessionNeedsToReconnectThe", vi: "Phiên cloud cần xác thực lại. Tài khoản vẫn được giữ đăng nhập trên thiết bị này.", en: "The cloud session needs to reconnect. The account is still kept signed in on this device.", ja: "クラウドセッションの再接続が必要です。この端末ではアカウントをログイン状態のまま保持しています。") }
                static func theCloudSessionNeedsToReconnectThe(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.theCloudSessionNeedsToReconnectThe", vi: "Phiên cloud cần xác thực lại. Tài khoản vẫn được giữ đăng nhập trên thiết bị này.", en: "The cloud session needs to reconnect. The account is still kept signed in on this device.", ja: "クラウドセッションの再接続が必要です。この端末ではアカウントをログイン状態のまま保持しています。", language: language) }
                static var theEmailOrPasswordIsIncorrectCheck: String { L10n.tr("shared.session.session.theEmailOrPasswordIsIncorrectCheck", vi: "Email hoặc mật khẩu chưa đúng. Kiểm tra lại rồi thử thêm lần nữa.", en: "The email or password is incorrect. Check them and try again.", ja: "メールアドレスまたはパスワードが正しくありません。確認してもう一度お試しください。") }
                static func theEmailOrPasswordIsIncorrectCheck(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.theEmailOrPasswordIsIncorrectCheck", vi: "Email hoặc mật khẩu chưa đúng. Kiểm tra lại rồi thử thêm lần nữa.", en: "The email or password is incorrect. Check them and try again.", ja: "メールアドレスまたはパスワードが正しくありません。確認してもう一度お試しください。", language: language) }
                static var theExistingCloudDataDoesnTMatch: String { L10n.tr("shared.session.session.theExistingCloudDataDoesnTMatch", vi: "Dữ liệu cloud hiện có không khớp format app đang cần.", en: "The existing cloud data doesn't match the format this app expects.", ja: "既存のクラウドデータが、このアプリの想定フォーマットと一致していません。") }
                static func theExistingCloudDataDoesnTMatch(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.theExistingCloudDataDoesnTMatch", vi: "Dữ liệu cloud hiện có không khớp format app đang cần.", en: "The existing cloud data doesn't match the format this app expects.", ja: "既存のクラウドデータが、このアプリの想定フォーマットと一致していません。", language: language) }
                static var theServiceTemporarilySlowedThingsDownTo: String { L10n.tr("shared.session.session.theServiceTemporarilySlowedThingsDownTo", vi: "Hệ thống tạm chậm lại để bảo vệ tài khoản. Chờ một chút rồi thử lại nhé.", en: "The service temporarily slowed things down to protect the account flow. Please wait a moment and try again.", ja: "サービス保護のため一時的に制限されています。少し待ってからもう一度お試しください。") }
                static func theServiceTemporarilySlowedThingsDownTo(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.theServiceTemporarilySlowedThingsDownTo", vi: "Hệ thống tạm chậm lại để bảo vệ tài khoản. Chờ một chút rồi thử lại nhé.", en: "The service temporarily slowed things down to protect the account flow. Please wait a moment and try again.", ja: "サービス保護のため一時的に制限されています。少し待ってからもう一度お試しください。", language: language) }
                static var theSessionWasKeptOnThisDevice: String { L10n.tr("shared.session.session.theSessionWasKeptOnThisDevice", vi: "Phiên đã được giữ lại trên máy", en: "The session was kept on this device", ja: "この端末ではセッションを保持しています") }
                static func theSessionWasKeptOnThisDevice(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.theSessionWasKeptOnThisDevice", vi: "Phiên đã được giữ lại trên máy", en: "The session was kept on this device", ja: "この端末ではセッションを保持しています", language: language) }
                static var theSyncDataFromSupabaseCouldnT: String { L10n.tr("shared.session.session.theSyncDataFromSupabaseCouldnT", vi: "Không đọc được dữ liệu đồng bộ từ Supabase. Kiểm tra lại schema và dữ liệu cloud nhé.", en: "The sync data from Supabase couldn't be read. Please check the cloud schema and data.", ja: "Supabase からの同期データを読み取れませんでした。クラウドのスキーマとデータを確認してください。") }
                static func theSyncDataFromSupabaseCouldnT(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.theSyncDataFromSupabaseCouldnT", vi: "Không đọc được dữ liệu đồng bộ từ Supabase. Kiểm tra lại schema và dữ liệu cloud nhé.", en: "The sync data from Supabase couldn't be read. Please check the cloud schema and data.", ja: "Supabase からの同期データを読み取れませんでした。クラウドのスキーマとデータを確認してください。", language: language) }
                static var theSyncDataFromSupabaseDoesnT: String { L10n.tr("shared.session.session.theSyncDataFromSupabaseDoesnT", vi: "Dữ liệu đồng bộ từ Supabase không đúng định dạng app đang cần. Kiểm tra lại schema bảng hoặc dữ liệu cũ trên cloud.", en: "The sync data from Supabase doesn't match the format this app expects. Check the table schema or older cloud data.", ja: "Supabase からの同期データが、このアプリが想定する形式と一致しません。テーブルスキーマまたは既存のクラウドデータを確認してください。") }
                static func theSyncDataFromSupabaseDoesnT(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.theSyncDataFromSupabaseDoesnT", vi: "Dữ liệu đồng bộ từ Supabase không đúng định dạng app đang cần. Kiểm tra lại schema bảng hoặc dữ liệu cũ trên cloud.", en: "The sync data from Supabase doesn't match the format this app expects. Check the table schema or older cloud data.", ja: "Supabase からの同期データが、このアプリが想定する形式と一致しません。テーブルスキーマまたは既存のクラウドデータを確認してください。", language: language) }
                static var theSyncResponseCouldnTBeRead: String { L10n.tr("shared.session.session.theSyncResponseCouldnTBeRead", vi: "Không đọc được dữ liệu sync trả về. Khả năng response từ Supabase đang thiếu dữ liệu hoặc sai định dạng.", en: "The sync response couldn't be read. Supabase may be returning missing or malformed data.", ja: "同期レスポンスを読み取れませんでした。Supabase が不足または不正な形式のデータを返している可能性があります。") }
                static func theSyncResponseCouldnTBeRead(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.theSyncResponseCouldnTBeRead", vi: "Không đọc được dữ liệu sync trả về. Khả năng response từ Supabase đang thiếu dữ liệu hoặc sai định dạng.", en: "The sync response couldn't be read. Supabase may be returning missing or malformed data.", ja: "同期レスポンスを読み取れませんでした。Supabase が不足または不正な形式のデータを返している可能性があります。", language: language) }
                static var theSyncServiceHasnTBeenConfigured: String { L10n.tr("shared.session.session.theSyncServiceHasnTBeenConfigured", vi: "Dịch vụ đồng bộ chưa được cấu hình đầy đủ trong app này.", en: "The sync service hasn't been configured completely in this build.", ja: "このビルドでは同期サービスの設定がまだ完了していません。") }
                static func theSyncServiceHasnTBeenConfigured(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.theSyncServiceHasnTBeenConfigured", vi: "Dịch vụ đồng bộ chưa được cấu hình đầy đủ trong app này.", en: "The sync service hasn't been configured completely in this build.", ja: "このビルドでは同期サービスの設定がまだ完了していません。", language: language) }
                static var thisAccountCanTAutomaticallyTakeThe: String { L10n.tr("shared.session.session.thisAccountCanTAutomaticallyTakeThe", vi: "Tài khoản này không được nhận dữ liệu local guest hiện tại. Giữ dữ liệu guest lại riêng hoặc xóa nó trước khi mở tài khoản.", en: "This account can't automatically take the current guest local data. Keep the guest data separate or delete it before opening the account.", ja: "このアカウントには現在のゲストローカルデータを自動で引き継げません。アカウントを開く前に、ゲストデータを分離したまま保持するか削除してください。") }
                static func thisAccountCanTAutomaticallyTakeThe(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.thisAccountCanTAutomaticallyTakeThe", vi: "Tài khoản này không được nhận dữ liệu local guest hiện tại. Giữ dữ liệu guest lại riêng hoặc xóa nó trước khi mở tài khoản.", en: "This account can't automatically take the current guest local data. Keep the guest data separate or delete it before opening the account.", ja: "このアカウントには現在のゲストローカルデータを自動で引き継げません。アカウントを開く前に、ゲストデータを分離したまま保持するか削除してください。", language: language) }
                static var thisBuildIsMissingTheIOSSettings: String { L10n.tr("shared.session.session.thisBuildIsMissingTheIOSSettings", vi: "Google Sign-In của app này còn thiếu cấu hình iOS cần thiết. Kiểm tra lại client ID và URL scheme rồi thử lại nhé.", en: "This build is missing the iOS settings Google Sign-In needs. Check the client IDs and URL scheme, then try again.", ja: "このビルドでは Google ログインに必要な iOS 設定が不足しています。client ID と URL スキームを確認してから再試行してください。") }
                static func thisBuildIsMissingTheIOSSettings(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.thisBuildIsMissingTheIOSSettings", vi: "Google Sign-In của app này còn thiếu cấu hình iOS cần thiết. Kiểm tra lại client ID và URL scheme rồi thử lại nhé.", en: "This build is missing the iOS settings Google Sign-In needs. Check the client IDs and URL scheme, then try again.", ja: "このビルドでは Google ログインに必要な iOS 設定が不足しています。client ID と URL スキームを確認してから再試行してください。", language: language) }
                static var thisDeviceIsBackToAClean: String { L10n.tr("shared.session.session.thisDeviceIsBackToAClean", vi: "Dữ liệu trên thiết bị này đã về trạng thái ban đầu.", en: "This device is back to a clean local state.", ja: "この端末のローカルデータを初期状態に戻しました。") }
                static func thisDeviceIsBackToAClean(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.thisDeviceIsBackToAClean", vi: "Dữ liệu trên thiết bị này đã về trạng thái ban đầu.", en: "This device is back to a clean local state.", ja: "この端末のローカルデータを初期状態に戻しました。", language: language) }
                static var thisDeviceIsBackToAClean2: String { L10n.tr("shared.session.session.thisDeviceIsBackToAClean2", vi: "Dữ liệu trên thiết bị này đã về trạng thái ban đầu. Cloud, đăng nhập và gia đình vẫn được giữ; hãy bấm Đồng bộ ngay nếu muốn tải lại dữ liệu cloud.", en: "This device is back to a clean local state. Cloud, sign-in, and family are preserved; tap Sync now if you want to load cloud data again.", ja: "この端末のローカルデータを初期状態に戻しました。クラウド、ログイン、家族は保持されています。クラウドデータを再取得する場合は「今すぐ同期」を押してください。") }
                static func thisDeviceIsBackToAClean2(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.thisDeviceIsBackToAClean2", vi: "Dữ liệu trên thiết bị này đã về trạng thái ban đầu. Cloud, đăng nhập và gia đình vẫn được giữ; hãy bấm Đồng bộ ngay nếu muốn tải lại dữ liệu cloud.", en: "This device is back to a clean local state. Cloud, sign-in, and family are preserved; tap Sync now if you want to load cloud data again.", ja: "この端末のローカルデータを初期状態に戻しました。クラウド、ログイン、家族は保持されています。クラウドデータを再取得する場合は「今すぐ同期」を押してください。", language: language) }
                static var thisEmailIsnTReadyForA: String { L10n.tr("shared.session.session.thisEmailIsnTReadyForA", vi: "Email này chưa sẵn sàng để tạo tài khoản mới. Thử đăng nhập hoặc dùng quên mật khẩu nhé.", en: "This email isn't ready for a new account right now. Try signing in or use password recovery instead.", ja: "このメールアドレスでは現在新しいアカウントを作成できません。ログインするか、パスワード再設定をお試しください。") }
                static func thisEmailIsnTReadyForA(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.thisEmailIsnTReadyForA", vi: "Email này chưa sẵn sàng để tạo tài khoản mới. Thử đăng nhập hoặc dùng quên mật khẩu nhé.", en: "This email isn't ready for a new account right now. Try signing in or use password recovery instead.", ja: "このメールアドレスでは現在新しいアカウントを作成できません。ログインするか、パスワード再設定をお試しください。", language: language) }
                static var youCanTryAgainAnyTimeWhen: String { L10n.tr("shared.session.session.youCanTryAgainAnyTimeWhen", vi: "Bạn có thể thử lại bất cứ lúc nào khi sẵn sàng.", en: "You can try again any time when you're ready.", ja: "準備ができたらいつでも再試行できます。") }
                static func youCanTryAgainAnyTimeWhen(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.youCanTryAgainAnyTimeWhen", vi: "Bạn có thể thử lại bất cứ lúc nào khi sẵn sàng.", en: "You can try again any time when you're ready.", ja: "準備ができたらいつでも再試行できます。", language: language) }
                static var youReEditingLocalDataForThe: String { L10n.tr("shared.session.session.youReEditingLocalDataForThe", vi: "Bạn đang chỉnh sửa dữ liệu cục bộ của profile trước đó. Thay đổi chỉ đồng bộ khi đăng nhập lại đúng tài khoản.", en: "You're editing local data for the previous profile. Changes sync only after signing back into that same account.", ja: "以前のプロフィールのローカルデータを編集中です。変更は同じアカウントで再ログインした場合のみ同期されます。") }
                static func youReEditingLocalDataForThe(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.youReEditingLocalDataForThe", vi: "Bạn đang chỉnh sửa dữ liệu cục bộ của profile trước đó. Thay đổi chỉ đồng bộ khi đăng nhập lại đúng tài khoản.", en: "You're editing local data for the previous profile. Changes sync only after signing back into that same account.", ja: "以前のプロフィールのローカルデータを編集中です。変更は同じアカウントで再ログインした場合のみ同期されます。", language: language) }
                static var youReMovingABitFast: String { L10n.tr("shared.session.session.youReMovingABitFast", vi: "Bạn thao tác hơi nhanh", en: "You're moving a bit fast", ja: "少し操作が速すぎます") }
                static func youReMovingABitFast(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.youReMovingABitFast", vi: "Bạn thao tác hơi nhanh", en: "You're moving a bit fast", ja: "少し操作が速すぎます", language: language) }
                static var yourAccountHasBeenCreatedOpenThe: String { L10n.tr("shared.session.session.yourAccountHasBeenCreatedOpenThe", vi: "Tài khoản của bạn đã được tạo. Mở email xác nhận rồi quay lại đăng nhập trong Mistia nhé.", en: "Your account has been created. Open the confirmation email, then come back and sign in to Mistia.", ja: "アカウントが作成されました。確認メールを開いてからミスティアにログインしてください。") }
                static func yourAccountHasBeenCreatedOpenThe(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.yourAccountHasBeenCreatedOpenThe", vi: "Tài khoản của bạn đã được tạo. Mở email xác nhận rồi quay lại đăng nhập trong Mistia nhé.", en: "Your account has been created. Open the confirmation email, then come back and sign in to Mistia.", ja: "アカウントが作成されました。確認メールを開いてからミスティアにログインしてください。", language: language) }
                static var yourCloudAccountAndServerDataWere: String { L10n.tr("shared.session.session.yourCloudAccountAndServerDataWere", vi: "Tài khoản và dữ liệu trên cloud đã được xóa. Dữ liệu local trên máy này vẫn được giữ lại.", en: "Your cloud account and server data were deleted. Local data on this device has been kept.", ja: "クラウドアカウントとサーバーデータを削除しました。この端末のローカルデータは保持されています。") }
                static func yourCloudAccountAndServerDataWere(language: MistiaAppLanguage) -> String { L10n.tr("shared.session.session.yourCloudAccountAndServerDataWere", vi: "Tài khoản và dữ liệu trên cloud đã được xóa. Dữ liệu local trên máy này vẫn được giữ lại.", en: "Your cloud account and server data were deleted. Local data on this device has been kept.", ja: "クラウドアカウントとサーバーデータを削除しました。この端末のローカルデータは保持されています。", language: language) }
            }
        }

        nonisolated enum sync {

            nonisolated enum familyOwnerPushConflict {
                static var alertMessage: String { L10n.tr("shared.sync.familyOwnerPushConflict.alertMessage", vi: "Mục này đã thay đổi trên cloud. Mistia sẽ làm mới dữ liệu rồi bạn có thể thử lại. Thay đổi chưa đẩy của bạn sẽ bị bỏ.", en: "This item changed in the cloud. Mistia will refresh the data, then you can try again. Your unpushed change will be discarded.", ja: "この項目はクラウドで変更されました。ミスティアがデータを更新するので、その後もう一度お試しください。未送信の変更は破棄されます。") }
                static func alertMessage(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.familyOwnerPushConflict.alertMessage", vi: "Mục này đã thay đổi trên cloud. Mistia sẽ làm mới dữ liệu rồi bạn có thể thử lại. Thay đổi chưa đẩy của bạn sẽ bị bỏ.", en: "This item changed in the cloud. Mistia will refresh the data, then you can try again. Your unpushed change will be discarded.", ja: "この項目はクラウドで変更されました。ミスティアがデータを更新するので、その後もう一度お試しください。未送信の変更は破棄されます。", language: language) }
                static var alertTitle: String { L10n.tr("shared.sync.familyOwnerPushConflict.alertTitle", vi: "Dữ liệu đã thay đổi", en: "Data changed", ja: "データが変更されました") }
                static func alertTitle(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.familyOwnerPushConflict.alertTitle", vi: "Dữ liệu đã thay đổi", en: "Data changed", ja: "データが変更されました", language: language) }
                static var badge: String { L10n.tr("shared.sync.familyOwnerPushConflict.badge", vi: "Đã có thay đổi trên cloud", en: "Changed in cloud", ja: "クラウドで変更あり") }
                static func badge(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.familyOwnerPushConflict.badge", vi: "Đã có thay đổi trên cloud", en: "Changed in cloud", ja: "クラウドで変更あり", language: language) }
            }

            nonisolated enum mistiasync {
                static var active: String { L10n.tr("shared.sync.mistiasync.active", vi: "Đang active", en: "Active", ja: "有効") }
                static func active(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.active", vi: "Đang active", en: "Active", ja: "有効", language: language) }
                static var active2: String { L10n.tr("shared.sync.mistiasync.active2", vi: "Đang dùng", en: "Active", ja: "有効") }
                static func active2(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.active2", vi: "Đang dùng", en: "Active", ja: "有効", language: language) }
                static var amount: String { L10n.tr("shared.sync.mistiasync.amount", vi: "Số tiền", en: "Amount", ja: "金額") }
                static func amount(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.amount", vi: "Số tiền", en: "Amount", ja: "金額", language: language) }
                static var amountPerCycle: String { L10n.tr("shared.sync.mistiasync.amountPerCycle", vi: "Số tiền mỗi kỳ", en: "Amount per cycle", ja: "各回の金額") }
                static func amountPerCycle(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.amountPerCycle", vi: "Số tiền mỗi kỳ", en: "Amount per cycle", ja: "各回の金額", language: language) }
                static var archived: String { L10n.tr("shared.sync.mistiasync.archived", vi: "Đã lưu trữ", en: "Archived", ja: "アーカイブ済み") }
                static func archived(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.archived", vi: "Đã lưu trữ", en: "Archived", ja: "アーカイブ済み", language: language) }
                static var archived2: String { L10n.tr("shared.sync.mistiasync.archived2", vi: "Lưu trữ", en: "Archived", ja: "アーカイブ") }
                static func archived2(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.archived2", vi: "Lưu trữ", en: "Archived", ja: "アーカイブ", language: language) }
                static var archivedAt: String { L10n.tr("shared.sync.mistiasync.archivedAt", vi: "Lưu trữ lúc", en: "Archived at", ja: "アーカイブ日時") }
                static func archivedAt(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.archivedAt", vi: "Lưu trữ lúc", en: "Archived at", ja: "アーカイブ日時", language: language) }
                static var bill: String { L10n.tr("shared.sync.mistiasync.bill", vi: "Hóa đơn", en: "Bill", ja: "請求書") }
                static func bill(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.bill", vi: "Hóa đơn", en: "Bill", ja: "請求書", language: language) }
                static var budget: String { L10n.tr("shared.sync.mistiasync.budget", vi: "Ngân sách", en: "Budget", ja: "予算") }
                static func budget(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.budget", vi: "Ngân sách", en: "Budget", ja: "予算", language: language) }
                static var budget2: String { L10n.tr("shared.sync.mistiasync.budget2", vi: "Ngân sách", en: "Budget", ja: "予算") }
                static func budget2(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.budget2", vi: "Ngân sách", en: "Budget", ja: "予算", language: language) }
                static var budgetPlan: String { L10n.tr("shared.sync.mistiasync.budgetPlan", vi: "Ngân sách", en: "Budget plan", ja: "予算") }
                static func budgetPlan(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.budgetPlan", vi: "Ngân sách", en: "Budget plan", ja: "予算", language: language) }
                static var cardName: String { L10n.tr("shared.sync.mistiasync.cardName", vi: "Tên thẻ", en: "Card name", ja: "カード名") }
                static func cardName(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.cardName", vi: "Tên thẻ", en: "Card name", ja: "カード名", language: language) }
                static var cardNetwork: String { L10n.tr("shared.sync.mistiasync.cardNetwork", vi: "Mạng thẻ", en: "Card network", ja: "カードブランド") }
                static func cardNetwork(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.cardNetwork", vi: "Mạng thẻ", en: "Card network", ja: "カードブランド", language: language) }
                static var cardWallet: String { L10n.tr("shared.sync.mistiasync.cardWallet", vi: "Ví thẻ", en: "Card wallet", ja: "カードウォレット") }
                static func cardWallet(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.cardWallet", vi: "Ví thẻ", en: "Card wallet", ja: "カードウォレット", language: language) }
                static var category: String { L10n.tr("shared.sync.mistiasync.category", vi: "Danh mục", en: "Category", ja: "カテゴリ") }
                static func category(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.category", vi: "Danh mục", en: "Category", ja: "カテゴリ", language: language) }
                static var category2: String { L10n.tr("shared.sync.mistiasync.category2", vi: "Danh mục", en: "Category", ja: "カテゴリ") }
                static func category2(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.category2", vi: "Danh mục", en: "Category", ja: "カテゴリ", language: language) }
                static var categorySnapshot: String { L10n.tr("shared.sync.mistiasync.categorySnapshot", vi: "Ảnh chụp danh mục", en: "Category snapshot", ja: "カテゴリスナップショット") }
                static func categorySnapshot(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.categorySnapshot", vi: "Ảnh chụp danh mục", en: "Category snapshot", ja: "カテゴリスナップショット", language: language) }
                static func closesValueDueValue(_ arg1: String, _ arg2: String) -> String {
                    L10n.format("shared.sync.mistiasync.closesValueDueValue", vi: "Chốt %@, hạn %@", en: "Closes %@, due %@", ja: "締め %@, 支払 %@", arg1, arg2)
                }
                static func closesValueDueValue(_ arg1: String, _ arg2: String, language: MistiaAppLanguage) -> String {
                    L10n.format("shared.sync.mistiasync.closesValueDueValue", vi: "Chốt %@, hạn %@", en: "Closes %@, due %@", ja: "締め %@, 支払 %@", language: language, arg1, arg2)
                }
                static var closingDay: String { L10n.tr("shared.sync.mistiasync.closingDay", vi: "Ngày chốt", en: "Closing day", ja: "締め日") }
                static func closingDay(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.closingDay", vi: "Ngày chốt", en: "Closing day", ja: "締め日", language: language) }
                static var color: String { L10n.tr("shared.sync.mistiasync.color", vi: "Màu", en: "Color", ja: "色") }
                static func color(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.color", vi: "Màu", en: "Color", ja: "色", language: language) }
                static var counterparty: String { L10n.tr("shared.sync.mistiasync.counterparty", vi: "Đối tác", en: "Counterparty", ja: "相手先") }
                static func counterparty(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.counterparty", vi: "Đối tác", en: "Counterparty", ja: "相手先", language: language) }
                static var creditCard: String { L10n.tr("shared.sync.mistiasync.creditCard", vi: "Thẻ tín dụng", en: "Credit card", ja: "クレジットカード") }
                static func creditCard(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.creditCard", vi: "Thẻ tín dụng", en: "Credit card", ja: "クレジットカード", language: language) }
                static var creditLimit: String { L10n.tr("shared.sync.mistiasync.creditLimit", vi: "Hạn mức", en: "Credit limit", ja: "利用限度額") }
                static func creditLimit(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.creditLimit", vi: "Hạn mức", en: "Credit limit", ja: "利用限度額", language: language) }
                static var currency: String { L10n.tr("shared.sync.mistiasync.currency", vi: "Tiền tệ", en: "Currency", ja: "通貨") }
                static func currency(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.currency", vi: "Tiền tệ", en: "Currency", ja: "通貨", language: language) }
                static var cycles: String { L10n.tr("shared.sync.mistiasync.cycles", vi: "Số kỳ", en: "Cycles", ja: "回数") }
                static func cycles(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.cycles", vi: "Số kỳ", en: "Cycles", ja: "回数", language: language) }
                static func dayValue(_ value: String) -> String {
                    L10n.format("shared.sync.mistiasync.dayValue", vi: "Ngày %@", en: "Day %@", ja: "%@日", value)
                }
                static func dayValue(_ value: String, language: MistiaAppLanguage) -> String {
                    L10n.format("shared.sync.mistiasync.dayValue", vi: "Ngày %@", en: "Day %@", ja: "%@日", language: language, value)
                }
                static var debtIntent: String { L10n.tr("shared.sync.mistiasync.debtIntent", vi: "Ý định nợ", en: "Debt intent", ja: "債務区分") }
                static func debtIntent(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.debtIntent", vi: "Ý định nợ", en: "Debt intent", ja: "債務区分", language: language) }
                static var deleteStatus: String { L10n.tr("shared.sync.mistiasync.deleteStatus", vi: "Trạng thái xóa", en: "Delete status", ja: "削除状態") }
                static func deleteStatus(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.deleteStatus", vi: "Trạng thái xóa", en: "Delete status", ja: "削除状態", language: language) }
                static var deleted: String { L10n.tr("shared.sync.mistiasync.deleted", vi: "Đã xóa", en: "Deleted", ja: "削除済み") }
                static func deleted(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.deleted", vi: "Đã xóa", en: "Deleted", ja: "削除済み", language: language) }
                static var deletedAt: String { L10n.tr("shared.sync.mistiasync.deletedAt", vi: "Xóa lúc", en: "Deleted at", ja: "削除日時") }
                static func deletedAt(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.deletedAt", vi: "Xóa lúc", en: "Deleted at", ja: "削除日時", language: language) }
                static func deletedAtValue(_ value: String) -> String {
                    L10n.format("shared.sync.mistiasync.deletedAtValue", vi: "Đã xóa lúc %@", en: "Deleted at %@", ja: "%@ に削除", value)
                }
                static func deletedAtValue(_ value: String, language: MistiaAppLanguage) -> String {
                    L10n.format("shared.sync.mistiasync.deletedAtValue", vi: "Đã xóa lúc %@", en: "Deleted at %@", ja: "%@ に削除", language: language, value)
                }
                static var deletedHereEditedInCloud: String { L10n.tr("shared.sync.mistiasync.deletedHereEditedInCloud", vi: "Máy này xóa, cloud đã sửa", en: "Deleted here, edited in cloud", ja: "この端末で削除、クラウドでは編集") }
                static func deletedHereEditedInCloud(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.deletedHereEditedInCloud", vi: "Máy này xóa, cloud đã sửa", en: "Deleted here, edited in cloud", ja: "この端末で削除、クラウドでは編集", language: language) }
                static var destinationWallet: String { L10n.tr("shared.sync.mistiasync.destinationWallet", vi: "Ví đích", en: "Destination wallet", ja: "入金ウォレット") }
                static func destinationWallet(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.destinationWallet", vi: "Ví đích", en: "Destination wallet", ja: "入金ウォレット", language: language) }
                static var dueDay: String { L10n.tr("shared.sync.mistiasync.dueDay", vi: "Hạn trả", en: "Payment deadline", ja: "支払い期限") }
                static func dueDay(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.dueDay", vi: "Hạn trả", en: "Payment deadline", ja: "支払い期限", language: language) }
                static var dueOccurrence: String { L10n.tr("shared.sync.mistiasync.dueOccurrence", vi: "Kỳ thanh toán", en: "Payment occurrence", ja: "支払いが必要") }
                static func dueOccurrence(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.dueOccurrence", vi: "Kỳ thanh toán", en: "Payment occurrence", ja: "支払いが必要", language: language) }
                static var dueOccurrence2: String { L10n.tr("shared.sync.mistiasync.dueOccurrence2", vi: "Kỳ thanh toán", en: "Payment occurrence", ja: "支払いが必要") }
                static func dueOccurrence2(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.dueOccurrence2", vi: "Kỳ thanh toán", en: "Payment occurrence", ja: "支払いが必要", language: language) }
                static var duplicateCreate: String { L10n.tr("shared.sync.mistiasync.duplicateCreate", vi: "Trùng tạo dữ liệu", en: "Duplicate create", ja: "重複作成") }
                static func duplicateCreate(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.duplicateCreate", vi: "Trùng tạo dữ liệu", en: "Duplicate create", ja: "重複作成", language: language) }
                static var editedHereDeletedInCloud: String { L10n.tr("shared.sync.mistiasync.editedHereDeletedInCloud", vi: "Máy này sửa, cloud đã xóa", en: "Edited here, deleted in cloud", ja: "この端末で編集、クラウドでは削除") }
                static func editedHereDeletedInCloud(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.editedHereDeletedInCloud", vi: "Máy này sửa, cloud đã xóa", en: "Edited here, deleted in cloud", ja: "この端末で編集、クラウドでは削除", language: language) }
                static var editedOnTwoDevices: String { L10n.tr("shared.sync.mistiasync.editedOnTwoDevices", vi: "Hai thiết bị cùng sửa", en: "Edited on two devices", ja: "2 台で同時編集") }
                static func editedOnTwoDevices(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.editedOnTwoDevices", vi: "Hai thiết bị cùng sửa", en: "Edited on two devices", ja: "2 台で同時編集", language: language) }
                static var englishName: String { L10n.tr("shared.sync.mistiasync.englishName", vi: "Tên tiếng Anh", en: "English name", ja: "英語名") }
                static func englishName(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.englishName", vi: "Tên tiếng Anh", en: "English name", ja: "英語名", language: language) }
                static var familyBudget: String { L10n.tr("shared.sync.mistiasync.familyBudget", vi: "Ngân sách gia đình", en: "Family budget", ja: "家族予算") }
                static func familyBudget(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.familyBudget", vi: "Ngân sách gia đình", en: "Family budget", ja: "家族予算", language: language) }
                static var favorite: String { L10n.tr("shared.sync.mistiasync.favorite", vi: "Yêu thích", en: "Favorite", ja: "お気に入り") }
                static func favorite(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.favorite", vi: "Yêu thích", en: "Favorite", ja: "お気に入り", language: language) }
                static var goal: String { L10n.tr("shared.sync.mistiasync.goal", vi: "Mục tiêu", en: "Goal", ja: "目標") }
                static func goal(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.goal", vi: "Mục tiêu", en: "Goal", ja: "目標", language: language) }
                static var hierarchyRole: String { L10n.tr("shared.sync.mistiasync.hierarchyRole", vi: "Vai trò phân cấp", en: "Hierarchy role", ja: "階層ロール") }
                static func hierarchyRole(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.hierarchyRole", vi: "Vai trò phân cấp", en: "Hierarchy role", ja: "階層ロール", language: language) }
                static var icon: String { L10n.tr("shared.sync.mistiasync.icon", vi: "Icon", en: "Icon", ja: "アイコン") }
                static func icon(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.icon", vi: "Icon", en: "Icon", ja: "アイコン", language: language) }
                static var installment: String { L10n.tr("shared.sync.mistiasync.installment", vi: "Trả góp", en: "Installment", ja: "分割払い") }
                static func installment(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.installment", vi: "Trả góp", en: "Installment", ja: "分割払い", language: language) }
                static var institution: String { L10n.tr("shared.sync.mistiasync.institution", vi: "Ngân hàng", en: "Institution", ja: "金融機関") }
                static func institution(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.institution", vi: "Ngân hàng", en: "Institution", ja: "金融機関", language: language) }
                static var institutionPreset: String { L10n.tr("shared.sync.mistiasync.institutionPreset", vi: "Preset ngân hàng", en: "Institution preset", ja: "金融機関プリセット") }
                static func institutionPreset(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.institutionPreset", vi: "Preset ngân hàng", en: "Institution preset", ja: "金融機関プリセット", language: language) }
                static var japaneseName: String { L10n.tr("shared.sync.mistiasync.japaneseName", vi: "Tên tiếng Nhật", en: "Japanese name", ja: "日本語名") }
                static func japaneseName(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.japaneseName", vi: "Tên tiếng Nhật", en: "Japanese name", ja: "日本語名", language: language) }
                static var keepDeleted: String { L10n.tr("shared.sync.mistiasync.keepDeleted", vi: "Giữ đã xóa", en: "Keep deleted", ja: "削除を維持") }
                static func keepDeleted(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.keepDeleted", vi: "Giữ đã xóa", en: "Keep deleted", ja: "削除を維持", language: language) }
                static var kind: String { L10n.tr("shared.sync.mistiasync.kind", vi: "Loại", en: "Kind", ja: "種別") }
                static func kind(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.kind", vi: "Loại", en: "Kind", ja: "種別", language: language) }
                static var lastDigits: String { L10n.tr("shared.sync.mistiasync.lastDigits", vi: "4 số cuối", en: "Last 4 digits", ja: "下4桁") }
                static func lastDigits(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.lastDigits", vi: "4 số cuối", en: "Last 4 digits", ja: "下4桁", language: language) }
                static var lastModifiedDevice: String { L10n.tr("shared.sync.mistiasync.lastModifiedDevice", vi: "Thiết bị sửa cuối", en: "Last modified device", ja: "最終更新端末") }
                static func lastModifiedDevice(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.lastModifiedDevice", vi: "Thiết bị sửa cuối", en: "Last modified device", ja: "最終更新端末", language: language) }
                static var limit: String { L10n.tr("shared.sync.mistiasync.limit", vi: "Hạn mức", en: "Limit", ja: "上限") }
                static func limit(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.limit", vi: "Hạn mức", en: "Limit", ja: "上限", language: language) }
                static var linkedTransaction: String { L10n.tr("shared.sync.mistiasync.linkedTransaction", vi: "Thu chi liên kết", en: "Linked cashflow item", ja: "リンク済み取引") }
                static func linkedTransaction(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.linkedTransaction", vi: "Thu chi liên kết", en: "Linked cashflow item", ja: "リンク済み取引", language: language) }
                static var linkedWallet: String { L10n.tr("shared.sync.mistiasync.linkedWallet", vi: "Ví liên kết", en: "Linked wallet", ja: "リンク済みウォレット") }
                static func linkedWallet(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.linkedWallet", vi: "Ví liên kết", en: "Linked wallet", ja: "リンク済みウォレット", language: language) }
                static var month: String { L10n.tr("shared.sync.mistiasync.month", vi: "Tháng", en: "Month", ja: "月") }
                static func month(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.month", vi: "Tháng", en: "Month", ja: "月", language: language) }
                static var monthlyFrequency: String { L10n.tr("shared.sync.mistiasync.monthlyFrequency", vi: "Chu kỳ tháng", en: "Monthly frequency", ja: "月単位の周期") }
                static func monthlyFrequency(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.monthlyFrequency", vi: "Chu kỳ tháng", en: "Monthly frequency", ja: "月単位の周期", language: language) }
                static var name: String { L10n.tr("shared.sync.mistiasync.name", vi: "Tên", en: "Name", ja: "名前") }
                static func name(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.name", vi: "Tên", en: "Name", ja: "名前", language: language) }
                static var nameUnavailable: String { L10n.tr("shared.sync.mistiasync.nameUnavailable", vi: "Không tìm thấy tên", en: "Name unavailable", ja: "名前なし") }
                static func nameUnavailable(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.nameUnavailable", vi: "Không tìm thấy tên", en: "Name unavailable", ja: "名前なし", language: language) }
                static var no: String { L10n.tr("shared.sync.mistiasync.no", vi: "Không", en: "No", ja: "いいえ") }
                static func no(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.no", vi: "Không", en: "No", ja: "いいえ", language: language) }
                static var none: String { L10n.tr("shared.sync.mistiasync.none", vi: "Chưa có", en: "None", ja: "なし") }
                static func none(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.none", vi: "Chưa có", en: "None", ja: "なし", language: language) }
                static var note: String { L10n.tr("shared.sync.mistiasync.note", vi: "Ghi chú", en: "Note", ja: "メモ") }
                static func note(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.note", vi: "Ghi chú", en: "Note", ja: "メモ", language: language) }
                static var notes: String { L10n.tr("shared.sync.mistiasync.notes", vi: "Ghi chú", en: "Notes", ja: "メモ") }
                static func notes(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.notes", vi: "Ghi chú", en: "Notes", ja: "メモ", language: language) }
                static var openingBalance: String { L10n.tr("shared.sync.mistiasync.openingBalance", vi: "Số dư đầu kỳ", en: "Opening balance", ja: "初期残高") }
                static func openingBalance(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.openingBalance", vi: "Số dư đầu kỳ", en: "Opening balance", ja: "初期残高", language: language) }
                static var paidAt: String { L10n.tr("shared.sync.mistiasync.paidAt", vi: "Đã trả lúc", en: "Paid at", ja: "支払い日時") }
                static func paidAt(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.paidAt", vi: "Đã trả lúc", en: "Paid at", ja: "支払い日時", language: language) }
                static var parentCategory: String { L10n.tr("shared.sync.mistiasync.parentCategory", vi: "Danh mục cha", en: "Parent category", ja: "親カテゴリ") }
                static func parentCategory(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.parentCategory", vi: "Danh mục cha", en: "Parent category", ja: "親カテゴリ", language: language) }
                static var parentSnapshot: String { L10n.tr("shared.sync.mistiasync.parentSnapshot", vi: "Ảnh chụp danh mục cha", en: "Parent snapshot", ja: "親カテゴリスナップショット") }
                static func parentSnapshot(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.parentSnapshot", vi: "Ảnh chụp danh mục cha", en: "Parent snapshot", ja: "親カテゴリスナップショット", language: language) }
                static var paused: String { L10n.tr("shared.sync.mistiasync.paused", vi: "Tạm dừng", en: "Paused", ja: "一時停止") }
                static func paused(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.paused", vi: "Tạm dừng", en: "Paused", ja: "一時停止", language: language) }
                static var pausedAt: String { L10n.tr("shared.sync.mistiasync.pausedAt", vi: "Tạm dừng lúc", en: "Paused at", ja: "一時停止日時") }
                static func pausedAt(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.pausedAt", vi: "Tạm dừng lúc", en: "Paused at", ja: "一時停止日時", language: language) }
                static var paymentWallet: String { L10n.tr("shared.sync.mistiasync.paymentWallet", vi: "Ví thanh toán", en: "Payment wallet", ja: "支払いウォレット") }
                static func paymentWallet(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.paymentWallet", vi: "Ví thanh toán", en: "Payment wallet", ja: "支払いウォレット", language: language) }
                static var restoreRecord: String { L10n.tr("shared.sync.mistiasync.restoreRecord", vi: "Khôi phục bản trên máy", en: "Restore record", ja: "この端末の内容を復元") }
                static func restoreRecord(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.restoreRecord", vi: "Khôi phục bản trên máy", en: "Restore record", ja: "この端末の内容を復元", language: language) }
                static var resumeStartMonth: String { L10n.tr("shared.sync.mistiasync.resumeStartMonth", vi: "Tháng bắt đầu lại", en: "Resume month", ja: "再開月") }
                static func resumeStartMonth(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.resumeStartMonth", vi: "Tháng bắt đầu lại", en: "Resume month", ja: "再開月", language: language) }
                static var rollover: String { L10n.tr("shared.sync.mistiasync.rollover", vi: "Chuyển dư", en: "Rollover", ja: "繰り越し") }
                static func rollover(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.rollover", vi: "Chuyển dư", en: "Rollover", ja: "繰り越し", language: language) }
                static var saved: String { L10n.tr("shared.sync.mistiasync.saved", vi: "Đã tiết kiệm", en: "Saved", ja: "貯蓄済み") }
                static func saved(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.saved", vi: "Đã tiết kiệm", en: "Saved", ja: "貯蓄済み", language: language) }
                static var scheduledDate: String { L10n.tr("shared.sync.mistiasync.scheduledDate", vi: "Ngày dự kiến", en: "Scheduled date", ja: "予定日") }
                static func scheduledDate(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.scheduledDate", vi: "Ngày dự kiến", en: "Scheduled date", ja: "予定日", language: language) }
                static var sortOrder: String { L10n.tr("shared.sync.mistiasync.sortOrder", vi: "Thứ tự", en: "Sort order", ja: "並び順") }
                static func sortOrder(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.sortOrder", vi: "Thứ tự", en: "Sort order", ja: "並び順", language: language) }
                static var source: String { L10n.tr("shared.sync.mistiasync.source", vi: "Nguồn", en: "Source", ja: "ソース") }
                static func source(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.source", vi: "Nguồn", en: "Source", ja: "ソース", language: language) }
                static var sourceWallet: String { L10n.tr("shared.sync.mistiasync.sourceWallet", vi: "Ví nguồn", en: "Source wallet", ja: "出金ウォレット") }
                static func sourceWallet(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.sourceWallet", vi: "Ví nguồn", en: "Source wallet", ja: "出金ウォレット", language: language) }
                static var status: String { L10n.tr("shared.sync.mistiasync.status", vi: "Trạng thái", en: "Status", ja: "状態") }
                static func status(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.status", vi: "Trạng thái", en: "Status", ja: "状態", language: language) }
                static var syncVersion: String { L10n.tr("shared.sync.mistiasync.syncVersion", vi: "Sync version", en: "Sync version", ja: "同期バージョン") }
                static func syncVersion(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.syncVersion", vi: "Sync version", en: "Sync version", ja: "同期バージョン", language: language) }
                static var systemCategory: String { L10n.tr("shared.sync.mistiasync.systemCategory", vi: "Danh mục hệ thống", en: "System category", ja: "システムカテゴリ") }
                static func systemCategory(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.systemCategory", vi: "Danh mục hệ thống", en: "System category", ja: "システムカテゴリ", language: language) }
                static var systemKey: String { L10n.tr("shared.sync.mistiasync.systemKey", vi: "Mã hệ thống", en: "System key", ja: "システムキー") }
                static func systemKey(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.systemKey", vi: "Mã hệ thống", en: "System key", ja: "システムキー", language: language) }
                static var target: String { L10n.tr("shared.sync.mistiasync.target", vi: "Mục tiêu", en: "Target", ja: "目標額") }
                static func target(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.target", vi: "Mục tiêu", en: "Target", ja: "目標額", language: language) }
                static var targetDate: String { L10n.tr("shared.sync.mistiasync.targetDate", vi: "Ngày mục tiêu", en: "Target date", ja: "目標日") }
                static func targetDate(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.targetDate", vi: "Ngày mục tiêu", en: "Target date", ja: "目標日", language: language) }
                static func targetValue(_ value: String) -> String {
                    L10n.format("shared.sync.mistiasync.targetValue", vi: "Mục tiêu %@", en: "Target %@", ja: "目標 %@", value)
                }
                static func targetValue(_ value: String, language: MistiaAppLanguage) -> String {
                    L10n.format("shared.sync.mistiasync.targetValue", vi: "Mục tiêu %@", en: "Target %@", ja: "目標 %@", language: language, value)
                }
                static var title: String { L10n.tr("shared.sync.mistiasync.title", vi: "Tiêu đề", en: "Title", ja: "タイトル") }
                static func title(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.title", vi: "Tiêu đề", en: "Title", ja: "タイトル", language: language) }
                static var transaction: String { L10n.tr("shared.sync.mistiasync.transaction", vi: "Thu chi", en: "Cashflow", ja: "収支") }
                static func transaction(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.transaction", vi: "Thu chi", en: "Cashflow", ja: "収支", language: language) }
                static var transaction2: String { L10n.tr("shared.sync.mistiasync.transaction2", vi: "Thu chi", en: "Cashflow", ja: "収支") }
                static func transaction2(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.transaction2", vi: "Thu chi", en: "Cashflow", ja: "収支", language: language) }
                static var transactionDate: String { L10n.tr("shared.sync.mistiasync.transactionDate", vi: "Ngày thu chi", en: "Cashflow date", ja: "取引日") }
                static func transactionDate(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.transactionDate", vi: "Ngày thu chi", en: "Cashflow date", ja: "取引日", language: language) }
                static var transactionType: String { L10n.tr("shared.sync.mistiasync.transactionType", vi: "Loại thu chi", en: "Cashflow type", ja: "取引種別") }
                static func transactionType(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.transactionType", vi: "Loại thu chi", en: "Cashflow type", ja: "取引種別", language: language) }
                static var transferSubtype: String { L10n.tr("shared.sync.mistiasync.transferSubtype", vi: "Nhánh chuyển khoản", en: "Transfer subtype", ja: "振替サブタイプ") }
                static func transferSubtype(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.transferSubtype", vi: "Nhánh chuyển khoản", en: "Transfer subtype", ja: "振替サブタイプ", language: language) }
                static var unnamedTransaction: String { L10n.tr("shared.sync.mistiasync.unnamedTransaction", vi: "Thu chi không tên", en: "Unnamed cashflow item", ja: "無名取引") }
                static func unnamedTransaction(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.unnamedTransaction", vi: "Thu chi không tên", en: "Unnamed cashflow item", ja: "無名取引", language: language) }
                static var unnamedTransaction2: String { L10n.tr("shared.sync.mistiasync.unnamedTransaction2", vi: "Thu chi không tên", en: "Unnamed cashflow item", ja: "無名取引") }
                static func unnamedTransaction2(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.unnamedTransaction2", vi: "Thu chi không tên", en: "Unnamed cashflow item", ja: "無名取引", language: language) }
                static var updatedAt: String { L10n.tr("shared.sync.mistiasync.updatedAt", vi: "Cập nhật lúc", en: "Updated at", ja: "更新日時") }
                static func updatedAt(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.updatedAt", vi: "Cập nhật lúc", en: "Updated at", ja: "更新日時", language: language) }
                static var useCloudVersion: String { L10n.tr("shared.sync.mistiasync.useCloudVersion", vi: "Dùng bản trên cloud", en: "Use cloud version", ja: "クラウドの内容を使う") }
                static func useCloudVersion(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.useCloudVersion", vi: "Dùng bản trên cloud", en: "Use cloud version", ja: "クラウドの内容を使う", language: language) }
                static var useThisDeviceSVersion: String { L10n.tr("shared.sync.mistiasync.useThisDeviceSVersion", vi: "Dùng bản trên máy này", en: "Use this device's version", ja: "この端末の内容を使う") }
                static func useThisDeviceSVersion(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.useThisDeviceSVersion", vi: "Dùng bản trên máy này", en: "Use this device's version", ja: "この端末の内容を使う", language: language) }
                static func valueCycles(_ value: String) -> String {
                    L10n.format("shared.sync.mistiasync.valueCycles", vi: "%@ kỳ", en: "%@ cycles", ja: "%@回", value)
                }
                static func valueCycles(_ value: String, language: MistiaAppLanguage) -> String {
                    L10n.format("shared.sync.mistiasync.valueCycles", vi: "%@ kỳ", en: "%@ cycles", ja: "%@回", language: language, value)
                }
                static var wallet: String { L10n.tr("shared.sync.mistiasync.wallet", vi: "Ví", en: "Wallet", ja: "ウォレット") }
                static func wallet(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.wallet", vi: "Ví", en: "Wallet", ja: "ウォレット", language: language) }
                static var wallet2: String { L10n.tr("shared.sync.mistiasync.wallet2", vi: "Ví", en: "Wallet", ja: "ウォレット") }
                static func wallet2(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.wallet2", vi: "Ví", en: "Wallet", ja: "ウォレット", language: language) }
                static var walletType: String { L10n.tr("shared.sync.mistiasync.walletType", vi: "Loại ví", en: "Wallet type", ja: "ウォレット種別") }
                static func walletType(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.walletType", vi: "Loại ví", en: "Wallet type", ja: "ウォレット種別", language: language) }
                static var yes: String { L10n.tr("shared.sync.mistiasync.yes", vi: "Có", en: "Yes", ja: "はい") }
                static func yes(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasync.yes", vi: "Có", en: "Yes", ja: "はい", language: language) }
            }

            nonisolated enum mistiasynccoordinator {
                static var aFamilyMember: String { L10n.tr("shared.sync.mistiasynccoordinator.aFamilyMember", vi: "Một thành viên", en: "A family member", ja: "家族メンバー") }
                static func aFamilyMember(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasynccoordinator.aFamilyMember", vi: "Một thành viên", en: "A family member", ja: "家族メンバー", language: language) }
                static var aTransaction: String { L10n.tr("shared.sync.mistiasynccoordinator.aTransaction", vi: "một khoản thu chi", en: "a cashflow item", ja: "収支") }
                static func aTransaction(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasynccoordinator.aTransaction", vi: "một khoản thu chi", en: "a cashflow item", ja: "収支", language: language) }
                static var billDeleted: String { L10n.tr("shared.sync.mistiasynccoordinator.billDeleted", vi: "Hóa đơn đã xóa", en: "Bill deleted", ja: "請求が削除されました") }
                static func billDeleted(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasynccoordinator.billDeleted", vi: "Hóa đơn đã xóa", en: "Bill deleted", ja: "請求が削除されました", language: language) }
                static var billUpdated: String { L10n.tr("shared.sync.mistiasynccoordinator.billUpdated", vi: "Hóa đơn đã cập nhật", en: "Bill updated", ja: "請求が更新されました") }
                static func billUpdated(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasynccoordinator.billUpdated", vi: "Hóa đơn đã cập nhật", en: "Bill updated", ja: "請求が更新されました", language: language) }
                static var budgetDeleted: String { L10n.tr("shared.sync.mistiasynccoordinator.budgetDeleted", vi: "Ngân sách đã xóa", en: "Budget deleted", ja: "予算が削除されました") }
                static func budgetDeleted(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasynccoordinator.budgetDeleted", vi: "Ngân sách đã xóa", en: "Budget deleted", ja: "予算が削除されました", language: language) }
                static var budgetUpdated: String { L10n.tr("shared.sync.mistiasynccoordinator.budgetUpdated", vi: "Ngân sách đã cập nhật", en: "Budget updated", ja: "予算が更新されました") }
                static func budgetUpdated(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasynccoordinator.budgetUpdated", vi: "Ngân sách đã cập nhật", en: "Budget updated", ja: "予算が更新されました", language: language) }
                static var categoryDeleted: String { L10n.tr("shared.sync.mistiasynccoordinator.categoryDeleted", vi: "Danh mục đã xóa", en: "Category deleted", ja: "カテゴリが削除されました") }
                static func categoryDeleted(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasynccoordinator.categoryDeleted", vi: "Danh mục đã xóa", en: "Category deleted", ja: "カテゴリが削除されました", language: language) }
                static var categoryUpdated: String { L10n.tr("shared.sync.mistiasynccoordinator.categoryUpdated", vi: "Danh mục đã cập nhật", en: "Category updated", ja: "カテゴリが更新されました") }
                static func categoryUpdated(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasynccoordinator.categoryUpdated", vi: "Danh mục đã cập nhật", en: "Category updated", ja: "カテゴリが更新されました", language: language) }
                static var cloudChangedRefreshRequired: String { L10n.tr("shared.sync.mistiasynccoordinator.cloudChangedRefreshRequired", vi: "Một số mục đã có bản mới hơn trên cloud. Làm mới dữ liệu đã đổi rồi thử lại; các thay đổi khác vẫn tiếp tục được đẩy.", en: "Some items have a newer cloud version. Refresh the changed data and try again; other changes continue to upload.", ja: "一部の項目はクラウド側に新しい版があります。変更されたデータを更新してから再試行してください。他の変更は引き続きアップロードされます。") }
                static func cloudChangedRefreshRequired(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasynccoordinator.cloudChangedRefreshRequired", vi: "Một số mục đã có bản mới hơn trên cloud. Làm mới dữ liệu đã đổi rồi thử lại; các thay đổi khác vẫn tiếp tục được đẩy.", en: "Some items have a newer cloud version. Refresh the changed data and try again; other changes continue to upload.", ja: "一部の項目はクラウド側に新しい版があります。変更されたデータを更新してから再試行してください。他の変更は引き続きアップロードされます。", language: language) }
                static func downloadedValueRecordsFromTheCloud(_ value: String) -> String {
                    L10n.format("shared.sync.mistiasynccoordinator.downloadedValueRecordsFromTheCloud", vi: "Đã nhận %@ bản ghi từ cloud.", en: "Downloaded %@ records from the cloud.", ja: "クラウドから %@ 件を取得しました。", value)
                }
                static func downloadedValueRecordsFromTheCloud(_ value: String, language: MistiaAppLanguage) -> String {
                    L10n.format("shared.sync.mistiasynccoordinator.downloadedValueRecordsFromTheCloud", vi: "Đã nhận %@ bản ghi từ cloud.", en: "Downloaded %@ records from the cloud.", ja: "クラウドから %@ 件を取得しました。", language: language, value)
                }
                static var familyActivity: String { L10n.tr("shared.sync.mistiasynccoordinator.familyActivity", vi: "Hoạt động gia đình", en: "Family activity", ja: "家族のアクティビティ") }
                static func familyActivity(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasynccoordinator.familyActivity", vi: "Hoạt động gia đình", en: "Family activity", ja: "家族のアクティビティ", language: language) }
                static var goalDeleted: String { L10n.tr("shared.sync.mistiasynccoordinator.goalDeleted", vi: "Mục tiêu đã xóa", en: "Goal deleted", ja: "目標が削除されました") }
                static func goalDeleted(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasynccoordinator.goalDeleted", vi: "Mục tiêu đã xóa", en: "Goal deleted", ja: "目標が削除されました", language: language) }
                static var goalUpdated: String { L10n.tr("shared.sync.mistiasynccoordinator.goalUpdated", vi: "Mục tiêu đã cập nhật", en: "Goal updated", ja: "目標が更新されました") }
                static func goalUpdated(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasynccoordinator.goalUpdated", vi: "Mục tiêu đã cập nhật", en: "Goal updated", ja: "目標が更新されました", language: language) }
                static var installmentDeleted: String { L10n.tr("shared.sync.mistiasynccoordinator.installmentDeleted", vi: "Trả góp đã xóa", en: "Installment deleted", ja: "分割払いが削除されました") }
                static func installmentDeleted(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasynccoordinator.installmentDeleted", vi: "Trả góp đã xóa", en: "Installment deleted", ja: "分割払いが削除されました", language: language) }
                static var installmentUpdated: String { L10n.tr("shared.sync.mistiasynccoordinator.installmentUpdated", vi: "Trả góp đã cập nhật", en: "Installment updated", ja: "分割払いが更新されました") }
                static func installmentUpdated(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasynccoordinator.installmentUpdated", vi: "Trả góp đã cập nhật", en: "Installment updated", ja: "分割払いが更新されました", language: language) }
                static var newTransaction: String { L10n.tr("shared.sync.mistiasynccoordinator.newTransaction", vi: "Thu chi mới", en: "New cashflow item", ja: "新しい取引") }
                static func newTransaction(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasynccoordinator.newTransaction", vi: "Thu chi mới", en: "New cashflow item", ja: "新しい取引", language: language) }
                static func syncCompletedAcrossValueRecords(_ value: String) -> String {
                    L10n.format("shared.sync.mistiasynccoordinator.syncCompletedAcrossValueRecords", vi: "Đồng bộ xong %@ bản ghi.", en: "Sync completed across %@ records.", ja: "%@ 件の同期が完了しました。", value)
                }
                static func syncCompletedAcrossValueRecords(_ value: String, language: MistiaAppLanguage) -> String {
                    L10n.format("shared.sync.mistiasynccoordinator.syncCompletedAcrossValueRecords", vi: "Đồng bộ xong %@ bản ghi.", en: "Sync completed across %@ records.", ja: "%@ 件の同期が完了しました。", language: language, value)
                }
                static var thereAreNoNewChangesToSync: String { L10n.tr("shared.sync.mistiasynccoordinator.thereAreNoNewChangesToSync", vi: "Không có thay đổi mới cần đồng bộ.", en: "There are no new changes to sync.", ja: "新しく同期する変更はありません。") }
                static func thereAreNoNewChangesToSync(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasynccoordinator.thereAreNoNewChangesToSync", vi: "Không có thay đổi mới cần đồng bộ.", en: "There are no new changes to sync.", ja: "新しく同期する変更はありません。", language: language) }
                static var transactionDeleted: String { L10n.tr("shared.sync.mistiasynccoordinator.transactionDeleted", vi: "Thu chi đã xóa", en: "Cashflow deleted", ja: "取引が削除されました") }
                static func transactionDeleted(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasynccoordinator.transactionDeleted", vi: "Thu chi đã xóa", en: "Cashflow deleted", ja: "取引が削除されました", language: language) }
                static var transactionUpdated: String { L10n.tr("shared.sync.mistiasynccoordinator.transactionUpdated", vi: "Thu chi đã cập nhật", en: "Cashflow updated", ja: "取引が更新されました") }
                static func transactionUpdated(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasynccoordinator.transactionUpdated", vi: "Thu chi đã cập nhật", en: "Cashflow updated", ja: "取引が更新されました", language: language) }
                static var uploadedLocalChangesToTheCloud: String { L10n.tr("shared.sync.mistiasynccoordinator.uploadedLocalChangesToTheCloud", vi: "Đã đẩy thay đổi local lên cloud.", en: "Uploaded local changes to the cloud.", ja: "ローカル変更をクラウドへアップロードしました。") }
                static func uploadedLocalChangesToTheCloud(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasynccoordinator.uploadedLocalChangesToTheCloud", vi: "Đã đẩy thay đổi local lên cloud.", en: "Uploaded local changes to the cloud.", ja: "ローカル変更をクラウドへアップロードしました。", language: language) }
                static func uploadedValueLocalRecordsToTheCloud(_ value: String) -> String {
                    L10n.format("shared.sync.mistiasynccoordinator.uploadedValueLocalRecordsToTheCloud", vi: "Đã đẩy %@ bản ghi local lên cloud.", en: "Uploaded %@ local records to the cloud.", ja: "ローカルの %@ 件をクラウドへアップロードしました。", value)
                }
                static func uploadedValueLocalRecordsToTheCloud(_ value: String, language: MistiaAppLanguage) -> String {
                    L10n.format("shared.sync.mistiasynccoordinator.uploadedValueLocalRecordsToTheCloud", vi: "Đã đẩy %@ bản ghi local lên cloud.", en: "Uploaded %@ local records to the cloud.", ja: "ローカルの %@ 件をクラウドへアップロードしました。", language: language, value)
                }
                static func valueChangedOneOfYourTransactions(_ value: String) -> String {
                    L10n.format("shared.sync.mistiasynccoordinator.valueChangedOneOfYourTransactions", vi: "%@ vừa thao tác trên thu chi của bạn.", en: "%@ changed one of your cashflow items.", ja: "%@があなたの取引を変更しました。", value)
                }
                static func valueChangedOneOfYourTransactions(_ value: String, language: MistiaAppLanguage) -> String {
                    L10n.format("shared.sync.mistiasynccoordinator.valueChangedOneOfYourTransactions", vi: "%@ vừa thao tác trên thu chi của bạn.", en: "%@ changed one of your cashflow items.", ja: "%@があなたの取引を変更しました。", language: language, value)
                }
                static func valueChangedYourData(_ value: String) -> String {
                    L10n.format("shared.sync.mistiasynccoordinator.valueChangedYourData", vi: "%@ vừa thao tác trên dữ liệu của bạn.", en: "%@ changed your data.", ja: "%@があなたのデータを変更しました。", value)
                }
                static func valueChangedYourData(_ value: String, language: MistiaAppLanguage) -> String {
                    L10n.format("shared.sync.mistiasynccoordinator.valueChangedYourData", vi: "%@ vừa thao tác trên dữ liệu của bạn.", en: "%@ changed your data.", ja: "%@があなたのデータを変更しました。", language: language, value)
                }
                static func valueDeletedValueOnYourWallet(_ arg1: String, _ arg2: String) -> String {
                    L10n.format("shared.sync.mistiasynccoordinator.valueDeletedValueOnYourWallet", vi: "%@ vừa xóa %@ trên ví của bạn.", en: "%@ deleted %@ on your wallet.", ja: "%@があなたのウォレットの%@を削除しました。", arg1, arg2)
                }
                static func valueDeletedValueOnYourWallet(_ arg1: String, _ arg2: String, language: MistiaAppLanguage) -> String {
                    L10n.format("shared.sync.mistiasynccoordinator.valueDeletedValueOnYourWallet", vi: "%@ vừa xóa %@ trên ví của bạn.", en: "%@ deleted %@ on your wallet.", ja: "%@があなたのウォレットの%@を削除しました。", language: language, arg1, arg2)
                }
                static func valueEditedValueOnYourWallet(_ arg1: String, _ arg2: String) -> String {
                    L10n.format("shared.sync.mistiasynccoordinator.valueEditedValueOnYourWallet", vi: "%@ vừa chỉnh sửa %@ trên ví của bạn.", en: "%@ edited %@ on your wallet.", ja: "%@があなたのウォレットの%@を編集しました。", arg1, arg2)
                }
                static func valueEditedValueOnYourWallet(_ arg1: String, _ arg2: String, language: MistiaAppLanguage) -> String {
                    L10n.format("shared.sync.mistiasynccoordinator.valueEditedValueOnYourWallet", vi: "%@ vừa chỉnh sửa %@ trên ví của bạn.", en: "%@ edited %@ on your wallet.", ja: "%@があなたのウォレットの%@を編集しました。", language: language, arg1, arg2)
                }
                static func valueUpdatedYourBudget(_ value: String) -> String {
                    L10n.format("shared.sync.mistiasynccoordinator.valueUpdatedYourBudget", vi: "%@ vừa cập nhật ngân sách của bạn.", en: "%@ updated your budget.", ja: "%@があなたの予算を更新しました。", value)
                }
                static func valueUpdatedYourBudget(_ value: String, language: MistiaAppLanguage) -> String {
                    L10n.format("shared.sync.mistiasynccoordinator.valueUpdatedYourBudget", vi: "%@ vừa cập nhật ngân sách của bạn.", en: "%@ updated your budget.", ja: "%@があなたの予算を更新しました。", language: language, value)
                }
                static func valueUpdatedYourValueBill(_ arg1: String, _ arg2: String) -> String {
                    L10n.format("shared.sync.mistiasynccoordinator.valueUpdatedYourValueBill", vi: "%@ vừa cập nhật hóa đơn %@ của bạn.", en: "%@ updated your %@ bill.", ja: "%@があなたの請求%@を更新しました。", arg1, arg2)
                }
                static func valueUpdatedYourValueBill(_ arg1: String, _ arg2: String, language: MistiaAppLanguage) -> String {
                    L10n.format("shared.sync.mistiasynccoordinator.valueUpdatedYourValueBill", vi: "%@ vừa cập nhật hóa đơn %@ của bạn.", en: "%@ updated your %@ bill.", ja: "%@があなたの請求%@を更新しました。", language: language, arg1, arg2)
                }
                static func valueUpdatedYourValueCategory(_ arg1: String, _ arg2: String) -> String {
                    L10n.format("shared.sync.mistiasynccoordinator.valueUpdatedYourValueCategory", vi: "%@ vừa cập nhật danh mục %@ của bạn.", en: "%@ updated your %@ category.", ja: "%@があなたのカテゴリ%@を更新しました。", arg1, arg2)
                }
                static func valueUpdatedYourValueCategory(_ arg1: String, _ arg2: String, language: MistiaAppLanguage) -> String {
                    L10n.format("shared.sync.mistiasynccoordinator.valueUpdatedYourValueCategory", vi: "%@ vừa cập nhật danh mục %@ của bạn.", en: "%@ updated your %@ category.", ja: "%@があなたのカテゴリ%@を更新しました。", language: language, arg1, arg2)
                }
                static func valueUpdatedYourValueGoal(_ arg1: String, _ arg2: String) -> String {
                    L10n.format("shared.sync.mistiasynccoordinator.valueUpdatedYourValueGoal", vi: "%@ vừa cập nhật mục tiêu %@ của bạn.", en: "%@ updated your %@ goal.", ja: "%@があなたの目標%@を更新しました。", arg1, arg2)
                }
                static func valueUpdatedYourValueGoal(_ arg1: String, _ arg2: String, language: MistiaAppLanguage) -> String {
                    L10n.format("shared.sync.mistiasynccoordinator.valueUpdatedYourValueGoal", vi: "%@ vừa cập nhật mục tiêu %@ của bạn.", en: "%@ updated your %@ goal.", ja: "%@があなたの目標%@を更新しました。", language: language, arg1, arg2)
                }
                static func valueUpdatedYourValueInstallment(_ arg1: String, _ arg2: String) -> String {
                    L10n.format("shared.sync.mistiasynccoordinator.valueUpdatedYourValueInstallment", vi: "%@ vừa cập nhật trả góp %@ của bạn.", en: "%@ updated your %@ installment.", ja: "%@があなたの分割払い%@を更新しました。", arg1, arg2)
                }
                static func valueUpdatedYourValueInstallment(_ arg1: String, _ arg2: String, language: MistiaAppLanguage) -> String {
                    L10n.format("shared.sync.mistiasynccoordinator.valueUpdatedYourValueInstallment", vi: "%@ vừa cập nhật trả góp %@ của bạn.", en: "%@ updated your %@ installment.", ja: "%@があなたの分割払い%@を更新しました。", language: language, arg1, arg2)
                }
                static func valueUpdatedYourValueWallet(_ arg1: String, _ arg2: String) -> String {
                    L10n.format("shared.sync.mistiasynccoordinator.valueUpdatedYourValueWallet", vi: "%@ vừa cập nhật ví %@ của bạn.", en: "%@ updated your %@ wallet.", ja: "%@があなたの%@ウォレットを更新しました。", arg1, arg2)
                }
                static func valueUpdatedYourValueWallet(_ arg1: String, _ arg2: String, language: MistiaAppLanguage) -> String {
                    L10n.format("shared.sync.mistiasynccoordinator.valueUpdatedYourValueWallet", vi: "%@ vừa cập nhật ví %@ của bạn.", en: "%@ updated your %@ wallet.", ja: "%@があなたの%@ウォレットを更新しました。", language: language, arg1, arg2)
                }
                static func valueUsedYourValueWalletToCreate(_ arg1: String, _ arg2: String, _ arg3: String) -> String {
                    L10n.format("shared.sync.mistiasynccoordinator.valueUsedYourValueWalletToCreate", vi: "%@ vừa sử dụng ví %@ của bạn để tạo %@.", en: "%@ used your %@ wallet to create %@.", ja: "%@があなたの%@ウォレットで%@を作成しました。", arg1, arg2, arg3)
                }
                static func valueUsedYourValueWalletToCreate(_ arg1: String, _ arg2: String, _ arg3: String, language: MistiaAppLanguage) -> String {
                    L10n.format("shared.sync.mistiasynccoordinator.valueUsedYourValueWalletToCreate", vi: "%@ vừa sử dụng ví %@ của bạn để tạo %@.", en: "%@ used your %@ wallet to create %@.", ja: "%@があなたの%@ウォレットで%@を作成しました。", language: language, arg1, arg2, arg3)
                }
                static func valueUsedYourWalletToCreateValue(_ arg1: String, _ arg2: String) -> String {
                    L10n.format("shared.sync.mistiasynccoordinator.valueUsedYourWalletToCreateValue", vi: "%@ vừa sử dụng ví của bạn để tạo %@.", en: "%@ used your wallet to create %@.", ja: "%@があなたのウォレットで%@を作成しました。", arg1, arg2)
                }
                static func valueUsedYourWalletToCreateValue(_ arg1: String, _ arg2: String, language: MistiaAppLanguage) -> String {
                    L10n.format("shared.sync.mistiasynccoordinator.valueUsedYourWalletToCreateValue", vi: "%@ vừa sử dụng ví của bạn để tạo %@.", en: "%@ used your wallet to create %@.", ja: "%@があなたのウォレットで%@を作成しました。", language: language, arg1, arg2)
                }
                static var walletDeleted: String { L10n.tr("shared.sync.mistiasynccoordinator.walletDeleted", vi: "Ví đã xóa", en: "Wallet deleted", ja: "ウォレットが削除されました") }
                static func walletDeleted(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasynccoordinator.walletDeleted", vi: "Ví đã xóa", en: "Wallet deleted", ja: "ウォレットが削除されました", language: language) }
                static var walletUpdated: String { L10n.tr("shared.sync.mistiasynccoordinator.walletUpdated", vi: "Ví đã cập nhật", en: "Wallet updated", ja: "ウォレットが更新されました") }
                static func walletUpdated(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.mistiasynccoordinator.walletUpdated", vi: "Ví đã cập nhật", en: "Wallet updated", ja: "ウォレットが更新されました", language: language) }
            }

            nonisolated enum receiptanalysis {
                static var couldnTAnalyzeThisReceiptRightNow: String { L10n.tr("shared.sync.receiptanalysis.couldnTAnalyzeThisReceiptRightNow", vi: "Không thể phân tích bill lúc này.", en: "Couldn't analyze this receipt right now.", ja: "現在レシートを解析できません。") }
                static func couldnTAnalyzeThisReceiptRightNow(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.receiptanalysis.couldnTAnalyzeThisReceiptRightNow", vi: "Không thể phân tích bill lúc này.", en: "Couldn't analyze this receipt right now.", ja: "現在レシートを解析できません。", language: language) }
                static var receiptAITookTooLongTryAgain: String { L10n.tr("shared.sync.receiptanalysis.receiptAITookTooLongTryAgain", vi: "AI đang mất quá lâu để phân tích bill. Hãy thử lại sau.", en: "Receipt AI is taking too long. Try again later.", ja: "レシートAIの解析に時間がかかりすぎています。しばらくしてからもう一度お試しください。") }
                static func receiptAITookTooLongTryAgain(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.receiptanalysis.receiptAITookTooLongTryAgain", vi: "AI đang mất quá lâu để phân tích bill. Hãy thử lại sau.", en: "Receipt AI is taking too long. Try again later.", ja: "レシートAIの解析に時間がかかりすぎています。しばらくしてからもう一度お試しください。", language: language) }
                static var requestTimedOutCheckNetwork: String { L10n.tr("shared.sync.receiptanalysis.requestTimedOutCheckNetwork", vi: "Mạng phản hồi quá chậm. Hãy kiểm tra kết nối và thử lại sau.", en: "The network was too slow to respond. Check your connection and try again.", ja: "ネットワークの応答が遅すぎます。接続を確認してからもう一度お試しください。") }
                static func requestTimedOutCheckNetwork(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.receiptanalysis.requestTimedOutCheckNetwork", vi: "Mạng phản hồi quá chậm. Hãy kiểm tra kết nối và thử lại sau.", en: "The network was too slow to respond. Check your connection and try again.", ja: "ネットワークの応答が遅すぎます。接続を確認してからもう一度お試しください。", language: language) }
                static var signInToAnalyzeReceipts: String { L10n.tr("shared.sync.receiptanalysis.signInToAnalyzeReceipts", vi: "Bạn cần đăng nhập để phân tích bill.", en: "Sign in to analyze receipts.", ja: "レシート解析にはサインインが必要です。") }
                static func signInToAnalyzeReceipts(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.receiptanalysis.signInToAnalyzeReceipts", vi: "Bạn cần đăng nhập để phân tích bill.", en: "Sign in to analyze receipts.", ja: "レシート解析にはサインインが必要です。", language: language) }
                static var theNextDailyReset: String { L10n.tr("shared.sync.receiptanalysis.theNextDailyReset", vi: "lần reset ngày tiếp theo", en: "the next daily reset", ja: "次の日次リセット") }
                static func theNextDailyReset(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.receiptanalysis.theNextDailyReset", vi: "lần reset ngày tiếp theo", en: "the next daily reset", ja: "次の日次リセット", language: language) }
                static var theReceiptImageIsTooLargeChoose: String { L10n.tr("shared.sync.receiptanalysis.theReceiptImageIsTooLargeChoose", vi: "Ảnh bill quá lớn. Hãy chọn ảnh rõ hơn nhưng nhẹ hơn.", en: "The receipt image is too large. Choose a clearer, smaller image.", ja: "レシート画像が大きすぎます。より軽い画像を選択してください。") }
                static func theReceiptImageIsTooLargeChoose(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.receiptanalysis.theReceiptImageIsTooLargeChoose", vi: "Ảnh bill quá lớn. Hãy chọn ảnh rõ hơn nhưng nhẹ hơn.", en: "The receipt image is too large. Choose a clearer, smaller image.", ja: "レシート画像が大きすぎます。より軽い画像を選択してください。", language: language) }
                static var unstableNetworkTryAgain: String { L10n.tr("shared.sync.receiptanalysis.unstableNetworkTryAgain", vi: "Kết nối mạng không ổn định. Hãy kiểm tra mạng và thử lại sau.", en: "The network connection is unstable. Check your connection and try again.", ja: "ネットワーク接続が不安定です。接続を確認してからもう一度お試しください。") }
                static func unstableNetworkTryAgain(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.receiptanalysis.unstableNetworkTryAgain", vi: "Kết nối mạng không ổn định. Hãy kiểm tra mạng và thử lại sau.", en: "The network connection is unstable. Check your connection and try again.", ja: "ネットワーク接続が不安定です。接続を確認してからもう一度お試しください。", language: language) }
                static func youVeReachedTodaySReceiptScan(_ value: String) -> String {
                    L10n.format("shared.sync.receiptanalysis.youVeReachedTodaySReceiptScan", vi: "Bạn đã đạt giới hạn quét bill hôm nay. Vui lòng thử lại sau %@.", en: "You've reached today's receipt scan limit. Try again after %@.", ja: "本日のレシート読み取り上限に達しました。%@ 以降にもう一度お試しください。", value)
                }
                static func youVeReachedTodaySReceiptScan(_ value: String, language: MistiaAppLanguage) -> String {
                    L10n.format("shared.sync.receiptanalysis.youVeReachedTodaySReceiptScan", vi: "Bạn đã đạt giới hạn quét bill hôm nay. Vui lòng thử lại sau %@.", en: "You've reached today's receipt scan limit. Try again after %@.", ja: "本日のレシート読み取り上限に達しました。%@ 以降にもう一度お試しください。", language: language, value)
                }
                static var youVeReachedTodaySReceiptScan2: String { L10n.tr("shared.sync.receiptanalysis.youVeReachedTodaySReceiptScan2", vi: "Bạn đã đạt giới hạn quét bill hôm nay. Vui lòng thử lại sau thời điểm reset ngày.", en: "You've reached today's receipt scan limit. Try again after the daily reset.", ja: "本日のレシート読み取り上限に達しました。日次リセット後にもう一度お試しください。") }
                static func youVeReachedTodaySReceiptScan2(language: MistiaAppLanguage) -> String { L10n.tr("shared.sync.receiptanalysis.youVeReachedTodaySReceiptScan2", vi: "Bạn đã đạt giới hạn quét bill hôm nay. Vui lòng thử lại sau thời điểm reset ngày.", en: "You've reached today's receipt scan limit. Try again after the daily reset.", ja: "本日のレシート読み取り上限に達しました。日次リセット後にもう一度お試しください。", language: language) }
            }
        }
    }

    nonisolated enum transactions {

        nonisolated enum aibill {
            static var addBills: String { L10n.tr("transactions.aibill.addBills", vi: "Thêm bill", en: "Add bills", ja: "レシートを追加") }
            static func addBills(language: MistiaAppLanguage) -> String { L10n.tr("transactions.aibill.addBills", vi: "Thêm bill", en: "Add bills", ja: "レシートを追加", language: language) }
            static var aiBill: String { L10n.tr("transactions.aibill.aiBill", vi: "Phân tích bill", en: "Receipt Analysis", ja: "レシート解析") }
            static func aiBill(language: MistiaAppLanguage) -> String { L10n.tr("transactions.aibill.aiBill", vi: "Phân tích bill", en: "Receipt Analysis", ja: "レシート解析", language: language) }
            static var allocateDiscount: String { L10n.tr("transactions.aibill.allocateDiscount", vi: "Phân bổ tỷ lệ", en: "Allocate proportionally", ja: "按分") }
            static func allocateDiscount(language: MistiaAppLanguage) -> String { L10n.tr("transactions.aibill.allocateDiscount", vi: "Phân bổ tỷ lệ", en: "Allocate proportionally", ja: "按分", language: language) }
            static var allocated: String { L10n.tr("transactions.aibill.allocated", vi: "Đã phân bổ", en: "Allocated", ja: "按分済み") }
            static func allocated(language: MistiaAppLanguage) -> String { L10n.tr("transactions.aibill.allocated", vi: "Đã phân bổ", en: "Allocated", ja: "按分済み", language: language) }
            static var analyze: String { L10n.tr("transactions.aibill.analyze", vi: "Phân tích", en: "Analyze", ja: "解析") }
            static func analyze(language: MistiaAppLanguage) -> String { L10n.tr("transactions.aibill.analyze", vi: "Phân tích", en: "Analyze", ja: "解析", language: language) }
            static var analyzing: String { L10n.tr("transactions.aibill.analyzing", vi: "Đang phân tích...", en: "Analyzing...", ja: "解析中...") }
            static func analyzing(language: MistiaAppLanguage) -> String { L10n.tr("transactions.aibill.analyzing", vi: "Đang phân tích...", en: "Analyzing...", ja: "解析中...", language: language) }
            static func billValue(_ value: String) -> String {
                L10n.format("transactions.aibill.billValue", vi: "Bill %@", en: "Bill %@", ja: "レシート %@", value)
            }
            static func billValue(_ value: String, language: MistiaAppLanguage) -> String {
                L10n.format("transactions.aibill.billValue", vi: "Bill %@", en: "Bill %@", ja: "レシート %@", language: language, value)
            }
            static var createTransaction: String { L10n.tr("transactions.aibill.createTransaction", vi: "Thêm", en: "Add", ja: "追加") }
            static func createTransaction(language: MistiaAppLanguage) -> String { L10n.tr("transactions.aibill.createTransaction", vi: "Thêm", en: "Add", ja: "追加", language: language) }
            static var created: String { L10n.tr("transactions.aibill.created", vi: "Đã tạo", en: "Created", ja: "作成済み") }
            static func created(language: MistiaAppLanguage) -> String { L10n.tr("transactions.aibill.created", vi: "Đã tạo", en: "Created", ja: "作成済み", language: language) }
            static var discardAnalysis: String { L10n.tr("transactions.aibill.discardAnalysis", vi: "Thoát", en: "Leave", ja: "閉じる") }
            static func discardAnalysis(language: MistiaAppLanguage) -> String { L10n.tr("transactions.aibill.discardAnalysis", vi: "Thoát", en: "Leave", ja: "閉じる", language: language) }
            static var discountLine: String { L10n.tr("transactions.aibill.discountLine", vi: "Giảm giá", en: "Discount", ja: "値引") }
            static func discountLine(language: MistiaAppLanguage) -> String { L10n.tr("transactions.aibill.discountLine", vi: "Giảm giá", en: "Discount", ja: "値引", language: language) }
            static var imageContainsMultipleBills: String { L10n.tr("transactions.aibill.imageContainsMultipleBills", vi: "Ảnh này có vẻ chứa nhiều bill. Hãy tách ra mỗi ảnh một bill rồi gửi lại.", en: "This image appears to contain multiple receipts. Split them into one receipt per image and try again.", ja: "この画像には複数のレシートが含まれているようです。1枚につき1つのレシートに分けて再度送信してください。") }
            static func imageContainsMultipleBills(language: MistiaAppLanguage) -> String { L10n.tr("transactions.aibill.imageContainsMultipleBills", vi: "Ảnh này có vẻ chứa nhiều bill. Hãy tách ra mỗi ảnh một bill rồi gửi lại.", en: "This image appears to contain multiple receipts. Split them into one receipt per image and try again.", ja: "この画像には複数のレシートが含まれているようです。1枚につき1つのレシートに分けて再度送信してください。", language: language) }
            static var locked: String { L10n.tr("transactions.aibill.locked", vi: "Đã chốt", en: "Locked", ja: "確定済み") }
            static func locked(language: MistiaAppLanguage) -> String { L10n.tr("transactions.aibill.locked", vi: "Đã chốt", en: "Locked", ja: "確定済み", language: language) }
            static func lockedGroupValue(_ value: String) -> String {
                L10n.format("transactions.aibill.lockedGroupValue", vi: "Đã chốt %@", en: "Locked %@", ja: "%@ 確定済み", value)
            }
            static func lockedGroupValue(_ value: String, language: MistiaAppLanguage) -> String {
                L10n.format("transactions.aibill.lockedGroupValue", vi: "Đã chốt %@", en: "Locked %@", ja: "%@ 確定済み", language: language, value)
            }
            static var noBillsMessage: String { L10n.tr("transactions.aibill.noBillsMessage", vi: "Thêm tối đa 5 ảnh bill để AI tách từng mục đã mua.", en: "Add up to 5 receipt images for AI to split items.", ja: "最大5枚のレシートを追加してAIで明細を分けます。") }
            static func noBillsMessage(language: MistiaAppLanguage) -> String { L10n.tr("transactions.aibill.noBillsMessage", vi: "Thêm tối đa 5 ảnh bill để AI tách từng mục đã mua.", en: "Add up to 5 receipt images for AI to split items.", ja: "最大5枚のレシートを追加してAIで明細を分けます。", language: language) }
            static var noBillsTitle: String { L10n.tr("transactions.aibill.noBillsTitle", vi: "Chưa có bill", en: "No receipts yet", ja: "レシートがありません") }
            static func noBillsTitle(language: MistiaAppLanguage) -> String { L10n.tr("transactions.aibill.noBillsTitle", vi: "Chưa có bill", en: "No receipts yet", ja: "レシートがありません", language: language) }
            static var noSelectableItems: String { L10n.tr("transactions.aibill.noSelectableItems", vi: "Chọn các mục hợp lệ để tạo khoản thu chi.", en: "Select valid items to create a cashflow item.", ja: "有効な項目を選んで取引を作成してください。") }
            static func noSelectableItems(language: MistiaAppLanguage) -> String { L10n.tr("transactions.aibill.noSelectableItems", vi: "Chọn các mục hợp lệ để tạo khoản thu chi.", en: "Select valid items to create a cashflow item.", ja: "有効な項目を選んで取引を作成してください。", language: language) }
            static func remainingAmountValue(_ value: String) -> String {
                L10n.format("transactions.aibill.remainingAmountValue", vi: "Còn lại %@", en: "Remaining %@", ja: "残り %@", value)
            }
            static func remainingAmountValue(_ value: String, language: MistiaAppLanguage) -> String {
                L10n.format("transactions.aibill.remainingAmountValue", vi: "Còn lại %@", en: "Remaining %@", ja: "残り %@", language: language, value)
            }
            static var resultsWillBeLost: String { L10n.tr("transactions.aibill.resultsWillBeLost", vi: "Dữ liệu phân tích sẽ mất nếu bạn thoát màn này.", en: "Analysis data will be lost if you leave this screen.", ja: "この画面を閉じると解析データは失われます。") }
            static func resultsWillBeLost(language: MistiaAppLanguage) -> String { L10n.tr("transactions.aibill.resultsWillBeLost", vi: "Dữ liệu phân tích sẽ mất nếu bạn thoát màn này.", en: "Analysis data will be lost if you leave this screen.", ja: "この画面を閉じると解析データは失われます。", language: language) }
            static func selectedAmountValue(_ value: String) -> String {
                L10n.format("transactions.aibill.selectedAmountValue", vi: "Tổng chọn %@", en: "Selected %@", ja: "選択 %@", value)
            }
            static func selectedAmountValue(_ value: String, language: MistiaAppLanguage) -> String {
                L10n.format("transactions.aibill.selectedAmountValue", vi: "Tổng chọn %@", en: "Selected %@", ja: "選択 %@", language: language, value)
            }
            static var stayHere: String { L10n.tr("transactions.aibill.stayHere", vi: "Ở lại", en: "Stay", ja: "このまま") }
            static func stayHere(language: MistiaAppLanguage) -> String { L10n.tr("transactions.aibill.stayHere", vi: "Ở lại", en: "Stay", ja: "このまま", language: language) }
            static func tooManyImages(_ value: String) -> String {
                L10n.format("transactions.aibill.tooManyImages", vi: "Mỗi lần chỉ chọn tối đa %@ ảnh bill.", en: "Choose no more than %@ receipt images at a time.", ja: "一度に選択できるレシート画像は %@ 枚までです。", value)
            }
            static func tooManyImages(_ value: String, language: MistiaAppLanguage) -> String {
                L10n.format("transactions.aibill.tooManyImages", vi: "Mỗi lần chỉ chọn tối đa %@ ảnh bill.", en: "Choose no more than %@ receipt images at a time.", ja: "一度に選択できるレシート画像は %@ 枚までです。", language: language, value)
            }
            static var walletForBill: String { L10n.tr("transactions.aibill.walletForBill", vi: "Ví của bill", en: "Receipt wallet", ja: "レシートのウォレット") }
            static func walletForBill(language: MistiaAppLanguage) -> String { L10n.tr("transactions.aibill.walletForBill", vi: "Ví của bill", en: "Receipt wallet", ja: "レシートのウォレット", language: language) }
        }

        nonisolated enum debtsettlement {
            static var amountExceedsOutstanding: String { L10n.tr("transactions.debtsettlement.amountExceedsOutstanding", vi: "Số tiền không được lớn hơn khoản đang mở.", en: "The amount cannot be greater than the open loan balance.", ja: "金額は未決済の債務を超えられません。") }
            static func amountExceedsOutstanding(language: MistiaAppLanguage) -> String { L10n.tr("transactions.debtsettlement.amountExceedsOutstanding", vi: "Số tiền không được lớn hơn khoản đang mở.", en: "The amount cannot be greater than the open loan balance.", ja: "金額は未決済の債務を超えられません。", language: language) }
            static var detail: String { L10n.tr("transactions.debtsettlement.detail", vi: "Chi tiết", en: "Details", ja: "詳細") }
            static func detail(language: MistiaAppLanguage) -> String { L10n.tr("transactions.debtsettlement.detail", vi: "Chi tiết", en: "Details", ja: "詳細", language: language) }
        }

        nonisolated enum generatedTitle {
            static var balanceAdjustment: String { L10n.tr("transactions.generatedTitle.balanceAdjustment", vi: "Điều chỉnh số dư", en: "Balance adjustment", ja: "残高調整") }
            static func balanceAdjustment(language: MistiaAppLanguage) -> String { L10n.tr("transactions.generatedTitle.balanceAdjustment", vi: "Điều chỉnh số dư", en: "Balance adjustment", ja: "残高調整", language: language) }
            static var familyTransferReceived: String { L10n.tr("transactions.generatedTitle.familyTransferReceived", vi: "Nhận tiền gia đình", en: "Family transfer received", ja: "家族送金の受け取り") }
            static func familyTransferReceived(language: MistiaAppLanguage) -> String { L10n.tr("transactions.generatedTitle.familyTransferReceived", vi: "Nhận tiền gia đình", en: "Family transfer received", ja: "家族送金の受け取り", language: language) }
            static var familyTransferSent: String { L10n.tr("transactions.generatedTitle.familyTransferSent", vi: "Chuyển tiền gia đình", en: "Family transfer sent", ja: "家族送金") }
            static func familyTransferSent(language: MistiaAppLanguage) -> String { L10n.tr("transactions.generatedTitle.familyTransferSent", vi: "Chuyển tiền gia đình", en: "Family transfer sent", ja: "家族送金", language: language) }
        }

        nonisolated enum settlement {
            static var addExpense: String { L10n.tr("transactions.settlement.addExpense", vi: "Thêm chi tiêu", en: "Add expense", ja: "支出を追加") }
            static func addExpense(language: MistiaAppLanguage) -> String { L10n.tr("transactions.settlement.addExpense", vi: "Thêm chi tiêu", en: "Add expense", ja: "支出を追加", language: language) }
            static var addExpenseToEvent: String { L10n.tr("transactions.settlement.addExpenseToEvent", vi: "Thêm chi tiêu vào sự kiện", en: "Add expense to event", ja: "イベントに支出を追加") }
            static func addExpenseToEvent(language: MistiaAppLanguage) -> String { L10n.tr("transactions.settlement.addExpenseToEvent", vi: "Thêm chi tiêu vào sự kiện", en: "Add expense to event", ja: "イベントに支出を追加", language: language) }
            static var addExpensesToTrackEventCost: String { L10n.tr("transactions.settlement.addExpensesToTrackEventCost", vi: "Thêm chi tiêu mới hoặc chọn chi tiêu có sẵn để lưu chi phí bạn đã trả cho sự kiện.", en: "Add a new expense or choose an existing expense to track what you paid for this event.", ja: "新しい支出を追加するか、既存の支出を選んで、このイベントで支払った金額を記録します。") }
            static func addExpensesToTrackEventCost(language: MistiaAppLanguage) -> String { L10n.tr("transactions.settlement.addExpensesToTrackEventCost", vi: "Thêm chi tiêu mới hoặc chọn chi tiêu có sẵn để lưu chi phí bạn đã trả cho sự kiện.", en: "Add a new expense or choose an existing expense to track what you paid for this event.", ja: "新しい支出を追加するか、既存の支出を選んで、このイベントで支払った金額を記録します。", language: language) }
            static var addNewExpense: String { L10n.tr("transactions.settlement.addNewExpense", vi: "Thêm chi tiêu mới", en: "New expense", ja: "新しい支出") }
            static func addNewExpense(language: MistiaAppLanguage) -> String { L10n.tr("transactions.settlement.addNewExpense", vi: "Thêm chi tiêu mới", en: "New expense", ja: "新しい支出", language: language) }
            static var addParticipant: String { L10n.tr("transactions.settlement.addParticipant", vi: "Thêm người", en: "Add person", ja: "人を追加") }
            static func addParticipant(language: MistiaAppLanguage) -> String { L10n.tr("transactions.settlement.addParticipant", vi: "Thêm người", en: "Add person", ja: "人を追加", language: language) }
            static var addParticipantsInEventEditor: String { L10n.tr("transactions.settlement.addParticipantsInEventEditor", vi: "Thêm người tham gia trong sự kiện trước khi chia chi phí.", en: "Add participants to the event before splitting costs.", ja: "費用を分ける前に、イベントに参加者を追加してください。") }
            static func addParticipantsInEventEditor(language: MistiaAppLanguage) -> String { L10n.tr("transactions.settlement.addParticipantsInEventEditor", vi: "Thêm người tham gia trong sự kiện trước khi chia chi phí.", en: "Add participants to the event before splitting costs.", ja: "費用を分ける前に、イベントに参加者を追加してください。", language: language) }
            static var addSharedExpense: String { L10n.tr("transactions.settlement.addSharedExpense", vi: "Sự kiện", en: "Event", ja: "イベント") }
            static func addSharedExpense(language: MistiaAppLanguage) -> String { L10n.tr("transactions.settlement.addSharedExpense", vi: "Sự kiện", en: "Event", ja: "イベント", language: language) }
            static var amount: String { L10n.tr("transactions.settlement.amount", vi: "Số tiền", en: "Amount", ja: "金額") }
            static func amount(language: MistiaAppLanguage) -> String { L10n.tr("transactions.settlement.amount", vi: "Số tiền", en: "Amount", ja: "金額", language: language) }
            static var archiveEvent: String { L10n.tr("transactions.settlement.archiveEvent", vi: "Lưu trữ sự kiện", en: "Archive event", ja: "イベントをアーカイブ") }
            static func archiveEvent(language: MistiaAppLanguage) -> String { L10n.tr("transactions.settlement.archiveEvent", vi: "Lưu trữ sự kiện", en: "Archive event", ja: "イベントをアーカイブ", language: language) }
            static var archiveEventDescription: String { L10n.tr("transactions.settlement.archiveEventDescription", vi: "Sự kiện sẽ được chuyển vào Mục đã lưu trữ. Các thu chi liên kết vẫn ở màn Thu chi nhưng không còn hiển thị badge sự kiện.", en: "The event will move to Archived items. Linked expenses stay in Cashflow without the event badge.", ja: "イベントはアーカイブ済みアイテムへ移動します。関連する支出はイベントバッジなしで収支に残ります。") }
            static func archiveEventDescription(language: MistiaAppLanguage) -> String { L10n.tr("transactions.settlement.archiveEventDescription", vi: "Sự kiện sẽ được chuyển vào Mục đã lưu trữ. Các thu chi liên kết vẫn ở màn Thu chi nhưng không còn hiển thị badge sự kiện.", en: "The event will move to Archived items. Linked expenses stay in Cashflow without the event badge.", ja: "イベントはアーカイブ済みアイテムへ移動します。関連する支出はイベントバッジなしで収支に残ります。", language: language) }
            static var archiveEventMessage: String { L10n.tr("transactions.settlement.archiveEventMessage", vi: "Lưu trữ sự kiện này? Các thu chi liên kết vẫn được giữ trong Thu chi, còn các giao dịch thanh toán tự động của sự kiện sẽ được ẩn cho đến khi khôi phục.", en: "Archive this event? Linked expenses stay in Cashflow, and event-generated settlement transactions are hidden until the event is restored.", ja: "このイベントをアーカイブしますか？関連する支出は収支に残り、イベントから作成された精算取引は復元するまで非表示になります。") }
            static func archiveEventMessage(language: MistiaAppLanguage) -> String { L10n.tr("transactions.settlement.archiveEventMessage", vi: "Lưu trữ sự kiện này? Các thu chi liên kết vẫn được giữ trong Thu chi, còn các giao dịch thanh toán tự động của sự kiện sẽ được ẩn cho đến khi khôi phục.", en: "Archive this event? Linked expenses stay in Cashflow, and event-generated settlement transactions are hidden until the event is restored.", ja: "このイベントをアーカイブしますか？関連する支出は収支に残り、イベントから作成された精算取引は復元するまで非表示になります。", language: language) }
            static func billCountValue(_ value: String) -> String {
                L10n.format("transactions.settlement.billCountValue", vi: "%@ bill", en: "%@ bills", ja: "%@ 件", value)
            }
            static func billCountValue(_ value: String, language: MistiaAppLanguage) -> String {
                L10n.format("transactions.settlement.billCountValue", vi: "%@ bill", en: "%@ bills", ja: "%@ 件", language: language, value)
            }
            static var category: String { L10n.tr("transactions.settlement.category", vi: "Danh mục", en: "Category", ja: "カテゴリ") }
            static func category(language: MistiaAppLanguage) -> String { L10n.tr("transactions.settlement.category", vi: "Danh mục", en: "Category", ja: "カテゴリ", language: language) }
            static var chooseExistingExpense: String { L10n.tr("transactions.settlement.chooseExistingExpense", vi: "Chọn chi tiêu có sẵn", en: "Existing expense", ja: "既存の支出") }
            static func chooseExistingExpense(language: MistiaAppLanguage) -> String { L10n.tr("transactions.settlement.chooseExistingExpense", vi: "Chọn chi tiêu có sẵn", en: "Existing expense", ja: "既存の支出", language: language) }
            static var completedEvents: String { L10n.tr("transactions.settlement.completedEvents", vi: "Sự kiện đã hoàn tất", en: "Completed events", ja: "完了したイベント") }
            static func completedEvents(language: MistiaAppLanguage) -> String { L10n.tr("transactions.settlement.completedEvents", vi: "Sự kiện đã hoàn tất", en: "Completed events", ja: "完了したイベント", language: language) }
            static var debtFullySettled: String { L10n.tr("transactions.settlement.debtFullySettled", vi: "Khoản nợ này đã được thanh toán hoàn tất", en: "This debt has been fully settled", ja: "この負債は精算済みです") }
            static func debtFullySettled(language: MistiaAppLanguage) -> String { L10n.tr("transactions.settlement.debtFullySettled", vi: "Khoản nợ này đã được thanh toán hoàn tất", en: "This debt has been fully settled", ja: "この負債は精算済みです", language: language) }
            static func editDebtAmount(_ value: String) -> String {
                L10n.format("transactions.settlement.editDebtAmount", vi: "Sửa khoản nợ của %@", en: "Edit %@ debt amount", ja: "%@ の債務額を編集", value)
            }
            static func editDebtAmount(_ value: String, language: MistiaAppLanguage) -> String {
                L10n.format("transactions.settlement.editDebtAmount", vi: "Sửa khoản nợ của %@", en: "Edit %@ debt amount", ja: "%@ の債務額を編集", language: language, value)
            }
            static var editEventTitle: String { L10n.tr("transactions.settlement.editEventTitle", vi: "Sửa sự kiện", en: "Edit event", ja: "イベントを編集") }
            static func editEventTitle(language: MistiaAppLanguage) -> String { L10n.tr("transactions.settlement.editEventTitle", vi: "Sửa sự kiện", en: "Edit event", ja: "イベントを編集", language: language) }
            static var enterAllParticipantAmounts: String { L10n.tr("transactions.settlement.enterAllParticipantAmounts", vi: "Vui lòng nhập số tiền cho tất cả người tham gia để chia chi phí.", en: "Enter amounts for all participants before splitting expenses.", ja: "費用を分ける前に、すべての参加者の金額を入力してください。") }
            static func enterAllParticipantAmounts(language: MistiaAppLanguage) -> String { L10n.tr("transactions.settlement.enterAllParticipantAmounts", vi: "Vui lòng nhập số tiền cho tất cả người tham gia để chia chi phí.", en: "Enter amounts for all participants before splitting expenses.", ja: "費用を分ける前に、すべての参加者の金額を入力してください。", language: language) }
            static var enterAmountsGreaterThanZero: String { L10n.tr("transactions.settlement.enterAmountsGreaterThanZero", vi: "Nhập số tiền lớn hơn 0.", en: "Enter amounts greater than 0.", ja: "0 より大きい金額を入力してください。") }
            static func enterAmountsGreaterThanZero(language: MistiaAppLanguage) -> String { L10n.tr("transactions.settlement.enterAmountsGreaterThanZero", vi: "Nhập số tiền lớn hơn 0.", en: "Enter amounts greater than 0.", ja: "0 より大きい金額を入力してください。", language: language) }
            static var enterEventName: String { L10n.tr("transactions.settlement.enterEventName", vi: "Nhập tên sự kiện.", en: "Enter the event name.", ja: "イベント名を入力してください。") }
            static func enterEventName(language: MistiaAppLanguage) -> String { L10n.tr("transactions.settlement.enterEventName", vi: "Nhập tên sự kiện.", en: "Enter the event name.", ja: "イベント名を入力してください。", language: language) }
            static var enterParticipant: String { L10n.tr("transactions.settlement.enterParticipant", vi: "Thêm ít nhất một người tham gia.", en: "Add at least one participant.", ja: "参加者を 1 人以上追加してください。") }
            static func enterParticipant(language: MistiaAppLanguage) -> String { L10n.tr("transactions.settlement.enterParticipant", vi: "Thêm ít nhất một người tham gia.", en: "Add at least one participant.", ja: "参加者を 1 人以上追加してください。", language: language) }
            static var eventBills: String { L10n.tr("transactions.settlement.eventBills", vi: "Chi tiêu của sự kiện", en: "Event expenses", ja: "イベント支出") }
            static func eventBills(language: MistiaAppLanguage) -> String { L10n.tr("transactions.settlement.eventBills", vi: "Chi tiêu của sự kiện", en: "Event expenses", ja: "イベント支出", language: language) }
            static var eventDetailsTitle: String { L10n.tr("transactions.settlement.eventDetailsTitle", vi: "Chi tiết sự kiện", en: "Event details", ja: "イベント詳細") }
            static func eventDetailsTitle(language: MistiaAppLanguage) -> String { L10n.tr("transactions.settlement.eventDetailsTitle", vi: "Chi tiết sự kiện", en: "Event details", ja: "イベント詳細", language: language) }
            static var eventName: String { L10n.tr("transactions.settlement.eventName", vi: "Tên sự kiện", en: "Event name", ja: "イベント名") }
            static func eventName(language: MistiaAppLanguage) -> String { L10n.tr("transactions.settlement.eventName", vi: "Tên sự kiện", en: "Event name", ja: "イベント名", language: language) }
            static var eventTitle: String { L10n.tr("transactions.settlement.eventTitle", vi: "Sự kiện", en: "Event", ja: "イベント") }
            static func eventTitle(language: MistiaAppLanguage) -> String { L10n.tr("transactions.settlement.eventTitle", vi: "Sự kiện", en: "Event", ja: "イベント", language: language) }
            static var noBillsYet: String { L10n.tr("transactions.settlement.noBillsYet", vi: "Chưa có chi tiêu", en: "No expenses yet", ja: "支出はまだありません") }
            static func noBillsYet(language: MistiaAppLanguage) -> String { L10n.tr("transactions.settlement.noBillsYet", vi: "Chưa có chi tiêu", en: "No expenses yet", ja: "支出はまだありません", language: language) }
            static var noEventsYet: String { L10n.tr("transactions.settlement.noEventsYet", vi: "Chưa có sự kiện nào", en: "No events yet", ja: "イベントはまだありません") }
            static func noEventsYet(language: MistiaAppLanguage) -> String { L10n.tr("transactions.settlement.noEventsYet", vi: "Chưa có sự kiện nào", en: "No events yet", ja: "イベントはまだありません", language: language) }
            static var noEventsYetMessage: String { L10n.tr("transactions.settlement.noEventsYetMessage", vi: "Các sự kiện chia chi phí sẽ xuất hiện ở đây.", en: "Split-expense events will appear here.", ja: "割り勘イベントはここに表示されます。") }
            static func noEventsYetMessage(language: MistiaAppLanguage) -> String { L10n.tr("transactions.settlement.noEventsYetMessage", vi: "Các sự kiện chia chi phí sẽ xuất hiện ở đây.", en: "Split-expense events will appear here.", ja: "割り勘イベントはここに表示されます。", language: language) }
            static var noParticipantsYet: String { L10n.tr("transactions.settlement.noParticipantsYet", vi: "Chưa có người tham gia", en: "No participants yet", ja: "参加者なし") }
            static func noParticipantsYet(language: MistiaAppLanguage) -> String { L10n.tr("transactions.settlement.noParticipantsYet", vi: "Chưa có người tham gia", en: "No participants yet", ja: "参加者なし", language: language) }
            static var noSettlementNeeded: String { L10n.tr("transactions.settlement.noSettlementNeeded", vi: "Không cần thanh toán thêm.", en: "No extra settlement needed.", ja: "追加の精算は不要です。") }
            static func noSettlementNeeded(language: MistiaAppLanguage) -> String { L10n.tr("transactions.settlement.noSettlementNeeded", vi: "Không cần thanh toán thêm.", en: "No extra settlement needed.", ja: "追加の精算は不要です。", language: language) }
            static var note: String { L10n.tr("transactions.settlement.note", vi: "Ghi chú", en: "Note", ja: "メモ") }
            static func note(language: MistiaAppLanguage) -> String { L10n.tr("transactions.settlement.note", vi: "Ghi chú", en: "Note", ja: "メモ", language: language) }
            static var notePlaceholder: String { L10n.tr("transactions.settlement.notePlaceholder", vi: "Thêm ghi chú cho sự kiện", en: "Add an event note", ja: "イベントメモを追加") }
            static func notePlaceholder(language: MistiaAppLanguage) -> String { L10n.tr("transactions.settlement.notePlaceholder", vi: "Thêm ghi chú cho sự kiện", en: "Add an event note", ja: "イベントメモを追加", language: language) }
            static var ongoingEvents: String { L10n.tr("transactions.settlement.ongoingEvents", vi: "Sự kiện đang diễn ra", en: "Ongoing events", ja: "進行中のイベント") }
            static func ongoingEvents(language: MistiaAppLanguage) -> String { L10n.tr("transactions.settlement.ongoingEvents", vi: "Sự kiện đang diễn ra", en: "Ongoing events", ja: "進行中のイベント", language: language) }
            static var paid: String { L10n.tr("transactions.settlement.paid", vi: "Đã trả", en: "Paid", ja: "支払い済み") }
            static func paid(language: MistiaAppLanguage) -> String { L10n.tr("transactions.settlement.paid", vi: "Đã trả", en: "Paid", ja: "支払い済み", language: language) }
            static var paidAmount: String { L10n.tr("transactions.settlement.paidAmount", vi: "Đã trả", en: "Paid", ja: "支払い済み") }
            static func paidAmount(language: MistiaAppLanguage) -> String { L10n.tr("transactions.settlement.paidAmount", vi: "Đã trả", en: "Paid", ja: "支払い済み", language: language) }
            static func participantCollectedValue(_ value: String) -> String {
                L10n.format("transactions.settlement.participantCollectedValue", vi: "Đã thu %@", en: "Collected %@", ja: "%@ 回収済み", value)
            }
            static func participantCollectedValue(_ value: String, language: MistiaAppLanguage) -> String {
                L10n.format("transactions.settlement.participantCollectedValue", vi: "Đã thu %@", en: "Collected %@", ja: "%@ 回収済み", language: language, value)
            }
            static var participantName: String { L10n.tr("transactions.settlement.participantName", vi: "Tên", en: "Name", ja: "名前") }
            static func participantName(language: MistiaAppLanguage) -> String { L10n.tr("transactions.settlement.participantName", vi: "Tên", en: "Name", ja: "名前", language: language) }
            static func participantPaidValue(_ value: String) -> String {
                L10n.format("transactions.settlement.participantPaidValue", vi: "Đã trả %@", en: "Paid %@", ja: "%@ 支払い済み", value)
            }
            static func participantPaidValue(_ value: String, language: MistiaAppLanguage) -> String {
                L10n.format("transactions.settlement.participantPaidValue", vi: "Đã trả %@", en: "Paid %@", ja: "%@ 支払い済み", language: language, value)
            }
            static func participantRemainingValue(_ value: String) -> String {
                L10n.format("transactions.settlement.participantRemainingValue", vi: "Còn lại %@", en: "Remaining %@", ja: "残り %@", value)
            }
            static func participantRemainingValue(_ value: String, language: MistiaAppLanguage) -> String {
                L10n.format("transactions.settlement.participantRemainingValue", vi: "Còn lại %@", en: "Remaining %@", ja: "残り %@", language: language, value)
            }
            static var participantSettled: String { L10n.tr("transactions.settlement.participantSettled", vi: "Đã thanh toán xong", en: "Settled", ja: "精算済み") }
            static func participantSettled(language: MistiaAppLanguage) -> String { L10n.tr("transactions.settlement.participantSettled", vi: "Đã thanh toán xong", en: "Settled", ja: "精算済み", language: language) }
            static var participants: String { L10n.tr("transactions.settlement.participants", vi: "Người tham gia", en: "Participants", ja: "参加者") }
            static func participants(language: MistiaAppLanguage) -> String { L10n.tr("transactions.settlement.participants", vi: "Người tham gia", en: "Participants", ja: "参加者", language: language) }
            static var paymentProgress: String { L10n.tr("transactions.settlement.paymentProgress", vi: "Tiến độ thanh toán", en: "Payment progress", ja: "支払い状況") }
            static func paymentProgress(language: MistiaAppLanguage) -> String { L10n.tr("transactions.settlement.paymentProgress", vi: "Tiến độ thanh toán", en: "Payment progress", ja: "支払い状況", language: language) }
            static var recalculateSplit: String { L10n.tr("transactions.settlement.recalculateSplit", vi: "Chia lại chi phí", en: "Recalculate split", ja: "割り勘をやり直す") }
            static func recalculateSplit(language: MistiaAppLanguage) -> String { L10n.tr("transactions.settlement.recalculateSplit", vi: "Chia lại chi phí", en: "Recalculate split", ja: "割り勘をやり直す", language: language) }
            static var resetSplitAction: String { L10n.tr("transactions.settlement.resetSplitAction", vi: "Đồng ý", en: "Continue", ja: "続ける") }
            static func resetSplitAction(language: MistiaAppLanguage) -> String { L10n.tr("transactions.settlement.resetSplitAction", vi: "Đồng ý", en: "Continue", ja: "続ける", language: language) }
            static var resetSplitMessage: String { L10n.tr("transactions.settlement.resetSplitMessage", vi: "Thao tác này sẽ xoá các khoản thanh toán đã tạo từ sự kiện và đưa sự kiện về trạng thái chia lại chi phí. Các thu chi đã liên kết với sự kiện vẫn được giữ nguyên.", en: "This will delete the settlement payments generated for this event and return it to split-editing mode. Linked cashflow entries will remain unchanged.", ja: "このイベント用に作成された精算支払いを削除し、割り勘の編集状態に戻します。関連する収支は変更されません。") }
            static func resetSplitMessage(language: MistiaAppLanguage) -> String { L10n.tr("transactions.settlement.resetSplitMessage", vi: "Thao tác này sẽ xoá các khoản thanh toán đã tạo từ sự kiện và đưa sự kiện về trạng thái chia lại chi phí. Các thu chi đã liên kết với sự kiện vẫn được giữ nguyên.", en: "This will delete the settlement payments generated for this event and return it to split-editing mode. Linked cashflow entries will remain unchanged.", ja: "このイベント用に作成された精算支払いを削除し、割り勘の編集状態に戻します。関連する収支は変更されません。", language: language) }
            static var resetSplitTitle: String { L10n.tr("transactions.settlement.resetSplitTitle", vi: "Chia lại chi phí?", en: "Recalculate split?", ja: "割り勘をやり直しますか？") }
            static func resetSplitTitle(language: MistiaAppLanguage) -> String { L10n.tr("transactions.settlement.resetSplitTitle", vi: "Chia lại chi phí?", en: "Recalculate split?", ja: "割り勘をやり直しますか？", language: language) }
            static func saveDebtAmount(_ value: String) -> String {
                L10n.format("transactions.settlement.saveDebtAmount", vi: "Lưu khoản nợ của %@", en: "Save %@ debt amount", ja: "%@ の債務額を保存", value)
            }
            static func saveDebtAmount(_ value: String, language: MistiaAppLanguage) -> String {
                L10n.format("transactions.settlement.saveDebtAmount", vi: "Lưu khoản nợ của %@", en: "Save %@ debt amount", ja: "%@ の債務額を保存", language: language, value)
            }
            static var searchExpense: String { L10n.tr("transactions.settlement.searchExpense", vi: "Tìm chi tiêu", en: "Search expense", ja: "支出を検索") }
            static func searchExpense(language: MistiaAppLanguage) -> String { L10n.tr("transactions.settlement.searchExpense", vi: "Tìm chi tiêu", en: "Search expense", ja: "支出を検索", language: language) }
            static var searchExpenseNamePrompt: String { L10n.tr("transactions.settlement.searchExpenseNamePrompt", vi: "Tìm tên chi tiêu...", en: "Search expense name...", ja: "支出名を検索...") }
            static func searchExpenseNamePrompt(language: MistiaAppLanguage) -> String { L10n.tr("transactions.settlement.searchExpenseNamePrompt", vi: "Tìm tên chi tiêu...", en: "Search expense name...", ja: "支出名を検索...", language: language) }
            static var searchNoResultsMessage: String { L10n.tr("transactions.settlement.searchNoResultsMessage", vi: "Không có chi tiêu nào khớp với từ khóa này.", en: "No expenses match this search.", ja: "この検索に一致する支出はありません。") }
            static func searchNoResultsMessage(language: MistiaAppLanguage) -> String { L10n.tr("transactions.settlement.searchNoResultsMessage", vi: "Không có chi tiêu nào khớp với từ khóa này.", en: "No expenses match this search.", ja: "この検索に一致する支出はありません。", language: language) }
            static var selfPaidLocked: String { L10n.tr("transactions.settlement.selfPaidLocked", vi: "Số tiền của bạn lấy từ các chi tiêu đã lưu. Bấm Sửa để thay đổi.", en: "Your paid amount comes from saved expenses. Tap Edit to change them.", ja: "あなたの支払額は保存済み支出から計算されます。変更するには編集します。") }
            static func selfPaidLocked(language: MistiaAppLanguage) -> String { L10n.tr("transactions.settlement.selfPaidLocked", vi: "Số tiền của bạn lấy từ các chi tiêu đã lưu. Bấm Sửa để thay đổi.", en: "Your paid amount comes from saved expenses. Tap Edit to change them.", ja: "あなたの支払額は保存済み支出から計算されます。変更するには編集します。", language: language) }
            static var selfParticipantName: String { L10n.tr("transactions.settlement.selfParticipantName", vi: "Bạn", en: "You", ja: "自分") }
            static func selfParticipantName(language: MistiaAppLanguage) -> String { L10n.tr("transactions.settlement.selfParticipantName", vi: "Bạn", en: "You", ja: "自分", language: language) }
            static var settlementNotFound: String { L10n.tr("transactions.settlement.settlementNotFound", vi: "Không tìm thấy khoản chờ thu / chờ trả này.", en: "This pending settlement could not be found.", ja: "この未精算項目が見つかりません。") }
            static func settlementNotFound(language: MistiaAppLanguage) -> String { L10n.tr("transactions.settlement.settlementNotFound", vi: "Không tìm thấy khoản chờ thu / chờ trả này.", en: "This pending settlement could not be found.", ja: "この未精算項目が見つかりません。", language: language) }
            static var settlementSuggestions: String { L10n.tr("transactions.settlement.settlementSuggestions", vi: "Gợi ý thanh toán", en: "Settlement suggestions", ja: "精算候補") }
            static func settlementSuggestions(language: MistiaAppLanguage) -> String { L10n.tr("transactions.settlement.settlementSuggestions", vi: "Gợi ý thanh toán", en: "Settlement suggestions", ja: "精算候補", language: language) }
            static var share: String { L10n.tr("transactions.settlement.share", vi: "Phần chia", en: "Share", ja: "負担分") }
            static func share(language: MistiaAppLanguage) -> String { L10n.tr("transactions.settlement.share", vi: "Phần chia", en: "Share", ja: "負担分", language: language) }
            static var sharedExpenseQuickCreateSubtitle: String { L10n.tr("transactions.settlement.sharedExpenseQuickCreateSubtitle", vi: "Nhập ai đã trả bao nhiêu để tính phần cần thu/trả.", en: "Enter who paid what and calculate what to collect or pay.", ja: "誰がいくら払ったかを入力して、回収・支払い額を計算します。") }
            static func sharedExpenseQuickCreateSubtitle(language: MistiaAppLanguage) -> String { L10n.tr("transactions.settlement.sharedExpenseQuickCreateSubtitle", vi: "Nhập ai đã trả bao nhiêu để tính phần cần thu/trả.", en: "Enter who paid what and calculate what to collect or pay.", ja: "誰がいくら払ったかを入力して、回収・支払い額を計算します。", language: language) }
            static var sharedExpenseTitle: String { L10n.tr("transactions.settlement.sharedExpenseTitle", vi: "Chia chi phí", en: "Split expense", ja: "割り勘") }
            static func sharedExpenseTitle(language: MistiaAppLanguage) -> String { L10n.tr("transactions.settlement.sharedExpenseTitle", vi: "Chia chi phí", en: "Split expense", ja: "割り勘", language: language) }
            static var totalPaid: String { L10n.tr("transactions.settlement.totalPaid", vi: "Tổng đã trả", en: "Total paid", ja: "支払い合計") }
            static func totalPaid(language: MistiaAppLanguage) -> String { L10n.tr("transactions.settlement.totalPaid", vi: "Tổng đã trả", en: "Total paid", ja: "支払い合計", language: language) }
        }

        nonisolated enum transactioneditor {
            static var addANoteIfNeeded: String { L10n.tr("transactions.transactioneditor.addANoteIfNeeded", vi: "Thêm ghi chú nếu cần", en: "Add a note if needed", ja: "必要ならメモを追加") }
            static func addANoteIfNeeded(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.addANoteIfNeeded", vi: "Thêm ghi chú nếu cần", en: "Add a note if needed", ja: "必要ならメモを追加", language: language) }
            static var addReceiptImage: String { L10n.tr("transactions.transactioneditor.addReceiptImage", vi: "Thêm ảnh bill", en: "Add receipt image", ja: "レシート画像を追加") }
            static func addReceiptImage(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.addReceiptImage", vi: "Thêm ảnh bill", en: "Add receipt image", ja: "レシート画像を追加", language: language) }
            static var amount: String { L10n.tr("transactions.transactioneditor.amount", vi: "Số tiền", en: "Amount", ja: "金額") }
            static func amount(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.amount", vi: "Số tiền", en: "Amount", ja: "金額", language: language) }
            static var analyzingReceipt: String { L10n.tr("transactions.transactioneditor.analyzingReceipt", vi: "Đang phân tích bill", en: "Analyzing receipt", ja: "レシートを解析中") }
            static func analyzingReceipt(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.analyzingReceipt", vi: "Đang phân tích bill", en: "Analyzing receipt", ja: "レシートを解析中", language: language) }
            static var archiveTransaction: String { L10n.tr("transactions.transactioneditor.archiveTransaction", vi: "Lưu trữ thu chi", en: "Archive cashflow item", ja: "取引をアーカイブ") }
            static func archiveTransaction(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.archiveTransaction", vi: "Lưu trữ thu chi", en: "Archive cashflow item", ja: "取引をアーカイブ", language: language) }
            static var archivedTransactionsWillNoLongerAppearIn: String { L10n.tr("transactions.transactioneditor.archivedTransactionsWillNoLongerAppearIn", vi: "Thu chi lưu trữ sẽ không còn hiện trong danh sách. Mục này sẽ được tự động xóa vĩnh viễn sau 30 ngày.", en: "Archived cashflow items will no longer appear in the list. They will be automatically deleted permanently after 30 days.", ja: "アーカイブした取引はリストに表示されなくなります。これらは30日後に自動的に永久削除されます。") }
            static func archivedTransactionsWillNoLongerAppearIn(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.archivedTransactionsWillNoLongerAppearIn", vi: "Thu chi lưu trữ sẽ không còn hiện trong danh sách. Mục này sẽ được tự động xóa vĩnh viễn sau 30 ngày.", en: "Archived cashflow items will no longer appear in the list. They will be automatically deleted permanently after 30 days.", ja: "アーカイブした取引はリストに表示されなくなります。これらは30日後に自動的に永久削除されます。", language: language) }
            static var borrowPaidFor: String { L10n.tr("transactions.transactioneditor.borrowPaidFor", vi: "Được trả hộ", en: "Paid for me", ja: "立て替えてもらう") }
            static func borrowPaidFor(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.borrowPaidFor", vi: "Được trả hộ", en: "Paid for me", ja: "立て替えてもらう", language: language) }
            static var borrowReceiveIntoWallet: String { L10n.tr("transactions.transactioneditor.borrowReceiveIntoWallet", vi: "Nhận tiền vào ví", en: "Receive into wallet", ja: "ウォレットに受け取る") }
            static func borrowReceiveIntoWallet(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.borrowReceiveIntoWallet", vi: "Nhận tiền vào ví", en: "Receive into wallet", ja: "ウォレットに受け取る", language: language) }
            static var canTSaveYet: String { L10n.tr("transactions.transactioneditor.canTSaveYet", vi: "Chưa thể lưu", en: "Can't save yet", ja: "まだ保存できません") }
            static func canTSaveYet(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.canTSaveYet", vi: "Chưa thể lưu", en: "Can't save yet", ja: "まだ保存できません", language: language) }
            static var category: String { L10n.tr("transactions.transactioneditor.category", vi: "Danh mục", en: "Category", ja: "カテゴリ") }
            static func category(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.category", vi: "Danh mục", en: "Category", ja: "カテゴリ", language: language) }
            static var chooseACategoryForThisTransaction: String { L10n.tr("transactions.transactioneditor.chooseACategoryForThisTransaction", vi: "Chọn danh mục cho thu chi này.", en: "Choose a category for this cashflow item.", ja: "この取引のカテゴリを選択してください。") }
            static func chooseACategoryForThisTransaction(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.chooseACategoryForThisTransaction", vi: "Chọn danh mục cho thu chi này.", en: "Choose a category for this cashflow item.", ja: "この取引のカテゴリを選択してください。", language: language) }
            static var chooseADebtType: String { L10n.tr("transactions.transactioneditor.chooseADebtType", vi: "Chọn loại vay/cho vay.", en: "Choose a loan type.", ja: "貸し借りの種類を選択してください。") }
            static func chooseADebtType(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.chooseADebtType", vi: "Chọn loại vay/cho vay.", en: "Choose a loan type.", ja: "貸し借りの種類を選択してください。", language: language) }
            static var chooseAWalletForThisTransaction: String { L10n.tr("transactions.transactioneditor.chooseAWalletForThisTransaction", vi: "Chọn ví cho thu chi này.", en: "Choose a wallet for this cashflow item.", ja: "この取引のウォレットを選択してください。") }
            static func chooseAWalletForThisTransaction(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.chooseAWalletForThisTransaction", vi: "Chọn ví cho thu chi này.", en: "Choose a wallet for this cashflow item.", ja: "この取引のウォレットを選択してください。", language: language) }
            static var chooseCategory: String { L10n.tr("transactions.transactioneditor.chooseCategory", vi: "Chọn danh mục", en: "Choose category", ja: "カテゴリを選択") }
            static func chooseCategory(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.chooseCategory", vi: "Chọn danh mục", en: "Choose category", ja: "カテゴリを選択", language: language) }
            static var chooseDestination: String { L10n.tr("transactions.transactioneditor.chooseDestination", vi: "Chọn đích", en: "Choose destination", ja: "入金先を選択") }
            static func chooseDestination(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.chooseDestination", vi: "Chọn đích", en: "Choose destination", ja: "入金先を選択", language: language) }
            static var chooseFamilyMember: String { L10n.tr("transactions.transactioneditor.chooseFamilyMember", vi: "Chọn thành viên", en: "Choose member", ja: "メンバーを選択") }
            static func chooseFamilyMember(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.chooseFamilyMember", vi: "Chọn thành viên", en: "Choose member", ja: "メンバーを選択", language: language) }
            static var chooseFromPhotos: String { L10n.tr("transactions.transactioneditor.chooseFromPhotos", vi: "Chọn từ ảnh", en: "Choose from Photos", ja: "写真から選択") }
            static func chooseFromPhotos(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.chooseFromPhotos", vi: "Chọn từ ảnh", en: "Choose from Photos", ja: "写真から選択", language: language) }
            static var chooseSource: String { L10n.tr("transactions.transactioneditor.chooseSource", vi: "Chọn nguồn", en: "Choose source", ja: "出金元を選択") }
            static func chooseSource(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.chooseSource", vi: "Chọn nguồn", en: "Choose source", ja: "出金元を選択", language: language) }
            static var chooseTheDestinationWallet: String { L10n.tr("transactions.transactioneditor.chooseTheDestinationWallet", vi: "Chọn ví đích.", en: "Choose the destination wallet.", ja: "入金先ウォレットを選択してください。") }
            static func chooseTheDestinationWallet(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.chooseTheDestinationWallet", vi: "Chọn ví đích.", en: "Choose the destination wallet.", ja: "入金先ウォレットを選択してください。", language: language) }
            static var chooseTheSourceWallet: String { L10n.tr("transactions.transactioneditor.chooseTheSourceWallet", vi: "Chọn ví nguồn.", en: "Choose the source wallet.", ja: "出金元ウォレットを選択してください。") }
            static func chooseTheSourceWallet(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.chooseTheSourceWallet", vi: "Chọn ví nguồn.", en: "Choose the source wallet.", ja: "出金元ウォレットを選択してください。", language: language) }
            static var chooseTheWalletUsedForThisDebt: String { L10n.tr("transactions.transactioneditor.chooseTheWalletUsedForThisDebt", vi: "Chọn ví thực hiện vay & cho vay.", en: "Choose the wallet used for this loan.", ja: "この貸し借り取引で使うウォレットを選択してください。") }
            static func chooseTheWalletUsedForThisDebt(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.chooseTheWalletUsedForThisDebt", vi: "Chọn ví thực hiện vay & cho vay.", en: "Choose the wallet used for this loan.", ja: "この貸し借り取引で使うウォレットを選択してください。", language: language) }
            static var chooseWallet: String { L10n.tr("transactions.transactioneditor.chooseWallet", vi: "Chọn ví", en: "Choose wallet", ja: "ウォレットを選択") }
            static func chooseWallet(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.chooseWallet", vi: "Chọn ví", en: "Choose wallet", ja: "ウォレットを選択", language: language) }
            static var completeTheDraft: String { L10n.tr("transactions.transactioneditor.completeTheDraft", vi: "Hoàn thiện bản nháp", en: "Complete the draft", ja: "下書きを完成させる") }
            static func completeTheDraft(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.completeTheDraft", vi: "Hoàn thiện bản nháp", en: "Complete the draft", ja: "下書きを完成させる", language: language) }
            static var confirmFamilyTransferAction: String { L10n.tr("transactions.transactioneditor.confirmFamilyTransferAction", vi: "Chuyển tiền", en: "Transfer", ja: "送金") }
            static func confirmFamilyTransferAction(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.confirmFamilyTransferAction", vi: "Chuyển tiền", en: "Transfer", ja: "送金", language: language) }
            static var confirmFamilyTransferMessage: String { L10n.tr("transactions.transactioneditor.confirmFamilyTransferMessage", vi: "Khoản chuyển tiền gia đình sẽ được tạo cho cả hai thành viên và không thể sửa, lưu trữ hoặc xóa sau khi chuyển.", en: "This family transfer will create records for both members and cannot be edited, archived, or deleted after transfer.", ja: "家族送金は両方のメンバーに記録され、送金後は編集、アーカイブ、削除できません。") }
            static func confirmFamilyTransferMessage(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.confirmFamilyTransferMessage", vi: "Khoản chuyển tiền gia đình sẽ được tạo cho cả hai thành viên và không thể sửa, lưu trữ hoặc xóa sau khi chuyển.", en: "This family transfer will create records for both members and cannot be edited, archived, or deleted after transfer.", ja: "家族送金は両方のメンバーに記録され、送金後は編集、アーカイブ、削除できません。", language: language) }
            static var confirmFamilyTransferTitle: String { L10n.tr("transactions.transactioneditor.confirmFamilyTransferTitle", vi: "Xác nhận chuyển tiền?", en: "Confirm transfer?", ja: "送金を確認しますか？") }
            static func confirmFamilyTransferTitle(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.confirmFamilyTransferTitle", vi: "Xác nhận chuyển tiền?", en: "Confirm transfer?", ja: "送金を確認しますか？", language: language) }
            static var conversion: String { L10n.tr("transactions.transactioneditor.conversion", vi: "Quy đổi", en: "Conversion", ja: "換算") }
            static func conversion(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.conversion", vi: "Quy đổi", en: "Conversion", ja: "換算", language: language) }
            static var convertedAmount: String { L10n.tr("transactions.transactioneditor.convertedAmount", vi: "Số tiền quy đổi", en: "Converted amount", ja: "換算額") }
            static func convertedAmount(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.convertedAmount", vi: "Số tiền quy đổi", en: "Converted amount", ja: "換算額", language: language) }
            static var couldnTAnalyzeThisReceiptRightNow: String { L10n.tr("transactions.transactioneditor.couldnTAnalyzeThisReceiptRightNow", vi: "Không thể phân tích bill lúc này.", en: "Couldn't analyze this receipt right now.", ja: "現在レシートを解析できません。") }
            static func couldnTAnalyzeThisReceiptRightNow(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.couldnTAnalyzeThisReceiptRightNow", vi: "Không thể phân tích bill lúc này.", en: "Couldn't analyze this receipt right now.", ja: "現在レシートを解析できません。", language: language) }
            static var couldnTCreateFamilyTransfer: String { L10n.tr("transactions.transactioneditor.couldnTCreateFamilyTransfer", vi: "Không thể tạo khoản chuyển tiền gia đình lúc này.", en: "Couldn't create the family transfer right now.", ja: "現在、家族送金を作成できません。") }
            static func couldnTCreateFamilyTransfer(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.couldnTCreateFamilyTransfer", vi: "Không thể tạo khoản chuyển tiền gia đình lúc này.", en: "Couldn't create the family transfer right now.", ja: "現在、家族送金を作成できません。", language: language) }
            static var couldnTLoadTheSavedReceiptImage: String { L10n.tr("transactions.transactioneditor.couldnTLoadTheSavedReceiptImage", vi: "Không thể mở ảnh bill đã lưu.", en: "Couldn't load the saved receipt image.", ja: "保存済みのレシート画像を読み込めません。") }
            static func couldnTLoadTheSavedReceiptImage(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.couldnTLoadTheSavedReceiptImage", vi: "Không thể mở ảnh bill đã lưu.", en: "Couldn't load the saved receipt image.", ja: "保存済みのレシート画像を読み込めません。", language: language) }
            static var couldnTProcessThisReceiptImage: String { L10n.tr("transactions.transactioneditor.couldnTProcessThisReceiptImage", vi: "Không thể xử lý ảnh bill này.", en: "Couldn't process this receipt image.", ja: "このレシート画像を処理できません。") }
            static func couldnTProcessThisReceiptImage(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.couldnTProcessThisReceiptImage", vi: "Không thể xử lý ảnh bill này.", en: "Couldn't process this receipt image.", ja: "このレシート画像を処理できません。", language: language) }
            static var couldnTSaveTheArchiveState: String { L10n.tr("transactions.transactioneditor.couldnTSaveTheArchiveState", vi: "Không thể lưu trạng thái lưu trữ.", en: "Couldn't save the archive state.", ja: "アーカイブ状態を保存できません。") }
            static func couldnTSaveTheArchiveState(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.couldnTSaveTheArchiveState", vi: "Không thể lưu trạng thái lưu trữ.", en: "Couldn't save the archive state.", ja: "アーカイブ状態を保存できません。", language: language) }
            static var couldnTSaveTheReceiptImage: String { L10n.tr("transactions.transactioneditor.couldnTSaveTheReceiptImage", vi: "Không thể lưu ảnh bill.", en: "Couldn't save the receipt image.", ja: "レシート画像を保存できません。") }
            static func couldnTSaveTheReceiptImage(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.couldnTSaveTheReceiptImage", vi: "Không thể lưu ảnh bill.", en: "Couldn't save the receipt image.", ja: "レシート画像を保存できません。", language: language) }
            static var couldnTSaveThisTransactionRightNow: String { L10n.tr("transactions.transactioneditor.couldnTSaveThisTransactionRightNow", vi: "Không thể lưu thu chi lúc này.", en: "Couldn't save this cashflow item right now.", ja: "現在この取引を保存できません。") }
            static func couldnTSaveThisTransactionRightNow(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.couldnTSaveThisTransactionRightNow", vi: "Không thể lưu thu chi lúc này.", en: "Couldn't save this cashflow item right now.", ja: "現在この取引を保存できません。", language: language) }
            static var countAsExpense: String { L10n.tr("transactions.transactioneditor.countAsExpense", vi: "Tính vào chi tiêu", en: "Count as expense", ja: "支出に含める") }
            static func countAsExpense(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.countAsExpense", vi: "Tính vào chi tiêu", en: "Count as expense", ja: "支出に含める", language: language) }
            static var counterparty: String { L10n.tr("transactions.transactioneditor.counterparty", vi: "Đối tượng", en: "Counterparty", ja: "相手") }
            static func counterparty(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.counterparty", vi: "Đối tượng", en: "Counterparty", ja: "相手", language: language) }
            static var counterpartyName: String { L10n.tr("transactions.transactioneditor.counterpartyName", vi: "Tên người liên quan", en: "Counterparty name", ja: "相手の名前") }
            static func counterpartyName(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.counterpartyName", vi: "Tên người liên quan", en: "Counterparty name", ja: "相手の名前", language: language) }
            static var creditCardsCannotReceiveIncomePleaseSelect: String { L10n.tr("transactions.transactioneditor.creditCardsCannotReceiveIncomePleaseSelect", vi: "Thẻ tín dụng không thể ghi nhận thu nhập. Hãy chọn ví tiền mặt, ngân hàng hoặc ví điện tử.", en: "Credit cards cannot receive income. Please select a cash, bank, or e-wallet instead.", ja: "クレジットカードは収入を記録できません。現金、銀行、または電子マネーを選択してください。") }
            static func creditCardsCannotReceiveIncomePleaseSelect(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.creditCardsCannotReceiveIncomePleaseSelect", vi: "Thẻ tín dụng không thể ghi nhận thu nhập. Hãy chọn ví tiền mặt, ngân hàng hoặc ví điện tử.", en: "Credit cards cannot receive income. Please select a cash, bank, or e-wallet instead.", ja: "クレジットカードは収入を記録できません。現金、銀行、または電子マネーを選択してください。", language: language) }
            static var creditCardsCannotSendMoneyViaTransfer: String { L10n.tr("transactions.transactioneditor.creditCardsCannotSendMoneyViaTransfer", vi: "Thẻ tín dụng không thể chuyển tiền đi. Chỉ có thể nhận tiền để trả nợ.", en: "Credit cards cannot send money via transfer. They can only receive payments for debt repayment.", ja: "クレジットカードは振替で送金できません。返済の受け取りのみ可能です。") }
            static func creditCardsCannotSendMoneyViaTransfer(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.creditCardsCannotSendMoneyViaTransfer", vi: "Thẻ tín dụng không thể chuyển tiền đi. Chỉ có thể nhận tiền để trả nợ.", en: "Credit cards cannot send money via transfer. They can only receive payments for debt repayment.", ja: "クレジットカードは振替で送金できません。返済の受け取りのみ可能です。", language: language) }
            static var currency: String { L10n.tr("transactions.transactioneditor.currency", vi: "Loại tiền", en: "Currency", ja: "通貨") }
            static func currency(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.currency", vi: "Loại tiền", en: "Currency", ja: "通貨", language: language) }
            static var dataIsSavedDirectlyOnThisDevice: String { L10n.tr("transactions.transactioneditor.dataIsSavedDirectlyOnThisDevice", vi: "Dữ liệu sẽ được lưu ngay trên thiết bị và phản ánh trực tiếp vào tab Thu chi.", en: "Data is saved directly on this device and reflected immediately in the Cashflow tab.", ja: "データはこの端末にすぐ保存され、取引タブへ即時反映されます。") }
            static func dataIsSavedDirectlyOnThisDevice(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.dataIsSavedDirectlyOnThisDevice", vi: "Dữ liệu sẽ được lưu ngay trên thiết bị và phản ánh trực tiếp vào tab Thu chi.", en: "Data is saved directly on this device and reflected immediately in the Cashflow tab.", ja: "データはこの端末にすぐ保存され、取引タブへ即時反映されます。", language: language) }
            static var dateTime: String { L10n.tr("transactions.transactioneditor.dateTime", vi: "Thời gian", en: "Date & time", ja: "日時") }
            static func dateTime(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.dateTime", vi: "Thời gian", en: "Date & time", ja: "日時", language: language) }
            static var debtType: String { L10n.tr("transactions.transactioneditor.debtType", vi: "Loại vay/cho vay", en: "Loan type", ja: "貸し借りの種類") }
            static func debtType(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.debtType", vi: "Loại vay/cho vay", en: "Loan type", ja: "貸し借りの種類", language: language) }
            static var destinationAmount: String { L10n.tr("transactions.transactioneditor.destinationAmount", vi: "Số tiền ví đích", en: "Destination amount", ja: "入金先の金額") }
            static func destinationAmount(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.destinationAmount", vi: "Số tiền ví đích", en: "Destination amount", ja: "入金先の金額", language: language) }
            static var editTransaction: String { L10n.tr("transactions.transactioneditor.editTransaction", vi: "Sửa khoản thu chi", en: "Edit cashflow item", ja: "収支を編集") }
            static func editTransaction(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.editTransaction", vi: "Sửa khoản thu chi", en: "Edit cashflow item", ja: "収支を編集", language: language) }
            static var enterATransactionNameBeforeSaving: String { L10n.tr("transactions.transactioneditor.enterATransactionNameBeforeSaving", vi: "Nhập tên khoản thu chi để lưu.", en: "Enter a cashflow item name before saving.", ja: "保存する前に収支名を入力してください。") }
            static func enterATransactionNameBeforeSaving(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.enterATransactionNameBeforeSaving", vi: "Nhập tên khoản thu chi để lưu.", en: "Enter a cashflow item name before saving.", ja: "保存する前に収支名を入力してください。", language: language) }
            static var enterAnAmountGreaterThan: String { L10n.tr("transactions.transactioneditor.enterAnAmountGreaterThan", vi: "Nhập số tiền lớn hơn 0.", en: "Enter an amount greater than 0.", ja: "0 より大きい金額を入力してください。") }
            static func enterAnAmountGreaterThan(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.enterAnAmountGreaterThan", vi: "Nhập số tiền lớn hơn 0.", en: "Enter an amount greater than 0.", ja: "0 より大きい金額を入力してください。", language: language) }
            static var enterAnAmountGreaterThanTo: String { L10n.tr("transactions.transactioneditor.enterAnAmountGreaterThanTo", vi: "Nhập số tiền lớn hơn 0 để lưu ghi nhanh.", en: "Enter an amount greater than 0 to save the quick capture.", ja: "クイック記録を保存するには 0 より大きい金額を入力してください。") }
            static func enterAnAmountGreaterThanTo(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.enterAnAmountGreaterThanTo", vi: "Nhập số tiền lớn hơn 0 để lưu ghi nhanh.", en: "Enter an amount greater than 0 to save the quick capture.", ja: "クイック記録を保存するには 0 より大きい金額を入力してください。", language: language) }
            static var enterManually: String { L10n.tr("transactions.transactioneditor.enterManually", vi: "Tự nhập", en: "Manual", ja: "手入力") }
            static func enterManually(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.enterManually", vi: "Tự nhập", en: "Manual", ja: "手入力", language: language) }
            static var enterResaleItemName: String { L10n.tr("transactions.transactioneditor.enterResaleItemName", vi: "Nhập tên món bán.", en: "Enter the item name.", ja: "品名を入力してください。") }
            static func enterResaleItemName(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.enterResaleItemName", vi: "Nhập tên món bán.", en: "Enter the item name.", ja: "品名を入力してください。", language: language) }
            static var enterResalePurchasePrice: String { L10n.tr("transactions.transactioneditor.enterResalePurchasePrice", vi: "Nhập giá mua lớn hơn 0.", en: "Enter a purchase price greater than 0.", ja: "0 より大きい仕入れ価格を入力してください。") }
            static func enterResalePurchasePrice(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.enterResalePurchasePrice", vi: "Nhập giá mua lớn hơn 0.", en: "Enter a purchase price greater than 0.", ja: "0 より大きい仕入れ価格を入力してください。", language: language) }
            static var enterTheConvertedAmountOrRefreshRates: String { L10n.tr("transactions.transactioneditor.enterTheConvertedAmountOrRefreshRates", vi: "Nhập số tiền quy đổi hoặc cập nhật tỷ giá trước khi lưu.", en: "Enter the converted amount or refresh rates before saving.", ja: "保存する前に換算額を入力するかレートを更新してください。") }
            static func enterTheConvertedAmountOrRefreshRates(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.enterTheConvertedAmountOrRefreshRates", vi: "Nhập số tiền quy đổi hoặc cập nhật tỷ giá trước khi lưu.", en: "Enter the converted amount or refresh rates before saving.", ja: "保存する前に換算額を入力するかレートを更新してください。", language: language) }
            static var enterTheCounterpartyName: String { L10n.tr("transactions.transactioneditor.enterTheCounterpartyName", vi: "Nhập tên người liên quan.", en: "Enter the counterparty name.", ja: "相手の名前を入力してください。") }
            static func enterTheCounterpartyName(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.enterTheCounterpartyName", vi: "Nhập tên người liên quan.", en: "Enter the counterparty name.", ja: "相手の名前を入力してください。", language: language) }
            static var eventGeneratedDebtReadOnlyNotice: String { L10n.tr("transactions.transactioneditor.eventGeneratedDebtReadOnlyNotice", vi: "Khoản vay & cho vay này được tạo từ sự kiện. Dùng Chia lại chi phí trong sự kiện để thay đổi.", en: "This loan entry was generated from an event. Use Recalculate split in the event to change it.", ja: "この貸し借りはイベントから作成されました。変更するにはイベントの分割を再計算してください。") }
            static func eventGeneratedDebtReadOnlyNotice(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.eventGeneratedDebtReadOnlyNotice", vi: "Khoản vay & cho vay này được tạo từ sự kiện. Dùng Chia lại chi phí trong sự kiện để thay đổi.", en: "This loan entry was generated from an event. Use Recalculate split in the event to change it.", ja: "この貸し借りはイベントから作成されました。変更するにはイベントの分割を再計算してください。", language: language) }
            static var eventGeneratedDebtReportingEditableNotice: String { L10n.tr("transactions.transactioneditor.eventGeneratedDebtReportingEditableNotice", vi: "Khoản vay & cho vay này được tạo từ sự kiện. Chỉ phần Ghi nhận chi tiêu có thể chỉnh ở đây; số tiền và người liên quan được quản lý trong sự kiện.", en: "This loan entry was generated from an event. Only Expense reporting can be edited here; the amount and people are managed in the event.", ja: "この貸し借りはイベントから作成されました。ここでは支出への反映のみ編集でき、金額と参加者はイベントで管理されます。") }
            static func eventGeneratedDebtReportingEditableNotice(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.eventGeneratedDebtReportingEditableNotice", vi: "Khoản vay & cho vay này được tạo từ sự kiện. Chỉ phần Ghi nhận chi tiêu có thể chỉnh ở đây; số tiền và người liên quan được quản lý trong sự kiện.", en: "This loan entry was generated from an event. Only Expense reporting can be edited here; the amount and people are managed in the event.", ja: "この貸し借りはイベントから作成されました。ここでは支出への反映のみ編集でき、金額と参加者はイベントで管理されます。", language: language) }
            static var eventGeneratedExpenseReportingSection: String { L10n.tr("transactions.transactioneditor.eventGeneratedExpenseReportingSection", vi: "Ghi nhận chi tiêu", en: "Expense reporting", ja: "支出への反映") }
            static func eventGeneratedExpenseReportingSection(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.eventGeneratedExpenseReportingSection", vi: "Ghi nhận chi tiêu", en: "Expense reporting", ja: "支出への反映", language: language) }
            static var expenseName: String { L10n.tr("transactions.transactioneditor.expenseName", vi: "Tên khoản chi", en: "Expense name", ja: "支出名") }
            static func expenseName(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.expenseName", vi: "Tên khoản chi", en: "Expense name", ja: "支出名", language: language) }
            static var expensesAndIncomeMustUseAChild: String { L10n.tr("transactions.transactioneditor.expensesAndIncomeMustUseAChild", vi: "Chi tiêu và thu nhập phải dùng danh mục con.", en: "Expenses and income must use a child category.", ja: "支出と収入は子カテゴリを使う必要があります。") }
            static func expensesAndIncomeMustUseAChild(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.expensesAndIncomeMustUseAChild", vi: "Chi tiêu và thu nhập phải dùng danh mục con.", en: "Expenses and income must use a child category.", ja: "支出と収入は子カテゴリを使う必要があります。", language: language) }
            static var familyMember: String { L10n.tr("transactions.transactioneditor.familyMember", vi: "Thành viên", en: "Family member", ja: "家族メンバー") }
            static func familyMember(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.familyMember", vi: "Thành viên", en: "Family member", ja: "家族メンバー", language: language) }
            static var familyTransferNeedsNetwork: String { L10n.tr("transactions.transactioneditor.familyTransferNeedsNetwork", vi: "Chuyển tiền gia đình cần đăng nhập và có internet.", en: "Family transfers need sign-in and an internet connection.", ja: "家族送金にはサインインとインターネット接続が必要です。") }
            static func familyTransferNeedsNetwork(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.familyTransferNeedsNetwork", vi: "Chuyển tiền gia đình cần đăng nhập và có internet.", en: "Family transfers need sign-in and an internet connection.", ja: "家族送金にはサインインとインターネット接続が必要です。", language: language) }
            static var familyTransferReadOnlyNotice: String { L10n.tr("transactions.transactioneditor.familyTransferReadOnlyNotice", vi: "Khoản chuyển tiền gia đình không thể sửa, lưu trữ hoặc xóa sau khi đã tạo.", en: "Family transfers cannot be edited, archived, or deleted after they are created.", ja: "作成済みの家族送金は編集、アーカイブ、削除できません。") }
            static func familyTransferReadOnlyNotice(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.familyTransferReadOnlyNotice", vi: "Khoản chuyển tiền gia đình không thể sửa, lưu trữ hoặc xóa sau khi đã tạo.", en: "Family transfers cannot be edited, archived, or deleted after they are created.", ja: "作成済みの家族送金は編集、アーカイブ、削除できません。", language: language) }
            static var familyWalletsMustUseACategoryFrom: String { L10n.tr("transactions.transactioneditor.familyWalletsMustUseACategoryFrom", vi: "Ví gia đình phải dùng danh mục đã có trên cloud của chủ ví.", en: "Family wallets must use a category from the wallet owner's cloud catalog.", ja: "家族ウォレットでは、ウォレット所有者のクラウドカテゴリを使う必要があります。") }
            static func familyWalletsMustUseACategoryFrom(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.familyWalletsMustUseACategoryFrom", vi: "Ví gia đình phải dùng danh mục đã có trên cloud của chủ ví.", en: "Family wallets must use a category from the wallet owner's cloud catalog.", ja: "家族ウォレットでは、ウォレット所有者のクラウドカテゴリを使う必要があります。", language: language) }
            static var fromWallet: String { L10n.tr("transactions.transactioneditor.fromWallet", vi: "Từ ví", en: "From wallet", ja: "出金元") }
            static func fromWallet(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.fromWallet", vi: "Từ ví", en: "From wallet", ja: "出金元", language: language) }
            static var fundingSource: String { L10n.tr("transactions.transactioneditor.fundingSource", vi: "Nguồn tiền", en: "Funding source", ja: "支払い元") }
            static func fundingSource(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.fundingSource", vi: "Nguồn tiền", en: "Funding source", ja: "支払い元", language: language) }
            static var image: String { L10n.tr("transactions.transactioneditor.image", vi: "Ảnh", en: "Image", ja: "画像") }
            static func image(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.image", vi: "Ảnh", en: "Image", ja: "画像", language: language) }
            static var incomeName: String { L10n.tr("transactions.transactioneditor.incomeName", vi: "Tên khoản thu", en: "Income name", ja: "収入名") }
            static func incomeName(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.incomeName", vi: "Tên khoản thu", en: "Income name", ja: "収入名", language: language) }
            static var insufficientWalletBalanceToPerformTheTransaction: String { L10n.tr("transactions.transactioneditor.insufficientWalletBalanceToPerformTheTransaction", vi: "Số dư ví không đủ để ghi nhận khoản này.", en: "Insufficient wallet balance for this item.", ja: "取引を実行するためのウォレット残高が不足しています。") }
            static func insufficientWalletBalanceToPerformTheTransaction(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.insufficientWalletBalanceToPerformTheTransaction", vi: "Số dư ví không đủ để ghi nhận khoản này.", en: "Insufficient wallet balance for this item.", ja: "取引を実行するためのウォレット残高が不足しています。", language: language) }
            static var internalTransfer: String { L10n.tr("transactions.transactioneditor.internalTransfer", vi: "Chuyển tiền nội bộ", en: "Internal transfer", ja: "内部振替") }
            static func internalTransfer(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.internalTransfer", vi: "Chuyển tiền nội bộ", en: "Internal transfer", ja: "内部振替", language: language) }
            static var justEnterTheAmountAndTransactionType: String { L10n.tr("transactions.transactioneditor.justEnterTheAmountAndTransactionType", vi: "Chỉ cần số tiền và loại thu chi. Phần còn lại sẽ xuất hiện trong lịch sử để bạn bổ sung sau.", en: "Just enter the amount and cashflow item type. The rest will appear in history for you to complete later.", ja: "金額と取引タイプだけ入力してください。残りの内容は履歴に表示され、あとで追記できます。") }
            static func justEnterTheAmountAndTransactionType(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.justEnterTheAmountAndTransactionType", vi: "Chỉ cần số tiền và loại thu chi. Phần còn lại sẽ xuất hiện trong lịch sử để bạn bổ sung sau.", en: "Just enter the amount and cashflow item type. The rest will appear in history for you to complete later.", ja: "金額と取引タイプだけ入力してください。残りの内容は履歴に表示され、あとで追記できます。", language: language) }
            static var localFirstTransaction: String { L10n.tr("transactions.transactioneditor.localFirstTransaction", vi: "Ghi thu chi local-first", en: "Local-first cashflow", ja: "ローカルファーストの取引") }
            static func localFirstTransaction(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.localFirstTransaction", vi: "Ghi thu chi local-first", en: "Local-first cashflow", ja: "ローカルファーストの取引", language: language) }
            static var mainDetails: String { L10n.tr("transactions.transactioneditor.mainDetails", vi: "Thông tin chính", en: "Main details", ja: "基本情報") }
            static func mainDetails(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.mainDetails", vi: "Thông tin chính", en: "Main details", ja: "基本情報", language: language) }
            static var noUsableWalletsForThisMember: String { L10n.tr("transactions.transactioneditor.noUsableWalletsForThisMember", vi: "Thành viên này chưa cấp quyền sử dụng ví nào cho bạn.", en: "This member has not granted you use access to any wallet.", ja: "このメンバーは、あなたに使用を許可したウォレットがありません。") }
            static func noUsableWalletsForThisMember(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.noUsableWalletsForThisMember", vi: "Thành viên này chưa cấp quyền sử dụng ví nào cho bạn.", en: "This member has not granted you use access to any wallet.", ja: "このメンバーは、あなたに使用を許可したウォレットがありません。", language: language) }
            static var notes: String { L10n.tr("transactions.transactioneditor.notes", vi: "Ghi chú", en: "Notes", ja: "メモ") }
            static func notes(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.notes", vi: "Ghi chú", en: "Notes", ja: "メモ", language: language) }
            static var permissionRequestPendingTitle: String { L10n.tr("transactions.transactioneditor.permissionRequestPendingTitle", vi: "Đã gửi yêu cầu quyền", en: "Access request sent", ja: "権限リクエスト送信済み") }
            static func permissionRequestPendingTitle(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.permissionRequestPendingTitle", vi: "Đã gửi yêu cầu quyền", en: "Access request sent", ja: "権限リクエスト送信済み", language: language) }
            static var quickCapture: String { L10n.tr("transactions.transactioneditor.quickCapture", vi: "Ghi nhanh", en: "Quick capture", ja: "クイック記録") }
            static func quickCapture(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.quickCapture", vi: "Ghi nhanh", en: "Quick capture", ja: "クイック記録", language: language) }
            static var quickCaptureOnlySavesTheTransactionType: String { L10n.tr("transactions.transactioneditor.quickCaptureOnlySavesTheTransactionType", vi: "Ghi nhanh chỉ lưu loại thu chi và số tiền. Hãy hoàn thiện chi tiết ở tab Thu chi.", en: "Quick capture only saves the cashflow item type and amount. Complete the rest in the Cashflow tab.", ja: "クイック記録では取引タイプと金額だけを保存します。残りの詳細は取引タブで仕上げてください。") }
            static func quickCaptureOnlySavesTheTransactionType(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.quickCaptureOnlySavesTheTransactionType", vi: "Ghi nhanh chỉ lưu loại thu chi và số tiền. Hãy hoàn thiện chi tiết ở tab Thu chi.", en: "Quick capture only saves the cashflow item type and amount. Complete the rest in the Cashflow tab.", ja: "クイック記録では取引タイプと金額だけを保存します。残りの詳細は取引タブで仕上げてください。", language: language) }
            static var receiptAIIsTemporarilyDisabledToday: String { L10n.tr("transactions.transactioneditor.receiptAIIsTemporarilyDisabledToday", vi: "AI quét bill đang tạm tắt hôm nay.", en: "Receipt AI is temporarily disabled today.", ja: "本日のレシートAIは一時的に無効です。") }
            static func receiptAIIsTemporarilyDisabledToday(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.receiptAIIsTemporarilyDisabledToday", vi: "AI quét bill đang tạm tắt hôm nay.", en: "Receipt AI is temporarily disabled today.", ja: "本日のレシートAIは一時的に無効です。", language: language) }
            static var receiptAINeedsSignInAndNetwork: String { L10n.tr("transactions.transactioneditor.receiptAINeedsSignInAndNetwork", vi: "AI cần đăng nhập và kết nối mạng để phân tích bill. Ảnh vẫn được giữ trong modal để bạn nhập thủ công.", en: "Receipt AI needs sign-in and network access. The image stays in the modal so you can fill the cashflow item manually.", ja: "レシートAIにはサインインとネットワーク接続が必要です。画像はモーダルに残るため手入力できます。") }
            static func receiptAINeedsSignInAndNetwork(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.receiptAINeedsSignInAndNetwork", vi: "AI cần đăng nhập và kết nối mạng để phân tích bill. Ảnh vẫn được giữ trong modal để bạn nhập thủ công.", en: "Receipt AI needs sign-in and network access. The image stays in the modal so you can fill the cashflow item manually.", ja: "レシートAIにはサインインとネットワーク接続が必要です。画像はモーダルに残るため手入力できます。", language: language) }
            static var receiptImage: String { L10n.tr("transactions.transactioneditor.receiptImage", vi: "Ảnh bill", en: "Receipt image", ja: "レシート画像") }
            static func receiptImage(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.receiptImage", vi: "Ảnh bill", en: "Receipt image", ja: "レシート画像", language: language) }
            static var refreshPermissionStatus: String { L10n.tr("transactions.transactioneditor.refreshPermissionStatus", vi: "Làm mới", en: "Refresh", ja: "更新") }
            static func refreshPermissionStatus(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.refreshPermissionStatus", vi: "Làm mới", en: "Refresh", ja: "更新", language: language) }
            static var removeImage: String { L10n.tr("transactions.transactioneditor.removeImage", vi: "Xóa ảnh", en: "Remove image", ja: "画像を削除") }
            static func removeImage(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.removeImage", vi: "Xóa ảnh", en: "Remove image", ja: "画像を削除", language: language) }
            static func requestDebtPermissionMessage(_ value: String) -> String {
                L10n.format("transactions.transactioneditor.requestDebtPermissionMessage", vi: "Bạn cần quyền tạo vay & cho vay cho %@. Gửi yêu cầu tới chủ dữ liệu?", en: "You need loan creation access for %@. Send a request to the data owner?", ja: "%@ の貸し借り作成権限が必要です。データ所有者へリクエストしますか？", value)
            }
            static func requestDebtPermissionMessage(_ value: String, language: MistiaAppLanguage) -> String {
                L10n.format("transactions.transactioneditor.requestDebtPermissionMessage", vi: "Bạn cần quyền tạo vay & cho vay cho %@. Gửi yêu cầu tới chủ dữ liệu?", en: "You need loan creation access for %@. Send a request to the data owner?", ja: "%@ の貸し借り作成権限が必要です。データ所有者へリクエストしますか？", language: language, value)
            }
            static func requestFamilyTransferPermissionMessage(_ value: String) -> String {
                L10n.format("transactions.transactioneditor.requestFamilyTransferPermissionMessage", vi: "Bạn cần quyền chuyển tiền gia đình cho %@. Gửi yêu cầu tới chủ dữ liệu?", en: "You need family transfer access for %@. Send a request to the data owner?", ja: "%@ のファミリー送金権限が必要です。データ所有者へリクエストしますか？", value)
            }
            static func requestFamilyTransferPermissionMessage(_ value: String, language: MistiaAppLanguage) -> String {
                L10n.format("transactions.transactioneditor.requestFamilyTransferPermissionMessage", vi: "Bạn cần quyền chuyển tiền gia đình cho %@. Gửi yêu cầu tới chủ dữ liệu?", en: "You need family transfer access for %@. Send a request to the data owner?", ja: "%@ のファミリー送金権限が必要です。データ所有者へリクエストしますか？", language: language, value)
            }
            static var requestTransferPermissionTitle: String { L10n.tr("transactions.transactioneditor.requestTransferPermissionTitle", vi: "Yêu cầu quyền chuyển tiền", en: "Request transfer access", ja: "送金権限をリクエスト") }
            static func requestTransferPermissionTitle(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.requestTransferPermissionTitle", vi: "Yêu cầu quyền chuyển tiền", en: "Request transfer access", ja: "送金権限をリクエスト", language: language) }
            static var resaleAmountSection: String { L10n.tr("transactions.transactioneditor.resaleAmountSection", vi: "Số tiền", en: "Amounts", ja: "金額") }
            static func resaleAmountSection(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.resaleAmountSection", vi: "Số tiền", en: "Amounts", ja: "金額", language: language) }
            static var resaleBuyerName: String { L10n.tr("transactions.transactioneditor.resaleBuyerName", vi: "Người mua", en: "Buyer", ja: "購入者") }
            static func resaleBuyerName(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.resaleBuyerName", vi: "Người mua", en: "Buyer", ja: "購入者", language: language) }
            static var resaleCreditSale: String { L10n.tr("transactions.transactioneditor.resaleCreditSale", vi: "Bán chịu", en: "Credit sale", ja: "掛け売り") }
            static func resaleCreditSale(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.resaleCreditSale", vi: "Bán chịu", en: "Credit sale", ja: "掛け売り", language: language) }
            static var resaleInformationSection: String { L10n.tr("transactions.transactioneditor.resaleInformationSection", vi: "Thông tin", en: "Details", ja: "詳細") }
            static func resaleInformationSection(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.resaleInformationSection", vi: "Thông tin", en: "Details", ja: "詳細", language: language) }
            static var resaleItemName: String { L10n.tr("transactions.transactioneditor.resaleItemName", vi: "Tên món bán", en: "Item name", ja: "品名") }
            static func resaleItemName(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.resaleItemName", vi: "Tên món bán", en: "Item name", ja: "品名", language: language) }
            static var resalePurchasePrice: String { L10n.tr("transactions.transactioneditor.resalePurchasePrice", vi: "Giá mua", en: "Purchase price", ja: "仕入れ価格") }
            static func resalePurchasePrice(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.resalePurchasePrice", vi: "Giá mua", en: "Purchase price", ja: "仕入れ価格", language: language) }
            static var resaleSalePrice: String { L10n.tr("transactions.transactioneditor.resaleSalePrice", vi: "Giá bán", en: "Sale price", ja: "販売価格") }
            static func resaleSalePrice(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.resaleSalePrice", vi: "Giá bán", en: "Sale price", ja: "販売価格", language: language) }
            static var resaleWalletCategorySection: String { L10n.tr("transactions.transactioneditor.resaleWalletCategorySection", vi: "Ví & danh mục", en: "Wallet & category", ja: "ウォレットとカテゴリ") }
            static func resaleWalletCategorySection(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.resaleWalletCategorySection", vi: "Ví & danh mục", en: "Wallet & category", ja: "ウォレットとカテゴリ", language: language) }
            static var saveDraft: String { L10n.tr("transactions.transactioneditor.saveDraft", vi: "Lưu nháp", en: "Save draft", ja: "下書きを保存") }
            static func saveDraft(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.saveDraft", vi: "Lưu nháp", en: "Save draft", ja: "下書きを保存", language: language) }
            static var saveFastFinishLater: String { L10n.tr("transactions.transactioneditor.saveFastFinishLater", vi: "Lưu nhanh rồi hoàn thiện sau", en: "Save fast, finish later", ja: "すばやく保存して後で仕上げる") }
            static func saveFastFinishLater(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.saveFastFinishLater", vi: "Lưu nhanh rồi hoàn thiện sau", en: "Save fast, finish later", ja: "すばやく保存して後で仕上げる", language: language) }
            static var sendPermissionRequest: String { L10n.tr("transactions.transactioneditor.sendPermissionRequest", vi: "Gửi yêu cầu", en: "Send request", ja: "リクエストを送信") }
            static func sendPermissionRequest(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.sendPermissionRequest", vi: "Gửi yêu cầu", en: "Send request", ja: "リクエストを送信", language: language) }
            static var sourceAndDestinationWalletsMustBeDifferent: String { L10n.tr("transactions.transactioneditor.sourceAndDestinationWalletsMustBeDifferent", vi: "Ví nguồn và đích phải khác nhau.", en: "Source and destination wallets must be different.", ja: "出金元と入金先のウォレットは別である必要があります。") }
            static func sourceAndDestinationWalletsMustBeDifferent(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.sourceAndDestinationWalletsMustBeDifferent", vi: "Ví nguồn và đích phải khác nhau.", en: "Source and destination wallets must be different.", ja: "出金元と入金先のウォレットは別である必要があります。", language: language) }
            static var takePhoto: String { L10n.tr("transactions.transactioneditor.takePhoto", vi: "Chụp ảnh", en: "Take photo", ja: "写真を撮る") }
            static func takePhoto(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.takePhoto", vi: "Chụp ảnh", en: "Take photo", ja: "写真を撮る", language: language) }
            static var theAmountExceedsTheAvailableCreditOn: String { L10n.tr("transactions.transactioneditor.theAmountExceedsTheAvailableCreditOn", vi: "Số tiền vượt quá hạn mức khả dụng của thẻ.", en: "The amount exceeds the available credit on the card.", ja: "金額がカードの利用可能額を超えています。") }
            static func theAmountExceedsTheAvailableCreditOn(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.theAmountExceedsTheAvailableCreditOn", vi: "Số tiền vượt quá hạn mức khả dụng của thẻ.", en: "The amount exceeds the available credit on the card.", ja: "金額がカードの利用可能額を超えています。", language: language) }
            static func theValueStatementForThisCardHas(_ value: String) -> String {
                L10n.format("transactions.transactioneditor.theValueStatementForThisCardHas", vi: "Sao kê %@ của thẻ này đã thanh toán xong. Không thể thêm chi tiêu mới vào kỳ đã đóng.", en: "The %@ statement for this card has already been paid. You can't add a new expense to a closed cycle.", ja: "このカードの %@ 明細は支払い済みです。締め済みの期間に新しい支出は追加できません。", value)
            }
            static func theValueStatementForThisCardHas(_ value: String, language: MistiaAppLanguage) -> String {
                L10n.format("transactions.transactioneditor.theValueStatementForThisCardHas", vi: "Sao kê %@ của thẻ này đã thanh toán xong. Không thể thêm chi tiêu mới vào kỳ đã đóng.", en: "The %@ statement for this card has already been paid. You can't add a new expense to a closed cycle.", ja: "このカードの %@ 明細は支払い済みです。締め済みの期間に新しい支出は追加できません。", language: language, value)
            }
            static var thisTransactionIsLinkedToABillPayment: String { L10n.tr("transactions.transactioneditor.thisTransactionIsLinkedToABillPayment", vi: "Giao dịch này được tạo tự động từ thanh toán hóa đơn. Để hoàn tác hoặc xóa, vui lòng thực hiện hoàn tác tại mục Hóa đơn.", en: "This transaction was automatically created from a bill payment. To undo, please perform undo in the Bills section.", ja: "この取引は請求の支払いから自動作成されました。取り消すには、請求セクションで取り消しを行ってください。") }
            static func thisTransactionIsLinkedToABillPayment(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.thisTransactionIsLinkedToABillPayment", vi: "Giao dịch này được tạo tự động từ thanh toán hóa đơn. Để hoàn tác hoặc xóa, vui lòng thực hiện hoàn tác tại mục Hóa đơn.", en: "This transaction was automatically created from a bill payment. To undo, please perform undo in the Bills section.", ja: "この取引は請求の支払いから自動作成されました。取り消すには、請求セクションで取り消しを行ってください。", language: language) }
            static var thisTransactionIsPartOfAPaid: String { L10n.tr("transactions.transactioneditor.thisTransactionIsPartOfAPaid", vi: "Khoản thu chi này thuộc sao kê thẻ tín dụng đã thanh toán nên không thể sửa hoặc lưu trữ.", en: "This cashflow item belongs to a paid credit card statement and cannot be edited or archived.", ja: "この収支は支払い済みのクレジットカード明細に含まれているため、編集やアーカイブはできません。") }
            static func thisTransactionIsPartOfAPaid(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.thisTransactionIsPartOfAPaid", vi: "Khoản thu chi này thuộc sao kê thẻ tín dụng đã thanh toán nên không thể sửa hoặc lưu trữ.", en: "This cashflow item belongs to a paid credit card statement and cannot be edited or archived.", ja: "この収支は支払い済みのクレジットカード明細に含まれているため、編集やアーカイブはできません。", language: language) }
            static var thisTransactionWillBeArchivedArchivedTransactions: String { L10n.tr("transactions.transactioneditor.thisTransactionWillBeArchivedArchivedTransactions", vi: "Thu chi này sẽ bị lưu trữ. Các khoản thu chi đã lưu trữ sẽ nằm trong \"Mục đã lưu trữ\" và được giữ lại trong 30 ngày.", en: "This cashflow item will be archived. Archived cashflow items will remain in \"Archived items\" for 30 days.", ja: "この取引はアーカイブされます。アーカイブされた取引は「アーカイブ済みアイテム」に30日間保持されます。") }
            static func thisTransactionWillBeArchivedArchivedTransactions(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.thisTransactionWillBeArchivedArchivedTransactions", vi: "Thu chi này sẽ bị lưu trữ. Các khoản thu chi đã lưu trữ sẽ nằm trong \"Mục đã lưu trữ\" và được giữ lại trong 30 ngày.", en: "This cashflow item will be archived. Archived cashflow items will remain in \"Archived items\" for 30 days.", ja: "この取引はアーカイブされます。アーカイブされた取引は「アーカイブ済みアイテム」に30日間保持されます。", language: language) }
            static var toWallet: String { L10n.tr("transactions.transactioneditor.toWallet", vi: "Đến ví", en: "To wallet", ja: "入金先") }
            static func toWallet(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.toWallet", vi: "Đến ví", en: "To wallet", ja: "入金先", language: language) }
            static var transactionNameOptional: String { L10n.tr("transactions.transactioneditor.transactionNameOptional", vi: "Tên khoản thu chi (không bắt buộc)", en: "Cashflow item name (optional)", ja: "収支名（任意）") }
            static func transactionNameOptional(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.transactionNameOptional", vi: "Tên khoản thu chi (không bắt buộc)", en: "Cashflow item name (optional)", ja: "収支名（任意）", language: language) }
            static var transactionType: String { L10n.tr("transactions.transactioneditor.transactionType", vi: "Loại thu chi", en: "Cashflow type", ja: "収支タイプ") }
            static func transactionType(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.transactionType", vi: "Loại thu chi", en: "Cashflow type", ja: "収支タイプ", language: language) }
            static var transferFlow: String { L10n.tr("transactions.transactioneditor.transferFlow", vi: "Luồng chuyển", en: "Transfer flow", ja: "振替の流れ") }
            static func transferFlow(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.transferFlow", vi: "Luồng chuyển", en: "Transfer flow", ja: "振替の流れ", language: language) }
            static func transferPermissionPendingMessage(_ arg1: String, _ arg2: String) -> String {
                L10n.format("transactions.transactioneditor.transferPermissionPendingMessage", vi: "Yêu cầu quyền %@ cho %@ đã được gửi. Làm mới trạng thái quyền từ cloud?", en: "The %@ access request for %@ has already been sent. Refresh access status from cloud?", ja: "%@（%@）の権限リクエストは送信済みです。クラウドから権限状態を更新しますか？", arg1, arg2)
            }
            static func transferPermissionPendingMessage(_ arg1: String, _ arg2: String, language: MistiaAppLanguage) -> String {
                L10n.format("transactions.transactioneditor.transferPermissionPendingMessage", vi: "Yêu cầu quyền %@ cho %@ đã được gửi. Làm mới trạng thái quyền từ cloud?", en: "The %@ access request for %@ has already been sent. Refresh access status from cloud?", ja: "%@（%@）の権限リクエストは送信済みです。クラウドから権限状態を更新しますか？", language: language, arg1, arg2)
            }
            static var transferType: String { L10n.tr("transactions.transactioneditor.transferType", vi: "Kiểu chuyển tiền", en: "Transfer type", ja: "振替タイプ") }
            static func transferType(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.transferType", vi: "Kiểu chuyển tiền", en: "Transfer type", ja: "振替タイプ", language: language) }
            static var useAppRate: String { L10n.tr("transactions.transactioneditor.useAppRate", vi: "Theo app", en: "App rate", ja: "アプリのレート") }
            static func useAppRate(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.useAppRate", vi: "Theo app", en: "App rate", ja: "アプリのレート", language: language) }
            static func usedValueValueReceiptScansToday(_ arg1: String, _ arg2: String) -> String {
                L10n.format("transactions.transactioneditor.usedValueValueReceiptScansToday", vi: "Đã dùng %@/%@ lượt quét bill hôm nay.", en: "Used %@/%@ receipt scans today.", ja: "本日のレシート読み取りは %@/%@ 回使用済みです。", arg1, arg2)
            }
            static func usedValueValueReceiptScansToday(_ arg1: String, _ arg2: String, language: MistiaAppLanguage) -> String {
                L10n.format("transactions.transactioneditor.usedValueValueReceiptScansToday", vi: "Đã dùng %@/%@ lượt quét bill hôm nay.", en: "Used %@/%@ receipt scans today.", ja: "本日のレシート読み取りは %@/%@ 回使用済みです。", language: language, arg1, arg2)
            }
            static var wallet: String { L10n.tr("transactions.transactioneditor.wallet", vi: "Ví", en: "Wallet", ja: "ウォレット") }
            static func wallet(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.wallet", vi: "Ví", en: "Wallet", ja: "ウォレット", language: language) }
            static var walletUsed: String { L10n.tr("transactions.transactioneditor.walletUsed", vi: "Ví thực hiện", en: "Wallet used", ja: "使用ウォレット") }
            static func walletUsed(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.walletUsed", vi: "Ví thực hiện", en: "Wallet used", ja: "使用ウォレット", language: language) }
            static var youDonTHaveAnyWalletsAvailable: String { L10n.tr("transactions.transactioneditor.youDonTHaveAnyWalletsAvailable", vi: "Bạn chưa có ví nào để gắn vào thu chi.", en: "You don't have any wallets available for this cashflow item.", ja: "この取引に使えるウォレットがまだありません。") }
            static func youDonTHaveAnyWalletsAvailable(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.youDonTHaveAnyWalletsAvailable", vi: "Bạn chưa có ví nào để gắn vào thu chi.", en: "You don't have any wallets available for this cashflow item.", ja: "この取引に使えるウォレットがまだありません。", language: language) }
            static var youNeedAvailableCategoriesBeforeAICan: String { L10n.tr("transactions.transactioneditor.youNeedAvailableCategoriesBeforeAICan", vi: "Bạn cần có danh mục phù hợp trước khi AI có thể chọn danh mục cho bill.", en: "You need available categories before AI can choose one for the receipt.", ja: "AIがカテゴリを選ぶには利用可能なカテゴリが必要です。") }
            static func youNeedAvailableCategoriesBeforeAICan(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.youNeedAvailableCategoriesBeforeAICan", vi: "Bạn cần có danh mục phù hợp trước khi AI có thể chọn danh mục cho bill.", en: "You need available categories before AI can choose one for the receipt.", ja: "AIがカテゴリを選ぶには利用可能なカテゴリが必要です。", language: language) }
            static var youNeedToAddAtLeastOne: String { L10n.tr("transactions.transactioneditor.youNeedToAddAtLeastOne", vi: "Bạn cần thêm ít nhất một ví trong tab Quản lý trước khi ghi nhận thu chi hoàn chỉnh.", en: "You need to add at least one wallet in the Manage tab before saving a full cashflow item.", ja: "取引を完全に記録する前に、管理タブで少なくとも 1 つのウォレットを追加してください。") }
            static func youNeedToAddAtLeastOne(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactioneditor.youNeedToAddAtLeastOne", vi: "Bạn cần thêm ít nhất một ví trong tab Quản lý trước khi ghi nhận thu chi hoàn chỉnh.", en: "You need to add at least one wallet in the Manage tab before saving a full cashflow item.", ja: "取引を完全に記録する前に、管理タブで少なくとも 1 つのウォレットを追加してください。", language: language) }
        }

        nonisolated enum transactions {
            static var aFamilyMember: String { L10n.tr("transactions.transactions.aFamilyMember", vi: "thành viên", en: "a family member", ja: "家族メンバー") }
            static func aFamilyMember(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactions.aFamilyMember", vi: "thành viên", en: "a family member", ja: "家族メンバー", language: language) }
            static var adjustment: String { L10n.tr("transactions.transactions.adjustment", vi: "Điều chỉnh số dư", en: "Adjustment", ja: "残高調整") }
            static func adjustment(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactions.adjustment", vi: "Điều chỉnh số dư", en: "Adjustment", ja: "残高調整", language: language) }
            static var all: String { L10n.tr("transactions.transactions.all", vi: "Tất cả", en: "All", ja: "すべて") }
            static func all(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactions.all", vi: "Tất cả", en: "All", ja: "すべて", language: language) }
            static var category: String { L10n.tr("transactions.transactions.category", vi: "Danh mục", en: "Category", ja: "カテゴリ") }
            static func category(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactions.category", vi: "Danh mục", en: "Category", ja: "カテゴリ", language: language) }
            static var clearAllFilters: String { L10n.tr("transactions.transactions.clearAllFilters", vi: "Xoá tất cả bộ lọc", en: "Clear all filters", ja: "すべてのフィルタを解除") }
            static func clearAllFilters(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactions.clearAllFilters", vi: "Xoá tất cả bộ lọc", en: "Clear all filters", ja: "すべてのフィルタを解除", language: language) }
            static var close: String { L10n.tr("transactions.transactions.close", vi: "Đóng", en: "Close", ja: "閉じる") }
            static func close(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactions.close", vi: "Đóng", en: "Close", ja: "閉じる", language: language) }
            static var couldnTExportStatement: String { L10n.tr("transactions.transactions.couldnTExportStatement", vi: "Không thể xuất sao kê", en: "Couldn't export statement", ja: "明細を出力できませんでした") }
            static func couldnTExportStatement(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactions.couldnTExportStatement", vi: "Không thể xuất sao kê", en: "Couldn't export statement", ja: "明細を出力できませんでした", language: language) }
            static var couldnTSend: String { L10n.tr("transactions.transactions.couldnTSend", vi: "Chưa thể gửi", en: "Couldn't send", ja: "送信できませんでした") }
            static func couldnTSend(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactions.couldnTSend", vi: "Chưa thể gửi", en: "Couldn't send", ja: "送信できませんでした", language: language) }
            static var couldnTSendTheRequestRightNow: String { L10n.tr("transactions.transactions.couldnTSendTheRequestRightNow", vi: "Không thể gửi yêu cầu lúc này.", en: "Couldn't send the request right now.", ja: "現在リクエストは送信できません。") }
            static func couldnTSendTheRequestRightNow(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactions.couldnTSendTheRequestRightNow", vi: "Không thể gửi yêu cầu lúc này.", en: "Couldn't send the request right now.", ja: "現在リクエストは送信できません。", language: language) }
            static func createdByValue(_ value: String) -> String {
                L10n.format("transactions.transactions.createdByValue", vi: "Tạo bởi %@", en: "Created by %@", ja: "%@ が作成", value)
            }
            static func createdByValue(_ value: String, language: MistiaAppLanguage) -> String {
                L10n.format("transactions.transactions.createdByValue", vi: "Tạo bởi %@", en: "Created by %@", ja: "%@ が作成", language: language, value)
            }
            static var creditCardStatement: String { L10n.tr("transactions.transactions.creditCardStatement", vi: "Sao kê thẻ tín dụng", en: "Credit card statement", ja: "クレジットカード明細") }
            static func creditCardStatement(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactions.creditCardStatement", vi: "Sao kê thẻ tín dụng", en: "Credit card statement", ja: "クレジットカード明細", language: language) }
            static var debt: String { L10n.tr("transactions.transactions.debt", vi: "Vay & cho vay", en: "Loans", ja: "貸し借り") }
            static func debt(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactions.debt", vi: "Vay & cho vay", en: "Loans", ja: "貸し借り", language: language) }
            static var destination: String { L10n.tr("transactions.transactions.destination", vi: "Đích", en: "Destination", ja: "入金先") }
            static func destination(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactions.destination", vi: "Đích", en: "Destination", ja: "入金先", language: language) }
            static var draftTapToComplete: String { L10n.tr("transactions.transactions.draftTapToComplete", vi: "Bản nháp • Chạm để hoàn thiện", en: "Draft • Tap to complete", ja: "下書き • タップして仕上げる") }
            static func draftTapToComplete(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactions.draftTapToComplete", vi: "Bản nháp • Chạm để hoàn thiện", en: "Draft • Tap to complete", ja: "下書き • タップして仕上げる", language: language) }
            static var editRequestSent: String { L10n.tr("transactions.transactions.editRequestSent", vi: "Đã gửi yêu cầu chỉnh sửa", en: "Edit request sent", ja: "編集リクエスト送信済み") }
            static func editRequestSent(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactions.editRequestSent", vi: "Đã gửi yêu cầu chỉnh sửa", en: "Edit request sent", ja: "編集リクエスト送信済み", language: language) }
            static var expense: String { L10n.tr("transactions.transactions.expense", vi: "Chi", en: "Expense", ja: "支出") }
            static func expense(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactions.expense", vi: "Chi", en: "Expense", ja: "支出", language: language) }
            static var expense2: String { L10n.tr("transactions.transactions.expense2", vi: "Chi tiêu", en: "Expense", ja: "支出") }
            static func expense2(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactions.expense2", vi: "Chi tiêu", en: "Expense", ja: "支出", language: language) }
            static var expenseNeedsDetails: String { L10n.tr("transactions.transactions.expenseNeedsDetails", vi: "Chi tiêu cần hoàn thiện", en: "Expense needs details", ja: "支出の詳細が未入力") }
            static func expenseNeedsDetails(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactions.expenseNeedsDetails", vi: "Chi tiêu cần hoàn thiện", en: "Expense needs details", ja: "支出の詳細が未入力", language: language) }
            static var income: String { L10n.tr("transactions.transactions.income", vi: "Thu", en: "Income", ja: "収入") }
            static func income(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactions.income", vi: "Thu", en: "Income", ja: "収入", language: language) }
            static var income2: String { L10n.tr("transactions.transactions.income2", vi: "Thu nhập", en: "Income", ja: "収入") }
            static func income2(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactions.income2", vi: "Thu nhập", en: "Income", ja: "収入", language: language) }
            static var incomeNeedsDetails: String { L10n.tr("transactions.transactions.incomeNeedsDetails", vi: "Thu nhập cần hoàn thiện", en: "Income needs details", ja: "収入の詳細が未入力") }
            static func incomeNeedsDetails(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactions.incomeNeedsDetails", vi: "Thu nhập cần hoàn thiện", en: "Income needs details", ja: "収入の詳細が未入力", language: language) }
            static var internalTransfer: String { L10n.tr("transactions.transactions.internalTransfer", vi: "Chuyển tiền nội bộ", en: "Internal transfer", ja: "内部振替") }
            static func internalTransfer(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactions.internalTransfer", vi: "Chuyển tiền nội bộ", en: "Internal transfer", ja: "内部振替", language: language) }
            static var loadingMoreTransactions: String { L10n.tr("transactions.transactions.loadingMoreTransactions", vi: "Đang tải thêm thu chi", en: "Loading more cashflow items", ja: "さらに収支を読み込み中") }
            static func loadingMoreTransactions(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactions.loadingMoreTransactions", vi: "Đang tải thêm thu chi", en: "Loading more cashflow items", ja: "さらに収支を読み込み中", language: language) }
            static var noCategorySelected: String { L10n.tr("transactions.transactions.noCategorySelected", vi: "Chưa chọn danh mục", en: "No category selected", ja: "カテゴリ未選択") }
            static func noCategorySelected(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactions.noCategorySelected", vi: "Chưa chọn danh mục", en: "No category selected", ja: "カテゴリ未選択", language: language) }
            static var noMatchingResults: String { L10n.tr("transactions.transactions.noMatchingResults", vi: "Không có kết quả phù hợp", en: "No matching results", ja: "一致する結果はありません") }
            static func noMatchingResults(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactions.noMatchingResults", vi: "Không có kết quả phù hợp", en: "No matching results", ja: "一致する結果はありません", language: language) }
            static var noTransactionEditAccess: String { L10n.tr("transactions.transactions.noTransactionEditAccess", vi: "Chưa có quyền chỉnh sửa thu chi", en: "No cashflow edit access", ja: "収支編集権限がありません") }
            static func noTransactionEditAccess(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactions.noTransactionEditAccess", vi: "Chưa có quyền chỉnh sửa thu chi", en: "No cashflow edit access", ja: "収支編集権限がありません", language: language) }
            static var noTransactionsYet: String { L10n.tr("transactions.transactions.noTransactionsYet", vi: "Chưa có khoản thu chi nào", en: "No cashflow items yet", ja: "収支はまだありません") }
            static func noTransactionsYet(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactions.noTransactionsYet", vi: "Chưa có khoản thu chi nào", en: "No cashflow items yet", ja: "収支はまだありません", language: language) }
            static var noWalletSelected: String { L10n.tr("transactions.transactions.noWalletSelected", vi: "Chưa chọn ví", en: "No wallet selected", ja: "ウォレット未選択") }
            static func noWalletSelected(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactions.noWalletSelected", vi: "Chưa chọn ví", en: "No wallet selected", ja: "ウォレット未選択", language: language) }
            static var openDebts: String { L10n.tr("transactions.transactions.openDebts", vi: "Vay & cho vay đang mở", en: "Open loans", ja: "未解決の貸し借り") }
            static func openDebts(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactions.openDebts", vi: "Vay & cho vay đang mở", en: "Open loans", ja: "未解決の貸し借り", language: language) }
            static var person: String { L10n.tr("transactions.transactions.person", vi: "Người", en: "Person", ja: "相手") }
            static func person(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactions.person", vi: "Người", en: "Person", ja: "相手", language: language) }
            static var requestEditAccess: String { L10n.tr("transactions.transactions.requestEditAccess", vi: "Yêu cầu quyền chỉnh sửa", en: "Request edit access", ja: "編集権限をリクエスト") }
            static func requestEditAccess(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactions.requestEditAccess", vi: "Yêu cầu quyền chỉnh sửa", en: "Request edit access", ja: "編集権限をリクエスト", language: language) }
            static var requestSent: String { L10n.tr("transactions.transactions.requestSent", vi: "Đã gửi yêu cầu", en: "Request sent", ja: "リクエストを送信しました") }
            static func requestSent(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactions.requestSent", vi: "Đã gửi yêu cầu", en: "Request sent", ja: "リクエストを送信しました", language: language) }
            static var searchEmptyMessage: String { L10n.tr("transactions.transactions.searchEmptyMessage", vi: "Nhập tên, ghi chú hoặc người liên quan để tìm thu chi.", en: "Enter a name, note, or person to find cashflow items.", ja: "名前、メモ、相手を入力して取引を検索します。") }
            static func searchEmptyMessage(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactions.searchEmptyMessage", vi: "Nhập tên, ghi chú hoặc người liên quan để tìm thu chi.", en: "Enter a name, note, or person to find cashflow items.", ja: "名前、メモ、相手を入力して取引を検索します。", language: language) }
            static var searchEmptyTitle: String { L10n.tr("transactions.transactions.searchEmptyTitle", vi: "Tìm thu chi", en: "Search cashflow", ja: "収支を検索") }
            static func searchEmptyTitle(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactions.searchEmptyTitle", vi: "Tìm thu chi", en: "Search cashflow", ja: "収支を検索", language: language) }
            static var searchNoResultsMessage: String { L10n.tr("transactions.transactions.searchNoResultsMessage", vi: "Không có khoản thu chi nào khớp với từ khóa này.", en: "No cashflow items match this search.", ja: "この検索に一致する収支はありません。") }
            static func searchNoResultsMessage(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactions.searchNoResultsMessage", vi: "Không có khoản thu chi nào khớp với từ khóa này.", en: "No cashflow items match this search.", ja: "この検索に一致する収支はありません。", language: language) }
            static var searchTransactionName: String { L10n.tr("transactions.transactions.searchTransactionName", vi: "Tìm tên khoản thu chi...", en: "Search cashflow item name...", ja: "収支名を検索...") }
            static func searchTransactionName(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactions.searchTransactionName", vi: "Tìm tên khoản thu chi...", en: "Search cashflow item name...", ja: "収支名を検索...", language: language) }
            static var source: String { L10n.tr("transactions.transactions.source", vi: "Nguồn", en: "Source", ja: "出金元") }
            static func source(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactions.source", vi: "Nguồn", en: "Source", ja: "出金元", language: language) }
            static var statement: String { L10n.tr("transactions.transactions.statement", vi: "Sao kê", en: "Statement", ja: "明細") }
            static func statement(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactions.statement", vi: "Sao kê", en: "Statement", ja: "明細", language: language) }
            static var summaryStatement: String { L10n.tr("transactions.transactions.summaryStatement", vi: "Sao kê tổng hợp", en: "Summary statement", ja: "サマリー明細") }
            static func summaryStatement(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactions.summaryStatement", vi: "Sao kê tổng hợp", en: "Summary statement", ja: "サマリー明細", language: language) }
            static var thePermissionRequestWasSentToThe: String { L10n.tr("transactions.transactions.thePermissionRequestWasSentToThe", vi: "Yêu cầu quyền đã được gửi tới chủ dữ liệu.", en: "The permission request was sent to the data owner.", ja: "権限リクエストをデータ所有者へ送信しました。") }
            static func thePermissionRequestWasSentToThe(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactions.thePermissionRequestWasSentToThe", vi: "Yêu cầu quyền đã được gửi tới chủ dữ liệu.", en: "The permission request was sent to the data owner.", ja: "権限リクエストをデータ所有者へ送信しました。", language: language) }
            static var theyOweYou: String { L10n.tr("transactions.transactions.theyOweYou", vi: "Đang nợ bạn", en: "They owe you", ja: "相手があなたに返す") }
            static func theyOweYou(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactions.theyOweYou", vi: "Đang nợ bạn", en: "They owe you", ja: "相手があなたに返す", language: language) }
            static var time: String { L10n.tr("transactions.transactions.time", vi: "Thời gian", en: "Time", ja: "期間") }
            static func time(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactions.time", vi: "Thời gian", en: "Time", ja: "期間", language: language) }
            static var transaction: String { L10n.tr("transactions.transactions.transaction", vi: "thu chi", en: "cashflow", ja: "収支") }
            static func transaction(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactions.transaction", vi: "thu chi", en: "cashflow", ja: "収支", language: language) }
            static var transactions: String { L10n.tr("transactions.transactions.transactions", vi: "Thu chi", en: "Cashflow", ja: "収支") }
            static func transactions(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactions.transactions", vi: "Thu chi", en: "Cashflow", ja: "収支", language: language) }
            static var transfer: String { L10n.tr("transactions.transactions.transfer", vi: "Chuyển tiền", en: "Transfer", ja: "振替") }
            static func transfer(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactions.transfer", vi: "Chuyển tiền", en: "Transfer", ja: "振替", language: language) }
            static var transferNeedsDetails: String { L10n.tr("transactions.transactions.transferNeedsDetails", vi: "Chuyển tiền cần hoàn thiện", en: "Transfer needs details", ja: "振替の詳細が未入力") }
            static func transferNeedsDetails(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactions.transferNeedsDetails", vi: "Chuyển tiền cần hoàn thiện", en: "Transfer needs details", ja: "振替の詳細が未入力", language: language) }
            static var tryAdjustingTheTimeRangeWalletFilters: String { L10n.tr("transactions.transactions.tryAdjustingTheTimeRangeWalletFilters", vi: "Thử đổi thời gian, ví, bộ lọc hoặc từ khóa tìm kiếm để xem thêm thu chi.", en: "Try adjusting the time range, wallet, filters, or search keyword to see more cashflow items.", ja: "期間、ウォレット、フィルタ、検索キーワードを変更すると、ほかの取引を確認できます。") }
            static func tryAdjustingTheTimeRangeWalletFilters(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactions.tryAdjustingTheTimeRangeWalletFilters", vi: "Thử đổi thời gian, ví, bộ lọc hoặc từ khóa tìm kiếm để xem thêm thu chi.", en: "Try adjusting the time range, wallet, filters, or search keyword to see more cashflow items.", ja: "期間、ウォレット、フィルタ、検索キーワードを変更すると、ほかの取引を確認できます。", language: language) }
            static var type: String { L10n.tr("transactions.transactions.type", vi: "Phân loại", en: "Type", ja: "種類") }
            static func type(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactions.type", vi: "Phân loại", en: "Type", ja: "種類", language: language) }
            static var unknownName: String { L10n.tr("transactions.transactions.unknownName", vi: "Không rõ tên", en: "Unknown name", ja: "名前未設定") }
            static func unknownName(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactions.unknownName", vi: "Không rõ tên", en: "Unknown name", ja: "名前未設定", language: language) }
            static func valueActiveFilters(_ value: String) -> String {
                L10n.format("transactions.transactions.valueActiveFilters", vi: "%@ bộ lọc đang áp dụng", en: "%@ active filters", ja: "%@ 個のフィルタを適用中", value)
            }
            static func valueActiveFilters(_ value: String, language: MistiaAppLanguage) -> String {
                L10n.format("transactions.transactions.valueActiveFilters", vi: "%@ bộ lọc đang áp dụng", en: "%@ active filters", ja: "%@ 個のフィルタを適用中", language: language, value)
            }
            static func valueDrafts(_ value: String) -> String {
                L10n.format("transactions.transactions.valueDrafts", vi: "%@ nháp", en: "%@ drafts", ja: "下書き %@ 件", value)
            }
            static func valueDrafts(_ value: String, language: MistiaAppLanguage) -> String {
                L10n.format("transactions.transactions.valueDrafts", vi: "%@ nháp", en: "%@ drafts", ja: "下書き %@ 件", language: language, value)
            }
            static func valueItems(_ value: String) -> String {
                L10n.format("transactions.transactions.valueItems", vi: "%@ mục", en: "%@ items", ja: "%@ 件", value)
            }
            static func valueItems(_ value: String, language: MistiaAppLanguage) -> String {
                L10n.format("transactions.transactions.valueItems", vi: "%@ mục", en: "%@ items", ja: "%@ 件", language: language, value)
            }
            static var wallet: String { L10n.tr("transactions.transactions.wallet", vi: "Ví", en: "Wallet", ja: "ウォレット") }
            static func wallet(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactions.wallet", vi: "Ví", en: "Wallet", ja: "ウォレット", language: language) }
            static var whenYouAddAnExpenseIncomeTransfer: String { L10n.tr("transactions.transactions.whenYouAddAnExpenseIncomeTransfer", vi: "Khi bạn thêm chi tiêu, thu nhập, chuyển tiền hoặc ghi nhanh từ nút plus, lịch sử sẽ xuất hiện ở đây.", en: "When you add an expense, income, transfer, or quick capture from the plus button, your history will appear here.", ja: "支出、収入、振替、またはプラスボタンからクイック記録を追加すると、ここに履歴が表示されます。") }
            static func whenYouAddAnExpenseIncomeTransfer(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactions.whenYouAddAnExpenseIncomeTransfer", vi: "Khi bạn thêm chi tiêu, thu nhập, chuyển tiền hoặc ghi nhanh từ nút plus, lịch sử sẽ xuất hiện ở đây.", en: "When you add an expense, income, transfer, or quick capture from the plus button, your history will appear here.", ja: "支出、収入、振替、またはプラスボタンからクイック記録を追加すると、ここに履歴が表示されます。", language: language) }
            static var youDoNotHavePermissionToEdit: String { L10n.tr("transactions.transactions.youDoNotHavePermissionToEdit", vi: "Bạn chưa có quyền chỉnh sửa thu chi của thành viên này.", en: "You do not have permission to edit this member's cashflow items.", ja: "このメンバーの取引を編集する権限がありません。") }
            static func youDoNotHavePermissionToEdit(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactions.youDoNotHavePermissionToEdit", vi: "Bạn chưa có quyền chỉnh sửa thu chi của thành viên này.", en: "You do not have permission to edit this member's cashflow items.", ja: "このメンバーの取引を編集する権限がありません。", language: language) }
            static var youOwe: String { L10n.tr("transactions.transactions.youOwe", vi: "Bạn đang nợ", en: "You owe", ja: "あなたが支払う") }
            static func youOwe(language: MistiaAppLanguage) -> String { L10n.tr("transactions.transactions.youOwe", vi: "Bạn đang nợ", en: "You owe", ja: "あなたが支払う", language: language) }
        }
    }
}
