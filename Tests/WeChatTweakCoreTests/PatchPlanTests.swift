import Foundation
import WeChatTweakCore

final class PatchPlanTests {
    func testThinAndFatOffsets() throws {
        try withFixture { app, file in
            let plan = try PatchPlan.prepare(app: app, config: testConfig())
            try checkEqual(plan.writes.count, 1)
            try checkEqual(plan.writes[0].offset, 0x100)
            try checkEqual(plan.writes[0].before, Data([1,2,3,4,5,6,7,8]))
            try checkEqual(try Data(contentsOf: file), thinFixture())
        }
        try withFixture(fatFixture()) { app, _ in
            try checkEqual(try PatchPlan.prepare(app: app, config: testConfig()).writes[0].offset, 0x500)
        }
    }

    func testRejectsZeroFillBoundaryAndWrongBytes() throws {
        try withFixture { app, file in
            for address in ["11fc", "1200", "ffffffffffffffff"] {
                try checkThrows(try PatchPlan.prepare(app: app, config: testConfig(addr: address)))
            }
            try checkThrows(try PatchPlan.prepare(app: app, config: testConfig(original: "0000000000000000")))
            try checkEqual(try Data(contentsOf: file), thinFixture())
        }
    }

    func testMalformedCommandsAndMissingArchitecture() throws {
        var malformed = thinFixture(); malformed[36] = 0
        try withFixture(malformed) { app, _ in
            try checkThrows(try PatchPlan.prepare(app: app, config: testConfig()))
        }
        try withFixture(Data(thinFixture().prefix(40))) { app, _ in
            try checkThrows(try PatchPlan.prepare(app: app, config: testConfig()))
        }
        try withFixture { app, _ in
            try checkThrows(try PatchPlan.prepare(app: app, config: testConfig(arch: "x86_64")))
        }
    }

    func testRejectsPathEscapeAndSymlink() throws {
        try withFixture { app, file in
            for path in ["/tmp/outside", "../outside", "Contents/../../outside"] {
                try checkThrows(try PatchPlan.prepare(app: app, config: testConfig(file: path)))
            }
            try FileManager.default.createSymbolicLink(at: app.appendingPathComponent("outside"), withDestinationURL: app.deletingLastPathComponent())
            try checkThrows(try PatchPlan.prepare(app: app, config: testConfig(file: "outside/file")))
            try checkEqual(try Data(contentsOf: file), thinFixture())
        }
    }

    func testResourcesTargetAndIdempotency() throws {
        try withFixture { app, _ in
            let target = app.appendingPathComponent("Contents/Resources/wechat.dylib")
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            var patched = thinFixture()
            patched.replaceSubrange(0x100..<0x108, with: [0,0,128,82,192,3,95,214])
            try patched.write(to: target)
            let plan = try PatchPlan.prepare(app: app, config: testConfig(file: "Contents/Resources/wechat.dylib"))
            try check(plan.writes.isEmpty)
        }
    }

    func testLaterInvalidEntryAndOverlapsLeaveAllFilesUnchanged() throws {
        try withFixture { app, file in
            let second = app.appendingPathComponent("Contents/MacOS/Other")
            try thinFixture().write(to: second)
            let good = try testConfig()
            let bad = try testConfig(file: "Contents/MacOS/Other", original: "0000000000000000")
            let combined = Config(version: "269602", targets: good.targets + bad.targets)
            try checkThrows(try PatchPlan.prepare(app: app, config: combined))
            try checkThrows(try PatchPlan.prepare(app: app, config: Config(version: "269602", targets: good.targets + good.targets)))
            try checkEqual(try Data(contentsOf: file), thinFixture())
            try checkEqual(try Data(contentsOf: second), thinFixture())
        }
    }
}

@MainActor let patchTests: [(String, () throws -> Void)] = [
    ("thin and fat offsets", PatchPlanTests().testThinAndFatOffsets),
    ("zero fill, bounds, original bytes", PatchPlanTests().testRejectsZeroFillBoundaryAndWrongBytes),
    ("malformed Mach-O and missing arch", PatchPlanTests().testMalformedCommandsAndMissingArchitecture),
    ("path escape and symlink", PatchPlanTests().testRejectsPathEscapeAndSymlink),
    ("Resources target and idempotency", PatchPlanTests().testResourcesTargetAndIdempotency),
    ("all-target preflight and overlaps", PatchPlanTests().testLaterInvalidEntryAndOverlapsLeaveAllFilesUnchanged),
]
