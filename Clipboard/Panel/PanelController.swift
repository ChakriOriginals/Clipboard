import AppKit
import os
import SwiftUI

/// Shows, positions, and drives the history panel; routes keyboard commands to the model.
@MainActor
final class PanelController {
    private unowned let app: AppController
    private let panel = ClipboardPanel(contentRect: NSRect(origin: .zero, size: Theme.panelSize))
    private let hostingView: NSHostingView<PanelView>
    private let focus = PanelFocus()
    private var keyMonitor: Any?
    private var mouseMonitor: Any?
    private let signposter = OSSignposter(subsystem: "dev.clipflow.ClipFlow", category: "panel")
    private let log = Logger(subsystem: "dev.clipflow.ClipFlow", category: "panel")

    init(app: AppController) {
        self.app = app
        hostingView = NSHostingView(rootView: Self.makeView(app: app, focus: focus, accessState: .allowed))
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = Self.makeSurface(containing: hostingView)
        panel.onResignKey = { [weak self] in self?.hide() }
    }

    /// Liquid Glass on macOS 26+, the popover material before. Both turn opaque with Reduce Transparency
    /// and gain contrast with Increase Contrast on their own. Glass sits only on this floating layer.
    private static func makeSurface(containing content: NSView) -> NSView {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = Theme.panelRadius
            glass.contentView = content
            return glass
        }
        let material = NSVisualEffectView()
        material.material = .popover
        material.blendingMode = .behindWindow
        material.state = .active
        material.wantsLayer = true
        material.layer?.cornerRadius = Theme.panelRadius
        material.layer?.cornerCurve = .continuous
        material.layer?.masksToBounds = true
        material.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: material.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: material.trailingAnchor),
            content.topAnchor.constraint(equalTo: material.topAnchor),
            content.bottomAnchor.constraint(equalTo: material.bottomAnchor),
        ])
        return material
    }

    private static func makeView(app: AppController, focus: PanelFocus, accessState: PasteAccessState) -> PanelView {
        PanelView(model: app.model, settings: app.settings, focus: focus, accessState: accessState,
                  dataDirectory: app.dataDirectory, actions: app.panelActions)
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
        focus.pointerActive = false
        hostingView.rootView = Self.makeView(app: app, focus: focus, accessState: app.accessState)
        position()
        // A short fade, not a slide: the panel appears where the user is looking.
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
        focus.requestFocus()
        installMonitors()
        DispatchQueue.main.async { [signposter, log] in
            signposter.endInterval("PanelOpen", interval)
            let ms = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1e6
            log.info("Panel open took \(ms, format: .fixed(precision: 1), privacy: .public) ms")
        }
    }

    func hide() {
        guard panel.isVisible else { return }
        removeMonitors()
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

    // MARK: Input

    private func installMonitors() {
        removeMonitors()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel,
                  let command = KeyRouter.command(keyCode: event.keyCode, modifiers: event.modifierFlags,
                                                  charactersIgnoringModifiers: event.charactersIgnoringModifiers)
            else { return event }
            self.focus.pointerActive = false
            self.perform(command)
            return nil
        }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            if let self, event.window === self.panel { self.focus.pointerActive = true }
            return event
        }
    }

    private func removeMonitors() {
        for monitor in [keyMonitor, mouseMonitor].compactMap({ $0 }) { NSEvent.removeMonitor(monitor) }
        keyMonitor = nil
        mouseMonitor = nil
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

/// Focus and pointer state shared between the controller and the SwiftUI panel.
@MainActor
@Observable
final class PanelFocus {
    private(set) var token = 0
    /// True once the mouse moves inside the panel; keyboard navigation turns it off.
    var pointerActive = false
    func requestFocus() { token &+= 1 }
}
