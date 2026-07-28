import Foundation

/// Stages the bundled Mermaid runtime in a temporary directory.
///
/// WebKit loads the script from disk, so any page that needs it must live in a
/// directory the web view has been granted read access to. The bundle's resource
/// directory is read-only, so `mermaid.min.js` is copied out once and shared by
/// every page that renders diagrams — the viewer's shell and the PDF exporter.
final class MermaidRuntime {
    static let shared = MermaidRuntime()

    /// Directory holding `mermaid.min.js`, or `nil` if the runtime is unavailable.
    let directory: URL?

    private init() {
        guard let bundledScript = Bundle.module.url(forResource: "mermaid.min", withExtension: "js") else {
            directory = nil
            return
        }

        let fileManager = FileManager.default
        let dir = fileManager.temporaryDirectory.appendingPathComponent("MDViewerMermaid", isDirectory: true)
        let script = dir.appendingPathComponent("mermaid.min.js")

        do {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)

            // Re-copy when the staged script is missing or a different build than the bundled one.
            let staged = try? fileManager.attributesOfItem(atPath: script.path)[.size] as? Int
            let bundled = try fileManager.attributesOfItem(atPath: bundledScript.path)[.size] as? Int
            if staged == nil || staged != bundled {
                try? fileManager.removeItem(at: script)
                try fileManager.copyItem(at: bundledScript, to: script)
            }

            directory = dir
        } catch {
            directory = nil
        }
    }

    /// Writes `html` beside the script and returns its file URL, so a web view can
    /// load it with `loadFileURL(_:allowingReadAccessTo:)` and reach the runtime.
    func stage(html: String, as name: String) -> URL? {
        guard let directory else { return nil }
        let url = directory.appendingPathComponent(name)
        do {
            try html.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    func discard(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
