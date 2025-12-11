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
                    MarkdownContentView(content: viewModel.currentContent)
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
}

extension Notification.Name {
    static let openFile = Notification.Name("openFile")
}
