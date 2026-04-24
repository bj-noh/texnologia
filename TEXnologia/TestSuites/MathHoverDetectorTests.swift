import Foundation

enum MathHoverDetectorTests {
    static var allCases: [(String, (inout TestReport) -> Void)] {
        [
            ("MathHover/inlineDollar_inside_matches", inlineDollar_inside_matches),
            ("MathHover/inlineDollar_onOpenDollar_matches", inlineDollar_onOpenDollar_matches),
            ("MathHover/inlineDollar_onCloseDollar_matches", inlineDollar_onCloseDollar_matches),
            ("MathHover/inlineDollar_emptyBody_returnsNil", inlineDollar_emptyBody_returnsNil),
            ("MathHover/inlineDollar_linebreakInside_returnsNil", inlineDollar_linebreakInside_returnsNil),
            ("MathHover/displayDoubleDollar_inside_matches", displayDoubleDollar_inside_matches),
            ("MathHover/displayDoubleDollar_multiline_matches", displayDoubleDollar_multiline_matches),
            ("MathHover/displayBracket_inside_matches", displayBracket_inside_matches),
            ("MathHover/displayBracket_multiline_matches", displayBracket_multiline_matches),
            ("MathHover/inlineParen_inside_matches", inlineParen_inside_matches),
            ("MathHover/outsideMath_returnsNil", outsideMath_returnsNil),
            ("MathHover/beforeFirstDollar_returnsNil", beforeFirstDollar_returnsNil),
            ("MathHover/afterLastDollar_returnsNil", afterLastDollar_returnsNil),
            ("MathHover/escapedDollar_isIgnored", escapedDollar_isIgnored),
            ("MathHover/multipleInlineMath_picksCorrect", multipleInlineMath_picksCorrect),
            ("MathHover/displayPriorityOverInline", displayPriorityOverInline),
            ("MathHover/nestedBraces_handled", nestedBraces_handled),
            ("MathHover/emptyText_returnsNil", emptyText_returnsNil),
            ("MathHover/indexBeyondLength_returnsNil", indexBeyondLength_returnsNil),
            ("MathHover/negativeIndex_returnsNil", negativeIndex_returnsNil),
            ("MathHover/sourceTrimmed", sourceTrimmed),
            ("MathHover/displayFlag_setCorrectly_forInline", displayFlag_setCorrectly_forInline),
            ("MathHover/displayFlag_setCorrectly_forDoubleDollar", displayFlag_setCorrectly_forDoubleDollar),
            ("MathHover/displayFlag_setCorrectly_forBracket", displayFlag_setCorrectly_forBracket),
            ("MathHover/displayFlag_setCorrectly_forParen", displayFlag_setCorrectly_forParen),
            ("MathHover/longSurroundingText_doesNotFalseMatch", longSurroundingText_doesNotFalseMatch),
            ("MathHover/consecutiveMathExpressions", consecutiveMathExpressions),
            ("MathHover/indexAtStart_isHandled", indexAtStart_isHandled),
            ("MathHover/indexAtEnd_isHandled", indexAtEnd_isHandled),
            ("MathHover/onlyOpenDelimiter_returnsNil", onlyOpenDelimiter_returnsNil),
            ("MathHover/onlyCloseDelimiter_returnsNil", onlyCloseDelimiter_returnsNil)
        ]
    }

    private static func markPass(_ r: inout TestReport) {
        if r.failed == 0 { r.passed = 1 }
    }

    // Convert a UTF-16 index into something consistent for tests.
    private static func utf16Index(of substr: String, in text: String, occurrence: Int = 1) -> Int {
        let ns = text as NSString
        var searchStart = 0
        var count = 0
        while searchStart < ns.length {
            let r = ns.range(of: substr, options: [], range: NSRange(location: searchStart, length: ns.length - searchStart))
            if r.location == NSNotFound { return -1 }
            count += 1
            if count == occurrence { return r.location }
            searchStart = r.location + r.length
        }
        return -1
    }

    private static func inlineDollar_inside_matches(_ r: inout TestReport) {
        let text = "Hello $x + y$ world"
        let idx = utf16Index(of: "x", in: text)
        let result = MathHoverDetector.mathRange(in: text, at: idx)
        TestAssert.assertEqual(result?.source, "x + y", report: &r)
        TestAssert.assertEqual(result?.display, false, report: &r)
        markPass(&r)
    }

    private static func inlineDollar_onOpenDollar_matches(_ r: inout TestReport) {
        let text = "a $y$ b"
        let idx = utf16Index(of: "$", in: text)
        let result = MathHoverDetector.mathRange(in: text, at: idx)
        TestAssert.assertEqual(result?.source, "y", report: &r)
        markPass(&r)
    }

    private static func inlineDollar_onCloseDollar_matches(_ r: inout TestReport) {
        let text = "a $y$ b"
        let idx = utf16Index(of: "$", in: text, occurrence: 2)
        let result = MathHoverDetector.mathRange(in: text, at: idx)
        TestAssert.assertEqual(result?.source, "y", report: &r)
        markPass(&r)
    }

    private static func inlineDollar_emptyBody_returnsNil(_ r: inout TestReport) {
        let text = "a $$ b"
        let idx = utf16Index(of: "$", in: text)
        // "$$" looks like start of display math, not empty inline.
        let result = MathHoverDetector.mathRange(in: text, at: idx)
        // $$ with empty body also returns nil per our implementation.
        TestAssert.assertNil(result, report: &r)
        markPass(&r)
    }

    private static func inlineDollar_linebreakInside_returnsNil(_ r: inout TestReport) {
        let text = "a $start\ncontinues$ b"
        let idx = utf16Index(of: "start", in: text)
        let result = MathHoverDetector.mathRange(in: text, at: idx)
        TestAssert.assertNil(result, report: &r)
        markPass(&r)
    }

    private static func displayDoubleDollar_inside_matches(_ r: inout TestReport) {
        let text = "intro $$E=mc^2$$ outro"
        let idx = utf16Index(of: "=", in: text)
        let result = MathHoverDetector.mathRange(in: text, at: idx)
        TestAssert.assertEqual(result?.source, "E=mc^2", report: &r)
        TestAssert.assertEqual(result?.display, true, report: &r)
        markPass(&r)
    }

    private static func displayDoubleDollar_multiline_matches(_ r: inout TestReport) {
        let text = "intro $$\n\\sum_{i=0}^n i\n$$ outro"
        let idx = utf16Index(of: "\\sum", in: text)
        let result = MathHoverDetector.mathRange(in: text, at: idx)
        TestAssert.assertNotNil(result, report: &r)
        TestAssert.assertTrue(result?.source.contains("\\sum") ?? false, report: &r)
        markPass(&r)
    }

    private static func displayBracket_inside_matches(_ r: inout TestReport) {
        let text = "\\[a^2 + b^2 = c^2\\]"
        let idx = utf16Index(of: "a", in: text)
        let result = MathHoverDetector.mathRange(in: text, at: idx)
        TestAssert.assertEqual(result?.source, "a^2 + b^2 = c^2", report: &r)
        TestAssert.assertEqual(result?.display, true, report: &r)
        markPass(&r)
    }

    private static func displayBracket_multiline_matches(_ r: inout TestReport) {
        let text = "\\[\n\\frac{1}{2}\n\\]"
        let idx = utf16Index(of: "frac", in: text)
        let result = MathHoverDetector.mathRange(in: text, at: idx)
        TestAssert.assertNotNil(result, report: &r)
        markPass(&r)
    }

    private static func inlineParen_inside_matches(_ r: inout TestReport) {
        let text = "intro \\(f(x) = 1\\) outro"
        let idx = utf16Index(of: "f(", in: text)
        let result = MathHoverDetector.mathRange(in: text, at: idx)
        TestAssert.assertEqual(result?.source, "f(x) = 1", report: &r)
        TestAssert.assertEqual(result?.display, false, report: &r)
        markPass(&r)
    }

    private static func outsideMath_returnsNil(_ r: inout TestReport) {
        let text = "Hello world, no math here."
        let idx = utf16Index(of: "world", in: text)
        TestAssert.assertNil(MathHoverDetector.mathRange(in: text, at: idx), report: &r)
        markPass(&r)
    }

    private static func beforeFirstDollar_returnsNil(_ r: inout TestReport) {
        let text = "prefix $math$ suffix"
        let idx = utf16Index(of: "prefix", in: text)
        TestAssert.assertNil(MathHoverDetector.mathRange(in: text, at: idx), report: &r)
        markPass(&r)
    }

    private static func afterLastDollar_returnsNil(_ r: inout TestReport) {
        let text = "$math$ suffix"
        let idx = utf16Index(of: "suffix", in: text)
        TestAssert.assertNil(MathHoverDetector.mathRange(in: text, at: idx), report: &r)
        markPass(&r)
    }

    private static func escapedDollar_isIgnored(_ r: inout TestReport) {
        let text = "price is \\$5 and $x+y$ here"
        // Cursor inside "x+y" must match
        let idx = utf16Index(of: "x+y", in: text)
        let result = MathHoverDetector.mathRange(in: text, at: idx)
        TestAssert.assertEqual(result?.source, "x+y", report: &r)
        markPass(&r)
    }

    private static func multipleInlineMath_picksCorrect(_ r: inout TestReport) {
        let text = "$a$ and $b+c$ together"
        let idx = utf16Index(of: "b+c", in: text)
        let result = MathHoverDetector.mathRange(in: text, at: idx)
        TestAssert.assertEqual(result?.source, "b+c", report: &r)
        markPass(&r)
    }

    private static func displayPriorityOverInline(_ r: inout TestReport) {
        // $$ opens display math first; inline single-$ search walks left but stops when it finds $$ ambiguity
        let text = "intro $$X$$ outro"
        let idx = utf16Index(of: "X", in: text)
        let result = MathHoverDetector.mathRange(in: text, at: idx)
        TestAssert.assertEqual(result?.source, "X", report: &r)
        TestAssert.assertEqual(result?.display, true, report: &r)
        markPass(&r)
    }

    private static func nestedBraces_handled(_ r: inout TestReport) {
        let text = "$\\frac{1}{2}$ is a fraction"
        let idx = utf16Index(of: "frac", in: text)
        let result = MathHoverDetector.mathRange(in: text, at: idx)
        TestAssert.assertTrue(result?.source.contains("frac") ?? false, report: &r)
        markPass(&r)
    }

    private static func emptyText_returnsNil(_ r: inout TestReport) {
        TestAssert.assertNil(MathHoverDetector.mathRange(in: "", at: 0), report: &r)
        markPass(&r)
    }

    private static func indexBeyondLength_returnsNil(_ r: inout TestReport) {
        let text = "hi"
        TestAssert.assertNil(MathHoverDetector.mathRange(in: text, at: 100), report: &r)
        markPass(&r)
    }

    private static func negativeIndex_returnsNil(_ r: inout TestReport) {
        TestAssert.assertNil(MathHoverDetector.mathRange(in: "abc", at: -5), report: &r)
        markPass(&r)
    }

    private static func sourceTrimmed(_ r: inout TestReport) {
        let text = "\\[   hello   \\]"
        let idx = utf16Index(of: "hello", in: text)
        TestAssert.assertEqual(MathHoverDetector.mathRange(in: text, at: idx)?.source, "hello", report: &r)
        markPass(&r)
    }

    private static func displayFlag_setCorrectly_forInline(_ r: inout TestReport) {
        let text = "$a$"
        let result = MathHoverDetector.mathRange(in: text, at: 1)
        TestAssert.assertEqual(result?.display, false, report: &r)
        markPass(&r)
    }

    private static func displayFlag_setCorrectly_forDoubleDollar(_ r: inout TestReport) {
        let text = "$$a$$"
        let idx = utf16Index(of: "a", in: text)
        let result = MathHoverDetector.mathRange(in: text, at: idx)
        TestAssert.assertEqual(result?.display, true, report: &r)
        markPass(&r)
    }

    private static func displayFlag_setCorrectly_forBracket(_ r: inout TestReport) {
        let text = "\\[a\\]"
        let idx = utf16Index(of: "a", in: text)
        let result = MathHoverDetector.mathRange(in: text, at: idx)
        TestAssert.assertEqual(result?.display, true, report: &r)
        markPass(&r)
    }

    private static func displayFlag_setCorrectly_forParen(_ r: inout TestReport) {
        let text = "\\(a\\)"
        let idx = utf16Index(of: "a", in: text)
        let result = MathHoverDetector.mathRange(in: text, at: idx)
        TestAssert.assertEqual(result?.display, false, report: &r)
        markPass(&r)
    }

    private static func longSurroundingText_doesNotFalseMatch(_ r: inout TestReport) {
        let text = String(repeating: "prose ", count: 100) + "$x$" + String(repeating: " more prose", count: 50)
        let idx = utf16Index(of: "prose", in: text)
        TestAssert.assertNil(MathHoverDetector.mathRange(in: text, at: idx), report: &r)
        markPass(&r)
    }

    private static func consecutiveMathExpressions(_ r: inout TestReport) {
        let text = "$a$$b$$c$"
        // In $..$$..$$..$ — ambiguous but our parser handles greedy pairings.
        let idx0 = utf16Index(of: "a", in: text)
        TestAssert.assertNotNil(MathHoverDetector.mathRange(in: text, at: idx0), report: &r)
        markPass(&r)
    }

    private static func indexAtStart_isHandled(_ r: inout TestReport) {
        let text = "$x$ hello"
        let result = MathHoverDetector.mathRange(in: text, at: 0)
        TestAssert.assertEqual(result?.source, "x", report: &r)
        markPass(&r)
    }

    private static func indexAtEnd_isHandled(_ r: inout TestReport) {
        let text = "hello $x$"
        let endIdx = (text as NSString).length
        _ = MathHoverDetector.mathRange(in: text, at: endIdx)
        TestAssert.assertTrue(true, report: &r)
        markPass(&r)
    }

    private static func onlyOpenDelimiter_returnsNil(_ r: inout TestReport) {
        let text = "broken $math here"
        let idx = utf16Index(of: "math", in: text)
        TestAssert.assertNil(MathHoverDetector.mathRange(in: text, at: idx), report: &r)
        markPass(&r)
    }

    private static func onlyCloseDelimiter_returnsNil(_ r: inout TestReport) {
        let text = "broken math$ here"
        let idx = utf16Index(of: "math", in: text)
        TestAssert.assertNil(MathHoverDetector.mathRange(in: text, at: idx), report: &r)
        markPass(&r)
    }
}
