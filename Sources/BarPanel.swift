import AppKit

// MARK: - 悬浮面板

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 420, height: 64),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        hasShadow = true
        acceptsMouseMovedEvents = true
    }
}

// MARK: - 模块视图（标题+数值+趋势线）

final class ModuleView: NSView {
    let titleLabel: NSTextField
    let valueLabel: NSTextField
    let sparkline: SparklineView
    let detailLabel: NSTextField

    init(title: String, color: NSColor, fixedScale: Double?) {
        titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        titleLabel.textColor = .labelColor

        valueLabel = NSTextField(labelWithString: "--")
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right

        sparkline = SparklineView()
        sparkline.lineColor = color
        sparkline.fillColor = color
        sparkline.fixedScale = fixedScale

        detailLabel = NSTextField(labelWithString: "")
        detailLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.maximumNumberOfLines = 2
        detailLabel.lineBreakMode = .byWordWrapping

        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let header = NSStackView(views: [titleLabel, valueLabel])
        header.translatesAutoresizingMaskIntoConstraints = false
        header.orientation = .horizontal
        header.distribution = .fill
        header.alignment = .firstBaseline

        header.translatesAutoresizingMaskIntoConstraints = false
        sparkline.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(header)
        addSubview(sparkline)
        addSubview(detailLabel)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor),
            header.leadingAnchor.constraint(equalTo: leadingAnchor),
            header.trailingAnchor.constraint(equalTo: trailingAnchor),

            sparkline.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 5),
            sparkline.leadingAnchor.constraint(equalTo: leadingAnchor),
            sparkline.trailingAnchor.constraint(equalTo: trailingAnchor),
            sparkline.heightAnchor.constraint(equalToConstant: 26),
            sparkline.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),

            detailLabel.topAnchor.constraint(equalTo: sparkline.bottomAnchor, constant: 6),
            detailLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        detailLabel.isHidden = true
    }

    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - 主内容视图

final class BarContentView: NSView {
    private(set) var expanded = false

    private let effectView = NSVisualEffectView()
    private let modulesStack = NSStackView()
    private var modules: [ModuleView] = []
    private var contentWidth: NSLayoutConstraint!
    private var topPadding: NSLayoutConstraint!

    private let historyLimit = 60
    private var cpuHistory: [Double] = []
    private var memHistory: [Double] = []
    private var diskHistory: [Double] = []
    private var netHistory: [Double] = []

    var onToggleExpand: ((Bool) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false

        effectView.material = .hudWindow
        effectView.state = .active
        effectView.blendingMode = .behindWindow
        effectView.appearance = NSAppearance(named: .vibrantDark)
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 14
        effectView.layer?.masksToBounds = true
        effectView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(effectView)

        modulesStack.translatesAutoresizingMaskIntoConstraints = false
        modulesStack.orientation = .horizontal
        modulesStack.distribution = .fillEqually
        modulesStack.spacing = 14
        effectView.addSubview(modulesStack)

        let specs: [(String, NSColor, Double?)] = [
            ("CPU", .systemGreen, 1.0),
            ("内存", .systemBlue, 1.0),
            ("磁盘", .systemOrange, nil),
            ("网络", .systemPurple, nil),
        ]
        for spec in specs {
            let m = ModuleView(title: spec.0, color: spec.1, fixedScale: spec.2)
            modules.append(m)
            modulesStack.addArrangedSubview(m)
        }

        contentWidth = modulesStack.widthAnchor.constraint(equalToConstant: 392)
        contentWidth.isActive = true

        topPadding = modulesStack.topAnchor.constraint(equalTo: effectView.topAnchor, constant: 10)

        NSLayoutConstraint.activate([
            effectView.topAnchor.constraint(equalTo: topAnchor),
            effectView.bottomAnchor.constraint(equalTo: bottomAnchor),
            effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: trailingAnchor),

            modulesStack.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 16),
            topPadding,
        ])

        // 单击切换展开/收起
        let click = NSClickGestureRecognizer(target: self, action: #selector(handleClick(_:)))
        addGestureRecognizer(click)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func handleClick(_ g: NSClickGestureRecognizer) {
        setExpanded(!expanded)
    }

    func setExpanded(_ e: Bool) {
        guard e != expanded else { return }
        expanded = e
        for m in modules { m.detailLabel.isHidden = !e }
        onToggleExpand?(e)
    }

    func update(_ snap: MetricSnapshot) {
        cpuHistory.append(snap.cpu)
        memHistory.append(snap.memory)
        diskHistory.append(Double(snap.diskRead + snap.diskWrite))
        netHistory.append(Double(snap.netDown + snap.netUp))
        while cpuHistory.count > historyLimit { cpuHistory.removeFirst() }
        while memHistory.count > historyLimit { memHistory.removeFirst() }
        while diskHistory.count > historyLimit { diskHistory.removeFirst() }
        while netHistory.count > historyLimit { netHistory.removeFirst() }

        modules[0].valueLabel.stringValue = String(format: "%.0f%%", snap.cpu * 100)
        modules[0].sparkline.samples = cpuHistory

        modules[1].valueLabel.stringValue = String(format: "%.0f%%", snap.memory * 100)
        modules[1].sparkline.samples = memHistory

        modules[2].valueLabel.stringValue = "↓\(fmtBytesPerSec(snap.diskRead)) ↑\(fmtBytesPerSec(snap.diskWrite))"
        modules[2].sparkline.samples = diskHistory

        modules[3].valueLabel.stringValue = "↓\(fmtBytesPerSec(snap.netDown)) ↑\(fmtBytesPerSec(snap.netUp))"
        modules[3].sparkline.samples = netHistory

        if expanded {
            let memGB = Double(snap.memUsed) / 1024 / 1024 / 1024
            let totalGB = Double(snap.memTotal) / 1024 / 1024 / 1024
            modules[0].detailLabel.stringValue = String(format: "使用率 %.1f%%", snap.cpu * 100)
            modules[1].detailLabel.stringValue = String(format: "已用 %.1fG / %.0fG", memGB, totalGB)
            modules[2].detailLabel.stringValue = String(format: "读 %@/s\n写 %@/s", fmtBytesPerSec(snap.diskRead), fmtBytesPerSec(snap.diskWrite))
            modules[3].detailLabel.stringValue = String(format: "下行 %@/s\n上行 %@/s\n%@", fmtBytesPerSec(snap.netDown), fmtBytesPerSec(snap.netUp), snap.interfaces.joined(separator: " "))
        }
    }
}

// MARK: - 面板控制器（含位置记忆 / 展开收起动画）

final class PanelController {
    let panel = FloatingPanel()
    private let contentView = BarContentView()
    private static let frameKey = "perfbar.lastFrame"

    init() {
        let content = contentView
        panel.contentView = content
        content.onToggleExpand = { [weak self] expanded in
            self?.resize(expanded: expanded)
        }
        restoreFrame()
        // 记录拖动后的位置
        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification,
                                               object: panel, queue: .main) { [weak self] _ in
            self?.saveFrame()
        }
    }

    func update(_ snap: MetricSnapshot) {
        contentView.update(snap)
    }

    var isPassthrough: Bool {
        get { panel.ignoresMouseEvents }
        set { panel.ignoresMouseEvents = newValue }
    }

    func toggleVisibility() {
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            restoreFrame()
            panel.makeKeyAndOrderFront(nil)
        }
    }

    private func resize(expanded: Bool) {
        guard let frame = panel.frame as NSRect? else { return }
        let delta = CGFloat(expanded ? 52 : -52)
        var newFrame = frame
        newFrame.origin.y -= delta   // 保持顶边不动
        newFrame.size.height += delta
        panel.setFrame(newFrame, display: true, animate: true)
        saveFrame()
    }

    private func restoreFrame() {
        let defaults = UserDefaults.standard
        if let s = defaults.string(forKey: Self.frameKey) {
            let parts = s.split(separator: ",").compactMap { Double($0) }
            if parts.count == 4 {
                panel.setFrame(NSRect(x: parts[0], y: parts[1],
                                      width: parts[2], height: parts[3]), display: true)
                return
            }
        }
        // 首次启动：主屏顶部居中
        if let screen = NSScreen.main {
            let vf = screen.visibleFrame
            let w: CGFloat = 420, h: CGFloat = 64
            panel.setFrame(NSRect(x: vf.midX - w / 2, y: vf.maxY - h - 4,
                                  width: w, height: h), display: true)
        }
    }

    private func saveFrame() {
        let f = panel.frame
        UserDefaults.standard.set("\(f.origin.x),\(f.origin.y),\(f.size.width),\(f.size.height)",
                                  forKey: Self.frameKey)
    }
}
