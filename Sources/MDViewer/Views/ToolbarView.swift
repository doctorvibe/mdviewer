import SwiftUI

struct ToolbarView: ToolbarContent {
    let onOpenFile: () -> Void
    let onReload: () -> Void
    let onExportPDF: () -> Void
    let hasFile: Bool

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button(action: onOpenFile) {
                Label("Open", systemImage: "folder")
            }
            .help("Open markdown file")

            Button(action: onReload) {
                Label("Reload", systemImage: "arrow.clockwise")
            }
            .help("Reload file")
            .disabled(!hasFile)

            Button(action: onExportPDF) {
                Label("Export PDF", systemImage: "arrow.down.doc")
            }
            .help("Export to PDF")
            .disabled(!hasFile)
        }
    }
}
