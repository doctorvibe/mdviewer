import Foundation

final class SessionManager {
    private let userDefaults = UserDefaults.standard
    private let tabsKey = "savedTabs"
    private let selectedTabKey = "selectedTabId"

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

    func clearSession() {
        userDefaults.removeObject(forKey: tabsKey)
        userDefaults.removeObject(forKey: selectedTabKey)
    }
}
