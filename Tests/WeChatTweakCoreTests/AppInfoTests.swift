import Foundation
import WeChatTweakCore

final class AppInfoTests {
    func testDistributionRequiresRegularReceipt() throws {
        let app = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: app) }
        let directory = app.appendingPathComponent("Contents/_MASReceipt")
        let receipt = directory.appendingPathComponent("receipt")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try checkEqual(AppInfo.distribution(app: app), "unknown")
        try Data([1]).write(to: receipt)
        try checkEqual(AppInfo.distribution(app: app), "appStore")
        try FileManager.default.removeItem(at: receipt)
        try FileManager.default.createSymbolicLink(at: receipt, withDestinationURL: URL(fileURLWithPath: "/etc/hosts"))
        try checkEqual(AppInfo.distribution(app: app), "unknown")
        try FileManager.default.removeItem(at: receipt)
        try FileManager.default.createDirectory(at: receipt, withIntermediateDirectories: false)
        try checkEqual(AppInfo.distribution(app: app), "unknown")
        try FileManager.default.removeItem(at: directory)
        try FileManager.default.createSymbolicLink(at: directory, withDestinationURL: app.deletingLastPathComponent())
        try checkEqual(AppInfo.distribution(app: app), "unknown")
    }
    func testReadsBuildWithoutGUISession() throws {
        let app = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + " Test WeChat.app")
        defer { try? FileManager.default.removeItem(at: app) }
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let plist: [String: String] = ["CFBundleShortVersionString": "4.1.13", "CFBundleVersion": "269602", "CFBundleIdentifier": "com.tencent.xinWeChat"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: app.appendingPathComponent("Contents/Info.plist"))
        let info = try AppInfo.read(app: app)
        try checkEqual(info.build, "269602")
        try checkEqual(info.displayVersion, "4.1.13")
        try checkEqual(info.bundleID, "com.tencent.xinWeChat")
    }

    func testRejectsMissingOrMalformedPlist() throws {
        let app = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: app) }
        try checkThrows(try AppInfo.read(app: app))
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try Data("not a plist".utf8).write(to: app.appendingPathComponent("Contents/Info.plist"))
        try checkThrows(try AppInfo.read(app: app))
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleVersion": ""], format: .xml, options: 0).write(to: app.appendingPathComponent("Contents/Info.plist"))
        try checkThrows(try AppInfo.read(app: app))
    }
}
