import Foundation
import Combine
import SwiftUI

@MainActor
final class DocumentViewModel: ObservableObject {
    @Published var tabs: [TabItem] = []
    @Published var selectedTabId: UUID?
    @Published var tabContents: [UUID: String] = [:]
    @Published var errorMessage: String?
    @Published var isFilePickerPresented: Bool = false

    private var fileWatchers: [UUID: FileWatcher] = [:]
    private var cancellables = Set<AnyCancellable>()
    private let sessionManager = SessionManager.shared

    init() {
        loadSession()
    }

    private func loadSession() {
        let (savedTabs, savedSelectedId) = sessionManager.loadTabs()

        for tab in savedTabs {
            if let resolvedURL = tab.resolveURL() {
                let newTab = TabItem(id: tab.id, fileURL: resolvedURL)
                tabs.append(newTab)
                loadContent(for: newTab)
                setupFileWatcher(for: newTab)
            }
        }

        if let savedSelectedId = savedSelectedId, tabs.contains(where: { $0.id == savedSelectedId }) {
            selectedTabId = savedSelectedId
        } else {
            selectedTabId = tabs.first?.id
        }
    }

    private func saveSession() {
        sessionManager.saveTabs(tabs, selectedTabId: selectedTabId)
    }

    func openFile(url: URL) {
        // Check if already open
        if let existingTab = tabs.first(where: { $0.fileURL == url }) {
            selectedTabId = existingTab.id
            return
        }

        let tab = TabItem(fileURL: url)
        tabs.append(tab)
        selectedTabId = tab.id
        loadContent(for: tab)
        setupFileWatcher(for: tab)
        saveSession()
    }

    func closeTab(_ tabId: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabId }) else { return }

        // Stop watching
        fileWatchers[tabId]?.stopWatching()
        fileWatchers.removeValue(forKey: tabId)
        tabContents.removeValue(forKey: tabId)

        tabs.remove(at: index)

        // Update selection
        if selectedTabId == tabId {
            if tabs.isEmpty {
                selectedTabId = nil
            } else {
                let newIndex = min(index, tabs.count - 1)
                selectedTabId = tabs[newIndex].id
            }
        }

        saveSession()
    }

    func selectTab(_ tabId: UUID) {
        guard tabs.contains(where: { $0.id == tabId }) else { return }
        selectedTabId = tabId
        saveSession()
    }

    func reloadCurrentTab() {
        guard let tabId = selectedTabId,
              let tab = tabs.first(where: { $0.id == tabId }) else { return }
        loadContent(for: tab)
    }

    private func loadContent(for tab: TabItem) {
        guard let url = tab.resolveURL() else {
            tabContents[tab.id] = ""
            errorMessage = "Could not access file: \(tab.fileName)"
            return
        }

        do {
            let content = try FileService.readMarkdown(from: url)
            tabContents[tab.id] = content
            errorMessage = nil
        } catch {
            tabContents[tab.id] = ""
            errorMessage = error.localizedDescription
        }
    }

    private func setupFileWatcher(for tab: TabItem) {
        guard let url = tab.resolveURL() else { return }

        let watcher = FileWatcher()
        fileWatchers[tab.id] = watcher

        watcher.$lastModified
            .dropFirst()
            .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.loadContent(for: tab)
            }
            .store(in: &cancellables)

        watcher.watch(url: url)
    }

    var currentContent: String {
        guard let tabId = selectedTabId else { return "" }
        return tabContents[tabId] ?? ""
    }

    var currentFileName: String {
        guard let tabId = selectedTabId,
              let tab = tabs.first(where: { $0.id == tabId }) else {
            return "MDViewer"
        }
        return tab.fileName
    }

    var hasOpenTabs: Bool {
        !tabs.isEmpty
    }
}
