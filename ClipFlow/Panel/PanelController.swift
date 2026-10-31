import AppKit
import os
import SwiftUI

/// Shows, positions, and drives the history panel; routes keyboard commands to the model.
@MainActor
final class PanelController {
    private unowned let app: AppController
    private let panel = ClipboardPanel(contentRect: NSRect(x: 0, y: 0, width: 600, height: 440))
    private let hostingView: NSHostingView<PanelView>
    private let focus = PanelFocus()
    private var keyMonitor: Any?
    private let signposter = OSSignposter(subsystem: "dev.clipflow.ClipFlow", category: "panel")
    private let log = Logger(subsystem: "dev.clipflow.ClipFlow", category: "panel")

    init(app: AppController) {
        self.app = app
        hostingView = NSHostingView(rootView: PanelView(app: app, focus: focus, accessState: .allowed))
        let background = NSVisualEffectView()
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        background.layer?.masksToBounds = true
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: background.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
        panel.contentView = background
        panel.onResignKey = { [weak self] in self?.hide() }
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        let interval = signposter.beginInterval("PanelOpen")
        let start = DispatchTime.now()
        app.pasteTargetPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        app.model.resetForPresentation()
        hostingView.rootView = PanelView(app: app, focus: focus, accessState: app.accessState)
        position()
        panel.makeKeyAndOrderFront(nil)
        focus.requestFocus()
        installKeyMonitor()
        DispatchQueue.main.async { [signposter, log] in
            signposter.endInterval("PanelOpen", interval)
            let ms = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1e6
            log.info("Panel open took \(ms, format: .fixed(precision: 1), privacy: .public) ms")
        }
    }

    func hide() {
        guard panel.isVisible else { return }
        removeKeyMonitor()
        panel.orderOut(nil)
    }

    private func position() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = panel.frame.size
        var origin: NSPoint
        switch app.settings.panelPosition {
        case .center:
            origin = NSPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2 + visible.height * 0.08)
        case .nearMouse:
            origin = NSPoint(x: mouse.x - size.width / 2, y: mouse.y - size.height - 8)
        }
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        panel.setFrameOrigin(origin)
    }

    // MARK: Keyboard

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel,
                  let command = KeyRouter.command(keyCode: event.keyCode, modifiers: event.modifierFlags,
                                                  charactersIgnoringModifiers: event.charactersIgnoringModifiers)
            else { return event }
            self.perform(command)
            return nil
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    func perform(_ command: PanelCommand) {
        let model = app.model
        let selected = model.selectedID
        switch command {
        case .moveUp: model.moveSelection(-1)
        case .moveDown: model.moveSelection(1)
        case .select: if let selected { app.choose(selected, paste: app.settings.pasteOnSelect) }
        case .copyOnly: if let selected { app.choose(selected, paste: false) }
        case .selectIndex(let index):
            guard index < model.results.count else { return }
            app.choose(model.results[index].id, paste: app.settings.pasteOnSelect)
        case .togglePin: if let selected { Task { await model.togglePin(selected) } }
        case .delete: if let selected { Task { await model.delete(selected) } }
        case .close: hide()
        }
    }
}

/// Lets the controller ask SwiftUI to focus the search field each time the panel opens.
@MainActor
@Observable
final class PanelFocus {
    private(set) var token = 0
    func requestFocus() { token &+= 1 }
}
