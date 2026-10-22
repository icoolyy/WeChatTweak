import Foundation
import Darwin

struct TestFailure: Error, CustomStringConvertible { let description: String }
func check(_ value: @autoclosure () throws -> Bool, file: StaticString = #filePath, line: UInt = #line) throws {
    if try !value() { throw TestFailure(description: "\(file):\(line): assertion failed") }
}
func checkEqual<T: Equatable>(_ actual: T, _ expected: T, file: StaticString = #filePath, line: UInt = #line) throws {
    if actual != expected { throw TestFailure(description: "\(file):\(line): expected \(expected), got \(actual)") }
}
@discardableResult func checkThrows<T>(_ value: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) throws -> Error {
    do { _ = try value() } catch { return error }
    throw TestFailure(description: "\(file):\(line): expected an error")
}
let tests: [(String, () throws -> Void)] = [
    ("reads build without GUI", AppInfoTests().testReadsBuildWithoutGUISession),
    ("rejects malformed plist", AppInfoTests().testRejectsMissingOrMalformedPlist),
    ("config beside executable", ConfigTests().testDefaultConfigUsesExecutableDirectory),
    ("legacy config", ConfigTests().testLegacyConfigStillDecodes),
    ("HTTP failure before decode", ConfigTests().testHTTPFailureIsReportedBeforeJSONDecoding),
]
var failures = 0
for (name, body) in tests {
    do { try body(); print("PASS: \(name)") }
    catch { failures += 1; print("FAIL: \(name): \(error)") }
}
print("\(tests.count) tests, \(failures) failures")
exit(failures == 0 ? 0 : 1)
