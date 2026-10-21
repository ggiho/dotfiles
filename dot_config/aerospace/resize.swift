import CoreGraphics
import Foundation

// resize <h|j|k|l>   (bound to alt-shift-hjkl in aerospace.toml)
//
// The key says which way the edge of the window moves, the way a divider is pushed:
//   l  pushes the right edge right: the window grows if it has a neighbour on its right,
//      and shrinks if its only neighbour is on its left (then it is the right-hand window).
//   h  the same to the left, j down, k up.
// A static AeroSpace binding cannot know where the neighbours are, so this looks at the windows first.
//
// Holding the key keeps resizing: AeroSpace ignores the repeated key events of a held key, so this
// reads the state of the key itself and repeats until it is let go.
//
// RESIZE_DRY=1 only prints what would be done.

let aerospace = "/opt/homebrew/bin/aerospace"
let firstStep = 50, repeatStep = 15
let firstDelay: useconds_t = 250_000, repeatEvery: useconds_t = 55_000, maxRepeats = 100

func start(_ args: [String], capture: Bool) -> (Process, Pipe?)? {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: aerospace)
    p.arguments = args
    let pipe: Pipe? = capture ? Pipe() : nil
    p.standardOutput = pipe ?? FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return nil }
    return (p, pipe)
}

func finish(_ job: (Process, Pipe?)?) -> (status: Int32, out: String) {
    guard let (p, pipe) = job else { return (127, "") }
    let data = pipe?.fileHandleForReading.readDataToEndOfFile() ?? Data()
    p.waitUntilExit()
    return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
}

func run(_ args: [String]) -> (status: Int32, out: String) { finish(start(args, capture: true)) }

func frames() -> [Int: CGRect] {
    var out = [Int: CGRect]()
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    for w in list {
        guard let layer = w[kCGWindowLayer as String] as? Int, layer == 0,
              let id = w[kCGWindowNumber as String] as? Int,
              let b = w[kCGWindowBounds as String] as? NSDictionary,
              let r = CGRect(dictionaryRepresentation: b as CFDictionary) else { continue }
        out[id] = r
    }
    return out
}

let keys: [String: (code: CGKeyCode, axis: String)] = ["h": (4, "width"), "l": (37, "width"), "j": (38, "height"), "k": (40, "height")]
guard CommandLine.arguments.count > 1, let key = keys[CommandLine.arguments[1]] else { exit(2) }
let letter = CommandLine.arguments[1]

// the focused window and the tiled windows of its workspace
let focusedJob = start(["list-windows", "--focused", "--format", "%{window-id}"], capture: true)
let tiledJob = start(["list-windows", "--workspace", "focused", "--format", "%{window-id}|%{window-layout}"], capture: true)
guard let focused = Int(finish(focusedJob).out.trimmingCharacters(in: .whitespacesAndNewlines)) else { exit(1) }
var tiled = [Int]()
for line in finish(tiledJob).out.split(separator: "\n") {
    let p = line.split(separator: "|")
    if p.count == 2, p[1].contains("tiles"), let id = Int(p[0]) { tiled.append(id) }
}
let fr = frames()
guard tiled.contains(focused), let f = fr[focused] else { exit(0) }       // floating, accordion or alone: nothing to resize
let others = tiled.filter { $0 != focused }.compactMap { fr[$0] }

func overlap(_ a0: CGFloat, _ a1: CGFloat, _ b0: CGFloat, _ b1: CGFloat) -> CGFloat { min(a1, b1) - max(a0, b0) }
let tol: CGFloat = 4
let right = others.contains { $0.minX >= f.maxX - tol && overlap(f.minY, f.maxY, $0.minY, $0.maxY) > 10 }
let left  = others.contains { $0.maxX <= f.minX + tol && overlap(f.minY, f.maxY, $0.minY, $0.maxY) > 10 }
let below = others.contains { $0.minY >= f.maxY - tol && overlap(f.minX, f.maxX, $0.minX, $0.maxX) > 10 }
let above = others.contains { $0.maxY <= f.minY + tol && overlap(f.minX, f.maxX, $0.minX, $0.maxX) > 10 }

var sign = 0
switch letter {
case "l": sign = right ? 1 : (left ? -1 : 0)
case "h": sign = left ? 1 : (right ? -1 : 0)
case "j": sign = below ? 1 : (above ? -1 : 0)
default:  sign = above ? 1 : (below ? -1 : 0)             // k
}
if ProcessInfo.processInfo.environment["RESIZE_DRY"] != nil {
    print("key \(letter): neighbours right=\(right) left=\(left) below=\(below) above=\(above) -> \(key.axis) \(sign > 0 ? "+" : (sign < 0 ? "-" : "none"))")
    exit(0)
}
if sign == 0 { exit(0) }

func stepArgs(_ n: Int) -> [String] { ["resize", "--window-id", String(focused), key.axis, (sign > 0 ? "+" : "-") + String(n)] }
guard finish(start(stepArgs(firstStep), capture: false)).status == 0 else { exit(0) }
usleep(firstDelay)
// The repeats are fired without waiting for each one (a call takes ~30 ms, a repeat is due every 55 ms):
// waiting made the held key crawl.
var jobs = [Process]()
var n = 0
while n < maxRepeats && CGEventSource.keyState(.combinedSessionState, key: key.code) {
    if let (p, _) = start(stepArgs(repeatStep), capture: false) { jobs.append(p) }
    n += 1
    usleep(repeatEvery)
}
for p in jobs { p.waitUntilExit() }
