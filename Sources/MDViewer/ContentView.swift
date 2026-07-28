import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var viewModel = DocumentViewModel()

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.hasOpenTabs {
                TabBarView(
                    tabs: viewModel.tabs,
                    selectedTabId: viewModel.selectedTabId,
                    onSelect: { viewModel.selectTab($0) },
                    onClose: { viewModel.closeTab($0) }
                )
                Divider()
            }

            Group {
                if viewModel.hasOpenTabs {
                    MarkdownContentView(content: viewModel.currentContent, zoom: viewModel.zoomLevel)
                } else {
                    EmptyStateView(onOpenFile: { viewModel.isFilePickerPresented = true })
                }
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .navigationTitle(viewModel.currentFileName)
        .toolbar {
            ToolbarView(
                onOpenFile: { viewModel.isFilePickerPresented = true },
                onReload: { viewModel.reloadCurrentTab() },
                onExportPDF: { exportToPDF() },
                onZoomIn: { viewModel.zoomIn() },
                onZoomOut: { viewModel.zoomOut() },
                onResetZoom: { viewModel.resetZoom() },
                zoomDescription: viewModel.zoomDescription,
                canZoomIn: viewModel.canZoomIn,
                canZoomOut: viewModel.canZoomOut,
                hasFile: viewModel.hasOpenTabs
            )
        }
        .fileImporter(
            isPresented: $viewModel.isFilePickerPresented,
            allowedContentTypes: [.markdown, .plainText],
            allowsMultipleSelection: true
        ) { result in
            handleFileSelection(result)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openFile)) { _ in
            viewModel.isFilePickerPresented = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .exportPDF)) { _ in
            exportToPDF()
        }
        .onReceive(NotificationCenter.default.publisher(for: .zoomIn)) { _ in
            viewModel.zoomIn()
        }
        .onReceive(NotificationCenter.default.publisher(for: .zoomOut)) { _ in
            viewModel.zoomOut()
        }
        .onReceive(NotificationCenter.default.publisher(for: .resetZoom)) { _ in
            viewModel.resetZoom()
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                viewModel.openFile(url: url)
            }
        case .failure(let error):
            viewModel.errorMessage = error.localizedDescription
        }
    }

    private func exportToPDF() {
        guard viewModel.hasOpenTabs else { return }
        PDFExportService.exportToPDF(
            markdownContent: viewModel.currentContent,
            suggestedName: viewModel.currentTabBaseName
        )
    }
}

extension Notification.Name {
    static let openFile = Notification.Name("openFile")
    static let exportPDF = Notification.Name("exportPDF")
    static let zoomIn = Notification.Name("zoomIn")
    static let zoomOut = Notification.Name("zoomOut")
    static let resetZoom = Notification.Name("resetZoom")
}
