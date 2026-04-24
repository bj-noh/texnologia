import Foundation

enum ExtendedTests {
    static var allCases: [(String, (inout TestReport) -> Void)] {
        var cases: [(String, (inout TestReport) -> Void)] = []

        // Offset → (line, column) parametric — 40 cases.
        let offsetSamples: [(text: String, offset: Int, line: Int, col: Int)] = [
            ("", 0, 1, 0),
            ("a", 0, 1, 0),
            ("a", 1, 1, 1),
            ("ab", 2, 1, 2),
            ("a\nb", 0, 1, 0),
            ("a\nb", 1, 1, 1),
            ("a\nb", 2, 2, 0),
            ("a\nb", 3, 2, 1),
            ("\n", 0, 1, 0),
            ("\n", 1, 2, 0),
            ("\n\n", 2, 3, 0),
            ("hello", 5, 1, 5),
            ("line1\nline2\nline3", 6, 2, 0),
            ("line1\nline2\nline3", 11, 2, 5),
            ("line1\nline2\nline3", 12, 3, 0),
            ("line1\nline2\nline3", 17, 3, 5),
            ("\n\n\nfourth", 3, 4, 0),
            ("\n\n\nfourth", 9, 4, 6),
            ("a\n\n\nb", 4, 4, 0),
            ("a\n\n\nb", 5, 4, 1),
            ("abc\ndef\nghi", 0, 1, 0),
            ("abc\ndef\nghi", 1, 1, 1),
            ("abc\ndef\nghi", 2, 1, 2),
            ("abc\ndef\nghi", 3, 1, 3),
            ("abc\ndef\nghi", 4, 2, 0),
            ("abc\ndef\nghi", 5, 2, 1),
            ("abc\ndef\nghi", 6, 2, 2),
            ("abc\ndef\nghi", 7, 2, 3),
            ("abc\ndef\nghi", 8, 3, 0),
            ("abc\ndef\nghi", 9, 3, 1),
            ("abc\ndef\nghi", 10, 3, 2),
            ("abc\ndef\nghi", 11, 3, 3),
            ("x", 0, 1, 0),
            ("x\n", 2, 2, 0),
            ("x\n\n", 3, 3, 0),
            ("a\r\nb", 1, 1, 1),
            ("a\r\nb", 3, 2, 0),
            ("a\r\nb", 4, 2, 1),
            (String(repeating: "x", count: 50), 25, 1, 25),
            (String(repeating: "a\n", count: 20), 20, 11, 0)
        ]
        for (i, sample) in offsetSamples.enumerated() {
            let name = "Extended/lineAndColumn_\(i)"
            cases.append((name, { (r: inout TestReport) in
                let (line, column) = SyncTeXBridge.lineAndColumn(in: sample.text, at: sample.offset)
                TestAssert.assertEqual(line, sample.line, "text=\(sample.text.prefix(20)) offset=\(sample.offset)", report: &r)
                TestAssert.assertEqual(column, sample.col, "text=\(sample.text.prefix(20)) offset=\(sample.offset)", report: &r)
                if r.failed == 0 { r.passed = 1 }
            }))
        }

        // SyncTeX forward parser parametric — 24 cases.
        let forwardSamples: [(label: String, output: String, expectedPage: Int?, expectedX: Double?, expectedY: Double?)] = [
            ("forward_P1", "Page:1\nx:1\ny:1", 1, 1, 1),
            ("forward_P100", "Page:100\nx:5\ny:10", 100, 5, 10),
            ("forward_decimal", "Page:1\nx:1.5\ny:2.5", 1, 1.5, 2.5),
            ("forward_extra_lines", "Header\nPage:2\nMiddle\nx:3\nEnd\ny:4", 2, 3, 4),
            ("forward_missing_page", "x:1\ny:1", nil, nil, nil),
            ("forward_missing_x", "Page:1\ny:1", nil, nil, nil),
            ("forward_missing_y", "Page:1\nx:1", nil, nil, nil),
            ("forward_empty", "", nil, nil, nil),
            ("forward_garbage", "no relevant data here", nil, nil, nil),
            ("forward_p_only_digits", "Page:007\nx:1\ny:1", 7, 1, 1),
            ("forward_p_negative", "Page:-1\nx:1\ny:1", -1, 1, 1),
            ("forward_trailing_newline", "Page:3\nx:2\ny:2\n", 3, 2, 2),
            ("forward_tabs", "\tPage:1\n\tx:2\n\ty:3", 1, 2, 3),
            ("forward_crlf", "Page:4\r\nx:5\r\ny:6", 4, 5, 6),
            ("forward_lf_mixed", "Page:5\nx:6\r\ny:7", 5, 6, 7),
            ("forward_realworld_1", """
                SyncTeX result begin
                Output:document.pdf
                Page:3
                x:134.077
                y:287.512
                h:134.077
                v:293.512
                SyncTeX result end
                """, 3, 134.077, 287.512),
            ("forward_zero_coords", "Page:1\nx:0\ny:0", 1, 0, 0),
            ("forward_very_large_page", "Page:9999\nx:1\ny:1", 9999, 1, 1),
            ("forward_bad_x", "Page:1\nx:abc\ny:1", nil, nil, nil),
            ("forward_bad_y", "Page:1\nx:1\ny:abc", nil, nil, nil),
            ("forward_duplicated_keys_lastWins", "Page:1\nx:1\ny:1\nPage:9\nx:2\ny:3", 9, 2, 3),
            ("forward_interleaved", "Page:2\nfoo\nx:4\nbar\ny:6\nbaz", 2, 4, 6),
            ("forward_spaces_in_values", "Page: 2 \nx: 3 \ny: 4 ", 2, 3, 4),
            ("forward_only_page", "Page:1", nil, nil, nil)
        ]
        for sample in forwardSamples {
            cases.append(("Extended/\(sample.label)", { (r: inout TestReport) in
                let result = SyncTeXService.parseForward(sample.output)
                if let p = sample.expectedPage {
                    TestAssert.assertEqual(result?.page, p, sample.label, report: &r)
                    if let x = sample.expectedX { TestAssert.assertEqual(result?.x ?? -9999, x, sample.label, report: &r) }
                    if let y = sample.expectedY { TestAssert.assertEqual(result?.y ?? -9999, y, sample.label, report: &r) }
                } else {
                    TestAssert.assertNil(result, sample.label, report: &r)
                }
                if r.failed == 0 { r.passed = 1 }
            }))
        }

        // SyncTeX reverse parser parametric — 18 cases.
        let reverseSamples: [(label: String, output: String, expectedInput: String?, expectedLine: Int?, expectedCol: Int?)] = [
            ("reverse_basic", "Input:a.tex\nLine:1", "a.tex", 1, 0),
            ("reverse_with_col", "Input:a.tex\nLine:5\nColumn:3", "a.tex", 5, 3),
            ("reverse_empty", "", nil, nil, nil),
            ("reverse_no_input", "Line:1\nColumn:2", nil, nil, nil),
            ("reverse_no_line", "Input:a.tex\nColumn:2", nil, nil, nil),
            ("reverse_abs_path", "Input:/abs/path/main.tex\nLine:10", "/abs/path/main.tex", 10, 0),
            ("reverse_rel_path", "Input:./rel.tex\nLine:2", "./rel.tex", 2, 0),
            ("reverse_path_spaces", "Input:/a b c.tex\nLine:1", "/a b c.tex", 1, 0),
            ("reverse_crlf", "Input:a.tex\r\nLine:1\r\nColumn:2", "a.tex", 1, 2),
            ("reverse_garbage", "asdf fdsa", nil, nil, nil),
            ("reverse_trailing_newline", "Input:x.tex\nLine:1\n", "x.tex", 1, 0),
            ("reverse_multi_keys_lastWins", "Input:a.tex\nInput:b.tex\nLine:1\nLine:2", "b.tex", 2, 0),
            ("reverse_high_line", "Input:x.tex\nLine:9999", "x.tex", 9999, 0),
            ("reverse_zero_line", "Input:x.tex\nLine:0", "x.tex", 0, 0),
            ("reverse_spaced_values", "Input: a.tex \nLine: 5 \nColumn: 2 ", "a.tex", 5, 2),
            ("reverse_with_extras", """
                SyncTeX result begin
                Output:doc.pdf
                Input:main.tex
                Line:7
                Column:14
                Context:some context
                SyncTeX result end
                """, "main.tex", 7, 14),
            ("reverse_bad_line", "Input:a.tex\nLine:abc", nil, nil, nil),
            ("reverse_bad_col", "Input:a.tex\nLine:1\nColumn:xyz", "a.tex", 1, 0)
        ]
        for sample in reverseSamples {
            cases.append(("Extended/\(sample.label)", { (r: inout TestReport) in
                let result = SyncTeXService.parseReverse(sample.output)
                if let input = sample.expectedInput {
                    TestAssert.assertEqual(result?.inputFile, input, sample.label, report: &r)
                    if let line = sample.expectedLine { TestAssert.assertEqual(result?.line, line, sample.label, report: &r) }
                    if let col = sample.expectedCol { TestAssert.assertEqual(result?.column, col, sample.label, report: &r) }
                } else {
                    TestAssert.assertNil(result, sample.label, report: &r)
                }
                if r.failed == 0 { r.passed = 1 }
            }))
        }

        // Math detection parametric — 30 cases.
        struct MathSample {
            var label: String
            var text: String
            var cursor: Int
            var expectedSource: String?
            var expectedDisplay: Bool?
        }
        let mathSamples: [MathSample] = [
            .init(label: "math_inline_basic", text: "$a$", cursor: 1, expectedSource: "a", expectedDisplay: false),
            .init(label: "math_inline_two_chars", text: "$ab$", cursor: 1, expectedSource: "ab", expectedDisplay: false),
            .init(label: "math_inline_operator", text: "$a+b$", cursor: 2, expectedSource: "a+b", expectedDisplay: false),
            .init(label: "math_inline_frac", text: "$\\frac{1}{2}$", cursor: 5, expectedSource: "\\frac{1}{2}", expectedDisplay: false),
            .init(label: "math_display_dd_basic", text: "$$a$$", cursor: 2, expectedSource: "a", expectedDisplay: true),
            .init(label: "math_display_dd_mid", text: "$$alpha+beta$$", cursor: 4, expectedSource: "alpha+beta", expectedDisplay: true),
            .init(label: "math_bracket_basic", text: "\\[a\\]", cursor: 2, expectedSource: "a", expectedDisplay: true),
            .init(label: "math_bracket_mid", text: "\\[abcdef\\]", cursor: 4, expectedSource: "abcdef", expectedDisplay: true),
            .init(label: "math_paren_basic", text: "\\(a\\)", cursor: 2, expectedSource: "a", expectedDisplay: false),
            .init(label: "math_paren_mid", text: "\\(abcdef\\)", cursor: 5, expectedSource: "abcdef", expectedDisplay: false),
            .init(label: "math_outside_pre", text: "hello $a$ world", cursor: 0, expectedSource: nil, expectedDisplay: nil),
            .init(label: "math_outside_post", text: "hello $a$ world", cursor: 12, expectedSource: nil, expectedDisplay: nil),
            .init(label: "math_inside_prose", text: "prose $math$ here", cursor: 8, expectedSource: "math", expectedDisplay: false),
            .init(label: "math_second_of_two", text: "$first$ and $second$", cursor: 15, expectedSource: "second", expectedDisplay: false),
            .init(label: "math_display_between_inline", text: "$a$ $$b$$ $c$", cursor: 6, expectedSource: "b", expectedDisplay: true),
            .init(label: "math_empty_inline_not_match", text: "$$ hi", cursor: 0, expectedSource: nil, expectedDisplay: nil),
            .init(label: "math_escape_dollar", text: "\\$5 or $x$", cursor: 8, expectedSource: "x", expectedDisplay: false),
            .init(label: "math_near_end", text: "$x$", cursor: 2, expectedSource: "x", expectedDisplay: false),
            .init(label: "math_near_start", text: "$x$", cursor: 0, expectedSource: "x", expectedDisplay: false),
            .init(label: "math_multiline_dd", text: "$$\nABC\n$$", cursor: 3, expectedSource: "ABC", expectedDisplay: true),
            .init(label: "math_multiline_bracket", text: "\\[\nABC\n\\]", cursor: 3, expectedSource: "ABC", expectedDisplay: true),
            .init(label: "math_deep_inside", text: "a $x+y+z+w$ b", cursor: 6, expectedSource: "x+y+z+w", expectedDisplay: false),
            .init(label: "math_long_expression", text: "$" + String(repeating: "x", count: 30) + "$", cursor: 10, expectedSource: String(repeating: "x", count: 30), expectedDisplay: false),
            .init(label: "math_greek_letters", text: "$\\alpha+\\beta$", cursor: 4, expectedSource: "\\alpha+\\beta", expectedDisplay: false),
            .init(label: "math_subscript", text: "$a_1$", cursor: 2, expectedSource: "a_1", expectedDisplay: false),
            .init(label: "math_superscript", text: "$a^2$", cursor: 2, expectedSource: "a^2", expectedDisplay: false),
            .init(label: "math_integral", text: "\\[\\int_0^1 f(x) dx\\]", cursor: 5, expectedSource: "\\int_0^1 f(x) dx", expectedDisplay: true),
            .init(label: "math_sum_display", text: "\\[\\sum_{i=1}^n i\\]", cursor: 4, expectedSource: "\\sum_{i=1}^n i", expectedDisplay: true),
            .init(label: "math_prose_no_math", text: "this is some text with no math", cursor: 10, expectedSource: nil, expectedDisplay: nil),
            .init(label: "math_consecutive_inline", text: "$a$$b$", cursor: 1, expectedSource: "a$$b", expectedDisplay: false)
        ]
        for sample in mathSamples {
            cases.append(("Extended/\(sample.label)", { (r: inout TestReport) in
                let result = MathHoverDetector.mathRange(in: sample.text, at: sample.cursor)
                if let src = sample.expectedSource {
                    TestAssert.assertEqual(result?.source, src, sample.label, report: &r)
                    if let display = sample.expectedDisplay {
                        TestAssert.assertEqual(result?.display, display, sample.label, report: &r)
                    }
                } else {
                    TestAssert.assertNil(result, sample.label, report: &r)
                }
                if r.failed == 0 { r.passed = 1 }
            }))
        }

        return cases
    }
}
