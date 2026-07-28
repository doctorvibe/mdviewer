import SwiftUI
import WebKit

/// The page that hosts a single diagram, staged once and reused by every diagram view.
///
/// `renderDiagram` is driven from Swift after the page loads, so changing the source
/// or the appearance re-renders without reloading.
private enum MermaidShell {
    static let url: URL? = MermaidRuntime.shared.stage(html: html, as: "shell.html")

    private static let html = """
    <!DOCTYPE html>
    <html>
    <head>
    <meta charset="utf-8">
    <script src="mermaid.min.js"></script>
    <style>
        html, body {
            margin: 0;
            padding: 0;
            overflow: hidden;
            background: transparent;
        }
        #diagram {
            display: flex;
            justify-content: center;
            padding: 8px 0;
        }
        /* Mermaid writes an inline max-width, so !important is needed to fit the view. */
        #diagram svg {
            max-width: 100% !important;
            height: auto;
        }
        #error {
            margin: 0;
            padding: 12px;
            width: 100%;
            box-sizing: border-box;
            border-radius: 6px;
            font-family: SFMono-Regular, Menlo, monospace;
            font-size: 12px;
            line-height: 1.45;
            white-space: pre-wrap;
        }
    </style>
    </head>
    <body>
    <div id="diagram"></div>
    <script>
    let sequence = 0;

    async function renderDiagram(source, theme, errorColor, errorBackground) {
        const container = document.getElementById('diagram');
        try {
            mermaid.initialize({
                startOnLoad: false,
                securityLevel: 'strict',
                theme: theme,
                fontFamily: '-apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif'
            });
            const { svg } = await mermaid.render('mermaid-' + (++sequence), source);
            container.innerHTML = svg;
        } catch (error) {
            const message = error && error.message ? error.message : String(error);
            const pre = document.createElement('pre');
            pre.id = 'error';
            pre.style.color = errorColor;
            pre.style.background = errorBackground;
            pre.textContent = 'Mermaid could not render this diagram:\\n\\n' + message;
            container.innerHTML = '';
            container.appendChild(pre);
        }
        // mermaid.render can leave its measuring element behind on failure.
        document.querySelectorAll('body > div:not(#diagram), body > svg').forEach(n => n.remove());
        requestAnimationFrame(reportHeight);
    }

    function reportHeight() {
        const height = document.getElementById('diagram').getBoundingClientRect().height;
        window.webkit.messageHandlers.mermaid.postMessage(Math.ceil(height));
    }

    window.addEventListener('resize', () => requestAnimationFrame(reportHeight));
    </script>
    </body>
    </html>
    """
}

/// A ```mermaid fenced code block, rendered as a diagram.
///
/// Falls back to the raw source when the Mermaid runtime is unavailable; syntax errors
/// are reported inside the web view by the shell itself.
struct MermaidView: View {
    let source: String

    @Environment(\.colorScheme) private var colorScheme
    @State private var height: CGFloat = 80

    var body: some View {
        if let shellURL = MermaidShell.url, let directory = MermaidRuntime.shared.directory {
            MermaidWebView(
                source: source,
                shellURL: shellURL,
                directory: directory,
                isDark: colorScheme == .dark,
                height: $height
            )
            .frame(height: height)
            .frame(maxWidth: .infinity)
        } else {
            fallback
        }
    }

    private var fallback: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Mermaid runtime unavailable")
                .font(.caption)
                .foregroundColor(.secondary)
            Text(source)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(6)
    }
}

private struct MermaidWebView: NSViewRepresentable {
    let source: String
    let shellURL: URL
    let directory: URL
    let isDark: Bool
    @Binding var height: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(height: $height)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "mermaid")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.enclosingScrollView?.hasVerticalScroller = false
        webView.loadFileURL(shellURL, allowingReadAccessTo: directory)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.render(source: source, isDark: isDark, in: webView)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "mermaid")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        private let height: Binding<CGFloat>
        private var isLoaded = false
        private var rendered: (source: String, isDark: Bool)?
        private var pending: (source: String, isDark: Bool)?

        init(height: Binding<CGFloat>) {
            self.height = height
        }

        func render(source: String, isDark: Bool, in webView: WKWebView) {
            guard rendered?.source != source || rendered?.isDark != isDark else { return }
            guard isLoaded else {
                pending = (source, isDark)
                return
            }
            rendered = (source, isDark)
            pending = nil

            let theme = isDark ? "dark" : "default"
            let errorColor = isDark ? "#ff9492" : "#cf222e"
            let errorBackground = isDark ? "#2d1618" : "#fff1f0"
            let arguments = [source, theme, errorColor, errorBackground]
                .map(Self.jsString)
                .joined(separator: ", ")
            webView.evaluateJavaScript("renderDiagram(\(arguments));")
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoaded = true
            if let pending {
                render(source: pending.source, isDark: pending.isDark, in: webView)
            }
        }

        /// The shell is the only thing this view is allowed to load; a link inside a
        /// diagram must not be able to navigate it somewhere else.
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            decisionHandler(navigationAction.request.url?.isFileURL == true ? .allow : .cancel)
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard let reported = message.body as? NSNumber else { return }
            let newHeight = max(CGFloat(reported.doubleValue), 20)
            // Height feeds back into the frame, which resizes the web view — only
            // propagate real changes so the two cannot oscillate.
            guard abs(newHeight - height.wrappedValue) > 1 else { return }
            height.wrappedValue = newHeight
        }

        private static func jsString(_ value: String) -> String {
            let data = try? JSONSerialization.data(withJSONObject: [value])
            guard let data, let array = String(data: data, encoding: .utf8) else { return "\"\"" }
            return String(array.dropFirst().dropLast())
        }
    }
}
