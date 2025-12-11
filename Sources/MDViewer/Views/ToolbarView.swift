import SwiftUI

struct ToolbarView: ToolbarContent {
    let onOpenFile: () -> Void
    let onReload: () -> Void
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
        }
    }
}
