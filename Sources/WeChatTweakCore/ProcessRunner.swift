import Foundation

public enum ProcessRunner {
    @discardableResult
    public static func run(executable: URL, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: output, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw TweakError("\(executable.lastPathComponent) failed (\(process.terminationStatus)): \(text)")
        }
        return text
    }
}
