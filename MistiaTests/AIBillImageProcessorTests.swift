import UIKit
import XCTest
@testable import Mistia

final class AIBillImageProcessorTests: XCTestCase {
    func testMakeDraftKeepsDetailedReceiptPayloadBelowServerLimit() throws {
        let image = makeDetailedReceiptImage(size: CGSize(width: 2_400, height: 3_200))

        let draft = try XCTUnwrap(AIBillImageProcessor.makeDraft(from: image))

        XCTAssertLessThanOrEqual(draft.imageData.count, 3_800_000)
        XCTAssertEqual(draft.contentType, "image/jpeg")
        XCTAssertGreaterThan(draft.image.size.width, 0)
        XCTAssertGreaterThan(draft.thumbnail.size.width, 0)
    }

    private func makeDetailedReceiptImage(size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineBreakMode = .byClipping
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 21, weight: .medium),
                .foregroundColor: UIColor.black,
                .paragraphStyle: paragraphStyle
            ]

            for index in 0..<108 {
                let y = 24 + index * 28
                let text = String(
                    format: "%03d  スーパー玉出 商品 %03d  ¥%04d   %@",
                    index,
                    index,
                    120 + index,
                    String(repeating: "\(index % 10)", count: 40)
                )
                text.draw(in: CGRect(x: 28, y: y, width: Int(size.width) - 56, height: 24), withAttributes: attributes)
            }

            for y in stride(from: 0, to: Int(size.height), by: 3) {
                UIColor(white: CGFloat((y * 37) % 255) / 255.0, alpha: 0.12).setStroke()
                context.cgContext.move(to: CGPoint(x: 0, y: y))
                context.cgContext.addLine(to: CGPoint(x: size.width, y: CGFloat(y)))
                context.cgContext.strokePath()
            }
        }
    }
}
