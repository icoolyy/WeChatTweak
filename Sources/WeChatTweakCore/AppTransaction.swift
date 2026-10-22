import Foundation
import CryptoKit
import Darwin

/// A same-filesystem replacement with rollback if moving the staged app fails.
public enum ApplicationSwap {
    public static func replace(app: URL, staged: URL) throws {
        let fm = FileManager.default
        let displaced = app.deletingLastPathComponent().appendingPathComponent(".WeChatTweak-original-\(UUID().uuidString).app")
        try fm.moveItem(at: app, to: displaced)
        do { try fm.moveItem(at: staged, to: app) }
        catch {
            do { try fm.moveItem(at: displaced, to: app) }
            catch { throw TweakError("Replacement and rollback failed. Original application retained at \(displaced.path): \(error)") }
            throw error
        }
        // Failure to remove a redundant copy must not undo a successful replacement.
        do { try fm.removeItem(at: displaced) }
        catch { fputs("Warning: previous application also retained at \(displaced.path)\n", stderr) }
    }
}

public enum AppTransaction {
    private struct Manifest: Codable {
        let appPath: String
        let info: AppInfo
        let files: [String: String]
    }

    public static func apply(app: URL, plan: PatchPlan, backupRoot: URL, signer: (URL) throws -> Void) throws -> URL {
        let app = app.standardizedFileURL.resolvingSymlinksInPath()
        let root = backupRoot.standardizedFileURL.resolvingSymlinksInPath()
        guard plan.app == app, !plan.writes.isEmpty, !root.path.hasPrefix(app.path + "/"), root != app else {
            throw TweakError("Invalid patch plan or backup location")
        }
        return try withLock(app: app) {
            let info = try AppInfo.read(app: app)
            guard info.build == plan.version else { throw TweakError("Application build changed since preflight") }
            try validateWrites(plan, within: app)
            let fm = FileManager.default
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            let backup = root.appendingPathComponent(UUID().uuidString)
            try fm.createDirectory(at: backup, withIntermediateDirectories: false)
            let original = backup.appendingPathComponent("original.app")
            try fm.copyItem(at: app, to: original)
            let manifest = Manifest(appPath: app.path, info: info, files: try fingerprints(original))
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(manifest).write(to: backup.appendingPathComponent("manifest.json"), options: .atomic)
            let staged = app.deletingLastPathComponent().appendingPathComponent(".WeChatTweak-stage-\(UUID().uuidString).app")
            defer { try? fm.removeItem(at: staged) }
            do {
                try fm.copyItem(at: original, to: staged)
                try validateWrites(plan, within: staged)
                for write in plan.writes {
                    let relative = String(write.file.path.dropFirst(app.path.count + 1))
                    let file = try PatchPlan.targetURL(app: staged, relative: relative)
                    let handle = try FileHandle(forUpdating: file)
                    defer { try? handle.close() }
                    try handle.seek(toOffset: write.offset)
                    try handle.write(contentsOf: write.after)
                    try handle.synchronize()
                }
                try signer(staged)
                let current = try fingerprints(app)
                guard current == manifest.files else { throw TweakError("Application changed during staging; refusing replacement") }
                try ApplicationSwap.replace(app: app, staged: staged)
                return backup
            } catch {
                throw TweakError("Patch failed; backup retained at \(backup.path). \(error.localizedDescription)")
            }
        }
    }

    public static func restore(app: URL, backup: URL) throws {
        let app = app.standardizedFileURL.resolvingSymlinksInPath()
        try withLock(app: app) {
            let fm = FileManager.default
            let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: backup.appendingPathComponent("manifest.json")))
            let original = backup.appendingPathComponent("original.app")
            guard manifest.appPath == app.path, try AppInfo.read(app: app) == manifest.info,
                  try AppInfo.read(app: original) == manifest.info,
                  try fingerprints(original) == manifest.files else {
                throw TweakError("Backup is damaged or belongs to a different application/build")
            }
            let before = try fingerprints(app)
            let staged = app.deletingLastPathComponent().appendingPathComponent(".WeChatTweak-restore-\(UUID().uuidString).app")
            defer { try? fm.removeItem(at: staged) }
            try fm.copyItem(at: original, to: staged)
            guard try fingerprints(staged) == manifest.files, try fingerprints(app) == before else {
                throw TweakError("Application or backup changed during restore")
            }
            try ApplicationSwap.replace(app: app, staged: staged)
        }
    }

    private static func validateWrites(_ plan: PatchPlan, within root: URL) throws {
        for write in plan.writes {
            guard write.file.path.hasPrefix(plan.app.path + "/") else { throw TweakError("Invalid write target") }
            let file = try PatchPlan.targetURL(app: root, relative: String(write.file.path.dropFirst(plan.app.path.count + 1)))
            let handle = try FileHandle(forReadingFrom: file)
            defer { try? handle.close() }
            try handle.seek(toOffset: write.offset)
            guard try handle.read(upToCount: write.before.count) == write.before else {
                throw TweakError("Application bytes changed since preflight")
            }
        }
    }

    private static func withLock<T>(app: URL, body: () throws -> T) throws -> T {
        let lock = app.deletingLastPathComponent().appendingPathComponent(".\(app.lastPathComponent).wechattweak.lock")
        let fd = open(lock.path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw TweakError("Cannot lock application; verify write permissions for \(app.deletingLastPathComponent().path)") }
        defer { close(fd) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw TweakError("Another transaction is using this application") }
        defer { _ = flock(fd, LOCK_UN) }
        return try body()
    }

    private static func fingerprints(_ root: URL) throws -> [String: String] {
        let fm = FileManager.default
        var failure: Error?
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey], errorHandler: { _, error in failure = error; return false }) else {
            throw TweakError("Cannot enumerate application")
        }
        var result: [String: String] = [:]
        for case let file as URL in enumerator {
            // Foundation may enumerate /var through its /private/var alias.
            // Enumerator depth gives the relative name without string-prefix assumptions.
            let relative = file.pathComponents.suffix(enumerator.level).joined(separator: "/")
            let values = try file.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
            if values.isSymbolicLink == true {
                enumerator.skipDescendants()
                result[relative] = "link:" + (try fm.destinationOfSymbolicLink(atPath: file.path))
            } else if values.isRegularFile == true {
                let handle = try FileHandle(forReadingFrom: file)
                defer { try? handle.close() }
                var hash = SHA256()
                while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty { hash.update(data: chunk) }
                result[relative] = hash.finalize().map { String(format: "%02x", $0) }.joined()
            }
        }
        if let failure { throw failure }
        guard !result.isEmpty else { throw TweakError("Empty application backup") }
        return result
    }
}
