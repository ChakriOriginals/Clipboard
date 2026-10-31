import AppKit
import ClipFlowCore

/// Restores a stored entry to a pasteboard.
@MainActor
enum PasteboardWriter {
    /// Writes every item and flavor; PNG images also get a TIFF flavor for apps that only read TIFF.
    /// Returns the resulting change count so the monitor can ignore this write.
    @discardableResult
    static func write(_ content: ClipContent, to pasteboard: NSPasteboard) -> Int {
        pasteboard.clearContents()
        let items = content.items.map { reps -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for rep in reps {
                item.setData(rep.data, forType: NSPasteboard.PasteboardType(rep.type))
            }
            if let png = reps.first(where: { $0.type == PasteboardType.png })?.data,
               !reps.contains(where: { $0.type == PasteboardType.tiff }),
               let tiff = NSBitmapImageRep(data: png)?.tiffRepresentation {
                item.setData(tiff, forType: .tiff)
            }
            return item
        }
        pasteboard.writeObjects(items)
        return pasteboard.changeCount
    }
}
