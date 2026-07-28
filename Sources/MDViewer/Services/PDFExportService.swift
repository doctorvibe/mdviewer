import AppKit
import SwiftUI
import MarkdownUI
import WebKit

// Helper class to manage PDF generation with WKWebView
private class PDFGenerator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    let url: URL
    var webView: WKWebView?
    var window: NSWindow?
    /// Set when the page renders Mermaid diagrams, which finish asynchronously.
    var waitsForDiagrams = false
    /// Staged HTML to delete once the PDF has been written.
    var stagedDocument: URL?

    private var hasGenerated = false

    init(url: URL) {
        self.url = url
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard waitsForDiagrams else {
            // Give a moment for final rendering, then generate PDF
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.generatePDF()
            }
            return
        }

        // The page signals when Mermaid has settled; fall back on a timeout so a
        // runtime failure cannot leave the export hanging forever.
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            guard let self, !self.hasGenerated else { return }
            print("Mermaid rendering timed out; exporting anyway")
            self.generatePDF()
        }
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.generatePDF()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("WebView failed to load: \(error.localizedDescription)")
        cleanup()
    }

    private func generatePDF() {
        guard let webView = webView, !hasGenerated else { return }
        hasGenerated = true

        let pdfConfig = WKPDFConfiguration()
        // Don't set rect - let WebKit capture full scrollable content

        webView.createPDF(configuration: pdfConfig) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let data):
                do {
                    try data.write(to: self.url)
                    print("PDF saved successfully to \(self.url.path)")
                } catch {
                    print("Failed to write PDF: \(error.localizedDescription)")
                }
            case .failure(let error):
                print("Failed to create PDF: \(error.localizedDescription)")
            }

            self.cleanup()
        }
    }

    private func cleanup() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.webView?.configuration.userContentController
                .removeScriptMessageHandler(forName: "diagramsReady")
            self.window?.close()
            self.window = nil
            self.webView = nil
            if let stagedDocument = self.stagedDocument {
                MermaidRuntime.shared.discard(stagedDocument)
                self.stagedDocument = nil
            }
            activeGenerators.removeAll { $0 === self }
        }
    }
}

// Store generator references to prevent deallocation
private var activeGenerators: [PDFGenerator] = []

struct PDFExportService {
    @MainActor
    static func exportToPDF(markdownContent: String, suggestedName: String) {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.pdf]
        savePanel.nameFieldStringValue = "\(suggestedName).pdf"
        savePanel.title = "Export to PDF"
        savePanel.message = "Choose a location to save the PDF"

        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }

            Task { @MainActor in
                generatePDFWithWebKit(content: markdownContent, to: url)
            }
        }
    }

    @MainActor
    private static func generatePDFWithWebKit(content: String, to url: URL) {
        let document = convertMarkdownToHTML(content)

        // Create an off-screen window to host the WebView (required for rendering)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 595, height: 842),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.setFrameOrigin(NSPoint(x: -10000, y: -10000)) // Move off-screen

        // Create generator and keep strong reference
        let generator = PDFGenerator(url: url)

        let configuration = WKWebViewConfiguration()
        if document.containsDiagrams {
            configuration.userContentController.add(generator, name: "diagramsReady")
        }
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 595, height: 842), configuration: configuration)

        generator.webView = webView
        generator.window = window
        webView.navigationDelegate = generator
        activeGenerators.append(generator)

        // Add webView to window (required for rendering to work)
        window.contentView = webView
        window.orderBack(nil)

        // Diagrams need the Mermaid runtime, which WebKit can only read from disk —
        // stage the page next to it rather than loading it from a string.
        if document.containsDiagrams,
           let directory = MermaidRuntime.shared.directory,
           let staged = MermaidRuntime.shared.stage(html: document.html, as: "export-\(UUID().uuidString).html") {
            generator.waitsForDiagrams = true
            generator.stagedDocument = staged
            webView.loadFileURL(staged, allowingReadAccessTo: directory)
        } else {
            webView.loadHTMLString(document.html, baseURL: nil)
        }
    }

    struct Document {
        let html: String
        let containsDiagrams: Bool
    }

    private static func convertMarkdownToHTML(_ markdown: String) -> Document {
        // Convert markdown to HTML with GitHub-like styling
        let escapedContent = markdown
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")

        // Fenced blocks are lifted out first and put back last. Their contents are
        // literal, and Mermaid sources in particular are full of characters the
        // passes below would rewrite — `|` reads as a table, `*` as emphasis.
        let (extracted, fencedBlocks) = extractFencedBlocks(from: escapedContent)
        var html = extracted

        // Inline code
        let inlineCodePattern = "`([^`]+)`"
        if let regex = try? NSRegularExpression(pattern: inlineCodePattern, options: []) {
            html = regex.stringByReplacingMatches(
                in: html,
                options: [],
                range: NSRange(html.startIndex..., in: html),
                withTemplate: "<code>$1</code>"
            )
        }

        // Headers
        html = html.replacingOccurrences(of: "(?m)^###### (.+)$", with: "<h6>$1</h6>", options: .regularExpression)
        html = html.replacingOccurrences(of: "(?m)^##### (.+)$", with: "<h5>$1</h5>", options: .regularExpression)
        html = html.replacingOccurrences(of: "(?m)^#### (.+)$", with: "<h4>$1</h4>", options: .regularExpression)
        html = html.replacingOccurrences(of: "(?m)^### (.+)$", with: "<h3>$1</h3>", options: .regularExpression)
        html = html.replacingOccurrences(of: "(?m)^## (.+)$", with: "<h2>$1</h2>", options: .regularExpression)
        html = html.replacingOccurrences(of: "(?m)^# (.+)$", with: "<h1>$1</h1>", options: .regularExpression)

        // Bold and italic
        html = html.replacingOccurrences(of: "\\*\\*\\*(.+?)\\*\\*\\*", with: "<strong><em>$1</em></strong>", options: .regularExpression)
        html = html.replacingOccurrences(of: "\\*\\*(.+?)\\*\\*", with: "<strong>$1</strong>", options: .regularExpression)
        html = html.replacingOccurrences(of: "\\*(.+?)\\*", with: "<em>$1</em>", options: .regularExpression)

        // Horizontal rules
        html = html.replacingOccurrences(of: "(?m)^---+$", with: "<hr>", options: .regularExpression)

        // Tables
        html = convertTables(html)

        // Lists
        html = convertLists(html)

        // Paragraphs - wrap remaining text blocks
        let lines = html.components(separatedBy: "\n\n")
        html = lines.map { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty ||
                trimmed.hasPrefix(placeholderMarker) ||
                trimmed.hasPrefix("<h") ||
                trimmed.hasPrefix("<ul") ||
                trimmed.hasPrefix("<ol") ||
                trimmed.hasPrefix("<pre") ||
                trimmed.hasPrefix("<hr") ||
                trimmed.hasPrefix("<table") {
                return line
            }
            return "<p>\(line)</p>"
        }.joined(separator: "\n\n")

        // Restore the fenced blocks now that no further pass can rewrite them.
        for (index, block) in fencedBlocks.enumerated() {
            html = html.replacingOccurrences(of: placeholder(index), with: block.html)
        }

        let containsDiagrams = fencedBlocks.contains(where: \.isDiagram)

        let diagramSupport = containsDiagrams ? Self.diagramSupport : ""

        return Document(html: """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <style>
                body {
                    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
                    font-size: 14px;
                    line-height: 1.6;
                    color: #24292e;
                    max-width: 100%;
                    padding: 20px;
                }
                h1, h2, h3, h4, h5, h6 {
                    margin-top: 24px;
                    margin-bottom: 16px;
                    font-weight: 600;
                    line-height: 1.25;
                }
                h1 { font-size: 2em; border-bottom: 1px solid #eaecef; padding-bottom: 0.3em; }
                h2 { font-size: 1.5em; border-bottom: 1px solid #eaecef; padding-bottom: 0.3em; }
                h3 { font-size: 1.25em; }
                code {
                    background-color: #f6f8fa;
                    padding: 0.2em 0.4em;
                    border-radius: 3px;
                    font-family: SFMono-Regular, Consolas, "Liberation Mono", Menlo, monospace;
                    font-size: 85%;
                }
                pre {
                    background-color: #f6f8fa;
                    padding: 16px;
                    border-radius: 6px;
                    overflow-x: auto;
                    line-height: 1.45;
                }
                pre code {
                    background: none;
                    padding: 0;
                    font-size: 100%;
                }
                table {
                    border-collapse: collapse;
                    width: 100%;
                    margin: 16px 0;
                }
                th, td {
                    border: 1px solid #dfe2e5;
                    padding: 8px 12px;
                    text-align: left;
                }
                th {
                    background-color: #f6f8fa;
                    font-weight: 600;
                }
                tr:nth-child(even) {
                    background-color: #f6f8fa;
                }
                ul, ol {
                    padding-left: 2em;
                    margin: 16px 0;
                }
                li {
                    margin: 4px 0;
                }
                hr {
                    border: none;
                    border-top: 1px solid #eaecef;
                    margin: 24px 0;
                }
                p {
                    margin: 16px 0;
                }
                strong { font-weight: 600; }
                pre.mermaid {
                    background: none;
                    padding: 0;
                    text-align: center;
                }
                pre.mermaid svg {
                    max-width: 100% !important;
                    height: auto;
                }
            </style>
        </head>
        <body>
        \(html)
        \(diagramSupport)
        </body>
        </html>
        """, containsDiagrams: containsDiagrams)
    }

    /// Renders the staged `<pre class="mermaid">` blocks, then tells the generator the
    /// page has settled. Failures still report ready so the export cannot stall.
    private static let diagramSupport = """
    <script src="mermaid.min.js"></script>
    <script>
    (async () => {
        try {
            mermaid.initialize({
                startOnLoad: false,
                securityLevel: 'strict',
                theme: 'default',
                fontFamily: '-apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif'
            });
            await mermaid.run({ querySelector: 'pre.mermaid' });
        } catch (error) {
            console.error(error);
        }
        requestAnimationFrame(() => {
            window.webkit.messageHandlers.diagramsReady.postMessage(true);
        });
    })();
    </script>
    """

    private struct FencedBlock {
        let language: String
        let body: String

        var isDiagram: Bool {
            language.lowercased() == "mermaid"
        }

        var html: String {
            // Mermaid reads the element's text, so the escaped body decodes back to
            // the original source; a plain code block wants the escaping kept as-is.
            isDiagram ? "<pre class=\"mermaid\">\(body)</pre>" : "<pre><code>\(body)</code></pre>"
        }
    }

    /// A private-use character, so a placeholder can never collide with document text
    /// and no markdown pass will rewrite it.
    private static let placeholderMarker = "\u{E000}"

    private static func placeholder(_ index: Int) -> String {
        "\(placeholderMarker)FENCE\(index)\(placeholderMarker)"
    }

    /// Replaces every fenced block with a placeholder, returning the blocks in order.
    /// The info string is captured as the language rather than left in the block body.
    private static func extractFencedBlocks(from input: String) -> (text: String, blocks: [FencedBlock]) {
        let pattern = "```([^\\n`]*)\\n([\\s\\S]*?)```"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return (input, [])
        }

        let source = input as NSString
        var blocks: [FencedBlock] = []
        var output = ""
        var cursor = 0

        for match in regex.matches(in: input, range: NSRange(location: 0, length: source.length)) {
            output += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            output += placeholder(blocks.count)
            blocks.append(
                FencedBlock(
                    language: source.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces),
                    body: source.substring(with: match.range(at: 2))
                )
            )
            cursor = match.range.location + match.range.length
        }
        output += source.substring(from: cursor)

        return (output, blocks)
    }

    /// Groups consecutive list items, keeping `1.` style lists numbered rather than
    /// collapsing every marker into a bullet.
    private static func convertLists(_ input: String) -> String {
        var output: [String] = []
        var items: [String] = []
        var isOrdered = false

        func flush() {
            guard !items.isEmpty else { return }
            let tag = isOrdered ? "ol" : "ul"
            output.append("<\(tag)>")
            output.append(contentsOf: items.map { "<li>\($0)</li>" })
            output.append("</\(tag)>")
            items.removeAll()
        }

        for line in input.components(separatedBy: "\n") {
            if let item = listItem(line, ordered: true) {
                if !isOrdered { flush() }
                isOrdered = true
                items.append(item)
            } else if let item = listItem(line, ordered: false) {
                if isOrdered { flush() }
                isOrdered = false
                items.append(item)
            } else {
                flush()
                output.append(line)
            }
        }
        flush()

        return output.joined(separator: "\n")
    }

    private static func listItem(_ line: String, ordered: Bool) -> String? {
        // A marker must be followed by a space, which keeps `---` and `*emphasis*`
        // from being mistaken for list items.
        let pattern = ordered ? "^ *\\d+\\. +(.+)$" : "^ *[-*] +(.+)$"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length))
        else { return nil }
        return (line as NSString).substring(with: match.range(at: 1))
    }

    private static func convertTables(_ input: String) -> String {
        var result = input
        let lines = input.components(separatedBy: "\n")
        var i = 0
        var tableRanges: [(start: Int, end: Int, html: String)] = []

        while i < lines.count {
            let line = lines[i]

            // Check if this looks like a table header row
            if line.contains("|") && i + 1 < lines.count {
                let nextLine = lines[i + 1]
                // Check for separator row (|---|---|)
                if nextLine.contains("|") && nextLine.contains("-") {
                    var tableHTML = "<table>\n<thead>\n<tr>\n"

                    // Parse header
                    let headers = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                    for header in headers where !header.isEmpty {
                        tableHTML += "<th>\(header)</th>\n"
                    }
                    tableHTML += "</tr>\n</thead>\n<tbody>\n"

                    let tableStart = i
                    i += 2 // Skip header and separator

                    // Parse body rows
                    while i < lines.count && lines[i].contains("|") {
                        let cells = lines[i].split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                        tableHTML += "<tr>\n"
                        for cell in cells where !cell.isEmpty {
                            tableHTML += "<td>\(cell)</td>\n"
                        }
                        tableHTML += "</tr>\n"
                        i += 1
                    }

                    tableHTML += "</tbody>\n</table>"
                    tableRanges.append((tableStart, i - 1, tableHTML))
                    continue
                }
            }
            i += 1
        }

        // Replace table sections in reverse order to preserve indices
        for range in tableRanges.reversed() {
            let startLine = lines[range.start]
            var endLine = lines[range.end]
            if range.end < lines.count {
                endLine = lines[range.end]
            }

            // Find and replace the table text
            var searchStart = result.startIndex
            if let startRange = result.range(of: startLine, range: searchStart..<result.endIndex) {
                if let endRange = result.range(of: endLine, range: startRange.lowerBound..<result.endIndex) {
                    let tableRange = startRange.lowerBound..<endRange.upperBound
                    result.replaceSubrange(tableRange, with: range.html)
                }
            }
        }

        return result
    }
}
