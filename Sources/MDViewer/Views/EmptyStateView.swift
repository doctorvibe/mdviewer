import SwiftUI

struct EmptyStateView: View {
    let onOpenFile: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text")
                .font(.system(size: 64))
                .foregroundColor(.secondary)

            Text("No Markdown File Open")
                .font(.title2)
                .foregroundColor(.secondary)

            Text("Open a .md file to view its contents")
                .font(.body)
                .foregroundColor(.secondary)

            Button("Open File...") {
                onOpenFile()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
