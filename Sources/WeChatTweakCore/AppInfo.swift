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
