import Foundation

struct BillItemAnalysisRequestPayload: Codable, Equatable {
    let imageBase64: String
    let mimeType: String
    let localeIdentifier: String
    let timeZoneIdentifier: String
    let currencyCode: String
    let targetLanguageCode: String
    let categories: [ReceiptAnalysisCategoryCandidate]
    let wallets: [ReceiptAnalysisWalletCandidate]

    enum CodingKeys: String, CodingKey {
        case imageBase64 = "image_base64"
        case mimeType = "mime_type"
        case localeIdentifier = "locale_identifier"
        case timeZoneIdentifier = "time_zone_identifier"
        case currencyCode = "currency_code"
        case targetLanguageCode = "target_language_code"
        case categories
        case wallets
    }
}

struct BillItemAnalysisItem: Codable, Equatable, Identifiable {
    let lineID: String
    var originalName: String
    var translatedName: String?
    var finalAmountMinor: Int64
    var categoryID: UUID?
    var confidence: Double
    var missingFields: [String]

    var id: String { lineID }

    enum CodingKeys: String, CodingKey {
        case lineID = "line_id"
        case originalName = "original_name"
        case translatedName = "translated_name"
        case finalAmountMinor = "final_amount_minor"
        case categoryID = "category_id"
        case confidence
        case missingFields = "missing_fields"
    }

    init(
        lineID: String,
        originalName: String,
        translatedName: String? = nil,
        finalAmountMinor: Int64,
        categoryID: UUID? = nil,
        confidence: Double,
        missingFields: [String] = []
    ) {
        self.lineID = lineID.nilIfBlank ?? UUID().uuidString
        self.originalName = originalName.nilIfBlank ?? ""
        self.translatedName = translatedName?.nilIfBlank
        self.finalAmountMinor = max(0, finalAmountMinor)
        self.categoryID = categoryID
        self.confidence = max(0, min(1, confidence))
        self.missingFields = missingFields
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lineID = try container.decodeTrimmedStringIfPresent(forKey: .lineID) ?? UUID().uuidString
        originalName = try container.decodeTrimmedStringIfPresent(forKey: .originalName) ?? ""
        translatedName = try container.decodeTrimmedStringIfPresent(forKey: .translatedName)
        finalAmountMinor = max(0, try container.decodeFlexibleInt64(forKey: .finalAmountMinor, defaultValue: 0))
        categoryID = try container.decodeUUIDIfPresent(forKey: .categoryID)
        confidence = try container.decodeFlexibleDouble(forKey: .confidence, defaultValue: 0)
        missingFields = try container.decodeStringArrayIfPresent(forKey: .missingFields)
    }
}

struct BillItemAnalysisResult: Codable, Equatable {
    var merchantName: String?
    var totalMinor: Int64?
    var currencyCode: String?
    var occurredAt: Date?
    var walletID: UUID?
    var multipleBillsDetected: Bool
    var confidence: Double
    var missingFields: [String]
    var rawText: String?
    var items: [BillItemAnalysisItem]
    var quota: ReceiptAnalysisQuota?

    enum CodingKeys: String, CodingKey {
        case merchantName = "merchant_name"
        case totalMinor = "total_minor"
        case currencyCode = "currency_code"
        case occurredAt = "occurred_at"
        case walletID = "wallet_id"
        case multipleBillsDetected = "multiple_bills_detected"
        case confidence
        case missingFields = "missing_fields"
        case rawText = "raw_text"
        case items
        case quota
    }

    init(
        merchantName: String? = nil,
        totalMinor: Int64? = nil,
        currencyCode: String? = nil,
        occurredAt: Date? = nil,
        walletID: UUID? = nil,
        multipleBillsDetected: Bool = false,
        confidence: Double,
        missingFields: [String] = [],
        rawText: String? = nil,
        items: [BillItemAnalysisItem] = [],
        quota: ReceiptAnalysisQuota? = nil
    ) {
        self.merchantName = merchantName?.nilIfBlank
        self.totalMinor = totalMinor
        self.currencyCode = currencyCode?.nilIfBlank?.uppercased()
        self.occurredAt = occurredAt
        self.walletID = walletID
        self.multipleBillsDetected = multipleBillsDetected
        self.confidence = max(0, min(1, confidence))
        self.missingFields = missingFields
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        self.rawText = rawText?.nilIfBlank
        self.items = items
        self.quota = quota
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        merchantName = try container.decodeTrimmedStringIfPresent(forKey: .merchantName)
        totalMinor = try container.decodeFlexibleInt64IfPresent(forKey: .totalMinor)
        currencyCode = try container.decodeTrimmedStringIfPresent(forKey: .currencyCode)?.uppercased()
        occurredAt = try container.decodeBillDateIfPresent(forKey: .occurredAt)
        walletID = try container.decodeUUIDIfPresent(forKey: .walletID)
        multipleBillsDetected = try container.decodeIfPresent(Bool.self, forKey: .multipleBillsDetected) ?? false
        confidence = try container.decodeFlexibleDouble(forKey: .confidence, defaultValue: 0)
        missingFields = try container.decodeStringArrayIfPresent(forKey: .missingFields)
        rawText = try container.decodeTrimmedStringIfPresent(forKey: .rawText)
        items = try container.decodeIfPresent([BillItemAnalysisItem].self, forKey: .items) ?? []
        quota = try container.decodeIfPresent(ReceiptAnalysisQuota.self, forKey: .quota)
    }

    func validated(categoryIDs: Set<UUID>, walletIDs: Set<UUID>) -> BillItemAnalysisResult {
        var copy = self
        var missing = Set(copy.missingFields)

        if let walletID, !walletIDs.contains(walletID) {
            copy.walletID = nil
            missing.insert("walletID")
        }

        copy.items = copy.items.map { item in
            var next = item
            if let categoryID = item.categoryID, !categoryIDs.contains(categoryID) {
                next.categoryID = nil
                var itemMissing = Set(next.missingFields)
                itemMissing.insert("categoryID")
                next.missingFields = Array(itemMissing).sorted()
                missing.insert("itemCategoryID")
            }
            return next
        }

        copy.missingFields = Array(missing).sorted()
        return copy
    }
}

enum BillItemTransactionMode: String, CaseIterable, Codable, Equatable {
    case expense
    case lend
}

struct BillItemSelectionID: Hashable, Codable, Equatable {
    let billID: UUID
    let itemID: String
}

struct BillItemSelectionCandidate: Hashable, Codable, Equatable {
    let id: BillItemSelectionID
    let walletID: UUID?
    let categoryID: UUID?
    let amountMinor: Int64
    let merchantName: String?
    let occurredAt: Date?
    let isCreated: Bool

    init(
        id: BillItemSelectionID,
        walletID: UUID?,
        categoryID: UUID?,
        amountMinor: Int64,
        merchantName: String? = nil,
        occurredAt: Date? = nil,
        isCreated: Bool = false
    ) {
        self.id = id
        self.walletID = walletID
        self.categoryID = categoryID
        self.amountMinor = max(0, amountMinor)
        self.merchantName = merchantName?.nilIfBlank
        self.occurredAt = occurredAt
        self.isCreated = isCreated
    }
}

struct BillItemTransactionDraft: Equatable {
    let primaryKind: TransactionPrimaryKind
    let transferSubtype: TransactionTransferSubtype?
    let debtIntent: TransactionDebtIntent?
    let amountMinor: Int64
    let title: String
    let walletID: UUID
    let categoryID: UUID?
    let occurredAt: Date
    let receiptAttachmentBillID: UUID?
}

enum BillItemSelectionLogic {
    static func canSelect(
        _ candidate: BillItemSelectionCandidate,
        selected: [BillItemSelectionCandidate],
        mode: BillItemTransactionMode
    ) -> Bool {
        guard !candidate.isCreated,
              candidate.amountMinor > 0,
              candidate.walletID != nil else {
            return false
        }

        if mode == .expense, candidate.categoryID == nil {
            return false
        }

        guard let anchor = selected.first else {
            return true
        }

        switch mode {
        case .expense:
            return candidate.walletID == anchor.walletID
                && candidate.categoryID == anchor.categoryID
        case .lend:
            return candidate.walletID == anchor.walletID
        }
    }

    static func normalizedSelection(
        _ selection: Set<BillItemSelectionID>,
        candidates: [BillItemSelectionCandidate],
        mode: BillItemTransactionMode
    ) -> Set<BillItemSelectionID> {
        let selectedCandidates = candidates.filter { selection.contains($0.id) && !$0.isCreated }
        guard let anchor = selectedCandidates.first,
              canSelect(anchor, selected: [], mode: mode) else {
            return []
        }

        let normalized = selectedCandidates.filter { candidate in
            candidate.id == anchor.id || canSelect(candidate, selected: [anchor], mode: mode)
        }
        return Set(normalized.map(\.id))
    }

    static func transactionDraft(
        for selected: [BillItemSelectionCandidate],
        mode: BillItemTransactionMode,
        fallbackDate: Date
    ) -> BillItemTransactionDraft? {
        let candidates = selected.filter { !$0.isCreated && $0.amountMinor > 0 }
        guard !candidates.isEmpty,
              let walletID = candidates.first?.walletID,
              candidates.allSatisfy({ $0.walletID == walletID }) else {
            return nil
        }

        let categoryID: UUID?
        switch mode {
        case .expense:
            guard let firstCategoryID = candidates.first?.categoryID,
                  candidates.allSatisfy({ $0.categoryID == firstCategoryID }) else {
                return nil
            }
            categoryID = firstCategoryID
        case .lend:
            categoryID = nil
        }

        let amountMinor = candidates.reduce(Int64.zero) { partial, candidate in
            partial + candidate.amountMinor
        }
        guard amountMinor > 0 else { return nil }

        let title = sharedMerchantName(in: candidates) ?? ""
        let occurredAt = sharedOccurredAt(in: candidates) ?? fallbackDate
        let billIDs = Set(candidates.map(\.id.billID))
        let attachmentBillID = billIDs.count == 1 ? billIDs.first : nil

        switch mode {
        case .expense:
            return BillItemTransactionDraft(
                primaryKind: .expense,
                transferSubtype: nil,
                debtIntent: nil,
                amountMinor: amountMinor,
                title: title,
                walletID: walletID,
                categoryID: categoryID,
                occurredAt: occurredAt,
                receiptAttachmentBillID: attachmentBillID
            )
        case .lend:
            return BillItemTransactionDraft(
                primaryKind: .transfer,
                transferSubtype: .debt,
                debtIntent: .lend,
                amountMinor: amountMinor,
                title: title,
                walletID: walletID,
                categoryID: nil,
                occurredAt: occurredAt,
                receiptAttachmentBillID: attachmentBillID
            )
        }
    }

    private static func sharedMerchantName(in candidates: [BillItemSelectionCandidate]) -> String? {
        let names = Set(candidates.compactMap { $0.merchantName?.nilIfBlank })
        return names.count == 1 ? names.first : nil
    }

    private static func sharedOccurredAt(in candidates: [BillItemSelectionCandidate]) -> Date? {
        let dates = candidates.compactMap(\.occurredAt)
        guard dates.count == candidates.count else { return nil }
        return Set(dates).count == 1 ? dates.first : nil
    }
}

private extension KeyedDecodingContainer {
    func decodeTrimmedStringIfPresent(forKey key: K) throws -> String? {
        guard contains(key), !(try decodeNil(forKey: key)) else { return nil }
        let value = try decode(String.self, forKey: key)
        return value.nilIfBlank
    }

    func decodeFlexibleInt64IfPresent(forKey key: K) throws -> Int64? {
        guard contains(key), !(try decodeNil(forKey: key)) else { return nil }
        return try decodeFlexibleInt64(forKey: key, defaultValue: 0)
    }

    func decodeFlexibleInt64(forKey key: K, defaultValue: Int64) throws -> Int64 {
        guard contains(key), !(try decodeNil(forKey: key)) else { return defaultValue }

        if let value = try? decode(Int64.self, forKey: key) {
            return value
        }

        if let value = try? decode(Double.self, forKey: key), value.isFinite {
            return Int64(value.rounded())
        }

        if let string = try? decode(String.self, forKey: key) {
            let sanitized = string.replacingOccurrences(
                of: "[^0-9-]",
                with: "",
                options: .regularExpression
            )
            return sanitized.isEmpty ? defaultValue : (Int64(sanitized) ?? defaultValue)
        }

        throw DecodingError.dataCorruptedError(
            forKey: key,
            in: self,
            debugDescription: "Expected integer, number, numeric string, or null."
        )
    }

    func decodeFlexibleDouble(forKey key: K, defaultValue: Double) throws -> Double {
        guard contains(key), !(try decodeNil(forKey: key)) else { return defaultValue }

        if let value = try? decode(Double.self, forKey: key), value.isFinite {
            return max(0, min(1, value))
        }

        if let string = try? decode(String.self, forKey: key),
           let value = Double(string.trimmingCharacters(in: .whitespacesAndNewlines)),
           value.isFinite {
            return max(0, min(1, value))
        }

        throw DecodingError.dataCorruptedError(
            forKey: key,
            in: self,
            debugDescription: "Expected confidence to be a finite number."
        )
    }

    func decodeUUIDIfPresent(forKey key: K) throws -> UUID? {
        guard contains(key), !(try decodeNil(forKey: key)) else { return nil }
        let value = try decode(String.self, forKey: key).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        return UUID(uuidString: value)
    }

    func decodeStringArrayIfPresent(forKey key: K) throws -> [String] {
        guard contains(key), !(try decodeNil(forKey: key)) else { return [] }
        return try decode([String].self, forKey: key)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func decodeBillDateIfPresent(forKey key: K) throws -> Date? {
        guard contains(key), !(try decodeNil(forKey: key)) else { return nil }
        let value = try decode(String.self, forKey: key).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if let date = ISO8601DateFormatter.mistiaSyncWithFractionalSeconds.date(from: value)
            ?? ISO8601DateFormatter.mistiaSyncWithoutFractionalSeconds.date(from: value) {
            return date
        }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }

        throw DecodingError.dataCorruptedError(
            forKey: key,
            in: self,
            debugDescription: "Invalid bill date: \(value)"
        )
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
