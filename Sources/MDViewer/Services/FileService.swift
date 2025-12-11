import Foundation

enum FileError: LocalizedError {
    case accessDenied
    case readFailed(Error)
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Access to file was denied"
        case .readFailed(let error):
            return "Failed to read file: \(error.localizedDescription)"
        case .invalidURL:
            return "Invalid file URL"
        }
    }
}

struct FileService {
    static func readMarkdown(from url: URL) throws -> String {
        let accessing = url.startAccessingSecurityScopedResource()

        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw FileError.readFailed(error)
        }
    }
}
