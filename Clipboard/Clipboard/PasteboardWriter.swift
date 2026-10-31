import AppKit
import ClipboardCore

/// Restores a stored entry to a pasteboard.
@MainActor
enum PasteboardWriter {
    /// Keeps the lazy TIFF providers alive until the pasteboard changes again.
    private static var providers: [TIFFProvider] = []

    /// Writes every item and flavor. PNG images also offer TIFF, produced only if another app asks for
    /// it and only for images up to `TIFFProvider.maxPixels`. `concealed` adds the nspasteboard.org
    /// marker so other clipboard tools skip a restored secret. Returns the resulting change count so
    /// the monitor can ignore this write.
    @discardableResult
    static func write(_ content: ClipContent, to pasteboard: NSPasteboard, concealed: Bool = false) -> Int {
        pasteboard.clearContents()
        providers = []
        let items = content.items.map { reps -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for rep in reps {
                item.setData(rep.data, forType: NSPasteboard.PasteboardType(rep.type))
            }
            if let png = reps.first(where: { $0.type == PasteboardType.png })?.data,
               !reps.contains(where: { $0.type == PasteboardType.tiff }) {
                let provider = TIFFProvider(png: png)
                providers.append(provider)
                item.setDataProvider(provider, forTypes: [.tiff])
            }
            if concealed {
                item.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
            }
            return item
        }
        pasteboard.writeObjects(items)
        return pasteboard.changeCount
    }
}

/// Converts a stored PNG to TIFF on demand. Large images are not converted: an uncompressed TIFF of a
/// 100-megapixel image would be ~400 MB.
final class TIFFProvider: NSObject, NSPasteboardItemDataProvider, @unchecked Sendable {
    static let maxPixels = 25_000_000
    private let png: Data

    init(png: Data) {
        self.png = png
    }

    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        guard type == .tiff, let size = Thumbnailer.pixelSize(png),
              size.width > 0, size.height > 0, size.width.multipliedReportingOverflow(by: size.height).partialValue <= Self.maxPixels,
              let tiff = NSBitmapImageRep(data: png)?.tiffRepresentation
        else { return }
        item.setData(tiff, forType: .tiff)
    }
}
