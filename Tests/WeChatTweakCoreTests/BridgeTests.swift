import Foundation
import WeChatTweakCore

private func executableFixture() -> Data {
    var data = thinFixture()
    func put(_ value: UInt64, _ offset: Int, _ size: Int) {
        for i in 0..<size { data[offset+i] = UInt8(truncatingIfNeeded: value >> (i*8)) }
    }
    put(152, 20, 4); put(152, 36, 4); put(1, 96, 4)
    data.replaceSubrange(104..<110, with: Data("__text".utf8))
    data.replaceSubrange(0x100..<0x108, with: repeatElement(UInt8(0), count: 8))
    data.replaceSubrange(0x180..<0x188, with: [1,2,3,4,5,6,7,8])
    put(0x1180, 136, 8); put(8, 144, 8); put(0x180, 152, 4)
    return data
}

@MainActor let bridgeTests: [(String, () throws -> Void)] = [
    ("bridge load command preserves code and is idempotent", {
        let original = executableFixture()
        let result = try BridgeLoadCommand.inserting(into: original)
        try checkEqual(result.count, original.count)
        try checkEqual(result.subdata(in: 0x180..<0x200), original.subdata(in: 0x180..<0x200))
        try checkEqual(result[16], 2)
        try checkEqual(try BridgeLoadCommand.inserting(into: result), result)
    }),
    ("bridge rejects occupied padding, malformed sections and missing arm64", {
        var occupied = executableFixture(); occupied[190] = 0xaa
        try checkThrows(try BridgeLoadCommand.inserting(into: occupied))
        var truncated = executableFixture(); truncated[96] = 2
        try checkThrows(try BridgeLoadCommand.inserting(into: truncated))
        try checkThrows(try BridgeLoadCommand.inserting(into: thinFixture(cpu: 0x01000007)))
        try checkThrows(try BridgeLoadCommand.inserting(into: thinFixture()))
        var wrongSlice = fatFixture(); wrongSlice.replaceSubrange(0x400..<0x600, with: executableFixture()); wrongSlice[0x404] = 7
        try checkThrows(try BridgeLoadCommand.inserting(into: wrongSlice))
    }),
    ("fat bridge insertion leaves Intel slice unchanged", {
        var fat = fatFixture(); fat.replaceSubrange(0x400..<0x600, with: executableFixture())
        let result = try BridgeLoadCommand.inserting(into: fat)
        try checkEqual(result.subdata(in: 0..<0x400), fat.subdata(in: 0..<0x400))
        try checkEqual(result[0x410], 2)
    }),
]

// Explicit opt-in: copies only local application inputs into an unlaunched,
// disposable fixture. No test ever modifies or starts the installed application.
@MainActor let realBridgeTests: [(String, () throws -> Void)] = ProcessInfo.processInfo.environment["WCT_REAL_INSTALL_TEST"] == "1" ? [
    ("real-input bridge transaction, rollback, idempotence and full restore", {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("wct-bridge-install-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let app = root.appendingPathComponent("Fixture.app")
        for relative in ["Contents/Info.plist", "Contents/MacOS/WeChat", "Contents/Resources/wechat.dylib"] {
            let target = app.appendingPathComponent(relative)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: URL(fileURLWithPath: "/Applications/WeChat.app").appendingPathComponent(relative), to: target)
        }
        let launcher = app.appendingPathComponent("Contents/MacOS/WeChat")
        let original = try Data(contentsOf: launcher)
        let config = try JSONDecoder().decode([Config].self, from: Data(contentsOf: URL(fileURLWithPath: "config.json"))).first { $0.version == "269602" }!
        let plan = try PatchPlan.prepare(app: app, config: config)
        let payload = URL(fileURLWithPath: "dist/WeChatTweakBridge.dylib")
        let bridge = try BridgePlan.prepare(app: app, payload: payload)
        let backups = root.appendingPathComponent("backups")
        try checkThrows(try AppTransaction.apply(app: app, plan: plan, backupRoot: backups, bridge: bridge) { _ in throw TweakError("simulated signer failure") })
        try checkEqual(try Data(contentsOf: launcher), original)
        try check(!fm.fileExists(atPath: app.appendingPathComponent("Contents/Frameworks/WeChatTweakBridge.dylib").path))
        let backup = try AppTransaction.apply(app: app, plan: plan, backupRoot: backups, bridge: bridge) { _ in }
        try checkEqual(try Data(contentsOf: launcher), BridgeLoadCommand.inserting(into: original))
        try check(fm.fileExists(atPath: app.appendingPathComponent("Contents/Resources/WeChatTweak.enabled").path))
        try check(!(try BridgePlan.prepare(app: app, payload: payload)).changed)
        try check((try PatchPlan.prepare(app: app, config: config)).writes.isEmpty)
        try AppTransaction.restore(app: app, backup: backup)
        try checkEqual(try Data(contentsOf: launcher), original)
        try check(!fm.fileExists(atPath: app.appendingPathComponent("Contents/Frameworks/WeChatTweakBridge.dylib").path))
        try check(!fm.fileExists(atPath: app.appendingPathComponent("Contents/Resources/WeChatTweak.enabled").path))
        var stale = original; stale[stale.count-1] ^= 1; try stale.write(to: launcher)
        try checkThrows(try AppTransaction.apply(app: app, plan: plan, backupRoot: backups, bridge: bridge) { _ in })
        try checkEqual(try Data(contentsOf: launcher), stale)
    })
] : []
