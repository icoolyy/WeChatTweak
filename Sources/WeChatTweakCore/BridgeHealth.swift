import Foundation
import CryptoKit
import Darwin

public enum BridgeHealth {
    public static var defaultCredential: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/WeChatTweak/bridge-token")
    }
    /// Public health only: the credential is never transmitted by the CLI.
    public static func check(credential: URL = defaultCredential) async -> (available: Bool, reason: String) {
        let fd = open(credential.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { return (false, "Bridge credential unavailable; launch WeChat with the installed bridge") }
        defer { close(fd) }
        var metadata = stat()
        guard fstat(fd, &metadata) == 0, metadata.st_uid == getuid(), metadata.st_mode & S_IFMT == S_IFREG,
              metadata.st_mode & 0o777 == 0o600, (64...65).contains(metadata.st_size) else {
            return (false, "Bridge credential has unsafe ownership, permissions or type")
        }
        var bytes = [UInt8](repeating: 0, count: 66)
        let count = read(fd, &bytes, bytes.count)
        guard count == 64 || (count == 65 && bytes[64] == 10), bytes.prefix(64).allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            return (false, "Bridge credential is malformed")
        }
        let token = Data(bytes.prefix(64))
        let challenge = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased() + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        do {
            let url = URL(string: "http://127.0.0.1:48065/health?challenge=\(challenge)")!
            var request = URLRequest(url: url); request.timeoutInterval = 3; request.cachePolicy = .reloadIgnoringLocalCacheData
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 3; configuration.timeoutIntervalForResource = 3
            let session = URLSession(configuration: configuration)
            defer { session.invalidateAndCancel() }
            let (stream, response) = try await session.bytes(for: request)
            defer { stream.task.cancel() }
            var data = Data()
            for try await byte in stream {
                guard data.count < 8192 else { return (false, "Bridge health response exceeds limit") }
                data.append(byte)
            }
            guard let response = response as? HTTPURLResponse, response.statusCode == 200,
                  response.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("application/json") == true,
                  let body = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return (false, "Port 48065 is not a compatible bridge") }
            let expected = HMAC<SHA256>.authenticationCode(for: Data("wechattweak-health-v1:\(challenge)".utf8), using: SymmetricKey(data: token))
            let hex = expected.map { String(format: "%02x", $0) }.joined()
            guard body["proof"] as? String == hex, body["service"] as? String == "WeChatTweak", body["protocol"] as? Int == 1,
                  body["build"] as? String == "269602" else { return (false, "Bridge identity or protocol verification failed") }
            let caps = body["capabilities"] as? [String: Bool] ?? [:]
            let ready = caps["contacts"] == true && caps["openChat"] == true && body["state"] as? String == "ready"
            return (ready, ready ? "Verified: loaded contacts and confirmed chat opening" : "Bridge running; WeChat state: \(body["state"] as? String ?? "unknown")")
        } catch { return (false, "Bridge not reachable; launch the patched WeChat and log in") }
    }
}
