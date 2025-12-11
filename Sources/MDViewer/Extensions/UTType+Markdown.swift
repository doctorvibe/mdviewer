import UniformTypeIdentifiers

extension UTType {
    static var markdown: UTType {
        UTType(filenameExtension: "md", conformingTo: .plainText) ?? .plainText
    }
}
