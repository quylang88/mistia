import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import Mistia

@MainActor
final class AIBillReviewPresentationTests: XCTestCase {
    func testReceiptReviewLightAndDarkLayouts() async throws {
        let schema = Schema(versionedSchema: MistiaSchemaV1.self)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "AIBillReviewPresentationTests.\(UUID())"))
        let session = SessionStore(modelContainer: container, userDefaults: defaults,
                                   connectivityMonitor: SessionConnectivityMonitor(initialStatus: .disconnected), registerBackgroundRefresh: false)
        let userID = UUID()
        session.summary = SessionSummary(userID: userID, displayName: "Receipt test", email: "receipt@example.com", avatarURL: nil)
        let family = FamilyContextStore(modelContainer: container)
        let chrome = MistiaUIState()
        let wallet = LedgerWallet(name: "PayPay", kind: .bank, iconSymbolName: "creditcard", iconColorHex: "#A673FA")
        container.mainContext.insert(wallet)
        let parent = TransactionCategory(name: "Sinh hoạt", kind: .expense, iconSymbolName: "house", iconColorHex: "#A673FA", hierarchyRole: .parent)
        let category = TransactionCategory(name: "Đồ tiêu dùng", kind: .expense, iconSymbolName: "tag", iconColorHex: "#A673FA", parentCategory: parent, hierarchyRole: .child)
        container.mainContext.insert(parent)
        container.mainContext.insert(category)
        container.mainContext.insert(OwnedRecordScope(entity: .wallet, recordID: wallet.id, ownerUserID: userID))
        container.mainContext.insert(OwnedRecordScope(entity: .category, recordID: category.id, ownerUserID: userID))
        try container.mainContext.save()
        let thumbnail = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 160)).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 120, height: 160))
            "CAINZ".draw(at: CGPoint(x: 15, y: 20), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 22), .foregroundColor: UIColor.black])
        }
        var bill = AIBillDraft(thumbnail: thumbnail, imageData: try XCTUnwrap(thumbnail.pngData()), contentType: "image/png")
        let items = [
            BillItemAnalysisItem(lineID: "softymo", originalName: "ソフティモ", rawLineText: "073 ソフティモ\n@298 10 ¥2,980\nM01まとめ売り値下 -¥200", translatedName: "Sản phẩm chăm sóc da Softymo", quantity: 10, originalAmountMinor: 2980, discountAmountMinor: 200, finalAmountMinor: 2780, categoryID: category.id, confidence: 0.95),
            BillItemAnalysisItem(lineID: "pen", originalName: "ボールペン替芯", translatedName: "Ruột bút bi thay thế", originalAmountMinor: 48, finalAmountMinor: 48, categoryID: category.id, confidence: 0.95),
            BillItemAnalysisItem(lineID: "note", originalName: "付箋", translatedName: "Giấy ghi chú", originalAmountMinor: 128, finalAmountMinor: 128, categoryID: category.id, confidence: 0.95),
        ]
        bill.result = BillItemAnalysisResult(merchantName: "CAINZ 新座店", totalMinor: 2956, currencyCode: "JPY", walletID: wallet.id, confidence: 0.95, items: items)
        bill.walletID = wallet.id
        let previousLanguage = UserDefaults.standard.string(forKey: MistiaAppStorageKey.appLanguage)
        UserDefaults.standard.set("vi", forKey: MistiaAppStorageKey.appLanguage)
        defer { UserDefaults.standard.set(previousLanguage, forKey: MistiaAppStorageKey.appLanguage) }
        for scheme in [ColorScheme.light, .dark] {
            let content = NavigationStack { AIBillAnalysisView(initialBills: [bill]) }
                .modelContainer(container).environment(session).environment(family).environment(chrome)
                .environment(\.colorScheme, scheme)
            let host = UIHostingController(rootView: content)
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
            window.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
            window.rootViewController = host
            window.makeKeyAndVisible()
            host.view.frame = window.bounds
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(500))
            XCTAssertTrue(chrome.isTabBarHidden)
            let screenshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let pixels = try XCTUnwrap(screenshot.cgImage?.dataProvider?.data) as Data
            let sampledColors = Set(stride(from: 0, to: pixels.count, by: 64).map { pixels[$0] })
            XCTAssertGreaterThan(sampledColors.count, 8, "Receipt snapshot must contain visible content")
            let attachment = XCTAttachment(image: screenshot)
            attachment.name = "bill-review-\(scheme)"
            attachment.lifetime = .keepAlways
            add(attachment)
            window.isHidden = true
            window.rootViewController = nil
        }
    }

    func testItemEditorDisplaysPrintedQuantityAndDiscount() async throws {
        let item = BillItemAnalysisItem(lineID: "softymo", originalName: "ソフティモ", rawLineText: "073 ソフティモ\n@298 10 ¥2,980\nM01まとめ売り値下 -¥200", translatedName: "Sản phẩm chăm sóc da Softymo", quantity: 10, originalAmountMinor: 2980, discountAmountMinor: 200, finalAmountMinor: 2780, confidence: 1)
        let content = AIBillItemEditorSheet(item: item, currencyCode: "JPY", onSave: { _ in })
            .environment(\.colorScheme, .dark)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.overrideUserInterfaceStyle = .dark
        let host = UIHostingController(rootView: content)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(500))
        let screenshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: screenshot)
        attachment.name = "bill-item-editor-dark"
        attachment.lifetime = .keepAlways
        add(attachment)
        window.isHidden = true
        window.rootViewController = nil
    }

    func testItemDetailsGrowForAccessibilityTextWithoutHorizontalOverflow() {
        let item = BillItemAnalysisItem(lineID: "item", originalName: "L3 ライオン ホワイト＆赤", translatedName: "Kem đánh răng Lion White & Red", quantity: 10, originalAmountMinor: 2280, finalAmountMinor: 2280, confidence: 0.95)
        let regular = UIHostingController(rootView: AIBillItemSummary(item: item, currencyCode: "JPY", amountMinor: 2280).environment(\.dynamicTypeSize, .large))
        let accessible = UIHostingController(rootView: AIBillItemSummary(item: item, currencyCode: "JPY", amountMinor: 2280).environment(\.dynamicTypeSize, .accessibility3))
        let proposed = CGSize(width: 280, height: 2000)
        let regularSize = regular.sizeThatFits(in: proposed)
        let accessibleSize = accessible.sizeThatFits(in: proposed)
        XCTAssertLessThanOrEqual(accessibleSize.width, 280)
        XCTAssertGreaterThan(accessibleSize.height, regularSize.height)
    }
}
