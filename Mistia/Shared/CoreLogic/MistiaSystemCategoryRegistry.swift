import Foundation

struct ParsedSystemCategory: Codable, Sendable {
    let id: String
    let kind: TransactionCategoryKind? // Only present on parent categories
    let icon: String
    let fallbackIcon: String
    let color: String
    let group: MistiaFinanceIconGroup
    let active: Bool
    let aliases: [String]
    let translations: [String: String]
    let children: [ParsedSystemCategory]?

    func kind(in registry: MistiaSystemCategoryRegistry) -> TransactionCategoryKind {
        if let kind {
            return kind
        }
        if let parentId = registry.parentId(for: id),
           let parent = registry.category(for: parentId) {
            return parent.kind ?? .expense
        }
        return .expense
    }

    func localizedTitle(for language: MistiaAppLanguage) -> String {
        translations[language.rawValue] ?? translations["en"] ?? id
    }

    func knownDefaultNames() -> [String] {
        Array(Set([translations["vi"], translations["en"], translations["ja"]].compactMap { $0 } + aliases))
    }
}

final class MistiaSystemCategoryRegistry: Sendable {
    static let shared = MistiaSystemCategoryRegistry()

    let allParents: [ParsedSystemCategory]
    private let categoryMap: [String: ParsedSystemCategory]
    private let parentChildMap: [String: String] // childId -> parentId

    private init() {
        let jsonName = "MistiaSystemCategories"
        let jsonExtension = "json"
        
        let bundle: Bundle
        #if SWIFT_PACKAGE
        bundle = Bundle.module
        #else
        bundle = Bundle.main
        #endif

        guard let url = bundle.url(forResource: jsonName, withExtension: jsonExtension) ??
                        Bundle.main.url(forResource: jsonName, withExtension: jsonExtension) ??
                        Bundle(for: BundleFinder.self).url(forResource: jsonName, withExtension: jsonExtension) else {
            fatalError("Could not find \(jsonName).\(jsonExtension) in any bundle")
        }

        do {
            let data = try Data(contentsOf: url)
            let parsed = try JSONDecoder().decode([ParsedSystemCategory].self, from: data)
            self.allParents = parsed
            
            var map: [String: ParsedSystemCategory] = [:]
            var parentChild: [String: String] = [:]
            for parent in parsed {
                map[parent.id] = parent
                for child in parent.children ?? [] {
                    map[child.id] = child
                    parentChild[child.id] = parent.id
                }
            }
            self.categoryMap = map
            self.parentChildMap = parentChild
        } catch {
            fatalError("Failed to load or parse \(jsonName).\(jsonExtension): \(error)")
        }
    }

    func category(for id: String) -> ParsedSystemCategory? {
        categoryMap[id]
    }

    func parentId(for childId: String) -> String? {
        parentChildMap[childId]
    }

    func allActiveParents() -> [ParsedSystemCategory] {
        allParents.filter { $0.active }
    }

    func children(forParentId parentId: String) -> [ParsedSystemCategory] {
        categoryMap[parentId]?.children ?? []
    }

    func metadata(forId id: String) -> ParsedSystemCategory? {
        categoryMap[id]
    }
}

private final class BundleFinder {}
