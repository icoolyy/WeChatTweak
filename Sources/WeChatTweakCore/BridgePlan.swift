import Foundation

/// Adds an arm64 dependency using existing zero-filled header padding only.
public enum BridgeLoadCommand {
    public static let name = "@executable_path/../Frameworks/WeChatTweakBridge.dylib"
    public static func inserting(into data: Data) throws -> Data {
        let image = try MachOImage(data: data)
        guard let slice = image.slices.first(where: { $0.cpu == 0x0100000c }) else { throw TweakError("Bridge requires an arm64 executable") }
        func read(_ pos: UInt64, _ size: Int) throws -> UInt64 {
            guard pos <= slice.size, UInt64(size) <= slice.size - pos else { throw TweakError("Truncated bridge target") }
            return try MachOImage.read(data, slice.offset + pos, size)
        }
        guard try read(0, 4) == 0xfeedfacf, try read(4, 4) == UInt64(slice.cpu), try read(12, 4) == 2 else { throw TweakError("Bridge target must be an arm64 MH_EXECUTE") }
        let count = try read(16, 4), bytes = try read(20, 4)
        guard bytes <= slice.size - 32, count <= bytes / 8 else { throw TweakError("Invalid executable command table") }
        let end = 32 + bytes
        var pos: UInt64 = 32, firstData = slice.size, installed = false
        for _ in 0..<count {
            guard pos <= end, end - pos >= 8 else { throw TweakError("Truncated executable command") }
            let command = try read(pos, 4), size = try read(pos + 4, 4)
            guard size >= 8, size % 8 == 0, size <= end - pos else { throw TweakError("Invalid executable command") }
            if command == 0x19 {
                guard size >= 72 else { throw TweakError("Invalid executable segment") }
                let sections = try read(pos + 64, 4)
                guard sections <= (size - 72) / 80 else { throw TweakError("Invalid executable sections") }
                let file = try read(pos + 40, 8), fileSize = try read(pos + 48, 8)
                guard file <= slice.size, fileSize <= slice.size - file else { throw TweakError("Invalid executable segment range") }
                if file > 0 && fileSize > 0 { firstData = min(firstData, file) }
                for i in 0..<sections {
                    let section = pos + 72 + i * 80
                    let offset = try read(section + 48, 4), flags = try read(section + 64, 4) & 0xff
                    let length = try read(section + 40, 8)
                    if length > 0 && ![UInt64(1), 0xc, 0x12].contains(flags) {
                        guard offset >= end, offset <= slice.size, length <= slice.size - offset else { throw TweakError("Invalid executable section range") }
                        firstData = min(firstData, offset)
                    }
                }
            }
            if [UInt64(0xc), 0x80000018, 0x8000001f, 0x80000023].contains(command) {
                guard size >= 24 else { throw TweakError("Invalid dylib command") }
                let offset = try read(pos + 8, 4)
                guard offset >= 24, offset < size else { throw TweakError("Invalid dylib name") }
                let raw = data.subdata(in: Int(slice.offset + pos + offset)..<Int(slice.offset + pos + size))
                guard let zero = raw.firstIndex(of: 0), let value = String(data: raw.prefix(upTo: zero), encoding: .utf8) else { throw TweakError("Invalid dylib name") }
                if value == name {
                    guard command == 0xc, !installed else { throw TweakError("Ambiguous bridge dependency") }
                    installed = true
                }
            }
            pos += size
        }
        guard pos == end else { throw TweakError("Invalid executable table length") }
        if installed { return data }
        let commandSize = UInt64((24 + name.utf8.count + 1 + 7) & ~7)
        guard firstData < slice.size, end <= firstData, commandSize <= firstData - end,
              bytes + commandSize <= UInt32.max,
              data[Int(slice.offset + end)..<Int(slice.offset + end + commandSize)].allSatisfy({ $0 == 0 }) else {
            throw TweakError("Executable has insufficient verified zero-filled load-command padding")
        }
        var result = data
        func put(_ value: UInt64, _ offset: UInt64, _ size: Int) {
            for i in 0..<size { result[Int(slice.offset + offset) + i] = UInt8(truncatingIfNeeded: value >> (i * 8)) }
        }
        put(count + 1, 16, 4); put(bytes + commandSize, 20, 4)
        put(0xc, end, 4); put(commandSize, end + 4, 4); put(24, end + 8, 4)
        result.replaceSubrange(Int(slice.offset + end + 24)..<Int(slice.offset + end + 24) + name.utf8.count, with: name.utf8)
        return result
    }
}

public struct BridgePlan: Sendable {
    public let app: URL
    public let changed: Bool
    private let before: [String: Data]
    private let absent: Set<String>
    private let after: [String: Data]
    private static let launcher = "Contents/MacOS/WeChat"
    private static let library = "Contents/Frameworks/WeChatTweakBridge.dylib"
    private static let marker = "Contents/Resources/WeChatTweak.enabled"

    public static func prepare(app: URL, payload: URL) throws -> BridgePlan {
        let app = app.standardizedFileURL.resolvingSymlinksInPath()
        let info = try AppInfo.read(app: app)
        guard info.build == "269602", info.bundleID == "com.tencent.xinWeChat" else { throw TweakError("Native bridge supports only WeChat arm64 build 269602") }
        let module = try PatchPlan.targetURL(app: app, relative: "Contents/Resources/wechat.dylib")
        // Hash executable code independently of a changed ad-hoc signature.
        // Normalize only the two known patches, accepting partial installation.
        let moduleData = try Data(contentsOf: module)
        let moduleImage = try MachOImage(data: moduleData)
        let textOffset = try moduleImage.offset(arch: .arm64, address: 0x17000, length: 0x6c97d28)
        var code = moduleData.subdata(in: Int(textOffset)..<Int(textOffset) + 0x6c97d28)
        let patches: [(Int, [UInt8], [UInt8])] = [
            (0x44de938 - 0x17000, [0xf4,0x4f,0xbe,0xa9,0xfd,0x7b,0x01,0xa9], [0,0,0x80,0x52,0xc0,3,0x5f,0xd6]),
            (0x27370c - 0x17000, [0xff,3,6,0xd1,0xfc,0x6f,0x14,0xa9], [0x20,0,0x80,0x52,0xc0,3,0x5f,0xd6])]
        for (offset, original, patched) in patches {
            let actual = code.subdata(in: offset..<offset + 8)
            guard actual == Data(original) || actual == Data(patched) else { throw TweakError("Native bridge instruction fingerprint mismatch") }
            code.replaceSubrange(offset..<offset + 8, with: original)
        }
        guard FileDigest.hash(data: code) == "5ccbdcba186265115fd52f2ef6f5dc39cca731b7f71f81601bff5e1272612df2" else {
            throw TweakError("Native bridge business-module fingerprint mismatch")
        }
        let payloadData = try Data(contentsOf: payload)
        let image = try MachOImage(data: payloadData)
        guard image.slices.count == 1, let slice = image.slices.first, slice.cpu == 0x0100000c,
              try MachOImage.read(payloadData, slice.offset + 12, 4) == 6 else { throw TweakError("Bridge payload must be an arm64 MH_DYLIB") }
        var before: [String: Data] = [:], absent = Set<String>()
        for relative in [launcher, library, marker] {
            let target = try safeTarget(app: app, relative: relative)
            if FileManager.default.fileExists(atPath: target.path) {
                guard try target.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { throw TweakError("Bridge target is not a regular file") }
                before[relative] = try Data(contentsOf: target)
            } else { absent.insert(relative) }
        }
        guard let original = before[launcher] else { throw TweakError("Missing WeChat launcher") }
        let after = [launcher: try BridgeLoadCommand.inserting(into: original), library: payloadData, marker: Data("protocol=1\nbuild=269602\n".utf8)]
        return BridgePlan(app: app, changed: before != after, before: before, absent: absent, after: after)
    }
    private static func safeTarget(app: URL, relative: String) throws -> URL {
        let target = try PatchPlan.targetURL(app: app, relative: relative)
        guard target == app.appendingPathComponent(relative).standardizedFileURL else { throw TweakError("Bridge target contains a symbolic link") }
        return target
    }
    func validate(within root: URL) throws {
        for (relative, data) in before {
            guard try Data(contentsOf: Self.safeTarget(app: root, relative: relative)) == data else { throw TweakError("Bridge target changed since preflight") }
        }
        for relative in absent {
            let target = try Self.safeTarget(app: root, relative: relative)
            guard !FileManager.default.fileExists(atPath: target.path) else { throw TweakError("Bridge target appeared since preflight") }
        }
    }
    func apply(within root: URL) throws {
        try validate(within: root)
        for (relative, data) in after {
            let target = try Self.safeTarget(app: root, relative: relative)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            let mode = relative == Self.launcher ? 0o755 : 0o644
            try data.write(to: target, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: target.path)
        }
    }
}
