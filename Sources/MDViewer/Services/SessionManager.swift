import Foundation

final class SessionManager {
    private let userDefaults = UserDefaults.standard
    private let tabsKey = "savedTabs"
    private let selectedTabKey = "selectedTabId"
    private let zoomKey = "zoomLevel"

    static let shared = SessionManager()

    private init() {}

    func saveTabs(_ tabs: [TabItem], selectedTabId: UUID?) {
        if let encoded = try? JSONEncoder().encode(tabs) {
            userDefaults.set(encoded, forKey: tabsKey)
        }

        if let selectedId = selectedTabId {
            userDefaults.set(selectedId.uuidString, forKey: selectedTabKey)
        } else {
            userDefaults.removeObject(forKey: selectedTabKey)
        }
    }

    func loadTabs() -> (tabs: [TabItem], selectedTabId: UUID?) {
        guard let data = userDefaults.data(forKey: tabsKey),
              let tabs = try? JSONDecoder().decode([TabItem].self, from: data) else {
            return ([], nil)
        }

        let selectedIdString = userDefaults.string(forKey: selectedTabKey)
        let selectedId = selectedIdString.flatMap { UUID(uuidString: $0) }

        return (tabs, selectedId)
    }

    func saveZoom(_ zoom: Double) {
        userDefaults.set(zoom, forKey: zoomKey)
    }

    func loadZoom() -> Double {
        let stored = userDefaults.double(forKey: zoomKey)
        // `double(forKey:)` returns 0 when nothing is stored.
        return stored > 0 ? stored : 1.0
    }

    func clearSession() {
        userDefaults.removeObject(forKey: tabsKey)
        userDefaults.removeObject(forKey: selectedTabKey)
    }
}
