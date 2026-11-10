import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let panelController = PanelController()
    private var timer: Timer?
    private var passthroughItem: NSMenuItem?
    private var visibilityItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // 托盘菜单
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "gauge", accessibilityDescription: "性能监控")
        statusItem = item

        let menu = NSMenu()
        let vis = NSMenuItem(title: "显示/隐藏悬浮条", action: #selector(toggleVisibility), keyEquivalent: "")
        vis.target = self
        menu.addItem(vis)
        let pass = NSMenuItem(title: "鼠标穿透", action: #selector(togglePassthrough), keyEquivalent: "")
        pass.target = self
        pass.state = .off
        passthroughItem = pass
        menu.addItem(pass)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu

        panelController.panel.makeKeyAndOrderFront(nil)

        // 1 秒采样一次
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            let snap = MetricsCollector.shared.sample()
            self?.panelController.update(snap)
        }
        // 先立刻采一帧，避免首屏空白
        panelController.update(MetricsCollector.shared.sample())
    }

    @objc private func toggleVisibility() {
        panelController.toggleVisibility()
    }

    @objc private func togglePassthrough() {
        let next = !panelController.isPassthrough
        panelController.isPassthrough = next
        passthroughItem?.state = next ? .on : .off
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
