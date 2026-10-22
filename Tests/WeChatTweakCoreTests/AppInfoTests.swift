import Foundation
import WeChatTweakCore

final class AppInfoTests {
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
