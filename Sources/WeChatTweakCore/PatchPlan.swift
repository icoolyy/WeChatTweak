import Foundation

public struct PatchWrite: Sendable {
    public let file: URL
    public let offset: UInt64
    public let before: Data
    public let after: Data
}

public struct PatchPlan: Sendable {
    public let app: URL
    public let version: String
    public let writes: [PatchWrite]
    public let alreadyPatched: Int
    public let unverifiedLegacyEntries: Int

    public static func targetURL(app: URL, relative: String) throws -> URL {
        let components = relative.split(separator: "/", omittingEmptySubsequences: false)
        guard !relative.hasPrefix("/"), !components.isEmpty,
              !components.contains(where: { $0 == ".." || $0 == "." || $0.isEmpty }) else {
            throw TweakError("Patch file must be a relative path within the application: \(relative)")
        }
        let root = app.standardizedFileURL.resolvingSymlinksInPath()
        let target = root.appendingPathComponent(relative).resolvingSymlinksInPath()
        guard target.path.hasPrefix(root.path + "/") else { throw TweakError("Patch target escapes the application") }
        return target
    }

    public static func prepare(app: URL, config: Config) throws -> PatchPlan {
        var images: [URL: MachOImage] = [:]
        var writes: [PatchWrite] = []
        var ranges: [URL: [Range<UInt64>]] = [:]
        var alreadyPatched = 0, legacy = 0, total = 0
        for target in config.targets {
            guard !target.entries.isEmpty else { throw TweakError("Empty patch target: \(target.identifier)") }
            let file = try targetURL(app: app, relative: target.file)
            if images[file] == nil { images[file] = try MachOImage(data: Data(contentsOf: file, options: .mappedIfSafe)) }
            guard let image = images[file] else { throw TweakError("Missing patch image") }
            for entry in target.entries {
                total += 1
                let offset = try image.offset(arch: entry.arch, address: entry.addr, length: entry.asm.count)
                let range = offset..<(offset + UInt64(entry.asm.count))
                guard !(ranges[file] ?? []).contains(where: { $0.overlaps(range) }) else { throw TweakError("Overlapping patches") }
                ranges[file, default: []].append(range)
                let actual = image.data.subdata(in: Int(range.lowerBound)..<Int(range.upperBound))
                if actual == entry.asm { alreadyPatched += 1; continue }
                if let original = entry.original {
                    guard actual == original else { throw TweakError("Original bytes mismatch: \(target.file) / \(target.identifier) / \(entry.arch.rawValue)") }
                } else { legacy += 1 }
                writes.append(PatchWrite(file: file, offset: offset, before: actual, after: entry.asm))
            }
        }
        guard total > 0 else { throw TweakError("No patch entries") }
        return PatchPlan(app: app.standardizedFileURL.resolvingSymlinksInPath(), version: config.version, writes: writes, alreadyPatched: alreadyPatched, unverifiedLegacyEntries: legacy)
    }
}
