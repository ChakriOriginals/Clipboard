import AppKit
import SwiftUI

/// The native preferences window: toolbar tabs with icons, title follows the selected tab, and the
/// window resizes to each tab's content.
@MainActor
enum SettingsWindow {
    static let width: CGFloat = 520

    static func make(app: AppController) -> NSWindow {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.transitionOptions = [.crossfade, .allowUserInteraction]
        func add(_ title: String, _ symbol: String, _ view: some View) {
            let controller = NSHostingController(rootView: view.frame(width: width).fixedSize(horizontal: false, vertical: true))
            controller.sizingOptions = .preferredContentSize
            controller.title = title
            let item = NSTabViewItem(viewController: controller)
            item.label = title
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            tabs.addTabViewItem(item)
        }
        add("General", "gearshape", GeneralTab(app: app))
        add("Shortcuts", "keyboard", ShortcutsTab(app: app))
        add("History", "clock.arrow.circlepath", HistoryTab(app: app))
        add("Privacy", "hand.raised", PrivacyTab(app: app))
        add("Appearance", "paintbrush", AppearanceTab(app: app))
        add("Sync", "arrow.triangle.2.circlepath", SyncTab())
        add("About", "info.circle", AboutTab(app: app))

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}
