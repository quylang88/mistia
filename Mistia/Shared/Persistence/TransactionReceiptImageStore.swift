import Foundation
import SwiftData

nonisolated struct TransactionReceiptImageStore {
    let fileManager: FileManager
    let baseDirectory: URL

    nonisolated init(
        fileManager: FileManager = .default,
        baseDirectory: URL? = nil
    ) {
        self.fileManager = fileManager
        self.baseDirectory = baseDirectory ?? TransactionReceiptImageStore.defaultBaseDirectory(fileManager: fileManager)
    }

    static func defaultBaseDirectory(fileManager: FileManager = .default) -> URL {
        let supportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return supportDirectory
            .appending(path: "Mistia", directoryHint: .isDirectory)
            .appending(path: "ReceiptImages", directoryHint: .isDirectory)
    }

    func receipt(
        for transactionID: UUID,
        context: ModelContext
    ) throws -> TransactionReceiptImage? {
        var descriptor = FetchDescriptor<TransactionReceiptImage>(
            predicate: #Predicate<TransactionReceiptImage> { receipt in
                receipt.transactionID == transactionID
            },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func replaceReceipt(
        for transactionID: UUID,
        imageData: Data,
        thumbnailData: Data,
        contentType: String = "image/jpeg",
        context: ModelContext,
        saveContext: Bool = true
    ) throws -> TransactionReceiptImage {
        try ensureDirectoryExists()

        let imageFileName = fileName(transactionID: transactionID, prefix: "receipt")
        let thumbnailFileName = fileName(transactionID: transactionID, prefix: "thumb")
        let imageURL = url(forFileName: imageFileName)
        let thumbnailURL = url(forFileName: thumbnailFileName)

        try imageData.write(to: imageURL, options: [.atomic])
        try thumbnailData.write(to: thumbnailURL, options: [.atomic])

        do {
            for existing in try receipts(for: transactionID, context: context) {
                try removeFiles(for: existing)
                context.delete(existing)
            }

            let now = Date()
            let receipt = TransactionReceiptImage(
                transactionID: transactionID,
                imageFileName: imageFileName,
                thumbnailFileName: thumbnailFileName,
                contentType: contentType,
                byteCount: imageData.count,
                createdAt: now,
                updatedAt: now
            )
            context.insert(receipt)

            if saveContext {
                try context.save()
            }

            return receipt
        } catch {
            try? fileManager.removeItem(at: imageURL)
            try? fileManager.removeItem(at: thumbnailURL)
            throw error
        }
    }

    nonisolated func deleteReceipt(
        for transactionID: UUID,
        context: ModelContext,
        saveContext: Bool = true
    ) throws {
        for receipt in try receipts(for: transactionID, context: context) {
            try removeFiles(for: receipt)
            context.delete(receipt)
        }

        if saveContext {
            try context.save()
        }
    }

    func deleteAll(
        context: ModelContext,
        saveContext: Bool = true
    ) throws {
        for receipt in try context.fetch(FetchDescriptor<TransactionReceiptImage>()) {
            context.delete(receipt)
        }

        if fileManager.fileExists(atPath: baseDirectory.path) {
            try fileManager.removeItem(at: baseDirectory)
        }

        if saveContext {
            try context.save()
        }
    }

    func imageData(for receipt: TransactionReceiptImage) throws -> Data {
        try Data(contentsOf: url(forFileName: receipt.imageFileName))
    }

    func thumbnailData(for receipt: TransactionReceiptImage) throws -> Data {
        try Data(contentsOf: url(forFileName: receipt.thumbnailFileName))
    }

    func url(forFileName fileName: String) -> URL {
        baseDirectory.appending(path: fileName, directoryHint: .notDirectory)
    }

    private func receipts(
        for transactionID: UUID,
        context: ModelContext
    ) throws -> [TransactionReceiptImage] {
        let descriptor = FetchDescriptor<TransactionReceiptImage>(
            predicate: #Predicate<TransactionReceiptImage> { receipt in
                receipt.transactionID == transactionID
            },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    private func ensureDirectoryExists() throws {
        try fileManager.createDirectory(
            at: baseDirectory,
            withIntermediateDirectories: true
        )
    }

    private func removeFiles(for receipt: TransactionReceiptImage) throws {
        for fileName in [receipt.imageFileName, receipt.thumbnailFileName] {
            let fileURL = url(forFileName: fileName)
            if fileManager.fileExists(atPath: fileURL.path) {
                try fileManager.removeItem(at: fileURL)
            }
        }
    }

    private func fileName(transactionID: UUID, prefix: String) -> String {
        "\(prefix)-\(transactionID.uuidString.lowercased())-\(UUID().uuidString.lowercased()).jpg"
    }
}
