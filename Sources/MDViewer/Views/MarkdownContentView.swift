import SwiftUI
import MarkdownUI

struct MarkdownContentView: View {
    let content: String

    var body: some View {
        ScrollView {
            // The block style must sit outside `markdownTheme`: the theme modifier
            // replaces the whole theme, so applying it last would discard this style.
            Markdown(content)
                .markdownBlockStyle(\.codeBlock) { configuration in
                    if configuration.language?.lowercased() == "mermaid" {
                        MermaidView(source: configuration.content)
                    } else {
                        configuration.label
                    }
                }
                .markdownTheme(.gitHub)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}
