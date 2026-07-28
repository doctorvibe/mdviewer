import SwiftUI

struct ToolbarView: ToolbarContent {
    let onOpenFile: () -> Void
    let onReload: () -> Void
    let onExportPDF: () -> Void
    let onZoomIn: () -> Void
    let onZoomOut: () -> Void
    let onResetZoom: () -> Void
    let zoomDescription: String
    let canZoomIn: Bool
    let canZoomOut: Bool
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

            Button(action: onZoomOut) {
                Label("Zoom Out", systemImage: "minus.magnifyingglass")
            }
            .help("Zoom out (\u{2318}-)")
            .disabled(!hasFile || !canZoomOut)

            Button(action: onResetZoom) {
                Text(zoomDescription)
                    .font(.system(size: 11).monospacedDigit())
                    .frame(minWidth: 34)
            }
            .help("Actual size (\u{2318}0)")
            .disabled(!hasFile)

            Button(action: onZoomIn) {
                Label("Zoom In", systemImage: "plus.magnifyingglass")
            }
            .help("Zoom in (\u{2318}+)")
            .disabled(!hasFile || !canZoomIn)

            Button(action: onExportPDF) {
                Label("Export PDF", systemImage: "arrow.down.doc")
            }
            .help("Export to PDF")
            .disabled(!hasFile)
        }
    }
}
