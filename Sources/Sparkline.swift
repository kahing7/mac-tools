import AppKit

/// 迷你趋势曲线（60 秒窗口）
final class SparklineView: NSView {
    var samples: [Double] = [] {
        didSet { needsDisplay = true }
    }
    /// 固定满刻度（如 CPU/内存 0-1），nil 则按窗口内最大值自适应
    var fixedScale: Double? = nil
    var lineColor: NSColor = .systemGreen
    var fillColor: NSColor = .systemGreen

    override func draw(_ dirtyRect: NSRect) {
        guard samples.count > 1 else { return }
        let maxV = max(fixedScale ?? (samples.max() ?? 1), 0.0001)
        let step = bounds.width / CGFloat(samples.count - 1)

        let path = NSBezierPath()
        for (i, v) in samples.enumerated() {
            let x = CGFloat(i) * step
            let ratio = CGFloat(min(1, max(0, v / maxV)))
            let y = bounds.height * ratio * 0.92 + 1
            if i == 0 { path.move(to: NSPoint(x: x, y: y)) }
            else { path.line(to: NSPoint(x: x, y: y)) }
        }
        lineColor.setStroke()
        path.lineWidth = 1.5
        path.lineJoinStyle = .round
        path.stroke()

        let fill = path.copy() as! NSBezierPath
        fill.line(to: NSPoint(x: bounds.width, y: 0))
        fill.line(to: NSPoint(x: 0, y: 0))
        fill.close()
        fillColor.setFill()
        fill.fill()
    }
}
