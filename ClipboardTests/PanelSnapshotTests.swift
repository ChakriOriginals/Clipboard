import AppKit
import ClipboardCore
import SwiftUI
import XCTest
@testable import Clipboard

/// Renders the real panel offscreen to PNGs for visual review. Runs only when SNAPSHOT_DIR is set
/// (`TEST_RUNNER_SNAPSHOT_DIR=/path make test-app`); always skipped in CI.
@MainActor
final class PanelSnapshotTests: XCTestCase {
    func testRenderPanelStates() async throws {
        guard let out = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] else { throw XCTSkip("SNAPSHOT_DIR not set") }
        let (defaults, suite) = makeTestDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ClipboardSnapshots-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let model = HistoryModel(store: ClipStore(directory: dir, keyStore: InMemoryKeyStore(), deviceID: "d"), settings: settings)
        await model.load()

        func text(_ s: String, app: String) -> PasteboardSnapshot {
            PasteboardSnapshot(items: [[Representation(type: PasteboardType.plainText, data: Data(s.utf8))]],
                               types: [PasteboardType.plainText], frontmostBundleID: nil, frontmostAppName: app)
        }
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 640, pixelsHigh: 400, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGradient(starting: .systemTeal, ending: .systemIndigo)!.draw(in: NSRect(x: 0, y: 0, width: 640, height: 400), angle: 30)
        NSGraphicsContext.restoreGraphicsState()
        let png = rep.representation(using: .png, properties: [:])!

        let samples: [PasteboardSnapshot] = [
            text("Quarterly invoice #4821 — due Friday", app: "Mail"),
            PasteboardSnapshot(items: [[Representation(type: PasteboardType.png, data: png)]], types: [PasteboardType.png],
                               frontmostBundleID: nil, frontmostAppName: "Preview"),
            text("password = hunter2", app: "Terminal"),
            text("https://developer.apple.com/design/human-interface-guidelines", app: "Safari"),
            text("Meeting notes\n- Ship the redesign\n- Run audit two\n- Celebrate", app: "Notes"),
            text("func greet(name: String) -> String {\n    return \"Hello, \\(name)!\"\n}", app: "Xcode"),
        ]
        var t = Date().addingTimeInterval(-3_600)
        for sample in samples {
            t += 300
            await model.ingest(sample, capturedAt: t)
        }
        await model.togglePin(model.results.last!.id) // pin the invoice
        model.resetForPresentation()

        try await render(model: model, settings: settings, appearance: .aqua, to: "\(out)/panel-light.png")
        try await render(model: model, settings: settings, appearance: .darkAqua, to: "\(out)/panel-dark.png")
        model.selectedID = model.results.first { $0.isSensitive }?.id
        try await render(model: model, settings: settings, appearance: .darkAqua, to: "\(out)/panel-sensitive.png")
        model.selectedID = model.results.first { $0.kind == .image }?.id
        try await render(model: model, settings: settings, appearance: .aqua, to: "\(out)/panel-image.png")
        model.query.text = "zzz-nothing"
        try await render(model: model, settings: settings, appearance: .aqua, to: "\(out)/panel-empty.png")
    }

    private func render(model: HistoryModel, settings: SettingsStore, appearance: NSAppearance.Name, to path: String) async throws {
        let actions = PanelActions(choose: { _, _ in }, setPaused: { _ in }, revealInFinder: { _ in }, openPrivacySettings: { _ in })
        let view = PanelView(model: model, settings: settings, focus: PanelFocus(), accessState: .allowed,
                             dataDirectory: URL(fileURLWithPath: "/tmp"), actions: actions)
            .background(Color(nsColor: .windowBackgroundColor))
        let hosting = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: Theme.panelSize), styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = hosting
        hosting.frame = NSRect(origin: .zero, size: Theme.panelSize)
        hosting.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(800)) // let previews and thumbnails load
        hosting.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: path))
    }

    func testRenderSettingsAndOnboarding() async throws {
        guard let out = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] else { throw XCTSkip("SNAPSHOT_DIR not set") }
        let (defaults, suite) = makeTestDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ClipboardSnapshots-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let app = AppController(settings: SettingsStore(defaults: defaults), dataDirectory: dir, keyStore: InMemoryKeyStore())
        let window = SettingsWindow.make(app: app)
        let tabs = try XCTUnwrap(window.contentViewController as? NSTabViewController)
        for (index, item) in tabs.tabViewItems.enumerated() {
            tabs.selectedTabViewItemIndex = index
            try await Task.sleep(for: .milliseconds(300))
            let view = try XCTUnwrap(item.viewController?.view)
            print("SETTINGS \(item.label) fitting size: \(view.fittingSize)")
            try snapshot(view, size: view.fittingSize, to: "\(out)/settings-\(item.label.lowercased()).png")
        }
        let onboarding = NSHostingView(rootView: OnboardingView(app: app) {}.background(Color(nsColor: .windowBackgroundColor)))
        try snapshot(onboarding, size: onboarding.fittingSize, to: "\(out)/onboarding.png")
    }

    private func snapshot(_ view: NSView, size: NSSize, to path: String) throws {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        view.frame = container.bounds
        container.addSubview(view)
        window.contentView = container
        container.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(container.bitmapImageRepForCachingDisplay(in: container.bounds))
        container.cacheDisplay(in: container.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: path))
    }
}
