import Foundation
import AppKit
import WeChatTweakCore

enum Command {
    static func requireStopped(app: URL) throws {
        let info = try AppInfo.read(app: app)
        let running = NSWorkspace.shared.runningApplications
        guard !running.isEmpty else { throw TweakError("Cannot inspect running applications in this environment; run from a normal Terminal before modifying WeChat") }
        guard !running.contains(where: { $0.bundleIdentifier == info.bundleID }) else {
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
