import Foundation
import WeChatTweakCore

func addAppInfo(_ app: URL, build: String = "269602") throws {
    let plist = ["CFBundleShortVersionString": "4.1.13", "CFBundleVersion": build, "CFBundleIdentifier": "com.tencent.xinWeChat"]
    try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: app.appendingPathComponent("Contents/Info.plist"))
    let signature = app.appendingPathComponent("Contents/_CodeSignature/CodeResources")
    try FileManager.default.createDirectory(at: signature.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("original signature".utf8).write(to: signature)
}

final class AppTransactionTests {
    func testSignFailurePreservesOriginalAndRetainsBackup() throws {
        try withFixture { app, file in
            try addAppInfo(app)
            let root = app.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let plan = try PatchPlan.prepare(app: app, config: testConfig())
            try checkThrows(try AppTransaction.apply(app: app, plan: plan, backupRoot: root) { staged in
                try Data("changed signature".utf8).write(to: staged.appendingPathComponent("Contents/_CodeSignature/CodeResources"))
                throw TweakError("injected signing failure")
            })
            try checkEqual(try Data(contentsOf: file), thinFixture())
            try checkEqual(try String(contentsOf: app.appendingPathComponent("Contents/_CodeSignature/CodeResources"), encoding: .utf8), "original signature")
            try checkEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).count, 1)
        }
    }

    func testApplyRestoreAndRejectUpgradedAppOrDamagedBackup() throws {
        try withFixture { app, file in
            try addAppInfo(app)
            let root = app.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let plan = try PatchPlan.prepare(app: app, config: testConfig())
            let backup = try AppTransaction.apply(app: app, plan: plan, backupRoot: root) { _ in }
            try checkEqual(try Data(contentsOf: file).subdata(in: 0x100..<0x108), Data([0,0,128,82,192,3,95,214]))
            try addAppInfo(app, build: "new-build")
            try checkThrows(try AppTransaction.restore(app: app, backup: backup))
            try checkEqual(try AppInfo.read(app: app).build, "new-build")
            try addAppInfo(app)
            try AppTransaction.restore(app: app, backup: backup)
            try checkEqual(try Data(contentsOf: file), thinFixture())
            try Data("corrupt".utf8).write(to: backup.appendingPathComponent("original.app/Contents/MacOS/WeChat"))
            try checkThrows(try AppTransaction.restore(app: app, backup: backup))
            try checkEqual(try Data(contentsOf: file), thinFixture())
        }
    }

    func testStalePlanAndBackupFailureDoNotMutateApp() throws {
        try withFixture { app, file in
            try addAppInfo(app)
            let plan = try PatchPlan.prepare(app: app, config: testConfig())
            var changed = thinFixture(); changed[0x100] = 99
            try changed.write(to: file)
            let root = app.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            try checkThrows(try AppTransaction.apply(app: app, plan: plan, backupRoot: root) { _ in })
            try checkEqual(try Data(contentsOf: file), changed)
            try thinFixture().write(to: file)
            try Data("not a directory".utf8).write(to: root)
            try checkThrows(try AppTransaction.apply(app: app, plan: plan, backupRoot: root) { _ in })
            try checkEqual(try Data(contentsOf: file), thinFixture())
        }
    }

    func testConcurrentSourceChangeAndLockAreRejected() throws {
        try withFixture { app, file in
            try addAppInfo(app)
            let root = app.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let plan = try PatchPlan.prepare(app: app, config: testConfig())
            try checkThrows(try AppTransaction.apply(app: app, plan: plan, backupRoot: root) { _ in
                try checkThrows(try AppTransaction.apply(app: app, plan: plan, backupRoot: root) { _ in })
                var changed = thinFixture(); changed[0x120] = 77
                try changed.write(to: file)
            })
            try checkEqual(try Data(contentsOf: file)[0x120], 77)
            try checkEqual(try Data(contentsOf: file)[0x100], 1)
        }
    }

    func testSwapFailureRestoresOriginalDirectory() throws {
        try withFixture { app, file in
            try checkThrows(try ApplicationSwap.replace(app: app, staged: app.appendingPathComponent("missing")))
            try checkEqual(try Data(contentsOf: file), thinFixture())
        }
    }
}

@MainActor let transactionTests: [(String, () throws -> Void)] = [
    ("sign failure preserves original", AppTransactionTests().testSignFailurePreservesOriginalAndRetainsBackup),
    ("apply, restore, upgrade and damage guards", AppTransactionTests().testApplyRestoreAndRejectUpgradedAppOrDamagedBackup),
    ("stale plan and failed backup", AppTransactionTests().testStalePlanAndBackupFailureDoNotMutateApp),
    ("concurrent modification and lock", AppTransactionTests().testConcurrentSourceChangeAndLockAreRejected),
    ("swap failure restores live app", AppTransactionTests().testSwapFailureRestoresOriginalDirectory),
    ("literal process arguments", {
        try checkEqual(try ProcessRunner.run(executable: URL(fileURLWithPath: "/usr/bin/printf"), arguments: ["%s", "$(touch /tmp/never-created); `echo test` ' "]), "$(touch /tmp/never-created); `echo test` ' ")
        try checkThrows(try ProcessRunner.run(executable: URL(fileURLWithPath: "/usr/bin/false"), arguments: []))
    }),
]
