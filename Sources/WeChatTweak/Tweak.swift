import Foundation
import ArgumentParser
import WeChatTweakCore

@main
struct Tweak: AsyncParsableCommand {
    static func main() async {
        do {
            var command = try parseAsRoot()
            if var command = command as? any AsyncParsableCommand { try await command.run() }
            else { try command.run() }
        } catch { exit(withError: error) }
    }
    static let configuration = CommandConfiguration(
        commandName: "wechattweak", abstract: "Inspect, patch and restore WeChat.",
        version: "2.1.0-dev", subcommands: [Versions.self, Doctor.self, Patch.self, Restore.self]
    )

    struct Options: ParsableArguments {
        @Option(name: .shortAndLong, help: "Path of WeChat.app")
        var app: String = "/Applications/WeChat.app"
        @Option(name: .shortAndLong, help: "Local config.json path or explicit HTTP(S) URL")
        var config: String?
        var appURL: URL { URL(fileURLWithPath: app).standardizedFileURL.resolvingSymlinksInPath() }
        func configURL() throws -> URL {
            if let config {
                if let url = URL(string: config), ["http", "https"].contains(url.scheme?.lowercased() ?? "") { return url }
                return URL(fileURLWithPath: config)
            }
            return try Config.defaultURL(executable: Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0]))
        }
    }

    struct Versions: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List app build and available patch configurations")
        @OptionGroup var options: Options
        mutating func run() async throws {
            let info = try AppInfo.read(app: options.appURL)
            let source = try options.configURL()
            print("Current WeChat: \(info.displayVersion) (\(info.build))")
            print("Config: \(source.absoluteString)")
            for config in try await Config.load(url: source) { print(config.version) }
        }
    }

    struct Doctor: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Read-only compatibility and patch-state diagnostics")
        @OptionGroup var options: Options
        @Flag(help: "Print machine-readable diagnostics") var json = false
        mutating func run() async throws {
            var report = Diagnostic(appPath: options.appURL.path)
            do {
                report.app = try AppInfo.read(app: options.appURL)
                let source = try options.configURL()
                report.configSource = source.absoluteString
                let configs = try await Config.load(url: source)
                if let config = configs.first(where: { $0.version == report.app?.build }) {
                    report.configuredFeatures = config.targets.map(\.identifier)
                    let plan = try PatchPlan.prepare(app: options.appURL, config: config)
                    report.pendingWrites = plan.writes.count
                    report.alreadyPatched = plan.alreadyPatched
                    report.unverifiedLegacyEntries = plan.unverifiedLegacyEntries
                    report.patchState = plan.writes.isEmpty ? "applied" : (plan.alreadyPatched > 0 ? "partiallyApplied" : "ready")
                } else { report.patchState = "unsupportedBuild" }
            } catch { report.patchState = "error"; report.errors.append(error.localizedDescription) }
            if json {
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                print(String(decoding: try encoder.encode(report), as: UTF8.self))
            } else {
                print("App: \(report.appPath)")
                if let app = report.app { print("WeChat: \(app.displayVersion) (\(app.build))") }
                print("Config: \(report.configSource ?? "unavailable")")
                print("Patch state: \(report.patchState); pending writes: \(report.pendingWrites)")
                print("Configured features: \(report.configuredFeatures.joined(separator: ", "))")
                print("Original-byte verification missing for \(report.unverifiedLegacyEntries) legacy entries")
                print("Raycast contacts bridge: unavailable (native adapter not verified)")
                for error in report.errors { print("Error: \(error)") }
            }
            if !report.errors.isEmpty { throw ExitCode.failure }
        }
    }

    struct Patch: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Preflight, back up and patch WeChat")
        @OptionGroup var options: Options
        @Flag(help: "Validate and list writes without modifying any application file") var dryRun = false
        @Option(help: "Directory retaining complete original application backups") var backupDir: String?
        mutating func run() async throws {
            let app = options.appURL
            let info = try AppInfo.read(app: app)
            let source = try options.configURL()
            print("WeChat: \(info.displayVersion) (\(info.build))")
            print("Config: \(source.absoluteString)")
            guard let config = try await Config.load(url: source).first(where: { $0.version == info.build }) else {
                throw TweakError("Unsupported WeChat build \(info.build); no files changed")
            }
            let plan = try PatchPlan.prepare(app: app, config: config)
            print("Preflight passed: \(plan.writes.count) writes, \(plan.alreadyPatched) already patched")
            for write in plan.writes { print("\(write.file.path) @ 0x\(String(write.offset, radix: 16)): \(write.before.count) bytes") }
            if plan.unverifiedLegacyEntries > 0 { print("Warning: \(plan.unverifiedLegacyEntries) legacy entries have no original-byte constraint") }
            if dryRun { print("Dry run: no files changed"); return }
            if plan.writes.isEmpty { print("Already patched; no files changed"); return }
            try Command.requireStopped(app: app)
            let root = backupDir.map { URL(fileURLWithPath: $0) } ?? app.deletingLastPathComponent().appendingPathComponent(".WeChatTweakBackups")
            let files = plan.writes.map { String($0.file.path.dropFirst(app.path.count + 1)) }
            let backup = try AppTransaction.apply(app: app, plan: plan, backupRoot: root) { staged in
                try Command.resign(app: staged, relativeFiles: files)
            }
            print("Patch and signature verification completed. Backup: \(backup.path)")
            print("Native behavior still requires live verification; this does not install a Raycast contacts bridge.")
        }
    }

    struct Restore: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Restore a complete original app from a verified backup")
        @Option(name: .shortAndLong) var app: String = "/Applications/WeChat.app"
        @Option(help: "Backup directory containing manifest.json and original.app") var backup: String
        mutating func run() async throws {
            let app = URL(fileURLWithPath: app)
            try Command.requireStopped(app: app)
            try AppTransaction.restore(app: app, backup: URL(fileURLWithPath: backup))
            print("Original application restored; backup retained.")
        }
    }
}

struct Diagnostic: Encodable {
    let schemaVersion = 1
    let cliVersion = "2.1.0-dev"
    let appPath: String
    var app: AppInfo?
    var configSource: String?
    var patchState = "unknown"
    var configuredFeatures: [String] = []
    var pendingWrites = 0
    var alreadyPatched = 0
    var unverifiedLegacyEntries = 0
    let contactsBridgeAvailable = false
    let contactsBridgeReason = "No verified native contacts/open-chat adapter for this build"
    var errors: [String] = []
}

