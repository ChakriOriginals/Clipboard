import CryptoKit
import Foundation
@testable import ClipFlowCore

func makeTempDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("ClipFlowTests-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func textDraft(_ text: String, sensitive: Bool = false, kind: ClipKind = .text) -> ClipDraft {
    let data = Data(text.utf8)
    return ClipDraft(kind: kind, previewText: text, sourceAppBundleID: "com.apple.TextEdit",
                     sourceAppName: "TextEdit", fileNames: [], isSensitive: sensitive,
                     content: ClipContent(items: [[Representation(type: "public.utf8-plain-text", data: data)]]),
                     canonical: data, thumbnailPNG: nil, byteSize: data.count)
}

struct UnreadableKeyStore: KeyStore {
    let status: OSStatus
    func loadKey() throws -> SymmetricKey? { throw KeyStoreError.unreadable(status) }
    func createKey() throws -> SymmetricKey { throw KeyStoreError.writeFailed(status) }
    func deleteKey() throws { throw KeyStoreError.writeFailed(status) }
}
