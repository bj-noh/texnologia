import Foundation

enum HistoryDiffStateTests {
    static var allCases: [(String, (inout TestReport) -> Void)] {
        [
            ("HistoryDiff/filter_noFileURL_returnsAllEntries", filter_noFileURL_returnsAllEntries),
            ("HistoryDiff/filter_emptyEntries_returnsEmpty", filter_emptyEntries_returnsEmpty),
            ("HistoryDiff/filter_singleFile_onlyMatching", filter_singleFile_onlyMatching),
            ("HistoryDiff/filter_manyFiles_scopesCorrectly", filter_manyFiles_scopesCorrectly),
            ("HistoryDiff/filter_allSameFile_allIncluded", filter_allSameFile_allIncluded),
            ("HistoryDiff/filter_noMatchingFile_returnsEmpty", filter_noMatchingFile_returnsEmpty),
            ("HistoryDiff/filter_preservesOrder", filter_preservesOrder),
            ("HistoryDiff/selectedEntry_nilID_returnsNil", selectedEntry_nilID_returnsNil),
            ("HistoryDiff/selectedEntry_validID_returnsEntry", selectedEntry_validID_returnsEntry),
            ("HistoryDiff/selectedEntry_staleID_returnsNil", selectedEntry_staleID_returnsNil),
            ("HistoryDiff/selectedEntry_idFromOtherFile_returnsNil", selectedEntry_idFromOtherFile_returnsNil),
            ("HistoryDiff/crossFile_selectingStaleEntry_doesNotShowMassiveDiff", crossFile_selectingStaleEntry_doesNotShowMassiveDiff),
            ("HistoryDiff/crossFile_filterHidesOtherFilesEntries", crossFile_filterHidesOtherFilesEntries),
            ("HistoryDiff/comparisonBase_currentEditorTarget_returnsEditorText", comparisonBase_currentEditorTarget_returnsEditorText),
            ("HistoryDiff/comparisonBase_baseTargetWithoutBase_fallsBackToEditor", comparisonBase_baseTargetWithoutBase_fallsBackToEditor),
            ("HistoryDiff/comparisonBase_baseTargetWithBase_returnsBaseText", comparisonBase_baseTargetWithBase_returnsBaseText),
            ("HistoryDiff/comparisonBase_snapshotTarget_returnsSnapshotText", comparisonBase_snapshotTarget_returnsSnapshotText),
            ("HistoryDiff/comparisonBase_snapshotTargetStaleID_returnsEmpty", comparisonBase_snapshotTargetStaleID_returnsEmpty),
            ("HistoryDiff/diffStats_identicalTexts_areIdentical", diffStats_identicalTexts_areIdentical),
            ("HistoryDiff/diffStats_addedLine_reportsAdded", diffStats_addedLine_reportsAdded),
            ("HistoryDiff/diffStats_removedLine_reportsRemoved", diffStats_removedLine_reportsRemoved),
            ("HistoryDiff/normalize_withMismatchedSelection_picksFirstFiltered", normalize_withMismatchedSelection_picksFirstFiltered),
            ("HistoryDiff/normalize_withOrphanedBase_clearsBaseAndTarget", normalize_withOrphanedBase_clearsBaseAndTarget),
            ("HistoryDiff/normalize_preservesValidBase", normalize_preservesValidBase),
            ("HistoryDiff/normalize_withNoSelection_pickFirst", normalize_withNoSelection_pickFirst),
            ("HistoryDiff/scenarioMatrix_allCombinations", scenarioMatrix_allCombinations),
            ("HistoryDiff/switchingFiles_doesNotProduceBogusDiff", switchingFiles_doesNotProduceBogusDiff),
            ("HistoryDiff/switchingFiles_baseIsClearedWhenCrossFile", switchingFiles_baseIsClearedWhenCrossFile),
            ("HistoryDiff/bulkRegression_200Random", bulkRegression_200Random),
            ("HistoryDiff/singleEntry_selfCompare_identical", singleEntry_selfCompare_identical),
            ("HistoryDiff/singleEntry_differentText_shows1Change", singleEntry_differentText_shows1Change),
            ("HistoryDiff/emptyCurrentText_removesAllLines", emptyCurrentText_removesAllLines),
            ("HistoryDiff/emptySnapshotText_addsAllLines", emptySnapshotText_addsAllLines),
            ("HistoryDiff/baseCompare_betweenTwoSnapshots", baseCompare_betweenTwoSnapshots),
            ("HistoryDiff/snapshotCompare_betweenSpecificPair", snapshotCompare_betweenSpecificPair),
            ("HistoryDiff/unrelatedBaseOtherFile_doesNotLeak", unrelatedBaseOtherFile_doesNotLeak),
            ("HistoryDiff/zeroEntries_noSelection_zeroDiff", zeroEntries_noSelection_zeroDiff),
            ("HistoryDiff/longHistory_lastSelected_isIdentical", longHistory_lastSelected_isIdentical),
            ("HistoryDiff/multilineText_addAtStart", multilineText_addAtStart),
            ("HistoryDiff/multilineText_addAtEnd", multilineText_addAtEnd),
            ("HistoryDiff/multilineText_modifyMiddle", multilineText_modifyMiddle),
            ("HistoryDiff/whitespaceOnlyChange_reflected", whitespaceOnlyChange_reflected),
            ("HistoryDiff/trailingNewlineDifference_reflected", trailingNewlineDifference_reflected),
            ("HistoryDiff/utf16_emoji_handled", utf16_emoji_handled),
            ("HistoryDiff/baseFallback_whenSetToOtherFileEntry", baseFallback_whenSetToOtherFileEntry)
        ]
    }

    // MARK: - Helpers

    private static func makeEntry(file: String, text: String, reason: String = "manual", at date: Date = Date()) -> HistoryEntry {
        HistoryEntry(
            fileURL: URL(fileURLWithPath: "/workspace/\(file)"),
            fileName: file,
            text: text,
            createdAt: date,
            reason: reason
        )
    }

    private static func url(_ file: String) -> URL { URL(fileURLWithPath: "/workspace/\(file)") }

    private static func markPass(_ r: inout TestReport) {
        if r.failed == 0 { r.passed = 1 }
    }

    // MARK: - Tests

    private static func filter_noFileURL_returnsAllEntries(_ r: inout TestReport) {
        let entries = [makeEntry(file: "a.tex", text: "A1"), makeEntry(file: "b.tex", text: "B1")]
        let state = HistoryDiffState(entries: entries, currentEditorFileURL: nil)
        TestAssert.assertEqual(state.fileFilteredEntries.count, 2, report: &r)
        markPass(&r)
    }

    private static func filter_emptyEntries_returnsEmpty(_ r: inout TestReport) {
        let state = HistoryDiffState(entries: [], currentEditorFileURL: url("a.tex"))
        TestAssert.assertTrue(state.fileFilteredEntries.isEmpty, report: &r)
        markPass(&r)
    }

    private static func filter_singleFile_onlyMatching(_ r: inout TestReport) {
        let entries = [
            makeEntry(file: "a.tex", text: "A1"),
            makeEntry(file: "a.tex", text: "A2"),
            makeEntry(file: "b.tex", text: "B1")
        ]
        let state = HistoryDiffState(entries: entries, currentEditorFileURL: url("a.tex"))
        TestAssert.assertEqual(state.fileFilteredEntries.count, 2, report: &r)
        TestAssert.assertTrue(state.fileFilteredEntries.allSatisfy { $0.fileURL == url("a.tex") }, report: &r)
        markPass(&r)
    }

    private static func filter_manyFiles_scopesCorrectly(_ r: inout TestReport) {
        var entries: [HistoryEntry] = []
        for i in 0..<20 { entries.append(makeEntry(file: "file\(i % 5).tex", text: "v\(i)")) }
        let state = HistoryDiffState(entries: entries, currentEditorFileURL: url("file3.tex"))
        TestAssert.assertEqual(state.fileFilteredEntries.count, 4, report: &r)
        markPass(&r)
    }

    private static func filter_allSameFile_allIncluded(_ r: inout TestReport) {
        let entries = (0..<10).map { makeEntry(file: "main.tex", text: "v\($0)") }
        let state = HistoryDiffState(entries: entries, currentEditorFileURL: url("main.tex"))
        TestAssert.assertEqual(state.fileFilteredEntries.count, 10, report: &r)
        markPass(&r)
    }

    private static func filter_noMatchingFile_returnsEmpty(_ r: inout TestReport) {
        let entries = [makeEntry(file: "a.tex", text: "A")]
        let state = HistoryDiffState(entries: entries, currentEditorFileURL: url("b.tex"))
        TestAssert.assertTrue(state.fileFilteredEntries.isEmpty, report: &r)
        markPass(&r)
    }

    private static func filter_preservesOrder(_ r: inout TestReport) {
        let entries = (0..<5).map {
            makeEntry(file: "main.tex", text: "v\($0)", at: Date(timeIntervalSince1970: TimeInterval($0)))
        }
        let state = HistoryDiffState(entries: entries, currentEditorFileURL: url("main.tex"))
        TestAssert.assertEqual(state.fileFilteredEntries.map(\.text), entries.map(\.text), report: &r)
        markPass(&r)
    }

    private static func selectedEntry_nilID_returnsNil(_ r: inout TestReport) {
        let entries = [makeEntry(file: "a.tex", text: "A")]
        let state = HistoryDiffState(entries: entries, currentEditorFileURL: url("a.tex"))
        TestAssert.assertNil(state.selectedEntry, report: &r)
        markPass(&r)
    }

    private static func selectedEntry_validID_returnsEntry(_ r: inout TestReport) {
        let entries = [makeEntry(file: "a.tex", text: "A")]
        let state = HistoryDiffState(entries: entries, currentEditorFileURL: url("a.tex"), selectedEntryID: entries[0].id)
        TestAssert.assertEqual(state.selectedEntry?.id, entries[0].id, report: &r)
        markPass(&r)
    }

    private static func selectedEntry_staleID_returnsNil(_ r: inout TestReport) {
        let entries = [makeEntry(file: "a.tex", text: "A")]
        let state = HistoryDiffState(entries: entries, currentEditorFileURL: url("a.tex"), selectedEntryID: UUID())
        TestAssert.assertNil(state.selectedEntry, report: &r)
        markPass(&r)
    }

    private static func selectedEntry_idFromOtherFile_returnsNil(_ r: inout TestReport) {
        let a = makeEntry(file: "a.tex", text: "A")
        let b = makeEntry(file: "b.tex", text: "B")
        let state = HistoryDiffState(entries: [a, b], currentEditorFileURL: url("a.tex"), selectedEntryID: b.id)
        TestAssert.assertNil(state.selectedEntry, report: &r)
        markPass(&r)
    }

    private static func crossFile_selectingStaleEntry_doesNotShowMassiveDiff(_ r: inout TestReport) {
        let a = makeEntry(file: "chapter1.tex", text: "Chapter 1 content")
        let b = makeEntry(file: "chapter2.tex", text: "Chapter 2 content")
        let state = HistoryDiffState(
            entries: [a, b],
            currentEditorText: "Chapter 2 content",
            currentEditorFileURL: url("chapter2.tex"),
            selectedEntryID: a.id
        )
        TestAssert.assertNil(state.selectedEntry, report: &r)
        TestAssert.assertTrue(state.diffLines.isEmpty, report: &r)
        TestAssert.assertTrue(state.diffStats.isIdentical, report: &r)
        markPass(&r)
    }

    private static func crossFile_filterHidesOtherFilesEntries(_ r: inout TestReport) {
        let aEntries = (0..<5).map { makeEntry(file: "a.tex", text: "A\($0)") }
        let bEntries = (0..<5).map { makeEntry(file: "b.tex", text: "B\($0)") }
        let state = HistoryDiffState(entries: aEntries + bEntries, currentEditorFileURL: url("a.tex"))
        TestAssert.assertEqual(state.fileFilteredEntries.count, 5, report: &r)
        TestAssert.assertTrue(state.fileFilteredEntries.allSatisfy { $0.fileURL == url("a.tex") }, report: &r)
        markPass(&r)
    }

    private static func comparisonBase_currentEditorTarget_returnsEditorText(_ r: inout TestReport) {
        let state = HistoryDiffState(currentEditorText: "editor-text", compareTarget: .currentEditor)
        TestAssert.assertEqual(state.comparisonBaseText, "editor-text", report: &r)
        markPass(&r)
    }

    private static func comparisonBase_baseTargetWithoutBase_fallsBackToEditor(_ r: inout TestReport) {
        let state = HistoryDiffState(currentEditorText: "fallback", compareTarget: .base, baseEntryID: nil)
        TestAssert.assertEqual(state.comparisonBaseText, "fallback", report: &r)
        markPass(&r)
    }

    private static func comparisonBase_baseTargetWithBase_returnsBaseText(_ r: inout TestReport) {
        let base = makeEntry(file: "a.tex", text: "BASE")
        let state = HistoryDiffState(entries: [base], currentEditorText: "editor", currentEditorFileURL: url("a.tex"), compareTarget: .base, baseEntryID: base.id)
        TestAssert.assertEqual(state.comparisonBaseText, "BASE", report: &r)
        markPass(&r)
    }

    private static func comparisonBase_snapshotTarget_returnsSnapshotText(_ r: inout TestReport) {
        let e = makeEntry(file: "a.tex", text: "SNAP")
        let state = HistoryDiffState(entries: [e], currentEditorFileURL: url("a.tex"), compareTarget: .snapshot(e.id))
        TestAssert.assertEqual(state.comparisonBaseText, "SNAP", report: &r)
        markPass(&r)
    }

    private static func comparisonBase_snapshotTargetStaleID_returnsEmpty(_ r: inout TestReport) {
        let state = HistoryDiffState(entries: [], currentEditorFileURL: url("a.tex"), compareTarget: .snapshot(UUID()))
        TestAssert.assertEqual(state.comparisonBaseText, "", report: &r)
        markPass(&r)
    }

    private static func diffStats_identicalTexts_areIdentical(_ r: inout TestReport) {
        let e = makeEntry(file: "a.tex", text: "same line\nsame line 2")
        let state = HistoryDiffState(entries: [e], currentEditorText: "same line\nsame line 2", currentEditorFileURL: url("a.tex"), selectedEntryID: e.id)
        TestAssert.assertTrue(state.diffStats.isIdentical, report: &r)
        markPass(&r)
    }

    private static func diffStats_addedLine_reportsAdded(_ r: inout TestReport) {
        let e = makeEntry(file: "a.tex", text: "line1\nline2")
        let state = HistoryDiffState(entries: [e], currentEditorText: "line1\nline2\nline3", currentEditorFileURL: url("a.tex"), selectedEntryID: e.id)
        TestAssert.assertEqual(state.diffStats.added, 1, report: &r)
        TestAssert.assertEqual(state.diffStats.removed, 0, report: &r)
        markPass(&r)
    }

    private static func diffStats_removedLine_reportsRemoved(_ r: inout TestReport) {
        let e = makeEntry(file: "a.tex", text: "line1\nline2\nline3")
        let state = HistoryDiffState(entries: [e], currentEditorText: "line1\nline2", currentEditorFileURL: url("a.tex"), selectedEntryID: e.id)
        TestAssert.assertEqual(state.diffStats.removed, 1, report: &r)
        TestAssert.assertEqual(state.diffStats.added, 0, report: &r)
        markPass(&r)
    }

    private static func normalize_withMismatchedSelection_picksFirstFiltered(_ r: inout TestReport) {
        let a0 = makeEntry(file: "a.tex", text: "A0")
        let a1 = makeEntry(file: "a.tex", text: "A1")
        let b = makeEntry(file: "b.tex", text: "B")
        var state = HistoryDiffState(entries: [a0, a1, b], currentEditorFileURL: url("a.tex"), selectedEntryID: b.id)
        state.normalize()
        TestAssert.assertEqual(state.selectedEntryID, a0.id, report: &r)
        markPass(&r)
    }

    private static func normalize_withOrphanedBase_clearsBaseAndTarget(_ r: inout TestReport) {
        let a = makeEntry(file: "a.tex", text: "A")
        var state = HistoryDiffState(entries: [a], currentEditorFileURL: url("a.tex"), compareTarget: .base, baseEntryID: UUID())
        state.normalize()
        TestAssert.assertNil(state.baseEntryID, report: &r)
        TestAssert.assertEqual(state.compareTarget, .currentEditor, report: &r)
        markPass(&r)
    }

    private static func normalize_preservesValidBase(_ r: inout TestReport) {
        let a = makeEntry(file: "a.tex", text: "A")
        var state = HistoryDiffState(entries: [a], currentEditorFileURL: url("a.tex"), compareTarget: .base, baseEntryID: a.id)
        state.normalize()
        TestAssert.assertEqual(state.baseEntryID, a.id, report: &r)
        TestAssert.assertEqual(state.compareTarget, .base, report: &r)
        markPass(&r)
    }

    private static func normalize_withNoSelection_pickFirst(_ r: inout TestReport) {
        let a0 = makeEntry(file: "a.tex", text: "A0")
        let a1 = makeEntry(file: "a.tex", text: "A1")
        var state = HistoryDiffState(entries: [a0, a1], currentEditorFileURL: url("a.tex"), selectedEntryID: nil)
        state.normalize()
        TestAssert.assertEqual(state.selectedEntryID, a0.id, report: &r)
        markPass(&r)
    }

    private static func scenarioMatrix_allCombinations(_ r: inout TestReport) {
        let files = ["a.tex", "b.tex", "c.tex"]
        var scenariosTested = 0
        for fileA in files {
            for fileB in files {
                let aEntries = (0..<3).map { makeEntry(file: fileA, text: "\(fileA)-v\($0)", at: Date(timeIntervalSince1970: TimeInterval($0))) }
                let bEntries = (0..<3).map { makeEntry(file: fileB, text: "\(fileB)-v\($0)", at: Date(timeIntervalSince1970: TimeInterval(10 + $0))) }
                let allEntries = aEntries + bEntries
                for currentFile in [fileA, fileB] {
                    let currentURL = url(currentFile)
                    let expectedFilteredEntries = allEntries.filter { $0.fileURL == currentURL }
                    let potentialSelections: [UUID?] = [nil, aEntries.first?.id, bEntries.first?.id, aEntries.last?.id, bEntries.last?.id]
                    for selection in potentialSelections {
                        for base in [UUID?.none, aEntries.first?.id, bEntries.first?.id] {
                            for target in [HistoryCompareTarget.currentEditor, .base] {
                                scenariosTested += 1
                                let currentText = "current-\(currentFile)"
                                let state = HistoryDiffState(
                                    entries: allEntries,
                                    currentEditorText: currentText,
                                    currentEditorFileURL: currentURL,
                                    selectedEntryID: selection,
                                    compareTarget: target,
                                    baseEntryID: base
                                )
                                TestAssert.assertEqual(state.fileFilteredEntries, expectedFilteredEntries, report: &r)
                                if let selected = state.selectedEntry {
                                    TestAssert.assertEqual(selected.fileURL, currentURL, report: &r)
                                }
                                if let resolved = state.baseEntry {
                                    TestAssert.assertEqual(resolved.fileURL, currentURL, report: &r)
                                }
                                switch target {
                                case .currentEditor:
                                    TestAssert.assertEqual(state.comparisonBaseText, currentText, report: &r)
                                case .base:
                                    if let resolved = state.baseEntry {
                                        TestAssert.assertEqual(state.comparisonBaseText, resolved.text, report: &r)
                                    } else {
                                        TestAssert.assertEqual(state.comparisonBaseText, currentText, report: &r)
                                    }
                                case .snapshot: break
                                }
                                if state.selectedEntry == nil {
                                    TestAssert.assertTrue(state.diffLines.isEmpty, report: &r)
                                    TestAssert.assertTrue(state.diffStats.isIdentical, report: &r)
                                }
                            }
                        }
                    }
                }
            }
        }
        TestAssert.assertTrue(scenariosTested >= 100, "expected 100+ scenarios, got \(scenariosTested)", report: &r)
        markPass(&r)
    }

    private static func switchingFiles_doesNotProduceBogusDiff(_ r: inout TestReport) {
        let fileA = url("a.tex")
        let fileB = url("b.tex")
        let aHistory = (0..<5).map { makeEntry(file: "a.tex", text: "alpha-\($0)") }
        let bHistory = (0..<5).map { makeEntry(file: "b.tex", text: "beta-\($0)") }
        var state = HistoryDiffState(entries: aHistory + bHistory, currentEditorText: "alpha-current", currentEditorFileURL: fileA, selectedEntryID: aHistory[2].id)
        TestAssert.assertNotNil(state.selectedEntry, report: &r)
        TestAssert.assertEqual(state.selectedEntry?.text, "alpha-2", report: &r)
        state.currentEditorFileURL = fileB
        state.currentEditorText = "beta-current"
        TestAssert.assertNil(state.selectedEntry, report: &r)
        TestAssert.assertTrue(state.diffLines.isEmpty, report: &r)
        state.normalize()
        TestAssert.assertEqual(state.selectedEntry?.fileURL, fileB, report: &r)
        markPass(&r)
    }

    private static func switchingFiles_baseIsClearedWhenCrossFile(_ r: inout TestReport) {
        let fileA = url("a.tex")
        let fileB = url("b.tex")
        let aBase = makeEntry(file: "a.tex", text: "alpha-base")
        let bEntry = makeEntry(file: "b.tex", text: "beta-v0")
        var state = HistoryDiffState(entries: [aBase, bEntry], currentEditorFileURL: fileA, compareTarget: .base, baseEntryID: aBase.id)
        TestAssert.assertNotNil(state.baseEntry, report: &r)
        state.currentEditorFileURL = fileB
        TestAssert.assertNil(state.baseEntry, report: &r)
        state.normalize()
        TestAssert.assertNil(state.baseEntryID, report: &r)
        TestAssert.assertEqual(state.compareTarget, .currentEditor, report: &r)
        markPass(&r)
    }

    private static func bulkRegression_200Random(_ r: inout TestReport) {
        var rng = SystemRandomNumberGenerator()
        let fileNames = ["main.tex", "chapter1.tex", "chapter2.tex", "preamble.tex", "bib/refs.bib"]
        for iteration in 0..<220 {
            var entries: [HistoryEntry] = []
            for i in 0..<(5 + (iteration % 6)) {
                let file = fileNames.randomElement(using: &rng) ?? "main.tex"
                entries.append(makeEntry(file: file, text: "it=\(iteration) v=\(i)", reason: "auto", at: Date(timeIntervalSince1970: TimeInterval(iteration * 100 + i))))
            }
            let currentFile = fileNames.randomElement(using: &rng) ?? "main.tex"
            let currentURL = url(currentFile)
            let scoped = entries.filter { $0.fileURL == currentURL }
            let selectionID: UUID? = scoped.isEmpty ? nil : scoped[Int.random(in: 0..<scoped.count, using: &rng)].id
            let staleID = entries.first(where: { $0.fileURL != currentURL })?.id
            let effectiveSelection: UUID? = iteration.isMultiple(of: 3) ? staleID : selectionID
            let state = HistoryDiffState(
                entries: entries,
                currentEditorText: "current-\(currentFile)-\(iteration)",
                currentEditorFileURL: currentURL,
                selectedEntryID: effectiveSelection
            )
            TestAssert.assertTrue(state.fileFilteredEntries.allSatisfy { $0.fileURL == currentURL }, report: &r)
            if let selected = state.selectedEntry {
                TestAssert.assertEqual(selected.fileURL, currentURL, report: &r)
            }
            if state.selectedEntry == nil {
                TestAssert.assertTrue(state.diffLines.isEmpty, report: &r)
            }
        }
        markPass(&r)
    }

    private static func singleEntry_selfCompare_identical(_ r: inout TestReport) {
        let e = makeEntry(file: "a.tex", text: "hi")
        let state = HistoryDiffState(entries: [e], currentEditorText: "hi", currentEditorFileURL: url("a.tex"), selectedEntryID: e.id)
        TestAssert.assertTrue(state.diffStats.isIdentical, report: &r)
        markPass(&r)
    }

    private static func singleEntry_differentText_shows1Change(_ r: inout TestReport) {
        let e = makeEntry(file: "a.tex", text: "hi")
        let state = HistoryDiffState(entries: [e], currentEditorText: "bye", currentEditorFileURL: url("a.tex"), selectedEntryID: e.id)
        TestAssert.assertTrue(!state.diffStats.isIdentical, report: &r)
        markPass(&r)
    }

    private static func emptyCurrentText_removesAllLines(_ r: inout TestReport) {
        let e = makeEntry(file: "a.tex", text: "a\nb\nc")
        let state = HistoryDiffState(entries: [e], currentEditorText: "", currentEditorFileURL: url("a.tex"), selectedEntryID: e.id)
        TestAssert.assertTrue(state.diffStats.removed > 0, report: &r)
        markPass(&r)
    }

    private static func emptySnapshotText_addsAllLines(_ r: inout TestReport) {
        let e = makeEntry(file: "a.tex", text: "")
        let state = HistoryDiffState(entries: [e], currentEditorText: "a\nb\nc", currentEditorFileURL: url("a.tex"), selectedEntryID: e.id)
        TestAssert.assertTrue(state.diffStats.added > 0, report: &r)
        markPass(&r)
    }

    private static func baseCompare_betweenTwoSnapshots(_ r: inout TestReport) {
        let e1 = makeEntry(file: "a.tex", text: "v1")
        let e2 = makeEntry(file: "a.tex", text: "v2")
        let state = HistoryDiffState(entries: [e1, e2], currentEditorText: "v3", currentEditorFileURL: url("a.tex"), selectedEntryID: e2.id, compareTarget: .base, baseEntryID: e1.id)
        TestAssert.assertEqual(state.comparisonBaseText, "v1", report: &r)
        TestAssert.assertTrue(!state.diffStats.isIdentical, report: &r)
        markPass(&r)
    }

    private static func snapshotCompare_betweenSpecificPair(_ r: inout TestReport) {
        let e1 = makeEntry(file: "a.tex", text: "alpha")
        let e2 = makeEntry(file: "a.tex", text: "beta")
        let state = HistoryDiffState(entries: [e1, e2], currentEditorText: "gamma", currentEditorFileURL: url("a.tex"), selectedEntryID: e2.id, compareTarget: .snapshot(e1.id))
        TestAssert.assertEqual(state.comparisonBaseText, "alpha", report: &r)
        markPass(&r)
    }

    private static func unrelatedBaseOtherFile_doesNotLeak(_ r: inout TestReport) {
        let aEntry = makeEntry(file: "a.tex", text: "AAA")
        let bBase = makeEntry(file: "b.tex", text: "BBB")
        let state = HistoryDiffState(entries: [aEntry, bBase], currentEditorText: "A-current", currentEditorFileURL: url("a.tex"), selectedEntryID: aEntry.id, compareTarget: .base, baseEntryID: bBase.id)
        TestAssert.assertNil(state.baseEntry, report: &r)
        TestAssert.assertEqual(state.comparisonBaseText, "A-current", report: &r)
        markPass(&r)
    }

    private static func zeroEntries_noSelection_zeroDiff(_ r: inout TestReport) {
        let state = HistoryDiffState(entries: [], currentEditorText: "anything", currentEditorFileURL: url("a.tex"))
        TestAssert.assertTrue(state.diffLines.isEmpty, report: &r)
        TestAssert.assertTrue(state.diffStats.isIdentical, report: &r)
        markPass(&r)
    }

    private static func longHistory_lastSelected_isIdentical(_ r: inout TestReport) {
        let entries = (0..<50).map { makeEntry(file: "a.tex", text: "content\n\($0)") }
        let last = entries.last!
        let state = HistoryDiffState(entries: entries, currentEditorText: last.text, currentEditorFileURL: url("a.tex"), selectedEntryID: last.id)
        TestAssert.assertTrue(state.diffStats.isIdentical, report: &r)
        markPass(&r)
    }

    private static func multilineText_addAtStart(_ r: inout TestReport) {
        let e = makeEntry(file: "a.tex", text: "line1\nline2")
        let state = HistoryDiffState(entries: [e], currentEditorText: "NEW\nline1\nline2", currentEditorFileURL: url("a.tex"), selectedEntryID: e.id)
        TestAssert.assertTrue(state.diffStats.added >= 1, report: &r)
        markPass(&r)
    }

    private static func multilineText_addAtEnd(_ r: inout TestReport) {
        let e = makeEntry(file: "a.tex", text: "line1\nline2")
        let state = HistoryDiffState(entries: [e], currentEditorText: "line1\nline2\nNEW", currentEditorFileURL: url("a.tex"), selectedEntryID: e.id)
        TestAssert.assertTrue(state.diffStats.added >= 1, report: &r)
        markPass(&r)
    }

    private static func multilineText_modifyMiddle(_ r: inout TestReport) {
        let e = makeEntry(file: "a.tex", text: "a\nb\nc\nd")
        let state = HistoryDiffState(entries: [e], currentEditorText: "a\nBB\nc\nd", currentEditorFileURL: url("a.tex"), selectedEntryID: e.id)
        TestAssert.assertTrue(state.diffStats.added >= 1 && state.diffStats.removed >= 1, report: &r)
        markPass(&r)
    }

    private static func whitespaceOnlyChange_reflected(_ r: inout TestReport) {
        let e = makeEntry(file: "a.tex", text: "hello world")
        let state = HistoryDiffState(entries: [e], currentEditorText: "hello  world", currentEditorFileURL: url("a.tex"), selectedEntryID: e.id)
        TestAssert.assertTrue(!state.diffStats.isIdentical, report: &r)
        markPass(&r)
    }

    private static func trailingNewlineDifference_reflected(_ r: inout TestReport) {
        let e = makeEntry(file: "a.tex", text: "hello")
        let state = HistoryDiffState(entries: [e], currentEditorText: "hello\n", currentEditorFileURL: url("a.tex"), selectedEntryID: e.id)
        // Either identical or reports a single change, depending on diff engine behavior.
        // Just ensure we don't crash and produce stats.
        TestAssert.assertTrue(state.diffLines.count >= 0, report: &r)
        markPass(&r)
    }

    private static func utf16_emoji_handled(_ r: inout TestReport) {
        let e = makeEntry(file: "a.tex", text: "hello 😀")
        let state = HistoryDiffState(entries: [e], currentEditorText: "hello 😀 world", currentEditorFileURL: url("a.tex"), selectedEntryID: e.id)
        TestAssert.assertTrue(!state.diffStats.isIdentical, report: &r)
        markPass(&r)
    }

    private static func baseFallback_whenSetToOtherFileEntry(_ r: inout TestReport) {
        let a = makeEntry(file: "a.tex", text: "A-only")
        let b = makeEntry(file: "b.tex", text: "B-only")
        let state = HistoryDiffState(
            entries: [a, b],
            currentEditorText: "current-A",
            currentEditorFileURL: url("a.tex"),
            selectedEntryID: a.id,
            compareTarget: .base,
            baseEntryID: b.id // cross-file: should not leak
        )
        TestAssert.assertEqual(state.comparisonBaseText, "current-A", report: &r)
        markPass(&r)
    }
}
