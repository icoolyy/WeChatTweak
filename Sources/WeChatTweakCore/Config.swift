//
//  Config.swift
//  WeChatTweak
//
//  Created by Sunny Young on 2025/12/5.
//

import Foundation
import MachO

public struct Config: Decodable, Sendable {
    public enum Arch: String, Decodable, Sendable {
        case arm64
        case x86_64

        public var cpu: UInt32 {
            switch self {
            case .arm64:
                return UInt32(CPU_TYPE_ARM64)
            case .x86_64:
                return UInt32(CPU_TYPE_X86_64)
            }
        }
    }

    public struct Entry: Decodable, Sendable {
        public let arch: Arch
        public let addr: UInt64
        public let asm: Data
        public let original: Data?

        private enum CodingKeys: CodingKey {
            case arch
            case addr
            case asm
            case original
        }

        public init(from decoder: any Decoder) throws {
            let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
            self.arch = try container.decode(Arch.self, forKey: .arch)
            self.addr = try {
                let hex = try container.decode(String.self, forKey: .addr)
                guard let value = UInt64(hex, radix: 16) else {
                    throw DecodingError.dataCorruptedError(
                        forKey: CodingKeys.addr,
                        in: container,
                        debugDescription: "Invalid Entry.addr"
                    )
                }
                return value
            }()
            self.asm = try {
                let hex = try container.decode(String.self, forKey: .asm)
                guard let value = Data(hex: hex) else {
                    throw DecodingError.dataCorruptedError(
                        forKey: CodingKeys.asm,
                        in: container,
                        debugDescription: "Invalid Entry.asm"
                    )
                }
                return value
            }()
            let original = try container.decodeIfPresent(String.self, forKey: .original)
            if let original {
                guard let bytes = Data(hex: original), bytes.count == asm.count, !bytes.isEmpty else {
                    throw TweakError("Original bytes must have the same nonzero length as asm")
                }
                self.original = bytes
            } else { self.original = nil }
            guard !asm.isEmpty else { throw TweakError("Patch bytes must not be empty") }
        }
    }

    public struct Target: Decodable, Sendable {
        public let identifier: String
        public let entries: [Entry]
        public let file: String

        private enum CodingKeys: CodingKey {
            case identifier
            case entries
            case file
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.identifier = try container.decode(String.self, forKey: .identifier)
            self.entries = try container.decode([Entry].self, forKey: .entries)
            self.file = try container.decodeIfPresent(String.self, forKey: .file) ?? "Contents/MacOS/WeChat"
        }
    }

    public let version: String
    public let targets: [Target]

    public init(version: String, targets: [Target]) {
        self.version = version
        self.targets = targets
    }

    public static func load(url: URL) async throws -> [Config] {
        if url.isFileURL {
            return try JSONDecoder().decode(
                [Config].self,
                from: Data(contentsOf: url)
            )
        } else {
            guard ["https", "http"].contains(url.scheme?.lowercased() ?? "") else {
                throw TweakError("Config URL must use HTTP or HTTPS")
            }
            let (data, response) = try await URLSession.shared.data(from: url)
            return try decode(data: data, response: response)
        }
    }

    public static func decode(data: Data, response: URLResponse) throws -> [Config] {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw TweakError("Config download failed: HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        return try JSONDecoder().decode([Config].self, from: data)
    }

    public static func defaultURL(executable: URL) throws -> URL {
        let url = executable.resolvingSymlinksInPath().deletingLastPathComponent().appendingPathComponent("config.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw TweakError("No packaged config.json found. Pass --config /path/to/config.json or build with make build")
        }
        return url
    }
}

private extension Data {
    init?(hex: String) {
        let chars = Array(hex.utf8)
        guard chars.count % 2 == 0 else { return nil }

        self.init()
        self.reserveCapacity(chars.count / 2)

        func nibble(_ c: UInt8) -> UInt8? {
            switch c {
            case 48...57:  return c - 48       // '0'...'9'
            case 65...70:  return c - 55       // 'A'...'F'
            case 97...102: return c - 87       // 'a'...'f'
            default:       return nil
            }
        }

        var i = 0
        while i < chars.count {
            guard let hi = nibble(chars[i]),
                  let lo = nibble(chars[i + 1]) else { return nil }
            append(hi << 4 | lo)
            i += 2
        }
    }
}
