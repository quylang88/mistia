import UIKit

// MARK: - Current Device Info Snapshot

/// Immutable snapshot of the current device's metadata.
/// Single source of truth — used by `MistiaAccountDeviceRegistry`,
/// `SendFeedbackView`, and anywhere else that needs device info.
struct CurrentDeviceInfo: Sendable {
    let deviceName: String       // User-assigned name, e.g. "Quy's iPhone"
    let modelIdentifier: String  // Hardware identifier, e.g. "iPhone15,2"
    let modelDisplayName: String // Marketing name, e.g. "iPhone 14 Pro"
    let systemName: String       // "iOS"
    let systemVersion: String    // "18.5"
    let appVersion: String       // "1.2.3"
    let appBuild: String         // "42"

    /// Convenience summary for user-facing display.
    var displaySummary: String {
        "Mistia v\(appVersion) • \(systemName) \(systemVersion) • \(modelDisplayName)"
    }

    /// Dictionary payload suitable for API submission.
    var asDictionary: [String: String] {
        [
            "app_version": appVersion,
            "os_version": systemVersion,
            "device_model": modelDisplayName,
        ]
    }

    static func current(
        bundle: Bundle = .main,
        device: UIDevice = .current
    ) -> CurrentDeviceInfo {
        let identifier = DeviceModelResolver.currentIdentifier()
        return CurrentDeviceInfo(
            deviceName: device.name,
            modelIdentifier: identifier,
            modelDisplayName: DeviceModelResolver.marketingName(for: identifier),
            systemName: device.systemName,
            systemVersion: device.systemVersion,
            appVersion: bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
            appBuild: bundle.infoDictionary?["CFBundleVersion"] as? String ?? ""
        )
    }
}

// MARK: - Device Model Resolver

/// Resolves hardware identifiers to marketing names.
enum DeviceModelResolver {

    /// Hardware identifier of the current device (e.g. "iPhone15,2").
    nonisolated static func currentIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        return mirror.children.reduce(into: "") { result, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            result.append(String(UnicodeScalar(UInt8(value))))
        }
    }

    /// Marketing name for the given hardware identifier.
    /// Falls back to `UIDevice.current.localizedModel` for unknown identifiers.
    static func marketingName(for identifier: String) -> String {
        if let name = table[identifier] { return name }
        if identifier.hasPrefix("iPhone") { return "iPhone" }
        let localized = UIDevice.current.localizedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        return localized.isEmpty ? "iPhone" : localized
    }

    // MARK: - Lookup table

    private static let table: [String: String] = [
        // iPhone 17
        "iPhone18,1": "iPhone 17 Pro",
        "iPhone18,2": "iPhone 17 Pro Max",
        "iPhone18,3": "iPhone 17",
        "iPhone18,4": "iPhone Air",
        "iPhone18,5": "iPhone 17e",

        // iPhone 16
        "iPhone17,1": "iPhone 16 Pro",
        "iPhone17,2": "iPhone 16 Pro Max",
        "iPhone17,3": "iPhone 16",
        "iPhone17,4": "iPhone 16 Plus",
        "iPhone17,5": "iPhone 16e",

        // iPhone 15
        "iPhone15,4": "iPhone 15",
        "iPhone15,5": "iPhone 15 Plus",
        "iPhone16,1": "iPhone 15 Pro",
        "iPhone16,2": "iPhone 15 Pro Max",

        // iPhone 14
        "iPhone14,7": "iPhone 14",
        "iPhone14,8": "iPhone 14 Plus",
        "iPhone15,2": "iPhone 14 Pro",
        "iPhone15,3": "iPhone 14 Pro Max",

        // iPhone 13
        "iPhone14,4": "iPhone 13 mini",
        "iPhone14,5": "iPhone 13",
        "iPhone14,2": "iPhone 13 Pro",
        "iPhone14,3": "iPhone 13 Pro Max",

        // iPhone 12
        "iPhone13,1": "iPhone 12 mini",
        "iPhone13,2": "iPhone 12",
        "iPhone13,3": "iPhone 12 Pro",
        "iPhone13,4": "iPhone 12 Pro Max",

        // iPhone 11
        "iPhone12,1": "iPhone 11",
        "iPhone12,3": "iPhone 11 Pro",
        "iPhone12,5": "iPhone 11 Pro Max",
        "iPhone12,8": "iPhone SE (2nd generation)",

        // iPhone XS / XR / X
        "iPhone11,2": "iPhone XS",
        "iPhone11,4": "iPhone XS Max",
        "iPhone11,6": "iPhone XS Max",
        "iPhone11,8": "iPhone XR",
        "iPhone10,3": "iPhone X",
        "iPhone10,6": "iPhone X",

        // iPhone 8 / 7 / 6
        "iPhone10,1": "iPhone 8",
        "iPhone10,2": "iPhone 8 Plus",
        "iPhone10,4": "iPhone 8",
        "iPhone10,5": "iPhone 8 Plus",
        "iPhone9,1":  "iPhone 7",
        "iPhone9,3":  "iPhone 7",
        "iPhone9,2":  "iPhone 7 Plus",
        "iPhone9,4":  "iPhone 7 Plus",
        "iPhone8,1":  "iPhone 6s",
        "iPhone8,2":  "iPhone 6s Plus",
        "iPhone8,4":  "iPhone SE (1st generation)",
        "iPhone14,6": "iPhone SE (3rd generation)",
        "iPhone7,1":  "iPhone 6 Plus",
        "iPhone7,2":  "iPhone 6",
    ]
}
