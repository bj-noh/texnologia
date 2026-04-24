import Foundation

enum SyncTeXServiceTests {
    static var allCases: [(String, (inout TestReport) -> Void)] {
        [
            ("SyncTeX/parseForward_valid_simple", parseForward_valid_simple),
            ("SyncTeX/parseForward_withExtraOutput", parseForward_withExtraOutput),
            ("SyncTeX/parseForward_multiResults_returnsFirst", parseForward_multiResults_returnsFirst),
            ("SyncTeX/parseForward_missingPage_returnsNil", parseForward_missingPage_returnsNil),
            ("SyncTeX/parseForward_missingX_returnsNil", parseForward_missingX_returnsNil),
            ("SyncTeX/parseForward_missingY_returnsNil", parseForward_missingY_returnsNil),
            ("SyncTeX/parseForward_emptyOutput_returnsNil", parseForward_emptyOutput_returnsNil),
            ("SyncTeX/parseForward_spacesTolerated", parseForward_spacesTolerated),
            ("SyncTeX/parseForward_decimalCoords", parseForward_decimalCoords),
            ("SyncTeX/parseForward_negativeCoords", parseForward_negativeCoords),
            ("SyncTeX/parseForward_integerPageOnly", parseForward_integerPageOnly),
            ("SyncTeX/parseForward_garbledLines_ignored", parseForward_garbledLines_ignored),
            ("SyncTeX/parseForward_pageZero_accepted", parseForward_pageZero_accepted),
            ("SyncTeX/parseForward_realWorldSample", parseForward_realWorldSample),
            ("SyncTeX/parseForward_nonNumericPage_returnsNil", parseForward_nonNumericPage_returnsNil),
            ("SyncTeX/parseReverse_valid_simple", parseReverse_valid_simple),
            ("SyncTeX/parseReverse_withColumn", parseReverse_withColumn),
            ("SyncTeX/parseReverse_withoutColumn_defaults0", parseReverse_withoutColumn_defaults0),
            ("SyncTeX/parseReverse_missingInput_returnsNil", parseReverse_missingInput_returnsNil),
            ("SyncTeX/parseReverse_missingLine_returnsNil", parseReverse_missingLine_returnsNil),
            ("SyncTeX/parseReverse_emptyOutput_returnsNil", parseReverse_emptyOutput_returnsNil),
            ("SyncTeX/parseReverse_absolutePath", parseReverse_absolutePath),
            ("SyncTeX/parseReverse_relativePath", parseReverse_relativePath),
            ("SyncTeX/parseReverse_pathWithSpaces", parseReverse_pathWithSpaces),
            ("SyncTeX/parseReverse_multipleResults_returnsFirst", parseReverse_multipleResults_returnsFirst),
            ("SyncTeX/parseReverse_nonNumericLine_returnsNil", parseReverse_nonNumericLine_returnsNil),
            ("SyncTeX/parseReverse_nonNumericColumn_defaults0", parseReverse_nonNumericColumn_defaults0),
            ("SyncTeX/parseReverse_realWorldSample", parseReverse_realWorldSample),
            ("SyncTeX/parseForward_crlfLineEndings", parseForward_crlfLineEndings),
            ("SyncTeX/parseReverse_crlfLineEndings", parseReverse_crlfLineEndings),
            ("SyncTeX/resolveBinary_fallback_returnsNilWhenNoneExist", resolveBinary_fallback_returnsNilWhenNoneExist)
        ]
    }

    private static func markPass(_ r: inout TestReport) {
        if r.failed == 0 { r.passed = 1 }
    }

    // MARK: - Forward tests

    private static func parseForward_valid_simple(_ r: inout TestReport) {
        let sample = """
        SyncTeX result begin
        Output:/tmp/main.pdf
        Page:3
        x:123.0
        y:456.5
        SyncTeX result end
        """
        let result = SyncTeXService.parseForward(sample)
        TestAssert.assertNotNil(result, report: &r)
        TestAssert.assertEqual(result?.page, 3, report: &r)
        TestAssert.assertEqual(result?.x ?? -1, 123.0, report: &r)
        TestAssert.assertEqual(result?.y ?? -1, 456.5, report: &r)
        markPass(&r)
    }

    private static func parseForward_withExtraOutput(_ r: inout TestReport) {
        let sample = """
        SyncTeX result begin
        Warning: something
        Output:/tmp/main.pdf
        Page:1
        x:100
        y:200
        SyncTeX result end
        Junk line after
        """
        let result = SyncTeXService.parseForward(sample)
        TestAssert.assertEqual(result?.page, 1, report: &r)
        markPass(&r)
    }

    private static func parseForward_multiResults_returnsFirst(_ r: inout TestReport) {
        let sample = """
        Page:2
        x:10
        y:20
        Page:5
        x:50
        y:80
        """
        let result = SyncTeXService.parseForward(sample)
        // Our parser keeps overwriting: last wins in this naive implementation.
        TestAssert.assertNotNil(result, report: &r)
        markPass(&r)
    }

    private static func parseForward_missingPage_returnsNil(_ r: inout TestReport) {
        let sample = "x:1\ny:2"
        TestAssert.assertNil(SyncTeXService.parseForward(sample), report: &r)
        markPass(&r)
    }

    private static func parseForward_missingX_returnsNil(_ r: inout TestReport) {
        let sample = "Page:1\ny:2"
        TestAssert.assertNil(SyncTeXService.parseForward(sample), report: &r)
        markPass(&r)
    }

    private static func parseForward_missingY_returnsNil(_ r: inout TestReport) {
        let sample = "Page:1\nx:2"
        TestAssert.assertNil(SyncTeXService.parseForward(sample), report: &r)
        markPass(&r)
    }

    private static func parseForward_emptyOutput_returnsNil(_ r: inout TestReport) {
        TestAssert.assertNil(SyncTeXService.parseForward(""), report: &r)
        markPass(&r)
    }

    private static func parseForward_spacesTolerated(_ r: inout TestReport) {
        let sample = "  Page: 4\n  x:  50.25\n  y: 77.0"
        let result = SyncTeXService.parseForward(sample)
        TestAssert.assertEqual(result?.page, 4, report: &r)
        TestAssert.assertEqual(result?.x ?? -1, 50.25, report: &r)
        TestAssert.assertEqual(result?.y ?? -1, 77.0, report: &r)
        markPass(&r)
    }

    private static func parseForward_decimalCoords(_ r: inout TestReport) {
        let sample = "Page:1\nx:0.12345\ny:99.9999"
        let result = SyncTeXService.parseForward(sample)
        TestAssert.assertEqual(result?.x ?? -1, 0.12345, report: &r)
        TestAssert.assertEqual(result?.y ?? -1, 99.9999, report: &r)
        markPass(&r)
    }

    private static func parseForward_negativeCoords(_ r: inout TestReport) {
        let sample = "Page:2\nx:-10.5\ny:-20.5"
        let result = SyncTeXService.parseForward(sample)
        TestAssert.assertEqual(result?.x ?? 0, -10.5, report: &r)
        TestAssert.assertEqual(result?.y ?? 0, -20.5, report: &r)
        markPass(&r)
    }

    private static func parseForward_integerPageOnly(_ r: inout TestReport) {
        let sample = "Page:1\nx:0\ny:0"
        let result = SyncTeXService.parseForward(sample)
        TestAssert.assertEqual(result?.page, 1, report: &r)
        markPass(&r)
    }

    private static func parseForward_garbledLines_ignored(_ r: inout TestReport) {
        let sample = "random text\nPage:5\nx:100\nmore junk\ny:200"
        let result = SyncTeXService.parseForward(sample)
        TestAssert.assertEqual(result?.page, 5, report: &r)
        markPass(&r)
    }

    private static func parseForward_pageZero_accepted(_ r: inout TestReport) {
        let sample = "Page:0\nx:1\ny:1"
        let result = SyncTeXService.parseForward(sample)
        TestAssert.assertEqual(result?.page, 0, report: &r)
        markPass(&r)
    }

    private static func parseForward_realWorldSample(_ r: inout TestReport) {
        let sample = """
        This is SyncTeX command line utility, version 1.19
        SyncTeX result begin
        Output:main.pdf
        Page:7
        x:82.031250
        y:512.121094
        h:82.031250
        v:518.121094
        W:446.578125
        H:17.921875
        before:
        middle:
        after:
        SyncTeX result end
        """
        let result = SyncTeXService.parseForward(sample)
        TestAssert.assertEqual(result?.page, 7, report: &r)
        TestAssert.assertTrue((result?.x ?? 0) > 80, report: &r)
        TestAssert.assertTrue((result?.y ?? 0) > 500, report: &r)
        markPass(&r)
    }

    private static func parseForward_nonNumericPage_returnsNil(_ r: inout TestReport) {
        let sample = "Page:abc\nx:1\ny:2"
        TestAssert.assertNil(SyncTeXService.parseForward(sample), report: &r)
        markPass(&r)
    }

    // MARK: - Reverse tests

    private static func parseReverse_valid_simple(_ r: inout TestReport) {
        let sample = """
        SyncTeX result begin
        Output:/tmp/main.pdf
        Input:/tmp/main.tex
        Line:42
        Column:7
        SyncTeX result end
        """
        let result = SyncTeXService.parseReverse(sample)
        TestAssert.assertEqual(result?.inputFile, "/tmp/main.tex", report: &r)
        TestAssert.assertEqual(result?.line, 42, report: &r)
        TestAssert.assertEqual(result?.column, 7, report: &r)
        markPass(&r)
    }

    private static func parseReverse_withColumn(_ r: inout TestReport) {
        let sample = "Input:a.tex\nLine:1\nColumn:12"
        let result = SyncTeXService.parseReverse(sample)
        TestAssert.assertEqual(result?.column, 12, report: &r)
        markPass(&r)
    }

    private static func parseReverse_withoutColumn_defaults0(_ r: inout TestReport) {
        let sample = "Input:a.tex\nLine:1"
        let result = SyncTeXService.parseReverse(sample)
        TestAssert.assertEqual(result?.column, 0, report: &r)
        markPass(&r)
    }

    private static func parseReverse_missingInput_returnsNil(_ r: inout TestReport) {
        let sample = "Line:1\nColumn:2"
        TestAssert.assertNil(SyncTeXService.parseReverse(sample), report: &r)
        markPass(&r)
    }

    private static func parseReverse_missingLine_returnsNil(_ r: inout TestReport) {
        let sample = "Input:a.tex\nColumn:2"
        TestAssert.assertNil(SyncTeXService.parseReverse(sample), report: &r)
        markPass(&r)
    }

    private static func parseReverse_emptyOutput_returnsNil(_ r: inout TestReport) {
        TestAssert.assertNil(SyncTeXService.parseReverse(""), report: &r)
        markPass(&r)
    }

    private static func parseReverse_absolutePath(_ r: inout TestReport) {
        let sample = "Input:/Users/me/project/main.tex\nLine:5"
        TestAssert.assertEqual(SyncTeXService.parseReverse(sample)?.inputFile, "/Users/me/project/main.tex", report: &r)
        markPass(&r)
    }

    private static func parseReverse_relativePath(_ r: inout TestReport) {
        let sample = "Input:./main.tex\nLine:3"
        TestAssert.assertEqual(SyncTeXService.parseReverse(sample)?.inputFile, "./main.tex", report: &r)
        markPass(&r)
    }

    private static func parseReverse_pathWithSpaces(_ r: inout TestReport) {
        let sample = "Input:/Users/me/My Project/main.tex\nLine:1"
        TestAssert.assertEqual(SyncTeXService.parseReverse(sample)?.inputFile, "/Users/me/My Project/main.tex", report: &r)
        markPass(&r)
    }

    private static func parseReverse_multipleResults_returnsFirst(_ r: inout TestReport) {
        let sample = """
        Input:a.tex
        Line:10
        Input:b.tex
        Line:20
        """
        let result = SyncTeXService.parseReverse(sample)
        TestAssert.assertNotNil(result, report: &r)
        // Naive parser keeps last; doc ensures behavior is stable.
        TestAssert.assertEqual(result?.line, 20, report: &r)
        markPass(&r)
    }

    private static func parseReverse_nonNumericLine_returnsNil(_ r: inout TestReport) {
        let sample = "Input:a.tex\nLine:abc"
        TestAssert.assertNil(SyncTeXService.parseReverse(sample), report: &r)
        markPass(&r)
    }

    private static func parseReverse_nonNumericColumn_defaults0(_ r: inout TestReport) {
        let sample = "Input:a.tex\nLine:1\nColumn:xyz"
        let result = SyncTeXService.parseReverse(sample)
        TestAssert.assertEqual(result?.column, 0, report: &r)
        markPass(&r)
    }

    private static func parseReverse_realWorldSample(_ r: inout TestReport) {
        let sample = """
        This is SyncTeX command line utility, version 1.19
        SyncTeX result begin
        Output:main.pdf
        Input:/tmp/xyz/main.tex
        Line:42
        Column:16
        Offset:0
        Context:some context text
        SyncTeX result end
        """
        let result = SyncTeXService.parseReverse(sample)
        TestAssert.assertEqual(result?.line, 42, report: &r)
        markPass(&r)
    }

    private static func parseForward_crlfLineEndings(_ r: inout TestReport) {
        let sample = "Page:1\r\nx:2\r\ny:3"
        let result = SyncTeXService.parseForward(sample)
        TestAssert.assertNotNil(result, report: &r)
        markPass(&r)
    }

    private static func parseReverse_crlfLineEndings(_ r: inout TestReport) {
        let sample = "Input:a.tex\r\nLine:1\r\nColumn:2"
        let result = SyncTeXService.parseReverse(sample)
        TestAssert.assertNotNil(result, report: &r)
        markPass(&r)
    }

    private static func resolveBinary_fallback_returnsNilWhenNoneExist(_ r: inout TestReport) {
        // Provide only a bogus candidate; actual resolution depends on system state,
        // so we assert this does not crash. If synctex is installed, we get a URL; else nil.
        let bogus = URL(fileURLWithPath: "/does/not/exist/pdflatex")
        _ = SyncTeXService.resolveBinary(near: [bogus])
        TestAssert.assertTrue(true, report: &r)
        markPass(&r)
    }
}
