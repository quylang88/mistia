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

enum BillItemLineType: String, Codable, Equatable, Hashable {
    case purchase
    case discount
}

struct BillItemAnalysisItem: Codable, Equatable, Identifiable {
    let lineID: String
    var originalName: String
    var translatedName: String?
    var lineType: BillItemLineType
    var originalAmountMinor: Int64?
    var discountAmountMinor: Int64
    var finalAmountMinor: Int64
    var categoryID: UUID?
    var confidence: Double
    var missingFields: [String]

    var id: String { lineID }
    var transactionAmountMinor: Int64 { finalAmountMinor }

    enum CodingKeys: String, CodingKey {
        case lineID = "line_id"
        case originalName = "original_name"
        case translatedName = "translated_name"
        case lineType = "line_type"
        case originalAmountMinor = "original_amount_minor"
        case discountAmountMinor = "discount_amount_minor"
        case finalAmountMinor = "final_amount_minor"
        case categoryID = "category_id"
        case confidence
        case missingFields = "missing_fields"
    }

    init(
        lineID: String,
        originalName: String,
        translatedName: String? = nil,
        lineType: BillItemLineType = .purchase,
        originalAmountMinor: Int64? = nil,
        discountAmountMinor: Int64 = 0,
        finalAmountMinor: Int64,
        categoryID: UUID? = nil,
        confidence: Double,
        missingFields: [String] = []
    ) {
        self.lineID = lineID.nilIfBlank ?? UUID().uuidString
        self.originalName = originalName.nilIfBlank ?? ""
        self.translatedName = translatedName?.nilIfBlank
        self.lineType = lineType
        self.originalAmountMinor = originalAmountMinor.map { max(0, $0) }
        self.discountAmountMinor = max(0, discountAmountMinor)
        self.finalAmountMinor = lineType == .discount ? min(0, finalAmountMinor) : max(0, finalAmountMinor)
        self.categoryID = lineType == .discount ? nil : categoryID
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
        let decodedLineType = try container.decodeIfPresent(BillItemLineType.self, forKey: .lineType) ?? .purchase
        let decodedFinalAmount = try container.decodeFlexibleInt64(forKey: .finalAmountMinor, defaultValue: 0)
        lineType = decodedLineType == .discount || decodedFinalAmount < 0 ? .discount : .purchase
        originalAmountMinor = try container.decodeFlexibleInt64IfPresent(forKey: .originalAmountMinor).map { max(0, $0) }
        let decodedDiscountAmount = try container.decodeFlexibleInt64IfPresent(forKey: .discountAmountMinor)
        discountAmountMinor = max(0, decodedDiscountAmount ?? (lineType == .discount ? abs(decodedFinalAmount) : 0))
        finalAmountMinor = lineType == .discount ? min(0, decodedFinalAmount) : max(0, decodedFinalAmount)
        categoryID = lineType == .discount ? nil : try container.decodeUUIDIfPresent(forKey: .categoryID)
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
    let lineType: BillItemLineType
    let amountMinor: Int64
    let merchantName: String?
    let occurredAt: Date?
    let isCreated: Bool
    let isLocked: Bool

    init(
        id: BillItemSelectionID,
        walletID: UUID?,
        categoryID: UUID?,
        lineType: BillItemLineType = .purchase,
        amountMinor: Int64,
        merchantName: String? = nil,
        occurredAt: Date? = nil,
        isCreated: Bool = false,
        isLocked: Bool = false
    ) {
        self.id = id
        self.walletID = walletID
        self.categoryID = lineType == .discount ? nil : categoryID
        self.lineType = lineType
        self.amountMinor = amountMinor
        self.merchantName = merchantName?.nilIfBlank
        self.occurredAt = occurredAt
        self.isCreated = isCreated
        self.isLocked = isLocked
    }
}

struct BillItemLockedGroup: Equatable, Hashable, Identifiable {
    let id: UUID
    let mode: BillItemTransactionMode
    let itemIDs: Set<BillItemSelectionID>
    let amountMinor: Int64
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

struct BillItemSelectionBillSnapshot: Equatable {
    let billID: UUID
    let walletID: UUID?
    let merchantName: String?
    let occurredAt: Date?
    let items: [BillItemAnalysisItem]
    let createdItemIDs: Set<String>
    let lockedGroups: [BillItemLockedGroup]
}

struct BillItemSelectionSnapshot: Equatable {
    let candidatesByBillID: [UUID: [BillItemSelectionCandidate]]
    let selectedCandidatesByBillID: [UUID: [BillItemSelectionCandidate]]
    let lockedItemIDsByBillID: [UUID: Set<BillItemSelectionID>]
    let candidatesByID: [BillItemSelectionID: BillItemSelectionCandidate]
    let allCandidates: [BillItemSelectionCandidate]
    let selectedCandidates: [BillItemSelectionCandidate]
    let selectedIDs: Set<BillItemSelectionID>

    init(
        bills: [BillItemSelectionBillSnapshot],
        selectedIDs: Set<BillItemSelectionID>
    ) {
        var candidatesByBillID: [UUID: [BillItemSelectionCandidate]] = [:]
        var selectedCandidatesByBillID: [UUID: [BillItemSelectionCandidate]] = [:]
        var lockedItemIDsByBillID: [UUID: Set<BillItemSelectionID>] = [:]
        var candidatesByID: [BillItemSelectionID: BillItemSelectionCandidate] = [:]
        var allCandidates: [BillItemSelectionCandidate] = []
        var selectedCandidates: [BillItemSelectionCandidate] = []

        for bill in bills {
            let lockedItemIDs = BillItemSelectionLogic.lockedItemIDs(in: bill.lockedGroups)
            lockedItemIDsByBillID[bill.billID] = lockedItemIDs

            let candidates = bill.items.map { item in
                let id = BillItemSelectionID(billID: bill.billID, itemID: item.lineID)
                return BillItemSelectionCandidate(
                    id: id,
                    walletID: bill.walletID,
                    categoryID: item.categoryID,
                    lineType: item.lineType,
                    amountMinor: item.transactionAmountMinor,
                    merchantName: bill.merchantName,
                    occurredAt: bill.occurredAt,
                    isCreated: bill.createdItemIDs.contains(item.lineID),
                    isLocked: lockedItemIDs.contains(id)
                )
            }

            candidatesByBillID[bill.billID] = candidates
            let selectedForBill = candidates.filter { selectedIDs.contains($0.id) }
            selectedCandidatesByBillID[bill.billID] = selectedForBill
            allCandidates.append(contentsOf: candidates)
            selectedCandidates.append(contentsOf: selectedForBill)
            for candidate in candidates {
                candidatesByID[candidate.id] = candidate
            }
        }

        self.candidatesByBillID = candidatesByBillID
        self.selectedCandidatesByBillID = selectedCandidatesByBillID
        self.lockedItemIDsByBillID = lockedItemIDsByBillID
        self.candidatesByID = candidatesByID
        self.allCandidates = allCandidates
        self.selectedCandidates = selectedCandidates
        self.selectedIDs = selectedIDs
    }

    func selectableIDs(mode: BillItemTransactionMode) -> Set<BillItemSelectionID> {
        var ids: Set<BillItemSelectionID> = []

        for candidate in allCandidates {
            guard !selectedIDs.contains(candidate.id) else {
                continue
            }
            guard selectedIDs.allSatisfy({ $0.billID == candidate.id.billID }) else {
                continue
            }

            let selectedForBill = selectedCandidatesByBillID[candidate.id.billID] ?? []
            if BillItemSelectionLogic.canSelect(candidate, selected: selectedForBill, mode: mode) {
                ids.insert(candidate.id)
            }
        }

        return ids
    }
}

enum BillItemSelectionLogic {
    static func canSelect(
        _ candidate: BillItemSelectionCandidate,
        selected: [BillItemSelectionCandidate],
        mode: BillItemTransactionMode
    ) -> Bool {
        guard !candidate.isCreated,
              !candidate.isLocked,
              candidate.amountMinor != 0,
              candidate.walletID != nil else {
            return false
        }

        if mode == .expense, candidate.lineType == .purchase, candidate.categoryID == nil {
            return false
        }

        guard let anchor = selected.first else {
            return true
        }

        guard candidate.walletID == anchor.walletID else {
            return false
        }

        switch mode {
        case .expense:
            if candidate.lineType == .discount {
                return true
            }

            guard let purchaseAnchor = selected.first(where: { $0.lineType == .purchase }) else {
                return true
            }

            return candidate.categoryID == purchaseAnchor.categoryID
        case .lend:
            return true
        }
    }

    static func normalizedSelection(
        _ selection: Set<BillItemSelectionID>,
        candidates: [BillItemSelectionCandidate],
        mode: BillItemTransactionMode
    ) -> Set<BillItemSelectionID> {
        var normalized: [BillItemSelectionCandidate] = []
        for candidate in candidates where selection.contains(candidate.id) {
            if canSelect(candidate, selected: normalized, mode: mode) {
                normalized.append(candidate)
            }
        }

        return Set(normalized.map(\.id))
    }

    static func lockedGroup(
        for selected: [BillItemSelectionCandidate],
        mode: BillItemTransactionMode,
        id: UUID = UUID()
    ) -> BillItemLockedGroup? {
        let candidates = selected.filter { !$0.isCreated && !$0.isLocked && $0.amountMinor != 0 }
        let amountMinor = candidates.reduce(Int64.zero) { $0 + $1.amountMinor }
        guard amountMinor > 0,
              !candidates.isEmpty,
              normalizedSelection(Set(candidates.map(\.id)), candidates: candidates, mode: mode) == Set(candidates.map(\.id)) else {
            return nil
        }

        return BillItemLockedGroup(
            id: id,
            mode: mode,
            itemIDs: Set(candidates.map(\.id)),
            amountMinor: amountMinor
        )
    }

    static func lockedItemIDs(in groups: [BillItemLockedGroup]) -> Set<BillItemSelectionID> {
        groups.reduce(into: Set<BillItemSelectionID>()) { partial, group in
            partial.formUnion(group.itemIDs)
        }
    }

    static func transactionDraft(
        for selected: [BillItemSelectionCandidate],
        mode: BillItemTransactionMode,
        fallbackDate: Date
    ) -> BillItemTransactionDraft? {
        let candidates = selected.filter { !$0.isCreated && $0.amountMinor != 0 }
        guard !candidates.isEmpty,
              let walletID = candidates.first?.walletID,
              candidates.allSatisfy({ $0.walletID == walletID }) else {
            return nil
        }

        let categoryID: UUID?
        switch mode {
        case .expense:
            let purchaseCandidates = candidates.filter { $0.lineType == .purchase }
            guard let firstCategoryID = purchaseCandidates.first?.categoryID,
                  !purchaseCandidates.isEmpty,
                  purchaseCandidates.allSatisfy({ $0.categoryID == firstCategoryID }) else {
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

enum BillItemDiscountAllocator {
    static func allocatingDiscount(
        itemID: String,
        in items: [BillItemAnalysisItem]
    ) -> [BillItemAnalysisItem]? {
        guard let discountIndex = items.firstIndex(where: { $0.lineID == itemID && $0.lineType == .discount }) else {
            return nil
        }

        let discountItem = items[discountIndex]
        let discountAmount = max(discountItem.discountAmountMinor, abs(discountItem.finalAmountMinor))
        guard discountAmount > 0 else { return nil }

        let eligibleIndexes = items.indices.filter { index in
            items[index].lineType == .purchase && items[index].finalAmountMinor > 0
        }
        let baseTotal = eligibleIndexes.reduce(Int64.zero) { partial, index in
            partial + max(items[index].originalAmountMinor ?? items[index].finalAmountMinor, 0)
        }
        guard baseTotal > 0 else { return nil }

        var allocations = eligibleIndexes.map { index -> (index: Int, floor: Int64, remainder: Double) in
            let base = Double(max(items[index].originalAmountMinor ?? items[index].finalAmountMinor, 0))
            let exact = base * Double(discountAmount) / Double(baseTotal)
            return (index, Int64(floor(exact)), exact - floor(exact))
        }

        let allocatedTotal = allocations.reduce(Int64.zero) { $0 + $1.floor }
        var remainder = discountAmount - allocatedTotal
        let rankedIndexes = allocations.indices.sorted {
            if allocations[$0].remainder != allocations[$1].remainder {
                return allocations[$0].remainder > allocations[$1].remainder
            }
            return allocations[$0].index < allocations[$1].index
        }
        for allocationIndex in rankedIndexes where remainder > 0 {
            allocations[allocationIndex].floor += 1
            remainder -= 1
        }

        var updated = items
        for allocation in allocations {
            updated[allocation.index].discountAmountMinor += allocation.floor
            updated[allocation.index].finalAmountMinor = max(0, updated[allocation.index].finalAmountMinor - allocation.floor)
        }
        updated[discountIndex].finalAmountMinor = 0
        updated[discountIndex].discountAmountMinor = discountAmount
        return updated
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
