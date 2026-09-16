#!/usr/bin/env swift

import Foundation

private struct Contract: Decodable {
    let entities: [Entity]
}

private struct Entity: Decodable {
    let name: String
    let pullOrder: Int
    let pushPriority: Int
    let fields: [String]
}

private enum CheckError: Error, CustomStringConvertible {
    case message(String)
    var description: String { if case .message(let value) = self { value } else { "" } }
}

do {
    let script = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
    let repo = script.deletingLastPathComponent().deletingLastPathComponent()
    let contractURL = repo.appending(path: "contracts/schema/cloud-entities.json")
    let kotlinURL = repo.appending(path: "android/core/model/src/main/java/vn/com/quyln/mistia/core/model/Contracts.kt")
    let contract = try JSONDecoder().decode(Contract.self, from: Data(contentsOf: contractURL))
    let kotlin = try String(contentsOf: kotlinURL, encoding: .utf8)
    let regex = try NSRegularExpression(
        pattern: #"[A-Z_]+\(\"([a-z0-9_]+)\",\s*([0-9]+),\s*([0-9]+)\)"#
    )
    let range = NSRange(kotlin.startIndex..<kotlin.endIndex, in: kotlin)
    let matches = regex.matches(in: kotlin, range: range).compactMap { match -> (String, Int, Int)? in
        guard
            let tableRange = Range(match.range(at: 1), in: kotlin),
            let pullRange = Range(match.range(at: 2), in: kotlin),
            let pushRange = Range(match.range(at: 3), in: kotlin),
            let pull = Int(kotlin[pullRange]),
            let push = Int(kotlin[pushRange])
        else { return nil }
        return (String(kotlin[tableRange]), pull, push)
    }

    guard contract.entities.count == 15 else {
        throw CheckError.message("Expected 15 cloud entities, found \(contract.entities.count).")
    }
    guard matches.count == contract.entities.count else {
        throw CheckError.message("Kotlin CloudEntity has \(matches.count) entries; contract has \(contract.entities.count).")
    }
    for entity in contract.entities {
        guard let kotlinEntity = matches.first(where: { $0.0 == entity.name }) else {
            throw CheckError.message("Kotlin is missing contract entity \(entity.name).")
        }
        guard kotlinEntity.1 == entity.pullOrder, kotlinEntity.2 == entity.pushPriority else {
            throw CheckError.message("Priority drift for \(entity.name).")
        }
        for required in ["id", "updated_at", "deleted_at", "sync_version"] where !entity.fields.contains(required) {
            throw CheckError.message("\(entity.name) is missing required field \(required).")
        }
    }

    let androidRoot = repo.appending(path: "android")
    let enumerator = FileManager.default.enumerator(at: androidRoot, includingPropertiesForKeys: nil)
    while let file = enumerator?.nextObject() as? URL {
        guard file.pathExtension == "kt" || file.pathExtension == "kts" else { continue }
        let content = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        if content.localizedCaseInsensitiveContains("service_role") {
            throw CheckError.message("Forbidden service-role reference in \(file.path).")
        }
    }
    print("Android contract check passed (15 entities).")
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}
