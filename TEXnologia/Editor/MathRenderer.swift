import AppKit
import Foundation
import PDFKit

actor MathRenderer {
    static let shared = MathRenderer()

    private var cache: [String: NSImage] = [:]
    private var inFlight: [String: Task<NSImage?, Never>] = [:]

    func render(latex: String, display: Bool, extraPreamble: String = "") async -> NSImage? {
        let key = cacheKey(latex: latex, display: display, preamble: extraPreamble)
        if let cached = cache[key] { return cached }
        if let task = inFlight[key] { return await task.value }

        let task = Task<NSImage?, Never> { [latex, display, extraPreamble] in
            await Self.renderToImage(latex: latex, display: display, extraPreamble: extraPreamble)
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        if let result { cache[key] = result }
        return result
    }

    private func cacheKey(latex: String, display: Bool, preamble: String) -> String {
        "\(display ? "D" : "I")::\(preamble.hashValue)::\(latex)"
    }

    private static func renderToImage(latex: String, display: Bool, extraPreamble: String) async -> NSImage? {
        guard let pdflatex = findExecutable("pdflatex") else { return nil }
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("texnologia-math-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        let source = composeSource(latex: latex, display: display, extraPreamble: extraPreamble)
        let texURL = tempDir.appendingPathComponent("math.tex")
        do {
            try source.write(to: texURL, atomically: true, encoding: .utf8)
        } catch {
            return nil
        }

        let exit = await runProcess(
            executable: pdflatex,
            arguments: [
                "-interaction=nonstopmode",
                "-halt-on-error",
                "-output-directory=\(tempDir.path)",
                texURL.path
            ]
        )
        guard exit == 0 else { return nil }

        let pdfURL = tempDir.appendingPathComponent("math.pdf")
        guard FileManager.default.fileExists(atPath: pdfURL.path) else { return nil }
        guard let document = PDFDocument(url: pdfURL),
              let page = document.page(at: 0) else { return nil }

        let pageBounds = page.bounds(for: .mediaBox)
        let scale: CGFloat = 3.0
        let size = NSSize(width: pageBounds.width * scale, height: pageBounds.height * scale)
        let image = NSImage(size: size)
        image.lockFocus()
        if let context = NSGraphicsContext.current?.cgContext {
            context.saveGState()
            context.setFillColor(NSColor.white.cgColor)
            context.fill(CGRect(origin: .zero, size: size))
            context.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: context)
            context.restoreGState()
        }
        image.unlockFocus()
        return image
    }

    private static func composeSource(latex: String, display: Bool, extraPreamble: String) -> String {
        let wrapped = display ? "\\[\n\(latex)\n\\]" : "$\(latex)$"
        return """
        \\documentclass[preview,border=2pt]{standalone}
        \\usepackage{amsmath}
        \\usepackage{amssymb}
        \\usepackage{amsfonts}
        \\usepackage{mathtools}
        \(extraPreamble)
        \\begin{document}
        \(wrapped)
        \\end{document}

        """
    }

    private static func findExecutable(_ name: String) -> URL? {
        let candidates = [
            "/Library/TeX/texbin/\(name)",
            "/usr/local/bin/\(name)",
            "/opt/homebrew/bin/\(name)",
            "/usr/local/texlive/2024basic/bin/universal-darwin/\(name)",
            "/usr/local/texlive/2024basic/bin/aarch64-darwin/\(name)",
            "/usr/local/texlive/2024basic/bin/x86_64-darwin/\(name)"
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    private static func runProcess(executable: URL, arguments: [String]) async -> Int32 {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = executable
                process.arguments = arguments
                process.standardOutput = Pipe()
                process.standardError = Pipe()
                do {
                    try process.run()
                    process.waitUntilExit()
                    continuation.resume(returning: process.terminationStatus)
                } catch {
                    continuation.resume(returning: -1)
                }
            }
        }
    }
}
