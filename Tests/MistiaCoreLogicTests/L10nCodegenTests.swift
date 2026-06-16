import XCTest

final class L10nCodegenTests: XCTestCase {
    func testGeneratorCreatesNestedAPIAndFormatFunctions() throws {
        let tempDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let catalogURL = tempDirectory.appendingPathComponent("Localizable.xcstrings")
        let outputURL = tempDirectory.appendingPathComponent("L10n.generated.swift")
        try sampleCatalog.write(to: catalogURL, atomically: true, encoding: .utf8)

        let result = try runGenerator(
            arguments: [
                "--input", catalogURL.path,
                "--output", outputURL.path
            ]
        )

        XCTAssertEqual(result.status, 0, result.stderr)

        let generated = try String(contentsOf: outputURL, encoding: .utf8)
        XCTAssertTrue(generated.contains("// Generated file. Do not edit manually."))
        XCTAssertTrue(generated.contains("nonisolated enum L10n"))
        XCTAssertTrue(generated.contains("nonisolated enum settings"))
        XCTAssertTrue(generated.contains("nonisolated enum notifications"))
        XCTAssertTrue(generated.contains("static var title: String"))
        XCTAssertTrue(generated.contains("\"settings.notifications.title\""))
        XCTAssertTrue(generated.contains("static func categoriesArchivedMessage(_ count: Int) -> String"))
        XCTAssertTrue(generated.contains("\"settings.resetData.categoriesArchivedMessage\""))
        XCTAssertFalse(generated.contains("legacy vietnamese key"))
    }

    func testGeneratedResolverUsesMistiaAppLanguageInsteadOfBundleLanguage() throws {
        let tempDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let catalogURL = tempDirectory.appendingPathComponent("Localizable.xcstrings")
        let outputURL = tempDirectory.appendingPathComponent("L10n.generated.swift")
        try sampleCatalog.write(to: catalogURL, atomically: true, encoding: .utf8)

        let result = try runGenerator(
            arguments: [
                "--input", catalogURL.path,
                "--output", outputURL.path
            ]
        )

        XCTAssertEqual(result.status, 0, result.stderr)

        let generated = try String(contentsOf: outputURL, encoding: .utf8)
        XCTAssertFalse(generated.contains("String.LocalizationValue"), generated)
        XCTAssertFalse(generated.contains("bundle: .main"), generated)
        XCTAssertTrue(generated.contains("switch language"), generated)
    }

    func testGeneratorCheckModeFailsWhenOutputIsStale() throws {
        let tempDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let catalogURL = tempDirectory.appendingPathComponent("Localizable.xcstrings")
        let outputURL = tempDirectory.appendingPathComponent("L10n.generated.swift")
        try sampleCatalog.write(to: catalogURL, atomically: true, encoding: .utf8)
        try "stale".write(to: outputURL, atomically: true, encoding: .utf8)

        let result = try runGenerator(
            arguments: [
                "--input", catalogURL.path,
                "--output", outputURL.path,
                "--check"
            ]
        )

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.stderr.contains("not up to date"), result.stderr)
    }

    func testGeneratorFailsForMissingTranslationOnGeneratedKeys() throws {
        let tempDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let catalogURL = tempDirectory.appendingPathComponent("Localizable.xcstrings")
        let outputURL = tempDirectory.appendingPathComponent("L10n.generated.swift")
        let catalog = """
        {
          "sourceLanguage": "vi",
          "strings": {
            "settings.title": {
              "localizations": {
                "vi": { "stringUnit": { "state": "translated", "value": "Cài đặt" } },
                "en": { "stringUnit": { "state": "translated", "value": "Settings" } }
              }
            }
          }
        }
        """
        try catalog.write(to: catalogURL, atomically: true, encoding: .utf8)

        let result = try runGenerator(
            arguments: [
                "--input", catalogURL.path,
                "--output", outputURL.path
            ]
        )

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.stderr.contains("missing ja localization"), result.stderr)
    }

    private var sampleCatalog: String {
        """
        {
          "sourceLanguage": "vi",
          "strings": {
            "legacy vietnamese key": {
              "localizations": {
                "vi": { "stringUnit": { "state": "translated", "value": "Cũ" } },
                "en": { "stringUnit": { "state": "translated", "value": "Old" } },
                "ja": { "stringUnit": { "state": "translated", "value": "古い" } }
              }
            },
            "settings.notifications.title": {
              "localizations": {
                "vi": { "stringUnit": { "state": "translated", "value": "Thông báo" } },
                "en": { "stringUnit": { "state": "translated", "value": "Notifications" } },
                "ja": { "stringUnit": { "state": "translated", "value": "通知" } }
              }
            },
            "settings.resetData.categoriesArchivedMessage": {
              "localizations": {
                "vi": { "stringUnit": { "state": "translated", "value": "%lld danh mục tự tạo đã được lưu trữ." } },
                "en": { "stringUnit": { "state": "translated", "value": "%lld custom categories were archived." } },
                "ja": { "stringUnit": { "state": "translated", "value": "作成したカテゴリ %lld 件をアーカイブしました。" } }
              }
            }
          }
        }
        """
    }

    private func runGenerator(arguments: [String]) throws -> (status: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["swift", repositoryRoot.appendingPathComponent("Scripts/generate-l10n.swift").path] + arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (process.terminationStatus, stdout, stderr)
    }

    private var repositoryRoot: URL {
        var url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        while !FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
            let parent = url.deletingLastPathComponent()
            precondition(parent.path != url.path, "Could not locate repository root")
            url = parent
        }
        return url
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mistia-l10n-codegen-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
