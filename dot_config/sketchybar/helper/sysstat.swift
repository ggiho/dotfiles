import Foundation
import Darwin
import CoreGraphics

// Prints one line for the bar: "<cpu %> <memory used GB> <memory pressure level>"
//   cpu       busy share of ALL cores over a short sample (0-100)
//   memory    like Activity Monitor's "Memory Used": app memory + wired + compressed
//   pressure  macOS memory pressure: 1 normal, 2 warning, 4 critical
// Other modes, for the popups:  --split  --mem  --mouse  (see below)

func cpuTicks() -> [Double]? {
    var info = host_cpu_load_info()
    var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
    let r = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
        }
    }
    guard r == KERN_SUCCESS else { return nil }
    let t = info.cpu_ticks
    return [Double(t.0), Double(t.1), Double(t.2), Double(t.3)]     // user, system, idle, nice
}

// Memory in MB the way Activity Monitor splits it: app memory + wired + compressed = "Memory Used"
func memoryMB() -> (app: Double, wired: Double, compressed: Double)? {
    var vm = vm_statistics64()
    var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
    let r = withUnsafeMutablePointer(to: &vm) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
        }
    }
    guard r == KERN_SUCCESS else { return nil }
    let mb = Double(getpagesize()) / 1_048_576
    let app = Double(UInt64(vm.internal_page_count) - min(UInt64(vm.internal_page_count), UInt64(vm.purgeable_count)))
    return (app * mb, Double(vm.wire_count) * mb, Double(vm.compressor_page_count) * mb)
}

func pressureLevel() -> Int32 {
    var level: Int32 = 1
    var size = MemoryLayout<Int32>.size
    sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0)
    return level
}

// --mem: "<used> <app> <wired> <compressed> <total> <swap used> <pressure>", memory in MB, for the popup
if CommandLine.arguments.contains("--mem") {
    guard let m = memoryMB() else { exit(1) }
    var total: UInt64 = 0
    var tsz = MemoryLayout<UInt64>.size
    sysctlbyname("hw.memsize", &total, &tsz, nil, 0)
    var swap = xsw_usage()
    var ssz = MemoryLayout<xsw_usage>.size
    sysctlbyname("vm.swapusage", &swap, &ssz, nil, 0)
    print(String(format: "%.0f %.0f %.0f %.0f %.0f %.0f %d", m.app + m.wired + m.compressed, m.app, m.wired, m.compressed,
                 Double(total) / 1_048_576, Double(swap.xsu_used) / 1_048_576, pressureLevel()))
    exit(0)
}

// --mouse: which monitor the pointer is on, counted left to right like AeroSpace numbers its monitors
if CommandLine.arguments.contains("--mouse") {
    guard let p = CGEvent(source: nil)?.location else { exit(1) }
    var ids = [CGDirectDisplayID](repeating: 0, count: 16)
    var n: UInt32 = 0
    CGGetActiveDisplayList(16, &ids, &n)
    let ds = ids.prefix(Int(n)).map { ($0, CGDisplayBounds($0)) }
        .sorted { ($0.1.origin.x, $0.1.origin.y) < ($1.1.origin.x, $1.1.origin.y) }
    if let i = ds.firstIndex(where: { $0.1.contains(p) }) { print(i + 1) }
    exit(0)
}

// --split: "<user %> <system %>" over a short sample, for the popup
if CommandLine.arguments.contains("--split") {
    if let a = cpuTicks() {
        usleep(120_000)
        if let b = cpuTicks() {
            let d = zip(b, a).map { $0 - $1 }
            let total = d.reduce(0, +)
            if total > 0 { print(String(format: "%.0f %.0f", (d[0] + d[3]) / total * 100, d[1] / total * 100)) }
        }
    }
    exit(0)
}

// --daemon: stays running and updates the cpu and mem items of the bar itself every few seconds, so
// nothing has to be started for each refresh (no shell, no helper, no sketchybar command).
//   --daemon            start (does nothing if one is already running)
//   --daemon --replace  start, taking over from a running one
//   --daemon --once     measure over a short sample, update once and exit (for testing)
// It talks to SketchyBar over its mach port (the same message the sketchybar command sends).
func sketchybarSend(_ args: [String]) -> kern_return_t {
    // bootstrap_look_up is not exposed to Swift, so find it at run time
    typealias LookUp = @convention(c) (mach_port_t, UnsafePointer<CChar>, UnsafeMutablePointer<mach_port_t>) -> kern_return_t
    guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "bootstrap_look_up") else { return -1 }   // RTLD_DEFAULT
    let lookUp = unsafeBitCast(sym, to: LookUp.self)
    var bootstrap: mach_port_t = 0
    guard task_get_special_port(mach_task_self_, TASK_BOOTSTRAP_PORT, &bootstrap) == KERN_SUCCESS else { return -2 }
    var port: mach_port_t = 0
    guard lookUp(bootstrap, "git.felix.sketchybar", &port) == KERN_SUCCESS, port != 0 else { return -3 }
    defer { mach_port_deallocate(mach_task_self_, port) }
    var payload = [UInt8]()
    for a in args { payload += Array(a.utf8); payload.append(0) }
    payload.append(0)
    let msg = UnsafeMutableRawPointer.allocate(byteCount: 44, alignment: 8)
    defer { msg.deallocate() }
    memset(msg, 0, 44)
    var result: kern_return_t = -4
    payload.withUnsafeMutableBytes { buf in
        // mach_msg_header_t (24 bytes), the descriptor count, then one out-of-line descriptor:
        // address (8), flags (deallocate, copy, pad, type: 1 byte each), size (4)
        let bits = UInt32(MACH_MSG_TYPE_COPY_SEND) | (UInt32(MACH_MSG_TYPE_MAKE_SEND) << 8) | 0x8000_0000
        msg.storeBytes(of: bits, toByteOffset: 0, as: UInt32.self)
        msg.storeBytes(of: 44, toByteOffset: 4, as: UInt32.self)                 // msgh_size
        msg.storeBytes(of: port, toByteOffset: 8, as: UInt32.self)               // remote port
        msg.storeBytes(of: 1, toByteOffset: 24, as: UInt32.self)                 // descriptor count
        msg.storeBytes(of: UInt(bitPattern: buf.baseAddress), toByteOffset: 28, as: UInt.self)   // address
        msg.storeBytes(of: UInt8(0), toByteOffset: 36, as: UInt8.self)           // deallocate
        msg.storeBytes(of: UInt8(MACH_MSG_VIRTUAL_COPY), toByteOffset: 37, as: UInt8.self)
        msg.storeBytes(of: UInt8(MACH_MSG_OOL_DESCRIPTOR), toByteOffset: 39, as: UInt8.self)
        msg.storeBytes(of: UInt32(buf.count), toByteOffset: 40, as: UInt32.self) // size
        let hdr = msg.assumingMemoryBound(to: mach_msg_header_t.self)
        // no reply port, like the helper example of SketchyBar: the update is fire and forget
        result = mach_msg(hdr, MACH_SEND_MSG, 44, 0, mach_port_t(MACH_PORT_NULL), MACH_MSG_TIMEOUT_NONE, mach_port_t(MACH_PORT_NULL))
    }
    return result
}

func loadColors(_ path: String) -> [String: String] {
    var out = [String: String]()
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return out }
    for line in text.split(separator: "\n") where line.hasPrefix("export ") {
        let kv = line.dropFirst(7).split(separator: "=", maxSplits: 1).map(String.init)
        if kv.count == 2 && kv[1].hasPrefix("0x") { out[kv[0]] = kv[1] }
    }
    return out
}

if CommandLine.arguments.contains("--daemon") {
    let args = CommandLine.arguments
    let configDir = ProcessInfo.processInfo.environment["CONFIG_DIR"] ?? NSHomeDirectory() + "/.config/sketchybar"
    let colors = loadColors(configDir + "/colors.sh")
    func color(_ name: String) -> String { colors[name] ?? "0xffffffff" }

    if !args.contains("--once") {
        // one instance: whoever holds the lock on the pid file is the daemon
        let fd = open("/tmp/sysstat.\(getuid()).pid", O_RDWR | O_CREAT, 0o644)
        let deadline = Date().addingTimeInterval(3)
        var asked: Int32 = 0
        while flock(fd, LOCK_EX | LOCK_NB) != 0 {
            if !args.contains("--replace") || Date() > deadline { exit(0) }
            var buf = [UInt8](repeating: 0, count: 32)
            let n = pread(fd, &buf, 31, 0)
            if n > 0, let pid = Int32(String(decoding: buf[0..<n], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)),
               pid != asked, pid != getpid() { kill(pid, SIGTERM); asked = pid }
            usleep(50_000)
        }
        ftruncate(fd, 0)
        let me = "\(getpid())"
        _ = me.withCString { pwrite(fd, $0, strlen($0), 0) }
        // the lock is kept for as long as this process lives
    }

    let interval: useconds_t = 5_000_000
    var prev = cpuTicks()
    var prevAt = Date()
    usleep(args.contains("--once") ? 300_000 : 400_000)
    while true {
        guard let now = cpuTicks(), let before = prev else { prev = cpuTicks(); usleep(interval); continue }
        let d = zip(now, before).map { $0 - $1 }
        let total = d.reduce(0, +)
        let cpu = total > 0 ? (d[0] + d[1] + d[3]) / total * 100 : 0
        let used = memoryMB().map { ($0.app + $0.wired + $0.compressed) / 1024 } ?? 0
        let cpuColor = cpu >= 85 ? color("RED") : (cpu >= 60 ? color("YELLOW") : color("WHITE"))
        let memColor = pressureLevel() >= 4 ? color("RED") : (pressureLevel() >= 2 ? color("YELLOW") : color("GREEN"))
        let sent = sketchybarSend(["--set", "cpu", "icon.color=" + cpuColor, String(format: "label=%.0f%%", cpu), "label.color=" + cpuColor,
                            "--set", "mem", "icon.color=" + memColor, String(format: "label=%.1fG", used)])
        if args.contains("--once") { print(String(format: "%.0f %.1f", cpu, used), "send result:", sent); exit(0) }
        prev = now
        prevAt = Date()
        usleep(interval)
        // after a sleep (lid closed) the first interval would average over hours: measure a fresh short one
        if Date().timeIntervalSince(prevAt) > 15 { prev = cpuTicks(); usleep(400_000) }
    }
}

var cpu = 0.0
if let a = cpuTicks() {
    usleep(300_000)
    if let b = cpuTicks() {
        let d = zip(b, a).map { $0 - $1 }
        let total = d.reduce(0, +)
        if total > 0 { cpu = (d[0] + d[1] + d[3]) / total * 100 }
    }
}

var usedGB = 0.0
if let m = memoryMB() { usedGB = (m.app + m.wired + m.compressed) / 1024 }

print(String(format: "%.0f %.1f %d", cpu, usedGB, pressureLevel()))
