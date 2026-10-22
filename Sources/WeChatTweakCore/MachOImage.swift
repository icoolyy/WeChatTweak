import Foundation

/// All offsets and lengths are checked before converting them to Data indices.
struct MachOImage {
    struct Slice {
        let cpu: UInt32
        let offset: UInt64
        let size: UInt64
    }
    let data: Data
    let slices: [Slice]

    init(data: Data) throws {
        self.data = data
        let magic = try Self.read(data, 0, 4, big: true)
        if [0xcafebabe, 0xbebafeca, 0xcafebabf, 0xbfbafeca].contains(magic) {
            let big = magic == 0xcafebabe || magic == 0xcafebabf
            let wide = magic == 0xcafebabf || magic == 0xbfbafeca
            let count = try Self.read(data, 4, 4, big: big)
            guard count > 0, count <= 64 else { throw TweakError("Invalid fat architecture count") }
            let stride: UInt64 = wide ? 32 : 20
            let end = 8 + count * stride
            guard end <= data.count else { throw TweakError("Truncated fat architecture table") }
            var slices: [Slice] = []
            for index in 0..<count {
                let pos = 8 + index * stride
                let cpu = UInt32(try Self.read(data, pos, 4, big: big))
                let offset = try Self.read(data, pos + 8, wide ? 8 : 4, big: big)
                let size = try Self.read(data, pos + (wide ? 16 : 12), wide ? 8 : 4, big: big)
                guard offset >= end, size >= 32, offset <= data.count, size <= UInt64(data.count) - offset,
                      !slices.contains(where: { $0.cpu == cpu || (offset < $0.offset + $0.size && $0.offset < offset + size) }) else {
                    throw TweakError("Invalid or overlapping Mach-O slice")
                }
                slices.append(Slice(cpu: cpu, offset: offset, size: size))
            }
            self.slices = slices
        } else {
            guard try Self.read(data, 0, 4) == 0xfeedfacf, data.count >= 32 else {
                throw TweakError("Expected a 64-bit little-endian Mach-O")
            }
            self.slices = [Slice(cpu: UInt32(try Self.read(data, 4, 4)), offset: 0, size: UInt64(data.count))]
        }
    }

    func offset(arch: Config.Arch, address: UInt64, length: Int) throws -> UInt64 {
        guard length > 0, let slice = slices.first(where: { $0.cpu == arch.cpu }) else {
            throw TweakError("Required architecture \(arch.rawValue) is missing")
        }
        func read(_ pos: UInt64, _ size: Int) throws -> UInt64 {
            guard pos <= slice.size, UInt64(size) <= slice.size - pos else { throw TweakError("Read outside Mach-O slice") }
            return try Self.read(data, slice.offset + pos, size)
        }
        guard try read(0, 4) == 0xfeedfacf, try read(4, 4) == UInt64(arch.cpu) else {
            throw TweakError("Invalid slice header")
        }
        let count = try read(16, 4), commandSize = try read(20, 4)
        guard slice.size >= 32, commandSize <= slice.size - 32, count <= commandSize / 8 else {
            throw TweakError("Invalid load command table")
        }
        let end = 32 + commandSize
        var pos: UInt64 = 32
        var result: UInt64?
        for _ in 0..<count {
            guard pos <= end, end - pos >= 8 else { throw TweakError("Truncated load command") }
            let command = try read(pos, 4), size = try read(pos + 4, 4)
            guard size >= 8, size % 8 == 0, size <= end - pos else { throw TweakError("Invalid load command size") }
            if command == 0x19 {
                guard size >= 72 else { throw TweakError("Truncated segment command") }
                let vm = try read(pos + 24, 8), vmSize = try read(pos + 32, 8)
                let file = try read(pos + 40, 8), fileSize = try read(pos + 48, 8)
                guard vmSize <= UInt64.max - vm, file <= slice.size, fileSize <= slice.size - file, fileSize <= vmSize else {
                    throw TweakError("Invalid segment range")
                }
                if address >= vm, address - vm < vmSize {
                    let delta = address - vm
                    guard delta <= fileSize, UInt64(length) <= fileSize - delta, result == nil else {
                        throw TweakError("Patch crosses file-backed segment or ambiguous address")
                    }
                    result = slice.offset + file + delta
                }
            }
            pos += size
        }
        guard pos == end, let result else { throw TweakError("Patch address is not in a file-backed segment") }
        return result
    }

    private static func read(_ data: Data, _ offset: UInt64, _ size: Int, big: Bool = false) throws -> UInt64 {
        guard offset <= data.count, UInt64(size) <= UInt64(data.count) - offset else { throw TweakError("Truncated Mach-O") }
        var result: UInt64 = 0
        for i in 0..<size {
            let byte = UInt64(data[Int(offset) + i])
            if big { result = (result << 8) | byte }
            else { result |= byte << (i * 8) }
        }
        return result
    }
}
