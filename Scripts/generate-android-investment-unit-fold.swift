#!/usr/bin/env swift
import CryptoKit
import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())
let root: URL = {
    if let index = arguments.firstIndex(of: "--root"), arguments.indices.contains(index + 1) {
        return URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
    }
    return URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
}()
let sourcePath = "Mistia/Shared/CoreLogic/InvestmentLogic.swift"
let generatorPath = "Scripts/generate-android-investment-unit-fold.swift"
let outputPath = "android/core/model/src/main/java/vn/com/quyln/mistia/core/model/SwiftInvestmentUnitFold.generated.kt"
let manifestPath = "docs/android/investment-unit-fold.generated.json"
func sha(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
func read(_ path: String) throws -> Data { try Data(contentsOf: root.appendingPathComponent(path)) }
func unitSource() throws -> String {
    let source = String(decoding: try read(sourcePath), as: UTF8.self)
    guard let start = source.range(of: "nonisolated enum InvestmentUnitLabel {")?.lowerBound,
          let end = source.range(of: "nonisolated struct InvestmentUnitPosition:", range: start..<source.endIndex)?.lowerBound else {
        throw NSError(domain: "InvestmentUnitFold", code: 1, userInfo: [NSLocalizedDescriptionKey: "Swift unit helper markers changed"])
    }
    return String(source[start..<end])
}
struct Manifest: Codable {
    let version: Int
    let sourceSnippetSHA256: String
    let generatorSHA256: String
    let generatedSHA256: String
    let mappingCount: Int
}
do {
    let snippet = try unitSource()
    let snippetSHA = sha(Data(snippet.utf8))
    let generatorSHA = try sha(read(generatorPath))
    if arguments.contains("--check") {
        let manifest = try JSONDecoder().decode(Manifest.self, from: read(manifestPath))
        guard manifest.version == 1, manifest.sourceSnippetSHA256 == snippetSHA,
              manifest.generatorSHA256 == generatorSHA, manifest.generatedSHA256 == (try sha(read(outputPath))),
              manifest.mappingCount > 1000 else {
            throw NSError(domain: "InvestmentUnitFold", code: 2, userInfo: [NSLocalizedDescriptionKey: "Stale Swift unit-fold source or generated artifact"])
        }
        print("Investment unit fold checked (\(manifest.mappingCount) mappings).")
    } else if arguments.contains("--write") {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("mistia-unit-fold-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let script = temporary.appendingPathComponent("derive.swift")
        let result = temporary.appendingPathComponent("folds.json")
        let diagnostics = temporary.appendingPathComponent("diagnostics.txt")
        let program = """
        import Foundation
        \(snippet)
        var mappings: [String: String] = [:]
        for code in 0...0x10ffff {
            guard let scalar = UnicodeScalar(code), !CharacterSet.whitespacesAndNewlines.contains(scalar) else { continue }
            let input = String(scalar)
            let output = InvestmentUnitLabel.comparisonKey(input).precomposedStringWithCanonicalMapping
            if output != input { mappings[String(code, radix: 16)] = output }
        }
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: mappings, options: [.sortedKeys, .withoutEscapingSlashes]))
        """
        try program.write(to: script, atomically: true, encoding: .utf8)
        FileManager.default.createFile(atPath: result.path, contents: nil)
        FileManager.default.createFile(atPath: diagnostics.path, contents: nil)
        let resultHandle = try FileHandle(forWritingTo: result)
        let diagnosticHandle = try FileHandle(forWritingTo: diagnostics)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
        process.arguments = [script.path]
        process.standardOutput = resultHandle
        process.standardError = diagnosticHandle
        try process.run()
        process.waitUntilExit()
        try resultHandle.close(); try diagnosticHandle.close()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "InvestmentUnitFold", code: 3, userInfo: [NSLocalizedDescriptionKey: try String(contentsOf: diagnostics, encoding: .utf8)])
        }
        let mappings = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: result))
        func kotlin(_ value: String) throws -> String {
            let array = try JSONSerialization.data(withJSONObject: [value], options: [.withoutEscapingSlashes])
            return String(String(decoding: array, as: UTF8.self).dropFirst().dropLast()).replacingOccurrences(of: "$", with: "\\$")
        }
        var output = """
        // Generated from Swift InvestmentUnitLabel. Run Scripts/generate-android-investment-unit-fold.swift --write.
        package vn.com.quyln.mistia.core.model

        import java.text.Normalizer

        internal object SwiftInvestmentUnitFold {
            fun apply(value: String): String {
                val result = StringBuilder()
                // Foundation folding uses the prefix before the first NUL scalar.
                value.takeWhile { it.code != 0 }.codePoints().forEach { point ->
                    when (point) {
        """
        for key in mappings.keys.sorted(by: { UInt32($0, radix: 16)! < UInt32($1, radix: 16)! }) {
            output += "\n                0x\(key) -> result.append(\(try kotlin(mappings[key]!)))"
        }
        output += """

                        else -> result.appendCodePoint(point)
                    }
                }
                return Normalizer.normalize(result.toString(), Normalizer.Form.NFC)
            }
        }

        """
        let data = Data(output.utf8)
        try data.write(to: root.appendingPathComponent(outputPath), options: .atomic)
        let manifest = Manifest(version: 1, sourceSnippetSHA256: snippetSHA, generatorSHA256: generatorSHA,
                                generatedSHA256: sha(data), mappingCount: mappings.count)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try (encoder.encode(manifest) + Data("\n".utf8)).write(to: root.appendingPathComponent(manifestPath), options: .atomic)
        print("Generated \(mappings.count) Swift investment unit-fold mappings.")
    } else {
        throw NSError(domain: "InvestmentUnitFold", code: 4, userInfo: [NSLocalizedDescriptionKey: "Use --check or --write"])
    }
} catch {
    FileHandle.standardError.write(Data("Investment unit fold: \(error.localizedDescription)\n".utf8))
    exit(1)
}
