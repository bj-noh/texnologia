import Foundation

enum SyncTeXBridgeTests {
    static var allCases: [(String, (inout TestReport) -> Void)] {
        [
            ("SyncTeXBridge/lineAndColumn_start", lineAndColumn_start),
            ("SyncTeXBridge/lineAndColumn_firstLineMiddle", lineAndColumn_firstLineMiddle),
            ("SyncTeXBridge/lineAndColumn_afterNewline", lineAndColumn_afterNewline),
            ("SyncTeXBridge/lineAndColumn_multipleLines", lineAndColumn_multipleLines),
            ("SyncTeXBridge/lineAndColumn_endOfText", lineAndColumn_endOfText),
            ("SyncTeXBridge/lineAndColumn_emptyText", lineAndColumn_emptyText),
            ("SyncTeXBridge/lineAndColumn_offsetBeyondLength_clamps", lineAndColumn_offsetBeyondLength_clamps),
            ("SyncTeXBridge/lineAndColumn_offsetNegative_clamps", lineAndColumn_offsetNegative_clamps),
            ("SyncTeXBridge/lineAndColumn_onlyNewlines", lineAndColumn_onlyNewlines),
            ("SyncTeXBridge/lineAndColumn_utf16_emoji", lineAndColumn_utf16_emoji),
            ("SyncTeXBridge/lineAndColumn_crlf_still_countsLines", lineAndColumn_crlf_still_countsLines),
            ("SyncTeXBridge/lineAndColumn_longText_manyLines", lineAndColumn_longText_manyLines)
        ]
    }

    private static func markPass(_ r: inout TestReport) {
        if r.failed == 0 { r.passed = 1 }
    }

    private static func lineAndColumn_start(_ r: inout TestReport) {
        let (line, column) = SyncTeXBridge.lineAndColumn(in: "abc", at: 0)
        TestAssert.assertEqual(line, 1, report: &r)
        TestAssert.assertEqual(column, 0, report: &r)
        markPass(&r)
    }

    private static func lineAndColumn_firstLineMiddle(_ r: inout TestReport) {
        let (line, column) = SyncTeXBridge.lineAndColumn(in: "hello", at: 3)
        TestAssert.assertEqual(line, 1, report: &r)
        TestAssert.assertEqual(column, 3, report: &r)
        markPass(&r)
    }

    private static func lineAndColumn_afterNewline(_ r: inout TestReport) {
        let (line, column) = SyncTeXBridge.lineAndColumn(in: "abc\ndef", at: 4)
        TestAssert.assertEqual(line, 2, report: &r)
        TestAssert.assertEqual(column, 0, report: &r)
        markPass(&r)
    }

    private static func lineAndColumn_multipleLines(_ r: inout TestReport) {
        let (line, column) = SyncTeXBridge.lineAndColumn(in: "a\nb\ncdef", at: 6)
        TestAssert.assertEqual(line, 3, report: &r)
        TestAssert.assertEqual(column, 2, report: &r)
        markPass(&r)
    }

    private static func lineAndColumn_endOfText(_ r: inout TestReport) {
        let text = "xy\nz"
        let (line, column) = SyncTeXBridge.lineAndColumn(in: text, at: (text as NSString).length)
        TestAssert.assertEqual(line, 2, report: &r)
        TestAssert.assertEqual(column, 1, report: &r)
        markPass(&r)
    }

    private static func lineAndColumn_emptyText(_ r: inout TestReport) {
        let (line, column) = SyncTeXBridge.lineAndColumn(in: "", at: 0)
        TestAssert.assertEqual(line, 1, report: &r)
        TestAssert.assertEqual(column, 0, report: &r)
        markPass(&r)
    }

    private static func lineAndColumn_offsetBeyondLength_clamps(_ r: inout TestReport) {
        let (line, column) = SyncTeXBridge.lineAndColumn(in: "abc", at: 999)
        TestAssert.assertEqual(line, 1, report: &r)
        TestAssert.assertEqual(column, 3, report: &r)
        markPass(&r)
    }

    private static func lineAndColumn_offsetNegative_clamps(_ r: inout TestReport) {
        let (line, column) = SyncTeXBridge.lineAndColumn(in: "abc", at: -10)
        TestAssert.assertEqual(line, 1, report: &r)
        TestAssert.assertEqual(column, 0, report: &r)
        markPass(&r)
    }

    private static func lineAndColumn_onlyNewlines(_ r: inout TestReport) {
        let (line, column) = SyncTeXBridge.lineAndColumn(in: "\n\n\n", at: 2)
        TestAssert.assertEqual(line, 3, report: &r)
        TestAssert.assertEqual(column, 0, report: &r)
        markPass(&r)
    }

    private static func lineAndColumn_utf16_emoji(_ r: inout TestReport) {
        // Emoji is outside BMP → 2 UTF-16 units. Our counter works on UTF-16 offsets.
        let text = "ab😀cd"
        // 😀 occupies positions 2 and 3 in UTF-16
        let (line, column) = SyncTeXBridge.lineAndColumn(in: text, at: 4)
        TestAssert.assertEqual(line, 1, report: &r)
        TestAssert.assertEqual(column, 4, report: &r)
        markPass(&r)
    }

    private static func lineAndColumn_crlf_still_countsLines(_ r: inout TestReport) {
        // Our implementation counts 0x0A only. CRLF treats \r as regular char, only \n increments.
        let (line, _) = SyncTeXBridge.lineAndColumn(in: "a\r\nb", at: 3)
        TestAssert.assertEqual(line, 2, report: &r)
        markPass(&r)
    }

    private static func lineAndColumn_longText_manyLines(_ r: inout TestReport) {
        var buf = ""
        for i in 0..<100 { buf += "line \(i)\n" }
        let (line, _) = SyncTeXBridge.lineAndColumn(in: buf, at: (buf as NSString).length)
        TestAssert.assertEqual(line, 101, report: &r)
        markPass(&r)
    }
}
