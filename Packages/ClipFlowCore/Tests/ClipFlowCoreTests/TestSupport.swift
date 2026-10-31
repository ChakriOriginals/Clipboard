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

import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

func makeImage(width: Int, height: Int, type: UTType = .png) -> Data {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let image = context.makeImage()!
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
    return data as Data
}

func makeItem(_ preview: String, kind: ClipKind = .text, lastCopied: Date = Date(timeIntervalSince1970: 1_800_000_000),
              pinned: Bool = false, sensitive: Bool = false, fileNames: [String] = []) -> ClipItem {
    ClipItem(id: UUID(), kind: kind, createdAt: lastCopied, lastCopiedAt: lastCopied, contentHash: Data(),
             isPinned: pinned, isSensitive: sensitive, deviceID: "d", byteSize: preview.utf8.count, hasThumbnail: false,
             summary: ClipSummary(previewText: preview, sourceAppBundleID: nil, sourceAppName: nil, fileNames: fileNames))
}
