import Foundation
import Darwin
import IOKit

struct MetricSnapshot {
    var cpu: Double = 0          // 0-1
    var memory: Double = 0       // 0-1
    var memUsed: UInt64 = 0      // bytes
    var memTotal: UInt64 = 0     // bytes
    var diskRead: UInt64 = 0     // B/s
    var diskWrite: UInt64 = 0    // B/s
    var netDown: UInt64 = 0      // B/s
    var netUp: UInt64 = 0        // B/s
    var interfaces: [String] = []
}

/// 系统指标采集：CPU / 内存 / 磁盘 / 网络
final class MetricsCollector {
    static let shared = MetricsCollector()

    private var prevCpuBusy: Double = 0
    private var prevCpuTotal: Double = 0
    private var prevDiskRead: UInt64? = nil
    private var prevDiskWrite: UInt64? = nil
    private var prevNetIn: UInt64? = nil
    private var prevNetOut: UInt64? = nil
    private var prevTimestamp: Double? = nil

    func sample() -> MetricSnapshot {
        var snap = MetricSnapshot()
        let now = CFAbsoluteTimeGetCurrent()
        let dt = prevTimestamp.map { max(0.5, now - $0) } ?? 1.0
        prevTimestamp = now

        // CPU
        if let (busy, total) = cpuTicks() {
            let dBusy = busy - prevCpuBusy
            let dTotal = total - prevCpuTotal
            if prevCpuTotal > 0 && dTotal > 0 {
                snap.cpu = min(1, max(0, dBusy / dTotal))
            }
            prevCpuBusy = busy
            prevCpuTotal = total
        }

        // Memory
        if let (used, total) = memoryInfo() {
            snap.memUsed = used
            snap.memTotal = total
            snap.memory = Double(used) / Double(max(1, total))
        }

        // Disk
        if let (r, w) = diskIOBytes() {
            if let pr = prevDiskRead, let pw = prevDiskWrite {
                snap.diskRead = r > pr ? UInt64(Double(r - pr) / dt) : 0
                snap.diskWrite = w > pw ? UInt64(Double(w - pw) / dt) : 0
            }
            prevDiskRead = r
            prevDiskWrite = w
        }

        // Network
        if let (inB, outB, names) = netBytes() {
            snap.interfaces = names
            if let pi = prevNetIn, let po = prevNetOut {
                snap.netDown = inB > pi ? UInt64(Double(inB - pi) / dt) : 0
                snap.netUp = outB > po ? UInt64(Double(outB - po) / dt) : 0
            }
            prevNetIn = inB
            prevNetOut = outB
        }

        return snap
    }

    // MARK: - CPU (mach host_processor_info)

    private func cpuTicks() -> (busy: Double, total: Double)? {
        var procCount: mach_msg_type_number_t = 0
        var cpuInfo: processor_info_array_t? = nil
        var cpuInfoCount: mach_msg_type_number_t = 0
        let host = mach_host_self()
        let kr = host_processor_info(host, PROCESSOR_CPU_LOAD_INFO,
                                     &procCount, &cpuInfo, &cpuInfoCount)
        guard kr == KERN_SUCCESS, let info = cpuInfo else { return nil }
        defer {
            let size = vm_size_t(MemoryLayout<integer_t>.stride) * vm_size_t(cpuInfoCount)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), size)
        }
        var busy = 0.0, total = 0.0
        for i in 0..<Int(cpuInfoCount) {
            let base = i * Int(CPU_STATE_MAX)
            let user = Double(info[base + Int(CPU_STATE_USER)])
            let sys  = Double(info[base + Int(CPU_STATE_SYSTEM)])
            let nice = Double(info[base + Int(CPU_STATE_NICE)])
            let idle = Double(info[base + Int(CPU_STATE_IDLE)])
            busy += user + sys + nice
            total += user + sys + nice + idle
        }
        return (busy, total)
    }

    // MARK: - Memory (host_statistics64)

    private func memoryInfo() -> (used: UInt64, total: UInt64)? {
        let total = ProcessInfo.processInfo.physicalMemory
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let host = mach_host_self()
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        let pageSize: UInt64 = 4096
        let used = (UInt64(stats.wire_count)
                    + UInt64(stats.active_count)
                    + UInt64(stats.compressor_page_count)) * pageSize
        return (used, total)
    }

    // MARK: - Disk (IOKit IOBlockStorageDriver)

    private func diskIOBytes() -> (read: UInt64, write: UInt64)? {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("IOBlockStorageDriver"),
                                           &iter) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iter) }
        var r: UInt64 = 0, w: UInt64 = 0
        while true {
            let service = IOIteratorNext(iter)
            if service == 0 { break }
            defer { IOObjectRelease(service) }
            var propsRef: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &propsRef,
                                                     kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let props = propsRef?.takeRetainedValue() as? [String: Any],
                  let stats = props["Statistics"] as? [String: Any] else { continue }
            r += (stats["Bytes (Read)"] as? UInt64) ?? 0
            w += (stats["Bytes (Write)"] as? UInt64) ?? 0
        }
        return (r, w)
    }

    // MARK: - Network (getifaddrs)

    private func netBytes() -> (inB: UInt64, outB: UInt64, names: [String])? {
        var addrsPtr: UnsafeMutablePointer<ifaddrs>? = nil
        guard getifaddrs(&addrsPtr) == 0, let first = addrsPtr else { return nil }
        defer { freeifaddrs(first) }

        var inB: UInt64 = 0, outB: UInt64 = 0
        var names: [String] = []
        var seen = Set<String>()
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let p = ptr {
            let name = String(validatingUTF8: p.pointee.ifa_name) ?? ""
            let sa = p.pointee.ifa_addr?.pointee.sa_family
            if sa == UInt8(AF_LINK) && !name.isEmpty && !seen.contains(name) {
                if !isExcludedInterface(name) {
                    seen.insert(name)
                    if let data = p.pointee.ifa_data {
                        let d = data.assumingMemoryBound(to: if_data.self)
                        inB += UInt64(d.pointee.ifi_ibytes)
                        outB += UInt64(d.pointee.ifi_obytes)
                    }
                    names.append(name)
                }
            }
            ptr = p.pointee.ifa_next
        }
        return (inB, outB, names)
    }

    private func isExcludedInterface(_ name: String) -> Bool {
        let prefixes = ["lo", "utun", "awdl", "llw", "bridge", "ap1", "p2p", "gif", "stf", "vmenet"]
        return prefixes.contains { name.hasPrefix($0) }
    }
}

// MARK: - 格式化工具

func fmtBytesPerSec(_ b: UInt64) -> String {
    let v = Double(b)
    if v < 1024 { return String(format: "%.0fB", v) }
    if v < 1024 * 1024 { return String(format: "%.1fK", v / 1024) }
    if v < 1024 * 1024 * 1024 { return String(format: "%.1fM", v / 1024 / 1024) }
    return String(format: "%.2fG", v / 1024 / 1024 / 1024)
}

func fmtBytes(_ b: UInt64) -> String {
    let v = Double(b)
    if v < 1024 { return String(format: "%.0fB", v) }
    if v < 1024 * 1024 { return String(format: "%.1fK", v / 1024) }
    if v < 1024 * 1024 * 1024 { return String(format: "%.2fG", v / 1024 / 1024) }
    return String(format: "%.1fT", v / 1024 / 1024 / 1024 / 1024)
}
