import Foundation
import AppKit
import WeChatTweakCore

enum Command {
    static func requireStopped(app: URL) throws {
        let info = try AppInfo.read(app: app)
        guard NSRunningApplication.runningApplications(withBundleIdentifier: info.bundleID).isEmpty else {
            throw TweakError("Quit all WeChat instances before patching or restoring")
        }
    }

    static func resign(app: URL, relativeFiles: [String]) throws {
        for path in Set(relativeFiles).sorted() {
            let file = try PatchPlan.targetURL(app: app, relative: path)
            try ProcessRunner.run(executable: URL(fileURLWithPath: "/usr/bin/codesign"), arguments: ["--force", "--sign", "-", file.path])
        }
        try ProcessRunner.run(executable: URL(fileURLWithPath: "/usr/bin/codesign"), arguments: ["--force", "--deep", "--sign", "-", app.path])
        try ProcessRunner.run(executable: URL(fileURLWithPath: "/usr/bin/xattr"), arguments: ["-cr", app.path])
        try ProcessRunner.run(executable: URL(fileURLWithPath: "/usr/bin/codesign"), arguments: ["--verify", "--deep", "--strict", app.path])
    }
}
