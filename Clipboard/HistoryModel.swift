import AppKit
import ClipboardCore
import Observation
import os

enum StoreStatus: Equatable {
    case loading
    case ready
    /// The Keychain refused access to the key; nothing is captured until Retry succeeds.
    case locked
    /// The previous history was unreadable and moved to this file.
    case recovered(URL)
    /// The history file comes from a newer Clipboard; it is left untouched and nothing is captured.
    case newerVersion
    case failed
}

/// Main-actor façade over the encrypted store: capture, search, selection, and management.
@MainActor
@Observable
final class HistoryModel {
    private(set) var items: [ClipItem] = []
    private(set) var results: [ClipItem] = []
    private(set) var status: StoreStatus = .loading
    var query = SearchQuery() { didSet { recompute() } }
    var selectedID: UUID? { didSet { if selectedID != revealedID { revealedID = nil } } }
    /// The sensitive item the user chose to show. Cleared when the selection moves or the panel reopens.
    private(set) var revealedID: UUID?

    @ObservationIgnored private let store: ClipStore
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var searchKeys: [UUID: String] = [:]
    @ObservationIgnored private var pendingCapture: (snapshot: PasteboardSnapshot, capturedAt: Date)?
    @ObservationIgnored private var captureWorker: Task<Void, Never>?
    @ObservationIgnored private let thumbnails: NSCache<NSUUID, NSImage> = {
        let cache = NSCache<NSUUID, NSImage>()
        cache.countLimit = 200
        return cache
    }()
    @ObservationIgnored private let log = Logger(subsystem: "dev.clipflow.ClipFlow", category: "history")

    init(store: ClipStore, settings: SettingsStore, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.settings = settings
        self.now = now
    }

    var pinnedResults: [ClipItem] { results.filter(\.isPinned) }
    var recentResults: [ClipItem] { results.filter { !$0.isPinned } }
    var selectedItem: ClipItem? { results.first { $0.id == selectedID } }

    // MARK: Lifecycle

    func load() async {
        do {
            let result = try await store.open()
            if case .recoveredFromUnreadable(let url) = result {
                status = .recovered(url)
            } else {
                status = .ready
            }
            let (loaded, purged) = try await store.allItems()
            if purged > 0 { log.error("Removed \(purged, privacy: .public) unreadable entries") }
            setItems(loaded)
            await applyRetention()
        } catch ClipStoreError.locked {
            status = .locked
            setItems([])
        } catch ClipStoreError.newerVersion {
            status = .newerVersion
            setItems([])
        } catch {
            log.error("Failed to open history: \(String(describing: type(of: error)), privacy: .public)")
            status = .failed
        }
    }

    var canCapture: Bool {
        switch status {
        case .ready, .recovered: true
        case .loading, .locked, .newerVersion, .failed: false
        }
    }

    /// Clears a `.recovered` notice once the user has seen it.
    func acknowledgeRecovery() {
        if case .recovered = status { status = .ready }
    }

    // MARK: Capture

    /// Queues a capture. One capture is processed at a time; while one runs, newer snapshots replace
    /// any still-waiting one, so a flood of pasteboard changes can't pile up decode work or memory.
    func enqueue(_ snapshot: PasteboardSnapshot, capturedAt: Date) {
        pendingCapture = (snapshot, capturedAt)
        guard captureWorker == nil else { return }
        captureWorker = Task {
            while let next = pendingCapture {
                pendingCapture = nil
                await ingest(next.snapshot, capturedAt: next.capturedAt)
            }
            captureWorker = nil
        }
    }

    func waitForPendingCaptures() async {
        while let worker = captureWorker { await worker.value }
    }

    /// Captures a snapshot. `capturedAt` is when the change was observed, so slow decodes can't
    /// reorder history.
    func ingest(_ snapshot: PasteboardSnapshot, capturedAt: Date? = nil) async {
        guard canCapture else { return }
        let observedAt = capturedAt ?? now()
        let settings = self.settings.captureSettings
        let decision = await Task.detached(priority: .userInitiated) {
            CapturePolicy.decide(snapshot, settings: settings)
        }.value
        guard case .capture(let draft) = decision else { return }
        do {
            let item = try await store.insertOrBump(draft, now: observedAt)
            upsert(item)
            await applyRetention()
        } catch {
            log.error("Failed to save entry: \(String(describing: type(of: error)), privacy: .public)")
        }
    }

    // MARK: Actions

    /// Restores an entry to the pasteboard and moves it to the top. Returns the pasteboard change count.
    /// `onWrite` runs synchronously right after the write, before any suspension, so the monitor can
    /// ignore Clipboard's own change before its next poll.
    func restore(id: UUID, to pasteboard: NSPasteboard, onWrite: (Int) -> Void = { _ in }) async -> Int? {
        guard let target = items.first(where: { $0.id == id }), !isExpired(target) else { return nil }
        do {
            let content = try await store.content(id: id)
            // Re-check after the await: the item may have expired or been deleted meanwhile.
            guard let current = items.first(where: { $0.id == id }), !isExpired(current) else { return nil }
            let changeCount = PasteboardWriter.write(content, to: pasteboard, concealed: current.isSensitive)
            onWrite(changeCount)
            let time = now()
            try await store.bump(id: id, now: time)
            if var item = items.first(where: { $0.id == id }) {
                item.lastCopiedAt = time
                upsert(item)
            }
            return changeCount
        } catch {
            log.error("Failed to restore entry: \(String(describing: type(of: error)), privacy: .public)")
            return nil
        }
    }

    func togglePin(_ id: UUID) async {
        guard var item = items.first(where: { $0.id == id }) else { return }
        item.isPinned.toggle()
        do {
            try await store.setPinned(id, item.isPinned)
            upsert(item)
        } catch {
            log.error("Failed to pin entry")
        }
    }

    func toggleSensitive(_ id: UUID) async {
        guard var item = items.first(where: { $0.id == id }) else { return }
        item.isSensitive.toggle()
        do {
            try await store.setSensitive(id, item.isSensitive)
            upsert(item)
        } catch {
            log.error("Failed to change sensitivity")
        }
    }

    func delete(_ id: UUID) async {
        do {
            try await store.delete(ids: [id])
            remove([id])
        } catch {
            log.error("Failed to delete entry")
        }
    }

    func clearUnpinned() async {
        do {
            try await store.clearUnpinned()
            remove(items.filter { !$0.isPinned }.map(\.id))
        } catch {
            log.error("Failed to clear history")
        }
    }

    func clearEverything() async {
        do {
            try await store.destroyEverything()
            thumbnails.removeAllObjects()
            status = .ready
            setItems([])
        } catch {
            // Files may already be gone: never keep showing (or restoring) what the user asked to erase.
            log.error("Failed to erase history: \(String(describing: type(of: error)), privacy: .public)")
            thumbnails.removeAllObjects()
            setItems([])
            status = .failed
        }
    }

    func applyRetention() async {
        let doomed = RetentionPolicy.idsToDelete(items, settings: settings.retentionSettings, now: now())
        guard !doomed.isEmpty else { return }
        do {
            try await store.delete(ids: doomed)
            remove(doomed)
        } catch {
            log.error("Failed to apply retention")
        }
    }

    /// Decrypts an entry to show exactly what pasting it would deliver. Nil for missing or expired items.
    func preview(for id: UUID) async -> ContentPreview? {
        guard let item = items.first(where: { $0.id == id }), !isExpired(item),
              let content = try? await store.content(id: id)
        else { return nil }
        return await Task.detached(priority: .userInitiated) { ContentPreview.make(from: content) }.value
    }

    func thumbnail(for id: UUID) async -> NSImage? {
        if let cached = thumbnails.object(forKey: id as NSUUID) { return cached }
        guard let data = try? await store.thumbnail(id: id), let image = NSImage(data: data) else { return nil }
        thumbnails.setObject(image, forKey: id as NSUUID)
        return image
    }

    /// Re-filters for the passage of time (expiry) without touching storage.
    func refreshForTimeChange() {
        recompute()
    }

    private func isExpired(_ item: ClipItem) -> Bool {
        RetentionPolicy.isExpired(item, settings: settings.retentionSettings, now: now())
    }

    // MARK: Selection

    /// Called each time the panel opens: clear the search and select the most recent entry.
    func resetForPresentation() {
        query = SearchQuery()
        selectedID = results.first?.id
        revealedID = nil
    }

    func reveal(_ id: UUID) {
        if id == selectedID { revealedID = id }
    }

    func moveSelection(_ delta: Int) {
        guard !results.isEmpty else { selectedID = nil; return }
        let current = results.firstIndex { $0.id == selectedID } ?? 0
        selectedID = results[min(max(current + delta, 0), results.count - 1)].id
    }

    // MARK: Internals

    private func setItems(_ newItems: [ClipItem]) {
        items = newItems.sorted { $0.lastCopiedAt > $1.lastCopiedAt }
        searchKeys = Dictionary(uniqueKeysWithValues: items.map { ($0.id, SearchIndex.searchKey(for: $0)) })
        recompute()
    }

    private func upsert(_ item: ClipItem) {
        items.removeAll { $0.id == item.id }
        let index = items.firstIndex { $0.lastCopiedAt <= item.lastCopiedAt } ?? items.endIndex
        items.insert(item, at: index)
        searchKeys[item.id] = SearchIndex.searchKey(for: item)
        recompute()
    }

    private func remove(_ ids: [UUID]) {
        let doomed = Set(ids)
        guard !doomed.isEmpty else { return }
        let oldIndex = results.firstIndex { $0.id == selectedID }
        items.removeAll { doomed.contains($0.id) }
        for id in doomed {
            searchKeys[id] = nil
            thumbnails.removeObject(forKey: id as NSUUID)
        }
        recompute(preferredIndex: oldIndex)
    }

    private func recompute(preferredIndex: Int? = nil) {
        let visible = items.filter { !isExpired($0) }
        results = SearchIndex.filter(visible, keys: searchKeys, query: query, now: now(), calendar: .current)
        if let selectedID, results.contains(where: { $0.id == selectedID }) { return }
        if results.isEmpty {
            selectedID = nil
        } else {
            selectedID = results[min(preferredIndex ?? 0, results.count - 1)].id
        }
    }
}
