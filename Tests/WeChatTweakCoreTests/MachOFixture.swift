import Foundation
import WeChatTweakCore

// Hand-checked: header 32, LC_SEGMENT_64 72, text file offset 0x100,
// VM base 0x1000. VA 0x1100 maps to byte 0x100 in a thin slice.
func thinFixture(cpu: UInt32 = 0x0100000c) -> Data {
    var data = Data(repeating: 0, count: 0x200)
    func put(_ value: UInt64, _ offset: Int, _ size: Int) {
        for i in 0..<size { data[offset + i] = UInt8(truncatingIfNeeded: value >> (i * 8)) }
    }
    put(0xfeedfacf, 0, 4); put(UInt64(cpu), 4, 4)
    put(2, 12, 4); put(1, 16, 4); put(72, 20, 4)
    put(0x19, 32, 4); put(72, 36, 4)
    data.replaceSubrange(40..<46, with: Data("__TEXT".utf8))
    put(0x1000, 56, 8); put(0x400, 64, 8)
    put(0, 72, 8); put(0x200, 80, 8)
    data.replaceSubrange(0x100..<0x108, with: [1, 2, 3, 4, 5, 6, 7, 8])
    return data
}

func fatFixture() -> Data {
    var data = Data(repeating: 0, count: 0x600)
    func put(_ value: UInt32, _ offset: Int) {
        for i in 0..<4 { data[offset + i] = UInt8(truncatingIfNeeded: value >> ((3 - i) * 8)) }
    }
    put(0xcafebabe, 0); put(2, 4)
    put(0x01000007, 8); put(0x100, 16); put(0x200, 20)
    put(0x0100000c, 28); put(0x400, 36); put(0x200, 40)
    data.replaceSubrange(0x100..<0x300, with: thinFixture(cpu: 0x01000007))
    data.replaceSubrange(0x400..<0x600, with: thinFixture())
    return data
}

func testConfig(file: String = "Contents/MacOS/WeChat", addr: String = "1100", original: String = "0102030405060708", arch: String = "arm64") throws -> Config {
    let entry: [String: String] = ["arch": arch, "addr": addr, "asm": "00008052C0035FD6", "original": original]
    let object: [String: Any] = ["version": "269602", "targets": [["identifier": "revoke", "file": file, "entries": [entry]]]]
    return try JSONDecoder().decode(Config.self, from: JSONSerialization.data(withJSONObject: object))
}

func withFixture(_ data: Data = thinFixture(), body: (URL, URL) throws -> Void) throws {
    let app = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".app")
    defer { try? FileManager.default.removeItem(at: app) }
    let file = app.appendingPathComponent("Contents/MacOS/WeChat")
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: file)
    try body(app, file)
}
