import Foundation

public struct TweakError: LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public struct AppInfo: Codable, Equatable, Sendable {
    public let displayVersion: String
    public let build: String
    public let bundleID: String

    // Receipt presence identifies the observed distribution only. It does not
    // authenticate the receipt or imply that App Store updates are blocked.
    public static func distribution(app: URL) -> String {
        var current = app
        for component in ["Contents", "_MASReceipt", "receipt"] {
            current.appendPathComponent(component)
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: current.path),
                  let type = attributes[.type] as? FileAttributeType,
                  type == (component == "receipt" ? .typeRegular : .typeDirectory) else { return "unknown" }
        }
        return "appStore"
    }

    public static func read(app: URL) throws -> AppInfo {
        let data = try Data(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let version = plist["CFBundleShortVersionString"] as? String, !version.isEmpty,
              let build = plist["CFBundleVersion"] as? String, !build.isEmpty,
              let identifier = plist["CFBundleIdentifier"] as? String, !identifier.isEmpty else {
            throw TweakError("Invalid app Info.plist: version, build and bundle identifier are required")
        }
        return AppInfo(displayVersion: version, build: build, bundleID: identifier)
    }
}
