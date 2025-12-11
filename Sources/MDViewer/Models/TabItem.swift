import Foundation

struct TabItem: Identifiable, Codable, Equatable {
    let id: UUID
    let fileURL: URL
    var bookmarkData: Data?

    var fileName: String {
        fileURL.lastPathComponent
    }

    init(id: UUID = UUID(), fileURL: URL) {
        self.id = id
        self.fileURL = fileURL
        self.bookmarkData = try? fileURL.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    func resolveURL() -> URL? {
        guard let bookmarkData = bookmarkData else {
            return fileURL
        }

        var isStale = false
        guard let resolvedURL = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }

        return resolvedURL
    }
}
