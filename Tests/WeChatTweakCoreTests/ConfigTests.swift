import Foundation
import WeChatTweakCore

final class ConfigTests {
    func testHTTPFailureIsReportedBeforeJSONDecoding() throws {
        let response = HTTPURLResponse(url: URL(string: "https://example.invalid/config.json")!, statusCode: 404, httpVersion: nil, headerFields: nil)!
        let error = try checkThrows(try Config.decode(data: Data("not JSON".utf8), response: response))
        try check(error.localizedDescription.contains("404"))
    }

    func testDefaultConfigUsesExecutableDirectory() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let executable = dir.appendingPathComponent("wechattweak")
        try checkThrows(try Config.defaultURL(executable: executable))
        let config = dir.appendingPathComponent("config.json")
        try Data("[]".utf8).write(to: config)
        try checkEqual(try Config.defaultURL(executable: executable), config)
    }

    func testLegacyConfigStillDecodes() throws {
        let json = #"{"version":"31927","targets":[{"identifier":"revoke","entries":[{"arch":"arm64","addr":"103dba3d0","asm":"00008052C0035FD6"}]}]}"#
        let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        try checkEqual(config.targets[0].entries[0].addr, 0x103dba3d0)
        try checkEqual(config.targets[0].entries[0].asm, Data([0, 0, 128, 82, 192, 3, 95, 214]))
    }
}
