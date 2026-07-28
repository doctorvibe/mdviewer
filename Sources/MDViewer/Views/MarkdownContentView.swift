import SwiftUI
import MarkdownUI

struct MarkdownContentView: View {
    let content: String
    var zoom: Double = 1.0

    /// The GitHub theme sizes headings, code, and quotes relative to its 16pt base,
    /// so scaling that one value zooms the whole document proportionally.
    private var theme: Theme {
        Theme.gitHub.text {
            ForegroundColor(.primary)
            FontSize(16 * zoom)
        }
    }

    var body: some View {
        ScrollView {
            // The block style must sit outside `markdownTheme`: the theme modifier
            // replaces the whole theme, so applying it last would discard this style.
            Markdown(content)
                .markdownBlockStyle(\.codeBlock) { configuration in
                    if configuration.language?.lowercased() == "mermaid" {
                        MermaidView(source: configuration.content, zoom: zoom)
                    } else {
                        configuration.label
                    }
                }
                .markdownTheme(theme)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}
