#!/usr/bin/env swift

import Foundation

private let languages = ["vi", "en", "ja"]

private struct Catalog: Decodable {
    let sourceLanguage: String
    let strings: [String: CatalogString]
}

private struct CatalogString: Decodable {
    let localizations: [String: CatalogLocalization]?
}

private struct CatalogLocalization: Decodable {
    let stringUnit: CatalogStringUnit?
}

private struct CatalogStringUnit: Decodable {
    let value: String
}

private struct Entry {
    let key: String
    let resourceName: String
    let values: [String: String]
}

private struct Arguments {
    let input: URL
    let outputRoot: URL
    let check: Bool
}

private enum GeneratorError: Error, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self {
        case .message(let message): message
        }
    }
}

do {
    let arguments = try parseArguments()
    let data = try Data(contentsOf: arguments.input)
    let catalog = try JSONDecoder().decode(Catalog.self, from: data)
    guard catalog.sourceLanguage == "vi" else {
        throw GeneratorError.message("Expected source language vi, found \(catalog.sourceLanguage).")
    }

    let entries = try makeEntries(catalog)
    let outputs = Dictionary(uniqueKeysWithValues: languages.map { language in
        let directory = language == "vi" ? "values" : "values-\(language)"
        return (
            arguments.outputRoot.appending(path: directory).appending(path: "strings.xml"),
            render(entries: entries, language: language)
        )
    })

    for (url, output) in outputs {
        if arguments.check {
            guard (try? String(contentsOf: url, encoding: .utf8)) == output else {
                throw GeneratorError.message("\(url.path) is not up to date. Run Scripts/generate-android-l10n.swift.")
            }
        } else {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try output.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    let mapURL = arguments.outputRoot
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "generated")
        .appending(path: "localization-key-map.json")
    let map = renderKeyMap(entries)
    if arguments.check {
        guard (try? String(contentsOf: mapURL, encoding: .utf8)) == map else {
            throw GeneratorError.message("\(mapURL.path) is not up to date. Run Scripts/generate-android-l10n.swift.")
        }
    } else {
        try FileManager.default.createDirectory(
            at: mapURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try map.write(to: mapURL, atomically: true, encoding: .utf8)
    }
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}

private func parseArguments() throws -> Arguments {
    let script = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
    let repo = script.deletingLastPathComponent().deletingLastPathComponent()
    var input = repo.appending(path: "Mistia/Localizable.xcstrings")
    var outputRoot = repo.appending(path: "android/core/designsystem/src/main/res")
    var check = false
    var index = 1
    while index < CommandLine.arguments.count {
        switch CommandLine.arguments[index] {
        case "--input":
            index += 1
            guard index < CommandLine.arguments.count else {
                throw GeneratorError.message("--input requires a path")
            }
            input = URL(fileURLWithPath: CommandLine.arguments[index])
        case "--output-root":
            index += 1
            guard index < CommandLine.arguments.count else {
                throw GeneratorError.message("--output-root requires a path")
            }
            outputRoot = URL(fileURLWithPath: CommandLine.arguments[index])
        case "--check":
            check = true
        default:
            throw GeneratorError.message("Unknown argument: \(CommandLine.arguments[index])")
        }
        index += 1
    }
    return Arguments(input: input.standardizedFileURL, outputRoot: outputRoot.standardizedFileURL, check: check)
}

private func makeEntries(_ catalog: Catalog) throws -> [Entry] {
    var resourceNames = [String: String]()
    return try catalog.strings.keys.sorted().map { key in
        guard key.range(of: #"^[a-z][A-Za-z0-9]*(\.[a-z][A-Za-z0-9]*)+$"#, options: .regularExpression) != nil else {
            throw GeneratorError.message("Invalid localization key for Android: \(key)")
        }
        let resourceName = androidResourceName(key)
        if let existing = resourceNames[resourceName], existing != key {
            throw GeneratorError.message("Android resource collision: \(existing) and \(key) both map to \(resourceName)")
        }
        resourceNames[resourceName] = key

        guard let item = catalog.strings[key] else {
            throw GeneratorError.message("Missing catalog item: \(key)")
        }
        var values = [String: String]()
        var expectedPlaceholders: [String]?
        for language in languages {
            guard let value = item.localizations?[language]?.stringUnit?.value, !value.isEmpty else {
                throw GeneratorError.message("\(key) is missing \(language) localization")
            }
            let converted = try androidFormat(value, key: "\(key) [\(language)]")
            if let expectedPlaceholders, expectedPlaceholders != converted.placeholders {
                throw GeneratorError.message("\(key) has mismatched placeholders for \(language)")
            }
            expectedPlaceholders = converted.placeholders
            values[language] = converted.value
        }
        return Entry(key: key, resourceName: resourceName, values: values)
    }
}

private func androidResourceName(_ key: String) -> String {
    var output = ""
    for character in key {
        if character == "." {
            if !output.hasSuffix("_") { output.append("_") }
        } else if character.isUppercase {
            if !output.isEmpty, !output.hasSuffix("_") { output.append("_") }
            output.append(contentsOf: character.lowercased())
        } else {
            output.append(character)
        }
    }
    return output.replacingOccurrences(of: "__", with: "_")
}

private func androidFormat(_ source: String, key: String) throws -> (value: String, placeholders: [String]) {
    let characters = Array(source)
    var result = ""
    var placeholders = [String]()
    var index = 0
    while index < characters.count {
        guard characters[index] == "%" else {
            result.append(characters[index])
            index += 1
            continue
        }
        guard index + 1 < characters.count else {
            throw GeneratorError.message("\(key) contains a dangling percent")
        }
        if characters[index + 1] == "%" {
            result.append("%%")
            index += 2
            continue
        }

        let token: String
        let consumed: Int
        if characters[index + 1] == "@" {
            token = "s"; consumed = 2
        } else if characters[index + 1] == "d" {
            token = "d"; consumed = 2
        } else if characters[index + 1] == "f" {
            token = "f"; consumed = 2
        } else if index + 2 < characters.count,
                  characters[index + 1] == "l", characters[index + 2] == "d" {
            token = "d"; consumed = 3
        } else if index + 3 < characters.count,
                  characters[index + 1] == "l", characters[index + 2] == "l", characters[index + 3] == "d" {
            token = "d"; consumed = 4
        } else if characters[index + 1].isLetter {
            throw GeneratorError.message("\(key) contains an unsupported placeholder near %\(characters[index + 1])")
        } else {
            result.append("%")
            index += 1
            continue
        }
        placeholders.append(token)
        result.append("%\(placeholders.count)$\(token)")
        index += consumed
    }
    return (result, placeholders)
}

private func render(entries: [Entry], language: String) -> String {
    var lines = [
        "<?xml version=\"1.0\" encoding=\"utf-8\"?>",
        "<!-- Generated from Mistia/Localizable.xcstrings. Do not edit manually. -->",
        "<resources>"
    ]
    for entry in entries {
        let raw = entry.values[language] ?? ""
        lines.append("    <string name=\"\(entry.resourceName)\">\(xmlEscape(raw))</string>")
    }
    lines.append("</resources>")
    lines.append("")
    return lines.joined(separator: "\n")
}

private func xmlEscape(_ value: String) -> String {
    value
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\n", with: "\\n")
        .replacingOccurrences(of: "'", with: "\\'")
        .replacingOccurrences(of: "\"", with: "\\\"")
}

private func renderKeyMap(_ entries: [Entry]) -> String {
    let pairs = entries.map { "  \(jsonString($0.key)): \(jsonString($0.resourceName))" }
    return (["{"] + pairs.enumerated().map { index, line in
        index == pairs.count - 1 ? line : line + ","
    } + ["}", ""]).joined(separator: "\n")
}

private func jsonString(_ value: String) -> String {
    let data = try? JSONSerialization.data(withJSONObject: [value], options: [])
    let encoded = data.flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\"]"
    return String(encoded.dropFirst().dropLast())
}
