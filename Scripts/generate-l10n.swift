#!/usr/bin/env swift

import Foundation

private let supportedLanguages = ["vi", "en", "ja"]
private let validKeyPattern = #"^[a-z][A-Za-z0-9]*(\.[a-z][A-Za-z0-9]*)+$"#

private struct Catalog: Decodable {
    let sourceLanguage: String
    let strings: [String: CatalogString]
}

private struct CatalogString: Decodable {
    let extractionState: String?
    let localizations: [String: CatalogLocalization]?
}

private struct CatalogLocalization: Decodable {
    let stringUnit: CatalogStringUnit?
}

private struct CatalogStringUnit: Decodable {
    let state: String?
    let value: String
}

private struct GeneratedEntry {
    let key: String
    let segments: [String]
    let localizations: [String: String]
    let placeholders: [Placeholder]
}

private enum Placeholder: Equatable {
    case string
    case int
    case double

    var swiftType: String {
        switch self {
        case .string:
            "String"
        case .int:
            "Int"
        case .double:
            "Double"
        }
    }
}

private final class Node {
    var entry: GeneratedEntry?
    var children: [String: Node] = [:]
}

private struct Arguments {
    let inputPath: String
    let inputURL: URL
    let outputPath: String
    let outputURL: URL
    let checkOnly: Bool
    let strictKeys: Bool
}

private enum GeneratorError: Error, CustomStringConvertible {
    case usage
    case message(String)

    var description: String {
        switch self {
        case .usage:
            "Usage: swift Scripts/generate-l10n.swift --input Mistia/Localizable.xcstrings --output Mistia/Shared/CoreLogic/L10n.generated.swift [--check] [--strict-keys]"
        case .message(let message):
            message
        }
    }
}

do {
    let arguments = try parseArguments(CommandLine.arguments.dropFirst())
    let generated = try generate(arguments: arguments)

    if arguments.checkOnly {
        let existing = try? String(contentsOf: arguments.outputURL, encoding: .utf8)
        guard existing == generated else {
            throw GeneratorError.message("\(arguments.outputURL.path) is not up to date. Run Scripts/generate-l10n.swift.")
        }
    } else {
        try FileManager.default.createDirectory(
            at: arguments.outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try generated.write(to: arguments.outputURL, atomically: true, encoding: .utf8)
    }
} catch {
    writeError("\(error)\n")
    exit(1)
}

private func parseArguments(_ rawArguments: ArraySlice<String>) throws -> Arguments {
    var input: String?
    var output: String?
    var checkOnly = false
    var strictKeys = false

    var index = rawArguments.startIndex
    while index < rawArguments.endIndex {
        let argument = rawArguments[index]
        switch argument {
        case "--input":
            index = rawArguments.index(after: index)
            guard index < rawArguments.endIndex else { throw GeneratorError.usage }
            input = rawArguments[index]
        case "--output":
            index = rawArguments.index(after: index)
            guard index < rawArguments.endIndex else { throw GeneratorError.usage }
            output = rawArguments[index]
        case "--check":
            checkOnly = true
        case "--strict-keys":
            strictKeys = true
        default:
            throw GeneratorError.message("Unknown argument: \(argument)")
        }
        index = rawArguments.index(after: index)
    }

    guard let input, let output else {
        throw GeneratorError.usage
    }

    return Arguments(
        inputPath: input,
        inputURL: URL(fileURLWithPath: input),
        outputPath: output,
        outputURL: URL(fileURLWithPath: output),
        checkOnly: checkOnly,
        strictKeys: strictKeys
    )
}

private func generate(arguments: Arguments) throws -> String {
    let data = try Data(contentsOf: arguments.inputURL)
    let catalog = try JSONDecoder().decode(Catalog.self, from: data)

    guard catalog.sourceLanguage == "vi" else {
        throw GeneratorError.message("Expected sourceLanguage vi, found \(catalog.sourceLanguage).")
    }

    let entries = try generatedEntries(from: catalog, strictKeys: arguments.strictKeys)
    let root = try buildTree(entries)
    return render(root: root, sourcePath: arguments.inputPath)
}

private func generatedEntries(from catalog: Catalog, strictKeys: Bool) throws -> [GeneratedEntry] {
    let validKeyRegex = try NSRegularExpression(pattern: validKeyPattern)
    var entries: [GeneratedEntry] = []
    var invalidKeys: [String] = []
    var sanitizedPaths = Set<String>()

    for key in catalog.strings.keys.sorted() {
        let range = NSRange(key.startIndex..<key.endIndex, in: key)
        let isValidKey = validKeyRegex.firstMatch(in: key, range: range) != nil

        guard isValidKey else {
            invalidKeys.append(key)
            continue
        }

        let catalogString = catalog.strings[key] ?? CatalogString(extractionState: nil, localizations: nil)
        let localizations = catalogString.localizations ?? [:]

        for language in supportedLanguages {
            guard let value = localizations[language]?.stringUnit?.value,
                  !value.isEmpty else {
                throw GeneratorError.message("\(key) is missing \(language) localization.")
            }
        }

        let sourceValue = localizations["vi"]?.stringUnit?.value ?? ""
        let sourcePlaceholders = try parsePlaceholders(in: sourceValue, key: key)
        for language in supportedLanguages where language != "vi" {
            let localizedValue = localizations[language]?.stringUnit?.value ?? ""
            let localizedPlaceholders = try parsePlaceholders(in: localizedValue, key: "\(key) [\(language)]")
            guard localizedPlaceholders == sourcePlaceholders else {
                throw GeneratorError.message("\(key) has mismatched placeholders for \(language).")
            }
        }

        let segments = key.split(separator: ".").map(String.init)
        let sanitizedPath = segments.map(sanitizedIdentifier).joined(separator: ".")
        guard sanitizedPaths.insert(sanitizedPath).inserted else {
            throw GeneratorError.message("Duplicate generated Swift path: \(sanitizedPath).")
        }

        entries.append(
            GeneratedEntry(
                key: key,
                segments: segments,
                localizations: Dictionary(
                    uniqueKeysWithValues: supportedLanguages.map { language in
                        (language, localizations[language]?.stringUnit?.value ?? "")
                    }
                ),
                placeholders: sourcePlaceholders
            )
        )
    }

    if strictKeys, !invalidKeys.isEmpty {
        throw GeneratorError.message("Invalid localization keys: \(invalidKeys.joined(separator: ", ")).")
    }

    return entries.sorted { $0.key < $1.key }
}

private func parsePlaceholders(in value: String, key: String) throws -> [Placeholder] {
    let characters = Array(value)
    var placeholders: [Placeholder] = []
    var index = 0

    while index < characters.count {
        guard characters[index] == "%" else {
            index += 1
            continue
        }

        let nextIndex = index + 1
        guard nextIndex < characters.count else {
            throw GeneratorError.message("\(key) contains a dangling percent placeholder.")
        }

        if characters[nextIndex] == "%" {
            index += 2
            continue
        }

        if characters[nextIndex] == "@" {
            placeholders.append(.string)
            index += 2
            continue
        }

        if characters[nextIndex] == "d" {
            placeholders.append(.int)
            index += 2
            continue
        }

        if characters[nextIndex] == "f" {
            placeholders.append(.double)
            index += 2
            continue
        }

        if nextIndex + 1 < characters.count,
           characters[nextIndex] == "l",
           characters[nextIndex + 1] == "d" {
            placeholders.append(.int)
            index += 3
            continue
        }

        if nextIndex + 2 < characters.count,
           characters[nextIndex] == "l",
           characters[nextIndex + 1] == "l",
           characters[nextIndex + 2] == "d" {
            placeholders.append(.int)
            index += 4
            continue
        }

        if characters[nextIndex].isLetter {
            throw GeneratorError.message("\(key) contains unsupported placeholder near %\(characters[nextIndex]).")
        }

        index += 1
    }

    return placeholders
}

private func buildTree(_ entries: [GeneratedEntry]) throws -> Node {
    let root = Node()

    for entry in entries {
        var node = root
        for segment in entry.segments.dropLast() {
            if let existing = node.children[segment] {
                node = existing
            } else {
                let child = Node()
                node.children[segment] = child
                node = child
            }
        }

        let leaf = entry.segments.last ?? entry.key
        let leafNode: Node
        if let existing = node.children[leaf] {
            leafNode = existing
        } else {
            leafNode = Node()
            node.children[leaf] = leafNode
        }
        guard leafNode.entry == nil else {
            throw GeneratorError.message("Duplicate localization key: \(entry.key).")
        }
        leafNode.entry = entry
    }

    return root
}

private func render(root: Node, sourcePath: String) -> String {
    var output: [String] = [
        "// Generated file. Do not edit manually.",
        "// Source: \(sourcePath)",
        "",
        "import Foundation",
        "",
        "nonisolated enum L10n {",
        "    fileprivate static func tr(_ key: String, vi: String, en: String, ja: String, language: MistiaAppLanguage = .current) -> String {",
        "        switch language {",
        "        case .vietnamese:",
        "            return vi",
        "        case .english:",
        "            return en",
        "        case .japanese:",
        "            return ja",
        "        }",
        "    }",
        "",
        "    fileprivate static func format(_ key: String, vi: String, en: String, ja: String, language: MistiaAppLanguage = .current, _ arguments: CVarArg...) -> String {",
        "        let format = tr(key, vi: vi, en: en, ja: ja, language: language)",
        "        return withVaList(arguments) { pointer in",
        "            NSString(format: format, locale: language.locale as NSLocale, arguments: pointer) as String",
        "        }",
        "    }"
    ]

    renderChildren(of: root, indent: "    ", output: &output)
    output.append("}")
    output.append("")
    return output.joined(separator: "\n")
}

private func renderChildren(of node: Node, indent: String, output: inout [String]) {
    for childName in node.children.keys.sorted() {
        let child = node.children[childName] ?? Node()
        let identifier = sanitizedIdentifier(childName)

        if !child.children.isEmpty {
            output.append("")
            output.append("\(indent)nonisolated enum \(identifier) {")
            if let entry = child.entry {
                renderEntry(entry, name: childName, indent: indent + "    ", output: &output)
            }
            renderChildren(of: child, indent: indent + "    ", output: &output)
            output.append("\(indent)}")
        } else if let entry = child.entry {
            renderEntry(entry, name: childName, indent: indent, output: &output)
        }
    }
}

private func renderEntry(_ entry: GeneratedEntry, name: String, indent: String, output: inout [String]) {
    let identifier = sanitizedIdentifier(name)
    let keyLiteral = swiftStringLiteral(entry.key)
    let vi = swiftStringLiteral(entry.localizations["vi"] ?? "")
    let en = swiftStringLiteral(entry.localizations["en"] ?? "")
    let ja = swiftStringLiteral(entry.localizations["ja"] ?? "")

    if entry.placeholders.isEmpty {
        output.append("\(indent)static var \(identifier): String { L10n.tr(\(keyLiteral), vi: \(vi), en: \(en), ja: \(ja)) }")
        output.append("\(indent)static func \(identifier)(language: MistiaAppLanguage) -> String { L10n.tr(\(keyLiteral), vi: \(vi), en: \(en), ja: \(ja), language: language) }")
    } else {
        let parameters = parameterList(for: entry.placeholders)
        let arguments = formatArguments(for: entry.placeholders)
        output.append("\(indent)static func \(identifier)(\(parameters)) -> String {")
        output.append("\(indent)    L10n.format(\(keyLiteral), vi: \(vi), en: \(en), ja: \(ja), \(arguments))")
        output.append("\(indent)}")
        output.append("\(indent)static func \(identifier)(\(parameters), language: MistiaAppLanguage) -> String {")
        output.append("\(indent)    L10n.format(\(keyLiteral), vi: \(vi), en: \(en), ja: \(ja), language: language, \(arguments))")
        output.append("\(indent)}")
    }
}

private func parameterList(for placeholders: [Placeholder]) -> String {
    if placeholders.count == 1 {
        let name: String
        switch placeholders[0] {
        case .int:
            name = "count"
        case .string, .double:
            name = "value"
        }
        return "_ \(name): \(placeholders[0].swiftType)"
    }

    return placeholders.enumerated()
        .map { index, placeholder in "_ arg\(index + 1): \(placeholder.swiftType)" }
        .joined(separator: ", ")
}

private func formatArguments(for placeholders: [Placeholder]) -> String {
    if placeholders.count == 1 {
        let name = placeholders[0] == .int ? "count" : "value"
        switch placeholders[0] {
        case .int:
            return "Int64(\(name))"
        case .string, .double:
            return name
        }
    }

    return placeholders.enumerated()
        .map { index, placeholder in
            let name = "arg\(index + 1)"
            switch placeholder {
            case .int:
                return "Int64(\(name))"
            case .string, .double:
                return name
            }
        }
        .joined(separator: ", ")
}

private func sanitizedIdentifier(_ value: String) -> String {
    if isSwiftKeyword(value) {
        return "`\(value)`"
    }
    return value
}

private func swiftStringLiteral(_ value: String) -> String {
    let escaped = value
        .replacingOccurrences(of: #"\"#, with: #"\\"#)
        .replacingOccurrences(of: #"""#, with: #"\""#)
        .replacingOccurrences(of: "\n", with: #"\n"#)
        .replacingOccurrences(of: "\r", with: #"\r"#)
        .replacingOccurrences(of: "\t", with: #"\t"#)
    return "\"\(escaped)\""
}

private func writeError(_ message: String) {
    FileHandle.standardError.write(Data(message.utf8))
}

private func isSwiftKeyword(_ value: String) -> Bool {
    switch value {
    case "associatedtype",
        "class",
        "deinit",
        "enum",
        "extension",
        "fileprivate",
        "func",
        "import",
        "init",
        "inout",
        "internal",
        "let",
        "open",
        "operator",
        "private",
        "protocol",
        "public",
        "rethrows",
        "static",
        "struct",
        "subscript",
        "typealias",
        "var",
        "break",
        "case",
        "catch",
        "continue",
        "default",
        "defer",
        "do",
        "else",
        "fallthrough",
        "for",
        "guard",
        "if",
        "in",
        "repeat",
        "return",
        "throw",
        "switch",
        "where",
        "while",
        "as",
        "Any",
        "false",
        "is",
        "nil",
        "self",
        "Self",
        "super",
        "throws",
        "true",
        "try":
        return true
    default:
        return false
    }
}
