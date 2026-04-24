import Foundation

struct TestFailure {
    let name: String
    let message: String
    let file: String
    let line: Int
}

struct TestReport {
    var passed: Int = 0
    var failed: Int = 0
    var assertions: Int = 0
    var failures: [TestFailure] = []

    mutating func merge(_ other: TestReport) {
        passed += other.passed
        failed += other.failed
        assertions += other.assertions
        failures.append(contentsOf: other.failures)
    }
}

enum TestAssert {
    static func assertTrue(
        _ condition: @autoclosure () -> Bool,
        _ message: String = "assertTrue failed",
        file: String = #file,
        line: Int = #line,
        report: inout TestReport
    ) {
        report.assertions += 1
        if condition() { return }
        report.failed += 1
        report.failures.append(TestFailure(name: "", message: message, file: file, line: line))
    }

    static func assertEqual<T: Equatable>(
        _ actual: @autoclosure () -> T,
        _ expected: @autoclosure () -> T,
        _ message: String = "",
        file: String = #file,
        line: Int = #line,
        report: inout TestReport
    ) {
        report.assertions += 1
        let a = actual()
        let e = expected()
        if a == e { return }
        report.failed += 1
        let msg = message.isEmpty ? "expected \(e) got \(a)" : "\(message): expected \(e) got \(a)"
        report.failures.append(TestFailure(name: "", message: msg, file: file, line: line))
    }

    static func assertNil<T>(
        _ value: @autoclosure () -> T?,
        _ message: String = "expected nil",
        file: String = #file,
        line: Int = #line,
        report: inout TestReport
    ) {
        report.assertions += 1
        if value() == nil { return }
        report.failed += 1
        report.failures.append(TestFailure(name: "", message: message, file: file, line: line))
    }

    static func assertNotNil<T>(
        _ value: @autoclosure () -> T?,
        _ message: String = "expected non-nil",
        file: String = #file,
        line: Int = #line,
        report: inout TestReport
    ) {
        report.assertions += 1
        if value() != nil { return }
        report.failed += 1
        report.failures.append(TestFailure(name: "", message: message, file: file, line: line))
    }
}

enum TestRunner {
    static func runAll() -> Int32 {
        var total = TestReport()
        let cases: [(String, (inout TestReport) -> Void)] =
            HistoryDiffStateTests.allCases +
            SyncTeXServiceTests.allCases +
            MathHoverDetectorTests.allCases +
            SyncTeXBridgeTests.allCases +
            ExtendedTests.allCases

        for (name, test) in cases {
            var sub = TestReport()
            test(&sub)
            total.merge(sub)
            let status = sub.failed == 0 ? "PASS" : "FAIL"
            print("[\(status)] \(name)  (\(sub.assertions) checks)")
            for failure in sub.failures {
                print("   ✗ \(failure.message) @ \(failure.file):\(failure.line)")
            }
        }

        print("")
        print("────────────────────────────────────")
        print("Tests: \(total.passed) passed, \(total.failed) failed, \(cases.count) total")
        print("Total assertions: \(total.assertions)")
        return total.failed == 0 ? 0 : 1
    }
}
