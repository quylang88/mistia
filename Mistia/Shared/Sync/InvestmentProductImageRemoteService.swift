import Foundation
import UIKit

struct InvestmentProductImageRemoteService {
    private let configurationProvider: () -> MistiaSyncConfiguration?
    private let cache: InvestmentProductImageStore

    init(
        configurationProvider: @escaping () -> MistiaSyncConfiguration? = { MistiaSyncConfiguration.load() },
        cache: InvestmentProductImageStore = InvestmentProductImageStore()
    ) {
        self.configurationProvider = configurationProvider
        self.cache = cache
    }

    func jpegData(path: String, session: SupabaseAuthSession?) async throws -> Data? {
        if let cached = try cache.cachedThumbnailData(for: path) {
            return cached
        }
        guard let session, let configuration = configurationProvider() else { return nil }
        let url = path.split(separator: "/").reduce(
            configuration.projectURL
                .appending(path: "storage")
                .appending(path: "v1")
                .appending(path: "object")
                .appending(path: "investment-product-images")
        ) { url, component in
            url.appending(path: String(component))
        }
        var request = URLRequest(url: url)
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 404 { return nil }
            throw SupabaseServiceError.invalidResponse
        }
        try cache.cacheDownloadedJPEG(
            data,
            thumbnailData: thumbnailJPEG(from: data),
            for: path
        )
        return data
    }

    private func thumbnailJPEG(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let longEdge = max(image.size.width, image.size.height)
        let scale = longEdge > 240 ? 240 / longEdge : 1
        let size = CGSize(
            width: max(1, image.size.width * scale),
            height: max(1, image.size.height * scale)
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            UIColor.systemBackground.setFill()
            UIRectFill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }.jpegData(compressionQuality: 0.78)
    }
}
