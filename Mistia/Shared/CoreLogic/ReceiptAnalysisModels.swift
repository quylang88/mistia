import Foundation

struct ReceiptAnalysisCategoryCandidate: Codable, Equatable, Identifiable {
    let id: UUID
    let name: String
    let parentName: String?
    let kindRawValue: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case parentName = "parent_name"
        case kindRawValue = "kind_raw_value"
    }
}

struct ReceiptAnalysisWalletCandidate: Codable, Equatable, Identifiable {
    let id: UUID
    let name: String
    let kindRawValue: String
    let currencyCode: String
    let institutionDisplayName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case kindRawValue = "kind_raw_value"
        case currencyCode = "currency_code"
        case institutionDisplayName = "institution_display_name"
    }
}

struct ReceiptAnalysisRequestPayload: Codable, Equatable {
    let imageBase64: String
    let mimeType: String
    let localeIdentifier: String
    let timeZoneIdentifier: String
    let currencyCode: String
    let categories: [ReceiptAnalysisCategoryCandidate]
    let wallets: [ReceiptAnalysisWalletCandidate]

    enum CodingKeys: String, CodingKey {
        case imageBase64 = "image_base64"
        case mimeType = "mime_type"
        case localeIdentifier = "locale_identifier"
        case timeZoneIdentifier = "time_zone_identifier"
        case currencyCode = "currency_code"
        case categories
        case wallets
    }
}

struct ReceiptAnalysisQuota: Codable, Equatable {
    var allowed: Bool
    var usedCount: Int
    var limitCount: Int
    var remainingCount: Int
    var usageDate: String?
    var resetTimeZone: String?
    var retryAfter: Date?

    enum CodingKeys: String, CodingKey {
        case allowed
        case usedCount = "used_count"
        case limitCount = "limit_count"
        case remainingCount = "remaining_count"
        case usageDate = "usage_date"
        case resetTimeZone = "reset_time_zone"
        case retryAfter = "retry_after"
    }

    init(
        allowed: Bool,
        usedCount: Int,
        limitCount: Int,
        remainingCount: Int,
        usageDate: String? = nil,
        resetTimeZone: String? = nil,
        retryAfter: Date? = nil
    ) {
        self.allowed = allowed
        self.usedCount = max(0, usedCount)
        self.limitCount = max(0, limitCount)
        self.remainingCount = max(0, remainingCount)
        self.usageDate = usageDate?.nilIfBlank
        self.resetTimeZone = resetTimeZone?.nilIfBlank
        self.retryAfter = retryAfter
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        allowed = try container.decodeIfPresent(Bool.self, forKey: .allowed) ?? true
        usedCount = max(0, try container.decodeFlexibleInt(forKey: .usedCount, defaultValue: 0))
        limitCount = max(0, try container.decodeFlexibleInt(forKey: .limitCount, defaultValue: 0))
        remainingCount = max(0, try container.decodeFlexibleInt(forKey: .remainingCount, defaultValue: max(limitCount - usedCount, 0)))
        usageDate = try container.decodeTrimmedStringIfPresent(forKey: .usageDate)
        resetTimeZone = try container.decodeTrimmedStringIfPresent(forKey: .resetTimeZone)
        retryAfter = try container.decodeReceiptQuotaDateIfPresent(forKey: .retryAfter)
    }
}

struct ReceiptAnalysisResult: Codable, Equatable {
    var merchantName: String?
    var totalMinor: Int64?
    var currencyCode: String?
    var occurredAt: Date?
    var categoryID: UUID?
    var walletID: UUID?
    var confidence: Double
    var missingFields: [String]
    var rawText: String?
    var quota: ReceiptAnalysisQuota?

    enum CodingKeys: String, CodingKey {
        case merchantName = "merchant_name"
        case totalMinor = "total_minor"
        case currencyCode = "currency_code"
        case occurredAt = "occurred_at"
        case categoryID = "category_id"
        case walletID = "wallet_id"
        case confidence
        case missingFields = "missing_fields"
        case rawText = "raw_text"
        case quota
    }

    init(
        merchantName: String? = nil,
        totalMinor: Int64? = nil,
        currencyCode: String? = nil,
        occurredAt: Date? = nil,
        categoryID: UUID? = nil,
        walletID: UUID? = nil,
        confidence: Double,
        missingFields: [String] = [],
        rawText: String? = nil,
        quota: ReceiptAnalysisQuota? = nil
    ) {
        self.merchantName = merchantName?.nilIfBlank
        self.totalMinor = totalMinor
        self.currencyCode = currencyCode?.nilIfBlank?.uppercased()
        self.occurredAt = occurredAt
        self.categoryID = categoryID
        self.walletID = walletID
        self.confidence = confidence
        self.missingFields = missingFields
        self.rawText = rawText?.nilIfBlank
        self.quota = quota
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        merchantName = try container.decodeTrimmedStringIfPresent(forKey: .merchantName)
        totalMinor = try container.decodeFlexibleInt64IfPresent(forKey: .totalMinor)
        currencyCode = try container.decodeTrimmedStringIfPresent(forKey: .currencyCode)?.uppercased()
        occurredAt = try container.decodeReceiptDateIfPresent(forKey: .occurredAt)
        categoryID = try container.decodeUUIDIfPresent(forKey: .categoryID)
        walletID = try container.decodeUUIDIfPresent(forKey: .walletID)
        confidence = try container.decodeFlexibleDouble(forKey: .confidence)
        missingFields = try container.decode([String].self, forKey: .missingFields)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        rawText = try container.decodeTrimmedStringIfPresent(forKey: .rawText)
        quota = try container.decodeIfPresent(ReceiptAnalysisQuota.self, forKey: .quota)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(merchantName, forKey: .merchantName)
        try container.encodeIfPresent(totalMinor, forKey: .totalMinor)
        try container.encodeIfPresent(currencyCode, forKey: .currencyCode)
        if let occurredAt {
            try container.encode(
                MistiaISO8601DateCoding.stringWithFractionalSeconds(from: occurredAt),
                forKey: .occurredAt
            )
        } else {
            try container.encodeNil(forKey: .occurredAt)
        }
        try container.encodeIfPresent(categoryID, forKey: .categoryID)
        try container.encodeIfPresent(walletID, forKey: .walletID)
        try container.encode(confidence, forKey: .confidence)
        try container.encode(missingFields, forKey: .missingFields)
        try container.encodeIfPresent(rawText, forKey: .rawText)
        try container.encodeIfPresent(quota, forKey: .quota)
    }

    func validated(
        categoryIDs: Set<UUID>,
        walletIDs: Set<UUID>
    ) -> ReceiptAnalysisResult {
        var copy = self
        var missing = Set(missingFields)

        if let categoryID, !categoryIDs.contains(categoryID) {
            copy.categoryID = nil
            missing.insert("categoryID")
        }

        if let walletID, !walletIDs.contains(walletID) {
            copy.walletID = nil
            missing.insert("walletID")
        }

        copy.missingFields = Array(missing).sorted()
        return copy
    }
}

private extension KeyedDecodingContainer where K == ReceiptAnalysisResult.CodingKeys {
    func decodeTrimmedStringIfPresent(forKey key: K) throws -> String? {
        guard contains(key), !(try decodeNil(forKey: key)) else { return nil }
        let value = try decode(String.self, forKey: key)
        return value.nilIfBlank
    }

    func decodeFlexibleInt64IfPresent(forKey key: K) throws -> Int64? {
        guard contains(key), !(try decodeNil(forKey: key)) else { return nil }

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
            return sanitized.isEmpty ? nil : Int64(sanitized)
        }

        throw DecodingError.dataCorruptedError(
            forKey: key,
            in: self,
            debugDescription: "Expected total_minor to be an integer, number, numeric string, or null."
        )
    }

    func decodeFlexibleDouble(forKey key: K) throws -> Double {
        if let value = try? decode(Double.self, forKey: key), value.isFinite {
            return value
        }

        if let string = try? decode(String.self, forKey: key),
           let value = Double(string.trimmingCharacters(in: .whitespacesAndNewlines)),
           value.isFinite {
            return value
        }

        throw DecodingError.dataCorruptedError(
            forKey: key,
            in: self,
            debugDescription: "Expected confidence to be a finite number."
        )
    }

    func decodeReceiptDateIfPresent(forKey key: K) throws -> Date? {
        guard contains(key), !(try decodeNil(forKey: key)) else { return nil }
        let value = try decode(String.self, forKey: key).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if let date = MistiaISO8601DateCoding.date(from: value) {
            return date
        }

        let dateTimeFormatter = DateFormatter()
        dateTimeFormatter.calendar = Calendar(identifier: .gregorian)
        dateTimeFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateTimeFormatter.timeZone = .current

        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm"] {
            dateTimeFormatter.dateFormat = format
            if let date = dateTimeFormatter.date(from: value) {
                return date
            }
        }

        let dateOnlyFormatter = DateFormatter()
        dateOnlyFormatter.calendar = Calendar(identifier: .gregorian)
        dateOnlyFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateOnlyFormatter.timeZone = .current
        dateOnlyFormatter.dateFormat = "yyyy-MM-dd"
        if let date = dateOnlyFormatter.date(from: value) {
            return date
        }

        throw DecodingError.dataCorruptedError(
            forKey: key,
            in: self,
            debugDescription: "Invalid receipt date: \(value)"
        )
    }

    func decodeUUIDIfPresent(forKey key: K) throws -> UUID? {
        guard contains(key), !(try decodeNil(forKey: key)) else { return nil }
        let value = try decode(String.self, forKey: key).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        return UUID(uuidString: value)
    }
}

private extension KeyedDecodingContainer where K == ReceiptAnalysisQuota.CodingKeys {
    func decodeTrimmedStringIfPresent(forKey key: K) throws -> String? {
        guard contains(key), !(try decodeNil(forKey: key)) else { return nil }
        let value = try decode(String.self, forKey: key)
        return value.nilIfBlank
    }

    func decodeFlexibleInt(forKey key: K, defaultValue: Int) throws -> Int {
        guard contains(key), !(try decodeNil(forKey: key)) else { return defaultValue }

        if let value = try? decode(Int.self, forKey: key) {
            return value
        }

        if let value = try? decode(Double.self, forKey: key), value.isFinite {
            return Int(value.rounded())
        }

        if let string = try? decode(String.self, forKey: key),
           let value = Int(string.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return value
        }

        throw DecodingError.dataCorruptedError(
            forKey: key,
            in: self,
            debugDescription: "Expected quota integer value."
        )
    }

    func decodeReceiptQuotaDateIfPresent(forKey key: K) throws -> Date? {
        guard contains(key), !(try decodeNil(forKey: key)) else { return nil }
        let value = try decode(String.self, forKey: key).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        if let date = MistiaISO8601DateCoding.date(from: value) {
            return date
        }

        throw DecodingError.dataCorruptedError(
            forKey: key,
            in: self,
            debugDescription: "Invalid quota retry date: \(value)"
        )
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
