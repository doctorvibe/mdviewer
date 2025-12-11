import Foundation
import Combine

final class FileWatcher: ObservableObject {
    @Published private(set) var lastModified: Date = Date()

    private var fileDescriptor: Int32 = -1
    private var source: DispatchSourceFileSystemObject?
    private var watchedURL: URL?

    func watch(url: URL) {
        stopWatching()

        watchedURL = url
        fileDescriptor = open(url.path, O_EVTONLY)

        guard fileDescriptor != -1 else {
            print("Failed to open file for watching: \(url.path)")
            return
        }

        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename, .extend, .attrib],
            queue: DispatchQueue.main
        )

        source?.setEventHandler { [weak self] in
            self?.lastModified = Date()
        }

        source?.setCancelHandler { [weak self] in
            guard let self = self, self.fileDescriptor != -1 else { return }
            close(self.fileDescriptor)
            self.fileDescriptor = -1
        }

        source?.resume()
    }

    func stopWatching() {
        source?.cancel()
        source = nil
        watchedURL = nil
    }

    deinit {
        stopWatching()
    }
}
